"""把中文 TTS 参考音分析成 BUZZER_VOICE_SMOKE 的 LPC-10 参数帧表。

流程：SAPI 参考 WAV ->（预加重）-> 30ms/10ms 分帧、汉明窗 -> 自相关 -> Levinson-Durbin
得到 k1..k10 与残差能量 -> 残差自相关定基音与清浊混合比 -> 8 位量化 -> 生成 C 参数表，
同时用 voice_model.py 的定点模型重合成一遍，产出可试听的 WAV 作为“固件实际发声”的预测。

    python make_voice_params.py --config voice.json --ref-dir build/voice_ref --out-c ...
"""

from __future__ import annotations

import argparse
import json
import math
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import voice_model as vm  # noqa: E402

LPC_ORDER = vm.ORDER
FRAME_MS = 30.0
HOP_MS = 10.0
PREEMPHASIS = 0.94
MIN_F0_HZ = 60.0
MAX_F0_HZ = 400.0
VOICED_STRONG = 0.45
VOICED_WEAK = 0.25
# 基音检测前先低通到 F0 所在频带：预加重（0.94）把声门脉冲能量摊开，
# 直接在预加重残差上求自相关会把大量浊音帧误判成噪声。
PITCH_LOWPASS_HZ = 900.0
PEAK_PREFERENCE = 0.85
SILENCE_RMS = 8.0
# 参考音归一化峰值：留 0.93 满量程，避免 TTS 输出本身贴顶。
NORMALIZE_PEAK = 0.93
# 合成输出峰值目标（0.85 满量程）；校准量直接吸收进增益满量程。
TARGET_PEAK = 27853.0
# 增益满量程上限：voiceGainTable 是 uint16。
GAIN_SCALE_LIMIT = 65535
# 帧表尾部补的淡出帧数（每帧 10ms），随后是 1 帧终止帧。
FADE_FRAMES = 2


# --------------------------------------------------------------------------- WAV

def read_wav(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as handle:
        channels = handle.getnchannels()
        width = handle.getsampwidth()
        rate = handle.getframerate()
        frames = handle.getnframes()
        raw = handle.readframes(frames)
    if width != 2:
        raise SystemExit(f"{path}: 只支持 16bit PCM，实际 {width * 8}bit")
    data = np.frombuffer(raw, dtype="<i2").astype(np.float64)
    if channels > 1:
        data = data.reshape(-1, channels).mean(axis=1)
    return data, rate


def write_wav(path: Path, samples: np.ndarray, rate: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(np.round(samples), -32768, 32767).astype("<i2")
    with wave.open(str(path), "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(int(rate))
        handle.writeframes(clipped.tobytes())


# ------------------------------------------------------------------------- LPC 分析

def levinson(autocorrelation: np.ndarray, order: int) -> tuple[np.ndarray, np.ndarray, float]:
    """返回 (kappa[1..order], a[1..order], 残差能量)。

    kappa 就是格型合成器用的反射系数：A_i(z) = A_{i-1}(z) - kappa_i z^-i A_{i-1}(z^-1)。
    """
    a = np.zeros(order + 1)
    kappa = np.zeros(order + 1)
    energy = float(autocorrelation[0])
    if energy <= 0.0:
        return kappa, a, 0.0
    for i in range(1, order + 1):
        acc = float(autocorrelation[i])
        for j in range(1, i):
            acc += a[j] * float(autocorrelation[i - j])
        value = acc / energy
        # 数值保护：量化前的反射系数必须落在 (-1, 1)，否则格型不稳定。
        value = max(min(value, 0.999), -0.999)
        previous = a.copy()
        a[i] = -value
        for j in range(1, i):
            a[j] = previous[j] - value * previous[i - j]
        kappa[i] = value
        energy *= 1.0 - value * value
        if energy <= 0.0:
            energy = 0.0
            break
    return kappa, a, energy


def autocorrelation(signal: np.ndarray, order: int) -> np.ndarray:
    # 有偏自相关：r[k] = sum(x[n]x[n-k]) / N，与 Levinson 的 E_0 = r[0] 约定一致。
    length = signal.size
    result = np.zeros(order + 1)
    for lag in range(order + 1):
        result[lag] = float(np.dot(signal[:length - lag], signal[lag:])) / length
    return result


def inverse_filter(windowed: np.ndarray, a: np.ndarray) -> np.ndarray:
    residual = windowed.copy()
    for i in range(1, LPC_ORDER + 1):
        if a[i] != 0.0:
            residual[i:] += a[i] * windowed[:-i]
    return residual


def lowpass(signal: np.ndarray, rate: int, cutoff: float) -> np.ndarray:
    """RBJ 二阶低通（Q=0.707），只用于基音检测。"""
    omega = 2.0 * math.pi * cutoff / rate
    alpha = math.sin(omega) / (2.0 * 0.7071)
    a0 = 1.0 + alpha
    b0 = (1.0 - math.cos(omega)) / 2.0 / a0
    b1 = (1.0 - math.cos(omega)) / a0
    b2 = b0
    a1 = -2.0 * math.cos(omega) / a0
    a2 = (1.0 - alpha) / a0
    out = np.zeros_like(signal)
    x1 = x2 = y1 = y2 = 0.0
    for index, value in enumerate(signal):
        current = b0 * value + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1 = x1, value
        y2, y1 = y1, current
        out[index] = current
    return out


def estimate_pitch(signal: np.ndarray, rate: int) -> tuple[int, float]:
    """归一化自相关定基音，返回 (周期样本数 0=无声, 周期性 0..1)。"""
    low = lowpass(signal, rate, PITCH_LOWPASS_HZ)
    # 去掉均值：直流分量会把归一化相关整体抬高。
    low = low - float(np.mean(low))
    length = low.size
    energy = float(np.dot(low, low)) / length
    if energy <= 1e-9:
        return 0, 0.0
    min_lag = max(2, int(rate / MAX_F0_HZ))
    max_lag = min(length - 1, int(rate / MIN_F0_HZ))
    if max_lag <= min_lag:
        return 0, 0.0
    correlations = np.zeros(max_lag + 1)
    for lag in range(min_lag, max_lag + 1):
        correlations[lag] = float(np.dot(low[:length - lag], low[lag:])) / length
    correlations /= energy
    peak_lag = int(np.argmax(correlations[min_lag:max_lag + 1]) + min_lag)
    peak = float(correlations[peak_lag])
    if peak <= VOICED_WEAK:
        return 0, 0.0
    # 高基音容易被误判成两倍周期：优先取最短的、相关度接近峰值的周期。
    for lag in range(min_lag, peak_lag):
        if correlations[lag] >= PEAK_PREFERENCE * peak:
            peak_lag = lag
            peak = float(correlations[lag])
            break
    return peak_lag, peak


def mix_from_periodicity(periodicity: float) -> int:
    """周期性 -> 噪声混合比。0.25 以下纯噪声，0.45 以上纯脉冲串。"""
    if periodicity <= VOICED_WEAK:
        return 255
    if periodicity >= VOICED_STRONG:
        return 0
    span = (periodicity - VOICED_WEAK) / (VOICED_STRONG - VOICED_WEAK)
    return int(round(255.0 * (1.0 - span)))


# ----------------------------------------------------------------------- 量化/打包

def quantize_reflection(kappa: float) -> int:
    value = int(round(127.0 * kappa))
    return max(-127, min(127, value))


def pack_frame(period: int, mix: int, gain: int, kappas) -> bytes:
    frame = bytearray()
    frame.append(max(0, min(255, period)))
    frame.append(max(0, min(255, mix)))
    frame.append(max(0, min(255, gain)))
    for value in kappas:
        frame.append(quantize_reflection(value) & 0xFF)
    return bytes(frame)


def analyze_utterance(samples: np.ndarray, rate: int) -> list[dict]:
    peak = float(np.max(np.abs(samples))) if samples.size else 0.0
    if peak <= 0.0:
        raise SystemExit("参考音为空")
    signal = samples * (NORMALIZE_PEAK * 32767.0 / peak)
    emphasized = np.append(signal[0], signal[1:] - PREEMPHASIS * signal[:-1])

    frame_length = int(round(FRAME_MS * rate / 1000.0))
    hop = int(round(HOP_MS * rate / 1000.0))
    window = np.hamming(frame_length)
    window_gain = math.sqrt(float(np.mean(window ** 2)))

    frames: list[dict] = []
    for start in range(0, max(1, signal.size - hop // 2), hop):
        segment = emphasized[start:start + frame_length]
        if segment.size < frame_length:
            segment = np.append(segment, np.zeros(frame_length - segment.size))
        # 基音检测用原始（未预加重）帧：预加重会削弱低频基频结构。
        segment_original = signal[start:start + frame_length]
        if segment_original.size < frame_length:
            segment_original = np.append(
                segment_original, np.zeros(frame_length - segment_original.size))
        windowed = segment * window

        kappa, a, energy = levinson(autocorrelation(windowed, LPC_ORDER), LPC_ORDER)
        rms_residual = math.sqrt(max(0.0, energy)) / window_gain if window_gain > 0 else 0.0
        if rms_residual < SILENCE_RMS:
            frames.append({
                "period": 0, "mix": 255, "gain": 0, "kappa": [0.0] * LPC_ORDER,
                "rms": rms_residual, "periodicity": 0.0,
            })
            continue

        # 基音与周期性用原始（未预加重）帧的低频带估计。
        period, periodicity = estimate_pitch(segment_original, rate)
        frames.append({
            "period": int(period),
            "mix": mix_from_periodicity(periodicity),
            "gain": 0,  # 稍后按全局满量程填
            "kappa": [float(value) for value in kappa[1:]],
            "rms": rms_residual,
            "periodicity": periodicity,
        })
    return frames


def trim_silence(frames: list[dict]) -> list[dict]:
    """裁掉首尾静音帧，只留 1 帧前导静音；句中的静音帧必须保留。"""
    audible = [index for index, frame in enumerate(frames) if frame["rms"] >= SILENCE_RMS]
    if not audible:
        return frames
    head = max(0, audible[0] - 1)
    tail = min(len(frames), audible[-1] + 2)
    return frames[head:tail]


def choose_gain_scale(frames_by_name: dict[str, list[dict]]) -> int:
    worst = 0.0
    for frames in frames_by_name.values():
        for frame in frames:
            worst = max(worst, vm.GAIN_LINEAR_SCALE * frame["rms"])
    scale = int(math.ceil(worst / 100.0) * 100)
    return max(scale, 1000)


def excitation_headroom(frames_by_name: dict[str, list[dict]], gain_scale: int,
                        calibration: float) -> float:
    """返回最坏一帧进格型前的激励幅度，用来确认不会溢出 int16。"""
    worst = 0.0
    for frames in frames_by_name.values():
        for frame in frames:
            byte = vm.encode_gain(
                vm.GAIN_LINEAR_SCALE * frame["rms"] * calibration, gain_scale)
            gain = vm.decode_gain(byte, gain_scale)
            bucket = min(15, frame["period"] >> 4)
            impulse = (gain * vm.PITCH_SCALE[bucket]) >> 8
            # 纯浊音帧（mix=0）的激励幅度最大。
            worst = max(worst, (impulse * 255) >> (8 + vm.EXC_SHIFT))
    return worst


def build_table(frames: list[dict], gain_scale: int,
                calibration: float) -> tuple[bytes, list[dict]]:
    """把线性增益 8*残差RMS*校准量 编码成增益字节；表满量程为 gain_scale。"""
    packed = bytearray()
    report: list[dict] = []
    last = None
    for frame in frames:
        linear = vm.GAIN_LINEAR_SCALE * frame["rms"] * calibration
        gain = vm.encode_gain(linear, gain_scale)
        packed += pack_frame(frame["period"], frame["mix"], gain, frame["kappa"])
        report.append({**frame, "gain_byte": gain})
        last = frame
    # 淡出：保持最后一帧的谱形，逐帧减半，最后补一帧全静音终止帧。
    if last is not None:
        fade_linear = vm.GAIN_LINEAR_SCALE * last["rms"] * calibration
        for step in range(FADE_FRAMES):
            fade_linear *= 0.5
            gain = vm.encode_gain(fade_linear, gain_scale)
            packed += pack_frame(last["period"], last["mix"], gain, last["kappa"])
            report.append({**last, "gain_byte": gain, "fade": step + 1})
        packed += pack_frame(0, 255, 0, [0.0] * LPC_ORDER)
        report.append({"period": 0, "mix": 255, "gain_byte": 0, "kappa": [0.0] * LPC_ORDER,
                       "rms": 0.0, "periodicity": 0.0, "terminator": True})
    return bytes(packed), report


def resample(samples: np.ndarray, source_rate: int, target_rate: int) -> np.ndarray:
    """窗函数 sinc 插值重采样。

    用来把 SAPI 的 8kHz 参考音搬到固件的目标采样率，以及把预览音升到识别器
    要求的 16kHz。不参与固件。
    """
    if source_rate == target_rate:
        return samples
    ratio = target_rate / float(source_rate)
    count = int(round(samples.size * ratio))
    taps = 33
    half = (taps - 1) // 2
    offsets = np.arange(-half, half + 1)
    window = np.hamming(taps)
    output = np.zeros(count)
    for index in range(count):
        center = index / ratio
        base = int(math.floor(center))
        positions = base + offsets
        weights = np.sinc(positions - center) * window
        valid = (positions >= 0) & (positions < samples.size)
        output[index] = float(np.sum(samples[positions[valid]] * weights[valid])
                              / np.sum(weights[valid]))
    return output


# ------------------------------------------------------------------------ 压电片模型

def piezo_response(samples: np.ndarray, rate: int) -> np.ndarray:
    """压电片频响的粗略模拟（仅用于试听预览，不参与固件）。

    按 docs/design 里记录的实测听感：500Hz 附近弱、2~4kHz 有谐振峰。
    """
    signal = samples.astype(np.float64)
    # 一阶高通，corner ≈ 600Hz。
    alpha = 1.0 / (1.0 + 2.0 * math.pi * 600.0 / rate)
    high = np.zeros_like(signal)
    previous_input = 0.0
    previous_output = 0.0
    for index, value in enumerate(signal):
        current = alpha * (previous_output + value - previous_input)
        high[index] = current
        previous_input = value
        previous_output = current
    # 二阶谐振峰，f0 = 2.9kHz、Q = 1.1（RBJ 带通），叠回干信号模拟 2~4kHz 抬升。
    f0 = 2900.0
    q = 1.1
    w0 = 2.0 * math.pi * f0 / rate
    alpha = math.sin(w0) / (2.0 * q)
    a0 = 1.0 + alpha
    cosine = 2.0 * math.cos(w0)
    band = np.zeros_like(high)
    x1 = x2 = y1 = y2 = 0.0
    for index, value in enumerate(high):
        current = (alpha * (value - x2) + cosine * y1 - (1.0 - alpha) * y2) / a0
        x2, x1 = x1, value
        y2, y1 = y1, current
        band[index] = current
    out = high + 1.5 * band
    peak = float(np.max(np.abs(out)))
    if peak > 0.0:
        out *= 30000.0 / peak
    return out


# ------------------------------------------------------------------------ C 代码输出

def c_byte_array(name: str, data: bytes, per_line: int = 16) -> str:
    lines = [f"const uint8_t {name}[{len(data)}] ="]
    lines.append("{")
    for start in range(0, len(data), per_line):
        chunk = data[start:start + per_line]
        lines.append("    " + " ".join(f"0x{value:02X}," for value in chunk))
    lines.append("};")
    return "\n".join(lines)


def c_word_array(name: str, values, per_line: int = 12) -> str:
    lines = [f"const uint16_t {name}[{len(values)}] ="]
    lines.append("{")
    for start in range(0, len(values), per_line):
        chunk = values[start:start + per_line]
        lines.append("    " + " ".join(f"{value}," for value in chunk))
    lines.append("};")
    return "\n".join(lines)


def emit_header(path: Path, utterances, gain_scale: int, sample_rate: float) -> None:
    guard = "BUZZER_VOICE_SMOKE_VOICE_DATA_H"
    body = [
        f"#ifndef {guard}",
        f"#define {guard}",
        "",
        "#include <stdint.h>",
        "",
        "/* 由 stc32g_sdcc/tools/voice/make_voice_params.py 生成，请勿手工修改。 */",
        f"#define VOICE_SAMPLE_RATE_HZ {int(round(sample_rate))}",
        f"#define VOICE_GAIN_FULL_SCALE {gain_scale}",
        "",
        "extern const uint16_t voiceGainTable[256];",
    ]
    for name, frames in utterances:
        count = len(frames) // vm.FRAME_BYTES
        body.append(f"extern const uint8_t voiceFrames{name}[{len(frames)}];")
        body.append(f"#define VOICE_FRAMES_{name.upper()}_COUNT {count}")
    body += ["", f"#endif /* {guard} */", ""]
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(body), encoding="utf-8")


def emit_source(path: Path, utterances, gain_table) -> None:
    body = [
        "/* 由 stc32g_sdcc/tools/voice/make_voice_params.py 生成，请勿手工修改。 */",
        "",
        '#include "voice_data.h"',
        "",
        "/* 增益字节 -> 线性增益（8*残差 RMS）的开方压扩表，替代运行时除法。 */",
        c_word_array("voiceGainTable", gain_table),
        "",
    ]
    for name, frames in utterances:
        count = len(frames) // vm.FRAME_BYTES
        body.append(f"/* {name}: {count} 帧，每帧 {vm.FRAME_BYTES} 字节。 */")
        body.append(c_byte_array(f"voiceFrames{name}", frames))
        body.append("")
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(body), encoding="utf-8")


# ------------------------------------------------------------------------------ 主流程

def render_peak(frames_list: list[bytes], gain_table) -> float | None:
    """渲染并返回峰值；格型定点越界时返回 None（调用方据此降电平）。"""
    peak = 0.0
    for frames in frames_list:
        try:
            idle = vm.render(frames, gain_table, tilt=True)
        except AssertionError:
            return None
        peak = max(peak, float(np.max(np.abs(np.array(idle) - vm.PWM_IDLE))) * 256.0)
    return peak


def main() -> int:
    parser = argparse.ArgumentParser(description="分析 TTS 参考音，生成 LPC-10 参数表与试听预览")
    parser.add_argument("--config", required=True, type=Path, help="voice.json")
    parser.add_argument("--ref-dir", required=True, type=Path, help="参考 WAV 目录")
    parser.add_argument("--out-c", required=True, type=Path)
    parser.add_argument("--out-h", required=True, type=Path)
    parser.add_argument("--params-json", required=True, type=Path)
    parser.add_argument("--preview-dir", type=Path, default=None)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    reference_rate = int(config.get("reference_sample_rate", 8000))
    rate = int(config.get("sample_rate_hz", reference_rate))

    analyzed: dict[str, list[dict]] = {}
    references: dict[str, np.ndarray] = {}
    for utterance in config["utterances"]:
        reference = args.ref_dir / f"{utterance['name']}_ref.wav"
        if not reference.exists():
            raise SystemExit(f"缺少参考音 {reference}；先运行 render_reference.ps1 或 build_voice.ps1")
        samples, wav_rate = read_wav(reference)
        if wav_rate != reference_rate:
            raise SystemExit(f"{reference}: 期望 {reference_rate}Hz，实际 {wav_rate}Hz")
        if rate != reference_rate:
            samples = resample(samples, reference_rate, rate)
        peak = float(np.max(np.abs(samples))) if samples.size else 0.0
        references[utterance["name"]] = samples * (NORMALIZE_PEAK * 32767.0 / peak) if peak else samples
        frames = trim_silence(analyze_utterance(samples, rate))
        analyzed[utterance["name"]] = frames
        print(f"[分析] {utterance['name']:<10} {samples.size / rate:.2f}s "
              f"{len(frames)} 帧 <- {reference.name}")

    base_scale = choose_gain_scale(analyzed)
    # 电平校准：整体增益系数 factor 越大越响，但受两个硬约束——
    #   * 格型内部是 16 位定点，状态越界就整段作废（voice_model 会断言）；
    #   * 8 位 PWM 输出不能削顶。
    # 两个约束对 factor 都是单调的，所以在 [1/16, 4] 上二分找“最大的安全值”。
    def evaluate(factor: float):
        gain_scale = int(min(round(base_scale * factor), GAIN_SCALE_LIMIT))
        if gain_scale < 1:
            return None
        calibration = gain_scale / base_scale
        tables = [build_table(analyzed[name], gain_scale, calibration)[0] for name in analyzed]
        peak = render_peak(tables, vm.build_gain_table(gain_scale))
        if peak is None or peak > TARGET_PEAK:
            return None
        return gain_scale, calibration, peak

    low, high = 1.0 / 16.0, 4.0
    if evaluate(low) is None:
        raise SystemExit("最小电平仍然越界，请提高 EXC_SHIFT")
    best = evaluate(low)
    for _ in range(14):
        middle = (low + high) / 2.0
        result = evaluate(middle)
        if result is None:
            high = middle
        else:
            low = middle
            best = result
    gain_scale, calibration, probe_peak = best
    print(f"[量化] 满量程 {base_scale} -> {gain_scale}（增益系数 x{calibration:.2f}，"
          f"合成峰值 {probe_peak:.0f} / 上限 {TARGET_PEAK:.0f}）")

    headroom = excitation_headroom(analyzed, gain_scale, calibration)
    limit = float(vm.EXCITATION_LIMIT << vm.EXC_SHIFT)
    if headroom > limit:
        raise SystemExit(f"激励幅度 {headroom:.0f} 超过上限 {limit:.0f}，请提高 EXC_SHIFT")
    print(f"[量化] 最大激励 = {headroom:.0f} / 上限 {limit:.0f}")

    gain_table = vm.build_gain_table(gain_scale)
    utterances: list[tuple[str, bytes]] = []
    params: dict = {
        "format_version": 1,
        "sample_rate_hz": rate,
        "frame_bytes": vm.FRAME_BYTES,
        "hop_samples": vm.HOP_SAMPLES,
        "gain_full_scale": gain_scale,
        "gain_table": gain_table,
        "utterances": [],
    }
    for utterance in config["utterances"]:
        name = utterance["name"]
        frames, report = build_table(analyzed[name], gain_scale, calibration)
        utterances.append((name, frames))
        params["utterances"].append({
            "name": name,
            "text": utterance["text"],
            "frame_count": len(frames) // vm.FRAME_BYTES,
            "frames_hex": frames.hex(),
            "stats": {
                "voiced_frames": sum(1 for f in report if f.get("period")),
                "unvoiced_frames": sum(1 for f in report if not f.get("period")),
                "max_kappa": max((abs(k) for f in report for k in f.get("kappa", [0.0])),
                                 default=0.0),
            },
        })
        print(f"[生成] {name:<10} {len(frames)} 字节 "
              f"({len(frames) // vm.FRAME_BYTES} 帧, "
              f"{len(frames) // vm.FRAME_BYTES * vm.HOP_SAMPLES / rate:.2f}s)")

    emit_header(args.out_h, utterances, gain_scale, rate)
    emit_source(args.out_c, utterances, gain_table)
    args.params_json.parent.mkdir(parents=True, exist_ok=True)
    args.params_json.write_text(json.dumps(params, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[写出] {args.out_h.name} / {args.out_c.name} / {args.params_json.name}")

    if args.preview_dir:
        args.preview_dir.mkdir(parents=True, exist_ok=True)
    for name, frames in utterances:
        idle = vm.render(frames, gain_table, tilt=True)
        plain = (np.array(idle, dtype=np.float64) - vm.PWM_IDLE) * 256.0
        reference = references[name]
        clipped = int(np.count_nonzero((np.array(idle) == 0) | (np.array(idle) == 255)))
        print(f"[电平] {name:<10} 参考 RMS={np.sqrt(np.mean(reference ** 2)):7.0f} "
              f"合成 RMS={np.sqrt(np.mean(plain ** 2)):7.0f} "
              f"峰值={np.max(np.abs(plain)):6.0f} 削顶={clipped * 100.0 / len(idle):.2f}%")
        if args.preview_dir:
            write_wav(args.preview_dir / f"{name}_synth.wav", plain, rate)
            # 识别器前端按 16kHz 处理，喂低采样率会得到完全错误的结果。
            write_wav(args.preview_dir / f"{name}_16k.wav",
                      resample(plain, rate, 16000), 16000)
            write_wav(args.preview_dir / f"{name}_piezo.wav",
                      piezo_response(plain, rate), rate)
    if args.preview_dir:
        print(f"[预览] {args.preview_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

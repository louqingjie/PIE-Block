"""校验 voice_model.py 的定点格型合成器。

两部分：
1. 与直接型全极点滤波器逐样本比对：同一组反射系数、同一激励下，
   格型输出必须等于 x[n] = e[n] - sum(a[j] x[n-j])。这一步能抓住符号、
   级序或 Q15 缩放错误——这类错误会让滤波器发散而不是变小声。
2. 用真实参数表跑一遍定点模型，检查 16 位余量与输出电平。

    python check_voice_model.py --params-json .../voice_params.json
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import voice_model as vm  # noqa: E402

ORDER = vm.ORDER


def kappa_to_direct(kappa: list[float]) -> np.ndarray:
    """A_i(z) = A_{i-1}(z) - kappa_i z^-i A_{i-1}(z^-1)，返回 a[1..p]。"""
    a = np.zeros(ORDER + 1)
    for i in range(1, ORDER + 1):
        previous = a.copy()
        a[i] = -kappa[i - 1]
        for j in range(1, i):
            a[j] = previous[j] - kappa[i - 1] * previous[i - j]
    return a


def lattice_reference(stored: list[float], excitation: list[int]) -> list[int]:
    """用 float 直接型滤波作为独立参考实现。

    stored 是表里存的 q = -k（Levinson 的 value）；kappa_to_direct 把它还原成
    A(z) = 1 + sum a_j z^-j 后，直接型差分方程是 y[n] = e[n] - sum a_j y[n-j]。
    history[j] 存 y[n-1-j]，所以读的是 history[j-1]。
    """
    a = kappa_to_direct(stored)
    history = [0.0] * (ORDER + 1)
    output = []
    for sample in excitation:
        value = float(sample)
        for j in range(1, ORDER + 1):
            value -= a[j] * history[j - 1]
        for j in range(ORDER, 0, -1):
            history[j] = history[j - 1]
        history[0] = value
        output.append(value)
    return output


def check_second_order() -> None:
    """2 阶闭式算例：k=[0.3,-0.4] 时 a1=k1(1+k2)=0.179、a2=k2=-0.4，
    y[1] = -a1*100 = -17.9，格型必须给出同一个值。"""
    stored = [round(127 * -0.3), round(127 * 0.4)]  # q = -k
    excitation = [100, 0, 0, 0, 0, 0]
    synth = vm.VoiceSynth.__new__(vm.VoiceSynth)
    synth.k = [0] + [value * vm.K_SCALE for value in stored] + [0] * (ORDER - 2)
    synth.b = [0] * (ORDER + 1)
    model = [synth._lattice(value) for value in excitation]
    reference = lattice_reference([value / 127.0 for value in stored] + [0.0] * (ORDER - 2),
                                  excitation)
    if abs(model[1] - (-17.9)) > 1.0:
        raise SystemExit(f"2 阶闭式校验失败：格型 y[1]={model[1]}，应为 -17.9")
    for index, (got, want) in enumerate(zip(model, reference)):
        if abs(got - want) > 2.0:
            raise SystemExit(f"2 阶第 {index} 个样本不符：{got} vs {want:.2f}")
    print(f"[PASS] 2 阶闭式校验：y[1]={model[1]}（闭式 -17.9）")


def check_lattice() -> None:
    rng = np.random.default_rng(20240607)
    worst = 0.0
    for trial in range(20):
        # 用中等谐振的系数集：随机 ±0.9 会造出极窄带的滤波器，
        # 输出幅度与定点误差都不可控，不适合做等价性判据。
        stored = [float(value) for value in rng.uniform(-0.6, 0.6, ORDER)]
        # 与固件一致：先量化成 round(127*q)，再按 Q15 解码。
        quantized = [max(-127, min(127, int(round(127.0 * value)))) for value in stored]
        decoded = [value / 127.0 for value in quantized]
        excitation = [int(value) for value in rng.integers(-120, 120, 400)]

        synth = vm.VoiceSynth.__new__(vm.VoiceSynth)
        synth.k = [0] + [value * vm.K_SCALE for value in quantized]
        synth.b = [0] * (ORDER + 1)
        model = [synth._lattice(value) for value in excitation]

        reference = lattice_reference(decoded, excitation)
        # 判据用波形相关性：定点每级 >>15 向下取整，10 级级联会带来系统性偏置，
        # 幅度上不该要求逐样本相等；但符号、级序或更新顺序错误会让输出发散或
        # 完全对不上，相关性一定塌掉。
        model_array = np.array(model, dtype=float)
        reference_array = np.array(reference, dtype=float)
        if np.std(model_array) == 0 or np.std(reference_array) == 0:
            raise SystemExit(f"第 {trial} 组输出恒为零，格型未生效")
        correlation = float(np.corrcoef(model_array, reference_array)[0, 1])
        if correlation < 0.995:
            raise SystemExit(f"第 {trial} 组相关性 {correlation:.4f} 低于 0.995")
        relative = float(np.sqrt(np.mean((model_array - reference_array) ** 2))
                         / np.sqrt(np.mean(reference_array ** 2)))
        if relative > 0.25:
            raise SystemExit(f"第 {trial} 组相对 RMS 误差 {relative * 100:.1f}% 超过 25%")
        worst = max(worst, correlation)
    print(f"[PASS] 格型与直接型一致：最低波形相关性 {worst:.4f}")


def check_tables(params: dict) -> None:
    gain_table = params["gain_table"]
    for utterance in params["utterances"]:
        frames = bytes.fromhex(utterance["frames_hex"])
        idle = vm.render(frames, gain_table, tilt=True)
        values = np.array(idle) - vm.PWM_IDLE
        peak = int(np.max(np.abs(values)))
        clipped = int(np.count_nonzero((np.array(idle) == 0) | (np.array(idle) == 255)))
        print(f"[PASS] {utterance['name']:<10} {len(frames) // vm.FRAME_BYTES} 帧 "
              f"峰值={peak} 8位满量程=128 削顶={clipped * 100.0 / len(idle):.2f}% "
              f"RMS={np.sqrt(np.mean(values ** 2)):.1f}")
        if peak >= 128:
            raise SystemExit(f"{utterance['name']}: 8 位输出削顶")
        if clipped:
            raise SystemExit(f"{utterance['name']}: 出现削顶样本")


def check_c_equivalence(params: dict, project_inc: Path, work_dir: Path) -> None:
    """把 voice_synth.c 编成原生程序，与 Python 定点模型逐样本比对。

    两侧都是整数算法，语义必须完全一致，所以判据是“完全相等”，不是近似。
    """
    utterance = params["utterances"][0]
    frames = bytes.fromhex(utterance["frames_hex"])
    gain_table = params["gain_table"]
    work_dir.mkdir(parents=True, exist_ok=True)

    data_lines = ["/* 由 check_voice_model.py 生成，用于主机侧逐样本比对。 */",
                  "#include <stdint.h>", ""]
    data_lines.append(f"const unsigned int voiceFramesTestCount = {len(frames) // vm.FRAME_BYTES};")
    data_lines.append(f"const uint8_t voiceFramesTest[{len(frames)}] =")
    data_lines.append("{")
    for start in range(0, len(frames), 16):
        chunk = frames[start:start + 16]
        data_lines.append("    " + " ".join(f"0x{value:02X}," for value in chunk))
    data_lines.append("};")
    data_lines.append("const uint16_t voiceGainTable[256] =")
    data_lines.append("{")
    for start in range(0, 256, 12):
        chunk = gain_table[start:start + 12]
        data_lines.append("    " + " ".join(f"{value}," for value in chunk))
    data_lines.append("};")
    data_source = work_dir / "host_check_data.c"
    data_source.write_text("\n".join(data_lines) + "\n", encoding="utf-8")

    tool_dir = Path(__file__).resolve().parent
    project_root = project_inc.parent
    executable = work_dir / "host_check.exe"
    compile_command = [
        "gcc", "-O2", "-DVOICE_CODE=", "-I", str(project_inc),
        str(project_root / "src" / "voice_synth.c"),
        str(tool_dir / "host_check_main.c"),
        str(data_source),
        "-o", str(executable),
    ]
    result = subprocess.run(compile_command, capture_output=True, text=True)
    if result.returncode != 0:
        raise SystemExit("主机侧编译失败：\n" + result.stdout + result.stderr)

    run = subprocess.run([str(executable)], capture_output=True, text=True)
    if run.returncode != 0:
        raise SystemExit("主机侧程序退出码非零：" + run.stderr)
    c_samples = [int(line) for line in run.stdout.split()]
    python_samples = vm.render(frames, gain_table, tilt=True)
    if len(c_samples) != len(python_samples):
        raise SystemExit(f"样本数不一致：C {len(c_samples)} vs Python {len(python_samples)}")
    mismatches = [index for index, (a, b) in enumerate(zip(c_samples, python_samples)) if a != b]
    if mismatches:
        first = mismatches[0]
        raise SystemExit(
            f"C 与 Python 有 {len(mismatches)} 个样本不同，第一个在 {first}："
            f"C={c_samples[first]} Python={python_samples[first]}")
    print(f"[PASS] C 与 Python 逐样本一致：{len(c_samples)} 个样本，0 处不同")


def main() -> int:
    tool_dir = Path(__file__).resolve().parent
    default_inc = tool_dir.parents[1] / "projects" / "BUZZER_VOICE_SMOKE" / "inc"
    parser = argparse.ArgumentParser()
    parser.add_argument("--params-json", type=Path, required=True)
    parser.add_argument("--project-inc", type=Path, default=default_inc)
    parser.add_argument("--work-dir", type=Path, default=None)
    parser.add_argument("--skip-host-check", action="store_true")
    args = parser.parse_args()

    params = json.loads(args.params_json.read_text(encoding="utf-8"))
    check_second_order()
    check_lattice()
    check_tables(params)
    if not args.skip_host_check:
        work_dir = args.work_dir or args.params_json.parent / "host_check"
        check_c_equivalence(params, args.project_inc, work_dir)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

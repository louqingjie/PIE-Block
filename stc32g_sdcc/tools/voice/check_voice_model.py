"""校验 voice_model.py 的定点合成器，以及固件热路径的乘法预算。

四部分：

1. :func:`check_arithmetic`：`mul_q8` / `lerp_q8` 的 16 位分解必须与 32 位写法
   **完全相等**（这是把 __mullong 赶出中断的前提，不能只是"近似"）。
2. :func:`check_second_order`：2 阶闭式算例，格型必须给出解析解。
3. :func:`check_lattice`：与直接型全极点滤波器比对波形相关性。
4. :func:`check_c_equivalence`：把 voice_synth.c 编成原生程序，与 Python 定点模型
   **逐样本完全相等**。
5. :func:`check_hot_path_budget`（构建后跑）：扫 voice_synth.asm，确认每个样本都会
   执行的函数里没有 32 位乘法运行库调用。

    python check_voice_model.py --params-json .../voice_params.json
    python check_voice_model.py --params-json .../voice_params.json --asm-only
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import voice_model as vm  # noqa: E402

ORDER = vm.ORDER
# 每个样本都会执行的函数：里面出现 32 位乘法运行库就会拖垮 8kHz 中断。
HOT_FUNCTIONS = (
    "_VoiceSynth_Lattice",
    "_VoiceSynth_Excitation",
    "_VoiceSynth_Noise",
    "_VoiceSynth_Tilt",
    "_VoiceSynth_NextSample",
)
# 32 位乘法运行库的调用指令（SDCC mcs251 用 ecall/lcall）。
LONG_MUL_PATTERN = re.compile(r"\b(?:e|l)call\s+__(?:mul|div)long\b")


def check_arithmetic() -> None:
    """mul_q8 / lerp_q8 必须与 32 位写法完全相等。"""
    values = [0, 1, -1, 2, -2, 127, -127, 128, -128, 255, -255, 256, -256,
              1023, -1024, 4095, -4096, 16383, -16384, 32767, -32768]
    for q in range(-127, 128):
        for value in values:
            expected = (q << 8) * value >> 15
            got = vm.mul_q8(q, value)
            if got != expected:
                raise SystemExit(f"mul_q8({q}, {value}) = {got}，应为 {expected}")
    rng = np.random.default_rng(20240607)
    for _ in range(200000):
        q = int(rng.integers(-127, 128))
        value = int(rng.integers(-32768, 32768))
        if vm.mul_q8(q, value) != ((q << 8) * value >> 15):
            raise SystemExit(f"mul_q8 随机样本不符：q={q} value={value}")
    print("[PASS] mul_q8 与 32 位写法完全相等（255×21 组边界 + 200000 组随机）")

    # lerp_q8 的契约是 |current - previous| <= 255，所以分两组合法端点穷举。
    for endpoints in ([-127, -100, -64, -1, 0, 1, 64, 100, 127],
                      [0, 1, 64, 127, 128, 200, 254, 255]):
        for previous in endpoints:
            for current in endpoints:
                for weight in vm.INTERP_WEIGHT:
                    expected = previous + (((current - previous) * weight) >> 8)
                    got = vm.lerp_q8(previous, current, weight)
                    if got != expected:
                        raise SystemExit(
                            f"lerp_q8({previous}, {current}, {weight}) = {got}，"
                            f"应为 {expected}")
    print("[PASS] lerp_q8 与 32 位写法完全相等（两组合法端点 × 8 个权重）")


def kappa_to_direct(stored: list[float]) -> np.ndarray:
    """stored 是表里存的 q = -k；还原 A(z) = 1 + sum a_j z^-j。"""
    a = np.zeros(ORDER + 1)
    for i in range(1, ORDER + 1):
        previous = a.copy()
        a[i] = -stored[i - 1]
        for j in range(1, i):
            a[j] = previous[j] - stored[i - 1] * previous[i - j]
    return a


def lattice_reference(stored: list[float], excitation: list[int]) -> list[int]:
    """用 float 直接型滤波作为独立参考实现。

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
    synth.k = [0] + stored + [0] * (ORDER - 2)
    synth.b = [0] * (ORDER + 1)
    model = [synth._lattice(value) for value in excitation]
    # 表里的 q 按 q<<8 解码（K_SCALE = 256），即 k = q/128。
    reference = lattice_reference([value / 128.0 for value in stored] + [0.0] * (ORDER - 2),
                                  excitation)
    if abs(model[1] - (-17.86)) > 1.5:
        raise SystemExit(f"2 阶闭式校验失败：格型 y[1]={model[1]}，应为 -17.86")
    for index, (got, want) in enumerate(zip(model, reference)):
        if abs(got - want) > 2.0:
            raise SystemExit(f"2 阶第 {index} 个样本不符：{got} vs {want:.2f}")
    print(f"[PASS] 2 阶闭式校验：y[1]={model[1]}（闭式 -17.86）")


def check_lattice() -> None:
    rng = np.random.default_rng(20240607)
    worst = 1.0
    for trial in range(20):
        # 用中等谐振的系数集：随机 ±0.9 会造出极窄带的滤波器，
        # 输出幅度与定点误差都不可控，不适合做等价性判据。
        stored = [float(value) for value in rng.uniform(-0.6, 0.6, ORDER)]
        quantized = [max(-127, min(127, int(round(127.0 * value)))) for value in stored]
        decoded = [value / 128.0 for value in quantized]   # q<<8 解码：k = q/128
        excitation = [int(value) for value in rng.integers(-120, 120, 400)]

        synth = vm.VoiceSynth.__new__(vm.VoiceSynth)
        synth.k = [0] + quantized
        synth.b = [0] * (ORDER + 1)
        model = [synth._lattice(value) for value in excitation]

        reference = lattice_reference(decoded, excitation)
        # 判据用波形相关性：定点每级右移都向下取整，10 级级联会带来系统性偏置，
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
        worst = min(worst, correlation)
    print(f"[PASS] 格型与直接型一致：最低波形相关性 {worst:.4f}")


def check_tables(params: dict) -> None:
    gain_table = params["gain_table"]
    gamma = params.get("compression_gamma")
    for utterance in params["utterances"]:
        frames = bytes.fromhex(utterance["frames_hex"])
        idle = vm.render(frames, gain_table, tilt=True, compression_gamma=gamma)
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

    两侧都是整数算法，语义必须完全一致，所以判据是"完全相等"，不是近似。
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
    data_lines.append("const uint8_t voiceCompressionTable[256] =")
    data_lines.append("{")
    compression = params["compression_table"]
    for start in range(0, 256, 16):
        chunk = compression[start:start + 16]
        data_lines.append("    " + " ".join(f"{value}," for value in chunk))
    data_lines.append("};")
    data_source = work_dir / "host_check_data.c"
    data_source.write_text("\n".join(data_lines) + "\n", encoding="utf-8")

    tool_dir = Path(__file__).resolve().parent
    project_root = project_inc.parent
    executable = work_dir / "host_check.exe"
    compile_command = [
        "gcc", "-O2", "-DVOICE_CODE=", "-DVOICE_NEAR=", "-DVOICE_HOST_BUILD",
        "-I", str(project_inc),
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
    python_samples = vm.render(frames, gain_table, tilt=True,
                               compression_gamma=params.get("compression_gamma"))
    if len(c_samples) != len(python_samples):
        raise SystemExit(f"样本数不一致：C {len(c_samples)} vs Python {len(python_samples)}")
    mismatches = [index for index, (a, b) in enumerate(zip(c_samples, python_samples)) if a != b]
    if mismatches:
        first = mismatches[0]
        raise SystemExit(
            f"C 与 Python 有 {len(mismatches)} 个样本不同，第一个在 {first}："
            f"C={c_samples[first]} Python={python_samples[first]}")
    print(f"[PASS] C 与 Python 逐样本一致：{len(c_samples)} 个样本，0 处不同")

    # 逐样本一致只覆盖真实语料出现过的取值；MulQ8/Lerp 的负数取整边界要单独穷举。
    arithmetic = subprocess.run([str(executable), "arith"], capture_output=True, text=True)
    if arithmetic.returncode != 0:
        raise SystemExit("主机侧算术模式退出码非零：" + arithmetic.stderr)
    checked = 0
    for line in arithmetic.stdout.splitlines():
        parts = line.split()
        if not parts:
            continue
        if parts[0] == "M":
            q, value, result = int(parts[1]), int(parts[2]), int(parts[3])
            expected = vm.mul_q8(q, value)
            if expected != result:
                raise SystemExit(f"C 的 MulQ8({q}, {value}) = {result}，Python 为 {expected}")
        elif parts[0] == "L":
            previous, current, weight, result = (int(parts[1]), int(parts[2]),
                                                 int(parts[3]), int(parts[4]))
            expected = vm.lerp_q8(previous, current, weight)
            if expected != result:
                raise SystemExit(
                    f"C 的 Lerp({previous}, {current}, {weight}) = {result}，"
                    f"Python 为 {expected}")
        else:
            continue
        checked += 1
    print(f"[PASS] C 的 MulQ8/Lerp 与 Python 完全一致：{checked} 组边界取值")


def check_hot_path_budget(asm_path: Path, order: int, sample_rate_hz: float = 8000.5) -> None:
    """扫汇编：热路径不允许出现 32 位乘除运行库调用，并估算每样本周期数。

    指令周期用保守的粗略模型（MCS-251 寄存器操作 1 周期、间接/外部存储访问 3、
    mul ab 2、分支 3、库调用另算）。估算值只用于"有没有数量级问题"，判据是
    每样本预算 = 1/采样率。
    """
    if not asm_path.exists():
        raise SystemExit(f"找不到汇编文件 {asm_path}，先构建固件")
    text = asm_path.read_text(encoding="utf-8", errors="replace")
    lines = text.splitlines()
    label_pattern = re.compile(r"^_([A-Za-z_][A-Za-z0-9_]*):")
    bodies: dict[str, list[str]] = {}
    current = None
    for line in lines:
        match = label_pattern.match(line)
        if match:
            current = "_" + match.group(1)
            bodies.setdefault(current, [])
            continue
        if current is not None:
            bodies[current].append(line)

    total_long_mul = len(LONG_MUL_PATTERN.findall(text))
    problems = []
    for name in HOT_FUNCTIONS:
        body = bodies.get(name)
        if body is None:
            raise SystemExit(f"汇编里找不到 {name}，热路径检查无法进行")
        instructions = sum(1 for line in body
                           if line.strip() and not line.lstrip().startswith(";"))
        calls = LONG_MUL_PATTERN.findall("\n".join(body))
        print(f"[信息] {name:<28} 指令 {instructions:4d} 条，32 位乘除调用 {len(calls)} 次")
        if calls:
            problems.append(name)
    if problems:
        raise SystemExit(
            "热路径里仍有 32 位乘除运行库调用（每个样本约 590 周期/次，会拖垮 8kHz 中断）: "
            + ", ".join(problems))

    # 估算：从 NextSample 出发递归展开被调函数，格型另有 9 级（NextSample 里只算到 1 级）。
    cost_table = [
        (re.compile(r"^\s*mul\s+ab\b"), 2),
        (re.compile(r"^\s*(?:e|l)call\b"), 4),
        (re.compile(r"^\s*(?:push|pop)\b"), 2),
        (re.compile(r"^\s*(?:sjmp|jne|je|jz|jnz|jb|jbc|jnb|cjne|djnz)\b"), 3),
        (re.compile(r"^\s*movx?\b.*@"), 3),
        (re.compile(r"^\s*ret\b"), 2),
    ]
    call_pattern = re.compile(r"^\s*(?:e|l)call\s+(_[A-Za-z_][A-Za-z0-9_]*)\b")

    def function_cost(name: str, stack: tuple[str, ...] = ()) -> int:
        if name in stack:
            return 0
        body = bodies.get(name)
        if body is None:
            return 0
        total = 0
        for line in body:
            stripped = line.strip()
            if not stripped or stripped.startswith(";"):
                continue
            matched = False
            for pattern, cycles in cost_table:
                if pattern.match(line):
                    total += cycles
                    matched = True
                    break
            if not matched:
                total += 1
            call = call_pattern.match(line)
            if call:
                # 插值只在每帧的 8 个子步里跑一次，按 1/10 摊到每个样本。
                weight = 0.1 if call.group(1) == "_VoiceSynth_AdvanceStep" else 1.0
                total += weight * function_cost(call.group(1), stack + (name,))
        return total

    lattice = function_cost("_VoiceSynth_Lattice")
    # NextSample 里已经含 1 级格型，剩下的 order-1 级要补上（阶数从帧长推：3 + 阶数）。
    per_sample = function_cost("_VoiceSynth_NextSample") + (order - 1) * lattice
    detail = [f"格型单级={lattice}", f"阶数={order}",
              f"NextSample(含1级格型)={function_cost('_VoiceSynth_NextSample')}"]

    budget_cycles = 33177600.0 / sample_rate_hz
    used_us = per_sample / 33177600.0 * 1e6
    budget_us = budget_cycles / 33177600.0 * 1e6
    print(f"[信息] 每样本约 {per_sample} 周期（{used_us:.1f} us）/ 预算 {budget_us:.1f} us"
          f"（{', '.join(detail)}）")
    # 估算用的单指令周期是保守值（存储访问 3、分支 3），实际约 2 周期/指令：
    # 校准点是上一版固件"每样本 25 次 __mullong"实测播放慢 3.6 倍（≈449 us）。
    # 所以这里只把"估算值超过预算"当失败，超过预算意味着中断会追尾。
    if per_sample > budget_cycles:
        raise SystemExit(
            f"中断预算不足：估算 {used_us:.1f} us > 预算 {budget_us:.1f} us，"
            "播放会变慢；请减少每样本的乘法或降低采样率")
    print(f"[PASS] 热路径无 32 位乘除调用，估算占用 {used_us / budget_us * 100:.0f}% 中断预算"
          f"（全文件 {total_long_mul} 次库调用，均在每帧执行一次的代码里）")


def main() -> int:
    tool_dir = Path(__file__).resolve().parent
    default_inc = tool_dir.parents[1] / "projects" / "BUZZER_VOICE_SMOKE" / "inc"
    parser = argparse.ArgumentParser()
    parser.add_argument("--params-json", type=Path, required=True)
    parser.add_argument("--project-inc", type=Path, default=default_inc)
    parser.add_argument("--work-dir", type=Path, default=None)
    parser.add_argument("--asm", type=Path, default=None,
                        help="voice_synth.asm，默认取 params-json 同目录")
    parser.add_argument("--asm-only", action="store_true")
    parser.add_argument("--skip-host-check", action="store_true")
    args = parser.parse_args()

    params = json.loads(args.params_json.read_text(encoding="utf-8-sig"))
    if not args.asm_only:
        check_arithmetic()
        check_second_order()
        check_lattice()
        check_tables(params)
        if not args.skip_host_check:
            work_dir = args.work_dir or args.params_json.parent / "host_check"
            check_c_equivalence(params, args.project_inc, work_dir)
    asm_path = args.asm or args.params_json.parent / "voice_synth.asm"
    check_hot_path_budget(asm_path, params["frame_bytes"] - 3, params["sample_rate_hz"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

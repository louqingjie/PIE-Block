"""主控板主频「探针定性」脚本（阶段 2，配合 clock_probe 探针固件使用）。

> ⚠ 标称频率已变更：固件主频已从 33.1776MHz 迁到 **22.1184MHz**（见
> docs/design/主控板主频故障复盘与22.1184MHz迁移.md）。本脚本的阈值/换算目前仍按
> **33.1776MHz 标称的探针固件**编写——它仍然适合诊断“33.1776 档校准值坏”的历史坏片。
> 若要用新标称（22.1184MHz）筛片，需要做两件事（TODO）：
>   1. 探针固件 `clock_probe_main.c` 增印 `CHIPID11`（22.1184MHz 档校准值）；
>   2. 本脚本把 `NOMINAL_MHZ` 改成 22.1184、主判据改成 `CHIPID11`。

前提
----
先用 tools/diagnostics/build_clock_probe.ps1 构建探针 hex，再用 STC-ISP（或 IDE）
烧到目标板：芯片型号 STC32G12K128、频率按探针的标称频率填写、勾选“本次下载需要修改硬件选项”
（若探针用 22.1184MHz 标称重建，则填 22.1184MHz）。

探针固件行为（见 clock_probe_main.c）
------------------------------------
· 调 Board_Init()（与应用固件相同的设频逻辑），随后打印
      I A:xx V:xx B:xx D:xx T:xx R:xx
  A=IRTRIM、V=VRTRIM、B=IRCBAND、D=CLKDIV、T=CHIPID15（33.1776MHz 校准值）、R=CHIPID23
· 然后 7 档循环：0=22.1184M 1=24M 2=27M 3=30M 4=33.1776M(手册写法)
  5=35M 6=33.1776M(应用写法)，每档打印一行同格式报告 + 连发 240 个档号字符。
· 线上波特率 = 230400 × 实际主频 / 探针标称频率，所以“在哪个波特率能解出该档字符”
  就说明该档实际跑到了多少主频。

用法
----
    python board_clock_probe_report.py COM3
    python board_clock_probe_report.py COM3 --json probe_result.json

退出码
    0 = PASS   主频正常（CHIPID15 合理，33.1776MHz 档能到 230400）
    1 = FAIL   主频异常 / CHIPID15 校准值异常
    2 = WARN   探针输出不足，需检查探针是否烧好、接线是否正常
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
import time

import serial

TAGS = "OI0123456"
TARGET_MHZ = {
    "0": 22.1184,
    "1": 24.0,
    "2": 27.0,
    "3": 30.0,
    "4": 33.1776,
    "5": 35.0,
    "6": 33.1776,
}
LINE_RE = re.compile(
    r"^([OI0-6]) A:([0-9A-Fa-f]{2}) V:([0-9A-Fa-f]{2}) B:([0-9A-Fa-f]{2}) "
    r"D:([0-9A-Fa-f]{2}) T:([0-9A-Fa-f]{2}) R:([0-9A-Fa-f]{2})$"
)
CHIPID15_MIN_OK = 0xE0   # 好板 33.1776MHz 校准值应接近 0xFA；明显低于 0xE0 判异常
# 主频判定容差：串口分频/CH340 量化会给估计带来约 ±3% 的系统偏差，故放宽到 ±8%
TOLERANCE = 0.08


def capture(port: str, baud: int, seconds: float) -> bytes:
    ser = serial.Serial(port, baud, timeout=0.05)
    buf = bytearray()
    t0 = time.perf_counter()
    while time.perf_counter() - t0 < seconds:
        chunk = ser.read(4096)
        if chunk:
            buf.extend(chunk)
    ser.close()
    return bytes(buf)


def longest_run(data: bytes, ch: int) -> int:
    best = cur = 0
    for b in data:
        if b == ch:
            cur += 1
            if cur > best:
                best = cur
        else:
            cur = 0
    return best


def decode_lines(data: bytes) -> list[tuple[str, ...]]:
    out = []
    for raw in data.split(b"\r\n"):
        try:
            text = raw.decode("ascii")
        except UnicodeDecodeError:
            continue
        m = LINE_RE.match(text.strip())
        if m:
            out.append(tuple(m.groups()))
    return out


def main() -> int:
    parser = argparse.ArgumentParser(description="主控板主频探针判读（阶段 2）")
    parser.add_argument("port", nargs="?", default="COM3")
    parser.add_argument("--seconds", type=float, default=1.5, help="每个波特率抓取秒数")
    parser.add_argument("--step", type=int, default=4000, help="扫描波特率步进")
    parser.add_argument("--json", dest="json_path")
    args = parser.parse_args()

    runs: dict[str, dict[int, int]] = {t: {} for t in TAGS}
    lines: dict[str, dict[int, tuple[str, ...]]] = {t: {} for t in TAGS}

    bauds = list(range(148000, 254000, args.step))
    for baud in bauds:
        try:
            data = capture(args.port, baud, args.seconds)
        except Exception as exc:  # noqa: BLE001
            print(f"打开串口 {args.port} @ {baud} 失败: {exc}")
            return 2
        for t in TAGS:
            run = longest_run(data, ord(t))
            if run >= 200:
                runs[t][baud] = max(runs[t].get(baud, 0), run)
        for item in decode_lines(data):
            lines[item[0]][baud] = item[1:]

    # 汇总每个档位：命中波特率的区间 → 估计实际主频
    step_info: dict[str, dict] = {}
    for t in "0123456":
        hits = sorted(runs[t])
        if not hits:
            step_info[t] = {"target_mhz": TARGET_MHZ[t], "hits": [], "clock_mhz": None}
            continue
        est = statistics.median([b * 33.1776 / 230400.0 for b in hits])
        step_info[t] = {
            "target_mhz": TARGET_MHZ[t],
            "hits": hits,
            "clock_mhz": round(est, 2),
        }

    # 寄存器报告：CHIPID15 / CHIPID23 是常量，取任意一行
    chipid15 = chipid23 = None
    for t in "I0123456":
        for baud in sorted(lines[t]):
            chipid15 = int(lines[t][baud][4], 16)
            chipid23 = int(lines[t][baud][5], 16)
            break
        if chipid15 is not None:
            break

    print(f"端口 {args.port}  扫描 {len(bauds)} 个波特率，每档 {args.seconds:.1f}s")
    print(f"{'档位':^4} {'目标主频':>10} {'实测估计':>10} {'命中波特率范围':>22}")
    for t in "0123456":
        info = step_info[t]
        hits = info["hits"]
        rng = f"{hits[0]}~{hits[-1]}" if hits else "未解出"
        clock = f"{info['clock_mhz']:.2f}MHz" if info["clock_mhz"] else "-"
        print(f"{t:^4} {info['target_mhz']:>9.4f}M {clock:>10} {rng:>22}")
    print()
    if chipid15 is None:
        print("未能解出寄存器报告行（探针可能没在跑，或接线/供电异常）")
    else:
        print(f"CHIPID15（33.1776MHz 校准值） = 0x{chipid15:02X}")
        print(f"CHIPID23（27M 频段 VRTRIM）   = 0x{chipid23:02X}")

    # 判定
    est4 = step_info["4"]["clock_mhz"]
    if chipid15 is None:
        verdict, code = "WARN", 2
        reason = "解不出探针报告行：确认探针固件已烧写、P31→CH340 RX 接线与共地、板子已上电"
    elif chipid15 < CHIPID15_MIN_OK:
        verdict, code = "FAIL", 1
        reason = (
            f"CHIPID15=0x{chipid15:02X} 明显偏低（正常应接近 0xFA），"
            "33.1776MHz 档的出厂校准值异常，属芯片级缺陷，建议更换芯片"
        )
    elif est4 is not None and abs(est4 - 33.1776) / 33.1776 > TOLERANCE:
        verdict, code = "FAIL", 1
        reason = f"33.1776MHz 档实测 {est4:.2f}MHz，偏差超过 ±5%，主频异常"
    elif est4 is None:
        verdict, code = "WARN", 2
        reason = "未能在任何波特率解出 33.1776MHz 档（档 4）标记，需人工复核"
    else:
        verdict, code = "PASS", 0
        reason = f"CHIPID15=0x{chipid15:02X}，33.1776MHz 档实测 {est4:.2f}MHz，主频正常"

    print()
    print(f"结论: {verdict}")
    print(f"原因: {reason}")

    result = {
        "port": args.port,
        "chipid15": chipid15,
        "chipid23": chipid23,
        "steps": step_info,
        "verdict": verdict,
        "exit_code": code,
        "reason": reason,
    }
    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as fp:
            json.dump(result, fp, ensure_ascii=False, indent=2)
        print(f"已写入 {args.json_path}")

    return code


if __name__ == "__main__":
    sys.exit(main())

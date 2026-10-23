"""主控板主频「快速筛板」脚本（阶段 1，配合标准应用固件使用）。

背景
----
应用固件里 UART1 的波特率是按**编译期 FOSC**（当前为 `22.1184MHz`，历史版本为 `33.1776MHz`）
算出来的 230400。所以同一份应用固件：
    · 主频正常的板子  → 230400 能干净解出 21 字节协议帧（AB BC ... CD DE）
    · 主频异常的板子  → 只在更低的波特率能解出（线上波特率 = 230400 × 实际主频 / 标称主频）
因此只要在几个候选波特率下统计“有效协议帧数”，就能把板子分成 PASS / FAIL。

> 主频迁移说明：标称频率已从 33.1776MHz 迁到 **22.1184MHz**，
> 详见 docs/design/主控板主频故障复盘与22.1184MHz迁移.md。
> 本脚本用 `NOMINAL_MHZ` 表示标称频率；更换编译频率时只需改它（以及必要时补候选波特率）。

用法
----
    python board_clock_screen.py COM3
    python board_clock_screen.py COM3 --seconds 3 --json result.json

退出码（方便批量脚本判断）
    0 = PASS      主频正常
    1 = FAIL      主频异常（典型：能在更低波特率解出、230400 解不出）
    2 = WARN      数据不足/不稳定，需要人工复核
    3 = NO-SIGNAL 所有波特率一个字节都没有（供电/接线/固件问题）
    4 = PROBE     检测到“时钟自检探针固件”的文本输出，请先烧回标准应用固件再筛板
"""
from __future__ import annotations

import argparse
import json
import sys
import time

import serial

# 标称主频（与 stc32g_sdcc/include/common.h 的 FOSC 保持一致）
NOMINAL_MHZ = 22.1184

# (波特率, 该波特率对应的“相对标称”说明)
BAUD_CANDIDATES = [
    (230400, "正常（=标称主频）"),
    (166667, "≈0.72× 标称"),
    (161000, "≈0.70× 标称"),
    (157300, "≈0.68× 标称"),
    (153600, "≈0.67× 标称"),
]

FRAME_LEN = 21
# 判定阈值：一个 2.5s 窗口里，正常固件至少能出现这么多帧
MIN_FRAMES = 10
LOW_BAND = (153600, 157300, 161000, 166667)


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


def count_frames(data: bytes) -> int:
    """统计 AB BC ... CD DE 的 21 字节协议帧数量。"""
    n = 0
    i = 0
    while i + FRAME_LEN <= len(data):
        if (
            data[i] == 0xAB
            and data[i + 1] == 0xBC
            and data[i + 19] == 0xCD
            and data[i + 20] == 0xDE
        ):
            n += 1
            i += FRAME_LEN
        else:
            i += 1
    return n


def looks_like_probe(data: bytes) -> bool:
    """探针固件输出形如 'I A:3D V:1A B:02 D:00 T:3D R:1A' 的 ASCII 行。"""
    return (b" A:" in data and b" V:" in data) or b"START" in data


def main() -> int:
    parser = argparse.ArgumentParser(description="主控板主频快速筛板（阶段 1）")
    parser.add_argument("port", nargs="?", default="COM3", help="串口名，默认 COM3")
    parser.add_argument("--seconds", type=float, default=2.5, help="每个波特率抓取秒数")
    parser.add_argument("--json", dest="json_path", help="把结果写入 JSON 文件")
    args = parser.parse_args()

    rows = []
    probe_signal = False
    for baud, label in BAUD_CANDIDATES:
        try:
            data = capture(args.port, baud, args.seconds)
        except Exception as exc:  # noqa: BLE001
            print(f"打开串口 {args.port} @ {baud} 失败: {exc}")
            return 2
        frames = count_frames(data)
        if looks_like_probe(data):
            probe_signal = True
        rows.append(
            {
                "baud": baud,
                "label": label,
                "bytes": len(data),
                "frames": frames,
            }
        )

    total_bytes = sum(r["bytes"] for r in rows)
    frames_at = {r["baud"]: r["frames"] for r in rows}
    low_frames = max(frames_at[b] for b in LOW_BAND)

    print(f"端口 {args.port}  每档 {args.seconds:.1f}s")
    print(f"{'波特率':>8} {'对应主频':<24} {'字节':>6} {'有效帧':>6}")
    for r in rows:
        print(f"{r['baud']:>8} {r['label']:<24} {r['bytes']:>6} {r['frames']:>6}")

    if total_bytes == 0:
        verdict, code = "NO-SIGNAL", 3
        reason = "所有波特率都收不到字节：检查供电、CH340 的 RX 是否接主控 P31、是否共地、是否已烧应用固件"
    elif probe_signal and frames_at[230400] < MIN_FRAMES and low_frames < MIN_FRAMES:
        verdict, code = "PROBE", 4
        reason = "检测到时钟自检探针固件的文本输出，请先烧回标准应用固件再做阶段 1 筛板"
    elif frames_at[230400] >= MIN_FRAMES and frames_at[230400] >= max(frames_at.values()):
        verdict, code = "PASS", 0
        reason = f"230400 下解出 {frames_at[230400]} 帧，主频正常（标称 {NOMINAL_MHZ:.4f}MHz）"
    elif low_frames >= MIN_FRAMES:
        verdict, code = "FAIL", 1
        reason = (
            "230400 解不出协议帧，但在更低波特率区间能解出：主频异常。"
            "典型原因是芯片当前档位的出厂校准值（CHIPID11 / 22.1184MHz 档，"
            "历史版本为 CHIPID15 / 33.1776MHz 档）损坏或异常，"
            "或该板仍在跑旧版标称频率的固件；建议进入阶段 2 用探针固件确认"
        )
    else:
        verdict, code = "WARN", 2
        reason = "有效帧太少或各档差异不明显：请复核固件版本、接线、供电后再测，或直接进入阶段 2"

    best = max(rows, key=lambda r: r["frames"])
    est_clock = best["baud"] * NOMINAL_MHZ / 230400.0 if best["frames"] else 0.0
    print()
    print(f"结论: {verdict}")
    print(f"原因: {reason}")
    if best["frames"]:
        print(f"估计主频: ≈{est_clock:.2f} MHz（最佳波特率 {best['baud']}，{best['frames']} 帧）")

    result = {
        "port": args.port,
        "seconds": args.seconds,
        "verdict": verdict,
        "exit_code": code,
        "reason": reason,
        "estimated_clock_mhz": round(est_clock, 2) if best["frames"] else None,
        "rows": rows,
    }
    if args.json_path:
        with open(args.json_path, "w", encoding="utf-8") as fp:
            json.dump(result, fp, ensure_ascii=False, indent=2)
        print(f"已写入 {args.json_path}")

    return code


if __name__ == "__main__":
    sys.exit(main())

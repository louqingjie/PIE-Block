#!/usr/bin/env python3
"""analyze_usbmon.py - 解析 Linux usbmon 文本抓包，提取 STC USB-ISP 的传输时间线。

仓库原有的 analyze_capture.py 只认 Windows 的 USBPcap pcap；Linux 侧要看清
「主机到底把什么、什么时候推上总线」，用 usbmon 的文本接口最省事：

    sudo modprobe usbmon
    ls /sys/kernel/debug/usb/usbmon/            # 找到板子所在总线的 <N>u
    sudo cat /sys/kernel/debug/usb/usbmon/3u > /tmp/usbmon-3u.txt   # 期间跑烧录
    # Ctrl-C 结束抓包后：
    python3 analyze_usbmon.py /tmp/usbmon-3u.txt

输出：
- 每笔中断/批量传输的完成事件（时间、方向、端点、状态、长度、STC 帧头/命令）；
- STC 报告的汇总：总笔数、方向分布、长度分布、相邻 OUT 之间的间隔统计；
- 失败段：状态非 0 的传输、以及时间线末尾（设备掉线前）的原始事件。

usbmon 文本行格式（`Nu` 接口）：
    <urb tag> <timestamp> <S|C|E> <type><dir>:<bus>:<dev>:<ep> <status>[:<interval>] <len> [= <hex>]
    C Ii:3:006:1 0:8 64 = 46b9...      （中断传输的 status 后面跟 interval）
    C Io:3:006:1 -71 0                 （失败时只有 status）
"""
from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass

EVENT = re.compile(
    r"^(?P<tag>[0-9a-f]+)\s+(?P<ts>\d+\.\d+)\s+(?P<kind>[SCE])\s+"
    r"(?P<type>[A-Za-z]{2}):(?P<bus>\d+):(?P<dev>\d+):(?P<ep>\d+)\s+"
    r"(?P<status>-?\d+)(?::\d+)?\s+(?P<len>\d+)(?:\s+=\s+(?P<data>[0-9a-fA-F ]*))?$"
)


@dataclass
class Transfer:
    ts: float
    direction: str   # 'in' / 'out'
    endpoint: str    # 例如 'Io:3:6:1'
    status: int
    length: int
    data: bytes

    @property
    def ok(self) -> bool:
        return self.status == 0


def parse(path: str) -> list[Transfer]:
    transfers: list[Transfer] = []
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            if not line.strip().startswith(("ffff", "0x")):
                continue
            match = EVENT.match(line.strip())
            if not match or match.group("kind") != "C":
                continue
            hexdata = (match.group("data") or "").replace(" ", "")
            kind = match.group("type")
            transfers.append(
                Transfer(
                    ts=float(match.group("ts")),
                    direction="in" if kind in ("Ii", "Bi", "Ci") else "out",
                    endpoint=f"{kind}:{match.group('bus')}:{match.group('dev')}:{match.group('ep')}",
                    status=int(match.group("status")),
                    length=int(match.group("len")),
                    data=bytes.fromhex(hexdata) if hexdata else b"",
                )
            )
    return transfers


def stc_offset(data: bytes) -> int | None:
    """返回 STC 帧头在报告里的偏移：0=内核已剥掉 report ID，1=仍带前导 0x00。"""
    if data[:2] == b"\x46\xb9":
        return 0
    if data[:3] == b"\x00\x46\xb9":
        return 1
    return None


def _is_frame_start(data: bytes) -> bool:
    offset = stc_offset(data)
    return offset is not None and data[offset + 2:offset + 3] == b"\x6a"


def describe_stc(data: bytes) -> str:
    """把 STC 报告解成帧头/命令/长度；不完整或非 STC 就返回原始前几字节。"""
    raw = " ".join(f"{b:02x}" for b in data[:8])
    offset = stc_offset(data)
    if offset is not None and len(data) >= 6 + offset:
        frame = data[offset:]
        who = {0x6A: "host", 0x68: "mcu"}.get(frame[2], "?")
        frame_len = (frame[3] << 8) | frame[4]
        command = f"cmd=0x{frame[5]:02x}" if len(frame) > 5 else ""
        address = ""
        if len(frame) > 7 and frame[5] in (0x02, 0x03, 0x04, 0x12, 0x32):
            address = f" addr=0x{frame[6]:02x}{frame[7]:02x}"
        lead = " [带前导 0x00]" if offset else ""
        return f"STC {who} len={frame_len} {command}{address}{lead} | {raw}"
    return f"| {raw}"


def summarize(transfers: list[Transfer], out) -> None:
    if not transfers:
        print("抓包里没有已完成的中断/批量传输", file=out)
        return
    first = transfers[0].ts
    outs = [t for t in transfers if t.direction == "out"]
    ins = [t for t in transfers if t.direction == "in"]
    print(
        f"总传输 {len(transfers)} 笔：OUT {len(outs)}、IN {len(ins)}；"
        f"跨度 {transfers[-1].ts - first:.3f}s",
        file=out,
    )
    lengths: dict[int, int] = {}
    for transfer in transfers:
        key = transfer.length if transfer.ok else -transfer.length
        lengths[key] = lengths.get(key, 0) + 1
    print(
        "长度分布（负数=失败的笔数）："
        + ", ".join(f"{key}B×{count}" for key, count in sorted(lengths.items())),
        file=out,
    )
    bad = [t for t in transfers if not t.ok]
    print(f"状态非 0 的传输：{len(bad)} 笔", file=out)
    for transfer in bad[:40]:
        print(
            f"  +{transfer.ts - first:8.3f}s {transfer.endpoint} "
            f"status={transfer.status} len={transfer.length} {transfer.data[:8].hex(' ')}",
            file=out,
        )
    gaps = [b.ts - a.ts for a, b in zip(outs, outs[1:])]
    if gaps:
        ordered = sorted(gaps)
        print(
            "相邻 OUT 完成间隔："
            f"min={ordered[0] * 1000:.2f}ms "
            f"p50={ordered[len(ordered) // 2] * 1000:.2f}ms "
            f"p95={ordered[int(len(ordered) * 0.95)] * 1000:.2f}ms "
            f"max={ordered[-1] * 1000:.2f}ms",
            file=out,
        )
    # 每帧的第一份报告都以 46 B9 6A 开头（可能带前导 0x00），据此数帧。
    frames = [t for t in outs if _is_frame_start(t.data)]
    print(f"OUT 中以 46 B9 6A 开头的帧起始报告：{len(frames)} 笔", file=out)
    if frames:
        print("最后 3 帧：", file=out)
        for transfer in frames[-3:]:
            frame = transfer.data[stc_offset(transfer.data) or 0:]
            command = frame[5] if len(frame) > 5 else -1
            address = (frame[6] << 8) | frame[7] if len(frame) > 7 else -1
            print(
                f"  +{transfer.ts - first:8.3f}s len={transfer.length} "
                f"cmd=0x{command:02x} addr=0x{address:04x}",
                file=out,
            )


def print_timeline(transfers: list[Transfer], out) -> None:
    if not transfers:
        return
    first = transfers[0].ts
    print("\n=== 时间线（每笔完成事件） ===", file=out)
    for transfer in transfers:
        mark = " " if transfer.ok else "!"
        print(
            f"{mark}+{transfer.ts - first:9.3f}s {transfer.endpoint:12s} "
            f"st={transfer.status:4d} len={transfer.length:3d} "
            f"{describe_stc(transfer.data)}",
            file=out,
        )


def selftest() -> int:
    """用构造的 usbmon 片段校验解析与解帧逻辑（不依赖真机）。"""
    sample = "\n".join(
        [
            "ffff8f0d0e4c1c00 3492278480.123456 C Ii:3:006:1 0:8 64 = "
            + "46b9680010010070".ljust(128, "0"),
            "ffff8f0d0e4c1c00 3492278480.223456 C Io:3:006:1 0:8 64 = "
            + "46b96a008b32".ljust(128, "0"),
            "ffff8f0d0e4c1c00 3492278480.323456 C Io:3:006:1 -71 0",
            "ffff8f0d0e4c1c00 3492278480.423456 S Io:3:006:1 0 64",
        ]
    )
    path = "/tmp/usbmon-selftest.txt"
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(sample + "\n")
    transfers = parse(path)
    assert len(transfers) == 3, transfers
    assert transfers[0].direction == "in" and transfers[0].length == 64
    assert transfers[1].data[:2] == b"\x46\xb9"
    assert not transfers[2].ok and transfers[2].status == -71
    assert "STC mcu" in describe_stc(transfers[0].data)
    assert "STC host" in describe_stc(transfers[1].data)
    assert stc_offset(b"\x00\x46\xb9\x6a") == 1
    print("selftest 通过：3 笔完成事件（含一笔 -71）解析正确")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="解析 usbmon 文本抓包的 STC USB-ISP 时间线")
    parser.add_argument("capture", nargs="?", help="usbmon 文本文件（如 /tmp/usbmon-3u.txt）")
    parser.add_argument("--device", help="只看某个端点前缀，例如 Io:3:6")
    parser.add_argument("--timeline", action="store_true", help="打印逐笔时间线")
    parser.add_argument("--selftest", action="store_true", help="用内置样本自检解析逻辑")
    args = parser.parse_args()
    if args.selftest:
        return selftest()
    if not args.capture:
        parser.error("需要给出 usbmon 文本文件（或用 --selftest）")
    transfers = parse(args.capture)
    if args.device:
        transfers = [t for t in transfers if t.endpoint.startswith(args.device)]
    if not transfers:
        print("没解析到传输：确认抓的是板子所在总线（/sys/kernel/debug/usb/usbmon/<N>u）", file=sys.stderr)
        return 2
    summarize(transfers, sys.stdout)
    if args.timeline:
        print_timeline(transfers, sys.stdout)
    return 0


if __name__ == "__main__":
    sys.exit(main())

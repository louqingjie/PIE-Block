#!/usr/bin/env python3
"""linux_hidraw_flash.py - Linux 免依赖 hidraw 烧录器（诊断 + 断点续烧）。

仓库原有的 Python 烧录器（pie_block_hid.py）走 hidapi，只在 Windows 真机验证过；
Linux 端只有应用内的 hidraw 传输层，出了问题要重新构建才能复测。本脚本直接用
/dev/hidraw* + ioctl 说话，零第三方依赖，用来：

1. **做受控实验**：报告间隔、写重试窗口、起始块都能从命令行调，用来区分
   「跟时间/块数有关的墙」和「跟应用特有的传输实现有关的墙」；
2. **断点续烧**：设备在写到一半时沉默后，断电重新上电进 ISP，用
   `--no-erase --start-block N` 从断点继续，已写入的块不会被擦掉；
3. **探活**：`--probe-only` 只发 info，判断板子当前是否还在 ISP 并且会回话。

协议（严格对齐 packages/pieblock_hid/lib/src/protocol.dart 与
stc32g/toolchain/stcflash/HID_PROTOCOL.md）：

    帧 = 46 B9 6A <len_hi> <len_lo> <payload> <csum_hi> <csum_lo> 16
    141 字节写帧拆成 64/64/13 三份报告，每份前面补 report ID 槽 0x00
    info   [01 00 00 00 00 00 00 80 00]   -> 01
    unlock [05 00 00 5a a5]               -> 05
    erase  [03 00 00 5a a5]               -> 03
    首块   [32 <addr2> 5a a5 <128B>]      -> 02 54
    后续块 [12 <addr2> 5a a5 <128B>]      -> 02 54
    0xFF0000 区 [02 <addr2> 5a a5 <128B>] -> 02 54
    复位   [ff]

用法：
    # 只看板子在不在、回不回话（只读，不发任何破坏性命令）
    python3 linux_hidraw_flash.py --probe-only

    # 打印烧录计划（不发任何 USB 数据，可与 dump_block_plan.dart 对拍）
    python3 linux_hidraw_flash.py firmware.hex --dry-run

    # 完整烧录（--erase 必须显式给，否则只在保护已有内容的前提下续写）
    python3 linux_hidraw_flash.py firmware.hex --erase

    # 断点续烧：断电重新上电进 ISP 后，从第 129 块（0-based 索引）继续
    python3 linux_hidraw_flash.py firmware.hex --no-erase --start-block 129
"""
from __future__ import annotations

import argparse
import fcntl
import glob
import hashlib
import os
import select
import struct
import sys
import time

VID = 0x34BF
PID = 0x1001
REPORT_SIZE = 64
BLOCK_SIZE = 128
CODE_BASE = 0xFE0000
HIGH_BASE = 0xFF0000
HIDIOCGRAWINFO = 0x80084803  # _IOR('H', 0x03, struct hidraw_devinfo)

PACKET_START = bytes([0x46, 0xB9])
PACKET_HOST = bytes([0x6A])
PACKET_MCU = bytes([0x68])
PACKET_END = bytes([0x16])


def log(message: str) -> None:
    print(message, flush=True)


def build_packet(payload: bytes) -> bytes:
    packet = PACKET_START + PACKET_HOST
    packet += struct.pack(">H", len(payload) + 6)
    packet += payload
    packet += struct.pack(">H", sum(packet[2:]) & 0xFFFF)
    packet += PACKET_END
    return packet


def split_reports(packet: bytes) -> list[bytes]:
    """与 protocol.dart 的 splitReports 一致：每份报告 = 0x00 + 最多 64 字节。"""
    reports = []
    for offset in range(0, len(packet), REPORT_SIZE):
        chunk = packet[offset:offset + REPORT_SIZE]
        wire = b"\x00" + chunk
        if len(wire) < REPORT_SIZE:
            wire += b"\x00" * (REPORT_SIZE - len(wire))
        reports.append(wire)
    return reports


def find_device() -> str | None:
    """枚举 /dev/hidraw*，返回匹配 STC USB-ISP 的节点路径。"""
    matches = []
    for path in sorted(glob.glob("/dev/hidraw*")):
        try:
            fd = os.open(path, os.O_RDONLY)
        except OSError:
            continue
        try:
            info = bytearray(8)
            fcntl.ioctl(fd, HIDIOCGRAWINFO, info, True)
            _, vendor, product = struct.unpack("=IHH", bytes(info))
            if vendor == VID and product == PID:
                matches.append(path)
        except OSError:
            pass
        finally:
            os.close(fd)
    return matches[0] if len(matches) == 1 else None


def load_hex(path: str) -> dict[int, int]:
    memory: dict[int, int] = {}
    base = 0
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line.startswith(":"):
                continue
            count = int(line[1:3], 16)
            address = int(line[3:7], 16)
            kind = int(line[7:9], 16)
            data = bytes.fromhex(line[9:9 + 2 * count])
            if kind == 0:
                for index, value in enumerate(data):
                    memory[base + address + index] = value
            elif kind == 4:
                base = int.from_bytes(data, "big") << 16
            elif kind == 2:
                base = int.from_bytes(data, "big") << 4
    return memory


def build_blocks(memory: dict[int, int]) -> list[tuple[int, int, bytes]]:
    """返回 [(cmd, isp_addr, 128B data)]，与 Dart 的 buildWriteBlocks 同规则。"""
    user: dict[int, bytearray] = {}
    high: dict[int, bytearray] = {}
    for address in sorted(memory):
        if address >= HIGH_BASE:
            target, base = high, HIGH_BASE
        else:
            target, base = user, CODE_BASE
        relative = address - base
        if relative < 0 or relative >= 0x10000:
            raise SystemExit(f"HEX 地址 0x{address:06x} 无法映射到 ISP 地址")
        block = target.setdefault(relative // BLOCK_SIZE, bytearray(BLOCK_SIZE))
        block[relative % BLOCK_SIZE] = memory[address]
    blocks: list[tuple[int, int, bytes]] = []
    for index, key in enumerate(sorted(user)):
        blocks.append((0x32 if index == 0 else 0x12, key * BLOCK_SIZE, bytes(user[key])))
    for key in sorted(high):
        blocks.append((0x02, key * BLOCK_SIZE, bytes(high[key])))
    return blocks


class Session:
    """一次 ISP 会话：打开节点、按需读写报告。"""

    def __init__(self, path: str, report_gap_ms: float, write_retry_ms: float):
        self.path = path
        self.report_gap = report_gap_ms / 1000.0
        self.write_retry = write_retry_ms / 1000.0
        self.fd = os.open(path, os.O_RDWR)

    def close(self) -> None:
        if self.fd >= 0:
            os.close(self.fd)
            self.fd = -1

    def write_report(self, wire: bytes) -> None:
        """写一份报告；设备忙（-EBUSY）时在有界窗口内退让重试，与 Windows
        侧 pb_hid_write 的 2000ms 等待、以及应用内 hidraw 实现保持一致。"""
        deadline = time.monotonic() + self.write_retry
        while True:
            try:
                written = os.write(self.fd, wire)
                if written == len(wire):
                    return
                raise OSError(f"只写入 {written} 字节")
            except OSError as error:
                if time.monotonic() >= deadline:
                    raise
                time.sleep(0.001)

    def read_report(self, timeout_ms: int) -> bytes | None:
        poller = select.poll()
        poller.register(self.fd, select.POLLIN)
        if not poller.poll(timeout_ms):
            return None
        try:
            return os.read(self.fd, REPORT_SIZE) or None
        except OSError:
            return None

    def send_frame(self, payload: bytes, timeout_ms: int = 3000) -> bytes | None:
        packet = build_packet(payload)
        for index, report in enumerate(split_reports(packet)):
            if index and self.report_gap > 0:
                time.sleep(self.report_gap)
            self.write_report(report)
        return self.read_report(timeout_ms)

    def expect_ack(self, payload: bytes, label: str, command: int,
                   timeout_ms: int = 3000, expect: int | None = None) -> bytes:
        response = self.send_frame(payload, timeout_ms)
        if not response:
            raise TimeoutError(f"{label}：设备无响应")
        if len(response) < 6 or response[:3] != PACKET_START + PACKET_MCU:
            raise RuntimeError(f"{label}：响应帧头异常 {response[:8].hex(' ')}")
        if response[5] != command:
            raise RuntimeError(f"{label}：响应命令异常 {response[:8].hex(' ')}")
        if expect is not None and (len(response) < 7 or response[6] != expect):
            raise RuntimeError(f"{label}：响应不是 {expect:02x} {response[:8].hex(' ')}")
        return response


INFO = bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00])
UNLOCK = bytes([0x05, 0x00, 0x00, 0x5A, 0xA5])
ERASE = bytes([0x03, 0x00, 0x00, 0x5A, 0xA5])


def probe_only(args: argparse.Namespace) -> int:
    path = find_device()
    if path is None:
        log("未找到处于 ISP 模式的主控板（VID 34BF / PID 1001）")
        return 2
    session = Session(path, args.report_gap_ms, args.write_retry_ms)
    started = time.monotonic()
    try:
        session.expect_ack(INFO, "info", 0x01, args.timeout_ms)
        log(f"{path}: info 正常，用时 {(time.monotonic() - started) * 1000:.0f}ms")
        return 0
    except Exception as error:  # noqa: BLE001 - 诊断脚本，任何失败都要打印
        log(f"{path}: info 失败（{(time.monotonic() - started) * 1000:.0f}ms）：{error}")
        return 3
    finally:
        session.close()


def dry_run(blocks: list[tuple[int, int, bytes]]) -> int:
    for index, (command, address, data) in enumerate(blocks):
        digest = hashlib.sha1(data).hexdigest()
        log(f"{index} {command:02x} {address:04x} {digest}")
    log(f"# 共 {len(blocks)} 块")
    return 0


def flash(args: argparse.Namespace, blocks: list[tuple[int, int, bytes]]) -> int:
    path = find_device()
    if path is None:
        log("未找到处于 ISP 模式的主控板（VID 34BF / PID 1001）：请断电几秒后重新上电")
        return 2
    session = Session(path, args.report_gap_ms, args.write_retry_ms)
    log(f"设备 {path}：报告间隔 {args.report_gap_ms}ms，写重试窗口 {args.write_retry_ms}ms")
    started = time.monotonic()
    written = 0
    try:
        session.expect_ack(INFO, "info", 0x01, args.timeout_ms)
        log(f"[{time.monotonic() - started:6.2f}s] info OK")
        session.expect_ack(UNLOCK, "unlock", 0x05, args.timeout_ms)
        log(f"[{time.monotonic() - started:6.2f}s] unlock OK")
        if args.erase:
            session.expect_ack(ERASE, "erase", 0x03, args.timeout_ms)
            log(f"[{time.monotonic() - started:6.2f}s] erase OK")
        else:
            log("跳过 erase（--no-erase）：只续写，不擦除已有内容")
        for index in range(args.start_block, len(blocks)):
            if args.limit and written >= args.limit:
                log(f"已达 --limit {args.limit}，停在块索引 {index}")
                break
            command, address, data = blocks[index]
            label = f"块 {index} @0x{address:04x}"
            session.expect_ack(
                bytes([command, (address >> 8) & 0xFF, address & 0xFF, 0x5A, 0xA5]) + data,
                label, 0x02, args.timeout_ms, expect=0x54,
            )
            written += 1
            if written % 25 == 0 or index + 1 == len(blocks) or args.limit:
                rate = written / max(time.monotonic() - started, 1e-6)
                log(
                    f"[{time.monotonic() - started:6.2f}s] {index + 1}/{len(blocks)} "
                    f"{label} 写入中（{rate:.0f} 块/秒）"
                )
        if args.reset:
            for report in split_reports(build_packet(bytes([0xFF]))):
                session.write_report(report)
            log("已发送复位")
        log(f"完成：写入 {written} 块，用时 {time.monotonic() - started:.2f}s")
        return 0
    except Exception as error:  # noqa: BLE001 - 诊断脚本，任何失败都要打印
        elapsed = time.monotonic() - started
        log(f"[{elapsed:6.2f}s] 中断：{type(error).__name__}: {error}")
        log(f"已写入 {written} 块（下一个待写块索引约为 {args.start_block + written}）")
        _diagnose_reopen(path, args)
        log(
            "续烧：给主控板断电几秒后重新上电（保持 ISP），再执行\n"
            f"  python3 {os.path.basename(__file__)} {args.hex} "
            f"--no-erase --start-block {args.start_block + written}"
        )
        return 3
    finally:
        session.close()


def _diagnose_reopen(path: str, args: argparse.Namespace) -> None:
    """关掉句柄重开一次再发 info：区分「设备已经不在总线上/不回应」与
    「只是这条 hidraw 会话的管道卡住」。"""
    log("诊断：关闭并重开 hidraw 会话后重试 info…")
    try:
        session = Session(path, args.report_gap_ms, args.write_retry_ms)
    except OSError as error:
        log(f"  重开失败：{error}（设备可能已重新枚举或掉线）")
        return
    try:
        started = time.monotonic()
        session.expect_ack(INFO, "info", 0x01, args.timeout_ms)
        log(f"  重开后 info 成功（{(time.monotonic() - started) * 1000:.0f}ms）："
            "设备仍在 ISP，只是原会话的管道卡住了")
    except Exception as error:  # noqa: BLE001
        log(f"  重开后 info 仍失败：{error}（设备已不响应，需要断电重新上电）")
    finally:
        session.close()


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Linux 免依赖 hidraw 烧录器（诊断 + 断点续烧）",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("hex", nargs="?", help="待烧录的 Intel HEX")
    parser.add_argument("--probe-only", action="store_true", help="只发 info 探活")
    parser.add_argument("--dry-run", action="store_true", help="只打印烧录计划")
    parser.add_argument("--erase", action="store_true", help="烧录前擦除程序区（破坏性，需显式给出）")
    parser.add_argument("--start-block", type=int, default=0, help="从第 N 块开始（断点续烧）")
    parser.add_argument("--limit", type=int, default=0, help="最多写 N 块后停下")
    parser.add_argument("--reset", action="store_true", help="写完后发送复位")
    parser.add_argument("--report-gap-ms", type=float, default=1.0, help="帧内报告间隔（默认 1，同应用）")
    parser.add_argument("--write-retry-ms", type=float, default=2000.0, help="写报告忙重试窗口（默认 2000，同应用）")
    parser.add_argument("--timeout-ms", type=int, default=3000, help="读响应超时（默认 3000，同应用）")
    args = parser.parse_args()

    if args.probe_only:
        return probe_only(args)
    if not args.hex:
        parser.error("需要给出 HEX 路径（或使用 --probe-only）")
    args.hex = os.path.abspath(args.hex)
    if not os.path.isfile(args.hex):
        log(f"HEX 不存在：{args.hex}")
        return 4
    blocks = build_blocks(load_hex(args.hex))
    if args.dry_run:
        return dry_run(blocks)
    return flash(args, blocks)


if __name__ == "__main__":
    sys.exit(main())

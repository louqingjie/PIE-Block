#!/usr/bin/env python3
"""pie_block_hid.py - STC32G USB-HID 一键烧录（不依赖 STC-ISP / CH340 / stcgal）

通过标准 USB-HID 与 STC32G ROM bootloader 通信（VID 0x34BF, PID 0x1001, "USB-ISP"）。
协议（实测验证 2026-08-07）：
  帧 = 0x46 0xB9 0x6A(host)/0x68(MCU) + 2字节长度 + payload + 2字节和校验(sum&0xffff) + 0x16
  命令：
    info   [0x01 0x00 0x00 0x00 0x00 0x00 0x00 0x80 0x00]      -> ACK 01 00 70
    unlock [0x05 0x00 0x00 0x5a 0xa5]                           -> ACK 05 00 74
    erase  [0x03 0x00 0x00 0x5a 0xa5]                           -> 03 <UID>
    写首块 [0x32 <addr2> 0x5a 0xa5 <128B>]                      -> 02 54
    写后续 [0x12 <addr2> 0x5a 0xa5 <128B>]                      -> 02 54
    复位   [0xFF]                                               -> 无响应（设备复位跑 App）
  大帧拆成多个 64 字节 HID 报告发送，设备按帧长度字段重组。

用法：
  python pie_block_hid.py <hex> [--no-reset] [--dry-run]
返回：0 成功 / 1 用法错误 / 2 设备未找到 / 3 烧录失败
"""
from __future__ import annotations

import os
import struct
import sys
import time

from hid_loader import ensure_hidapi_available

ensure_hidapi_available()
import hid  # noqa: E402

VID = 0x34BF
PID = 0x1001

PACKET_START = bytes([0x46, 0xB9])
PACKET_END = bytes([0x16])
PACKET_HOST = bytes([0x6A])
PACKET_MCU = bytes([0x68])

BLOCK_SIZE = 128


def _fix_stdio() -> None:
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def _p(msg: str) -> None:
    try:
        print(msg, flush=True)
    except UnicodeEncodeError:
        print(msg.encode("gbk", errors="replace").decode("gbk", errors="replace"), flush=True)


def build_packet(packet_data: bytes) -> bytes:
    p = PACKET_START + PACKET_HOST
    p += struct.pack(">H", len(packet_data) + 6)
    p += packet_data
    p += struct.pack(">H", sum(p[2:]) & 0xFFFF)
    p += PACKET_END
    return p


def hexstr(b: bytes) -> str:
    return " ".join("%02x" % x for x in b)


class HidFlasher:
    def __init__(self):
        self.h = None

    def open(self) -> bool:
        try:
            self.h = hid.Device(VID, PID)
        except Exception:
            return False
        return True

    def _read(self, timeout_ms: int = 1500) -> bytes | None:
        try:
            d = self.h.read(64, timeout_ms)
            return d if d else None
        except hid.HIDException:
            return None

    def send_frame(self, pkt: bytes, timeout_ms: int = 3000) -> bytes | None:
        """把完整帧拆成 64 字节 HID 报告发送，返回设备响应（或 None）。"""
        n_reports = (len(pkt) + 63) // 64
        for i in range(n_reports):
            chunk = pkt[i * 64:(i + 1) * 64]
            wire = b"\x00" + chunk
            if len(wire) < 64:
                wire += b"\x00" * (64 - len(wire))
            self.h.write(wire)
            # 报告间仅留 1ms 余量：USB HID 中断端点自带流控（设备忙时 NAK，
            # 主机自动重试），不需要 30ms 级的节流；官方 ISP 即连续发送。
            time.sleep(0.001)
        return self._read(timeout_ms)

    def _expect_ack(self, pkt: bytes, label: str, timeout_ms: int = 3000) -> bytes:
        resp = self.send_frame(pkt, timeout_ms)
        if not resp:
            raise RuntimeError("%s: 无响应（超时）" % label)
        # 校验帧头
        if resp[0] != 0x46 or resp[1] != 0xB9 or resp[2] != 0x68:
            raise RuntimeError("%s: 帧头异常: %s" % (label, hexstr(resp[:8])))
        return resp

    def info(self) -> bytes:
        pkt = build_packet(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]))
        resp = self._expect_ack(pkt, "info")
        # 期望 payload: 01 00 70
        if len(resp) < 9 or resp[5] != 0x01:
            raise RuntimeError("info 响应异常: %s" % hexstr(resp[:12]))
        return resp

    def unlock(self) -> None:
        pkt = build_packet(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5]))
        resp = self._expect_ack(pkt, "unlock")
        if resp[5] != 0x05:
            raise RuntimeError("unlock 响应异常: %s" % hexstr(resp[:12]))

    def erase(self) -> bytes:
        pkt = build_packet(bytes([0x03, 0x00, 0x00, 0x5a, 0xa5]))
        resp = self._expect_ack(pkt, "erase", 3000)
        if resp[5] != 0x03:
            raise RuntimeError("erase 响应异常: %s" % hexstr(resp[:12]))
        return resp

    def write_block(self, addr: int, data: bytes, cmd: int = 0x12) -> None:
        """写一个 128 字节块。cmd: 0x32=用户区首块, 0x12=用户区后续, 0x02=0xFF0000 区块。"""
        if addr > 0xFFFF:
            raise RuntimeError("地址 0x%X 超出 2 字节范围" % addr)
        if len(data) < BLOCK_SIZE:
            data = data + b"\xff" * (BLOCK_SIZE - len(data))
        payload = bytes([cmd, (addr >> 8) & 0xFF, addr & 0xFF, 0x5a, 0xa5]) + data[:BLOCK_SIZE]
        pkt = build_packet(payload)
        resp = self.send_frame(pkt)
        if not resp:
            raise RuntimeError("写块 @0x%04X 无响应" % addr)
        # 成功响应 payload: 02 54 ...
        if resp[5] != 0x02 or resp[6] != 0x54:
            raise RuntimeError("写块 @0x%04X 失败: %s" % (addr, hexstr(resp[:12])))

    def set_options(self, payload: bytes) -> None:
        """设置选项（cmd 0x04）。payload 为完整选项数据。"""
        pkt = build_packet(payload)
        resp = self.send_frame(pkt)
        if not resp:
            raise RuntimeError("set_options 无响应")
        if resp[5] != 0x04 or resp[6] != 0x54:
            raise RuntimeError("set_options 失败: %s" % hexstr(resp[:12]))

    def reset(self) -> None:
        """复位设备（0xFF），让其运行新固件。无响应。"""
        pkt = build_packet(bytes([0xFF]))
        n_reports = (len(pkt) + 63) // 64
        for i in range(n_reports):
            chunk = pkt[i * 64:(i + 1) * 64]
            wire = b"\x00" + chunk
            if len(wire) < 64:
                wire += b"\x00" * (64 - len(wire))
            self.h.write(wire)
        # 复位后设备可能断开重枚举，不等待响应
        time.sleep(0.2)

    def close(self):
        if self.h:
            try:
                self.h.close()
            except Exception:
                pass


def load_hex(path: str):
    """解析 Intel HEX，返回 {地址: 字节} 字典 和 最小地址。"""
    from intelhex import IntelHex

    ih = IntelHex(path)
    data = {}
    for a in ih.addresses():
        data[a] = ih[a]
    return data, ih.minaddr()


# STC32G 用户代码区基址：ISP 写地址 = hex地址 - CODE_BASE（用 cmd 0x32/0x12）
CODE_BASE = 0xFE0000
# 0xFF0000 区（bootloader/保留数据）：用 cmd 0x02 写，地址 = hex地址 - 0xFF0000
HIGH_BASE = 0xFF0000


def build_write_blocks(data: dict, minaddr: int):
    """根据 hex 地址生成 (isp_addr, data128, cmd) 写块列表。

    0xFE0000 段（用户代码）→ cmd 0x32(首块)/0x12(后续)，isp_addr = addr - CODE_BASE
    0xFF0000 段 → cmd 0x02，isp_addr = addr - HIGH_BASE
    0x0000 基址 hex（如 pie_bootloader.hex）→ 直接用原地址 cmd 0x32/0x12
    返回 (blocks, total_bytes)
    """
    if minaddr >= CODE_BASE:
        # 分两个区
        user_blocks = {}   # isp_addr -> bytearray
        high_blocks = {}   # isp_addr -> bytearray
        for addr in sorted(data):
            if CODE_BASE <= addr < HIGH_BASE:
                isp = addr - CODE_BASE
                blk = isp // BLOCK_SIZE
                user_blocks.setdefault(blk, bytearray(BLOCK_SIZE))
                user_blocks[blk][isp % BLOCK_SIZE] = data[addr]
            elif addr >= HIGH_BASE:
                isp = addr - HIGH_BASE
                blk = isp // BLOCK_SIZE
                high_blocks.setdefault(blk, bytearray(BLOCK_SIZE))
                high_blocks[blk][isp % BLOCK_SIZE] = data[addr]

        blocks = []
        user_blks = sorted(user_blocks)
        for i, blk in enumerate(user_blks):
            cmd = 0x32 if i == 0 else 0x12
            blocks.append((blk * BLOCK_SIZE, bytes(user_blocks[blk]), cmd))
        for blk in sorted(high_blocks):
            blocks.append((blk * BLOCK_SIZE, bytes(high_blocks[blk]), 0x02))

        total = sum(len(d) for _, d, _ in blocks)
        return blocks, total
    else:
        # 0x0000 基址 hex：直接顺序填块 cmd 0x32/0x12
        items = sorted(data.items())
        blkmap = {}
        for addr, b in items:
            blk = addr // BLOCK_SIZE
            blkmap.setdefault(blk, bytearray(BLOCK_SIZE))
            blkmap[blk][addr % BLOCK_SIZE] = b
        blocks = []
        for i, blk in enumerate(sorted(blkmap)):
            cmd = 0x32 if i == 0 else 0x12
            blocks.append((blk * BLOCK_SIZE, bytes(blkmap[blk]), cmd))
        total = sum(len(d) for _, d, _ in blocks)
        return blocks, total



def flash(hex_file: str, do_reset: bool) -> int:
    if not os.path.isfile(hex_file):
        _p("错误：hex 不存在: %s" % hex_file)
        return 4

    data, start = load_hex(hex_file)
    _p("Loading flash: %d bytes (Intel HEX, start=0x%X)" % (len(data), start))

    f = HidFlasher()
    if not f.open():
        _p("错误：未找到 STC USB-HID 设备 (VID=%04X PID=%04X)。请确认板子处于 ISP 模式（上电冷启动）。"
           % (VID, PID))
        return 2

    _p("Device: %r / %r" % (f.h.manufacturer, f.h.product))

    try:
        f.info()
        _p("info OK")
        f.unlock()
        _p("unlock OK")
        uid = f.erase()
        # erase 响应 payload: 03 <UID 7B> <2B>；从第 6 字节起 7 字节是 UID
        uid7 = uid[6:13]
        _p("erase OK, UID=%s" % hexstr(uid7))

        blocks, total = build_write_blocks(data, start)
        _p("Writing %d bytes in %d blocks..." % (total, len(blocks)))
        first_written = False
        for idx, (isp_addr, chunk, cmd) in enumerate(blocks):
            if isp_addr + BLOCK_SIZE > 0x10000:
                raise RuntimeError("写地址 0x%X 超出 2 字节范围" % isp_addr)
            # 用户区首块用 0x32，其余 0x12；0xFF0000 区用 0x02
            f.write_block(isp_addr, chunk, cmd=cmd)
            first_written = True
            if (idx + 1) % 25 == 0 or idx + 1 == len(blocks):
                _p("  block %d/%d @0x%04X (cmd=0x%02x)" % (idx + 1, len(blocks), isp_addr, cmd))

        _p("烧录成功（%d bytes, %d blocks）" % (total, len(blocks)))

        if do_reset:
            _p("resetting...")
            f.reset()
            _p("已复位，设备应运行新固件")
        return 0
    except Exception as exc:
        _p("烧录失败: %s: %s" % (type(exc).__name__, exc))
        return 3
    finally:
        f.close()


def main() -> int:
    _fix_stdio()
    if len(sys.argv) < 2:
        _p("用法: python pie_block_hid.py <hex> [--no-reset]")
        return 1
    hex_file = sys.argv[1]
    do_reset = "--no-reset" not in sys.argv
    return flash(hex_file, do_reset)


if __name__ == "__main__":
    sys.exit(main())

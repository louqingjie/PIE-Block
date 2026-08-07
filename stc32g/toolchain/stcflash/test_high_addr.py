#!/usr/bin/env python3
"""test_high_addr.py - 测试 >64KB 高地址写命令的编码方式。

STC32G 有 128KB flash（0x00000~0x1FFFF）。测向地址 0x10000 写一个 128B 块，
尝试多种地址字段编码，看哪种返回成功响应 02 54。
注意：每轮测试前先 info 确认设备存活；若失败可能需重新上电。
"""
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


def build_packet(packet_data: bytes) -> bytes:
    p = PACKET_START + PACKET_HOST
    p += struct.pack(">H", len(packet_data) + 6)
    p += packet_data
    p += struct.pack(">H", sum(p[2:]) & 0xFFFF)
    p += PACKET_END
    return p


def hexstr(b) -> str:
    return " ".join("%02x" % x for x in b)


def safe_read(h, size, timeout_ms):
    try:
        d = h.read(size, timeout_ms)
        return d if d else None
    except hid.HIDException:
        return None


def send_frame(h, pkt: bytes, timeout_ms=3000):
    n_reports = (len(pkt) + 63) // 64
    for i in range(n_reports):
        chunk = pkt[i * 64:(i + 1) * 64]
        wire = b"\x00" + chunk
        if len(wire) < 64:
            wire += b"\x00" * (64 - len(wire))
        h.write(wire)
        time.sleep(0.03)
    return safe_read(h, 64, timeout_ms)


def main():
    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    # info 确认存活
    r = send_frame(h, build_packet(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00])))
    print("info -> %s" % (hexstr(r) if r else "<timeout>"))
    if not r:
        print("device not alive; need re-power")
        h.close()
        return
    r = send_frame(h, build_packet(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5])))
    print("unlock -> %s" % (hexstr(r) if r else "<timeout>"))

    addr = 0x10000  # 64KB 之外
    data = bytes([0xBB]) * 128

    # 尝试 1: 3 字节地址字段（cmd, a2, a1, a0, 5a, a5）
    payload1 = bytes([0x32, (addr >> 16) & 0xFF, (addr >> 8) & 0xFF, addr & 0xFF, 0x5a, 0xa5]) + data
    r = send_frame(h, build_packet(payload1))
    print("try1 (3B addr 0x010000): %s" % (hexstr(r) if r else "<timeout>"))

    # 尝试 2: 2 字节地址 = (addr>>16) 做高字节，低字节 0？即 0x01 00 表示 0x10000 的页+偏移
    # 更可能: 地址字段仍是 2 字节 = addr & 0xffff，但先发一个"设高地址"命令
    # 尝试 2: 2字节地址字段 = (addr-0x10000)=0（低64K内偏移0），看是否仍是 0x10000
    payload2 = bytes([0x12, (addr >> 8) & 0xFF, addr & 0xFF, 0x5a, 0xa5]) + data  # 00 00 -> addr 0
    r = send_frame(h, build_packet(payload2))
    print("try2 (2B addr=0x0000): %s" % (hexstr(r) if r else "<timeout>"))

    h.close()


if __name__ == "__main__":
    main()

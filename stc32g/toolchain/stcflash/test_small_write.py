#!/usr/bin/env python3
"""test_small_write.py - 测试：把写命令做成塞进单个 64 字节报告的完整 STC 帧。

假设 H3：HID 版每次写一个完整 STC 帧（单报告），数据量 ≤ ~48 字节；
128 字节 flash 块分多次写（或 HID 版块大小更小）。
帧 payload = cmd(1) + addr(2) + magic 5a a5(2) + data(N)
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


def main():
    data_n = int(sys.argv[1]) if len(sys.argv) > 1 else 48
    first = "--first" in sys.argv

    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    def send(payload, label, timeout=1500):
        pkt = build_packet(payload)
        wire = b"\x00" + pkt
        if len(wire) < 64:
            wire += b"\x00" * (64 - len(wire))
        n = h.write(wire)
        d = safe_read(h, 64, timeout)
        print("%s: frame=%d wire=%d wrote=%d -> %s"
              % (label, len(pkt), len(wire), n, hexstr(d) if d else "<timeout>"))
        return d

    send(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]), "info")
    send(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5]), "unlock")
    send(bytes([0x03, 0x00, 0x00, 0x5a, 0xa5]), "erase", 2000)

    # 写命令：cmd(0x32 首包 / 0x12 后续) + 地址 + 5a a5 + N 字节数据
    data = bytes([0xAA]) * data_n
    cmd = 0x32 if first else 0x12
    payload = bytes([cmd, 0x00, 0x00, 0x5a, 0xa5]) + data
    send(payload, "write(N=%d,cmd=0x%02x)" % (data_n, cmd), 3000)

    h.close()


if __name__ == "__main__":
    main()

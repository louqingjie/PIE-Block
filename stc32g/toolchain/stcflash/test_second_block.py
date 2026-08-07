#!/usr/bin/env python3
"""test_second_block.py - 验证后续块的写命令字节与地址编码。

测：首块(0x32@0x0000) 之后，第二块地址 0x0080，分别试 cmd=0x12 / 0x02，
看哪个返回成功响应 02 54。
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


def send_frame_multi(h, pkt: bytes, label: str, timeout=3000):
    """把完整帧拆成 64 字节报告发送。返回响应。"""
    n_reports = (len(pkt) + 63) // 64
    for i in range(n_reports):
        chunk = pkt[i * 64:(i + 1) * 64]
        wire = b"\x00" + chunk
        if len(wire) < 64:
            wire += b"\x00" * (64 - len(wire))
        h.write(wire)
        time.sleep(0.03)
    d = safe_read(h, 64, timeout)
    print("%s (frame=%dB, %d reports) -> %s"
          % (label, len(pkt), n_reports, hexstr(d) if d else "<timeout>"))
    return d


def main():
    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    send_frame_multi(h, build_packet(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00])), "info")
    send_frame_multi(h, build_packet(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5])), "unlock")
    send_frame_multi(h, build_packet(bytes([0x03, 0x00, 0x00, 0x5a, 0xa5])), "erase", 2000)

    # 首块 @0x0000
    data1 = bytes([0x11]) * 128
    send_frame_multi(h, build_packet(bytes([0x32, 0x00, 0x00, 0x5a, 0xa5]) + data1), "first 0x32 @0x0000")

    # 第二块 @0x0080：试 0x12
    data2 = bytes([0x22]) * 128
    send_frame_multi(h, build_packet(bytes([0x12, 0x00, 0x80, 0x5a, 0xa5]) + data2), "second 0x12 @0x0080")

    h.close()


if __name__ == "__main__":
    main()

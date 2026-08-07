#!/usr/bin/env python3
"""test_multi_report_write.py - 测试：完整写帧拆成多个 64 字节报告发送，设备按长度字段重组。

假设：设备收到含长度字段的帧头后，会累计后续 64 字节报告直到凑够长度，再处理该帧。
本次实验：info -> unlock -> erase -> 把 141 字节写帧拆成 3 个报告(64/64/13)发送 -> 读响应。
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


def send_report(h, chunk: bytes):
    wire = b"\x00" + chunk
    if len(wire) < 64:
        wire += b"\x00" * (64 - len(wire))
    h.write(wire)


def main():
    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    def one(payload, label, timeout=1500):
        pkt = build_packet(payload)
        wire = b"\x00" + pkt
        if len(wire) < 64:
            wire += b"\x00" * (64 - len(wire))
        h.write(wire)
        d = safe_read(h, 64, timeout)
        print("%s -> %s" % (label, hexstr(d) if d else "<timeout>"))
        return d

    # 1) info
    if not one(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]), "info"):
        print("no info; device not in ISP mode -> need re-power")
        h.close()
        return
    # 2) unlock
    one(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5]), "unlock")
    # 3) erase
    one(bytes([0x03, 0x00, 0x00, 0x5a, 0xa5]), "erase", 2000)

    # 4) 写帧：cmd 0x32(首) + 地址 + 5a a5 + 128 数据 = 141 字节帧
    data = bytes([0xAA]) * 128
    payload = bytes([0x32, 0x00, 0x00, 0x5a, 0xa5]) + data
    pkt = build_packet(payload)
    print("write frame len=%d, splitting into 64-byte reports:" % len(pkt))
    n_reports = (len(pkt) + 63) // 64
    for i in range(n_reports):
        chunk = pkt[i * 64:(i + 1) * 64]
        send_report(h, chunk)
        print("  report %d/%d: %d bytes" % (i + 1, n_reports, len(chunk)))
        time.sleep(0.03)
    d = safe_read(h, 64, 4000)
    print("write -> %s" % (hexstr(d) if d else "<timeout>"))

    h.close()


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""test_high_addr2.py - 聚焦测试 >64KB 高地址写编码。

目标：确定向 0x10000（64KB 外）写 128B 块的正确命令格式。
基于已验证格式：cmd + 地址 + 5a a5 + 数据；成功响应 = 02 54。
每轮前先 info 确认设备存活；失败可能导致设备复位，需重新上电。
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


def alive(h):
    r = send_frame(h, build_packet(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00])))
    return r is not None


def main():
    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    if not alive(h):
        print("device not alive; re-power needed")
        h.close()
        return
    print("info OK")
    send_frame(h, build_packet(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5])))
    print("unlock sent")

    data = bytes([0xCC]) * 128

    tests = [
        # (名称, payload构造)
        ("4B_addr 0x01 0x00 0x00 0x00", bytes([0x32, 0x01, 0x00, 0x00, 0x00, 0x5a, 0xa5]) + data),
        ("4B_addr 0x00 0x00 0x01 0x00", bytes([0x32, 0x00, 0x00, 0x01, 0x00, 0x5a, 0xa5]) + data),
        ("2B_addr 0x00 0x00 (wrap)", bytes([0x32, 0x00, 0x00, 0x5a, 0xa5]) + data),
        ("cmd0x30 3B 01 00 00", bytes([0x30, 0x01, 0x00, 0x00, 0x5a, 0xa5]) + data),
        ("cmd0x12 3B 01 00 00", bytes([0x12, 0x01, 0x00, 0x00, 0x5a, 0xa5]) + data),
    ]

    for name, payload in tests:
        if not alive(h):
            print("== device died after '%s'; stop ==" % name)
            break
        r = send_frame(h, build_packet(payload))
        ok = "OK" if (r and len(r) > 6 and r[5] == 0x02 and r[6] == 0x54) else "FAIL"
        print("%-24s -> %s %s" % (name, ok, hexstr(r[:12]) if r else "<timeout>"))

    h.close()


if __name__ == "__main__":
    main()

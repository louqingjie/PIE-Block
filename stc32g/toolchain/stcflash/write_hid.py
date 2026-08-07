#!/usr/bin/env python3
"""write_hid.py - 测试能否通过 h.write 一次发送 >64 字节的完整写命令帧。

假设：STC bootloader 固件接受多包中断 OUT 传输（按 USB FIFO 累计），
hidapi 的 Windows 后端把整个 buffer 交给 WriteFile，设备端按长度字段重组。
若成立，则 128 字节数据可直接在一个 h.write 里发完，无需抓包。
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
    h = hid.Device(VID, PID)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    # 1) info —— 确认状态
    pkt = build_packet(bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]))
    h.write(b"\x00" + pkt)
    d = safe_read(h, 64, 1500)
    print("info -> %s" % (hexstr(d) if d else "<timeout>"))
    if not d:
        print("no info response; aborting")
        h.close()
        sys.exit(1)

    # 2) unlock
    pkt = build_packet(bytes([0x05, 0x00, 0x00, 0x5a, 0xa5]))
    h.write(b"\x00" + pkt)
    d = safe_read(h, 64, 1500)
    print("unlock -> %s" % (hexstr(d) if d else "<timeout>"))

    # 3) erase
    pkt = build_packet(bytes([0x03, 0x00, 0x00, 0x5a, 0xa5]))
    h.write(b"\x00" + pkt)
    d = safe_read(h, 64, 1500)
    print("erase -> %s" % (hexstr(d) if d else "<timeout>"))

    # 4) 写 flash：128 字节数据，整帧一次 h.write（帧长约 141 字节）
    data = bytes([0x55]) * 128
    payload = bytes([0x32, 0x00, 0x00, 0x5a, 0xa5]) + data  # 首包 0x32 + 地址 + 5a a5 + 数据
    pkt = build_packet(payload)
    print("write frame len: %d" % len(pkt))
    try:
        n = h.write(b"\x00" + pkt)
        print("h.write returned %d (frame+1=%d)" % (n, len(pkt) + 1))
    except Exception as e:
        print("h.write failed: %s" % e)
        h.close()
        sys.exit(1)

    d = safe_read(h, 64, 3000)
    print("write -> %s" % (hexstr(d) if d else "<timeout>"))

    h.close()


if __name__ == "__main__":
    main()

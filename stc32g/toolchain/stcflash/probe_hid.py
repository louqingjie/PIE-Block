#!/usr/bin/env python3
"""probe_hid.py - Phase 1: 直连 STC32G USB-HID bootloader，验证协议。

用已知逆向协议（robinkrens gist）发 info 命令，dump 响应并校验帧格式。
帧(主机->设备): 0x46 0xB9 0x6A | 2字节长度 | payload | 2字节和校验(sum&0xffff) | 0x16
"""
import argparse
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
PACKET_MCU = bytes([0x68])
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


def parse_frame(d: bytes):
    if d[:2] == PACKET_START:
        print("  header: 0x46 0xB9 OK")
        if len(d) >= 3:
            who = d[2]
            print("  direction byte: 0x%02x (%s)"
                  % (who, "MCU->host" if who == 0x68 else ("host->MCU" if who == 0x6A else "?")))
        if len(d) >= 5:
            length = (d[3] << 8) | d[4]
            print("  length field: %d" % length)
            print("  trailing after header: %d bytes" % (len(d) - 5))
    else:
        print("  ! not an STC frame (no 0x46 0xB9)")


def safe_read(h, size, timeout_ms):
    """读取，超时/无数据时返回 None（该 hid 包把 hid_read_timeout 返回 0 抛成
    HIDException('Success')，这里统一当作无响应处理）。"""
    try:
        d = h.read(size, timeout_ms)
        return d if d else None
    except hid.HIDException:
        return None


def main():
    ap = argparse.ArgumentParser(description="Probe STC32G USB-HID bootloader")
    ap.add_argument("--no-write", action="store_true", help="只读不写，看设备是否主动推包")
    ap.add_argument("--write-mode", choices=["raw", "prefix", "full64"], default="raw",
                    help="写格式：raw=gist 原样 / prefix=加 0x00 report-id / full64=0x00+帧+补零到64")
    ap.add_argument("--skip-start", action="store_true", help="不发 start 命令，直接发 info")
    ap.add_argument("--timeout", type=int, default=1500, help="读超时 ms")
    ap.add_argument("--read-n", type=int, default=1, help="每条命令后连续读 N 个报告")
    args = ap.parse_args()

    try:
        h = hid.Device(VID, PID)  # 构造函数会自动 open
    except Exception as e:
        print("open failed: %s" % e)
        sys.exit(1)
    print("Manufacturer: %r" % h.manufacturer)
    print("Product:      %r" % h.product)
    print("Serial:       %r" % h.serial)

    if args.no_write:
        d = safe_read(h, 64, args.timeout)
        print("read(no write): %s" % (hexstr(d) if d else "<timeout>"))
        h.close()
        return

    cmds = [("info", bytes([0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x00]))]
    if not args.skip_start:
        cmds.insert(0, ("start", bytes([0x00, 0x00])))

    for name, payload in cmds:
        pkt = build_packet(payload)
        if args.write_mode == "raw":
            wire = pkt
        elif args.write_mode == "prefix":
            wire = b"\x00" + pkt
        else:  # full64: 0x00 + 帧，补零到 64 字节（无 report-id 设备的完整 OUT report）
            wire = b"\x00" + pkt
            if len(wire) < 64:
                wire += b"\x00" * (64 - len(wire))
        print("\n[%s] -> %s (wire=%d bytes, mode=%s)"
              % (name, hexstr(pkt), len(wire), args.write_mode))
        try:
            n = h.write(wire)
            print("  wrote %d bytes" % n)
        except Exception as e:
            print("  write failed: %s" % e)
            h.close()
            sys.exit(1)
        time.sleep(0.05)
        for r in range(args.read_n):
            d = safe_read(h, 64, args.timeout)
            if not d:
                print("  read[%d]: <no response / timeout>" % r)
                break
            print("  read[%d](%d): %s" % (r, len(d), hexstr(d)))
            parse_frame(d)

    h.close()


if __name__ == "__main__":
    main()

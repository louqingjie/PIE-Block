#!/usr/bin/env python3
"""seq_hid.py - 灵活协议探索：发任意命令序列，观察每一步响应。

用法：
  seq_hid.py --hex "01 00 00 00 00 00 00 80 00" --hex "05 00 00 5a a5" ...
  seq_hid.py --file cmds.txt     # 每行一个 payload（空格分隔 hex，# 注释）
选项：
  --read-n N        每条命令后连续读 N 个报告（默认 1）
  --timeout MS      读超时（默认 1500）
  --mode raw|prefix|full64   写格式（默认 full64）
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
PACKET_HOST = bytes([0x6A])


def build_packet(packet_data: bytes) -> bytes:
    p = PACKET_START + PACKET_HOST
    p += struct.pack(">H", len(packet_data) + 6)
    p += packet_data
    p += struct.pack(">H", sum(p[2:]) & 0xFFFF)
    p += PACKET_END
    return p


def parse_hex(s: str) -> bytes:
    s = s.strip().replace(",", " ").replace("0x", "")
    return bytes(int(x, 16) for x in s.split())


def hexstr(b) -> str:
    return " ".join("%02x" % x for x in b)


def safe_read(h, size, timeout_ms):
    try:
        d = h.read(size, timeout_ms)
        return d if d else None
    except hid.HIDException:
        return None


def parse_frame(d: bytes):
    if d[:2] == PACKET_START:
        who = d[2] if len(d) >= 3 else 0
        print("    [frame] dir=0x%02x len=%d"
              % (who, ((d[3] << 8) | d[4]) if len(d) >= 5 else -1))
    else:
        print("    [frame] !not STC frame")


def main():
    ap = argparse.ArgumentParser(description="Send arbitrary command sequence to STC32G HID bootloader")
    ap.add_argument("--hex", action="append", default=[], help="payload hex（可多次）")
    ap.add_argument("--file", default=None, help="命令文件（每行一个 payload hex）")
    ap.add_argument("--read-n", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=1500)
    ap.add_argument("--mode", choices=["raw", "prefix", "full64"], default="full64")
    args = ap.parse_args()

    cmds = list(args.hex)
    if args.file:
        with open(args.file, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                cmds.append(line)

    if not cmds:
        print("no commands given")
        sys.exit(1)

    try:
        h = hid.Device(VID, PID)
    except Exception as e:
        print("open failed: %s" % e)
        sys.exit(1)
    print("opened: %r / %r" % (h.manufacturer, h.product))

    for idx, c in enumerate(cmds):
        payload = parse_hex(c)
        pkt = build_packet(payload)
        if args.mode == "raw":
            wire = pkt
        elif args.mode == "prefix":
            wire = b"\x00" + pkt
        else:
            wire = b"\x00" + pkt
            if len(wire) < 64:
                wire += b"\x00" * (64 - len(wire))
        print("\n[%d] payload=%s" % (idx, hexstr(payload)))
        try:
            n = h.write(wire)
            print("  -> wrote %d bytes" % n)
        except Exception as e:
            print("  -> write failed: %s" % e)
            break
        time.sleep(0.05)
        for r in range(args.read_n):
            d = safe_read(h, 64, args.timeout)
            if not d:
                print("  <- read[%d]: <timeout>" % r)
                break
            print("  <- read[%d]: %s" % (r, hexstr(d)))
            parse_frame(d)

    h.close()


if __name__ == "__main__":
    main()

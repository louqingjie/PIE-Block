#!/usr/bin/env python3
"""usbcap_scan.py - 从 USBPcap pcap 中识别 USB 设备（VID/PID/产品串），
用于确定 STC 板挂在哪个 USBPcap 设备上。

依赖 --inject-descriptors 注入的设备/配置描述符控制传输。
"""
import argparse
import struct

import dpkt


def hexstr(b) -> str:
    return " ".join("%02x" % x for x in b)


def parse_device_descriptor(data: bytes):
    # device descriptor: bLength=18, bDescriptorType=1
    if len(data) < 18 or data[0] != 18 or data[1] != 1:
        return None
    vid, pid = struct.unpack_from("<HH", data, 8)
    return vid, pid


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcap")
    ap.add_argument("--all", action="store_true", help="打印所有设备地址")
    args = ap.parse_args()

    found = {}
    with open(args.pcap, "rb") as f:
        reader = dpkt.pcap.Reader(f)
        for ts, buf in reader:
            if len(buf) < 38:
                continue
            (timestamp, cap_len, orig_len) = struct.unpack("<QII", buf[0:16])
            (event, tt, ep, dev) = struct.unpack("<BBBB", buf[24:28])
            (bus_id,) = struct.unpack("<H", buf[28:30])
            data = buf[38:38 + cap_len]
            if tt == 2 and event == 2:  # control COMPLETE
                dd = parse_device_descriptor(data)
                if dd:
                    found[(bus_id, dev)] = dd

    if not found:
        print("no device descriptors found in capture")
        # fallback: report interrupt transfer sources
        return

    for (bus, dev), (vid, pid) in sorted(found.items()):
        mark = "  <== STC" if vid == 0x34BF else ""
        print("bus=%d dev=%d vid=%04x pid=%04x%s" % (bus, dev, vid, pid, mark))

    if args.all:
        print("\ndevices without descriptor:")
        # not implemented


if __name__ == "__main__":
    main()

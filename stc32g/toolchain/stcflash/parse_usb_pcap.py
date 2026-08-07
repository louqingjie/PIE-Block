#!/usr/bin/env python3
"""parse_usb_pcap.py - 解析 USBPcap 抓包，提取 STC32G USB-HID ISP 的中断传输。

USBPcap 的 pcap 链路层头（LINKTYPE_USBPCAP=249）：
  0-7   timestamp (u64)
  8-11  cap_len (u32)
  12-15 original_len (u32)
  16-23 irp_id (8)
  24    event (1): 1=URB submit 2=URB complete 3=error
  25    transfer_type (1): 1=interrupt 2=control 3=bulk 4=iso
  26    endpoint_address (1): 0x81=EP1 IN 0x01=EP1 OUT
  27    device_address (1)
  28-29 bus_id (u16)
  30-37 setup_data (8)
  38+   payload

用法：parse_usb_pcap.py capture.pcap [--hex-dump] [--filter-device N] [--raw]
"""
import argparse
import struct
import sys

import dpkt


def hexstr(b) -> str:
    return " ".join("%02x" % x for x in b)


def main():
    ap = argparse.ArgumentParser(description="Parse USBPcap capture for STC USB-HID ISP traffic")
    ap.add_argument("pcap")
    ap.add_argument("--hex-dump", action="store_true", help="对每个中断传输打印完整 64 字节 hex")
    ap.add_argument("--device", type=int, default=None, help="只看指定 device_address")
    ap.add_argument("--raw", action="store_true", help="打印所有中断传输原始字节（含截断长度）")
    args = ap.parse_args()

    ev_names = {1: "SUBMIT", 2: "COMPLETE", 3: "ERROR"}
    tt_names = {1: "intr", 2: "ctrl", 3: "bulk", 4: "iso"}

    with open(args.pcap, "rb") as f:
        reader = dpkt.pcap.Reader(f)
        print("pcap linktype=%d (249=USBPcap)" % reader.datalink())

        n_total = 0
        n_intr = 0
        for ts, buf in reader:
            n_total += 1
            if len(buf) < 38:
                continue
            # USBPcap 头 (38B):
            #  0-7   timestamp (i64)
            #  8-11  cap_len (u32)
            #  12-15 original_len (u32)
            #  16-23 irp_id (8)
            #  24    event
            #  25    transfer_type
            #  26    endpoint_address
            #  27    device_address
            #  28-29 bus_id (u16)
            #  30-37 setup_data (8)
            (timestamp, cap_len, orig_len) = struct.unpack("<QII", buf[0:16])
            (event, tt, ep, dev) = struct.unpack("<BBBB", buf[24:28])
            (bus_id,) = struct.unpack("<H", buf[28:30])
            data = buf[38:38 + cap_len]

            if tt != 1:  # 只关心中断传输（HID）
                continue
            n_intr += 1

            if args.device is not None and dev != args.device:
                continue

            ev = ev_names.get(event, "?%d" % event)
            epname = "IN" if (ep & 0x80) else "OUT"
            line = "bus=%d dev=%d %-8s ep=0x%02x(%s) %s cap=%d" % (
                bus_id, dev, ev, ep, epname, tt_names.get(tt, "?"), cap_len)
            if args.hex_dump or args.raw:
                line += "  data=%s" % hexstr(data[:cap_len])
            print(line)

        print("\n--- summary ---")
        print("total packets: %d" % n_total)
        print("interrupt transfers: %d" % n_intr)


if __name__ == "__main__":
    main()

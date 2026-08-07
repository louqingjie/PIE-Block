#!/usr/bin/env python3
"""cmd_flow.py - 提取 USBPcap 抓包里的 STC 命令级序列（不含大块数据）。
用法：cmd_flow.py <pcap> [--last N]
"""
import os
import struct
import sys


def hexstr(b: bytes) -> str:
    return " ".join("%02x" % x for x in b)


def main():
    path = sys.argv[1]
    last_n = 0
    if len(sys.argv) > 2 and sys.argv[2] == "--last":
        last_n = int(sys.argv[3])

    data = open(path, "rb").read()
    off = 24
    frames = []
    while off + 16 <= len(data):
        ts_s, ts_us, caplen, origlen = struct.unpack_from("<IIII", data, off)
        if caplen > 65535 or off + 16 + caplen > len(data):
            break
        pkt = data[off + 16: off + 16 + caplen]
        i = pkt.find(b"\x46\xb9")
        if i != -1:
            fr = pkt[i:i + 64]
            if len(fr) >= 5 and (fr[2] == 0x6A or fr[2] == 0x68):
                d = fr[2]
                plen = (fr[3] << 8) | fr[4]
                payload = fr[5:5 + plen - 4]
                frames.append((d, plen, payload))
        off += 16 + caplen

    def fmt(d, plen, payload):
        dirs = "OUT" if d == 0x6A else "IN"
        if not payload:
            return "%s len=%d" % (dirs, plen)
        cmd = payload[0]
        desc = ""
        if dirs == "OUT":
            if cmd == 0x32:
                desc = "write-first addr=0x%02x%02x" % (payload[1], payload[2])
            elif cmd == 0x12:
                desc = "write addr=0x%02x%02x" % (payload[1], payload[2])
            elif cmd == 0x00:
                desc = "start/status-req"
            elif cmd == 0x01:
                desc = "info"
            elif cmd == 0x05:
                desc = "unlock"
            elif cmd == 0x03:
                desc = "erase"
            elif cmd == 0xff:
                desc = "reset"
            else:
                desc = "cmd?=0x%02x" % cmd
        else:
            if cmd == 0x00:
                desc = "status-packet (%d bytes)" % len(payload)
            elif cmd == 0x02:
                desc = "write-ack"
            elif cmd == 0x01:
                desc = "info-ack"
            elif cmd == 0x05:
                desc = "unlock-ack"
            elif cmd == 0x03:
                desc = "erase-ack"
            else:
                desc = "ack?=0x%02x" % cmd
        return "%s len=%d cmd=0x%02x %s payload=%s" % (dirs, plen, cmd, desc, hexstr(payload[:14]))

    print("total frames: %d" % len(frames))
    if last_n > 0:
        frames = frames[-last_n:]
    for d, plen, payload in frames:
        print(fmt(d, plen, payload))


if __name__ == "__main__":
    main()

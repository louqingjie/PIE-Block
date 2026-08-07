#!/usr/bin/env python3
"""analyze_capture.py - 从 USBPcap pcap 提取并解析 STC USB-HID ISP 帧序列。

用于分析 AiCube-ISP 烧录过程：按序提取所有含 0x46 0xB9 的 OUT/IN 报告，
解析帧结构（方向、命令字节、地址、数据、校验），并按时间顺序打印。

用法：analyze_capture.py <pcap> [--all] [--raw]
"""
import argparse
import os
import struct
import sys


def hexstr(b: bytes) -> str:
    return " ".join("%02x" % x for x in b)


def parse_pcap_records(path: str):
    """手动解析 pcap，返回 [(ts_usec, record_bytes)]"""
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 24:
        return []
    off = 24
    recs = []
    n = 0
    while off + 16 <= len(data) and n < 500000:
        ts_s, ts_us, caplen, origlen = struct.unpack_from("<IIII", data, off)
        if caplen > 65535 or off + 16 + caplen > len(data):
            break
        pkt = data[off + 16: off + 16 + caplen]
        ts = ts_s * 1000000 + ts_us
        recs.append((ts, pkt))
        off += 16 + caplen
        n += 1
    return recs


def find_frame_offset(pkt: bytes) -> int:
    """在记录里找 0x46 0xb9 帧起始（含 report-id 前缀 0x00 的情况）。"""
    # STC 帧可能以 0x00 0x46 0xb9（report-id+帧）或 0x46 0xb9 开头
    i = pkt.find(b"\x46\xb9")
    if i == -1:
        return -1
    # 若前面是 report-id 0x00，则从 report-id 开始算报告
    return i


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("pcap")
    ap.add_argument("--all", action="store_true", help="打印所有帧（含非 STC 报告）")
    ap.add_argument("--raw", action="store_true", help="打印完整原始字节")
    ap.add_argument("--dir", choices=["both", "out", "in"], default="both")
    args = ap.parse_args()

    recs = parse_pcap_records(args.pcap)
    print("total records: %d" % len(recs))

    frames = []
    for ts, pkt in recs:
        idx = find_frame_offset(pkt)
        if idx == -1:
            continue
        # 报告内容：从 report-id 0x00 开始，64 字节
        start = idx - 1 if (idx >= 1 and pkt[idx - 1] == 0x00) else idx
        report = pkt[start:start + 64]
        # 定位帧在报告内的偏移（跳过 report-id 0x00）
        foff = report.find(b"\x46\xb9")
        if foff == -1:
            continue
        frames.append((ts, report, foff))

    print("STC frames found: %d" % len(frames))
    print()
    for ts, report, foff in frames:
        fr = report[foff:]  # 从 46 b9 开始
        if len(fr) < 7:
            continue
        d = fr[2]
        direction = "OUT(host->mcu)" if d == 0x6a else ("IN(mcu->host)" if d == 0x68 else "?")
        plen = (fr[3] << 8) | fr[4]
        # payload = 方向+长度之后，到校验和(2字节)和 0x16 之前
        # plen 是从方向字节到帧尾的总长 = 1(方向)+2(长度)+payload+2(校验)+1(16)
        body_end = 3 + plen  # 帧内从 index 3(方向) 起 plen 字节
        if len(fr) >= body_end:
            payload = fr[5:body_end - 3]
        else:
            payload = fr[5:]
        line = "ts=%012d %-13s len=%d" % (ts, direction, plen)
        if args.raw:
            line += "  payload=%s" % hexstr(payload)
        if args.dir != "both":
            want_in = (args.dir == "in")
            is_in = (d == 0x68)
            if want_in != is_in:
                continue
        print(line)


if __name__ == "__main__":
    main()

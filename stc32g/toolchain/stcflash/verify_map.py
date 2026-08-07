#!/usr/bin/env python3
"""verify_map.py - 验证抓包写地址与 hex 地址的映射关系。

假设：AiCube-ISP 把 hex 地址 0xFE0000+ 映射为 ISP 写地址 (hex_addr - 0xFE0000)。
验证：抓包第一个写块(addr 0x0000)的数据 == hex[0xFE0000:0xFE0000+128]。
"""
import os
import struct
import sys

PCAP = os.path.join(os.environ["TEMP"], "usbcap_aicube.pcap")
HEX = r"C:\Users\louqi\Desktop\program\pie-block\stc32g\Projects\TEST\MDK\Objects\Project_Template.hex"


def load_hex_slice(path: str, start: int, length: int) -> bytes:
    """手工解析 Intel HEX，取 [start, start+length) 字节。"""
    out = {}
    base = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith(":"):
                continue
            try:
                n = int(line[1:3], 16)
                addr = int(line[3:7], 16)
                rtype = int(line[7:9], 16)
            except ValueError:
                continue
            data = bytes(int(line[9 + 2 * i:11 + 2 * i], 16) for i in range(n))
            if rtype == 0:
                for i in range(n):
                    out[base + addr + i] = data[i]
            elif rtype == 4:  # 线性地址扩展
                base = (data[0] << 8 | data[1]) << 16
    return bytes(out.get(start + i, 0xFF) for i in range(length))


def first_data_addr(path: str):
    """返回 hex 中第一个实际有数据的地址（非 0xFF 的连续段起点）。"""
    out = {}
    base = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line.startswith(":"):
                continue
            n = int(line[1:3], 16)
            addr = int(line[3:7], 16)
            rtype = int(line[7:9], 16)
            data = bytes(int(line[9 + 2 * i:11 + 2 * i], 16) for i in range(n))
            if rtype == 0:
                for i in range(n):
                    out[base + addr + i] = data[i]
            elif rtype == 4:
                base = (data[0] << 8 | data[1]) << 16
    if not out:
        return None
    return min(out)


def main():
    data = open(PCAP, "rb").read()
    off = 24
    first = None
    while off + 16 <= len(data):
        ts, ts2, caplen, orig = struct.unpack_from("<IIII", data, off)
        if off + 16 + caplen > len(data):
            break
        pkt = data[off + 16:off + 16 + caplen]
        i = pkt.find(b"\x46\xb9")
        if i != -1:
            fr = pkt[i:i + 64]
            # 写帧: 46 b9 6a len cmd addr_hi addr_lo 5a a5 data...
            if len(fr) >= 10 and fr[2] == 0x6A and fr[5] == 0x32:
                # 数据从 fr[10] 开始（跳过 5a a5）
                first = fr[10:138]
                break
        off += 16 + caplen

    if not first:
        print("no first write block found")
        return

    # hex 数据段起点
    hstart = first_data_addr(HEX)
    print("hex first data addr: 0x%X" % hstart if hstart else "none")
    if hstart is None:
        return
    hexdata = load_hex_slice(HEX, hstart, 128)
    print("captured block0 data: %s" % first[:16].hex(" "))
    print("hex @0x%X        : %s" % (hstart, hexdata[:16].hex(" ")))
    print("MATCH: %s" % (first == hexdata))


if __name__ == "__main__":
    main()

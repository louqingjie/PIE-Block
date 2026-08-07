#!/usr/bin/env python3
"""disasm_aiisp.py - 反汇编 AiCube-ISP 中 HID 写/烧录相关函数。

解析 PE 段映射，用 capstone 反汇编指定虚拟地址区间。
用法：disasm_aiisp.py <exe> <start_va> <length> [--raw-va]
"""
import struct
import sys

from capstone import Cs, CS_ARCH_X86, CS_MODE_32

# ============ PE 解析 ============

def parse_pe(data: bytes):
    pe_off = struct.unpack_from("<I", data, 0x3C)[0]
    assert data[pe_off:pe_off + 4] == b"PE\x00\x00"
    machine = struct.unpack_from("<H", data, pe_off + 4)[0]
    nsec = struct.unpack_from("<H", data, pe_off + 6)[0]
    opt_size = struct.unpack_from("<H", data, pe_off + 20)[0]
    opt_off = pe_off + 24
    # 段表在可选头之后
    sec_off = opt_off + opt_size
    secs = []
    for i in range(nsec):
        off = sec_off + i * 40
        name = data[off:off + 8].rstrip(b"\x00").decode("ascii", "replace")
        vsize = struct.unpack_from("<I", data, off + 8)[0]
        vaddr = struct.unpack_from("<I", data, off + 12)[0]
        raw_size = struct.unpack_from("<I", data, off + 16)[0]
        raw_ptr = struct.unpack_from("<I", data, off + 20)[0]
        secs.append((name, vaddr, vsize, raw_ptr, raw_size))
    return machine, secs


def va_to_off(secs, va):
    for name, vaddr, vsize, raw_ptr, raw_size in secs:
        if vaddr <= va < vaddr + max(vsize, raw_size):
            delta = va - vaddr
            if delta < raw_size:
                return raw_ptr + delta
    return None


def main():
    exe = sys.argv[1]
    start_va = int(sys.argv[2], 0)
    length = int(sys.argv[3], 0)
    data = open(exe, "rb").read()
    machine, secs = parse_pe(data)
    print("machine=%04x sections:" % machine)
    for s in secs:
        print("  %-8s va=%08x vsize=%x raw=%08x/%x" % s)

    md = Cs(CS_ARCH_X86, CS_MODE_32)
    md.detail = True

    # 从文件偏移反汇编（找到对应段）
    off = va_to_off(secs, start_va)
    if off is None:
        print("cannot map VA %08x to file" % start_va)
        return
    code = data[off:off + length]
    print("\n=== disasm VA %08x len %x ===" % (start_va, length))
    for insn in md.disasm(code, start_va):
        print("%08x: %-10s %s" % (insn.address, insn.mnemonic, insn.op_str))


if __name__ == "__main__":
    main()

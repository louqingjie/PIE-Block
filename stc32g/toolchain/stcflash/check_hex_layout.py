#!/usr/bin/env python3
"""检查 Intel HEX 的地址布局，用于 bootloader / App 分区方案的验证。

用途：
  1. 验 bootloader hex 是否塞进 LDR_SIZE（默认 4K）
  2. 验 bootloader 的中断蹦床是否指向 +LDR_SIZE
  3. 验 App hex 的段布局（是否有 0xFF0000 的复位跳转待搬运）
  4. 两个 hex 做字节级 diff，确认改动范围符合预期

地址布局背景见 stc32g/Libraries/deivers/inc/iap_proto.h。

用法：
  python check_hex_layout.py <hex>              # 单文件报告
  python check_hex_layout.py <hexA> --diff <hexB>
"""
import argparse
import sys

LDR_SIZE = 0x1000
"""bootloader 占用大小，必须与 PIE_BOOTLOADER/USER/inc/config.h 一致。"""

VECTOR_COUNT = 67
"""isr.asm 里 MAPISR 宏的条数。中断入口从 0x0003 起每 8 字节一个。"""


def parse_ihex(path):
    """解析 Intel HEX，返回 (地址->字节 的 dict, type04 记录列表)。

    type04（扩展线性地址）把后续记录的地址抬高 16 位，STC 的 App hex
    会出现两条（0xFE0000 与 0xFF0000）。
    """
    segs = {}
    base = 0
    t04 = []
    with open(path, "r", encoding="ascii") as f:
        for lineno, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            if not line.startswith(":"):
                raise ValueError(f"{path}:{lineno} 不是 HEX 记录行")
            try:
                raw = bytes.fromhex(line[1:])
            except ValueError as exc:
                raise ValueError(f"{path}:{lineno} 十六进制解析失败: {exc}") from exc
            if len(raw) < 5:
                raise ValueError(f"{path}:{lineno} 记录过短")
            count, addr, rtype = raw[0], (raw[1] << 8) | raw[2], raw[3]
            payload = raw[4:4 + count]
            if len(payload) != count:
                raise ValueError(f"{path}:{lineno} 长度与声明不符")
            if (sum(raw) & 0xFF) != 0:
                raise ValueError(f"{path}:{lineno} 校验和错误")
            if rtype == 0x00:
                for i, val in enumerate(payload):
                    segs[base + addr + i] = val
            elif rtype == 0x04:
                base = ((payload[0] << 8) | payload[1]) << 16
                t04.append((lineno, base))
            elif rtype == 0x01:
                break
    if not segs:
        raise ValueError(f"{path} 没有数据记录")
    return segs, t04


def contiguous_regions(segs):
    """把地址集合压成连续区间列表 [(lo, hi), ...]。"""
    keys = sorted(segs)
    out = []
    start = prev = keys[0]
    for key in keys[1:]:
        if key != prev + 1:
            out.append((start, prev))
            start = key
        prev = key
    out.append((start, prev))
    return out


def check_trampolines(segs):
    """核对中断蹦床：每个入口应是 LJMP 到 入口地址+LDR_SIZE。

    返回 (通过数, 总数, 前几条的明细)。
    并非 67 条都能查到 —— 靠后的入口会被主代码段覆盖，官方 hex 同样如此，
    所以这个数字只用于与官方对比，不作绝对判据。
    """
    ok = 0
    detail = []
    for i in range(VECTOR_COUNT):
        addr = 0x0003 + i * 8
        if addr not in segs or addr + 2 not in segs:
            continue
        opcode = segs[addr]
        target = (segs[addr + 1] << 8) | segs[addr + 2]
        good = opcode == 0x02 and target == addr + LDR_SIZE
        if good:
            ok += 1
        if i < 8:
            detail.append((addr, opcode, target, good))
    return ok, VECTOR_COUNT, detail


def report(path):
    segs, t04 = parse_ihex(path)
    lo, hi = min(segs), max(segs)
    regions = contiguous_regions(segs)

    print(f"=== {path} ===")
    print(f"  bytes        : {len(segs)}")
    print(f"  span         : 0x{lo:06X} - 0x{hi:06X}")
    print(f"  type04       : {[f'line {ln} -> 0x{b:06X}' for ln, b in t04] or 'none (base 0)'}")
    print(f"  regions      : {len(regions)}")

    if not t04:
        # 无 type04 => bootloader 风格，地址从 0 起
        over = [a for a in segs if a >= LDR_SIZE]
        verdict = f"OVER {LDR_SIZE // 1024}K ({len(over)} bytes)" if over else "fits"
        print(f"  vs LDR_SIZE  : {verdict}")
        ok, total, detail = check_trampolines(segs)
        print(f"  trampolines  : {ok}/{total} verified")
        for addr, opcode, target, good in detail:
            flag = "OK" if good else "MISMATCH"
            print(f"    0x{addr:04X}: {opcode:02X} -> 0x{target:04X}  {flag}")
    else:
        # 有 type04 => App 风格，检查是否存在待搬运的复位向量
        reset = [a for a in segs if 0xFF0000 <= a <= 0xFF0002]
        if reset:
            trio = " ".join(f"{segs[a]:02X}" for a in sorted(reset))
            print(f"  reset vector : 0xFF0000 present ({trio}) -> 上位机需搬到 0xFF{LDR_SIZE:04X}")
        else:
            print("  reset vector : 0xFF0000 absent")
        app_lo = 0xFF0000 + LDR_SIZE
        hole = [a for a in range(app_lo, app_lo + 3) if a not in segs]
        print(f"  app entry    : 0x{app_lo:06X} "
              f"{'空洞(待搬入)' if len(hole) == 3 else '已有数据'}")

    for r_lo, r_hi in regions if len(regions) <= 12 else regions[:12]:
        print(f"    region 0x{r_lo:06X} - 0x{r_hi:06X}  ({r_hi - r_lo + 1} bytes)")
    if len(regions) > 12:
        print(f"    ... 另有 {len(regions) - 12} 个区间")
    print()
    return segs


def diff(path_a, path_b):
    segs_a = parse_ihex(path_a)[0]
    segs_b = parse_ihex(path_b)[0]
    print(f"=== diff ===\n  A = {path_a}\n  B = {path_b}")
    print(f"  A bytes={len(segs_a)}  B bytes={len(segs_b)}")
    only_a = sorted(set(segs_a) - set(segs_b))
    only_b = sorted(set(segs_b) - set(segs_a))
    print(f"  only in A: {len(only_a)}   only in B: {len(only_b)}")
    changed = sorted(a for a in set(segs_a) & set(segs_b) if segs_a[a] != segs_b[a])
    print(f"  differing bytes: {len(changed)}")
    for addr in changed:
        print(f"    0x{addr:06X}: A={segs_a[addr]:02X}  B={segs_b[addr]:02X}")
    return len(changed) + len(only_a) + len(only_b)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("hexfile", help="要检查的 hex 文件")
    ap.add_argument("--diff", metavar="OTHER", help="与另一个 hex 做字节级对比")
    args = ap.parse_args(argv)

    try:
        report(args.hexfile)
        if args.diff:
            report(args.diff)
            diff(args.hexfile, args.diff)
    except (OSError, ValueError) as exc:
        print(f"错误: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

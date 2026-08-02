"""扫描 Intel HEX，定位特定 float 常量字节（验证 const 数组数据是否编进固件）。

用法：python scan_hex_floats.py <hex> [100.0f] [10.0f]
"""
import sys


def parse_ihex(path: str) -> dict:
    data: dict = {}
    base = 0
    with open(path, "r", encoding="ascii") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(":"):
                continue
            rec = bytes.fromhex(line[1:])
            count, hi, lo, rtype = rec[0], rec[1], rec[2], rec[3]
            payload = rec[4:4 + count]
            if rtype == 0x00:
                off = (hi << 8) | lo
                for i, b in enumerate(payload):
                    data[base + off + i] = b
            elif rtype == 0x04:
                base = ((payload[0] << 8) | payload[1]) << 16
    return data


def float_bytes(value: float, little: bool) -> bytes:
    import struct
    return struct.pack("<f" if little else ">f", value)


def search(data: dict, pattern: bytes) -> list:
    addrs = sorted(data.keys())
    found = []
    for i in range(len(addrs) - len(pattern) + 1):
        ok = True
        for j in range(len(pattern)):
            if data.get(addrs[i + j]) != pattern[j]:
                ok = False
                break
        if ok:
            found.append(addrs[i])
    return found


def main() -> int:
    path = sys.argv[1]
    values = [float(x) for x in sys.argv[2:]] or [100.0, 10.0]
    data = parse_ihex(path)
    print("=== %s ===" % path)
    print("total bytes: %d, span 0x%06X-0x%06X" % (
        len(data), min(data), max(data)))
    for value in values:
        for little in (True, False):
            pat = float_bytes(value, little)
            found = search(data, pat)
            if found:
                print("%s (%s) found %d times, first 0x%06X, span %s" % (
                    value, "LE" if little else "BE", len(found), found[0],
                    (hex(found[0]), hex(found[-1]))))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

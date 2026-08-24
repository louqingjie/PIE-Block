#!/usr/bin/env python3
"""Validate the STC32G12K128 SDCC HEX/MAP layout."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path


APP_BASE = 0xFE0000
VECTOR_BASE = 0xFF0000
VECTOR_LIMIT = 0xFF1000
XRAM_BASE = 0x010000
XRAM_LIMIT = 0x012000
IRAM_LIMIT = 0x1000


def parse_hex(path: Path) -> dict[int, int]:
    data: dict[int, int] = {}
    upper = 0
    for line_number, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        if not line.startswith(":"):
            raise ValueError(f"{path}:{line_number}: invalid Intel HEX record")
        raw = bytes.fromhex(line[1:])
        if len(raw) < 5 or (sum(raw) & 0xFF):
            raise ValueError(f"{path}:{line_number}: invalid checksum or record")
        count = raw[0]
        address = (raw[1] << 8) | raw[2]
        record_type = raw[3]
        payload = raw[4 : 4 + count]
        if len(payload) != count:
            raise ValueError(f"{path}:{line_number}: invalid record length")
        if record_type == 0:
            for offset, value in enumerate(payload):
                data[upper + address + offset] = value
        elif record_type == 4:
            upper = ((payload[0] << 8) | payload[1]) << 16
        elif record_type == 1:
            break
    if not data:
        raise ValueError(f"{path}: HEX has no data")
    return data


def parse_map(path: Path) -> list[tuple[str, int, int]]:
    area_pattern = re.compile(
        r"^\s*(HOME|GSINIT|GSFINAL|CSEG|CONST|XINIT|XISEG|DSEG|SSEG|PSEG|XSEG)\s+"
        r"([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})\s+="
    )
    areas: list[tuple[str, int, int]] = []
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = area_pattern.match(line)
        if match:
            name, start_hex, length_hex = match.groups()
            areas.append((name, int(start_hex, 16), int(length_hex, 16)))
    return areas


def validate(hex_path: Path, map_path: Path) -> None:
    image = parse_hex(hex_path)
    areas = parse_map(map_path)
    addresses = set(image)

    if not all(address in image for address in range(VECTOR_BASE, VECTOR_BASE + 3)):
        raise ValueError("reset vector 0xFF0000 is incomplete")
    if image[VECTOR_BASE] != 0x02:
        raise ValueError(f"reset vector opcode is 0x{image[VECTOR_BASE]:02X}, expected LJMP 0x02")

    high_addresses = sorted(address for address in addresses if address >= VECTOR_BASE)
    if high_addresses and max(high_addresses) >= VECTOR_LIMIT:
        raise ValueError("non-vector image data crosses 0xFF1000")
    app_addresses = [address for address in addresses if APP_BASE <= address < VECTOR_BASE]
    if not app_addresses:
        raise ValueError("no user code/data in 0xFE0000-0xFEFFFF")

    for name, start, length in areas:
        end = start + length
        if name == "HOME":
            if start != VECTOR_BASE or end > VECTOR_LIMIT:
                raise ValueError(f"HOME area outside vector region: 0x{start:08X}-0x{end:08X}")
        elif name in {"GSINIT", "GSFINAL", "CSEG", "CONST", "XINIT", "XISEG"}:
            if length and not (APP_BASE <= start < VECTOR_BASE and end <= VECTOR_BASE):
                raise ValueError(f"{name} area outside app code region: 0x{start:08X}-0x{end:08X}")
        elif name == "XSEG":
            if length and not (XRAM_BASE <= start and end <= XRAM_LIMIT):
                raise ValueError(f"XSEG outside STC32G XRAM: 0x{start:08X}-0x{end:08X}")
        elif name in {"DSEG", "SSEG", "PSEG"}:
            if length and not (0 <= start and end <= IRAM_LIMIT):
                raise ValueError(f"{name} outside STC32G EDATA: 0x{start:08X}-0x{end:08X}")

    map_text = map_path.read_text(encoding="utf-8", errors="replace")
    required_symbols = (
        "__sdcc_mcs251_reset_trampoline",
        "__sdcc_gsinit_startup",
        "_Default_Isr",
    )
    for symbol in required_symbols:
        if symbol not in map_text:
            raise ValueError(f"MAP is missing required startup/vector symbol: {symbol}")

    print(
        f"[PASS] {hex_path.name}: {len(image)} bytes, "
        f"app=0x{min(app_addresses):06X}-0x{max(app_addresses):06X}, "
        f"vectors=0x{min(high_addresses):06X}-0x{max(high_addresses):06X}"
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("hex", type=Path)
    parser.add_argument("--map", required=True, type=Path)
    args = parser.parse_args()
    try:
        validate(args.hex, args.map)
    except (OSError, ValueError) as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

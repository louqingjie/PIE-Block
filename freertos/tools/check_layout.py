#!/usr/bin/env python3
"""校验 FreeRTOS SDCC 固件的 HEX/MAP 布局。

布局约定（与 freertos/build_manifest.json 的 layout 字段一致）：
  - 复位/中断向量表在 0xFF0000（STC32G 兼容 code 窗口顶部的 HOME 区）；
  - 应用代码与初始化数据紧随其后，不越过 0xFFFFFF（LARGE，64 KB 代码窗口）；
  - XRAM（XSEG/XISEG）在 0x010000-0x012000；
  - 片内 edata（region 00:）0x0000-0x03FF 留给 DSEG/BSEG/BIT_BANK 与启动栈，
    0x0400-0x0FFF 是 FreeRTOS 的 FRHEAP 区域（任务栈必须落在 region 00:）。
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path


DEFAULT_LAYOUT = {
    "vector_base": 0xFF0000,
    "code_end": 0x1000000,
    "xram_base": 0x010000,
    "xram_limit": 0x012000,
    "edata_limit": 0x1000,
    "direct_limit": 0x0100,
    "frheap_area": "FRHEAP",
    "frheap_base": 0x0400,
    "frheap_size": 0x0C00,
}

CODE_AREAS = {"HOME", "GSINIT", "GSINIT0", "GSINIT1", "GSINIT2", "GSINIT3",
              "GSINIT4", "GSINIT5", "GSFINAL", "CSEG", "CONST", "XINIT"}
XRAM_AREAS = {"XSEG", "XISEG"}
EDATA_AREAS = {"DSEG", "SSEG", "BSEG", "BIT_BANK", "BSEG_BYTES", "REG_BANK_0",
               "REG_BANK_1", "REG_BANK_2", "REG_BANK_3"}


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
        payload = raw[4:4 + count]
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


AREA_PATTERN = re.compile(
    r"^\s*(\w+)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})\s+="
)
SYMBOL_PATTERN = re.compile(r"^\s*[A-Z]:\s*([0-9A-Fa-f]{8})\s+(\S+)")


def parse_map(path: Path) -> tuple[list[tuple[str, int, int]], dict[str, int]]:
    areas: list[tuple[str, int, int]] = []
    symbols: dict[str, int] = {}
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        match = AREA_PATTERN.match(line)
        if match:
            name, start_hex, length_hex = match.groups()
            areas.append((name, int(start_hex, 16), int(length_hex, 16)))
        symbol = SYMBOL_PATTERN.match(line)
        if symbol:
            value_hex, name = symbol.groups()
            symbols.setdefault(name, int(value_hex, 16))
    return areas, symbols


def validate(hex_path: Path, map_path: Path, layout: dict[str, int | str]) -> None:
    limit = {**DEFAULT_LAYOUT, **layout}
    image = parse_hex(hex_path)
    areas, symbols = parse_map(map_path)

    vector_base = int(limit["vector_base"])
    code_end = int(limit["code_end"])
    frheap_base = int(limit["frheap_base"])
    frheap_size = int(limit["frheap_size"])
    frheap_area = str(limit["frheap_area"])

    if vector_base not in image:
        raise ValueError(f"缺少复位向量 0x{vector_base:06X}")
    if image[vector_base] != 0x02:
        raise ValueError(
            f"复位向量操作码为 0x{image[vector_base]:02X}，期望 LJMP 0x02"
        )

    above = [address for address in image if address >= code_end]
    if above:
        raise ValueError(f"镜像越过 0x{code_end:06X}: 0x{max(above):06X}")

    code_areas: list[tuple[str, int, int, int]] = []
    for name, start, length in areas:
        end = start + length
        if name in CODE_AREAS:
            code_areas.append((name, start, end, length))
            if length and not (vector_base <= start and end <= code_end):
                raise ValueError(
                    f"{name} 超出代码区 0x{start:06X}-0x{end:06X}"
                )
        elif name in XRAM_AREAS:
            if length and not (int(limit["xram_base"]) <= start and end <= int(limit["xram_limit"])):
                raise ValueError(f"{name} 超出 XRAM: 0x{start:06X}-0x{end:06X}")
        elif name in EDATA_AREAS:
            if length and not (0 <= start and end <= int(limit["edata_limit"])):
                raise ValueError(f"{name} 超出 EDATA: 0x{start:06X}-0x{end:06X}")
        elif name == frheap_area:
            if start != frheap_base or length != frheap_size:
                raise ValueError(
                    f"{frheap_area} 区域为 0x{start:06X}+0x{length:X}，"
                    f"期望 0x{frheap_base:06X}+0x{frheap_size:X}"
                )

    homes = [area for area in areas if area[0] == "HOME"]
    if not homes:
        raise ValueError("MAP 缺少 HOME 区")
    if homes[0][1] != vector_base:
        raise ValueError(f"HOME 起始地址为 0x{homes[0][1]:06X}，期望 0x{vector_base:06X}")

    if not any(name == frheap_area for name, _, _ in areas):
        raise ValueError(f"MAP 缺少 {frheap_area} 区域，检查链接参数 -Wl-b")

    dseg_end = 0
    for name, start, length in areas:
        if name == "DSEG":
            dseg_end = max(dseg_end, start + length)
        if name in EDATA_AREAS and length and start + length > frheap_base:
            raise ValueError(
                f"{name} 与 {frheap_area} 冲突: 0x{start:06X}+0x{length:X}"
            )
    if dseg_end > int(limit["direct_limit"]):
        raise ValueError(
            f"DSEG 结束于 0x{dseg_end:06X}，超过直接寻址上限 0x{int(limit['direct_limit']):06X}，"
            "portasm.h 的 mov dir8 会溢出"
        )

    uc_heap = symbols.get("_ucHeap")
    if uc_heap != frheap_base:
        raise ValueError(
            f"_ucHeap 位于 0x{uc_heap if uc_heap is not None else 0:06X}，期望 0x{frheap_base:06X}"
        )

    required = ("__sdcc_gsinit_startup", "_vTickISR", "_pxCurrentTCB", "_main")
    missing = [name for name in required if name not in symbols]
    if missing:
        raise ValueError("MAP 缺少必需符号: " + ", ".join(missing))

    code_start = min(start for _, start, _, length in code_areas if length)
    code_last = max(end for _, _, end, length in code_areas if length)
    print(
        f"[PASS] {hex_path.name}: {len(image)} 字节, "
        f"代码 0x{code_start:06X}-0x{code_last:06X}, "
        f"FRHEAP 0x{frheap_base:06X}+0x{frheap_size:X}, "
        f"_ucHeap=0x{uc_heap:06X}"
    )


def load_layout(manifest_path: Path | None) -> dict[str, int | str]:
    if manifest_path is None or not manifest_path.is_file():
        return {}
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    return manifest.get("layout", {})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("hex", type=Path)
    parser.add_argument("--map", required=True, type=Path)
    parser.add_argument("--manifest", type=Path, default=None)
    args = parser.parse_args()
    try:
        validate(args.hex, args.map, load_layout(args.manifest))
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"[FAIL] {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

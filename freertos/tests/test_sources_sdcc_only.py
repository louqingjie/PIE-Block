#!/usr/bin/env python3
"""源码契约测试：SDCC 移植后的 freertos/ 不再包含 Keil 专有构造。"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))

COMMENT_PATTERN = re.compile(r"/\*.*?\*/|//[^\n]*", re.DOTALL)

FORBIDDEN_C = {
    "Keil __asm {} 块": re.compile(r"__asm\s*\{"),
    "裸 interrupt 关键字": re.compile(r"\binterrupt\s+[A-Za-z_0-9]"),
    "Keil using 寄存器组": re.compile(r"\busing\s+[0-9]"),
    "Keil sbit 赋值": re.compile(r"\bsbit\s+[A-Za-z_]\w*\s*="),
    "Keil reentrant 关键字": re.compile(r"\breentrant\b"),
    "Keil 存储类": re.compile(r"(?<!__)\b(?:data|code|xdata|idata|pdata)\s+[A-Za-z_]"),
    "Keil #pragma ROM/WARNING": re.compile(r"#pragma\s+(?:ROM|WARNING)"),
    "Keil 寄存器头 stc32g.h": re.compile(r"#\s*include\s*[<\"]stc32g\.h", re.IGNORECASE),
    "USB CDC 依赖": re.compile(r"\busb_cdc\b|\bUSB_SendData\b|\busb_init\b"),
}

FORBIDDEN_ASM = {
    "Keil A251 向量段": re.compile(r"CSEG\s+AT\s+0BH", re.IGNORECASE),
    "Keil 符号修饰": re.compile(r"\?\w+\?", re.IGNORECASE),
}

REMOVED_PATHS = [
    "FreeRTOS_STC32G_Demo.uvproj",
    "FreeRTOS_STC32G_Demo.uvopt",
    "keilclean.bat",
    "Objects",
    "Listings",
    "Sources/User/usb_cdc.c",
    "Sources/User/stc_usb_cdc_32g.LIB",
    "Sources/User/include/usb.h",
    "Sources/User/include/usb_cdc.h",
    "Sources/User/include/STC32G.H",
]


def project_files() -> tuple[list[Path], list[Path]]:
    relative: list[str] = [str(MANIFEST["projects"]["FREERTOS_DEMO"]["main"])]
    for group in MANIFEST["projects"]["FREERTOS_DEMO"]["source_groups"]:
        relative.extend(str(item) for item in MANIFEST["source_groups"][group])
    headers = [
        "Sources/User/include/FreeRTOSConfig.h",
        "Sources/FreeRTOS/portable/STC32G12K128/portmacro.h",
        "Sources/FreeRTOS/portable/STC32G12K128/portasm.h",
    ]
    assemblies = [str(item) for item in MANIFEST.get("assemblies", [])]
    return ([ROOT / item for item in relative + headers],
            [ROOT / item for item in assemblies])


class SdccSourceContractTests(unittest.TestCase):
    def test_no_keil_constructs_in_c_sources(self) -> None:
        sources, _ = project_files()
        violations: list[str] = []
        for path in sources:
            text = COMMENT_PATTERN.sub("", path.read_text(encoding="utf-8", errors="replace"))
            for description, pattern in FORBIDDEN_C.items():
                if pattern.search(text):
                    violations.append(f"{path.relative_to(ROOT)}: {description}")
        self.assertEqual([], violations, "仍存在 Keil 专有构造:\n" + "\n".join(violations))

    def test_no_keil_directives_in_assembly(self) -> None:
        _, assemblies = project_files()
        violations: list[str] = []
        for path in assemblies:
            text = path.read_text(encoding="utf-8", errors="replace")
            for description, pattern in FORBIDDEN_ASM.items():
                if pattern.search(text):
                    violations.append(f"{path.relative_to(ROOT)}: {description}")
        self.assertEqual([], violations, "汇编里仍存在 Keil 专有指令:\n" + "\n".join(violations))

    def test_keil_only_files_are_removed(self) -> None:
        remaining = [relative for relative in REMOVED_PATHS if (ROOT / relative).exists()]
        self.assertEqual([], remaining, f"Keil 专有文件仍存在: {remaining}")

    def test_manifest_has_no_removed_sources(self) -> None:
        referenced: set[str] = set()
        for group in MANIFEST["source_groups"].values():
            referenced.update(str(item) for item in group)
        referenced.update(MANIFEST.get("assemblies", []))
        referenced.add(str(MANIFEST["projects"]["FREERTOS_DEMO"]["main"]))
        self.assertFalse(any("usb" in item.lower() for item in referenced),
                         "构建清单仍引用 USB 相关文件")

    def test_only_required_kernel_sources_are_compiled(self) -> None:
        compiled = [str(item) for group in MANIFEST["source_groups"].values()
                    for item in group]
        for unused in ("croutine.c", "timers.c", "event_groups.c", "stream_buffer.c"):
            self.assertFalse(any(item.endswith(unused) for item in compiled),
                             f"未使用的内核文件不应编译: {unused}")


if __name__ == "__main__":
    unittest.main(verbosity=2)

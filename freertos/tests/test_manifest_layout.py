#!/usr/bin/env python3
"""清单/配置一致性测试：edata 预算、堆大小与 FRHEAP 链接参数必须自洽。"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
CONFIG = (ROOT / "Sources/User/include/FreeRTOSConfig.h").read_text(encoding="utf-8")
PORTHEAP = (ROOT / "Sources/FreeRTOS/portable/STC32G12K128/portheap.asm").read_text(encoding="utf-8")
MAIN = (ROOT / "Sources/User/main.c").read_text(encoding="utf-8")

TCB_ESTIMATE = 64  # SDCC --model-large 下 TCB 的保守估计（含对齐余量）


def config_number(name: str) -> int:
    match = re.search(rf"#define\s+{name}\s+(.+)", CONFIG)
    if match is None:
        raise AssertionError(f"FreeRTOSConfig.h 缺少 {name}")
    expression = match.group(1)
    expression = re.sub(r"//.*$", "", expression).strip()
    expression = expression.strip("()")
    expression = expression.replace("tskIDLE_PRIORITY", "0")
    expression = re.sub(r"\(\s*size_t\s*\)", "", expression)
    expression = re.sub(r"\(\s*unsigned short\s*\)", "", expression)
    return int(eval(expression, {"__builtins__": {}}, {}))  # noqa: S307 - 仅解析本地清单


class ManifestLayoutTests(unittest.TestCase):
    def test_frheap_matches_config_total_heap_size(self) -> None:
        layout = MANIFEST["layout"]
        self.assertEqual(config_number("configTOTAL_HEAP_SIZE"), layout["frheap_size"])
        size = re.search(r"\.ds\s+0x([0-9A-Fa-f]+)", PORTHEAP)
        self.assertIsNotNone(size, "portheap.asm 缺少 .ds 大小")
        self.assertEqual(layout["frheap_size"], int(size.group(1), 16))

    def test_link_flags_pin_frheap_to_expected_base(self) -> None:
        layout = MANIFEST["layout"]
        pins = [flag for flag in MANIFEST["link_flags"]
                if flag.startswith(f"-Wl-b {layout['frheap_area']}=")]
        self.assertEqual(1, len(pins), f"缺少/重复 FRHEAP 链接定位: {pins}")
        value = int(pins[0].split("=", 1)[1], 16)
        self.assertEqual(layout["frheap_base"], value)
        self.assertEqual(0, layout["frheap_base"] % 0x100,
                         "FRHEAP 基地址应页对齐，保证 _dpx 高位为 0")

    def test_region00_budget_fits_stc32g12k128(self) -> None:
        layout = MANIFEST["layout"]
        self.assertEqual(0x1000, layout["edata_limit"])
        self.assertEqual(layout["edata_limit"], layout["frheap_base"] + layout["frheap_size"])
        self.assertLessEqual(layout["direct_limit"], layout["frheap_base"])

    def test_task_stack_budget_fits_heap(self) -> None:
        tasks = len(re.findall(r"\bxTaskCreate\s*\(", MAIN))
        self.assertGreater(tasks, 0, "main.c 未创建任务")
        default_stack = config_number("configDEFAULT_STACK_SIZE")
        minimal_stack = config_number("configMINIMAL_STACK_SIZE")
        heap = config_number("configTOTAL_HEAP_SIZE")
        used = tasks * default_stack + minimal_stack + (tasks + 1) * TCB_ESTIMATE
        self.assertLessEqual(used, heap,
                             f"任务栈预算 {used} 超过堆大小 {heap}")

    def test_demo_features_stay_inside_large_code_window(self) -> None:
        # 已实测：原配置 60 586 B 会挤爆 64 KB LARGE 窗口，故关闭未使用特性。
        self.assertEqual(0, config_number("configUSE_TASK_NOTIFICATIONS"))
        self.assertEqual(0, config_number("configUSE_MUTEXES"))
        self.assertEqual(0, config_number("configUSE_COUNTING_SEMAPHORES"))
        self.assertEqual(0, config_number("configUSE_TIMERS"))
        self.assertLessEqual(config_number("configMAX_PRIORITIES"), 8)

    def test_heap_is_application_allocated(self) -> None:
        self.assertEqual(1, config_number("configAPPLICATION_ALLOCATED_HEAP"))

    def test_runtime_libraries_present(self) -> None:
        for library in ("mcs251.lib", "libsdcc.lib"):
            self.assertIn(library, MANIFEST["runtime_libraries"])

    def test_compile_flags_are_stack_auto_large(self) -> None:
        for flag in ("--model-large", "--stack-auto", "-mmcs251"):
            self.assertIn(flag, MANIFEST["compile_flags"])


if __name__ == "__main__":
    unittest.main(verbosity=2)

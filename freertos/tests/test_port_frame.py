#!/usr/bin/env python3
"""端口帧序契约测试。

SDCC 为 ``vTickISR()`` 生成的序言/尾声决定了任务帧的精确布局；本测试把
port.c 的 pxPortInitialiseStack()/xPortStartScheduler() 与 portasm.h 的
portRESTORE_CONTEXT() 与该汇编逐项对齐，避免升级工具链或改动端口时空静默
地破坏上下文切换。
"""

from __future__ import annotations

import json
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
REPO = ROOT.parent
MANIFEST = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
PORT_C = ROOT / "Sources/FreeRTOS/portable/STC32G12K128/port.c"
PORT_ASM_H = ROOT / "Sources/FreeRTOS/portable/STC32G12K128/portasm.h"

# SDCC 序言 push 顺序（调用其它函数的 ISR 保存完整寄存器组）。
EXPECTED_PUSHES = [
    "bits", "acc", "b", "dpl", "dph",
    "r15", "r14", "r13", "r12", "r9", "r8",
    "(0+7)", "(0+6)", "(0+5)", "(0+4)", "(0+3)", "(0+2)", "(0+1)", "(0+0)",
    "psw",
]
EXPECTED_POPS = list(reversed(EXPECTED_PUSHES))
FRAME_SIZE = 3 + len(EXPECTED_PUSHES)  # eret 返回地址 3 字节 + 序言寄存器


def find_sdcc() -> Path | None:
    override = os.environ.get("SDCC")
    if override:
        return Path(override)
    candidate = REPO / "vendor/sdcc-toolchain/bin/sdcc"
    if candidate.is_file():
        return candidate
    found = shutil.which("sdcc")
    return Path(found) if found else None


def compile_port_asm(sdcc: Path, destination: Path) -> str:
    include_args: list[str] = []
    for relative in MANIFEST["include_dirs"]:
        include_args.append(f"-I{(ROOT / relative).resolve()}")
    command = [
        str(sdcc),
        "-mmcs251", "--model-large", "--stack-auto", "--opt-code-size",
        "--constseg", "CSEG", "-S", *include_args,
        "-o", str(destination), str(PORT_C),
    ]
    result = subprocess.run(command, capture_output=True, text=True)
    if result.returncode != 0:
        raise AssertionError(f"sdcc -S 失败:\n{result.stdout}\n{result.stderr}")
    return destination.read_text(encoding="utf-8", errors="replace")


def function_block(text: str, label: str) -> str:
    marker = f"\n{label}:\n"
    if marker not in text:
        raise AssertionError(f"生成的汇编里找不到 {label}")
    rest = text[text.index(marker) + len(marker):]
    # 函数标签位于第 0 列；下一个第 0 列标签即函数结束。
    boundary = re.search(r"^[A-Za-z_$][\w$]*:\n", rest, re.MULTILINE)
    return rest[:boundary.start()] if boundary else rest


def meaningful_lines(block: str) -> list[str]:
    return [line.strip() for line in block.splitlines()
            if line.strip() and not line.strip().startswith(";")]


def opcodes(block: str, mnemonic: str) -> list[str]:
    # 编译器生成的尾声用制表符缩进，手写内联汇编可能用空格，两者都要兼容。
    pattern = re.compile(rf"^\s*{mnemonic}\s+(\S.*?)\s*$", re.MULTILINE)
    return [match.group(1).strip() for match in pattern.finditer(block)]


class PortFrameContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        sdcc = find_sdcc()
        if sdcc is None or not sdcc.is_file():
            raise unittest.SkipTest("未找到 sdcc，跳过需要工具链的帧序检查")
        cls._tmp = tempfile.TemporaryDirectory(prefix="freertos_frame_")
        cls.asm = compile_port_asm(sdcc, Path(cls._tmp.name) / "port.asm")

    @classmethod
    def tearDownClass(cls) -> None:
        tmp = getattr(cls, "_tmp", None)
        if tmp is not None:
            tmp.cleanup()

    def test_isr_prologue_saves_full_register_set(self) -> None:
        block = function_block(self.asm, "_vTickISR")
        self.assertEqual(EXPECTED_PUSHES, opcodes(block, "push"))

    def test_isr_epilogue_pops_in_reverse_order(self) -> None:
        block = function_block(self.asm, "_vTickISR")
        self.assertEqual(EXPECTED_POPS, opcodes(block, "pop"))
        self.assertIn("\treti", block)

    def test_spx_restore_is_immediately_followed_by_epilogue(self) -> None:
        block = function_block(self.asm, "_vTickISR")
        lines = meaningful_lines(block)
        index = max(i for i, line in enumerate(lines)
                    if line.startswith("mov") and "sph," in line)
        self.assertIn("_prvSPXHi", lines[index])
        self.assertTrue(lines[index + 1].startswith("pop"),
                        f"写入 SPX 后紧接着: {lines[index + 1]}")
        self.assertFalse(any(line.startswith("push") for line in lines[index + 1:]))

    def test_first_task_starter_uses_same_frame(self) -> None:
        block = function_block(self.asm, "_xPortStartScheduler")
        self.assertEqual(EXPECTED_POPS, opcodes(block, "pop"))
        self.assertIsNotNone(re.search(r"^\s*setb\s+ea\b", block, re.MULTILINE))
        self.assertIn("\teret", block)

    def test_portasm_restore_context_matches_epilogue(self) -> None:
        text = PORT_ASM_H.read_text(encoding="utf-8")
        macro = re.search(r"#define portRESTORE_CONTEXT\(\)(.*?)#define portRETURN_TASK",
                          text, re.DOTALL)
        self.assertIsNotNone(macro, "portasm.h 缺少 portRESTORE_CONTEXT")
        pops = re.findall(r"^\s*pop\s+(\S+)\s*\\?$", macro.group(1), re.MULTILINE)
        self.assertEqual(EXPECTED_POPS, pops)

    def test_initial_frame_matches_prologue_order(self) -> None:
        source = PORT_C.read_text(encoding="utf-8")
        body = source[source.index("StackType_t *pxPortInitialiseStack"):]
        body = body[:body.index("return pxTopOfStack;")]
        loop = re.search(r"for\(\s*index = 0;\s*index < (\d+);\s*index\+\+\s*\)", body)
        self.assertIsNotNone(loop, "pxPortInitialiseStack 缺少寄存器清零循环")
        # 文本里 9 处显式自增（3 字节返回地址 + bits/acc + b/dpl/dph + psw），
        # 循环体里的 1 处代表 loop 次。
        explicit = body.count("pxTopOfStack++")
        self.assertEqual(9 + 1, explicit)
        self.assertEqual(FRAME_SIZE, explicit - 1 + int(loop.group(1)))
        # 返回地址：高字节在前。
        address_order = [m.group(1).strip() for m in re.finditer(
            r"\*pxTopOfStack = \( StackType_t \) \( ulAddress([^)]*)\);", body)]
        self.assertEqual([">> 16", ">> 8", ""], address_order)
        # 参数放在 b/dpl/dph 槽，分别对应指针的高/低/中字节。
        param_order = [m.group(1).strip() for m in re.finditer(
            r"\*pxTopOfStack = \( StackType_t \) \( ulParameter([^)]*)\);", body)]
        self.assertEqual([">> 16", "", ">> 8"], param_order)


if __name__ == "__main__":
    unittest.main(verbosity=2)

from __future__ import annotations

"""固件五线谱渲染器的双平台编译检查 + 主机对拍。

- StaffRender.c 必须能在主机 gcc（-std=c99 -Wall -Wextra -Werror）无警告编译；
- StaffRender.c / OLED_Staff.c / LCD_Frame.c 必须能用 C251 工具链
  （sdcc -mmcs251 --model-large --opt-code-size）编译，且 1024B 帧缓冲落在 XSEG；
- host_harness.c + fixture（另一个任务生成，Dart 渲染器产出 golden 帧）逐场景
  逐帧对拍，固件渲染结果必须与 Dart 逐字节一致。

fixture 缺失时本文件 skip 并打印提示（不让固件 CI 因另一个任务未完成而失败）。
"""

import os
import shutil
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]  # stc32g_sdcc
REPO_ROOT = ROOT.parent

BOARDS_SRC = ROOT / "libraries" / "boards" / "src"
BOARDS_INC = ROOT / "libraries" / "boards" / "inc"
DRIVERS_INC = ROOT / "libraries" / "drivers" / "inc"
DEVICE_INC = ROOT / "include"

STAFF_SOURCES = ("StaffRender.c", "OLED_Staff.c", "LCD_Frame.c")
STAFF_FIXTURES = ROOT / "tests" / "staff" / "fixtures"
STAFF_FIXTURE_HEADER = STAFF_FIXTURES / "staff_fixture.h"
STAFF_FIXTURE_GOLDEN = STAFF_FIXTURES / "golden"
HOST_HARNESS = ROOT / "tests" / "staff" / "host_harness.c"
BUILD_DIR = ROOT / "build" / "staff_render_host"

FRAME_BYTES = 1024

# 注意：仓库 .gitignore 有全局 `*.bin`，golden 帧提交时需要 `git add -f`（见 Lead）。
# fixture 的任何一个部分缺失都算“另一个任务还没产出”，本文件 skip 而不是失败。
FIXTURE_MISSING_HINT = (
    "fixture 不完整，跳过固件/Dart 对拍：先运行 "
    "`dart run tool/emit_staff_fixtures.dart` 生成 "
    f"{STAFF_FIXTURES}（提交时 golden/*.bin 需要 git add -f）"
)


def _fixture_is_available() -> bool:
    if not STAFF_FIXTURE_HEADER.is_file():
        return False
    if not STAFF_FIXTURE_GOLDEN.is_dir():
        return False
    return any(STAFF_FIXTURE_GOLDEN.glob("*.bin"))


def _find_gcc() -> str | None:
    candidates = [shutil.which("gcc"), r"C:\msys64\ucrt64\bin\gcc.exe"]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    return None


def _find_sdcc() -> str | None:
    candidates = [
        os.environ.get("SDCC"),
        str(REPO_ROOT / "vendor" / "sdcc-toolchain" / "bin" / "sdcc.exe"),
        str(ROOT / "vendor" / "sdcc-toolchain" / "bin" / "sdcc.exe"),
        shutil.which("sdcc"),
    ]
    for candidate in candidates:
        if candidate and Path(candidate).is_file():
            return str(candidate)
    return None


def _run(args: list[object], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        [str(arg) for arg in args],
        cwd=str(cwd or ROOT),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )


def _format_failure(result: subprocess.CompletedProcess[str]) -> str:
    return f"退出码 {result.returncode}\n--- stdout ---\n{result.stdout}\n--- stderr ---\n{result.stderr}"


class StaffRenderNativeCompileTests(unittest.TestCase):
    def setUp(self) -> None:
        BUILD_DIR.mkdir(parents=True, exist_ok=True)

    def test_staff_render_gcc_c99_builds_without_warnings(self) -> None:
        gcc = _find_gcc()
        if gcc is None:
            self.skipTest("找不到 gcc（PATH 或 C:\\msys64\\ucrt64\\bin\\gcc.exe），跳过主机编译检查")
        object_file = BUILD_DIR / "StaffRender.gcc.o"
        result = _run(
            [
                gcc,
                "-std=c99",
                "-Wall",
                "-Wextra",
                "-Werror",
                "-I",
                BOARDS_INC,
                "-c",
                BOARDS_SRC / "StaffRender.c",
                "-o",
                object_file,
            ]
        )
        self.assertEqual(0, result.returncode, _format_failure(result))
        self.assertTrue(object_file.is_file(), "gcc 没有生成目标文件")

    def test_music_board_sources_compile_for_mcs251(self) -> None:
        sdcc = _find_sdcc()
        if sdcc is None:
            self.skipTest("找不到 SDCC（vendor/sdcc-toolchain/bin/sdcc.exe），跳过 C251 编译检查")
        include_args: list[object] = []
        for include_dir in (BOARDS_INC, DRIVERS_INC, DEVICE_INC):
            include_args += ["-I", include_dir]
        # 与 build_manifest.json 的 music 工程 compile_flags 一致。
        compile_flags: list[object] = [
            "-mmcs251",
            "--model-large",
            "--stack-auto",
            "--opt-code-size",
            "--constseg",
            "CSEG",
            "-c",
        ]
        for name in STAFF_SOURCES:
            with self.subTest(source=name):
                output = BUILD_DIR / f"{Path(name).stem}.rel"
                result = _run(
                    [
                        sdcc,
                        *compile_flags,
                        *include_args,
                        "-o",
                        output,
                        BOARDS_SRC / name,
                    ],
                    cwd=BUILD_DIR,
                )
                self.assertEqual(0, result.returncode, _format_failure(result))
                self.assertTrue(output.is_file(), f"{name} 没有生成 .rel")
                self.assertNotIn("error", (result.stdout + result.stderr).lower(), _format_failure(result))

    def test_oled_staff_frame_buffer_lands_in_xseg(self) -> None:
        sdcc = _find_sdcc()
        if sdcc is None:
            self.skipTest("找不到 SDCC（vendor/sdcc-toolchain/bin/sdcc.exe），跳过 XSEG 检查")
        output = BUILD_DIR / "OLED_Staff.rel"
        result = _run(
            [
                sdcc,
                "-mmcs251",
                "--model-large",
                "--stack-auto",
                "--opt-code-size",
                "--constseg",
                "CSEG",
                "-c",
                "-I",
                BOARDS_INC,
                "-I",
                DRIVERS_INC,
                "-I",
                DEVICE_INC,
                "-o",
                output,
                BOARDS_SRC / "OLED_Staff.c",
            ],
            cwd=BUILD_DIR,
        )
        self.assertEqual(0, result.returncode, _format_failure(result))
        asm_path = BUILD_DIR / "OLED_Staff.asm"
        self.assertTrue(asm_path.is_file(), "SDCC 没有生成 OLED_Staff.asm")
        lines = asm_path.read_text(encoding="utf-8", errors="replace").splitlines()
        symbol_line = None
        for index, line in enumerate(lines):
            if line.strip() == "_staffFrame:":
                symbol_line = index
                break
        self.assertIsNotNone(symbol_line, "OLED_Staff.asm 里找不到 _staffFrame 符号")
        assert symbol_line is not None
        section = "\n".join(lines[max(0, symbol_line - 6) : symbol_line + 1])
        # --xram-loc 0x010000 链接的 XSEG 即 8KB XRAM；1024B 帧缓冲必须落在这里，
        # 不能占 251 的 iram，也不能放栈上。
        self.assertIn(".area XSEG", section, f"_staffFrame 不在 XSEG：\n{section}")
        self.assertIn(".ds 1024", "\n".join(lines[symbol_line : symbol_line + 2]))


class StaffRenderHostComparisonTests(unittest.TestCase):
    def setUp(self) -> None:
        BUILD_DIR.mkdir(parents=True, exist_ok=True)

    def test_fixture_header_matches_host_harness_contract(self) -> None:
        if not _fixture_is_available():
            print(f"[skip] {FIXTURE_MISSING_HINT}")
            self.skipTest("fixture 缺失（由 Dart 任务生成）")
        header = STAFF_FIXTURE_HEADER.read_text(encoding="utf-8", errors="replace")
        self.assertIn('#include "StaffRender.h"', header)
        self.assertIn("StaffFixtureScenario", header)
        self.assertIn("staffFixtureScenarios", header)
        self.assertIn("STAFF_FIXTURE_SCENARIO_COUNT", header)
        self.assertTrue(STAFF_FIXTURE_GOLDEN.is_dir(), f"缺少 golden 目录：{STAFF_FIXTURE_GOLDEN}")
        golden = sorted(STAFF_FIXTURE_GOLDEN.glob("*.bin"))
        self.assertTrue(golden, f"golden 目录里没有 .bin：{STAFF_FIXTURE_GOLDEN}")
        for path in golden:
            self.assertEqual(
                FRAME_BYTES,
                path.stat().st_size,
                f"{path.name} 不是 {FRAME_BYTES} 字节的页格式帧",
            )

    def test_firmware_render_matches_dart_golden_frames(self) -> None:
        if not _fixture_is_available():
            print(f"[skip] {FIXTURE_MISSING_HINT}")
            self.skipTest("fixture 缺失（由 Dart 任务生成）")
        gcc = _find_gcc()
        if gcc is None:
            self.skipTest("找不到 gcc，跳过主机对拍")

        executable = BUILD_DIR / "staff_host_harness.exe"
        compile_result = _run(
            [
                gcc,
                "-std=c99",
                "-Wall",
                "-Wextra",
                "-I",
                BOARDS_INC,
                "-I",
                STAFF_FIXTURES,
                HOST_HARNESS,
                BOARDS_SRC / "StaffRender.c",
                "-o",
                executable,
            ]
        )
        self.assertEqual(0, compile_result.returncode, _format_failure(compile_result))
        self.assertTrue(executable.is_file(), "gcc 没有生成对拍可执行文件")

        run_result = _run([executable, STAFF_FIXTURES])
        print(run_result.stdout)
        self.assertEqual(
            0,
            run_result.returncode,
            _format_failure(run_result),
        )
        self.assertIn("[PASS]", run_result.stdout, "对拍没有报告 [PASS]")


if __name__ == "__main__":
    unittest.main()

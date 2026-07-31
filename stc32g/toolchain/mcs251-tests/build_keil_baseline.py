#!/usr/bin/env python3
"""Build a standalone Keil C251 calibration HEX."""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path


TEST_ROOT = Path(__file__).resolve().parent
BIN = TEST_ROOT.parent / "Keil_noarm" / "C251" / "BIN"


def run(build_dir: Path, tool: str, *arguments: str) -> None:
    command = [str(BIN / tool), *arguments]
    result = subprocess.run(command, cwd=build_dir, check=False)
    if result.returncode > 1:
        raise RuntimeError(f"{tool} failed with exit code {result.returncode}")


def build_case(case_name: str) -> Path:
    build_dir = TEST_ROOT / "build" / case_name
    shutil.rmtree(build_dir, ignore_errors=True)
    build_dir.mkdir(parents=True)

    source = TEST_ROOT / "cases" / f"{case_name}.c"
    if not source.is_file():
        raise RuntimeError(f"unknown calibration case: {case_name}")
    startup = TEST_ROOT / "support" / "startup_uart_smoke.a51"

    run(
        build_dir,
        "C251.EXE",
        str(source),
        "CODE",
        f"SRC({case_name}.src)",
        f"PRINT({case_name}.lst)",
    )

    generated = (build_dir / f"{case_name}.src").read_text(encoding="ascii")
    startup_external = "        EXTRN         CODE : NEAR (?C?STARTUP)\n"
    if generated.count(startup_external) != 1:
        raise RuntimeError("unexpected C251 startup declaration in generated assembly")
    generated = generated.replace(startup_external, "")
    standalone_name = f"{case_name}_standalone.src"
    (build_dir / standalone_name).write_text(generated, encoding="ascii")

    run(
        build_dir,
        "A251.EXE",
        standalone_name,
        f"OBJECT({case_name}.obj)",
        f"PRINT({case_name}_a251.lst)",
    )
    run(
        build_dir,
        "A251.EXE",
        str(startup),
        "OBJECT(startup_uart_smoke.obj)",
        "PRINT(startup_uart_smoke.lst)",
    )
    run(
        build_dir,
        "L251.EXE",
        f"startup_uart_smoke.obj,{case_name}.obj",
        "TO",
        case_name,
        f"PRINT({case_name}.map)",
        "CASE",
        "CLASSES(CODE(0xFF0010-0xFFFFFF))",
    )
    run(build_dir, "OH251.EXE", case_name, f"HEXFILE({case_name}.hex)")

    hex_path = build_dir / f"{case_name}.hex"
    if not hex_path.is_file():
        raise RuntimeError(f"OH251 did not create {case_name}.hex")
    print(hex_path)
    return hex_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("case", nargs="?", default="uart_smoke")
    args = parser.parse_args(argv)
    build_case(args.case)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
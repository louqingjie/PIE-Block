#!/usr/bin/env python3
"""Build and execute the Keil UART baseline as an integration check."""

from __future__ import annotations

import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path


TEST_ROOT = Path(__file__).resolve().parent
SIMULATOR_DIR = TEST_ROOT.parent / "mcs251-sim"
sys.path.insert(0, str(SIMULATOR_DIR))

from cpu import MCS251Cpu  # noqa: E402
from ihex import parse_ihex_file  # noqa: E402


@dataclass(frozen=True)
class BaselineCase:
    name: str
    stop_pc: int
    expected_uart: tuple[int, ...]
    max_steps: int
    expected_iram: tuple[tuple[int, int], ...] = ()


CASES = (
    BaselineCase("uart_smoke", 0xFF0013, (0x2A,), 20),
    BaselineCase("integer_control", 0xFF003D, (0x2A, 0x00, 0x0F, 0x55), 200),
    BaselineCase(
        "direct_ram",
        0xFF0030,
        (0x12, 0x13, 0x55),
        100,
        ((0x08, 0x13), (0x09, 0x12)),
    ),
)


def validate_case(case: BaselineCase) -> None:
    build_script = TEST_ROOT / "build_keil_baseline.py"
    result = subprocess.run(
        [sys.executable, str(build_script), case.name], check=False
    )
    if result.returncode != 0:
        raise RuntimeError(f"build failed for {case.name}")

    hex_path = TEST_ROOT / "build" / case.name / f"{case.name}.hex"
    image = parse_ihex_file(hex_path)
    cpu = MCS251Cpu.from_hex(image, reset_address=0xFF0000)
    cpu.run(max_steps=case.max_steps, stop_pc=case.stop_pc)

    uart = tuple(write.value for write in cpu.uart_trace if write.channel == 1)
    if uart != case.expected_uart:
        raise RuntimeError(
            f"{case.name}: expected UART {case.expected_uart}, got {uart}"
        )
    for address, expected in case.expected_iram:
        actual = cpu.iram[address]
        if actual != expected:
            raise RuntimeError(
                f"{case.name}: IRAM 0x{address:02X} expected 0x{expected:02X}, "
                f"got 0x{actual:02X}"
            )
    print(
        f"{case.name} PASS: {len(image.memory)} bytes, {cpu.steps} steps, "
        f"UART1={' '.join(f'{value:02X}' for value in uart)}"
    )


def main() -> int:
    for case in CASES:
        validate_case(case)
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError) as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
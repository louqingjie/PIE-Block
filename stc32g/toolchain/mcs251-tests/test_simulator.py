from __future__ import annotations

import sys
import unittest
from pathlib import Path

SIMULATOR_DIR = Path(__file__).resolve().parents[1] / "mcs251-sim"
sys.path.insert(0, str(SIMULATOR_DIR))

from cpu import (  # noqa: E402
    AC_MASK,
    CY_MASK,
    OV_MASK,
    ExecutionLimitExceeded,
    IllegalInstruction,
    MCS251Cpu,
    PSW,
    SP,
    SimulationError,
)
from ihex import HexImage, HexParseError, parse_ihex  # noqa: E402


def record(address: int, record_type: int, data: bytes = b"") -> str:
    raw = bytearray(
        [len(data), address >> 8, address & 0xFF, record_type]
    ) + bytearray(data)
    raw.append((-sum(raw)) & 0xFF)
    return ":" + raw.hex().upper()


class IntelHexTests(unittest.TestCase):
    def test_extended_linear_address_and_regions(self) -> None:
        image = parse_ihex(
            [
                record(0, 4, b"\x00\xFE"),
                record(0x0100, 0, b"\x01\x02"),
                record(0x0200, 0, b"\x03"),
                record(0, 1),
            ]
        )
        self.assertEqual(image.address_range, (0xFE0100, 0xFE0200))
        self.assertEqual(
            image.regions(), [(0xFE0100, 0xFE0101), (0xFE0200, 0xFE0200)]
        )

    def test_start_linear_address(self) -> None:
        image = parse_ihex(
            [record(0, 5, (0x123456).to_bytes(4, "big")), record(0, 0, b"\x00"), record(0, 1)]
        )
        self.assertEqual(image.entry_point, 0x123456)

    def test_rejects_checksum_error(self) -> None:
        with self.assertRaisesRegex(HexParseError, "checksum mismatch"):
            parse_ihex([":0100000000FE", record(0, 1)])

    def test_rejects_overlapping_data(self) -> None:
        with self.assertRaisesRegex(HexParseError, "overlapping data"):
            parse_ihex(
                [record(0, 0, b"\x01\x02"), record(1, 0, b"\x03"), record(0, 1)]
            )

    def test_rejects_record_after_eof(self) -> None:
        with self.assertRaisesRegex(HexParseError, "record after EOF"):
            parse_ihex([record(0, 0, b"\x00"), record(0, 1), record(2, 0, b"\x01")])


class CpuTests(unittest.TestCase):
    def test_arithmetic_and_uart_trace(self) -> None:
        cpu = MCS251Cpu.from_hex(
            HexImage(
                {
                    0: 0x74,
                    1: 0x20,
                    2: 0x24,
                    3: 0x0A,
                    4: 0xF5,
                    5: 0x99,
                }
            )
        )
        cpu.run(max_steps=3, stop_pc=6)
        self.assertEqual(cpu.accumulator, 0x2A)
        self.assertEqual([(write.channel, write.value) for write in cpu.uart_trace], [(1, 0x2A)])

    def test_addition_flags(self) -> None:
        cpu = MCS251Cpu.from_hex(HexImage({0: 0x74, 1: 0x7F, 2: 0x24, 3: 0x01}))
        cpu.run(max_steps=2, stop_pc=4)
        self.assertEqual(cpu.accumulator, 0x80)
        self.assertEqual(cpu.sfr[PSW] & (CY_MASK | AC_MASK | OV_MASK), AC_MASK | OV_MASK)

    def test_relative_jump_loop_hits_limit(self) -> None:
        cpu = MCS251Cpu.from_hex(HexImage({0: 0x80, 1: 0xFE}))
        with self.assertRaises(ExecutionLimitExceeded):
            cpu.run(max_steps=5)
        self.assertEqual(cpu.pc, 0)

    def test_long_call_and_return(self) -> None:
        code = {
            0: 0x12,
            1: 0x00,
            2: 0x05,
            3: 0x80,
            4: 0xFE,
            5: 0x74,
            6: 0x2A,
            7: 0x22,
        }
        cpu = MCS251Cpu.from_hex(HexImage(code))
        cpu.run(max_steps=3, stop_pc=3)
        self.assertEqual(cpu.accumulator, 0x2A)
        self.assertEqual(cpu.sfr[SP], 0x07)

    def test_unknown_opcode_fails_closed(self) -> None:
        cpu = MCS251Cpu.from_hex(HexImage({0: 0xA5, 1: 0x00}))
        with self.assertRaisesRegex(IllegalInstruction, "0xA5"):
            cpu.step()

    def test_accumulator_aliases_register_11(self) -> None:
        cpu = MCS251Cpu.from_hex(HexImage({0: 0x00}))
        cpu.accumulator = 0x2A
        self.assertEqual(cpu.read_register(11), 0x2A)
        cpu.write_direct(0xE0, 0x55)
        self.assertEqual(cpu.accumulator, 0x55)
        self.assertEqual(cpu.read_register(11), 0x55)
        self.assertEqual(cpu.sfr[0xE0], 0x55)

    def test_execute_from_unmapped_code_fails(self) -> None:
        cpu = MCS251Cpu.from_hex(HexImage({0: 0x00}))
        cpu.step()
        with self.assertRaisesRegex(SimulationError, "unmapped code"):
            cpu.step()


if __name__ == "__main__":
    unittest.main()
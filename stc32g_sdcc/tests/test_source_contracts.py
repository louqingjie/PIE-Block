from __future__ import annotations

import unittest
import re
import json
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]


class FirmwareSafetyContractTests(unittest.TestCase):
    def test_spi_probe_has_finite_timeout_api(self) -> None:
        header = (ROOT / "libraries" / "drivers" / "inc" / "CNU_PIE_SPI.h").read_text(
            encoding="utf-8"
        )
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_SPI.c").read_text(
            encoding="utf-8"
        )
        self.assertIn("SPI_TRANSFER_TIMEOUT 2000U", header)
        self.assertIn("SPI_ReadWriteByte_Timeout", header)
        self.assertIn("if (timeout == 0)", source)
        self.assertNotIn("while (!(SPSTAT & 0x80));", source)

    def test_sdcc_never_bit_addresses_non_addressable_spi_sfrs(self) -> None:
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_SPI.c").read_text(
            encoding="utf-8"
        )
        for bit_name in ("SSIG", "SPEN", "DORD", "MSTR", "CPOL", "CPHA", "SPIF", "WCOL"):
            self.assertIsNone(
                re.search(rf"\b{bit_name}\b\s*=", source),
                f"{bit_name} must be accessed through its containing SFR byte under SDCC",
            )
        self.assertIn("SPCTL = control;", source)
        self.assertIn("SPSTAT & 0x80", source)
        self.assertIn("SPSTAT = 0xC0", source)

    def test_other_non_addressable_sfr_bits_use_byte_masks(self) -> None:
        common = (ROOT / "startup" / "common.c").read_text(encoding="utf-8")
        uart = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_UART.c").read_text(
            encoding="utf-8"
        )
        watchdog = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_WDog.c").read_text(
            encoding="utf-8"
        )
        self.assertNotRegex(common, r"\bEAXFR\b\s*=")
        self.assertNotRegex(uart, r"\bES[234]\b\s*=")
        self.assertNotRegex(watchdog, r"\b(?:EN_WDT|CLR_WDT|IDL_WDT)\b\s*=")
        self.assertIn("P_SW2 |= 0x80", common)
        self.assertIn("IE2 |= 0x01", uart)
        self.assertIn("WDT_CONTR |= 0x20", watchdog)

    def test_packaged_sources_do_not_use_unsupported_extended_sbits(self) -> None:
        """SDCC 会把这些别名误编码到经典 8051 位地址，常见结果是破坏 PSW。"""
        header = (ROOT / "include" / "STC32Gxx.h").read_text(encoding="utf-8")
        current_sfr_address: int | None = None
        unsafe_names: set[str] = set()
        for line in header.splitlines():
            sfr_match = re.match(r"__sfr __at \(0x([0-9a-fA-F]+)\) (\w+);", line)
            if sfr_match:
                current_sfr_address = int(sfr_match.group(1), 16)
                continue
            sbit_match = re.match(r"__sbit __at \(0x[0-9a-fA-F]+\) (\w+);", line)
            if sbit_match and current_sfr_address is not None and current_sfr_address & 0x07:
                unsafe_names.add(sbit_match.group(1))

        manifest = json.loads((ROOT / "build_manifest.json").read_text(encoding="utf-8"))
        relative_sources: set[str] = set()
        for sources in manifest["source_groups"].values():
            relative_sources.update(sources)
        relative_sources.update(manifest["source_groups"]["common"])
        relative_sources.update(
            path.relative_to(ROOT).as_posix() for path in (ROOT / "projects").rglob("*.c")
        )

        violations: list[str] = []
        for relative_source in sorted(relative_sources):
            source_path = ROOT / relative_source
            text = source_path.read_text(encoding="utf-8")
            text = re.sub(r"/\*.*?\*/|//[^\n]*", "", text, flags=re.DOTALL)
            used_names = set(re.findall(r"\b[A-Za-z_]\w*\b", text)) & unsafe_names
            if used_names:
                violations.append(f"{relative_source}: {', '.join(sorted(used_names))}")
        self.assertEqual([], violations, "unsupported extended __sbit use:\n" + "\n".join(violations))

    def test_infantry_keeps_radio_initialization_bounded(self) -> None:
        source = (
            ROOT / "projects" / "ROBOMASTER_INFANTRY" / "src" / "main.c"
        ).read_text(encoding="utf-8")
        self.assertIn("for (retry = 0; retry < 20; retry++)", source)
        self.assertIn("SPI_ReadWriteByte", (ROOT / "libraries" / "boards" / "src" / "nrf24l01.c").read_text(encoding="utf-8"))

    def test_robot_projects_send_expansion_frames_atomically(self) -> None:
        projects = (
            "0000.培训模板",
            "FRICTION_CALIBRATION",
            "ROBOMASTER_ENGINEER",
            "TEST",
        )
        for project in projects:
            source = (ROOT / "projects" / project / "src" / "main.c").read_text(
                encoding="utf-8"
            )
            self.assertIn("static void Uart1SendFrameQuery", source, project)
            self.assertIn("uint8_t globalInterruptEnabled = EA", source, project)
            self.assertIn("EA = 0", source, project)
            self.assertIn("Uart1SendFrameQuery(control_frame_pack, 21)", source, project)
            self.assertNotIn(
                "UART_PutChar(UART_1, control_frame_pack[i])", source, project
            )

    def test_infantry_uses_known_good_bytewise_uart_query(self) -> None:
        source = (
            ROOT / "projects" / "ROBOMASTER_INFANTRY" / "src" / "main.c"
        ).read_text(encoding="utf-8")
        self.assertIn("static void Uart1TxQuery(uint8_t dat)", source)
        self.assertIn("Uart1TxQuery(control_frame_pack[i])", source)
        self.assertNotIn("Uart1SendFrameQuery", source)

    def test_robot_chassis_scaling_avoids_float_sign_conversion(self) -> None:
        projects = (
            "0000.培训模板",
            "ROBOMASTER_ENGINEER",
            "ROBOMASTER_INFANTRY",
            "TEST",
        )
        for project in projects:
            source = (ROOT / "projects" / project / "src" / "main.c").read_text(
                encoding="utf-8"
            )
            self.assertNotRegex(source, r"(?:baseSpeed|turnSpeed|_base_spd|_turn_spd)\s*=.*\(float\)", project)
            self.assertIn("int32_t", source, project)
            self.assertIn("2047L", source, project)

    def test_hspwm_prescaler_uses_async_window(self) -> None:
        source = (ROOT / "libraries" / "drivers" / "src" / "CNU_PIE_PWM.c").read_text(
            encoding="utf-8"
        )
        for timer in ("A", "B"):
            for byte in ("H", "L"):
                register = f"PWM{timer}_PSCR{byte}"
                self.assertGreaterEqual(
                    source.count(f"PWM_Write{timer}((uint32_t)&{register}"),
                    2,
                    f"{register} must use the HSPWM async window in init and update",
                )
                self.assertIsNone(
                    re.search(rf"\b{register}\s*=", source),
                    f"direct writes to {register} leave the prescaler at reset value",
                )

    def test_servo_50hz_register_model(self) -> None:
        system_clock = 33_177_600
        requested_frequency = 50
        timer_ticks = system_clock // requested_frequency
        prescaler = timer_ticks >> 16
        period = timer_ticks // (prescaler + 1) - 1
        actual_frequency = system_clock / ((prescaler + 1) * (period + 1))
        self.assertEqual(prescaler, 10)
        self.assertEqual(period, 60_321)
        self.assertAlmostEqual(actual_frequency, requested_frequency, delta=0.001)


if __name__ == "__main__":
    unittest.main()

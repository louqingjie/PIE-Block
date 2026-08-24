from __future__ import annotations

import unittest
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

    def test_infantry_keeps_radio_initialization_bounded(self) -> None:
        source = (
            ROOT / "projects" / "ROBOMASTER_INFANTRY" / "src" / "main.c"
        ).read_text(encoding="utf-8")
        self.assertIn("for (retry = 0; retry < 20; retry++)", source)
        self.assertIn("SPI_ReadWriteByte", (ROOT / "libraries" / "boards" / "src" / "nrf24l01.c").read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()

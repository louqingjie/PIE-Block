from __future__ import annotations

import unittest

from host_model import (
    Nrf24l01LinkStub,
    SpiBusStub,
    SpiTimeout,
    apply_deadband,
    booster_step,
    encode_expansion_frame,
    motor_mix,
    rising_edge,
)


class ControlModelTests(unittest.TestCase):
    def test_deadband_includes_both_boundaries(self) -> None:
        self.assertEqual(apply_deadband(-10, 10), 0)
        self.assertEqual(apply_deadband(10, 10), 0)
        self.assertEqual(apply_deadband(11, 10), 11)
        self.assertEqual(apply_deadband(-11, 10), -11)

    def test_motor_mix_at_rest_and_full_forward(self) -> None:
        self.assertEqual(motor_mix(0, 0), (0, 0, 0, 0))
        self.assertEqual(motor_mix(0, 2047), (-4000, -4000, 4000, 4000))
        self.assertEqual(motor_mix(2047, 0), (-4000, -4000, -4000, -4000))

    def test_sprint_and_arrow_override(self) -> None:
        self.assertEqual(motor_mix(0, 2047, sprint=True), (-8000, -8000, 8000, 8000))
        self.assertEqual(
            motor_mix(0, 0, sprint=True, arrows=(False, False, False, True)),
            (-4000, -4000, -4000, -4000),
        )

    def test_booster_start_ramp_and_safe_stop(self) -> None:
        self.assertEqual(booster_step(0, 800), 500)
        self.assertEqual(booster_step(500, 800), 501)
        self.assertEqual(booster_step(800, 799), 799)
        self.assertEqual(booster_step(500, 0), 0)
        self.assertEqual(booster_step(501, 0), 500)

    def test_rising_edge_only_triggers_once(self) -> None:
        self.assertTrue(rising_edge(True, False))
        self.assertFalse(rising_edge(True, True))
        self.assertFalse(rising_edge(False, True))

    def test_expansion_frame_is_21_bytes_big_endian(self) -> None:
        frame = encode_expansion_frame(0xBB, (0x1234, 0, 500, 800, 0xFFFF, 2, 3, 4))
        self.assertEqual(len(frame), 21)
        self.assertEqual(frame[:3], bytes((0xAB, 0xBC, 0xBB)))
        self.assertEqual(frame[3:5], bytes((0x12, 0x34)))
        self.assertEqual(frame[17:19], bytes((0, 4)))
        self.assertEqual(frame[-2:], bytes((0xCD, 0xDE)))

    def test_expansion_frame_rejects_wrong_shape(self) -> None:
        with self.assertRaises(ValueError):
            encode_expansion_frame(0xAA, (1, 2))


class PeripheralStubTests(unittest.TestCase):
    def test_spi_stub_returns_response(self) -> None:
        spi = SpiBusStub(responses=[0x5A])
        self.assertEqual(spi.transfer(0xFF), 0x5A)
        self.assertEqual(spi.transfers, [0xFF])

    def test_spi_stub_fails_closed_when_device_is_absent(self) -> None:
        spi = SpiBusStub(ready=False)
        with self.assertRaisesRegex(SpiTimeout, "2000 polls"):
            spi.transfer(0xFF)
        self.assertEqual(spi.transfers, [0xFF])

    def test_nrf_link_check_distinguishes_absent_and_present(self) -> None:
        self.assertTrue(Nrf24l01LinkStub(SpiBusStub(), present=True).link_check())
        self.assertFalse(Nrf24l01LinkStub(SpiBusStub(), present=False).link_check())
        self.assertFalse(Nrf24l01LinkStub(SpiBusStub(ready=False)).link_check())


if __name__ == "__main__":
    unittest.main()

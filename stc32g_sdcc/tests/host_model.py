"""步兵最小控制模型与不可用外设桩。

这里不依赖 STC SFR，专门用于主机侧单元测试。公式与
projects/ROBOMASTER_INFANTRY/src/main.c 的纯控制部分保持一致；硬件访问则由
有限等待的桩替代，避免把“外设未接”误判成控制逻辑故障。
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterable


def apply_deadband(value: int, deadband: int) -> int:
    return 0 if abs(value) <= deadband else value


def scale_rocker(value: int, speed: int) -> int:
    """使用与 C 有符号整数除法一致的向零截断缩放。"""

    product = value * speed
    magnitude = abs(product) // 2047
    return -magnitude if product < 0 else magnitude


def motor_mix(
    left_horizontal: int,
    left_vertical: int,
    *,
    max_speed: int = 4000,
    ultra_speed: int = 8000,
    sprint: bool = False,
    arrows: tuple[bool, bool, bool, bool] = (False, False, False, False),
) -> tuple[int, int, int, int]:
    """返回 L1/L2/R1/R2，与固件 CalculateMotorControls 一致。"""

    speed = ultra_speed if sprint else max_speed
    base = scale_rocker(left_vertical, speed)
    turn = scale_rocker(left_horizontal, speed)
    up, down, left, right = arrows
    if up:
        base = max_speed
    if down:
        base = -max_speed
    if left:
        turn = -max_speed
    if right:
        turn = max_speed
    return (-base - turn, -base - turn, base - turn, base - turn)


def split_motor_commands(
    values: Iterable[int],
) -> tuple[tuple[int, ...], tuple[int, ...]]:
    """将有符号电机指令拆成扩展板方向值和无符号占空比。"""

    commands = tuple(values)
    return (
        tuple(1 if value >= 0 else 0 for value in commands),
        tuple(abs(value) for value in commands),
    )


def booster_step(current: int, target: int) -> int:
    """执行固件每个主循环的一步摩擦轮渐变。"""

    if target >= 500 and current < 500:
        return 500
    if current < target:
        return current + 1
    if current > target:
        if current <= 500 and target == 0:
            return 0
        return current - 1
    return current


def rising_edge(current: bool, previous: bool) -> bool:
    return bool(current) and not bool(previous)


def encode_expansion_frame(command: int, data: Iterable[int]) -> bytes:
    """编码扩展板 21 字节帧，数据按大端 uint16_t 发送。"""

    values = tuple(data)
    if len(values) != 8:
        raise ValueError("扩展板帧必须包含 8 个 uint16 数据")
    if not 0 <= command <= 0xFF:
        raise ValueError("命令码必须是 uint8_t")
    frame = bytearray((0xAB, 0xBC, command))
    for value in values:
        if not 0 <= value <= 0xFFFF:
            raise ValueError("扩展板数据必须是 uint16_t")
        frame.extend(((value >> 8) & 0xFF, value & 0xFF))
    frame.extend((0xCD, 0xDE))
    return bytes(frame)


class SpiTimeout(RuntimeError):
    """SPI 完成位在有限轮询内没有出现。"""


@dataclass
class SpiBusStub:
    """可控制完成/不完成状态的 SPI 仿真桩。"""

    ready: bool = True
    responses: list[int] = field(default_factory=list)
    transfers: list[int] = field(default_factory=list)

    def transfer(self, value: int, *, timeout: int = 2000) -> int:
        self.transfers.append(value & 0xFF)
        if not self.ready:
            for _ in range(timeout):
                pass
            raise SpiTimeout(f"SPI transfer timeout after {timeout} polls")
        if self.responses:
            return self.responses.pop(0) & 0xFF
        return 0xFF


@dataclass
class Nrf24l01LinkStub:
    """仅模拟 NRF 链路探测所需的最小行为。"""

    spi: SpiBusStub
    present: bool = True

    def link_check(self) -> bool:
        try:
            for value in (0x30, 0x06, 0x10, 0x06, 0x06, 0x06, 0x06, 0x06):
                self.spi.transfer(value)
        except SpiTimeout:
            return False
        return self.present

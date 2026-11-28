"""PIE-Block 主控板 -> 机械拓展板 UART 协议。

帧格式（UART1，230400 8N1，固定 21 字节）：

    AB BC <cmd> <p60 hi> <p60 lo> ... <p77 hi> <p77 lo> CD DE

协议来源：

- ``docs/guides/RM电控指南.md``
- ``packages/pieblock_core/lib/src/code_generator.dart`` 的
  ``ExpansionBoradControl``
- ``docs/playbook/拓展板通信排障.md``

本模块不依赖 Qt，也不做串口 I/O，方便被单元测试和命令行工具复用。
"""
from __future__ import annotations

from dataclasses import dataclass
from typing import Sequence

FRAME_LEN = 21
HEADER = b"\xAB\xBC"
TAIL = b"\xCD\xDE"
MAX_BUFFER = 8 * 1024

CHANNELS: tuple[str, ...] = (
    "P60",
    "P62",
    "P64",
    "P66",
    "P74",
    "P75",
    "P76",
    "P77",
)

PWM_GROUPS: dict[str, tuple[int, ...]] = {
    "PWMA": (0, 1, 2, 3),
    "PWMB": (4, 5, 6, 7),
}

# 命令码（与 RM 电控指南 / code_generator.dart 保持一致）。
CMD_INIT = 0xAA
CMD_DUTY = 0xBB
CMD_FREQ = 0xCC
CMD_DIR = 0xDD
CMD_ZERO = 0xEE

COMMAND_NAMES: dict[int, str] = {
    CMD_INIT: "初始化",
    CMD_DUTY: "占空比",
    CMD_FREQ: "频率变更",
    CMD_DIR: "方向",
    CMD_ZERO: "归零",
}

INIT_FREQUENCIES = (50, 10000)
DUTY_MAX = 10000

SEVERITY_INFO = "info"
SEVERITY_WARNING = "warning"
SEVERITY_ERROR = "error"


class ProtocolError(ValueError):
    """字节流不符合 21 字节协议帧结构。"""


@dataclass(frozen=True, slots=True)
class Frame:
    """已通过帧头/帧尾/长度校验的原始帧。"""

    raw: bytes
    command: int
    values: tuple[int, ...]
    at_wall: float = 0.0
    at_mono: float = 0.0


@dataclass(frozen=True, slots=True)
class RawBytes:
    """不属于完整合法帧的字节。

    reason:
        garbage  帧头之前的噪声
        bad_tail 疑似帧头但帧尾不匹配，已重同步
        partial  断开/空闲 flush 时残留的未完整帧
        overflow 缓冲超过上限后强制丢弃
    """

    data: bytes
    reason: str
    at_wall: float = 0.0
    at_mono: float = 0.0


@dataclass(frozen=True, slots=True)
class FrameIssue:
    """解析阶段发现的可疑点；key 用于诊断页去重聚合。"""

    key: str
    severity: str
    message: str


@dataclass(frozen=True, slots=True)
class FieldView:
    """命令参数在界面上的显示形式。"""

    channel: str
    value: int
    text: str


@dataclass(frozen=True, slots=True)
class ParsedFrame:
    frame: Frame
    command_name: str
    summary: str
    fields: tuple[FieldView, ...]
    issues: tuple[FrameIssue, ...]

    @property
    def command(self) -> int:
        return self.frame.command

    @property
    def values(self) -> tuple[int, ...]:
        return self.frame.values

    @property
    def is_known(self) -> bool:
        return self.command in COMMAND_NAMES

    @property
    def has_issues(self) -> bool:
        return bool(self.issues)


def format_hex(data: bytes) -> str:
    """大写、空格分隔的 HEX。"""
    return " ".join(f"{byte:02X}" for byte in data)


def command_label(command: int) -> str:
    name = COMMAND_NAMES.get(command)
    if name is None:
        return f"0x{command:02X} 未知命令"
    return f"0x{command:02X} {name}"


def build_frame(command: int, values: Sequence[int]) -> bytes:
    """按当前协议组一帧；用于演示数据和测试。"""
    if not 0 <= command <= 0xFF:
        raise ValueError(f"命令码超出 0..255: {command}")
    if len(values) != len(CHANNELS):
        raise ValueError(f"需要 {len(CHANNELS)} 个参数，实际 {len(values)} 个")

    out = bytearray(HEADER)
    out.append(command)
    for value in values:
        if not 0 <= value <= 0xFFFF:
            raise ValueError(f"参数超出 0..65535: {value}")
        out.append((value >> 8) & 0xFF)
        out.append(value & 0xFF)
    out += TAIL
    if len(out) != FRAME_LEN:
        raise AssertionError(f"内部错误：组帧长度 {len(out)} != {FRAME_LEN}")
    return bytes(out)


def validate_frame(
    raw: bytes, *, at_wall: float = 0.0, at_mono: float = 0.0
) -> Frame:
    """校验结构并解出 8 个大端 uint16。内容是否可疑交给 parse_frame。"""
    if len(raw) != FRAME_LEN:
        raise ProtocolError(f"帧长 {len(raw)} != {FRAME_LEN}")
    if not raw.startswith(HEADER):
        raise ProtocolError(f"帧头错误: {format_hex(raw[:2])}")
    if not raw.endswith(TAIL):
        raise ProtocolError(f"帧尾错误: {format_hex(raw[-2:])}")
    values = tuple(
        (raw[3 + index * 2] << 8) | raw[4 + index * 2] for index in range(len(CHANNELS))
    )
    return Frame(bytes(raw), raw[2], values, at_wall, at_mono)


def parse_frame(frame: Frame) -> ParsedFrame:
    """生成摘要、逐通道显示值和内容诊断。"""
    fields = tuple(
        FieldView(channel, value, _field_text(frame.command, value))
        for channel, value in zip(CHANNELS, frame.values)
    )
    return ParsedFrame(
        frame=frame,
        command_name=COMMAND_NAMES.get(frame.command, "未知命令"),
        summary=_summary(frame),
        fields=fields,
        issues=tuple(_content_issues(frame)),
    )


class FrameParser:
    """增量字节流 -> 协议帧 / 原始字节事件。

    设计目标：
    - 帧头、帧尾被任意切分点切开都能恢复；
    - 坏帧尾后搜索下一个帧头重同步，不吞掉嵌套的合法帧；
    - 噪声里出现伪帧头时不会无限等待（空闲 flush / 缓冲上限）。
    """

    def __init__(self, max_buffer: int = MAX_BUFFER) -> None:
        if max_buffer < FRAME_LEN * 2:
            raise ValueError("max_buffer 至少要是两帧长度")
        self._buf = bytearray()
        self._max_buffer = max_buffer

    @property
    def pending_bytes(self) -> int:
        return len(self._buf)

    def feed(
        self,
        data: bytes,
        *,
        at_wall: float = 0.0,
        at_mono: float = 0.0,
    ) -> list[Frame | RawBytes]:
        """吃掉一段字节，返回本次可确定的事件（顺序与线上一致）。"""
        if data:
            self._buf.extend(data)

        events: list[Frame | RawBytes] = []
        while True:
            header_at = self._buf.find(HEADER)

            if header_at < 0:
                # 末尾单独的 0xAB 可能是被切开的帧头，留到下一次 feed。
                keep = 1 if self._buf[-1:] == HEADER[:1] else 0
                drain = len(self._buf) - keep
                if drain > 0:
                    events.append(
                        RawBytes(
                            bytes(self._buf[:drain]),
                            "garbage",
                            at_wall=at_wall,
                            at_mono=at_mono,
                        )
                    )
                    del self._buf[:drain]
                break

            if header_at > 0:
                events.append(
                    RawBytes(
                        bytes(self._buf[:header_at]),
                        "garbage",
                        at_wall=at_wall,
                        at_mono=at_mono,
                    )
                )
                del self._buf[:header_at]
                continue

            if len(self._buf) < FRAME_LEN:
                break

            if self._buf[FRAME_LEN - 2 : FRAME_LEN] == TAIL:
                raw = bytes(self._buf[:FRAME_LEN])
                del self._buf[:FRAME_LEN]
                events.append(validate_frame(raw, at_wall=at_wall, at_mono=at_mono))
                continue

            # 当前帧头之后 21 字节没有正确帧尾：找下一个帧头重同步。
            next_header = self._buf.find(HEADER, 2)
            if next_header >= 0:
                events.append(
                    RawBytes(
                        bytes(self._buf[:next_header]),
                        "bad_tail",
                        at_wall=at_wall,
                        at_mono=at_mono,
                    )
                )
                del self._buf[:next_header]
                continue

            if len(self._buf) > self._max_buffer:
                # 连续噪声且一直没有下一个帧头：丢弃，但保留末尾可能的半个帧头。
                keep = 1 if self._buf[-1:] == HEADER[:1] else 0
                drain = len(self._buf) - keep
                events.append(
                    RawBytes(
                        bytes(self._buf[:drain]),
                        "overflow",
                        at_wall=at_wall,
                        at_mono=at_mono,
                    )
                )
                del self._buf[:drain]
            break

        return events

    def flush(
        self, *, at_wall: float = 0.0, at_mono: float = 0.0
    ) -> list[RawBytes]:
        """空闲/断开时把残留字节作为事件吐出。"""
        if not self._buf:
            return []
        data = bytes(self._buf)
        self._buf.clear()
        reason = "bad_tail" if data.startswith(HEADER) else "partial"
        return [
            RawBytes(data, reason, at_wall=at_wall, at_mono=at_mono),
        ]


def _field_text(command: int, value: int) -> str:
    if command in (CMD_INIT, CMD_FREQ):
        return f"{value} Hz"
    if command == CMD_DUTY:
        return f"{value} ({value / 100:.2f}%)"
    if command == CMD_DIR:
        if value == 1:
            return "正"
        if value == 0:
            return "负"
        return f"?({value})"
    if command == CMD_ZERO:
        return "0" if value == 0 else f"?({value})"
    return f"0x{value:04X}"


def _summary(frame: Frame) -> str:
    command = frame.command
    values = frame.values
    if command == CMD_INIT:
        return (
            "初始化："
            f"PWMA={_group_frequency(values, PWM_GROUPS['PWMA'])} · "
            f"PWMB={_group_frequency(values, PWM_GROUPS['PWMB'])}"
        )
    if command == CMD_DUTY:
        parts = [
            f"{channel}={value}({value / 100:.2f}%)"
            for channel, value in zip(CHANNELS, values)
            if value
        ]
        return "占空比：" + (" · ".join(parts) if parts else "全部 0%")
    if command == CMD_FREQ:
        return (
            "频率变更："
            f"PWMA={_group_frequency(values, PWM_GROUPS['PWMA'])} · "
            f"PWMB={_group_frequency(values, PWM_GROUPS['PWMB'])}"
        )
    if command == CMD_DIR:
        parts = []
        for channel, value in zip(CHANNELS, values):
            if value == 1:
                parts.append(f"{channel}=正")
            elif value == 0:
                parts.append(f"{channel}=负")
            else:
                parts.append(f"{channel}=?{value}")
        return "方向：" + " ".join(parts)
    if command == CMD_ZERO:
        return "归零：P60–P77 输出清零"
    return f"未知命令 0x{command:02X}"


def _group_frequency(values: tuple[int, ...], indexes: tuple[int, ...]) -> str:
    group_values = [values[index] for index in indexes]
    if all(value == group_values[0] for value in group_values):
        return f"{group_values[0]} Hz"
    return " / ".join(f"{value} Hz" for value in group_values)


def _content_issues(frame: Frame) -> list[FrameIssue]:
    command = frame.command
    values = frame.values
    issues: list[FrameIssue] = []

    if command not in COMMAND_NAMES:
        issues.append(
            FrameIssue(
                key=f"unknown_command:0x{command:02X}",
                severity=SEVERITY_WARNING,
                message=f"未知命令码 0x{command:02X}，固件与上位机协议可能不一致",
            )
        )
        return issues

    if command in (CMD_INIT, CMD_FREQ):
        for group, indexes in PWM_GROUPS.items():
            group_values = [values[index] for index in indexes]
            if any(value != group_values[0] for value in group_values):
                issues.append(
                    FrameIssue(
                        key=f"freq_group:{group}",
                        severity=SEVERITY_WARNING,
                        message=(
                            f"{group} 组内四路频率不一致："
                            f"{', '.join(str(value) for value in group_values)} Hz"
                        ),
                    )
                )

        if command == CMD_INIT:
            for channel, value in zip(CHANNELS, values):
                if value not in INIT_FREQUENCIES:
                    issues.append(
                        FrameIssue(
                            key=f"init_freq:{channel}",
                            severity=SEVERITY_WARNING,
                            message=(
                                f"初始化频率 {channel}={value} Hz 不是约定的 "
                                f"50/10000 Hz"
                            ),
                        )
                    )

    if command == CMD_DUTY:
        for channel, value in zip(CHANNELS, values):
            if value > DUTY_MAX:
                issues.append(
                    FrameIssue(
                        key=f"duty_range:{channel}",
                        severity=SEVERITY_WARNING,
                        message=(
                            f"占空比 {channel}={value} 超出 0–{DUTY_MAX}"
                            f"（{value / 100:.2f}%）"
                        ),
                    )
                )

    if command == CMD_DIR:
        for channel, value in zip(CHANNELS, values):
            if value not in (0, 1):
                issues.append(
                    FrameIssue(
                        key=f"dir_range:{channel}",
                        severity=SEVERITY_WARNING,
                        message=f"方向 {channel}={value} 不是约定的 0/1",
                    )
                )

    if command in (CMD_INIT, CMD_DUTY, CMD_FREQ):
        for channel, value in zip(CHANNELS, values):
            if _looks_byte_duplicated(value):
                issues.append(
                    FrameIssue(
                        key=f"byte_dup:{channel}",
                        severity=SEVERITY_WARNING,
                        message=(
                            f"{channel}=0x{value:04X} 高/低字节相同，"
                            "疑似 SDCC 组帧取错字节（已知坑）"
                        ),
                    )
                )

    return issues


def _looks_byte_duplicated(value: int) -> bool:
    """已知 SDCC 低字节丢失坑的启发式：非零值高字节 == 低字节。"""
    return value != 0 and ((value >> 8) & 0xFF) == (value & 0xFF)

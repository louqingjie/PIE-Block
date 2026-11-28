"""会话状态、统计、链路判定与趋势缓冲（纯 Python，不依赖 Qt）。"""
from __future__ import annotations

from collections import Counter, deque
from dataclasses import dataclass, field
from enum import Enum

from .protocol import (
    CHANNELS,
    CMD_DIR,
    CMD_DUTY,
    CMD_FREQ,
    CMD_INIT,
    CMD_ZERO,
    ParsedFrame,
    RawBytes,
)

FPS_WINDOW_S = 1.0
FRAME_HISTORY_S = 2.0
TREND_WINDOW_S = 10.0
TREND_MAX_POINTS = 2000


@dataclass(slots=True)
class ChannelState:
    """根据最近收到的帧推断的通道状态；None 表示尚未观察到。"""

    duty: int | None = None
    direction: int | None = None
    frequency: int | None = None
    duty_at: float | None = None
    direction_at: float | None = None
    frequency_at: float | None = None


class LinkState(str, Enum):
    DISCONNECTED = "disconnected"
    WAITING = "waiting"
    BYTES_NO_FRAMES = "bytes-no-frames"
    NORMAL = "normal"
    INTERRUPTED = "interrupted"


_LINK_TEXT = {
    LinkState.DISCONNECTED: "未连接",
    LinkState.WAITING: "等待数据",
    LinkState.BYTES_NO_FRAMES: "有字节 · 无有效帧",
    LinkState.NORMAL: "通信正常",
    LinkState.INTERRUPTED: "通信中断",
}

_LINK_HINT = {
    LinkState.DISCONNECTED: "选择串口后点击“连接”开始只读监听",
    LinkState.WAITING: "检查 CH340 RX→P31、GND 共地、主控板供电与固件",
    LinkState.BYTES_NO_FRAMES: (
        "收到字节但解不出协议帧：核对 230400 8N1；"
        "主频异常板可尝试 153600–166667 非标波特率"
    ),
    LinkState.NORMAL: "帧头/帧尾与波特率正常，仅供观测，不代表拓展板输出正常",
    LinkState.INTERRUPTED: "超过 1 s 未收到有效帧：检查主控板是否复位/断电/重新烧录",
}


@dataclass(slots=True)
class SessionStats:
    """一次连接会话内的累计统计与通道状态。"""

    channels: dict[str, ChannelState] = field(
        default_factory=lambda: {pin: ChannelState() for pin in CHANNELS}
    )
    command_counts: Counter = field(default_factory=Counter)
    frame_times: deque[float] = field(default_factory=deque)

    bytes_total: int = 0
    frames_total: int = 0
    bad_frames: int = 0
    non_frame_bytes: int = 0
    started_mono: float | None = None
    last_byte_mono: float | None = None
    last_frame_mono: float | None = None
    last_frame: ParsedFrame | None = None

    def reset(self, now_mono: float | None = None) -> None:
        self.channels = {pin: ChannelState() for pin in CHANNELS}
        self.command_counts.clear()
        self.frame_times.clear()
        self.bytes_total = 0
        self.frames_total = 0
        self.bad_frames = 0
        self.non_frame_bytes = 0
        self.started_mono = now_mono
        self.last_byte_mono = None
        self.last_frame_mono = None
        self.last_frame = None

    def add_bytes(self, count: int, now_mono: float) -> None:
        if count <= 0:
            return
        self.bytes_total += count
        self.last_byte_mono = now_mono

    def apply_frame(self, parsed: ParsedFrame, now_mono: float) -> None:
        self.frames_total += 1
        self.command_counts[parsed.command] += 1
        self.last_frame = parsed
        self.last_frame_mono = now_mono
        self.frame_times.append(now_mono)
        self._trim_frame_times(now_mono)
        self._update_channels(parsed, now_mono)

    def apply_raw(self, event: RawBytes, now_mono: float) -> None:
        self.non_frame_bytes += len(event.data)
        if event.reason == "bad_tail":
            self.bad_frames += 1
        if event.data:
            self.last_byte_mono = now_mono

    def fps(self, now_mono: float) -> float:
        self._trim_frame_times(now_mono)
        return float(len(self.frame_times))

    def duration(self, now_mono: float) -> float:
        if self.started_mono is None:
            return 0.0
        return max(0.0, now_mono - self.started_mono)

    def _trim_frame_times(self, now_mono: float) -> None:
        cutoff = now_mono - FRAME_HISTORY_S
        while self.frame_times and self.frame_times[0] < cutoff:
            self.frame_times.popleft()

    def _update_channels(self, parsed: ParsedFrame, now_mono: float) -> None:
        command = parsed.command
        values = parsed.values
        if command == CMD_INIT or command == CMD_FREQ:
            for pin, value in zip(CHANNELS, values):
                state = self.channels[pin]
                state.frequency = value
                state.frequency_at = now_mono
            return
        if command == CMD_DUTY:
            for pin, value in zip(CHANNELS, values):
                state = self.channels[pin]
                state.duty = value
                state.duty_at = now_mono
            return
        if command == CMD_DIR:
            for pin, value in zip(CHANNELS, values):
                if value in (0, 1):
                    state = self.channels[pin]
                    state.direction = value
                    state.direction_at = now_mono
            return
        if command == CMD_ZERO:
            for pin in CHANNELS:
                state = self.channels[pin]
                state.duty = 0
                state.duty_at = now_mono


@dataclass(slots=True)
class TrendBuffer:
    """每通道最近 N 秒占空比历史，供折线图使用。"""

    window_s: float = TREND_WINDOW_S
    series: dict[str, deque[tuple[float, int]]] = field(
        default_factory=lambda: {pin: deque(maxlen=TREND_MAX_POINTS) for pin in CHANNELS}
    )

    def reset(self) -> None:
        for points in self.series.values():
            points.clear()

    def update(self, parsed: ParsedFrame, now_mono: float) -> None:
        if parsed.command not in (CMD_DUTY, CMD_ZERO):
            return
        for pin, value in zip(CHANNELS, parsed.values):
            points = self.series[pin]
            points.append((now_mono, value))
            self._trim(points, now_mono)

    def points(self, pin: str, now_mono: float) -> list[tuple[float, int]]:
        points = self.series[pin]
        self._trim(points, now_mono)
        return list(points)

    def _trim(self, points: deque[tuple[float, int]], now_mono: float) -> None:
        cutoff = now_mono - self.window_s
        while points and points[0][0] < cutoff:
            points.popleft()


def evaluate_link(
    stats: SessionStats, now_mono: float, *, connected: bool
) -> LinkState:
    """根据最近帧/字节时间判定链路状态。阈值与 UI 文案保持一致。"""
    if not connected:
        return LinkState.DISCONNECTED
    last_frame = stats.last_frame_mono
    if last_frame is not None and now_mono - last_frame <= 0.5:
        return LinkState.NORMAL
    if stats.bytes_total == 0:
        return LinkState.WAITING
    last_byte = stats.last_byte_mono
    if last_byte is not None and now_mono - last_byte <= 0.5:
        return LinkState.BYTES_NO_FRAMES
    if stats.frames_total > 0:
        return LinkState.INTERRUPTED
    return LinkState.WAITING


def link_text(state: LinkState) -> str:
    return _LINK_TEXT[state]


def link_hint(state: LinkState) -> str:
    return _LINK_HINT[state]


def link_severity(state: LinkState) -> str:
    if state is LinkState.NORMAL:
        return "ok"
    if state is LinkState.DISCONNECTED:
        return "idle"
    return "warn"

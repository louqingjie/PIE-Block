"""BUZZER_VOICE_SMOKE 语音合成器的整数模型。

本文件是定点算法的**规格**：固件里的 ``src/voice_synth.c`` 必须与它逐样本一致。
因此这里刻意只使用 Python 整数做与 C 相同的移位/截断运算，并在每一步断言不越界
（C 端没有断言，任何溢出都必须先在这里暴露）。主机侧脚本
``check_voice_model.py`` 会把 C 编译成原生程序、与这里逐样本比对。

参数帧格式（13 字节，100 帧/秒）：

    [0]    基音周期（样本数）；0 表示无周期性激励
    [1]    噪声混合比 0..255（0=纯脉冲串，255=纯噪声）
    [2]    增益 0..255（对 8*残差 RMS 做开方压扩）
    [3..12] 反射系数 k1..k10，有符号 8 位，线性量化（q = round(127*k)）

合成结构就是 TMS5220 那一类：10 阶格型（lattice）全极点滤波器 + 脉冲串/噪声
混合激励，参数按 8 个子步线性插值。
"""

from __future__ import annotations

import math

FRAME_BYTES = 13
ORDER = 10
HOP_SAMPLES = 80
INTERP_STEPS = 8
SAMPLES_PER_STEP = HOP_SAMPLES // INTERP_STEPS  # 10

# TMS5220 的 0,1,2,3,4,5,6,8/8 缓入插值表，Q8。
INTERP_WEIGHT = (0, 32, 64, 96, 128, 160, 192, 256)

# 32*sqrt(16*i+8)：把脉冲幅度按基音周期归一化，使每个子步的激励能量一致。
PITCH_SCALE = (
    90, 157, 202, 239, 272, 300, 326, 350,
    373, 395, 415, 434, 452, 470, 486, 502,
)

# 256*sqrt(3)/8：均匀噪声 ±N 的 RMS 是 N/sqrt(3)，这里把 ±127 的噪声标定到残差 RMS。
NOISE_SCALE = 55
# 增益字节编码 8*残差 RMS（Q3），配合 PITCH_SCALE 即可还原脉冲幅度。
GAIN_LINEAR_SCALE = 8
# 反射系数按 round(127*k) 存成有符号字节，解码回 Q15 要乘 127*258 ≈ 32767。
K_SCALE = 258
# 激励额外右移 4 位再进格型：格型内部的后向误差状态可达激励幅度的 ~30 倍
# （高 Q 共振帧的 L1 增益），必须留够 int16 余量。输出相应右移 8-EXC_SHIFT 位，
# 两者相加必须为 8，否则 8 位输出会削顶或变小。
EXC_SHIFT = 4
OUTPUT_SHIFT = 8 - EXC_SHIFT
# 进格型前的激励幅度必须落在 int16 内。
EXCITATION_LIMIT = 32767

PWM_IDLE = 128
PWM_MAX = 255


def _i16(value: int) -> int:
    assert -32768 <= value <= 32767, f"int16 overflow: {value}"
    return value


def _i32(value: int) -> int:
    assert -(1 << 31) <= value <= (1 << 31) - 1, f"int32 overflow: {value}"
    return value


def decode_gain(gain_byte: int, gain_full_scale: int) -> int:
    """8 位开方压扩 -> 线性增益（对应 C 里的整数乘法）。"""
    return (gain_byte * gain_byte * gain_full_scale) // (255 * 255)


def build_gain_table(gain_full_scale: int) -> list[int]:
    """生成 256 项线性增益表；固件里的 voiceGainTable 与它逐字节相同。"""
    return [decode_gain(value, gain_full_scale) for value in range(256)]


def encode_gain(linear_gain: float, gain_full_scale: int) -> int:
    if linear_gain <= 0.0:
        return 0
    ratio = min(1.0, linear_gain / gain_full_scale)
    return int(round(255.0 * math.sqrt(ratio)))


def unpack_frame(frame: bytes) -> tuple[int, int, int, list[int]]:
    assert len(frame) == FRAME_BYTES
    period = frame[0]
    mix = frame[1]
    gain = frame[2]
    k = [value - 256 if value > 127 else value for value in frame[3:13]]
    return period, mix, gain, k


class VoiceSynth:
    """与固件同构的逐样本合成器。

    ``frames`` 是连续的参数帧字节串，末尾必须有一帧 period=0、gain=0 作为终止帧。
    """

    def __init__(self, frames: bytes, gain_table, tilt: bool = True):
        assert len(frames) % FRAME_BYTES == 0
        assert len(gain_table) == 256
        self.frames = frames
        self.frame_count = len(frames) // FRAME_BYTES
        self.gain_table = gain_table
        self.tilt = tilt

        self.frame_index = 0
        self.active = True
        self.step = 0
        self.samples_left = SAMPLES_PER_STEP
        # 插值两端：prev = 上一帧，cur = 当前帧，目标向 cur 收敛。
        self.prev_period, self.prev_mix, self.prev_gain, self.prev_k = unpack_frame(
            self._frame(0)
        )
        self.cur_period, self.cur_mix, self.cur_gain, self.cur_k = unpack_frame(
            self._frame(0)
        )
        self.k = [0] * (ORDER + 1)
        for m in range(1, ORDER + 1):
            self.k[m] = self.cur_k[m - 1] * K_SCALE
        self.period = self.cur_period
        self.mix = self.cur_mix
        self.gain = self.gain_table[self.cur_gain]
        self.b = [0] * (ORDER + 1)  # b[0] 是上一输出样本
        self.phase = 0
        self.lfsr = 0xACE1
        self.tilt_state = 0
        self.last_out = PWM_IDLE

    def _frame(self, index: int) -> bytes:
        start = index * FRAME_BYTES
        frame = self.frames[start:start + FRAME_BYTES]
        if len(frame) < FRAME_BYTES:
            # 越界按静音帧处理，避免固件读到表尾之外。
            frame = bytes(FRAME_BYTES)
        return frame

    def _advance_step(self) -> None:
        self.step += 1
        if self.step >= INTERP_STEPS:
            self.step = 0
            self.frame_index += 1
            self.prev_period, self.prev_mix, self.prev_gain, self.prev_k = (
                self.cur_period, self.cur_mix, self.cur_gain, self.cur_k,
            )
            self.cur_period, self.cur_mix, self.cur_gain, self.cur_k = unpack_frame(
                self._frame(self.frame_index)
            )
            # 只有越过表尾（也就是过了那段淡出帧）才结束；句中静音帧不能终止播放。
            if self.frame_index >= self.frame_count:
                self.active = False
        weight = INTERP_WEIGHT[self.step]
        # 清浊切换处不插值周期：否则会在 10ms 内扫过几十 Hz~几百 Hz 的假基音。
        if self.prev_period == 0 or self.cur_period == 0:
            if (self.prev_period == 0) != (self.cur_period == 0):
                self.phase = 0
            self.period = self.cur_period
        else:
            self.period = self._lerp(self.prev_period, self.cur_period, weight)
        self.mix = self._lerp(self.prev_mix, self.cur_mix, weight)
        gain_byte = self._lerp(self.prev_gain, self.cur_gain, weight)
        self.gain = self.gain_table[gain_byte]
        for m in range(1, ORDER + 1):
            self.k[m] = self._lerp(self.prev_k[m - 1], self.cur_k[m - 1], weight) * K_SCALE

    @staticmethod
    def _lerp(previous: int, current: int, weight: int) -> int:
        return previous + ((current - previous) * weight >> 8)

    def _noise(self) -> int:
        lsb = self.lfsr & 1
        self.lfsr >>= 1
        if lsb:
            self.lfsr ^= 0xB400
        high = self.lfsr >> 8
        return high - 256 if high > 127 else high

    def _excitation(self) -> int:
        # 脉冲/噪声幅度先留在 32 位，等混完再一次性右移；若先截成 int16，
        # 强浊音帧的脉冲幅度（可达 5 万）会在移位前就溢出。
        impulse = 0
        if self.period > 0:
            self.phase += 1
            if self.phase >= self.period:
                self.phase = 0
                bucket = self.period >> 4
                if bucket > 15:
                    bucket = 15
                impulse = (self.gain * PITCH_SCALE[bucket]) >> 8
        noise = (self._noise() * ((self.gain * NOISE_SCALE) >> 8)) >> 7
        voiced_part = _i32(impulse * (255 - self.mix))
        noise_part = _i32(noise * self.mix)
        return _i16((voiced_part + noise_part) >> (8 + EXC_SHIFT))

    def _lattice(self, excitation: int) -> int:
        # 标准格型合成。分析格型是
        #   f_m(n) = f_{m-1}(n) + k_m b_{m-1}(n-1)
        #   b_m(n) = b_{m-1}(n-1) + k_m f_{m-1}(n)
        # （b 的更新用的是**本级的输入** f_{m-1}）。反解即：
        #   f_{m-1}(n) = f_m(n) - k_m b_{m-1}(n-1)
        #   b_m(n)     = b_{m-1}(n-1) + k_m f_{m-1}(n)
        # 所以必须先算出新的 f_{m-1}，再用它更新 b_m。表里存的是 q_m = -k_m
        # （Levinson 递推里的 value），代入后加减号如下。
        x = excitation
        for m in range(ORDER, 0, -1):
            coefficient = self.k[m]
            tmp = self.b[m - 1]
            x = _i16(x + _i32(coefficient * tmp) // 32768)
            self.b[m] = _i16(tmp - _i32(coefficient * x) // 32768)
        self.b[0] = x
        return x

    def _tilt_filter(self, sample: int) -> int:
        """一阶高频提升，补偿压电片低频滚降（见 docs/design 说明）。"""
        out = _i16(sample - (self.tilt_state * 3 >> 4))
        self.tilt_state = sample
        return out

    def next_sample(self) -> int:
        if not self.active:
            self.last_out = PWM_IDLE
            return self.last_out
        self.samples_left -= 1
        if self.samples_left == 0:
            self.samples_left = SAMPLES_PER_STEP
            self._advance_step()
            if not self.active:
                self.last_out = PWM_IDLE
                return self.last_out
        sample = self._lattice(self._excitation())
        if self.tilt:
            sample = self._tilt_filter(sample)
        scale = OUTPUT_SHIFT
        value = (sample + (1 << (scale - 1))) >> scale
        out = PWM_IDLE + value
        if out < 0:
            out = 0
        elif out > PWM_MAX:
            out = PWM_MAX
        self.last_out = out
        return out


def render(frames: bytes, gain_table, samples: int | None = None,
           tilt: bool = True) -> list[int]:
    synth = VoiceSynth(frames, gain_table, tilt=tilt)
    if samples is None:
        samples = (len(frames) // FRAME_BYTES) * HOP_SAMPLES
    return [synth.next_sample() for _ in range(samples)]

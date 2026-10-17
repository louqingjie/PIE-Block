/*
 * 10 阶 LPC 格型（lattice）语音合成器，结构与 TMS5220 那一类语音芯片相同：
 * 参数帧 100 帧/秒，每帧在 8 个子步上线性插值，激励为脉冲串与噪声的混合。
 *
 * 本文件与 stc32g_sdcc/tools/voice/voice_model.py 逐样本等价：任何改动都必须
 * 同步另一侧，并用 tools/voice/check_voice_model.py 重新校验。
 *
 * 定点约定（关键，别改回去）：
 *   SDCC 的 __mullong（32 位乘法）单次约 590 个周期。每个样本需要约 25 次乘法，
 *   若用 32 位乘法就是 444 µs，而 8kHz 采样只有 125 µs 预算——中断会被持续追尾，
 *   实测播放慢 3.6 倍（P35 亮 12s 才换灯）。因此：
 *     * 格型的 Q15 乘法用 VoiceSynth_MulQ8，两次 16 位乘法，结果与 32 位**完全相等**；
 *     * 插值用 VoiceSynth_Lerp，同样只用 16 位乘法；
 *     * 激励增益每子步预计算一次，样本级只剩两次 16 位乘法。
 */
#include "voice_synth.h"

/* 256*sqrt(3)/8：把 ±127 的均匀噪声标定到与脉冲串相同的每样本能量。 */
#define VOICE_NOISE_SCALE 55
/*
 * 激励右移 4 位再进格型：格型内部的后向误差状态可达激励幅度的 ~30 倍
 * （高 Q 共振帧的 L1 增益），16 位定点必须留够余量。
 * 输出相应右移 8-EXC_SHIFT 位取高 8 位送 PWM，两者相加必须为 8。
 */
#define VOICE_EXC_SHIFT 4
#define VOICE_OUTPUT_SHIFT (8 - VOICE_EXC_SHIFT)

/* 32*sqrt(16*i+8)：按基音周期归一化脉冲幅度，使每样本激励能量一致。 */
static const uint16_t VOICE_CODE voicePitchScale[16] =
{
    90, 157, 202, 239, 272, 300, 326, 350,
    373, 395, 415, 434, 452, 470, 486, 502
};

/* TMS5220 的 0,1,2,3,4,5,6,8/8 缓入插值表，Q8（256 = 1.0）。 */
static const uint16_t VOICE_CODE voiceInterpWeight[VOICE_INTERP_STEPS] =
{
    0, 32, 64, 96, 128, 160, 192, 256
};

static const uint8_t VOICE_CODE *voiceFrames;
static uint16_t voiceFrameCount;
static uint16_t voiceFrameIndex;
static uint16_t voiceFrameOffset;

/*
 * 每样本都要读写热状态，必须放在近内存（__data）。
 * --model-large 下普通 static 落在 XDATA：一次数组索引要先算 24 位地址（约 10 条
 * 指令）+ movx 访问；放进 __data 后是 @Ri 间接寻址（约 3 条指令）。
 * 格型每级有 3 次数组访问，10 级就是每样本 ~360 条指令的差距。
 * 主机侧编译时用 -DVOICE_NEAR= 去掉这个限定符。
 */
#ifndef VOICE_NEAR
#define VOICE_NEAR __data
#endif

static VOICE_NEAR uint8_t voiceActive;
static VOICE_NEAR uint8_t voiceStep;
static VOICE_NEAR uint8_t voiceSamplesLeft;

static uint8_t voicePrevPeriod;
static uint8_t voiceCurPeriod;
static uint8_t voicePrevMix;
static uint8_t voiceCurMix;
static uint8_t voicePrevGain;
static uint8_t voiceCurGain;
static int8_t voicePrevK[VOICE_ORDER];
static int8_t voiceCurK[VOICE_ORDER];

static VOICE_NEAR int8_t voiceK[VOICE_ORDER + 1];  /* 插值后的反射系数 q = round(127*k) */
static VOICE_NEAR uint16_t voicePeriod;
static VOICE_NEAR uint8_t voiceMix;
static VOICE_NEAR uint16_t voiceGain;
static VOICE_NEAR uint8_t voiceNoiseHigh;         /* 每子步预计算：噪声增益的高/低字节 */
static VOICE_NEAR uint8_t voiceNoiseLow;
static VOICE_NEAR int16_t voiceImpulseExc;        /* 每子步预计算：脉冲激励（已右移） */
static VOICE_NEAR int16_t voiceB[VOICE_ORDER + 1];/* voiceB[0] 是上一个输出样本 */
static VOICE_NEAR uint16_t voicePhase;
static VOICE_NEAR uint16_t voiceLfsr;
static VOICE_NEAR int16_t voiceTiltState[VOICE_TILT_STAGES];

/*
 * 把 (|q| * value) >> 7 展开成宏：格型每级要用同一个 q 乘两次，宏内联可以省掉
 * 每样本 20 次函数调用与调用现场保存，这是中断预算的关键。
 * 全部无分支：绝对值用 |x| = (x ^ mask) - mask，条件取负用 (x ^ -m) + m。
 *
 *   value = 256*high + low，其中 high 是**算术右移**（可为负）、low 取低 8 位
 *   （恒为非负，这是补码低位，不是"绝对值的低位"，别把它并进符号里）：
 *     (|q|*value)>>7 = |q|*high*2 + (|q|*low)>>7
 *   两项的符号分别是 sign(q)⊕sign(high) 与 sign(q)；
 *   value<0 时算术右移要向上取整，故 low 项在负数时加 127 再右移。
 */
#define VOICE_MUL_Q8_INLINE(q_magnitude, q_negative, value, result)                    \
    do {                                                                               \
        uint8_t value_bits_ = (uint8_t)((value) >> 8);                                 \
        uint8_t value_sign_mask_ = (uint8_t)((int8_t)value_bits_ >> 7);                \
        uint8_t value_high_magnitude_ = (uint8_t)((value_bits_ ^ value_sign_mask_)     \
                                                  - value_sign_mask_);                 \
        uint8_t value_low_ = (uint8_t)((value) & 0x00FF);                              \
        uint8_t negative_a_ = (uint8_t)((((uint8_t)((q_negative) << 7))                \
                                         ^ value_sign_mask_) >> 7);                    \
        uint8_t negative_b_ = (uint8_t)(q_negative);                                   \
        uint16_t high_product_ = (uint16_t)((uint16_t)(q_magnitude)                    \
                                            * (uint16_t)value_high_magnitude_);        \
        uint16_t low_product_ = (uint16_t)((uint16_t)(q_magnitude)                     \
                                           * (uint16_t)value_low_);                    \
        int16_t term_a_ = (int16_t)(high_product_ << 1);                               \
        int16_t term_b_ = (int16_t)((uint16_t)(low_product_                            \
                                  + (uint16_t)negative_b_ * 127u) >> 7);               \
        term_a_ = (int16_t)((int16_t)(term_a_ ^ (int16_t)(0u - negative_a_))           \
                            + (int16_t)negative_a_);                                   \
        term_b_ = (int16_t)((int16_t)(term_b_ ^ (int16_t)(0u - negative_b_))           \
                            + (int16_t)negative_b_);                                   \
        (result) = (int16_t)(term_a_ + term_b_);                                       \
    } while (0)

/* 宏的包装版本：主机侧校验穷举比对的就是这条路径。 */
static int16_t VoiceSynth_MulQ8(int8_t q, int16_t value)
{
    uint8_t q_bits = (uint8_t)q;
    uint8_t q_sign_mask = (uint8_t)((int8_t)q_bits >> 7);
    uint8_t q_magnitude = (uint8_t)((q_bits ^ q_sign_mask) - q_sign_mask);
    uint8_t q_negative = (uint8_t)(q_sign_mask & 0x01);
    int16_t result;
    VOICE_MUL_Q8_INLINE(q_magnitude, q_negative, value, result);
    return result;
}

/*
 * 精确实现 previous + ((current - previous) * weight >> 8)，只用一条 mul ab。
 *
 * 契约：|current - previous| ≤ 255。本文件里插值只作用于两类值——反射系数
 * （±127）与周期/混合比/增益（0..255），所以差值天然不超过 255，幅值能装进
 * uint8_t，乘积 |d|*w7 ≤ 255*128 = 32640 能装进 uint16_t。
 * weight = 2*w7（w7 ≤ 128），故 (d*weight)>>8 = (d*w7)>>7。
 */
static int16_t VoiceSynth_Lerp(int16_t previous, int16_t current, uint16_t weight)
{
    int16_t difference = (int16_t)(current - previous);
    uint8_t sign_mask = (uint8_t)(difference >> 15);           /* 0x00 / 0xFF */
    uint8_t magnitude = (uint8_t)(((uint8_t)difference ^ sign_mask) - sign_mask);
    uint8_t negative = (uint8_t)(sign_mask & 0x01);
    uint8_t half_weight = (uint8_t)(weight >> 1);
    uint16_t product = (uint16_t)((uint16_t)magnitude * (uint16_t)half_weight);
    int16_t shifted = (int16_t)((uint16_t)(product + (uint16_t)negative * 127u) >> 7);

    shifted = (int16_t)((int16_t)(shifted ^ (int16_t)(0u - negative)) + (int16_t)negative);
    return (int16_t)(previous + shifted);
}

#ifdef VOICE_HOST_BUILD
/* 主机侧校验用的薄包装：让 check_voice_model.py 能穷举比对这两个函数的边界。 */
int16_t VoiceSynth_TestMulQ8(int8_t q, int16_t value)
{
    return VoiceSynth_MulQ8(q, value);
}

int16_t VoiceSynth_TestLerp(int16_t previous, int16_t current, uint16_t weight)
{
    return VoiceSynth_Lerp(previous, current, weight);
}
#endif

static void VoiceSynth_LoadFrame(void)
{
    uint8_t i;
    if (voiceFrameIndex >= voiceFrameCount)
    {
        voiceCurPeriod = 0;
        voiceCurMix = 255;
        voiceCurGain = 0;
        for (i = 0; i < VOICE_ORDER; i++)
            voiceCurK[i] = 0;
        return;
    }
    voiceCurPeriod = voiceFrames[voiceFrameOffset];
    voiceCurMix = voiceFrames[voiceFrameOffset + 1];
    voiceCurGain = voiceFrames[voiceFrameOffset + 2];
    for (i = 0; i < VOICE_ORDER; i++)
        voiceCurK[i] = (int8_t)voiceFrames[voiceFrameOffset + 3 + i];
}

/* 把插值权重应用到本子步的系数与激励增益上。 */
static void VoiceSynth_ApplyStep(uint16_t weight)
{
    uint8_t i;
    int32_t noise_amp;
    int32_t noise_gain;
    int32_t impulse_amp;
    /* 清浊切换处不插值周期：否则会在 10ms 内扫过几十 Hz~几百 Hz 的假基音。 */
    if (voicePrevPeriod == 0 || voiceCurPeriod == 0)
    {
        if ((voicePrevPeriod == 0) != (voiceCurPeriod == 0))
            voicePhase = 0;
        voicePeriod = voiceCurPeriod;
    }
    else
    {
        voicePeriod = (uint16_t)VoiceSynth_Lerp((int16_t)voicePrevPeriod,
                                                (int16_t)voiceCurPeriod, weight);
    }
    voiceMix = (uint8_t)VoiceSynth_Lerp((int16_t)voicePrevMix, (int16_t)voiceCurMix,
                                        weight);
    voiceGain = voiceGainTable[(uint8_t)VoiceSynth_Lerp((int16_t)voicePrevGain,
                                                        (int16_t)voiceCurGain, weight)];
    for (i = 0; i < VOICE_ORDER; i++)
        voiceK[i + 1] = (int8_t)VoiceSynth_Lerp(voicePrevK[i], voiceCurK[i], weight);

    /* 每子步预计算激励增益；这里的 32 位乘法每 10 个样本才跑一次，代价可忽略。 */
    noise_amp = ((int32_t)voiceGain * VOICE_NOISE_SCALE) >> 8;
    noise_gain = (noise_amp * (int32_t)voiceMix) >> 8;
    voiceNoiseHigh = (uint8_t)(noise_gain >> 8);
    voiceNoiseLow = (uint8_t)(noise_gain & 0x00FF);
    if (voicePeriod > 0)
    {
        uint8_t bucket = (uint8_t)(voicePeriod >> 4);
        if (bucket > 15)
            bucket = 15;
        impulse_amp = ((int32_t)voiceGain * voicePitchScale[bucket]) >> 8;
    }
    else
    {
        impulse_amp = 0;
    }
    voiceImpulseExc = (int16_t)((((int32_t)impulse_amp * (255 - (int32_t)voiceMix)) >> 8)
                                >> VOICE_EXC_SHIFT);
}

void VoiceSynth_Start(const uint8_t VOICE_CODE *frames, uint16_t frame_count)
{
    uint8_t i;
    voiceFrames = frames;
    voiceFrameCount = frame_count;
    voiceFrameIndex = 0;
    voiceFrameOffset = 0;
    voiceStep = 0;
    voiceSamplesLeft = VOICE_SAMPLES_PER_STEP;
    voiceActive = (frame_count > 0) ? 1 : 0;
    voicePhase = 0;
    voiceLfsr = 0xACE1;
    for (i = 0; i < VOICE_TILT_STAGES; i++)
        voiceTiltState[i] = 0;
    for (i = 0; i <= VOICE_ORDER; i++)
    {
        voiceB[i] = 0;
        voiceK[i] = 0;
    }
    VoiceSynth_LoadFrame();
    voicePrevPeriod = voiceCurPeriod;
    voicePrevMix = voiceCurMix;
    voicePrevGain = voiceCurGain;
    for (i = 0; i < VOICE_ORDER; i++)
        voicePrevK[i] = voiceCurK[i];
    VoiceSynth_ApplyStep(0);
}

static void VoiceSynth_AdvanceStep(void)
{
    uint8_t i;
    voiceStep++;
    if (voiceStep >= VOICE_INTERP_STEPS)
    {
        voiceStep = 0;
        voiceFrameIndex++;
        voiceFrameOffset += VOICE_FRAME_BYTES;
        voicePrevPeriod = voiceCurPeriod;
        voicePrevMix = voiceCurMix;
        voicePrevGain = voiceCurGain;
        for (i = 0; i < VOICE_ORDER; i++)
            voicePrevK[i] = voiceCurK[i];
        VoiceSynth_LoadFrame();
        /* 只有越过表尾（也就是过了那段淡出帧）才结束；句中静音帧不能终止播放。 */
        if (voiceFrameIndex >= voiceFrameCount)
            voiceActive = 0;
    }
    VoiceSynth_ApplyStep(voiceInterpWeight[voiceStep]);
}

/* 16 位最大长度 LFSR（抽头 0xB400），取高字节作为 ±127 白噪声。 */
static int8_t VoiceSynth_Noise(void)
{
    uint8_t lsb = (uint8_t)(voiceLfsr & 1u);
    voiceLfsr >>= 1;
    if (lsb)
        voiceLfsr ^= 0xB400u;
    return (int8_t)(voiceLfsr >> 8);
}

static int16_t VoiceSynth_Excitation(void)
{
    int16_t impulse = 0;
    int8_t noise;
    int16_t noise_term;
    if (voicePeriod > 0)
    {
        voicePhase++;
        if (voicePhase >= voicePeriod)
        {
            voicePhase = 0;
            impulse = voiceImpulseExc;
        }
    }
    noise = VoiceSynth_Noise();
    /* 同样按绝对值走无符号 8x8 乘法，无分支：见 VoiceSynth_MulQ8 的说明。 */
    {
        uint8_t noise_bits = (uint8_t)noise;
        uint8_t sign_mask = (uint8_t)((int8_t)noise_bits >> 7);
        uint8_t magnitude = (uint8_t)((noise_bits ^ sign_mask) - sign_mask);
        uint8_t negative = (uint8_t)(sign_mask & 0x01);
        uint16_t high_product = (uint16_t)((uint16_t)magnitude * (uint16_t)voiceNoiseHigh);
        uint16_t low_product = (uint16_t)((uint16_t)magnitude * (uint16_t)voiceNoiseLow);
        int16_t combined = (int16_t)((int16_t)(high_product << 1)
                           + (int16_t)((uint16_t)(low_product + (uint16_t)negative * 127u) >> 7));
        noise_term = (int16_t)((int16_t)(combined ^ (int16_t)(0u - negative))
                               + (int16_t)negative);
    }
    return (int16_t)(impulse + (int16_t)(noise_term >> VOICE_EXC_SHIFT));
}

/*
 * 标准格型合成。分析格型是
 *   f_m(n) = f_{m-1}(n) + k_m b_{m-1}(n-1)
 *   b_m(n) = b_{m-1}(n-1) + k_m f_{m-1}(n)      （b 用本级的输入 f_{m-1}）
 * 反解即下面两行：先算新的 f_{m-1}，再用它更新 b_m。表里存 q_m = -k_m。
 */
static int16_t VoiceSynth_Lattice(int16_t excitation)
{
    int16_t x = excitation;
    uint8_t m;
    for (m = VOICE_ORDER; m > 0; m--)
    {
        uint8_t q_bits = (uint8_t)voiceK[m];
        uint8_t q_sign_mask = (uint8_t)((int8_t)q_bits >> 7);
        uint8_t q_magnitude = (uint8_t)((q_bits ^ q_sign_mask) - q_sign_mask);
        uint8_t q_negative = (uint8_t)(q_sign_mask & 0x01);
        int16_t tmp = voiceB[m - 1];
        int16_t delta;
        VOICE_MUL_Q8_INLINE(q_magnitude, q_negative, tmp, delta);
        x = (int16_t)(x + delta);
        VOICE_MUL_Q8_INLINE(q_magnitude, q_negative, x, delta);
        voiceB[m] = (int16_t)(tmp - delta);
    }
    voiceB[0] = x;
    return x;
}

/* 级联一阶高频提升，补偿压电片低频滚降（与试听预览用的是同一组系数）。
 * 注意每级的记忆是**该级自己的输入**，不是当前样本；
 * a = 1/2 用一次算术右移实现：既不碰乘法运行库，也不会溢出。 */
static int16_t VoiceSynth_Tilt(int16_t sample)
{
    int16_t value = sample;
    uint8_t index;
    for (index = 0; index < VOICE_TILT_STAGES; index++)
    {
        int16_t previous = voiceTiltState[index];
        voiceTiltState[index] = value;
        value = (int16_t)(value - (int16_t)(previous >> VOICE_TILT_SHIFT));
    }
    return value;
}

uint8_t VoiceSynth_NextSample(void)
{
    int16_t sample;
    int32_t value;
    int32_t out;
    if (!voiceActive)
        return VOICE_PWM_IDLE;
    voiceSamplesLeft--;
    if (voiceSamplesLeft == 0)
    {
        voiceSamplesLeft = VOICE_SAMPLES_PER_STEP;
        VoiceSynth_AdvanceStep();
        if (!voiceActive)
            return VOICE_PWM_IDLE;
    }
    sample = VoiceSynth_Lattice(VoiceSynth_Excitation());
    sample = VoiceSynth_Tilt(sample);
    value = ((int32_t)sample + (1L << (VOICE_OUTPUT_SHIFT - 1))) >> VOICE_OUTPUT_SHIFT;
    out = (int32_t)VOICE_PWM_IDLE + value;
    if (out < 0)
        out = 0;
    else if (out > 255)
        out = 255;
    return voiceCompressionTable[(uint8_t)out];
}

uint8_t VoiceSynth_IsActive(void)
{
    return voiceActive;
}

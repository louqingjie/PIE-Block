/*
 * 10 阶 LPC 格型（lattice）语音合成器，结构与 TMS5220 那一类语音芯片相同：
 * 参数帧 100 帧/秒，每帧在 8 个子步上线性插值，激励为脉冲串与噪声的混合。
 *
 * 本文件与 stc32g_sdcc/tools/voice/voice_model.py 逐样本等价：任何改动都必须
 * 同步另一侧，并用 tools/voice/check_voice_model.py 重新校验。
 */
#include "voice_synth.h"

#define VOICE_ORDER 10
/* 表里存的是 q = -k（Levinson 递推的 value），解码回 Q15 乘 127*258 ≈ 32767。 */
#define VOICE_K_SCALE 258
/* 256*sqrt(3)/8：把 ±127 的均匀噪声标定到与脉冲串相同的每样本能量。 */
#define VOICE_NOISE_SCALE 55
/*
 * 激励进格型前右移 4 位：格型内部的后向误差状态可达激励幅度的 ~30 倍
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

/* TMS5220 的 0,1,2,3,4,5,6,8/8 缓入插值表，Q8（256 = 1.0，uint8_t 装不下）。 */
static const uint16_t VOICE_CODE voiceInterpWeight[VOICE_INTERP_STEPS] =
{
    0, 32, 64, 96, 128, 160, 192, 256
};

static const uint8_t VOICE_CODE *voiceFrames;
static uint16_t voiceFrameCount;
static uint16_t voiceFrameIndex;
static uint16_t voiceFrameOffset;
static uint8_t voiceActive;
static uint8_t voiceStep;
static uint8_t voiceSamplesLeft;

static uint8_t voicePrevPeriod;
static uint8_t voiceCurPeriod;
static uint8_t voicePrevMix;
static uint8_t voiceCurMix;
static uint8_t voicePrevGain;
static uint8_t voiceCurGain;
static int8_t voicePrevK[VOICE_ORDER];
static int8_t voiceCurK[VOICE_ORDER];

static int16_t voiceK[VOICE_ORDER + 1];   /* 插值后的 Q15 反射系数 */
static uint16_t voicePeriod;
static uint8_t voiceMix;
static uint16_t voiceGain;
static int16_t voiceB[VOICE_ORDER + 1];   /* voiceB[0] 是上一个输出样本 */
static uint16_t voicePhase;
static uint16_t voiceLfsr;
static int16_t voiceTiltState;

/* previous + ((current - previous) * weight >> 8)：负差值的算术右移与模型一致。 */
static int16_t VoiceSynth_Lerp(int16_t previous, int16_t current, uint16_t weight)
{
    int32_t delta = (int32_t)(current - previous) * (int32_t)weight;
    return (int16_t)(previous + (int16_t)(delta >> 8));
}

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
    voiceTiltState = 0;
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
    voicePeriod = voiceCurPeriod;
    voiceMix = voiceCurMix;
    voiceGain = voiceGainTable[voiceCurGain];
    for (i = 0; i < VOICE_ORDER; i++)
        voiceK[i + 1] = (int16_t)((int16_t)voiceCurK[i] * VOICE_K_SCALE);
}

static void VoiceSynth_AdvanceStep(void)
{
    uint16_t weight;
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
    weight = voiceInterpWeight[voiceStep];
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
    voiceMix = (uint8_t)VoiceSynth_Lerp((int16_t)voicePrevMix, (int16_t)voiceCurMix, weight);
    voiceGain = voiceGainTable[(uint8_t)VoiceSynth_Lerp((int16_t)voicePrevGain,
                                                       (int16_t)voiceCurGain, weight)];
    for (i = 0; i < VOICE_ORDER; i++)
        voiceK[i + 1] = (int16_t)(VoiceSynth_Lerp(voicePrevK[i], voiceCurK[i], weight)
                                  * VOICE_K_SCALE);
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
    /* 脉冲/噪声幅度先留在 32 位，等混完再一次性右移；若先截成 int16，
     * 强浊音帧的脉冲幅度（可达 5 万）会在移位前就溢出。 */
    int32_t impulse = 0;
    int32_t noise;
    int32_t mixed;
    if (voicePeriod > 0)
    {
        uint8_t bucket;
        voicePhase++;
        if (voicePhase >= voicePeriod)
        {
            voicePhase = 0;
            bucket = (uint8_t)(voicePeriod >> 4);
            if (bucket > 15)
                bucket = 15;
            impulse = ((int32_t)voiceGain * voicePitchScale[bucket]) >> 8;
        }
    }
    noise = ((int32_t)VoiceSynth_Noise()
             * (((int32_t)voiceGain * VOICE_NOISE_SCALE) >> 8)) >> 7;
    mixed = impulse * (255 - (int32_t)voiceMix) + noise * (int32_t)voiceMix;
    return (int16_t)(mixed >> (8 + VOICE_EXC_SHIFT));
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
        int16_t coefficient = voiceK[m];
        int16_t tmp = voiceB[m - 1];
        x = (int16_t)(x + (int16_t)(((int32_t)coefficient * tmp) >> 15));
        voiceB[m] = (int16_t)(tmp - (int16_t)(((int32_t)coefficient * x) >> 15));
    }
    voiceB[0] = x;
    return x;
}

/* 一阶高频提升，补偿压电片低频滚降（与试听预览用的是同一系数）。 */
static int16_t VoiceSynth_Tilt(int16_t sample)
{
    int16_t out = (int16_t)(sample - ((voiceTiltState * 3) >> 4));
    voiceTiltState = sample;
    return out;
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
    return (uint8_t)out;
}

uint8_t VoiceSynth_IsActive(void)
{
    return voiceActive;
}

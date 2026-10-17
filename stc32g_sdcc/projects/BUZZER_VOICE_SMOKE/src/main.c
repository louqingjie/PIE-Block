/*
 * P33 无源蜂鸣器 LPC-10 语音示例固件。
 *
 * 播两遍语料：「这是P六零，电机调试」和「这是P六十，电机调试」，
 * 用来对比引脚名逐位读（六零）与按数字读（六十）两种念法。
 *
 * 发声链路：Timer0 以 8.0005kHz 中断 -> VoiceSynth_NextSample() 取一个 8 位样本
 * -> 直接写 PWMB CH3 的比较值。PWM 载波固定 129.6kHz（FOSC/256），占空比
 * 0..255 对应 0..100%，50% 占空比即无声；载波远高于音频带，压电片自身
 * 的机械低通把占空比还原成音频包络。
 */
#include "main.h"
#include "voice_synth.h"
#include "voice_data.h"

#define VOICE_BUZZER_CH PWMB_CH3_P33
/* FOSC / 64800 = 512，占空比分辨率 9 位。
 * 载波从 129.6kHz 降到 64.8kHz 是为了响度：压电片是容性负载（约 15nF），
 * 129.6kHz 时容抗只有 ~80Ω，与引脚内阻分压后加到压电片上的电压只剩六成左右；
 * 降一半载波让容抗翻倍，分压损失明显减小，同时仍远高于音频带。 */
#define VOICE_CARRIER_HZ 64800UL
/* PWM_Init 的占空比单位是万分之一：5000 = 50%。 */
#define VOICE_DUTY_IDLE 5000UL
/* Timer0 1T 模式（AUXR.7=1，计数频率 = FOSC）：65536-4608 = 60928，
 * 中断频率 = 33177600/4608 = 7200Hz（正好整除）。 */
#define VOICE_TIMER_RELOAD 60928U
#define VOICE_GAP_MS 800U
#define VOICE_LED_PORT GPIO_P3
#define VOICE_LED_A GPIO_Pin_5
#define VOICE_LED_B GPIO_Pin_6

/*
 * 谐振探测：上电先放一组离散单音（LED 全灭），人耳判断哪个最响。
 * 压电片是窄带谐振器，谐振点通常在 2~4kHz，把语音能量往那个频段搬才是提响度的
 * 正路；不同批次的蜂鸣器谐振点差别很大，所以必须实测而不是猜。置 0 可关闭。
 */
#define VOICE_RESONANCE_SWEEP 1

#if VOICE_RESONANCE_SWEEP
static const uint16_t voiceSweepTones[] =
{
    500, 700, 1000, 1300, 1600, 2000, 2400, 2800, 3200, 3600, 4000, 4500
};
#define VOICE_SWEEP_TONE_COUNT (sizeof(voiceSweepTones) / sizeof(voiceSweepTones[0]))
#define VOICE_SWEEP_ON_MS 300U
#define VOICE_SWEEP_GAP_MS 150U

static void VoiceResonanceSweep(void)
{
    uint16_t index;
    /* 单音测试要独占 PWM：先关采样中断，否则 ISR 会不停改写比较值。 */
    ET0 = 0;
    P35 = 1;
    P36 = 1;
    for (index = 0; index < VOICE_SWEEP_TONE_COUNT; index++)
    {
        PWM_SET_Frequency(VOICE_BUZZER_CH, voiceSweepTones[index], VOICE_DUTY_IDLE);
        Ms_Delay(VOICE_SWEEP_ON_MS);
        PWM_SET_Frequency(VOICE_BUZZER_CH, voiceSweepTones[index], 0);
        Ms_Delay(VOICE_SWEEP_GAP_MS);
    }
    /* 恢复音频载波（ARR 回到 511）与静音占空比，再开中断。 */
    PWM_Init(VOICE_BUZZER_CH, VOICE_CARRIER_HZ, VOICE_DUTY_IDLE);
    ET0 = 1;
}
#endif

/*
 * HSPWM 的比较值寄存器必须经异步窗口写：这与 CNU_PIE_PWM.c 里的
 * PWM_WriteB() 完全一致（该函数是 static，这里复制同一套时序）。
 * PWMB_CH3 的 CCR 地址来自 PWM_CCR_ADDR[PWMB_CH3_P33 >> 4] = 0x7efef9，
 * 异步窗口只取低 8 位，即 0xF9/0xFA。
 */
#define VOICE_CCR3H_ADDR 0xF9
#define VOICE_CCR3L_ADDR 0xFA

static void VoicePwmWriteB(uint8_t address, uint8_t value)
{
    while (HSPWMB_ADR & 0x80)
    {
    }
    HSPWMB_DAT = value;
    HSPWMB_ADR = (uint8_t)(address & 0x7F);
}

void VoiceTimerTick(void)
{
    /* 8 位样本 -> 9 位比较值（ARR = 511），先写高字节再写低字节。 */
    uint16_t compare = (uint16_t)((uint16_t)VoiceSynth_NextSample() << 1);
    VoicePwmWriteB(VOICE_CCR3H_ADDR, (uint8_t)(compare >> 8));
    VoicePwmWriteB(VOICE_CCR3L_ADDR, (uint8_t)(compare & 0x00FF));
}

static void VoiceTimerInit(void)
{
    AUXR |= 0x80;              /* Timer0 走 1T 模式 */
    TMOD &= 0xF0;              /* Timer0 保持 16 位自动重载（STC32G 的 mode 0） */
    TL0 = (uint8_t)(VOICE_TIMER_RELOAD & 0xFF);
    TH0 = (uint8_t)(VOICE_TIMER_RELOAD >> 8);
    TR0 = 1;
    ET0 = 1;
}

static void VoicePlay(const uint8_t VOICE_CODE *frames, uint16_t frame_count,
                      GPIO_Pin_enum led)
{
    P35 = 1;
    P36 = 1;
    led == VOICE_LED_A ? (P35 = 0) : (P36 = 0);
    VoiceSynth_Start(frames, frame_count);
    while (VoiceSynth_IsActive())
    {
        /* 播放完全由 Timer0 中断推进，主循环只等状态。 */
    }
    Ms_Delay(VOICE_GAP_MS);
}

void main(void)
{
    Board_Init();
    /* 板载 LED 低电平点亮，用来区分当前念的是哪一版语料。 */
    GPIO_Init(VOICE_LED_PORT, (GPIO_Pin_enum)(VOICE_LED_A | VOICE_LED_B), GPIO_OUT_PP);
    P35 = 1;
    P36 = 1;

    PWM_Init(VOICE_BUZZER_CH, VOICE_CARRIER_HZ, VOICE_DUTY_IDLE);
    /* 先把合成器置于静音，避免中断在 Start 之前读到未初始化状态。 */
    VoiceSynth_Start(voiceFramesPLiuling, 0);
    VoiceTimerInit();

#if VOICE_RESONANCE_SWEEP
    VoiceResonanceSweep();
#endif

    while (1)
    {
        VoicePlay(voiceFramesPLiuling, VOICE_FRAMES_PLIULING_COUNT, VOICE_LED_A);
        VoicePlay(voiceFramesPLiushi, VOICE_FRAMES_PLIUSHI_COUNT, VOICE_LED_B);
    }
}

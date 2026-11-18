// MIDI 单音音乐代码（由 PIE-Block Flutter 配置器自动生成）
// SDCC 构建额外带 128x64 五线谱滚动显示；Keil 构建保持只播放。
#include "main.h"

// 步兵 Keil 模板仍链接 nrf24l01.c，保留其所需的通道符号。
uint8_t Channal = 36;
#define MUSIC_BUZZER_CH PWMB_CH3_P33
#define MUSIC_DUTY_ON 5000
#define MUSIC_DUTY_OFF 0

static const uint16_t musicFrequencies[128] =
{
__FREQUENCY_ROWS__
};

static void Music_Stop(void)
{
    PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
}

#if defined(__SDCC)
/* 五线谱显示：事件/调号/拍号/字形点阵全部由配置预计算，渲染在固件里完成。 */
#include "OLED_Staff.h"
#include "MusicClock.h"

__STAFF_TABLES__

static void Music_PlayOnce(void)
{
    uint16_t i;
    MusicClock_Reset();
    for (i = 0; i < STAFF_EVENT_COUNT; i++)
    {
        MusicClock_WaitDeadline();
        if (staffPitches[i] == 0)
            Music_Stop();
        else
            PWM_SET_Frequency(MUSIC_BUZZER_CH,
                musicFrequencies[staffPitches[i]], MUSIC_DUTY_ON);
        OLEDStaff_Show(&staffSong, i);
        MusicClock_Advance(staffDurationsMs[i]);
    }
    MusicClock_WaitDeadline();
    Music_Stop();
}
#else
/* Keil 构建：没有 OLED 五线谱显示，保持原来的蜂鸣器播放行为。 */
typedef struct
{
    uint32_t duration_ms;
    uint8_t note;
} MusicSegment;

static const MusicSegment musicSegments[__SEGMENT_COUNT__] =
{
__SEGMENT_ROWS__
};
#define MUSIC_SEGMENT_COUNT __SEGMENT_COUNT__

static void Music_Wait(uint32_t duration_ms)
{
    while (duration_ms > 65535UL)
    {
        Ms_Delay((uint16_t)65535);
        duration_ms -= 65535UL;
    }
    if (duration_ms > 0UL)
        Ms_Delay((uint16_t)duration_ms);
}

static void Music_PlayOnce(void)
{
    uint16_t i;
    for (i = 0; i < MUSIC_SEGMENT_COUNT; i++)
    {
        if (musicSegments[i].note == 0)
            Music_Stop();
        else
            PWM_SET_Frequency(MUSIC_BUZZER_CH,
                musicFrequencies[musicSegments[i].note], MUSIC_DUTY_ON);
        Music_Wait(musicSegments[i].duration_ms);
    }
    Music_Stop();
}
#endif

static void All_Init(void)
{
    Board_Init();
    PWM_Init(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
    Music_Stop();
#if defined(__SDCC)
    MusicClock_Init();
    OLEDStaff_Init();
#endif
}

void main(void)
{
    All_Init();
    while (1)
        Music_PlayOnce();
}

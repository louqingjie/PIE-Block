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
    1000, 9, 9, 10, 10, 11, 12, 12,
    13, 14, 15, 15, 16, 17, 18, 19,
    21, 22, 23, 24, 26, 28, 29, 31,
    33, 35, 37, 39, 41, 44, 46, 49,
    52, 55, 58, 62, 65, 69, 73, 78,
    82, 87, 92, 98, 104, 110, 117, 123,
    131, 139, 147, 156, 165, 175, 185, 196,
    208, 220, 233, 247, 262, 277, 294, 311,
    330, 349, 370, 392, 415, 440, 466, 494,
    523, 554, 587, 622, 659, 698, 740, 784,
    831, 880, 932, 988, 1047, 1109, 1175, 1245,
    1319, 1397, 1480, 1568, 1661, 1760, 1865, 1976,
    2093, 2217, 2349, 2489, 2637, 2794, 2960, 3136,
    3322, 3520, 3729, 3951, 4186, 4435, 4699, 4978,
    5274, 5588, 5920, 6272, 6645, 7040, 7459, 7902,
    8372, 8870, 9397, 9956, 10548, 11175, 11840, 12544
};

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

static void Music_Stop(void)
{
    PWM_SET_Frequency(MUSIC_BUZZER_CH, 1000, MUSIC_DUTY_OFF);
}

#if defined(__SDCC)
/* 五线谱显示：事件/调号/拍号/字形点阵全部由配置预计算，渲染在固件里完成。 */
#include "OLED_Staff.h"

/* ---- 五线谱显示数据（由 Pie-Block 代码生成器自动生成）---- */
#define STAFF_EVENT_COUNT 14
#define STAFF_GLYPH_COUNT 22
#define STAFF_KEY_COUNT 0
#define STAFF_EVENT_STORAGE 14

static const uint16_t staffGlyphRows[] =
{
    0x00C0, 0x01E0, 0x0120, 0x0120, 0x0120, 0x0120, 0x00E0, 0x00E0, 0x0070, 0x007C, 0x005C, 0x004E,
    0x03C6, 0x07E3, 0x0FF1, 0x08B1, 0x0891, 0x0893, 0x0902, 0x0504, 0x03F8, 0x0100, 0x0100, 0x0330,
    0x0370, 0x0170, 0x00E0, 0x0000, 0x0078, 0x00CE, 0x0D86, 0x0D82, 0x018E, 0x019E, 0x0D8C, 0x0C80,
    0x00C0, 0x0070, 0x001E, 0x000A, 0x000A, 0x001F, 0x000A, 0x001F, 0x000A, 0x000A, 0x0001, 0x0001,
    0x0001, 0x0001, 0x0007, 0x0009, 0x0007, 0x0001, 0x0001, 0x0007, 0x0005, 0x0007, 0x0004, 0x0004,
    0x0006, 0x000F, 0x0006, 0x0006, 0x0009, 0x0006, 0x001F, 0x001F, 0x001F, 0x001F, 0x0006, 0x0001,
    0x0002, 0x0004, 0x0002, 0x0001, 0x0002, 0x0001, 0x0002, 0x0002, 0x0002, 0x0001, 0x0002, 0x0002,
    0x0002, 0x001C, 0x0026, 0x0062, 0x007A, 0x006F, 0x0066, 0x0022, 0x001C, 0x001C, 0x001A, 0x0018,
    0x0018, 0x0018, 0x0018, 0x0018, 0x003E, 0x001C, 0x0032, 0x0020, 0x0030, 0x0018, 0x000C, 0x0006,
    0x007E, 0x000F, 0x0018, 0x0018, 0x000E, 0x0018, 0x0010, 0x0018, 0x000F, 0x0038, 0x0038, 0x0034,
    0x0036, 0x0032, 0x007F, 0x0030, 0x0030, 0x001F, 0x0001, 0x0001, 0x000F, 0x0018, 0x0010, 0x0018,
    0x000F, 0x0038, 0x0006, 0x0002, 0x003E, 0x0026, 0x0062, 0x0026, 0x001C, 0x003E, 0x0020, 0x0030,
    0x0010, 0x0018, 0x0008, 0x000C, 0x0004, 0x003C, 0x0022, 0x0036, 0x001C, 0x0036, 0x0022, 0x0022,
    0x003C, 0x001C, 0x0022, 0x0022, 0x0032, 0x003E, 0x0020, 0x0030, 0x001E
};

static const StaffGlyph staffGlyphDescs[] =
{
    {13, 27, 0},
    {12, 12, 27},
    {5, 7, 39},
    {4, 7, 46},
    {3, 7, 53},
    {4, 3, 60},
    {4, 3, 63},
    {5, 2, 66},
    {5, 2, 68},
    {3, 6, 70},
    {2, 4, 76},
    {2, 5, 80},
    {7, 8, 85},
    {7, 8, 93},
    {7, 8, 101},
    {6, 8, 109},
    {7, 8, 117},
    {6, 8, 125},
    {7, 8, 133},
    {7, 8, 141},
    {7, 8, 149},
    {7, 8, 157}
};

static const StaffGlyphSet staffGlyphSet =
    {22, staffGlyphRows, staffGlyphDescs};

static const uint32_t staffTickDurations[] =
{
    480UL, 480UL, 480UL, 480UL, 480UL, 480UL, 960UL, 480UL,
    480UL, 480UL, 480UL, 480UL, 480UL, 960UL
};

static const uint32_t staffDurationsMs[] =
{
    500UL, 500UL, 500UL, 500UL, 500UL, 500UL, 1000UL, 500UL,
    500UL, 500UL, 500UL, 500UL, 500UL, 1000UL
};

static const uint8_t staffPitches[] =
{
    0x3C, 0x3C, 0x43, 0x43, 0x45, 0x45, 0x43, 0x41, 0x41, 0x40, 0x40, 0x3E, 0x3E, 0x3C
};

static const uint8_t staffFlags[] =
{
    0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x08, 0x18, 0x18, 0x18, 0x18, 0x18, 0x18, 0x08
};

static const int8_t staffSteps[] =
{
    -0x02, -0x02, 0x02, 0x02, 0x03, 0x03, 0x02, 0x01, 0x01, 0x00, 0x00, -0x01, -0x01, -0x02
};

static const int8_t staffKeyStepsTreble[] =
{
    0x00
};

static const int8_t staffKeyStepsBass[] =
{
    0x00
};

static const StaffSong staffSong =
{
    14,
    480,
    4,
    4,
    0,
    1,
    staffTickDurations,
    staffDurationsMs,
    staffPitches,
    staffSteps,
    staffFlags,
    staffKeyStepsTreble,
    staffKeyStepsBass,
    &staffGlyphSet
};


static void Music_PlayOnce(void)
{
    uint16_t i;
    for (i = 0; i < STAFF_EVENT_COUNT; i++)
    {
        OLEDStaff_Show(&staffSong, i);
        if (staffPitches[i] == 0)
            Music_Stop();
        else
            PWM_SET_Frequency(MUSIC_BUZZER_CH,
                musicFrequencies[staffPitches[i]], MUSIC_DUTY_ON);
        Music_Wait(staffDurationsMs[i]);
    }
    Music_Stop();
}
#else
/* Keil 构建：没有 OLED 五线谱显示，保持原来的蜂鸣器播放行为。 */
typedef struct
{
    uint32_t duration_ms;
    uint8_t note;
} MusicSegment;

static const MusicSegment musicSegments[8] =
{
    {1000UL, 60},
    {1000UL, 67},
    {1000UL, 69},
    {1000UL, 67},
    {1000UL, 65},
    {1000UL, 64},
    {1000UL, 62},
    {1000UL, 60},
};
#define MUSIC_SEGMENT_COUNT 8

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
    OLEDStaff_Init();
#endif
}

void main(void)
{
    All_Init();
    while (1)
        Music_PlayOnce();
}

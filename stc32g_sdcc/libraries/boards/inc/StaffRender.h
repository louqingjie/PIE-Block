#ifndef STAFF_RENDER_H
#define STAFF_RENDER_H

#include <stdint.h>

/* 128x64 单色 OLED 帧缓冲（SSD1306 页格式：frame[page*128+x]，bit0 = 页内最上一行）。 */
#define STAFF_WIDTH        128
#define STAFF_HEIGHT       64
#define STAFF_FRAME_BYTES  (STAFF_WIDTH * (STAFF_HEIGHT / 8))

/* 版面常量：与 pieblock_core 的 staff_layout.dart 保持一致，主机对拍会逐字节校验。 */
#define STAFF_SPACE            6
#define STAFF_TOP              14
#define STAFF_PX_PER_QUARTER   16
#define STAFF_MIN_NOTE_GAP     6
#define STAFF_PANEL_GUTTER     6
#define STAFF_CLEF_WIDTH       13
#define STAFF_TIME_DIGIT_WIDTH 7

/* 字形编号：顺序必须与 pieblock_core 的 StaffGlyphId 一致。 */
enum
{
    STAFF_GLYPH_TREBLE_CLEF = 0,
    STAFF_GLYPH_BASS_CLEF,
    STAFF_GLYPH_SHARP,
    STAFF_GLYPH_FLAT,
    STAFF_GLYPH_NATURAL,
    STAFF_GLYPH_NOTE_HEAD_FILLED,
    STAFF_GLYPH_NOTE_HEAD_HOLLOW,
    STAFF_GLYPH_REST_WHOLE,
    STAFF_GLYPH_REST_HALF,
    STAFF_GLYPH_REST_QUARTER,
    STAFF_GLYPH_REST_EIGHTH,
    STAFF_GLYPH_REST_SIXTEENTH,
    STAFF_GLYPH_DIGIT_0,
    STAFF_GLYPH_DIGIT_1,
    STAFF_GLYPH_DIGIT_2,
    STAFF_GLYPH_DIGIT_3,
    STAFF_GLYPH_DIGIT_4,
    STAFF_GLYPH_DIGIT_5,
    STAFF_GLYPH_DIGIT_6,
    STAFF_GLYPH_DIGIT_7,
    STAFF_GLYPH_DIGIT_8,
    STAFF_GLYPH_DIGIT_9,
    STAFF_GLYPH_COUNT
};

/* 事件 flags 位定义（与 staff_firmware_c.dart 的 staffFirmwareFlags 一致）。 */
#define STAFF_FLAG_ACCIDENTAL_MASK 0x03u
#define STAFF_FLAG_ACCIDENTAL_SHIFT 0u
#define STAFF_FLAG_CLEF_MASK       0x04u
#define STAFF_FLAG_CLEF_SHIFT      2u
#define STAFF_FLAG_NOTE_VALUE_MASK 0xF8u
#define STAFF_FLAG_NOTE_VALUE_SHIFT 3u

#define STAFF_ACCIDENTAL_NONE    0
#define STAFF_ACCIDENTAL_SHARP   1
#define STAFF_ACCIDENTAL_FLAT    2
#define STAFF_ACCIDENTAL_NATURAL 3

#define STAFF_CLEF_TREBLE 0
#define STAFF_CLEF_BASS   1

/* 时值编码：0 全音符、1 二分、2 附点二分、3 四分、4 附点四分、5 八分、
   6 附点八分、7 十六分、8 附点十六分。 */
#define STAFF_NOTE_VALUE_WHOLE          0
#define STAFF_NOTE_VALUE_HALF           1
#define STAFF_NOTE_VALUE_DOTTED_HALF    2
#define STAFF_NOTE_VALUE_QUARTER        3
#define STAFF_NOTE_VALUE_DOTTED_QUARTER 4
#define STAFF_NOTE_VALUE_EIGHTH         5
#define STAFF_NOTE_VALUE_DOTTED_EIGHTH  6
#define STAFF_NOTE_VALUE_SIXTEENTH      7
#define STAFF_NOTE_VALUE_DOTTED_SIXTEENTH 8

/* 字形：每行一个 uint16 位掩码，bit0 = 最左像素，bit1 = 右边一格。 */
typedef struct
{
    uint8_t  width;
    uint8_t  height;
    uint16_t rowOffset; /* 在 StaffGlyphSet.rows 中的行偏移 */
} StaffGlyph;

typedef struct
{
    uint8_t           count;
    const uint16_t   *rows;
    const StaffGlyph *descs;
} StaffGlyphSet;

/* 显示歌曲：事件表采用 SoA（结构体数组会因对齐浪费 flash）。
 * 事件首尾相接，startTick 由 C 侧累加 tickDurations 得到；不需要 32 位绝对 tick 表。 */
typedef struct
{
    uint16_t count;
    uint16_t ticksPerQuarter;
    uint8_t  timeNumerator;
    uint8_t  timeDenominator;
    uint8_t  keyCount;   /* 0..7 */
    uint8_t  keyIsSharp; /* 1 = 升号调 */
    const uint32_t *tickDurations;
    const uint32_t *durationsMs;
    const uint8_t  *pitches;  /* 0 = 休止符 */
    const int8_t   *steps;    /* 相对谱号底线的全音阶步数（已按调号拼写） */
    const uint8_t  *flags;
    const int8_t   *keyStepsTreble;
    const int8_t   *keyStepsBass;
    const StaffGlyphSet *glyphs;
} StaffSong;

/* 渲染第 index 帧到 1024 字节帧缓冲（先清零）。index 必须 < song->count。 */
void StaffRender_DrawFrame(const StaffSong *song, uint16_t index,
                           uint8_t *frame1024);

/* 供主机测试检查版面常量用（真实固件不使用）。 */
uint16_t StaffRender_PanelWidth(const StaffSong *song);
uint16_t StaffRender_NoteAreaStart(const StaffSong *song);
uint16_t StaffRender_CursorX(const StaffSong *song);

#endif /* STAFF_RENDER_H */

/* 五线谱帧渲染器：把 StaffSong 的预计算显示事件画成 128x64 1bit 页格式帧。
 *
 * 版面几何与 pieblock_core/lib/src/staff_layout.dart 完全一致（纯整数运算），
 * 绘制顺序/禁区/隔离带/整颗不截断等规则与 tool/render_oled_staff.dart 一致；
 * 主机对拍测试 stc32g_sdcc/tests/test_staff_render_host.py 会逐字节校验。
 *
 * 只依赖 <stdint.h>/<string.h> 与 StaffRender.h，主机构建（gcc）和 C251
 * 固件构建（SDCC --mmcs251 --model-large）都能编译。
 */

#include <stdint.h>
#include <string.h>

#include "StaffRender.h"

/* 谱表关键 y 坐标（staff_layout.dart 的 staffBottomLineY / 中间线）。 */
#define STAFF_BOTTOM_LINE_Y (STAFF_TOP + 4 * STAFF_SPACE)
#define STAFF_MIDDLE_LINE_Y (STAFF_TOP + 2 * STAFF_SPACE)

/* 滚动区绘制窗口：超出后整颗裁掉，与 Dart 模拟器的常量一致。 */
#define STAFF_SKIP_LEFT  24
#define STAFF_SKIP_RIGHT 18

/* 当前播放位置左侧最多同时可见约 10 个事件（128px / 最小步进 6px），
 * 24 个槽位留足余量。未初始化 static 数组在 --model-large 下进 XSEG。 */
#define STAFF_LEFT_CAPACITY 24

static int32_t staffLeftX[STAFF_LEFT_CAPACITY];

/* ------------------------------------------------------------------------- */
/* 帧缓冲基础操作：bit0 = 页内最上一行（SSD1306 页格式）。                    */
/* ------------------------------------------------------------------------- */

static void StaffSetPixel(uint8_t *frame, int32_t x, int32_t y, uint8_t on)
{
    uint16_t index;
    uint8_t mask;

    if (x < 0 || x >= STAFF_WIDTH || y < 0 || y >= STAFF_HEIGHT)
    {
        return;
    }
    index = (uint16_t)(((uint16_t)y >> 3) * STAFF_WIDTH + (uint16_t)x);
    mask = (uint8_t)(1u << ((uint8_t)y & 0x07u));
    if (on != 0u)
    {
        frame[index] |= mask;
    }
    else
    {
        frame[index] &= (uint8_t)~mask;
    }
}

static void StaffHLine(uint8_t *frame, int32_t x1, int32_t x2, int32_t y)
{
    int32_t x;
    int32_t start = x1 < x2 ? x1 : x2;
    int32_t end = x1 < x2 ? x2 : x1;

    for (x = start; x <= end; x++)
    {
        StaffSetPixel(frame, x, y, 1u);
    }
}

static void StaffVLine(uint8_t *frame, int32_t x, int32_t y1, int32_t y2)
{
    int32_t y;
    int32_t start = y1 < y2 ? y1 : y2;
    int32_t end = y1 < y2 ? y2 : y1;

    for (y = start; y <= end; y++)
    {
        StaffSetPixel(frame, x, y, 1u);
    }
}

static void StaffClearRect(uint8_t *frame, int32_t x, int32_t y, int32_t w,
                           int32_t h)
{
    int32_t yy;
    int32_t xx;

    for (yy = y; yy < y + h; yy++)
    {
        for (xx = x; xx < x + w; xx++)
        {
            StaffSetPixel(frame, xx, yy, 0u);
        }
    }
}

/* ------------------------------------------------------------------------- */
/* 字形表访问：字形行是 uint16 位掩码，bit0 = 最左像素。                       */
/* ------------------------------------------------------------------------- */

static const StaffGlyph *StaffGlyphDescr(const StaffSong *song, uint8_t id)
{
    return &song->glyphs->descs[id];
}

static void StaffBlitGlyph(uint8_t *frame, const StaffSong *song, uint8_t id,
                           int32_t x, int32_t y)
{
    const StaffGlyph *glyph = StaffGlyphDescr(song, id);
    const uint16_t *rows = song->glyphs->rows + glyph->rowOffset;
    uint8_t row;
    uint8_t col;

    for (row = 0; row < glyph->height; row++)
    {
        uint16_t bits = rows[row];

        if (bits == 0u)
        {
            continue;
        }
        for (col = 0; col < glyph->width; col++)
        {
            if ((bits & (uint16_t)(1u << col)) != 0u)
            {
                StaffSetPixel(frame, x + (int32_t)col, y + (int32_t)row, 1u);
            }
        }
    }
}

static uint8_t StaffIsStaffLineRow(int32_t y)
{
    uint8_t line;

    for (line = 0; line <= 4u; line++)
    {
        if (y == (int32_t)STAFF_TOP + (int32_t)line * STAFF_SPACE)
        {
            return 1u;
        }
    }
    return 0u;
}

/* 画升/降/还原号：先擦掉字形包围盒内的谱线像素，再落点阵。
 * 否则压在谱线上的升号中心空洞会被谱线填成实心（看起来像“工/日”）。 */
static void StaffBlitAccidental(uint8_t *frame, const StaffSong *song,
                                uint8_t id, int32_t x, int32_t centerY)
{
    const StaffGlyph *glyph = StaffGlyphDescr(song, id);
    const uint16_t *rows = song->glyphs->rows + glyph->rowOffset;
    int32_t top = centerY - (int32_t)(glyph->height / 2u);
    int32_t row;
    int32_t col;

    for (row = 0; row < (int32_t)glyph->height; row++)
    {
        uint16_t bits = rows[row];
        int32_t py = top + row;

        if (StaffIsStaffLineRow(py) == 0u)
        {
            continue;
        }
        for (col = 0; col < (int32_t)glyph->width; col++)
        {
            if ((bits & (uint16_t)(1u << (uint8_t)col)) == 0u)
            {
                StaffSetPixel(frame, x + col, py, 0u);
            }
        }
    }
    StaffBlitGlyph(frame, song, id, x, top);
}

/* ------------------------------------------------------------------------- */
/* 事件解码（flags 位定义见 StaffRender.h）。                                 */
/* ------------------------------------------------------------------------- */

static uint8_t StaffEventAccidental(const StaffSong *song, uint16_t index)
{
    return (uint8_t)(song->flags[index] & STAFF_FLAG_ACCIDENTAL_MASK);
}

static uint8_t StaffEventClef(const StaffSong *song, uint16_t index)
{
    return (uint8_t)((song->flags[index] & STAFF_FLAG_CLEF_MASK) >>
                     STAFF_FLAG_CLEF_SHIFT);
}

static uint8_t StaffEventNoteValue(const StaffSong *song, uint16_t index)
{
    return (uint8_t)((song->flags[index] & STAFF_FLAG_NOTE_VALUE_MASK) >>
                     STAFF_FLAG_NOTE_VALUE_SHIFT);
}

static uint8_t StaffEventIsRest(const StaffSong *song, uint16_t index)
{
    return (uint8_t)(song->pitches[index] == 0u ? 1u : 0u);
}

static uint8_t StaffNoteDenominator(uint8_t code)
{
    switch (code)
    {
    case STAFF_NOTE_VALUE_WHOLE:
        return 1u;
    case STAFF_NOTE_VALUE_HALF:
    case STAFF_NOTE_VALUE_DOTTED_HALF:
        return 2u;
    case STAFF_NOTE_VALUE_QUARTER:
    case STAFF_NOTE_VALUE_DOTTED_QUARTER:
        return 4u;
    case STAFF_NOTE_VALUE_EIGHTH:
    case STAFF_NOTE_VALUE_DOTTED_EIGHTH:
        return 8u;
    case STAFF_NOTE_VALUE_SIXTEENTH:
    case STAFF_NOTE_VALUE_DOTTED_SIXTEENTH:
        return 16u;
    default:
        return 4u;
    }
}

static uint8_t StaffNoteDots(uint8_t code)
{
    switch (code)
    {
    case STAFF_NOTE_VALUE_DOTTED_HALF:
    case STAFF_NOTE_VALUE_DOTTED_QUARTER:
    case STAFF_NOTE_VALUE_DOTTED_EIGHTH:
    case STAFF_NOTE_VALUE_DOTTED_SIXTEENTH:
        return 1u;
    default:
        return 0u;
    }
}

static uint8_t StaffClefChangeAt(const StaffSong *song, uint16_t index)
{
    if (index == 0u)
    {
        return 0u;
    }
    return (uint8_t)(StaffEventClef(song, index) !=
                     StaffEventClef(song, (uint16_t)(index - 1u)));
}

/* staff_layout.dart 的 staffAdvanceFor：同一行相邻事件的最小推进量。 */
static uint16_t StaffAdvanceFor(const StaffSong *song, uint16_t index)
{
    uint16_t width;

    width = StaffEventIsRest(song, index) != 0u ? 7u : STAFF_MIN_NOTE_GAP;
    if (StaffEventAccidental(song, index) != 0u)
    {
        width = (uint16_t)(width + 4u);
    }
    if (StaffClefChangeAt(song, index) != 0u)
    {
        width = (uint16_t)(width + 16u);
    }
    return width;
}

/* ------------------------------------------------------------------------- */
/* 版面几何（staff_layout.dart）。                                             */
/* ------------------------------------------------------------------------- */

static uint8_t StaffDigitCount(uint16_t value)
{
    if (value >= 100u)
    {
        return 3u;
    }
    if (value >= 10u)
    {
        return 2u;
    }
    return 1u;
}

uint16_t StaffRender_PanelWidth(const StaffSong *song)
{
    uint8_t numeratorDigits;
    uint8_t denominatorDigits;
    uint8_t timeDigits;
    uint16_t width;

    if (song == 0)
    {
        return 0u;
    }
    numeratorDigits = StaffDigitCount(song->timeNumerator);
    denominatorDigits = StaffDigitCount(song->timeDenominator);
    timeDigits = numeratorDigits > denominatorDigits ? numeratorDigits
                                                     : denominatorDigits;
    width = (uint16_t)(1u + STAFF_CLEF_WIDTH + 1u +
                       6u * (uint16_t)song->keyCount + 2u);
    width = (uint16_t)(width + (uint16_t)STAFF_TIME_DIGIT_WIDTH * timeDigits +
                       (uint16_t)(timeDigits - 1u) + 1u);
    return width;
}

uint16_t StaffRender_NoteAreaStart(const StaffSong *song)
{
    return (uint16_t)(StaffRender_PanelWidth(song) + STAFF_PANEL_GUTTER);
}

uint16_t StaffRender_CursorX(const StaffSong *song)
{
    uint16_t noteAreaStart = StaffRender_NoteAreaStart(song);
    int32_t remaining = (int32_t)STAFF_WIDTH - (int32_t)noteAreaStart;

    return (uint16_t)((int32_t)noteAreaStart + (remaining * 3) / 10);
}

/* 与 Dart `staffRoundDiv` 等价的“半值远离 0”整数除法。 */
static int32_t StaffRoundDiv(int32_t numerator, int32_t denominator)
{
    if (denominator == 0)
    {
        return 0;
    }
    if (denominator < 0)
    {
        numerator = -numerator;
        denominator = -denominator;
    }
    if (numerator >= 0)
    {
        return (numerator + denominator / 2) / denominator;
    }
    return -((-numerator + denominator / 2) / denominator);
}

static int32_t StaffYForStep(int8_t step)
{
    return (int32_t)STAFF_BOTTOM_LINE_Y - ((int32_t)step * STAFF_SPACE) / 2;
}

/* 事件 startTick 由 C 侧累加 tickDurations 得到（StaffRender.h）。 */
static uint32_t StaffStartTickOf(const StaffSong *song, uint16_t index)
{
    uint32_t tick = 0u;
    uint16_t i;

    for (i = 0u; i < index; i++)
    {
        tick += song->tickDurations[i];
    }
    return tick;
}

static uint32_t StaffBarTicks(const StaffSong *song)
{
    uint32_t ticksPerQuarter = song->ticksPerQuarter;
    uint32_t denominator = song->timeDenominator == 0u ? 1u
                                                       : song->timeDenominator;
    uint32_t numerator = song->timeNumerator == 0u ? 1u : song->timeNumerator;

    return (ticksPerQuarter * 4u / denominator) * numerator;
}

/* ------------------------------------------------------------------------- */
/* 固定区（谱号 + 调号 + 拍号）。                                              */
/* ------------------------------------------------------------------------- */

static void StaffDrawStaffLines(uint8_t *frame)
{
    uint8_t line;

    for (line = 0u; line <= 4u; line++)
    {
        StaffHLine(frame, 0, STAFF_WIDTH - 1,
                   (int32_t)STAFF_TOP + (int32_t)line * STAFF_SPACE);
    }
}

static void StaffDrawClef(uint8_t *frame, const StaffSong *song, uint8_t clef,
                          int32_t x)
{
    if (clef == STAFF_CLEF_BASS)
    {
        /* 低音谱号的两个点夹住第 2 条线（F 线）。 */
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_BASS_CLEF, x,
                       (int32_t)STAFF_TOP + STAFF_SPACE - 4);
    }
    else
    {
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_TREBLE_CLEF, x,
                       (int32_t)STAFF_TOP - 2);
    }
}

static void StaffDrawKeySignature(uint8_t *frame, const StaffSong *song,
                                  uint8_t clef)
{
    const int8_t *steps;
    uint8_t glyphId;
    uint16_t i;
    int32_t x;

    if (song->keyCount == 0u)
    {
        return;
    }
    steps = clef == STAFF_CLEF_BASS ? song->keyStepsBass
                                    : song->keyStepsTreble;
    glyphId = song->keyIsSharp != 0u ? (uint8_t)STAFF_GLYPH_SHARP
                                     : (uint8_t)STAFF_GLYPH_FLAT;
    x = 1 + STAFF_CLEF_WIDTH + 1;
    for (i = 0u; i < (uint16_t)song->keyCount; i++)
    {
        StaffBlitAccidental(frame, song, glyphId, x, StaffYForStep(steps[i]));
        x += 6;
    }
}

static void StaffDrawTimeNumber(uint8_t *frame, const StaffSong *song,
                                uint16_t value, int32_t x, int32_t y)
{
    uint8_t digits[3];
    uint8_t count = StaffDigitCount(value);
    uint8_t i;
    uint16_t remaining = value;

    for (i = count; i > 0u; i--)
    {
        digits[i - 1u] = (uint8_t)(remaining % 10u);
        remaining = (uint16_t)(remaining / 10u);
    }
    for (i = 0u; i < count; i++)
    {
        StaffBlitGlyph(frame, song,
                       (uint8_t)(STAFF_GLYPH_DIGIT_0 + digits[i]),
                       x + (int32_t)i * (STAFF_TIME_DIGIT_WIDTH + 1), y);
    }
}

static void StaffDrawTimeSignature(uint8_t *frame, const StaffSong *song,
                                   uint16_t panelWidth)
{
    uint8_t numeratorDigits = StaffDigitCount(song->timeNumerator);
    uint8_t denominatorDigits = StaffDigitCount(song->timeDenominator);
    uint8_t timeDigits = numeratorDigits > denominatorDigits
                             ? numeratorDigits
                             : denominatorDigits;
    int32_t width =
        (int32_t)STAFF_TIME_DIGIT_WIDTH * (int32_t)timeDigits +
        ((int32_t)timeDigits - 1);
    int32_t x = (int32_t)panelWidth - width - 1;
    /* 数字 7×8：上数字跨第 1–2 线，下数字跨第 3–4 线。 */
    int32_t topY = (int32_t)STAFF_TOP + STAFF_SPACE - 4;
    int32_t bottomY = (int32_t)STAFF_TOP + 3 * STAFF_SPACE - 4;

    StaffDrawTimeNumber(frame, song, song->timeNumerator, x, topY);
    StaffDrawTimeNumber(frame, song, song->timeDenominator, x, bottomY);
}

/* 清空 [0,noteAreaStart) 禁区/隔离带后重绘谱线与固定内容。 */
static void StaffDrawFixedPanel(uint8_t *frame, const StaffSong *song,
                                uint16_t noteAreaStart, uint16_t panelWidth,
                                uint8_t clef)
{
    uint8_t line;

    StaffClearRect(frame, 0, 0, (int32_t)noteAreaStart, STAFF_HEIGHT);
    for (line = 0u; line <= 4u; line++)
    {
        StaffHLine(frame, 0, (int32_t)noteAreaStart - 1,
                   (int32_t)STAFF_TOP + (int32_t)line * STAFF_SPACE);
    }
    StaffDrawClef(frame, song, clef, 1);
    StaffDrawKeySignature(frame, song, clef);
    StaffDrawTimeSignature(frame, song, panelWidth);
}

/* 当前播放位置上方的小三角（谱线上方 y=8/9/10）。 */
static void StaffDrawCursorMarker(uint8_t *frame, int32_t cursorX)
{
    int32_t top = (int32_t)STAFF_TOP - 6; /* STAFF_TOP 恒为 14，无需再夹到 0。 */

    StaffHLine(frame, cursorX - 2, cursorX + 2, top);
    StaffHLine(frame, cursorX - 1, cursorX + 1, top + 1);
    StaffSetPixel(frame, cursorX, top + 2, 1u);
}

/* ------------------------------------------------------------------------- */
/* 小节线：staff_layout.dart 的 staffBarLineXs。                              */
/* ------------------------------------------------------------------------- */

static void StaffDrawBarLines(uint8_t *frame, const StaffSong *song,
                              uint16_t cursorX, uint16_t noteAreaStart,
                              uint32_t playTick)
{
    uint32_t barTicks = StaffBarTicks(song);
    uint32_t ticksPerQuarter = song->ticksPerQuarter;
    uint32_t maxTick;
    uint32_t bar;
    uint32_t tick;

    if (barTicks == 0u || ticksPerQuarter == 0u)
    {
        return;
    }
    maxTick = playTick + ticksPerQuarter * 8u;
    bar = playTick / barTicks;
    for (;;)
    {
        int32_t x;

        tick = bar * barTicks;
        if (tick < barTicks)
        {
            bar++;
            continue;
        }
        if (tick > maxTick)
        {
            break;
        }
        x = (int32_t)cursorX +
            StaffRoundDiv((int32_t)(tick - playTick) * STAFF_PX_PER_QUARTER,
                          (int32_t)ticksPerQuarter);
        if (x >= (int32_t)noteAreaStart && x < STAFF_WIDTH)
        {
            StaffVLine(frame, x, STAFF_TOP, STAFF_BOTTOM_LINE_Y);
        }
        bar++;
    }
}

/* ------------------------------------------------------------------------- */
/* 音符 / 休止符。                                                            */
/* ------------------------------------------------------------------------- */

static void StaffDrawLedgerLines(uint8_t *frame, int32_t x, int8_t step)
{
    int32_t lineStep;

    if (step > 8)
    {
        for (lineStep = 10; lineStep <= (int32_t)step; lineStep += 2)
        {
            StaffHLine(frame, x - 3, x + 3,
                       (int32_t)STAFF_BOTTOM_LINE_Y -
                           (lineStep * STAFF_SPACE) / 2);
        }
    }
    else if (step < 0)
    {
        for (lineStep = -2; lineStep >= (int32_t)step; lineStep -= 2)
        {
            StaffHLine(frame, x - 3, x + 3,
                       (int32_t)STAFF_BOTTOM_LINE_Y -
                           (lineStep * STAFF_SPACE) / 2);
        }
    }
}

static void StaffDrawFlagUp(uint8_t *frame, int32_t stemX, int32_t y)
{
    StaffSetPixel(frame, stemX + 1, y, 1u);
    StaffSetPixel(frame, stemX + 2, y + 1, 1u);
    StaffSetPixel(frame, stemX + 2, y + 2, 1u);
}

static void StaffDrawFlagDown(uint8_t *frame, int32_t stemX, int32_t y)
{
    StaffSetPixel(frame, stemX + 1, y, 1u);
    StaffSetPixel(frame, stemX + 2, y - 1, 1u);
    StaffSetPixel(frame, stemX + 2, y - 2, 1u);
}

static uint8_t StaffAccidentalGlyph(uint8_t accidental)
{
    switch (accidental)
    {
    case STAFF_ACCIDENTAL_SHARP:
        return (uint8_t)STAFF_GLYPH_SHARP;
    case STAFF_ACCIDENTAL_FLAT:
        return (uint8_t)STAFF_GLYPH_FLAT;
    default:
        return (uint8_t)STAFF_GLYPH_NATURAL;
    }
}

static void StaffDrawNote(uint8_t *frame, const StaffSong *song,
                          uint16_t index, int32_t x, int32_t y)
{
    uint8_t accidental = StaffEventAccidental(song, index);
    uint8_t code = StaffEventNoteValue(song, index);
    uint8_t denominator = StaffNoteDenominator(code);
    uint8_t hollow = (uint8_t)(denominator <= 2u ? 1u : 0u);
    int8_t step = song->steps[index];
    uint8_t stemUp = (uint8_t)(((int32_t)step - 4) < 0 ? 1u : 0u);
    int32_t headLeft = x - 2;
    int32_t headTop = y - 1;

    StaffDrawLedgerLines(frame, x, step);
    if (accidental != 0u)
    {
        uint8_t glyphId = StaffAccidentalGlyph(accidental);
        const StaffGlyph *glyph = StaffGlyphDescr(song, glyphId);

        /* 临时记号右沿统一落在 x-4，和符头（左沿 x-2）之间留 1px 空隙。 */
        StaffBlitAccidental(frame, song, glyphId,
                            x - (int32_t)glyph->width - 3, y);
    }

    StaffBlitGlyph(frame, song,
                   hollow != 0u ? (uint8_t)STAFF_GLYPH_NOTE_HEAD_HOLLOW
                                : (uint8_t)STAFF_GLYPH_NOTE_HEAD_FILLED,
                   headLeft, headTop);
    if (StaffNoteDots(code) != 0u)
    {
        StaffSetPixel(frame, x + 3, y - (hollow != 0u ? 1 : 0), 1u);
    }
    if (denominator > 1u)
    {
        /* 符干 8px：向上时从符头顶部向上，向下时从符头底部向下。 */
        int32_t stemX = stemUp != 0u ? headLeft + 3 : headLeft;
        int32_t stemTop = stemUp != 0u ? headTop - 8 : headTop;
        int32_t stemBottom = stemUp != 0u ? headTop : headTop + 11;
        uint8_t flagCount = denominator == 8u ? 1u
                            : (denominator == 16u ? 2u : 0u);
        uint8_t flag;

        StaffVLine(frame, stemX, stemTop, stemBottom);
        for (flag = 0u; flag < flagCount; flag++)
        {
            if (stemUp != 0u)
            {
                StaffDrawFlagUp(frame, stemX, stemTop + (int32_t)flag * 3);
            }
            else
            {
                StaffDrawFlagDown(frame, stemX, stemBottom - (int32_t)flag * 3);
            }
        }
    }
}

static void StaffDrawRest(uint8_t *frame, const StaffSong *song,
                          uint16_t index, int32_t x)
{
    uint8_t denominator = StaffNoteDenominator(StaffEventNoteValue(song, index));

    switch (denominator)
    {
    case 1u:
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_REST_WHOLE, x - 2,
                       (int32_t)STAFF_TOP + STAFF_SPACE + 1);
        break;
    case 2u:
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_REST_HALF, x - 2,
                       (int32_t)STAFF_MIDDLE_LINE_Y - 2);
        break;
    case 4u:
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_REST_QUARTER, x - 1,
                       (int32_t)STAFF_MIDDLE_LINE_Y - 3);
        break;
    case 8u:
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_REST_EIGHTH, x,
                       (int32_t)STAFF_MIDDLE_LINE_Y - 2);
        break;
    case 16u:
        StaffBlitGlyph(frame, song, (uint8_t)STAFF_GLYPH_REST_SIXTEENTH, x,
                       (int32_t)STAFF_MIDDLE_LINE_Y - 3);
        break;
    default:
        break;
    }
}

/* 单个滚动事件：跳过规则与 Dart 模拟器 renderFrame 的循环体一致。 */
static void StaffDrawEvent(uint8_t *frame, const StaffSong *song,
                           uint16_t index, int32_t x, uint16_t noteAreaStart)
{
    uint8_t accidental = StaffEventAccidental(song, index);
    uint8_t isRest = StaffEventIsRest(song, index);
    uint16_t leftExtent = isRest != 0u ? 2u : (accidental != 0u ? 7u : 3u);

    if (x < (int32_t)noteAreaStart - STAFF_SKIP_LEFT)
    {
        return;
    }
    if (x > (int32_t)STAFF_WIDTH + STAFF_SKIP_RIGHT)
    {
        return;
    }
    /* 音符/休止符必须完整落在禁区外：任何被固定区/隔离带截断的音符不画。 */
    if (x - (int32_t)leftExtent < (int32_t)noteAreaStart)
    {
        return;
    }
    if (isRest != 0u)
    {
        StaffDrawRest(frame, song, index, x);
        return;
    }

    {
        int32_t y = StaffYForStep(song->steps[index]);

        if (y < -2 || y > (int32_t)STAFF_HEIGHT + 1)
        {
            return;
        }
        /* 换谱号处画一个小谱号；落在固定区/隔离带里时不画。 */
        if (index > 0u && StaffClefChangeAt(song, index) != 0u &&
            x - 16 >= (int32_t)noteAreaStart)
        {
            StaffDrawClef(frame, song, StaffEventClef(song, index), x - 16);
        }
        StaffDrawNote(frame, song, index, x, y);
    }
}

/* ------------------------------------------------------------------------- */
/* 帧入口。                                                                   */
/* ------------------------------------------------------------------------- */

void StaffRender_DrawFrame(const StaffSong *song, uint16_t index,
                           uint8_t *frame1024)
{
    uint8_t *frame = frame1024;
    uint16_t panelWidth;
    uint16_t noteAreaStart;
    uint16_t cursorX;
    uint32_t playTick;
    uint32_t forwardTick;
    uint16_t leftCount = 0u;
    uint16_t leftStart;
    uint16_t i;

    if (frame1024 == 0)
    {
        return;
    }
    memset(frame1024, 0, STAFF_FRAME_BYTES);
    if (song == 0 || song->glyphs == 0 || song->count == 0u ||
        index >= song->count)
    {
        return;
    }

    panelWidth = StaffRender_PanelWidth(song);
    noteAreaStart = (uint16_t)(panelWidth + STAFF_PANEL_GUTTER);
    cursorX = StaffRender_CursorX(song);
    playTick = StaffStartTickOf(song, index);

    StaffDrawStaffLines(frame);
    StaffDrawBarLines(frame, song, cursorX, noteAreaStart, playTick);

    /* 当前事件左侧：从 index 向左按最小间距后扫（冻结公式见 staff_layout）。 */
    if (index > 0u)
    {
        int32_t previousX = (int32_t)cursorX;
        int32_t advanceRight = (int32_t)StaffAdvanceFor(song, index);
        int32_t leftLimit = (int32_t)noteAreaStart - STAFF_SKIP_LEFT;
        uint32_t tick = playTick;
        uint16_t j = index;

        while (j > 0u)
        {
            uint16_t k = (uint16_t)(j - 1u);
            int32_t x;
            int32_t maximum;

            tick -= song->tickDurations[k];
            x = (int32_t)cursorX +
                StaffRoundDiv((int32_t)(tick - playTick) * STAFF_PX_PER_QUARTER,
                              (int32_t)song->ticksPerQuarter);
            maximum = previousX - advanceRight;
            if (x > maximum)
            {
                x = maximum;
            }
            /* 再往左只会更小（每步至少 -6），已经在窗口外的都不用画。 */
            if (x < leftLimit)
            {
                break;
            }
            if (leftCount >= STAFF_LEFT_CAPACITY)
            {
                break; /* 防御性上限：128px 屏幕实际最多 ~10 个。 */
            }
            staffLeftX[leftCount] = x;
            leftCount++;
            previousX = x;
            advanceRight = (int32_t)StaffAdvanceFor(song, k);
            j = k;
        }
    }
    leftStart = (uint16_t)(index - leftCount);

    /* 按索引升序绘制，保持与 Dart 模拟器相同的遮叠顺序。 */
    forwardTick = playTick;
    {
        int32_t forwardPreviousX = (int32_t)cursorX;

        for (i = leftStart; i < song->count; i++)
        {
            int32_t x;

            if (i < index)
            {
                /* 缓冲区按下标降序存放：leftX[0] = x[index-1]。 */
                x = staffLeftX[(uint16_t)(index - 1u - i)];
            }
            else if (i == index)
            {
                x = (int32_t)cursorX;
            }
            else
            {
                int32_t xt;
                int32_t minimum;

                forwardTick += song->tickDurations[(uint16_t)(i - 1u)];
                xt = (int32_t)cursorX +
                     StaffRoundDiv(
                         (int32_t)(forwardTick - playTick) *
                             STAFF_PX_PER_QUARTER,
                         (int32_t)song->ticksPerQuarter);
                minimum = forwardPreviousX + (int32_t)StaffAdvanceFor(song, i);
                if (xt < minimum)
                {
                    xt = minimum;
                }
                x = xt;
                forwardPreviousX = x;
                /* 右侧单调递增，超出绘制窗口后可以整段停止。 */
                if (x > (int32_t)STAFF_WIDTH + STAFF_SKIP_RIGHT)
                {
                    break;
                }
            }
            StaffDrawEvent(frame, song, i, x, noteAreaStart);
        }
    }

    /* 左端固定区 + 隔离带是禁区：清空后只重绘谱线和固定内容。 */
    StaffDrawFixedPanel(frame, song, noteAreaStart, panelWidth,
                        StaffEventClef(song, index));
    StaffDrawCursorMarker(frame, (int32_t)cursorX);
}

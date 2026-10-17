/*
 * 音乐固件时间基准：Timer0 mode 1（16-bit）自由计数，主循环轮询差值。
 *
 * 设计要点：
 * - 不启用定时器中断：中断里任何 MOVC/XDATA 访问都可能改动 DPXL，而 SDCC
 *   的 ISR 入口不保存 DPXL；一旦在 main 的 MOVC/@DPX 指令间隙里发生中断，
 *   会读错代码常量或 XDATA。纯轮询可以从根上避免这个问题。
 * - 每次采样把 16-bit 计数器的差值累加到 32-bit ticks；只要相邻采样间隔小于
 *   16-bit 溢出周期（FOSC/12 时约 23.7ms）就不会丢计数。OLED_Staff_Show 在
 *   渲染后、刷屏后各 poll 一次，播放等待循环本身也持续采样。
 * - 上电用 Ms_Delay(10) 做一次 ticks/ms 校准，兼容 Timer0 被配成 1T 或其它
 *   频率的情况；若计时器完全不动，则回退到 Ms_Delay 节奏，保证还能播放。
 */

#include "MusicClock.h"

#include "common.h"

/* Timer0 12T 模式下的理论值：FOSC/12/1000 ≈ 2764.8。 */
#define MUSIC_CLOCK_DEFAULT_TICKS_PER_MS 2765UL
/* 校准后 ticks/ms 的合理范围：12T≈2765，1T≈33178。 */
#define MUSIC_CLOCK_MIN_TICKS_PER_MS 1000UL
#define MUSIC_CLOCK_MAX_TICKS_PER_MS 40000UL
/* 单次 Advance 的分块上限，避免 durationMs * ticksPerMs 溢出 32 位。 */
#define MUSIC_CLOCK_ADVANCE_CHUNK_MS 60000UL
#define MUSIC_CLOCK_CALIBRATION_SAMPLES 10u
#define MUSIC_CLOCK_CALIBRATION_MS 10u

static volatile uint32_t musicClockTicks;
static uint16_t musicClockLast;
static uint32_t musicClockDeadline;
static uint32_t musicClockTicksPerMs;
static uint8_t musicClockReady;

static uint16_t MusicClock_ReadTimer(void)
{
    uint8_t hi;
    uint8_t lo;
    uint8_t hiAgain;

    for (;;)
    {
        hi = TH0;
        lo = TL0;
        hiAgain = TH0;
        if (hi == hiAgain)
        {
            return (uint16_t)(((uint16_t)hiAgain << 8) | (uint16_t)lo);
        }
    }
}

void MusicClock_Poll(void)
{
    uint16_t now = MusicClock_ReadTimer();
    uint16_t delta = (uint16_t)(now - musicClockLast);

    musicClockLast = now;
    musicClockTicks += (uint32_t)delta;
}

static uint32_t MusicClock_Ticks(void)
{
    MusicClock_Poll();
    return musicClockTicks;
}

static void MusicClock_DelayMs(uint32_t durationMs)
{
    while (durationMs > 60000UL)
    {
        Ms_Delay((uint16_t)60000);
        durationMs -= 60000UL;
    }
    if (durationMs > 0UL)
    {
        Ms_Delay((uint16_t)durationMs);
    }
}

void MusicClock_Init(void)
{
    uint32_t startTicks;
    uint32_t deltaTicks;
    uint32_t ticksPerMs;
    uint8_t i;

    TR0 = 0;
    TF0 = 0;
    ET0 = 0;
    /* mode 1：16-bit 定时器，自由计数；保留 TMOD 高 4 位（Timer1 配置）。 */
    TMOD = (uint8_t)((TMOD & 0xF0u) | 0x01u);
    TH0 = 0;
    TL0 = 0;
    TR0 = 1;

    musicClockTicks = 0;
    musicClockDeadline = 0;
    musicClockTicksPerMs = MUSIC_CLOCK_DEFAULT_TICKS_PER_MS;
    musicClockReady = 0;
    musicClockLast = MusicClock_ReadTimer();

    /* 用 10 次 Ms_Delay(10) 校准实际 ticks/ms，采样间隔 10ms 远小于 23.7ms。 */
    startTicks = MusicClock_Ticks();
    for (i = 0; i < MUSIC_CLOCK_CALIBRATION_SAMPLES; i++)
    {
        Ms_Delay(MUSIC_CLOCK_CALIBRATION_MS);
        MusicClock_Poll();
    }
    deltaTicks = MusicClock_Ticks() - startTicks;
    ticksPerMs = deltaTicks / (MUSIC_CLOCK_CALIBRATION_SAMPLES *
                               MUSIC_CLOCK_CALIBRATION_MS);
    if (ticksPerMs >= MUSIC_CLOCK_MIN_TICKS_PER_MS &&
        ticksPerMs <= MUSIC_CLOCK_MAX_TICKS_PER_MS)
    {
        musicClockTicksPerMs = ticksPerMs;
        musicClockReady = 1;
    }
}

void MusicClock_Reset(void)
{
    musicClockDeadline = MusicClock_Ticks();
}

void MusicClock_WaitDeadline(void)
{
    if (!musicClockReady)
    {
        return;
    }
    while ((int32_t)(MusicClock_Ticks() - musicClockDeadline) < 0)
    {
        /* 自旋等待：毫秒级调度，CPU 空闲开销可忽略。 */
    }
}

void MusicClock_Advance(uint32_t durationMs)
{
    if (!musicClockReady)
    {
        /* 计时器不可用时退回旧的 Ms_Delay 节奏：略慢但保证能播放。 */
        MusicClock_DelayMs(durationMs);
        return;
    }
    while (durationMs > MUSIC_CLOCK_ADVANCE_CHUNK_MS)
    {
        musicClockDeadline +=
            MUSIC_CLOCK_ADVANCE_CHUNK_MS * musicClockTicksPerMs;
        durationMs -= MUSIC_CLOCK_ADVANCE_CHUNK_MS;
    }
    musicClockDeadline += durationMs * musicClockTicksPerMs;
}

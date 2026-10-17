/*
 * 音乐固件时间基准：Timer0 mode 1（16-bit）自由计数 + 溢出中断。
 *
 * - tick 率 = FOSC / 12（STC32G 复位后 AUXR=0，Timer0 为 12T 模式）；
 * - 溢出中断只把 0x10000 累加到 32-bit 计数，不重装初值，因此 ISR 延迟
 *   不会像"重装初值"那样每次丢掉中断响应期间走过的计数；
 * - 读计时器时短暂关全局中断并处理读取期间挂起的 TF0，得到一致的
 *   32-bit 扩展 ticks；
 * - 调度期限用 ticks 表示，等待用有符号差值比较，32-bit 回绕也正确。
 */

#include "MusicClock.h"

#include "common.h"

/* 1ms 对应的 Timer0 ticks 数（FOSC/12/1000，四舍五入到 2765）。 */
#define MUSIC_CLOCK_TICKS_PER_MS ((FOSC + 6000UL) / 12000UL)

static volatile uint32_t musicClockTicks;
static uint32_t musicClockDeadline;

void MusicClock_Isr(void) __interrupt (TMR0_VECTOR)
{
    TF0 = 0;
    musicClockTicks += 0x10000UL;
}

void MusicClock_Init(void)
{
    musicClockTicks = 0;
    musicClockDeadline = 0;

    TR0 = 0;
    TF0 = 0;
    /* mode 1：16-bit 定时器；保留 TMOD 高 4 位（Timer1 配置）。 */
    TMOD = (uint8_t)((TMOD & 0xF0u) | 0x01u);
    TH0 = 0;
    TL0 = 0;

    ET0 = 1;
    TR0 = 1;
}

static uint32_t MusicClock_ReadTicks(void)
{
    uint8_t hi;
    uint8_t lo;
    uint8_t hiAgain;
    uint8_t irq;
    uint32_t base;

    irq = EA;
    EA = 0;

    for (;;)
    {
        hi = TH0;
        lo = TL0;
        hiAgain = TH0;
        if (hi != hiAgain)
        {
            /* 读取过程中刚好 16 位溢出，重读一次。 */
            continue;
        }
        if (TF0)
        {
            /* 溢出已发生但 ISR 还没跑：补上这一圈再重读当前计数值。 */
            musicClockTicks += 0x10000UL;
            TF0 = 0;
            continue;
        }
        break;
    }

    base = musicClockTicks + (((uint32_t)hiAgain << 8) | (uint32_t)lo);
    if (irq)
    {
        EA = 1;
    }
    return base;
}

void MusicClock_Reset(void)
{
    musicClockDeadline = MusicClock_ReadTicks();
}

void MusicClock_WaitDeadline(void)
{
    while ((int32_t)(MusicClock_ReadTicks() - musicClockDeadline) < 0)
    {
        /* 自旋等待：毫秒级调度，CPU 空闲开销可忽略。 */
    }
}

void MusicClock_Advance(uint32_t durationMs)
{
    musicClockDeadline += durationMs * MUSIC_CLOCK_TICKS_PER_MS;
}

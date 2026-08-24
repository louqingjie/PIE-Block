#include "main.h"

static volatile uint16_t timer0_divider;

void Timer0_Isr(void) __interrupt (TMR0_VECTOR)
{
    /* 清除中断标志，验证 SDCC 的定时器中断入口和返回。 */
    PIT_Timer_Clear(TIM0);

    /* 每次 1 ms 中断翻转一次，P34 应为约 500 Hz 方波。 */
    P34 = !P34;

    /* 每 500 次中断翻转一次 P35，LED 应以约 0.5 s 间隔闪烁。 */
    if (++timer0_divider >= 500)
    {
        timer0_divider = 0;
        P35 = !P35;
    }
}

void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

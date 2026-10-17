#include "main.h"

/*
 * Timer0：8.0005kHz 采样中断。合成器只在这里被推进，主循环不碰 PWM，
 * 因此 HSPWM 异步窗口不会有两个上下文同时访问。
 */
void VoiceTimer0Isr(void) __interrupt (TMR0_VECTOR)
{
    PIT_Timer_Clear(TIM0);
    VoiceTimerTick();
}

/* 音乐测试不使用的中断入口，保留默认实现覆盖向量。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

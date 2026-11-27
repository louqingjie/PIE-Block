/*
 * 中断服务：UART1（扩展板）、UART2（调试台）、Timer3（1 ms 计时）。
 *
 * 未使能的外设不定义 ISR；SDCC 向量声明由 build.ps1 预包含头自动生成。
 */
#include "main.h"

/* UART1：扩展板 230400，发送查询期间会临时关闭 ES；这里只清标志。 */
void UART1_Isr(void) __interrupt (4)
{
    if (SCON & 0x02)
    {
        SCON &= (uint8_t)~0x02;
    }
    if (SCON & 0x01)
    {
        SCON &= (uint8_t)~0x01;
        (void)SBUF;
    }
}

/* UART2：调试台收发环形缓冲。 */
void UART2_Isr(void) __interrupt (8)
{
    Dbg_UartIsr();
}

/* Timer3：固定 16 位自动重装，1 ms 节拍。 */
void TM3_Isr(void) __interrupt (19)
{
    PIT_Timer_Clear(TIM3);
    Dbg_TickIsr();
}

/* 未使用中断的默认入口（与仓库其他工程一致，布局检查需要该符号）。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

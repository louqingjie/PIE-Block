/*
 * 独立调试串口：UART3 P0.0/P0.1，115200 8N1，轮询发送。
 *
 * 这样 USB(P3.0/P3.1) 和机器人桥 UART2(P1.0/P1.1) 都不受影响。
 * 只实现 TX；RX 脚保留高阻/准双向，不开启串口中断。
 */

#include "main.h"
#include "debug_uart.h"

void DebugUartInit(void)
{
    /* UART3 默认引脚：P0.0 = RX，P0.1 = TX。 */
    P_SW2 &= ~(0x01 << 1);

    P0M1 &= ~0x03;
    P0M0 &= ~0x01;
    P0M0 |= 0x02;   /* P0.1 TX 推挽输出；P0.0 保持准双向输入。 */

    S3CON = 0x50;
    T3L = (BYTE)BR(CDC_DEBUG_BAUD);
    T3H = (BYTE)(BR(CDC_DEBUG_BAUD) >> 8);
    T4T3M |= 0x0a;  /* T3x12 = 1, T3R = 1；AUXR/T4T3M 不是可位寻址 SFR。 */
    S3CON &= ~0x02; /* 清 S3TI */
}

void DebugUartPutChar(BYTE c)
{
    S3CON &= ~0x02;
    S3BUF = c;
    while (!(S3CON & 0x02))
    {
    }
    S3CON &= ~0x02;
}

void DebugUartPuts(const char *s)
{
    while (*s)
        DebugUartPutChar((BYTE)*s++);
}

/* 让 SDCC 的 printf() 输出到调试串口。 */
int putchar(int c)
{
    DebugUartPutChar((BYTE)c);
    return c;
}

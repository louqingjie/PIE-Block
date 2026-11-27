#include "main.h"

/*
 * USB 与 UART2 的中断入口分别放在 src/usb.c 和 src/uart_cdc.c。
 * build.ps1 会扫描所有源码里的 __interrupt 定义，并在 main.c 里
 * 生成声明，确保 MCS-251 向量表包含这些入口。
 *
 * check_layout.py 要求 MAP 中存在 _Default_Isr；这里保留一个未使用
 * 向量上的空处理函数，和 UART1_IRQ_SMOKE 的做法一致。
 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

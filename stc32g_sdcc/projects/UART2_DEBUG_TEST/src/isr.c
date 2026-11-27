/*
 * UART2 调试链路临时测试工程不使用中断，全部查询发送/接收。
 * 保留本文件是为了满足 build.ps1 对每个工程 isr.c/main.c 的统一约定。
 */

#include "main.h"

void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

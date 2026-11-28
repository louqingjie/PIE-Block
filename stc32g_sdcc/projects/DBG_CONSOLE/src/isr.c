/*
 * 中断服务：UART1（扩展板）、UART2（调试台）、Timer3（1 ms 计时）。
 *
 * 未使能的外设不定义 ISR；SDCC 向量声明由 build.ps1 预包含头自动生成。
 *
 * 重要：SDCC mcs251 的 __interrupt 序言只保存 DPL/DPH，不保存 DPXL
 * （MCS-251 的 24 位指针高字节，SFR 0x84）。而主循环热路径会大量使用
 * 24 位取址：
 *   - switch 跳表（如 CNU_PIE_GPIO.c 的 GPIO_Write_Bit，nRF CE/CSN 每次都调）
 *     会 movc 读目标地址 → mov dpxl,a → ejmp @dr28；
 *   - __code 字符串/常量读取同样走 DPXL。
 * 若中断正好打断这段取址，ISR 里对 XDATA 的访问会把 DPXL 改掉，返回后
 * 取到错误页地址 → ejmp 跳到非程序区 → RSTFLAG.ROMOVF 复位。
 * 真机现象：初始化提示音反复响、串口反复出现
 *   ev=RESET rst=ROV raw=0x06 flags=ROV+SW
 * 且日志里偶发坏字符（moe=RX、build 的 bui 丢失等）。
 *
 * 因此每个会执行 C 代码的 ISR 都必须在主体外手工保存/恢复 DPXL。
 * 对应的契约测试见 tests/test_dbg_console_contract.py 的 ISR 用例。
 */
#include "main.h"

/* UART1：扩展板 230400，发送查询期间会临时关闭 ES；这里只清标志。 */
void UART1_Isr(void) __interrupt (4)
{
    __asm
        push dpxl
    __endasm;

    if (SCON & 0x02)
    {
        SCON &= (uint8_t)~0x02;
    }
    if (SCON & 0x01)
    {
        SCON &= (uint8_t)~0x01;
        (void)SBUF;
    }

    __asm
        pop dpxl
    __endasm;
}

/* UART2：调试台收发环形缓冲。 */
void UART2_Isr(void) __interrupt (8)
{
    __asm
        push dpxl
    __endasm;

    Dbg_UartIsr();

    __asm
        pop dpxl
    __endasm;
}

/* Timer3：固定 16 位自动重装，1 ms 节拍。 */
void TM3_Isr(void) __interrupt (19)
{
    __asm
        push dpxl
    __endasm;

    PIT_Timer_Clear(TIM3);
    Dbg_TickIsr();

    __asm
        pop dpxl
    __endasm;
}

/* 未使用中断的默认入口（与仓库其他工程一致，布局检查需要该符号）。 */
void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

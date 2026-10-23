/*
 * 时钟自检固件（Keil C251 版，用于 PIE-Block 排障）
 *
 * 目的：在一块主频不听话的 STC32G 主控板上，一次性读出/验证：
 *   1. 上电后（不设任何时钟）的真实主频：固件只用一次 UART_Init，
 *      波特率按编译期 FOSC=33.1776MHz 算成 230400，所以线上实际波特率
 *      = 230400 × 实际主频 / 33.1776MHz；
 *   2. 芯片出厂校准表 CHIPID15(33.1776MHz 的 IRTRIM) / CHIPID23(27M 频段 VRTRIM)；
 *   3. 软件写 IRTRIM / VRTRIM / IRCBAND 能否真的把主频切到各档。
 *
 * 串口：UART1，P31=TX、P30=RX，8N1。
 *
 * 输出协议（纯 ASCII、无中文、无字符串字面量）：
 *   上电后先重复约 120 次：
 *       \r\n O  A:xx V:xx B:xx D:xx T:xx R:xx \r\n
 *   其中 O=上电原始状态；A=IRTRIM V=VRTRIM B=IRCBAND D=CLKDIV
 *        T=CHIPID15(33.1776 校准值)  R=CHIPID23(27M 频段 VRTRIM 校准值)
 *   然后打印一行 START，进入循环：依次切 7 档，每档先打印
 *       \r\n <档号>  A:xx V:xx B:xx D:xx T:xx R:xx \r\n
 *   再连发 240 个档号字符（'0'~'6'）。
 *   档位含义：0=22.1184MHz 1=24MHz 2=27MHz 3=30MHz 4=33.1776MHz(手册写法)
 *             5=35MHz 6=33.1776MHz(完全照抄应用固件 System_Clock_Set 的写法)
 *
 * 判读方法：某档位实际跑在多少主频，就用 230400×主频/33.1776MHz 去解它打印的
 * 档号字符；例如芯片锁死在 22.65MHz 时，所有档位都只能在 157300 附近解出。
 */
#include "main.h"

/* nrf24l01.c 引用的全局通道号；本自检固件不用无线，给缺省值即可。 */
uint8_t Channal = 36;

#define PROBE_BAUD 230400UL

static void PutChar(uint8_t c)
{
    uint8_t es;

    es = ES;
    ES = 0;
    TI = 0;
    SBUF = c;
    while (!TI) ;
    TI = 0;
    ES = es;
}

static void PutHex8(uint8_t v)
{
    uint8_t hi;
    uint8_t lo;

    hi = (uint8_t)(v >> 4);
    lo = (uint8_t)(v & 0x0F);
    PutChar((uint8_t)((hi < 10) ? ('0' + hi) : ('A' + hi - 10)));
    PutChar((uint8_t)((lo < 10) ? ('0' + lo) : ('A' + lo - 10)));
}

/* 打印一行：<tag> A:xx V:xx B:xx D:xx T:xx R:xx */
static void Report(uint8_t tag)
{
    PutChar('\r');
    PutChar('\n');
    PutChar(tag);
    PutChar(' ');
    PutChar('A'); PutChar(':'); PutHex8(IRTRIM);   PutChar(' ');
    PutChar('V'); PutChar(':'); PutHex8(VRTRIM);   PutChar(' ');
    PutChar('B'); PutChar(':'); PutHex8(IRCBAND);  PutChar(' ');
    PutChar('D'); PutChar(':'); PutHex8(CLKDIV);   PutChar(' ');
    PutChar('T'); PutChar(':'); PutHex8(CHIPID15); PutChar(' ');
    PutChar('R'); PutChar(':'); PutHex8(CHIPID23);
    PutChar('\r');
    PutChar('\n');
}

static void Idle(uint16_t n)
{
    volatile uint16_t i;

    for (i = 0; i < n; i++)
        ;
}

/* 与 STC32G 手册 10.4.1 官方写法一致地切换 IRC 档位 */
static void SetClock(uint8_t idx)
{
    P_SW2 |= 0x80;
    switch (idx)
    {
    case 0:
        CLKDIV = 0x04; IRTRIM = T22M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND &= 0xFC; IRCBAND |= 0x02; CLKDIV = 0x00; break;
    case 1:
        CLKDIV = 0x04; IRTRIM = T24M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND &= 0xFC; IRCBAND |= 0x02; CLKDIV = 0x00; break;
    case 2:
        CLKDIV = 0x04; IRTRIM = T27M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND &= 0xFC; IRCBAND |= 0x02; CLKDIV = 0x00; break;
    case 3:
        CLKDIV = 0x04; IRTRIM = T30M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND &= 0xFC; IRCBAND |= 0x02; CLKDIV = 0x00; break;
    case 4:
        CLKDIV = 0x04; IRTRIM = T33M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND &= 0xFC; IRCBAND |= 0x02; CLKDIV = 0x00; break;
    case 5:
        CLKDIV = 0x04; IRTRIM = T35M_ADDR; VRTRIM = VRT44M_ADDR;
        IRCBAND |= 0x03; CLKDIV = 0x00; break;
    default:
        /* 6 号档：完全照抄应用固件 System_Clock_Set()（IRCBAND 整字节写 0x02） */
        CLKDIV = 0x04; IRTRIM = T33M_ADDR; VRTRIM = VRT27M_ADDR;
        IRCBAND = 0x02; CLKDIV = 0x00; break;
    }
}

void main(void)
{
    uint16_t i;
    uint8_t idx;

    /* 与应用固件完全一致地初始化：Board_Init() 会调用 System_Clock_Set()，
       按芯片 CHIPID 校准值把主频设成 33.1776MHz，并清 WTST/CKCON、配置 IO。 */
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, PROBE_BAUD, TIM1);

    /* 打印“应用初始化之后”的状态（应已尝试设成 33.1776MHz） */
    Report('I');
    Report('I');
    Idle(20000);

    /* 阶段 2：开始逐档切换主频 */
    PutChar('\r'); PutChar('\n');
    PutChar('S'); PutChar('T'); PutChar('A'); PutChar('R'); PutChar('T');
    PutChar('\r'); PutChar('\n');
    Idle(20000);

    while (1)
    {
        for (idx = 0; idx < 7; idx++)
        {
            SetClock(idx);
            Report((uint8_t)('0' + idx));
            for (i = 0; i < 240; i++)
                PutChar((uint8_t)('0' + idx));
            Idle(30000);
        }
    }
}

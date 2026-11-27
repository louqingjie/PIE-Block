/*
 * 车体串口调试台：UART2 非阻塞输出 + 1 ms 计时 + 快照/事件/命令。
 *
 * 接线：P1.1 -> USB-TTL RX，P1.0 <- USB-TTL TX，GND 共地。
 * 电平：3.3V TTL；默认 115200 8N1。
 */
#ifndef __DBG_CONSOLE_H
#define __DBG_CONSOLE_H

#include <stdint.h>

#include "STC32Gxx.h"
#include "common.h"

/* 可用编译宏 -DDBG_BAUD=921600 覆盖；主机端必须同步修改波特率。 */
#ifndef DBG_BAUD
#define DBG_BAUD 115200UL
#endif

/* UART2 波特率重装值：22.1184 MHz / 115200 => 48。 */
#define DBG_BR(n) (65536UL - ((FOSC) / (n) + 2UL) / 4UL)

#define DBG_TX_RING_SIZE 1024
#define DBG_RX_RING_SIZE 64
#define DBG_LINE_SIZE 320
#define DBG_DEFAULT_HZ 5
#define DBG_LINK_TIMEOUT_MS 500UL

/*
 * 初始化顺序：必须在 Board_Init() 之后、UART1/PWM/nRF 初始化之前调用。
 * fw/build 由 main.c 从构建脚本生成的宏传入（IDE 手工编译时为 local/__DATE__）。
 */
void Dbg_Init(const char __code *fw, const char __code *build);

void Dbg_UartIsr(void); /* UART2 收发中断，由 isr.c 调用 */
void Dbg_TickIsr(void); /* TIM3 1 ms 中断，由 isr.c 调用 */

uint32_t Dbg_Millis(void);
uint32_t Dbg_AgeMs(void);

/* 收到一个有效控制包时由 nrf_dbg.c 调用。 */
void Dbg_NoteRx(void);

/* 主循环每轮末尾调用：更新 loop/exp_ms、事件与周期快照。 */
void Dbg_EndLoop(uint16_t loop_ms, uint16_t exp_ms);

/* nrf_handler 之后调用：消费 FIFO_FULL 事件。 */
void Dbg_AfterNrfHandler(void);

/* 主循环开头调用：处理串口命令。 */
void Dbg_PollCommands(void);

#endif /* __DBG_CONSOLE_H */

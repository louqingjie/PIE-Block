/*
 * 车体串口调试台：UART2 非阻塞输出 + 1 ms 计时 + 快照/事件/命令。
 *
 * 接线：P1.1 -> USB-TTL RX，P1.0 <- USB-TTL TX，GND 共地。
 * 电平：3.3V TTL；默认 115200 8N1。
 *
 * v2 诊断版：启动横幅之后会打印两类启动自检行：
 *   ev=RESET rst=.. boot=.. raw=0x.. flags=.. pcon=0x.. wdt=0x.. rstcfg=0x..
 *   # NRF init=.. config=.. ...
 *   # init done t=..
 * 复位循环（“初始化提示音反复响”）会在串口上表现为反复出现这三行。
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
#define DBG_BR(DBG_BAUD) (65536UL - ((FOSC) / (DBG_BAUD) + 2UL) / 4UL)

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

/* nrf_handler 之后调用：消费 FIFO_FULL / TX_STUCK 事件。 */
void Dbg_AfterNrfHandler(void);

/* 主循环开头调用：处理串口命令。 */
void Dbg_PollCommands(void);

/* Nrf_Init() 之后调用：打印 nRF 初始化结果与关键寄存器回读。 */
void Dbg_BootNrfReport(void);

/* All_Init() 末尾调用：打印初始化完成时刻（用于看两次启动之间的间隔）。 */
void Dbg_InitDone(void);

/* `e` 命令：重复打印本次启动的复位信息。 */
void Dbg_PrintResetInfo(void);

/*
 * 跑飞面包屑：主循环各阶段调用（stage 见 main.c/nrf_dbg.c 注释编号）。
 * 复位后启动行会打印上一次复位前的最后 stage/t/spmax，用于定位 ROMOVF。
 */
void Dbg_Mark(uint8_t stage);

#endif /* __DBG_CONSOLE_H */

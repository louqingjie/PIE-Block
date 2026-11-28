/*
 * PIE-Block 车体串口调试台（独立校内赛工程）
 *
 * 本工程是手写的独立副本，不参与 PIE-Block 代码生成器流程：
 *   - 控制基线：麦轮工程.pieproj（工程机器人、频道 29、P74..P77 麦轮）
 *   - 调试串口：UART2，P1.1 = TX，P1.0 = RX，115200 8N1，3.3V TTL，需共地
 *
 * 目标：在不改变控制/遥测时序的前提下输出 nRF24L01+ RX FIFO 与主循环统计。
 *
 * 诊断版（v2，2026-11-28）：
 *   - 复位原因按手册 9.1.4 正确解码（LVD/WDG/SW/ROMOVF/PIN），并打印原始 RSTFLAG；
 *   - 用不参与启动清零的绝对 XDATA 记录复位之间的启动序号（不再依赖 EEPROM）；
 *   - nRF 初始化回读自检 + TX 有界等待后强制回 RX（避免停在 TX 收不到控制包）；
 *   - 调试台命令增加 e（复位信息）/ z（静音蜂鸣器）/ p（试音）/ w（看门狗）。
 */
#ifndef __MAIN_H
#define __MAIN_H

#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include "STC32Gxx.h"
#include "common.h"

#include "CNU_PIE_GPIO.h"
#include "CNU_PIE_TIMER.h"
#include "CNU_PIE_UART.h"
#include "CNU_PIE_SPI.h"
#include "CNU_PIE_PWM.h"

#include "dbg_console.h"
#include "nrf_dbg.h"

/*
 * 蜂鸣器：P3.3，与生成代码一致用 PWMA CH4N 驱动。
 * 不能用 PWMB：PWMB 的周期寄存器被拓展板舵机（P60/P62/P64/P66、P74..P77）
 * 共用，改蜂鸣器频率会连带改舵机周期。
 */
#define BUZZER_CH PWMA_CH4N_P33

/* 调试命令用（实现见 main.c）。 */
void Buzzer_Silence(void);
void Buzzer_Beep(uint16_t freq, uint16_t ms);

#endif /* __MAIN_H */

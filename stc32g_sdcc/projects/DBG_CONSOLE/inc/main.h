/*
 * PIE-Block 车体串口调试台（独立校内赛工程）
 *
 * 本工程是手写的独立副本，不参与 PIE-Block 代码生成器流程：
 *   - 控制基线：麦轮工程.pieproj（工程机器人、频道 29、P74..P77 麦轮）
 *   - 调试串口：UART2，P1.1 = TX，P1.0 = RX，115200 8N1，3.3V TTL，需共地
 *
 * 目标：在不改变控制/遥测时序的前提下输出 nRF24L01+ RX FIFO 与主循环统计。
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

#endif /* __MAIN_H */

/*
 * FreeRTOS Kernel V10.4.6
 * Copyright (C) 2021 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
 *
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy of
 * this software and associated documentation files (the "Software"), to deal in
 * the Software without restriction, including without limitation the rights to
 * use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
 * the Software, and to permit persons to whom the Software is furnished to do so,
 * subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
 * FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
 * COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
 * IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 *
 * https://www.FreeRTOS.org
 * https://github.com/FreeRTOS
 *
 */

/*
 * SDCC MCS-251 (STC32G12K128) 端口宏定义。
 *
 * 与 Keil C251 端口的关键差异：
 *   - SDCC 使用 ABI revision 2：3 字节平坦指针、ECALL/ERET 直接调用、
 *     __interrupt() 函数由编译器生成中断向量表入口；
 *   - 上下文切换完全交给编译器序言/尾声（调用其它函数的 ISR 会保存完整
 *     寄存器组），端口只负责切换硬件栈指针 SPX；
 *   - 存储类关键字是 __data/__code，不再使用 Keil 的 data/code。
 */

#ifndef PORTMACRO_H
#define PORTMACRO_H

#include "STC32Gxx.h"
#include "intrins.h"


/*-----------------------------------------------------------
 * 类型定义。
 *-----------------------------------------------------------*/
#define portCHAR		char
#define portFLOAT		float
#define portDOUBLE		float
#define portLONG		long
#define portSHORT		short
#define portSTACK_TYPE	uint8_t
#define portBASE_TYPE	char

typedef portSTACK_TYPE StackType_t;
typedef signed char BaseType_t;
typedef unsigned char UBaseType_t;


#if( configUSE_16_BIT_TICKS == 1 )
	typedef uint16_t TickType_t;
	#define portMAX_DELAY ( TickType_t ) 0xffff
#else
	typedef uint32_t TickType_t;
	#define portMAX_DELAY ( TickType_t ) 0xffffffffUL
#endif

/*-----------------------------------------------------------
 * 硬件相关。
 *-----------------------------------------------------------*/
#define portSTACK_GROWTH			( 1 )
#define portTICK_PERIOD_MS			( ( uint32_t ) 1000 / configTICK_RATE_HZ )
#define portBYTE_ALIGNMENT			2

/*-----------------------------------------------------------
 * 任务工具。
 *
 * portYIELD() 不直接切换上下文，而是把 TF0 置位软件触发 Timer0 中断，
 * 由 vTickISR() 统一完成切换，从而保证所有任务帧形状一致。
 *-----------------------------------------------------------*/
extern void vPortYield( void );
#define portYIELD()	                vPortYield()
#define portNOP()	                _nop_()

/*-----------------------------------------------------------
 * 临界区管理。
 *
 * 与 STC 官方 Keil 端口保持一致：直接开关总中断，不维护嵌套计数。
 *-----------------------------------------------------------*/
#define portENTER_CRITICAL()		EA = 0
#define portEXIT_CRITICAL()			EA = 1

#define portDISABLE_INTERRUPTS()	EA = 0
#define portENABLE_INTERRUPTS()		EA = 1

/* 在其它中断里请求一次任务切换：置位 TF0，等本中断返回后由 vTickISR() 处理。 */
#define portYIELD_FROM_ISR( x )		do { ( void ) ( x ); vPortYield(); } while( 0 )

/*-----------------------------------------------------------
 * 任务函数宏。
 *-----------------------------------------------------------*/
#define portTASK_FUNCTION_PROTO( vTaskFunction, pvParameters ) void vTaskFunction( void *pvParameters )
#define portTASK_FUNCTION( vTaskFunction, pvParameters ) void vTaskFunction( void *pvParameters )


#endif /* PORTMACRO_H */

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
 * STC32G12K128 + SDCC MCS-251 端口实现。
 *
 * 上下文切换的完整寄存器保存/恢复由 SDCC 为 vTickISR() 生成的序言/尾声
 * 负责（调用其它函数的 ISR 会压入 bits/acc/b/dpl/dph/r15..r8/r7..r0/psw），
 * 端口只做三件事：
 *   1. 把当前 SPX 写进 pxCurrentTCB->pxTopOfStack；
 *   2. 调用调度器；
 *   3. 从（可能已换过的）pxCurrentTCB->pxTopOfStack 恢复 SPX。
 *
 * 首个任务由 xPortStartScheduler() 按同样的帧布局手工构造并入栈后 eret
 * 进入，帧格式见 portasm.h。
 */

/* Standard includes. */
#include <stdlib.h>

/* Scheduler includes. */
#include "FreeRTOS.h"
#include "task.h"
#include "portasm.h"

/* 定时器重装值：1T 模式下每个 tick 的计数。 */
#define portRELOAD_VALUE                    ( 65536UL - ( configCPU_CLOCK_HZ / configTICK_RATE_HZ ) )

/* SPX 保存/恢复暂存字节；声明在 portasm.h，必须位于可直接寻址的 DSEG 内。 */
__data unsigned char prvSPXLo;
__data unsigned char prvSPXHi;

/* portYIELD() 软件触发 Timer0 中断时置位，vTickISR() 据此跳过 tick 递增。 */
__data volatile unsigned char xYieldPending;

/* Setup the timer to generate the tick interrupts. */
static void prvPortSetupTimerInterrupt( void );


/*-----------------------------------------------------------*/

/*
 * 构造任务首次运行的栈帧。顺序必须与 SDCC 为 vTickISR() 生成的序言完全一致，
 * 否则 xPortStartScheduler() 的 pop 序列会取到错误的数据。
 */
StackType_t *pxPortInitialiseStack( StackType_t *pxTopOfStack, TaskFunction_t pxCode, void *pvParameters )
{
    uint32_t ulAddress;
    uint32_t ulParameter;
    uint8_t index;

    ulAddress = ( uint32_t ) pxCode;
    ulParameter = ( uint32_t ) pvParameters;

    /* eret 返回地址：PC[23:16]、PC[15:8]、PC[7:0]。 */
    *pxTopOfStack = ( StackType_t ) ( ulAddress >> 16 );
    pxTopOfStack++;
    *pxTopOfStack = ( StackType_t ) ( ulAddress >> 8 );
    pxTopOfStack++;
    *pxTopOfStack = ( StackType_t ) ( ulAddress );
    pxTopOfStack++;

    /* 编译器序言 push 顺序：bits, acc, b, dpl, dph。 */
    *pxTopOfStack = 0;
    pxTopOfStack++;
    *pxTopOfStack = 0;
    pxTopOfStack++;
    *pxTopOfStack = ( StackType_t ) ( ulParameter >> 16 );
    pxTopOfStack++;
    *pxTopOfStack = ( StackType_t ) ( ulParameter );
    pxTopOfStack++;
    *pxTopOfStack = ( StackType_t ) ( ulParameter >> 8 );
    pxTopOfStack++;

    /* r15, r14, r13, r12, r9, r8, r7, r6, r5, r4, r3, r2, r1, r0。 */
    for( index = 0; index < 14; index++ )
    {
        *pxTopOfStack = 0;
        pxTopOfStack++;
    }

    /* psw。 */
    *pxTopOfStack = 0;
    pxTopOfStack++;

    return pxTopOfStack;
}
/*-----------------------------------------------------------*/

BaseType_t xPortStartScheduler( void )
{
    /* Start the timer that generates the tick ISR. */
    prvPortSetupTimerInterrupt();

    /* 切到第一个任务的栈，弹出序言保存的寄存器，最后 eret 进入任务。 */
    portRESTORE_SPX();
    portRESTORE_CONTEXT();
    portRETURN_TASK();

    /* Should never get here! */
    return pdTRUE;
}
/*-----------------------------------------------------------*/

void vPortEndScheduler( void )
{
    /* Not implemented for this port. */
}
/*-----------------------------------------------------------*/

/*
 * 请求一次任务切换：置位标志并通过 TF0 软件触发 Timer0 中断。
 * 若此刻总中断被关闭，挂起的 TF0 会在开中断后生效。
 */
void vPortYield( void )
{
    xYieldPending = 1;
    TF0 = 1;
}
/*-----------------------------------------------------------*/

/*
 * Timer0 中断（向量 1）：既是系统节拍，也是唯一的任务切换点。
 *
 * 序言已经把完整寄存器组压栈，这里只需切换 SPX；尾声弹出新任务的寄存器并
 * RETI 返回。构造首个任务帧时使用的正是同一套 push/pop 顺序。
 */
void vTickISR( void ) __interrupt ( 1 )
{
    portSAVE_SPX();

    if( xYieldPending != 0 )
    {
        xYieldPending = 0;
        vTaskSwitchContext();
    }
    else if( xTaskIncrementTick() != pdFALSE )
    {
        vTaskSwitchContext();
    }

    portRESTORE_SPX();
}
/*-----------------------------------------------------------*/

/* Setup the Timer0 to generate the tick interrupts at the required frequency. */
static void prvPortSetupTimerInterrupt( void )
{
    /* Timer0 work at 1T mode. */
    AUXR |= 0x80;

    /* Timer0 work at mode0 (16-bit auto reload mode). */
    TMOD &= ( uint8_t ) ~0x0f;

    /* Initial timer0 reload value. */
    TL0 = ( uint8_t ) ( portRELOAD_VALUE );
    TH0 = ( uint8_t ) ( portRELOAD_VALUE >> 8 );

    /* Interrupts are disabled when this is called so the timer can be started here. */
    TR0 = 1;

    /* Enable timer0 interrupts. */
    ET0 = 1;
}

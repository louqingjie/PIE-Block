/*
 * FreeRTOS V202112.00
 * Copyright (C) 2020 Amazon.com, Inc. or its affiliates.  All Rights Reserved.
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
 * http://www.FreeRTOS.org
 * http://aws.amazon.com/freertos
 *
 * 1 tab == 4 spaces!
 */

#ifndef FREERTOS_CONFIG_H
#define FREERTOS_CONFIG_H

#include "STC32Gxx.h"

/*-----------------------------------------------------------
 * 版本更新历史
 *
 * SDCC 移植版（相对 STC 官方 Keil 版 V1.0.2）
 *     1. 目标编译器改为 SDCC MCS-251（ABI revision 2）；
 *     2. 去掉 Keil 专有的 #pragma ROM / #pragma WARNING 与 stc32g.h；
 *     3. 关闭本演示未使用的可选特性，使 LARGE（64 KB 代码窗口）放得下：
 *        configUSE_TASK_NOTIFICATIONS / configUSE_MUTEXES /
 *        configUSE_COUNTING_SEMAPHORES / configUSE_TIMERS 均为 0，
 *        configMAX_PRIORITIES 降为 8（演示最高只用到 3）。
 *        如需启用这些特性，请另做 128 KB HUGE 代码布局；
 *     4. FreeRTOS 堆由 portheap.asm 的 FRHEAP 区域提供（见 README）。
 *----------------------------------------------------------*/


/***************************************************************************************************************/
/*                                        STC32-251 基础配置                                                    */
/***************************************************************************************************************/
#define configPORT_VERSION_NUMBER               "V1.0.2-sdcc"            //移植代码版本
#define MAIN_Fosc                               ( 24000000UL )           //系统工作频率

/* FreeRTOS 内核用 UNUSED() 抑制未使用告警。 */
#define UNUSED( x )                             ( void ) ( x )

/***************************************************************************************************************/
/*                                        FreeRTOS 基础配置                                                     */
/***************************************************************************************************************/

#define configUSE_PREEMPTION                    1                       //1使用抢占式内核，0使用协程
#define configUSE_TIME_SLICING                  1                       //1使能时间片调度
#define configUSE_PORT_OPTIMISED_TASK_SELECTION	0                       //MCS-251 无前导零指令，必须为 0
#define configUSE_TICKLESS_IDLE                 0                       //1启用低功耗tickless模式
#define configUSE_QUEUE_SETS                    0                       //为1时启用队列
#define configCPU_CLOCK_HZ                      ( MAIN_Fosc )           //CPU频率
#define configTICK_RATE_HZ                      ( ( TickType_t ) 1000 ) //时钟节拍频率，1ms
#define configMAX_PRIORITIES                    ( 8 )                   //可使用的最大优先级
#define configDEFAULT_PRIORITIES                ( tskIDLE_PRIORITY + 1 )//任务默认优先级
#define configMINIMAL_STACK_SIZE                ( ( unsigned short ) 256 ) //空闲任务堆栈大小
#define configDEFAULT_STACK_SIZE                ( ( unsigned short ) 256 ) //任务默认堆栈大小
#define configMAX_TASK_NAME_LEN                 ( 8 )                   //任务名字字符串长度
#define configUSE_IDLE_HOOK						0                       //1使用空闲钩子
#define configUSE_TICK_HOOK						0                       //1使用时间片钩子
#define configSUPPORT_DYNAMIC_ALLOCATION        1                       //支持动态内存申请
#define configAPPLICATION_ALLOCATED_HEAP        1                       //堆存储由 portheap.asm 提供
#define configTOTAL_HEAP_SIZE					( ( size_t ) 3072 )     //FRHEAP 区域大小，必须与 portheap.asm 一致

#define configUSE_16_BIT_TICKS                  0                       //0表示32位节拍计数
#define configIDLE_SHOULD_YIELD                 1                       //空闲任务让出 CPU 给同优先级任务
#define configUSE_TASK_NOTIFICATIONS            0                       //本演示未使用任务通知
#define configUSE_MUTEXES                       0                       //本演示未使用互斥信号量
#define configQUEUE_REGISTRY_SIZE               0                       //不启用队列记录
#define configCHECK_FOR_STACK_OVERFLOW          0                       //不启用堆栈溢出检测
#define configUSE_RECURSIVE_MUTEXES             0                       //不使用递归互斥信号量
#define configUSE_MALLOC_FAILED_HOOK            0                       //不使用内存申请失败钩子
#define configUSE_APPLICATION_TASK_TAG          0
#define configUSE_COUNTING_SEMAPHORES           0                       //不使用计数信号量

#define configGENERATE_RUN_TIME_STATS	        0                       //不启用运行时间统计
#define configUSE_TRACE_FACILITY				0                       //不启用可视化跟踪调试
#define configUSE_STATS_FORMATTING_FUNCTIONS	0

/* Co-routine definitions. */
#define configUSE_CO_ROUTINES 			        0                       //不使用协程
#define configMAX_CO_ROUTINE_PRIORITIES         ( 2 )                   //协程的有效优先级数目

/* Software timer definitions. */
#define configUSE_TIMERS                        0                       //本演示未使用软件定时器

/* Set the following definitions to 1 to include the API function, or zero
to exclude the API function. */

#define INCLUDE_xTaskGetSchedulerState          0
#define INCLUDE_vTaskPrioritySet                1
#define INCLUDE_uxTaskPriorityGet               1
#define INCLUDE_vTaskDelete                     1
#define INCLUDE_vTaskCleanUpResources           0
#define INCLUDE_vTaskSuspend                    1
#define INCLUDE_vTaskDelayUntil                 1
#define INCLUDE_vTaskDelay                      1
#define INCLUDE_eTaskGetState                   0
#define INCLUDE_xTimerPendFunctionCall          0


#endif /* FREERTOS_CONFIG_H */

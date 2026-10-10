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
 * SDCC MCS-251 上下文切换宏。
 *
 * 编译器序言/尾声负责保存与恢复寄存器，端口只保存/恢复硬件栈指针 SPX
 * （DR60，低 16 位即 SFR SPH:SP）。任务 TCB 的首成员 pxTopOfStack 是
 * 3 字节大端平坦指针，任务栈位于 00: 区，因此高字节恒为 0。
 *
 * 首次启动帧（pxPortInitialiseStack() 构造，low -> high，共 23 字节）：
 *
 *   偏移  内容                              说明
 *   0..2  PC[23:16], PC[15:8], PC[7:0]     eret 返回地址（高字节在前）
 *   3     bits                             位寄存器组
 *   4     acc
 *   5     b                                pvParameters[23:16]
 *   6     dpl                              pvParameters[7:0]
 *   7     dph                              pvParameters[15:8]
 *   8..13 r15, r14, r13, r12, r9, r8
 *   14..21 r7, r6, r5, r4, r3, r2, r1, r0
 *   22    psw
 *
 * 该顺序必须与 SDCC 为 vTickISR() 生成的序言 push 顺序、以及尾声 pop
 * 顺序逐字节一致。tests/test_port_frame.py 会从 sdcc 生成的汇编里核对。
 */

#ifndef PORT_ASM_H
#define PORT_ASM_H

/* 需要 pxCurrentTCB 的地址，但不关心它的具体类型。 */
typedef void TCB_t;
extern volatile TCB_t * pxCurrentTCB;

/* SPX 保存/恢复用的直接寻址暂存字节（定义在 port.c，位于 DSEG）。 */
extern __data unsigned char prvSPXLo;
extern __data unsigned char prvSPXHi;

/*
 * 把当前 SPX 存入 pxCurrentTCB->pxTopOfStack。
 *
 * 必须与编译器生成的 ISR 序言中的栈操作口径一致：保存的是序言压栈完成后
 * 的栈顶，因此保存前后不能改变栈内容。
 */
#define portSAVE_SPX()                                      \
{                                                           \
    __asm                                                   \
        mov _prvSPXLo, sp                                   \
        mov _prvSPXHi, sph                                  \
    __endasm;                                               \
    ( ( unsigned char * ) ( void * ) pxCurrentTCB )[ 0 ] = 0; \
    ( ( unsigned char * ) ( void * ) pxCurrentTCB )[ 1 ] = prvSPXHi; \
    ( ( unsigned char * ) ( void * ) pxCurrentTCB )[ 2 ] = prvSPXLo; \
}

/*
 * 从 pxCurrentTCB->pxTopOfStack 恢复 SPX。
 *
 * 先关总中断，避免写 SP 与 SPH 之间被其它中断打断；随后编译器尾声的
 * RETI 会重新打开总中断。
 */
#define portRESTORE_SPX()                                   \
{                                                           \
    prvSPXHi = ( ( unsigned char * ) ( void * ) pxCurrentTCB )[ 1 ]; \
    prvSPXLo = ( ( unsigned char * ) ( void * ) pxCurrentTCB )[ 2 ]; \
    __asm                                                   \
        clr ea                                              \
        mov sp, _prvSPXLo                                   \
        mov sph, _prvSPXHi                                  \
    __endasm;                                               \
}

/*
 * 首次启动任务时按编译器尾声的顺序弹出 23 字节帧中的寄存器部分，
 * 剩下 3 字节返回地址交给 eret。
 */
#define portRESTORE_CONTEXT()                               \
{                                                           \
    __asm                                                   \
        pop psw                                             \
        pop (0+0)                                           \
        pop (0+1)                                           \
        pop (0+2)                                           \
        pop (0+3)                                           \
        pop (0+4)                                           \
        pop (0+5)                                           \
        pop (0+6)                                           \
        pop (0+7)                                           \
        pop r8                                              \
        pop r9                                              \
        pop r12                                             \
        pop r13                                             \
        pop r14                                             \
        pop r15                                             \
        pop dph                                             \
        pop dpl                                             \
        pop b                                               \
        pop acc                                             \
        pop bits                                            \
    __endasm;                                               \
}

/* 打开总中断并进入任务。 */
#define portRETURN_TASK()                                   \
{                                                           \
    __asm                                                   \
        setb ea                                             \
        eret                                                \
    __endasm;                                               \
}


#endif /* PORT_ASM_H */

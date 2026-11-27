#ifndef UART2_DEBUG_TEST_MAIN_H
#define UART2_DEBUG_TEST_MAIN_H

#include "common.h"
#include "STC32Gxx.h"

/* UART2 用 Timer2 做波特率发生器；和桥固件的 uart_cdc.h 保持一致。 */
#define BR(n) (65536 - ((FOSC) / (n) + 2) / 4)

/* common.c 里定义，但 common.h 没有声明。 */
extern void Register_Set(void);

#endif

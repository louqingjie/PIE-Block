#ifndef UART1_IRQ_SMOKE_MAIN_H
#define UART1_IRQ_SMOKE_MAIN_H

#include "common.h"
#include "STC32Gxx.h"
#include "CNU_PIE_GPIO.h"
#include "CNU_PIE_UART.h"

extern volatile uint8_t uart1_rx_pending;
extern volatile uint8_t uart1_rx_data;
extern volatile uint8_t uart1_tx_busy;

#endif

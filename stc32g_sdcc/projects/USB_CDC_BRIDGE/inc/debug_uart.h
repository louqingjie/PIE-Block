#ifndef USB_CDC_BRIDGE_DEBUG_UART_H
#define USB_CDC_BRIDGE_DEBUG_UART_H

#include "usb_types.h"

/*
 * 独立调试串口：UART3 P0.0(RX)/P0.1(TX)，115200 8N1，只发送。
 * 不占用桥的 UART2 P1.0/P1.1，也不占用 USB 的 P3.0/P3.1。
 */
void DebugUartInit(void);
void DebugUartPutChar(BYTE c);
void DebugUartPuts(const char *s);

#endif

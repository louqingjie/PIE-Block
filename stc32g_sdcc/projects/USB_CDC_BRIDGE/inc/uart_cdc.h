#ifndef __UART_CDC_H__
#define __UART_CDC_H__

#include "usb_types.h"
#include "usb_config.h"

#define BR(n)                   (65536 - ((FOSC) / (n) + 2) / 4)

void uart_init(void);
void uart_set_parity(BYTE parity);
void uart_set_baud(DWORD baud);
void uart_polling(void);

#endif

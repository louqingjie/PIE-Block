#ifndef __UART_H__
#define __UART_H__


void uart_init();
void uart_isr();

extern BOOL bUartRxReady;

extern BYTE edata UartTxBuffer[256];
extern BYTE edata UartRxBuffer[256];

void uart_send(BYTE status, BYTE size);
void uart_recv_done();

#endif

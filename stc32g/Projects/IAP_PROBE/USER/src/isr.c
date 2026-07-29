/*********************************************************************************************************************
 * @file       isr.c
 * @brief      IAP_PROBE 中断服务
 * @note       只保留 UART1 ISR：UART_PutChar 依赖它清 UART_BUSY[1]，否则发送会死锁。
 ********************************************************************************************************************/
#include "isr.h"
#include "common.h"
#include "CNU_PIE_UART.h"

void UART1_Isr() interrupt 4
{
	if (UART1_GET_TX_FLAG)
	{
		UART1_CLEAR_TX_FLAG;
		UART_BUSY[1] = 0;
	}
	if (UART1_GET_RX_FLAG)
	{
		UART1_CLEAR_RX_FLAG;
		uart_receive[0]++;
	}
}

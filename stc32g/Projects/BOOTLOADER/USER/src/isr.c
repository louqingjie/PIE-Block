#include "isr.h"
#include "common.h"
#include "CNU_PIE_UART.h"

/* Bootloader 的 UART1 ISR：清发送忙标志 + 接收字节存入环形缓冲区。
   与 App 不同，bootloader 不监听 @STCISP# / @PIEIAP#，它自己就是下载器。 */
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
        /* 存入环形缓冲区 */
        uart1_rx_buff[uart1_rx_head] = SBUF;
        uart1_rx_head = (uart1_rx_head + 1) % UART1_RX_BUFFER_SIZE;
    }
}

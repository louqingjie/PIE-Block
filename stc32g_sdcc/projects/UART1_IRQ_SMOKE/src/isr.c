#include "main.h"

void UART1_Isr(void) __interrupt (UART1_VECTOR)
{
    P34 = !P34;

    if (RI)
    {
        uart1_rx_data = SBUF;
        RI = 0;
        uart1_rx_pending = 1;
        P35 = !P35;
    }

    if (TI)
    {
        TI = 0;
        uart1_tx_busy = 0;
        P36 = !P36;
    }
}

void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR)
{
}

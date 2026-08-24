#include <stdint.h>

#include "STC32Gxx.h"

static void wait_cycles(uint16_t cycles)
{
    volatile uint16_t i;
    for (i = 0; i < cycles; i++)
        ;
}

static void uart1_send_bounded(uint8_t value)
{
    uint16_t timeout = 2000;
    SBUF = value;
    while (!(SCON & 0x02) && timeout != 0)
        timeout--;
    SCON &= (uint8_t)~0x02;
}

void main(void)
{
    /* UART1 默认 P30/P31；这两个脚不能同时接 STC-USB Link1D 的 SWD。 */
    SCON = 0x50;
    TMOD = (TMOD & 0x0F) | 0x20;
    TH1 = 0xFF;
    TL1 = 0xFF;
    TR1 = 1;
    while (1)
    {
        uart1_send_bounded(0x55);
        wait_cycles(5000);
    }
}

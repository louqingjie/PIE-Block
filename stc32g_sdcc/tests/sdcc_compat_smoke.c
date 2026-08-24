#include <stdint.h>

#include "STC32Gxx.h"
#include "intrins.h"

static volatile uint8_t xdata_probe;

void smoke_isr(void) __interrupt (UART1_VECTOR)
{
    xdata_probe = SBUF;
}

void main(void)
{
    P0 = 0x00;
    P00 = 1;
    CLKSEL = 0x00;
    _nop_();
}

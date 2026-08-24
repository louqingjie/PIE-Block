#include <stdint.h>

#include "STC32Gxx.h"

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
    uint8_t i;
    static const char message[] = "PASS\n";

    SCON = 0x50;
    TMOD = (TMOD & 0x0F) | 0x20;
    TH1 = 0xFF;
    TL1 = 0xFF;
    TR1 = 1;
    for (i = 0; i < sizeof(message) - 1; i++)
        uart1_send_bounded((uint8_t)message[i]);
    while (1)
        ;
}

#include <stdint.h>

#include "STC32Gxx.h"

#define PASS_LED 0x20
#define FAIL_LED 0x40

static uint8_t spi_transfer_bounded(uint8_t value)
{
    uint16_t timeout = 2000;
    SPDAT = value;
    while (!(SPSTAT & 0x80) && timeout != 0)
        timeout--;
    if (timeout == 0)
        return 0;
    SPSTAT = 0xC0;
    return 1;
}

void main(void)
{
    P3M1 &= (uint8_t)~(PASS_LED | FAIL_LED);
    P3M0 |= PASS_LED | FAIL_LED;
    P3 |= PASS_LED | FAIL_LED;
    SPCTL = 0x50; /* 主机、使能、MSB；具体引脚复用由板级连接决定。 */
    if (spi_transfer_bounded(0xA5))
        P3 &= (uint8_t)~PASS_LED;
    else
        P3 &= (uint8_t)~FAIL_LED;
    while (1)
        ;
}

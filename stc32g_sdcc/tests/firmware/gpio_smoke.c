#include <stdint.h>

#include "STC32Gxx.h"

#define LED_MASK 0xE0

static void wait_cycles(uint16_t cycles)
{
    volatile uint16_t i;
    for (i = 0; i < cycles; i++)
        ;
}

void main(void)
{
    /* P35/P36/P37 作为低电平点亮的三颗诊断灯；不触碰 P34 的 NRF CE。 */
    P3M1 &= (uint8_t)~LED_MASK;
    P3M0 |= LED_MASK;
    P3 |= LED_MASK;
    while (1)
    {
        P3 ^= LED_MASK;
        wait_cycles(5000);
    }
}

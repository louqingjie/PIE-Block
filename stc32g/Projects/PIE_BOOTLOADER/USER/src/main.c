#include "stc.h"
#include "uart.h"
#include "iap.h"
#include "dfu.h"

void sys_init();

void main()
{
    dfu_check();

    sys_init();
    uart_init();
    iap_init();

    while (1)
    {
        uart_isr();
        dfu_events();
    }
}

void sys_init()
{
    WTST = 0x00;
    CKCON = 0x00;
    EAXFR = 1;

    /* UART1 从默认的 P30/P31 切到 P43(RXD)/P44(TXD)：
       S1_S1/S1_S0 = 11（P_SW1 |= 0xC0），并把这两个脚配成准双向。
       P4^3 | P4^4 = 0x08 | 0x10 = 0x18。 */
    P_SW1 = (P_SW1 & 0x3f) | 0xc0;
    P4M0 &= ~0x18;
    P4M1 &= ~0x18;
}

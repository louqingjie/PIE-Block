/*
 * USB-CDC 调试桥：USB CDC <-> UART2 (P1.0/P1.1, 115200 8N1)。
 *
 * 本工程只做桥，不初始化 NRF、OLED、拓展板或机器人控制逻辑。
 * 系统时钟由 Register_Set() 设为 22.1184MHz；USB 时钟在 usb_init()
 * 里显式选择 IRC48M。
 */

#include "main.h"

void main(void)
{
    Register_Set();

    usb_init();
    uart_init();

    EA = 1;

    while (1)
    {
        uart_polling();
    }
}

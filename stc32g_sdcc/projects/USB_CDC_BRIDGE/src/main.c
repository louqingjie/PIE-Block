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
    /*
     * 诊断 LED（低电平点亮）：
     *   P3.5 亮 = 应用已启动；
     *   P3.6 亮 = USB 已进入 DEVSTATE_CONFIGURED。
     * 若插拔后 P3.5 不亮而电脑仍看到 HID Writer，说明芯片还在 ROM
     * ISP 监控程序里，优先检查 P3.2 是否被拉低、ISP 软件是否在自动
     * 发送下载命令，以及下载时是否勾选了“P3.2/P3.3=0/0 才下载”。
     */
    P3M0 |= 0x60;
    P3M1 &= ~0x60;
    P35 = 0;
    P36 = 1;

    Register_Set();

    usb_init();
    uart_init();

    EA = 1;

    while (1)
    {
        uart_polling();
        P36 = (DeviceState == DEVSTATE_CONFIGURED) ? 0 : 1;
    }
}

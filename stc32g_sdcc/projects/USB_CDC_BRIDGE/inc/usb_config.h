#ifndef USB_CDC_BRIDGE_USB_CONFIG_H
#define USB_CDC_BRIDGE_USB_CONFIG_H

/* 与 stc32g_sdcc/include/common.h 保持一致。 */
#define FOSC 22118400UL

/* 板间 UART2：固定 115200 8N1，不跟随电脑端 CDC 的 line coding。 */
#define CDC_UART_BAUD 115200UL

/* 独立调试串口 UART3 P0.0/P0.1。 */
#define CDC_DEBUG_BAUD 115200UL

/* 0: UART2 P1.0(RX)/P1.1(TX)；1: UART2 P4.6(RX)/P4.7(TX)。 */
#define CDC_UART_PIN_GROUP 0

#define EN_EP1IN
#define EN_EP2IN
#define EN_EP1OUT

#define EP0_SIZE 64
#define EP1IN_SIZE 64
#define EP2IN_SIZE 64
#define EP1OUT_SIZE 64

/* 官方 CONFIGDESC 为 67 字节，留出余量。 */
#define EP0_STAGE_SIZE 128

/* 首版沿用 STC 70-CDC 例程的 VID/PID，仅用于内部调试。 */
#define CDC_VID_LO 0xBF
#define CDC_VID_HI 0x34
#define CDC_PID_LO 0x02
#define CDC_PID_HI 0xFF

#endif

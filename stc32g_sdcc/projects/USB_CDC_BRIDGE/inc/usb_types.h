#ifndef USB_CDC_BRIDGE_USB_TYPES_H
#define USB_CDC_BRIDGE_USB_TYPES_H

#include <stdint.h>

typedef uint8_t BYTE;
typedef uint16_t WORD;
typedef uint32_t DWORD;

/* 官方例程用 bit BOOL；SDCC 下改成字节，避免位变量 ABI/volatile 问题。 */
typedef uint8_t BOOL;

#endif

#ifndef USB_CDC_BRIDGE_MAIN_H
#define USB_CDC_BRIDGE_MAIN_H

#include <stdint.h>

#include "STC32Gxx.h"
#include "common.h"
#include "usb_config.h"
#include "usb_types.h"

#include "usb.h"
#include "uart_cdc.h"

/* common.c 里定义，但 common.h 没有声明。 */
extern void Register_Set(void);

#endif

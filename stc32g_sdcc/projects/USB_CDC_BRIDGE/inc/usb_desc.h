#ifndef __USB_DESC_H__
#define __USB_DESC_H__

#include "usb_types.h"

extern const __code BYTE DEVICEDESC[18];
extern const __code BYTE CONFIGDESC[67];
extern const __code BYTE LANGIDDESC[4];
extern const __code BYTE MANUFACTDESC[8];
extern const __code BYTE PRODUCTDESC[30];

/* 状态包很小，直接放 XDATA，保证 Ep0State.pData 不会指向 CODE。 */
extern __xdata BYTE PACKET0[2];
extern __xdata BYTE PACKET1[2];

#endif

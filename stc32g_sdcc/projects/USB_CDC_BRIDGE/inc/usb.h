#ifndef __USB_H__
#define __USB_H__

#include "usb_types.h"
#include "usb_regs.h"

#define DESC_DEVICE             0x01
#define DESC_CONFIGURATION      0x02
#define DESC_STRING             0x03

#define IN_DIRECT               0x80                //device to host
#define OUT_DIRECT              0x00                //host to device
#define DIRECT_MASK             0x80

#define STANDARD_REQUEST        0x00
#define CLASS_REQUEST           0x20
#define VENDOR_REQUEST          0x40
#define REQUEST_MASK            0x60

#define DEVICE_RECIPIENT        0x00
#define INTERFACE_RECIPIENT     0x01
#define ENDPOINT_RECIPIENT      0x02
#define RECIPIENT_MASK          0x0f

#define DEVICE_REMOTE_WAKEUP    0x01
#define ENDPOINT_HALT           0x00

#define EP1_IN                  0x81
#define EP1_OUT                 0x01
#define EP2_IN                  0x82
#define EP2_OUT                 0x02
#define EP3_IN                  0x83
#define EP3_OUT                 0x03
#define EP4_IN                  0x84
#define EP4_OUT                 0x04
#define EP5_IN                  0x85
#define EP5_OUT                 0x05

#define DEVSTATE_ATTACHED       0
#define DEVSTATE_POWERED        1
#define DEVSTATE_DEFAULT        2
#define DEVSTATE_ADDRESS        3
#define DEVSTATE_CONFIGURED     4
#define DEVSTATE_SUSPENDED      5

#define EPSTATE_IDLE            0
#define EPSTATE_HALT            1
#define EPSTATE_STATUS          2
#define EPSTATE_DATAIN          3
#define EPSTATE_DATAOUT         4
#define EPSTATE_STALL           5

typedef struct
{
    BYTE    bmRequestType;
    BYTE    bRequest;
    BYTE    wValueL;
    BYTE    wValueH;
    BYTE    wIndexL;
    BYTE    wIndexH;
    WORD    wLength;
}SETUP;

typedef struct
{
    BYTE    bState;
    WORD    wSize;
    BYTE    *pData;
}EPSTATE;

void usb_init(void);
BYTE usb_read_reg(BYTE addr);
void usb_write_reg(BYTE addr, BYTE dat);
BYTE usb_read_fifo(BYTE fifo, BYTE *pdat);
void usb_write_fifo(BYTE fifo, BYTE *pdat, BYTE cnt);

void usb_setup_stall(void);
void usb_setup_in(void);
void usb_setup_out(void);
void usb_setup_status(void);

void usb_ctrl_in(void);
void usb_ctrl_out(void);
void usb_bulk_intr_in(BYTE *pData, BYTE bSize, BYTE ep);
BYTE usb_bulk_intr_out(BYTE *pData, BYTE ep);

void usb_resume(void);
void usb_reset(void);
void usb_suspend(void);
void usb_setup(void);
void usb_in_ep1(void);
void usb_in_ep2(void);
void usb_in_ep3(void);
void usb_in_ep4(void);
void usb_in_ep5(void);
void usb_out_ep1(void);
void usb_out_ep2(void);
void usb_out_ep3(void);
void usb_out_ep4(void);
void usb_out_ep5(void);


extern volatile BYTE DeviceState;
extern volatile __xdata SETUP Setup;
extern volatile BYTE Ie2Shadow;
extern volatile BYTE UsbIrqEnabled;
extern volatile BYTE UsbIrqCount;
extern volatile BYTE UsbResetCount;
extern volatile BYTE UsbSetupCount;
extern volatile BYTE UsbLastIntrusb;
extern volatile BYTE UsbLastIntrin;
extern volatile BYTE UsbLastIntrout;
extern volatile __xdata EPSTATE Ep0State;
extern volatile BYTE InEpState;
extern volatile BYTE OutEpState;

extern volatile BOOL UsbInBusy;
extern volatile BOOL UsbOutBusy;

extern volatile BYTE RxRptr;
extern volatile BYTE RxWptr;
extern volatile BYTE TxRptr;
extern volatile BYTE TxWptr;
extern __xdata BYTE RxBuffer[256];
extern __xdata BYTE TxBuffer[256];

#endif

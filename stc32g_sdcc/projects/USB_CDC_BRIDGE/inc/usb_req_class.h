#ifndef __USB_REQ_CLASS_H__
#define __USB_REQ_CLASS_H__

#include "usb_types.h"

#define SET_LINE_CODING         0x20
#define GET_LINE_CODING         0x21
#define SET_CONTROL_LINE_STATE  0x22

#define NONE_PARITY             0
#define ODD_PARITY              1
#define EVEN_PARITY             2
#define MARK_PARITY             3
#define SPACE_PARITY            4

void usb_req_class(void);
void usb_uart_settings(void);

void usb_set_line_coding(void);
void usb_get_line_coding(void);
void usb_set_ctrl_line_state(void);

typedef struct
{
    DWORD   dwDTERate;
    BYTE    bCharFormat;
    BYTE    bParityType;
    BYTE    bDataBits;
}LINECODING;

extern volatile __xdata LINECODING LineCoding;

#endif

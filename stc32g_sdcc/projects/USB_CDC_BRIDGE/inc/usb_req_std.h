#ifndef __USB_REQ_STD_H__
#define __USB_REQ_STD_H__

#define GET_STATUS              0x00
#define CLEAR_FEATURE           0x01
#define SET_FEATURE             0x03
#define SET_ADDRESS             0x05
#define GET_DESCRIPTOR          0x06
#define SET_DESCRIPTOR          0x07
#define GET_CONFIGURATION       0x08
#define SET_CONFIGURATION       0x09
#define GET_INTERFACE           0x0A
#define SET_INTERFACE           0x0B
#define SYNCH_FRAME             0x0C

void usb_req_std(void);

void usb_get_status(void);
void usb_clear_feature(void);
void usb_set_feature(void);
void usb_set_address(void);
void usb_get_descriptor(void);
void usb_set_descriptor(void);
void usb_get_configuration(void);
void usb_set_configuration(void);
void usb_get_interface(void);
void usb_set_interface(void);
void usb_synch_frame(void);

#endif

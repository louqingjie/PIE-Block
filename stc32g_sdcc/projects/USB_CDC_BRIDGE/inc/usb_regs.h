#ifndef USB_CDC_BRIDGE_USB_REGS_H
#define USB_CDC_BRIDGE_USB_REGS_H

/*
 * STC32G USB 寄存器位定义。
 *
 * STC32Gxx.h 只给了 USB 寄存器地址（FADDR/POWER/INTRIN1/.../FIFO1），
 * 这里补齐官方 stc32g.h 里的位掩码。不要在这里重复定义寄存器地址，
 * 也不要把这些位写成 __sbit（USB 寄存器通过 USBADR/USBDAT 间接访问）。
 */

#define UPDATE                  0x80
#define ISOUD                   0x80
#define USBRST                  0x08
#define USBRSU                  0x04
#define USBSUS                  0x02
#define ENSUS                   0x01

#define EP5INIF                 0x20
#define EP4INIF                 0x10
#define EP3INIF                 0x08
#define EP2INIF                 0x04
#define EP1INIF                 0x02
#define EP0IF                   0x01

#define EP5OUTIF                0x20
#define EP4OUTIF                0x10
#define EP3OUTIF                0x08
#define EP2OUTIF                0x04
#define EP1OUTIF                0x02

#define SOFIF                   0x08
#define RSTIF                   0x04
#define RSUIF                   0x02
#define SUSIF                   0x01

#define EP5INIE                 0x20
#define EP4INIE                 0x10
#define EP3INIE                 0x08
#define EP2INIE                 0x04
#define EP1INIE                 0x02
#define EP0IE                   0x01

#define EP5OUTIE                0x20
#define EP4OUTIE                0x10
#define EP3OUTIE                0x08
#define EP2OUTIE                0x04
#define EP1OUTIE                0x02

#define SOFIE                   0x08
#define RSTIE                   0x04
#define RSUIE                   0x02
#define SUSIE                   0x01

#define SSUEND                  0x80
#define SOPRDY                  0x40
#define SDSTL                   0x20
#define SUEND                   0x10
#define DATEND                  0x08
#define STSTL                   0x04
#define IPRDY                   0x02
#define OPRDY                   0x01

#define INCLRDT                 0x40
#define INSTSTL                 0x20
#define INSDSTL                 0x10
#define INFLUSH                 0x08
#define INUNDRUN                0x04
#define INFIFONE                0x02
#define INIPRDY                 0x01

#define INAUTOSET               0x80
#define INISO                   0x40
#define INMODEIN                0x20
#define INMODEOUT               0x00
#define INENDMA                 0x10
#define INFCDT                  0x08

#define OUTCLRDT                0x80
#define OUTSTSTL                0x40
#define OUTSDSTL                0x20
#define OUTFLUSH                0x10
#define OUTDATERR               0x08
#define OUTOVRRUN               0x04
#define OUTFIFOFUL              0x02
#define OUTOPRDY                0x01

#define OUTAUTOCLR              0x80
#define OUTISO                  0x40
#define OUTENDMA                0x20
#define OUTDMAMD                0x10

#endif

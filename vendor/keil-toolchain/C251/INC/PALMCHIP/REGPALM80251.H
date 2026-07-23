/*-----------------------------------------------------------------------------
  REGPALM80251.H

Header file for PalmChip 80251 based IP core.
Copyright (c) 2011 ARM Ltd. and ARM Germnay GmbH.
All rights reserved.
-----------------------------------------------------------------------------*/

#ifndef __REGPALM80251_H__
#define __REGPALM80251_H__

/* Byte Registers */
sfr P0          = 0x80;            /* Port 0 Latch                           */
sfr P1          = 0x90;            /* Port 1 Latch                           */
sfr P2          = 0xA0;            /* Port 2 Latch                           */
sfr P3          = 0xB0;            /* Port 3 Latch                           */
sfr PSW         = 0xD0;            /* Program Status Word                    */
sfr PSW1        = 0xD1;            /* Program Status Word 1                  */
sfr ACC         = 0xE0;            /* Accumualtor                            */
sfr B           = 0xF0;            /* B register                             */
sfr SP          = 0x81;            /* Stackpointer low byte                  */
sfr SPH         = 0xBE;            /* Stackpointer high byte                 */
sfr DPL         = 0x82;            /* DPTR low byte                          */
sfr DPH         = 0x83;            /* DPTR high byte                         */
sfr DPXL        = 0x84;            /* DPTR extended low                      */
sfr PCON        = 0x87;            /* Power control                          */
sfr TCON        = 0x88;            /* Timer/Counter control                  */
sfr TMOD        = 0x89;            /* Timer/Counter Mode                     */
sfr TL0         = 0x8A;            /* Timer/Counter 0 low byte               */
sfr TL1         = 0x8B;            /* Timer/Counter 1 low byte               */
sfr TH0         = 0x8C;            /* Timer/Counter 0 high byte              */
sfr TH1         = 0x8D;            /* Timer/Counter 1 high byte              */
sfr IE0         = 0xA8;            /* Interrupt Enable                       */
sfr IPH0        = 0xB7;            /* Interrupt Priority Control High 0      */
sfr IPL0        = 0xB8;            /* Interrupt Priority Control Low 0       */
sfr SCON        = 0x98;            /* Serial port control                    */
sfr SBUF        = 0x99;            /* Serial buffer                          */
sfr SADDR       = 0xA9;            /* Slave Address                          */
sfr SADEN       = 0xB9;            /* Slave Address Mask                     */
sfr T2CON       = 0xC8;            /* Timer/Counter 2 Control                */
sfr T2MOD       = 0xC9;            /* Timer/Counter 2 Mode Control           */
sfr RCAP2L      = 0xCA;            /* Timer 2 Reload/Capture Low Byte        */
sfr RCAP2H      = 0xCB;            /* Timer 2 Reload/Capture High Byte       */
sfr TL2         = 0xCC;            /* Timer/Counter 2 Low Byte               */
sfr TH2         = 0xCD;            /* Timer/Counter 2 High Byte              */
sfr CCON        = 0xD8;            /* PCA Timer/Counter Control              */
sfr CMOD        = 0xD9;            /* PCA Timer/Counter Mode                 */
sfr CCAPM0      = 0xDA;            /* PCA Timer/Counter Mode 0               */
sfr CCAPM1      = 0xDB;            /* PCA Timer/Counter Mode 1               */
sfr CCAPM2      = 0xDC;            /* PCA Timer/Counter Mode 2               */
sfr CCAPM3      = 0xDD;            /* PCA Timer/Counter Mode 3               */
sfr CCAPM4      = 0xDE;            /* PCA Timer/Counter Mode 4               */
sfr CL          = 0xE9;            /* PCA Timer/Counter Low Byte             */
sfr CCAP0L      = 0xEA;            /* PCA Compare/Capture Module 0 Low Byte  */
sfr CCAP1L      = 0xEB;            /* PCA Compare/Capture Module 1 Low Byte  */
sfr CCAP2L      = 0xEC;            /* PCA Compare/Capture Module 2 Low Byte  */
sfr CCAP3L      = 0xED;            /* PCA Compare/Capture Module 3 Low Byte  */
sfr CCAP4L      = 0xEE;            /* PCA Compare/Capture Module 4 Low Byte  */
sfr CH          = 0xF9;            /* PCA Timer/Counter High Byte            */
sfr CCAP0H      = 0xFA;            /* PCA Compare/Capture Module 0 High Byte */
sfr CCAP1H      = 0xFB;            /* PCA Compare/Capture Module 1 High Byte */
sfr CCAP2H      = 0xFC;            /* PCA Compare/Capture Module 2 High Byte */
sfr CCAP3H      = 0xFD;            /* PCA Compare/Capture Module 3 High Byte */
sfr CCAP4H      = 0xFE;            /* PCA Compare/Capture Module 4 High Byte */
sfr WDTRST      = 0xA6;            /* Watchdog Timer Reset                   */
sfr WCON        = 0xA7;            /* Wait State Control Register            */

/* Bit Definitions */
/* PCON 0x87 */
sbit SMOD1    = PCON^7;            /* Timer 1 Overflow Flag                  */
sbit SMOD0    = PCON^6;            /* Timer 1 On/Off Run Control             */
                                   /* Bit 5 Reserved                         */
sbit POF      = PCON^4;            /* Power On Flag                          */
sbit GF1      = PCON^3;            /* General Purpose Flag 1                 */
sbit GF0      = PCON^2;            /* General Purpose Flag 0                 */
sbit PD       = PCON^1;            /* Power Down                             */
sbit IDL      = PCON^0;            /* Idle Mode Bit                          */

/* TCON 0x88 */
sbit TF1      = TCON^7;            /* Timer 1 Overflow Flag                  */
sbit TR1      = TCON^6;            /* Timer 1 On/Off Run Control             */
sbit TF0      = TCON^5;            /* Timer 0 Overflow Flag                  */
sbit TR0      = TCON^4;            /* Timer 0 On/Off Run Control             */
sbit IE1      = TCON^3;            /* Ext. Interrupt 1 Edge Flag             */
sbit IT1      = TCON^2;            /* Ext. Interrupt 1 Configuration         */
sbit IE0_     = TCON^1;            /* Ext. Interrupt 0 Edge Flag             */
sbit IT0      = TCON^0;            /* Ext. Interrupt 0 Configuration         */

/* TMOD 0x89 */
sbit GATE1    = TMOD^7;            /* Timer 1 Gate                           */
sbit T1       = TMOD^6;            /* Timer 1 Counter/Timer select           */
sbit M11      = TMOD^5;            /* Timer 1 Mode select bit 1              */
sbit M01      = TMOD^4;            /* Timer 1 Mode select bit 0              */
sbit GATE0    = TMOD^3;            /* Timer 0 Gate                           */
sbit T0       = TMOD^2;            /* Timer 0 Counter/Timer select           */
sbit M10      = TMOD^1;            /* Timer 0 Mode select bit 1              */
sbit M00      = TMOD^0;            /* Timer 0 Mode select bit 0              */

/* SCON 0x98 */
sbit SM0      = SCON^7;            /* Serial Port Mode Bit 0                 */
sbit SM1      = SCON^6;            /* Serial Port Mode Bit 1                 */
sbit SM2      = SCON^5;            /* Serial Port Mode Bit 2                 */
sbit REN      = SCON^4;            /* Receiver Enable                        */
sbit TB8      = SCON^3;            /* Transmission Bit                       */
sbit RB8      = SCON^2;            /* Reception Bit                          */
sbit TI       = SCON^1;            /* Transmitter Interrupt                  */
sbit RI       = SCON^0;            /* Receiver Interrupt                     */

/* WCON 0xA7 */
                                   /* Bit 7 Reserved                         */
                                   /* Bit 6 Reserved                         */
                                   /* Bit 5 Reserved                         */
                                   /* Bit 4 Reserved                         */
                                   /* Bit 3 Reserved                         */
                                   /* Bit 2 Reserved                         */
sbit RTWCE    = WCON^1;            /* Real time WAIT CLOCK enable            */
sbit RTWE     = WCON^0;            /* Real time WAIT enable                  */

/* IE0 0xA8 */
sbit EA       = IE0^7;             /* Global Interrupt Enable                */
sbit EC       = IE0^6;             /* PCA Interrupt Enable                   */
sbit ET2      = IE0^5;             /* Timer 2 Interrupt Enable               */
sbit ES       = IE0^4;             /* Serial Port Interrupt Enable           */
sbit ET1      = IE0^3;             /* Timer 1 Interrupt Enable               */
sbit EX1      = IE0^2;             /* External Interrupt 1 Enable            */
sbit ET0      = IE0^1;             /* Timer 0 Interrupt Enable               */
sbit EX0      = IE0^0;             /* External Interrupt 0 Enable            */

/* IPH0 0xB7 */
                                   /* Reserved                               */
sbit IPH0_6   = IPH0^6;            /* PCA Interrupt Priority Bit High        */
sbit IPH0_5   = IPH0^5;            /* Timer 2 Interrupt Priority Bit High    */
sbit IPH0_4   = IPH0^4;            /* Serial Port Interrupt Priority Bit High*/
sbit IPH0_3   = IPH0^3;            /* Timer 1 Interrupt Priority Bit High    */
sbit IPH0_2   = IPH0^2;            /* External Interrupt 1 Priority Bit High */
sbit IPH0_1   = IPH0^1;            /* Timer 0 Interrupt Priority Bit High    */
sbit IPH0_0   = IPH0^0;            /* External Interrupt 0 Priority Bit High */

/* IPL0 0xB8 */
                                   /* Reserved                               */
sbit IPL0_6   = IPL0^6;            /* PCA Interrupt Priority Bit Low         */
sbit IPL0_5   = IPL0^5;            /* Timer 2 Interrupt Priority Bit Low     */
sbit IPL0_4   = IPL0^4;            /* Serial Port Interrupt Priority Bit Low */
sbit IPL0_3   = IPL0^3;            /* Timer 1 Interrupt Priority Bit Low     */
sbit IPL0_2   = IPL0^2;            /* External Interrupt 1 Priority Bit Low  */
sbit IPL0_1   = IPL0^1;            /* Timer 0 Interrupt Priority Bit Low     */
sbit IPL0_0   = IPL0^0;            /* External Interrupt 0 Priority Bit Low  */

/* T2CON 0xC8 */
sbit TF2      = T2CON^7;           /* Timer 2 Overflow Flag                  */
sbit EXF2     = T2CON^6;           /* Timer 2 External Flag                  */
sbit RCLK     = T2CON^5;           /* Receive Clock Bit                      */
sbit TCLK     = T2CON^4;           /* Transmit Clock Bit                     */
sbit EXEN2    = T2CON^3;           /* Timer 2 External Enable Bit            */
sbit TR2      = T2CON^2;           /* Timer 2 Run Control Bit                */
sbit C        = T2CON^1;           /* Capture/Reload Bit                     */
sbit CP       = T2CON^0;           /* Capture/Reload Bit                     */

/* T2MOD 0xC9 */
                                   /* Bit 7 Reserved                         */
                                   /* Bit 6 Reserved                         */
                                   /* Bit 5 Reserved                         */
                                   /* Bit 4 Reserved                         */
                                   /* Bit 3 Reserved                         */
                                   /* Bit 2 Reserved                         */
sbit T2OE     = T2MOD^1;           /* Timer 2 Output Enable Bit              */
sbit DCEN     = T2MOD^0;           /* Down Count Enable Bit                  */

/* PSW 0xD0 */
sbit CY       = PSW^7;             /* Carry Flag                             */
sbit AC       = PSW^6;             /* Auxiliary Carry Flag                   */
sbit F0       = PSW^5;             /* General Purpose Flag 0                 */
sbit RS1      = PSW^4;             /* Register Bank Select 1                 */
sbit RS0      = PSW^3;             /* Register Bank Select 0                 */
sbit OV       = PSW^2;             /* Overflow Flag                          */
sbit UD       = PSW^1;             /* User Definable Flag                    */
sbit P        = PSW^0;             /* Accumulator Parity Flag                */

/* PSW1 0xD1 */
                                   /* Bit 7 Identical to the CY bit in PSW   */
                                   /* Bit 6 Identical to the AC bit in PSW   */
sbit N        = PSW1^5;            /* Negative Flag                          */
                                   /* Bit 4 Identical to the RS1 bit in PSW  */
                                   /* Bit 3 Identical to the RS0 bit in PSW  */
                                   /* Bit 2 Identical to the OV bit in PSW   */
sbit Z        = PSW1^1;            /* Zero Flag                              */
                                   /* Bit 0 Reserved                         */

/* CCAPM0 0xDA */
                                   /* Bit 7 Reserved                         */
sbit ECOM0    = CCAPM0^6;          /* Compare Modes                          */
sbit CAPP0    = CCAPM0^5;          /* Capture Mode (Positive)                */
sbit CAPN0    = CCAPM0^4;          /* Capture Mode (Negative)                */
sbit MAT0     = CCAPM0^3;          /* Match                                  */
sbit TOG0     = CCAPM0^2;          /* Toggle                                 */
sbit PWM0     = CCAPM0^1;          /* Pulse Width Modulation Mode            */
sbit ECCF0    = CCAPM0^0;          /* Enable CCF0 Interrupt                  */

/* CCAPM1 0xDB */
                                   /* Bit 7 Reserved                         */
sbit ECOM1    = CCAPM1^6;          /* Compare Modes                          */
sbit CAPP1    = CCAPM1^5;          /* Capture Mode (Positive)                */
sbit CAPN1    = CCAPM1^4;          /* Capture Mode (Negative)                */
sbit MAT1     = CCAPM1^3;          /* Match                                  */
sbit TOG1     = CCAPM1^2;          /* Toggle                                 */
sbit PWM1     = CCAPM1^1;          /* Pulse Width Modulation Mode            */
sbit ECCF1    = CCAPM1^0;          /* Enable CCF1 Interrupt                  */

/* CCAPM2 0xDC */
                                   /* Bit 7 Reserved                         */
sbit ECOM2    = CCAPM2^6;          /* Compare Modes                          */
sbit CAPP2    = CCAPM2^5;          /* Capture Mode (Positive)                */
sbit CAPN2    = CCAPM2^4;          /* Capture Mode (Negative)                */
sbit MAT2     = CCAPM2^3;          /* Match                                  */
sbit TOG2     = CCAPM2^2;          /* Toggle                                 */
sbit PWM2     = CCAPM2^1;          /* Pulse Width Modulation Mode            */
sbit ECCF2    = CCAPM2^0;          /* Enable CCF2 Interrupt                  */

/* CCAPM3 0xDD */
                                   /* Bit 7 Reserved                         */
sbit ECOM3    = CCAPM3^6;          /* Compare Modes                          */
sbit CAPP3    = CCAPM3^5;          /* Capture Mode (Positive)                */
sbit CAPN3    = CCAPM3^4;          /* Capture Mode (Negative)                */
sbit MAT3     = CCAPM3^3;          /* Match                                  */
sbit TOG3     = CCAPM3^2;          /* Toggle                                 */
sbit PWM3     = CCAPM3^1;          /* Pulse Width Modulation Mode            */
sbit ECCF3    = CCAPM3^0;          /* Enable CCF3 Interrupt                  */

/* CCAPM4 0xDE */
                                   /* Bit 7 Reserved                         */
sbit ECOM4    = CCAPM4^6;          /* Compare Modes                          */
sbit CAPP4    = CCAPM4^5;          /* Capture Mode (Positive)                */
sbit CAPN4    = CCAPM4^4;          /* Capture Mode (Negative)                */
sbit MAT4     = CCAPM4^3;          /* Match                                  */
sbit TOG4     = CCAPM4^2;          /* Toggle                                 */
sbit PWM4     = CCAPM4^1;          /* Pulse Width Modulation Mode            */
sbit ECCF4    = CCAPM4^0;          /* Enable CCF4 Interrupt                  */

/* CCON 0xD8 */
sbit CF       = CCON^7;            /* PCA Timer/Counter Overflow Flag        */
sbit CR       = CCON^6;            /* PCA Timer/Counter Run Control Bit      */
                                   /* Bit 5 Reserved                         */
sbit CCF4     = CCON^4;            /* PCA Module Compare/Capture Flag 4      */
sbit CCF3     = CCON^3;            /* PCA Module Compare/Capture Flag 3      */
sbit CCF2     = CCON^2;            /* PCA Module Compare/Capture Flag 2      */
sbit CCF1     = CCON^1;            /* PCA Module Compare/Capture Flag 1      */
sbit CCF0     = CCON^0;            /* PCA Module Compare/Capture Flag 0      */

/* CMOD 0xD9 */
sbit CIDL     = CMOD^7;            /* PCA Timer/Counter Idle Control         */
sbit WDTE     = CMOD^6;            /* Watchdog Timer Enable                  */
                                   /* Bit 5 Reserved                         */
                                   /* Bit 4 Reserved                         */
                                   /* Bit 3 Reserved                         */
sbit CPS1     = CMOD^2;            /* PCA Timer/Counter Input Select         */
sbit CPS0     = CMOD^1;            /* PCA Timer/Counter Input Select         */
sbit ECF      = CMOD^0;            /* PCA Timer/Counter Interrupt Enable     */


#endif                             /* #define __REGPALM8051_H__              */

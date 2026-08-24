#ifndef __STC32G_SDCC_H__
#define __STC32G_SDCC_H__

/* SDCC MCS-251 compatibility port for STC32G12K128. */
#if defined(__SDCC) && !defined(bit)
#define bit __bit
#endif

#ifndef     __STC32G_H__
#define     __STC32G_H__

/////////////////////////////////////////////////

__sfr __at (0x80) P0;
__sbit __at (0x80) P00;
__sbit __at (0x81) P01;
__sbit __at (0x82) P02;
__sbit __at (0x83) P03;
__sbit __at (0x84) P04;
__sbit __at (0x85) P05;
__sbit __at (0x86) P06;
__sbit __at (0x87) P07;
__sfr __at (0x81) SP;
__sfr __at (0x82) DPL;
__sfr __at (0x83) DPH;
__sfr __at (0x84) DPXL;
__sfr __at (0x85) SPH;
__sfr __at (0x87) PCON;
__sbit __at (0x8E) SMOD;
__sbit __at (0x8D) SMOD0;
__sbit __at (0x8C) LVDF;
__sbit __at (0x8B) POF;
__sbit __at (0x8A) GF1;
__sbit __at (0x89) GF0;
__sbit __at (0x88) PD;
__sbit __at (0x87) IDL;
__sfr __at (0x88) TCON;
__sbit __at (0x8F) TF1;
__sbit __at (0x8E) TR1;
__sbit __at (0x8D) TF0;
__sbit __at (0x8C) TR0;
__sbit __at (0x8B) IE1;
__sbit __at (0x8A) IT1;
__sbit __at (0x89) IE0;
__sbit __at (0x88) IT0;
__sfr __at (0x89) TMOD;
__sfr __at (0x8a) TL0;
__sfr __at (0x8b) TL1;
__sfr __at (0x8c) TH0;
__sfr __at (0x8d) TH1;
__sfr __at (0x8e) AUXR;
__sbit __at (0x95) T0x12;
__sbit __at (0x94) T1x12;
__sbit __at (0x93) S1M0x6;
__sbit __at (0x92) T2R;
__sbit __at (0x91) T2CT;
__sbit __at (0x90) T2x12;
__sbit __at (0x8F) EXTRAM;
__sbit __at (0x8E) S1BRT;
__sfr __at (0x8f) INTCLKO;
__sbit __at (0x95) EX4;
__sbit __at (0x94) EX3;
__sbit __at (0x93) EX2;
__sbit __at (0x91) T2CLKO;
__sbit __at (0x90) T1CLKO;
__sbit __at (0x8F) T0CLKO;
__sfr __at (0x90) P1;
__sbit __at (0x90) P10;
__sbit __at (0x91) P11;
__sbit __at (0x92) P12;
__sbit __at (0x93) P13;
__sbit __at (0x94) P14;
__sbit __at (0x95) P15;
__sbit __at (0x96) P16;
__sbit __at (0x97) P17;
__sfr __at (0x91) P1M1;
__sfr __at (0x92) P1M0;
__sfr __at (0x93) P0M1;
__sfr __at (0x94) P0M0;
__sfr __at (0x95) P2M1;
__sfr __at (0x96) P2M0;
__sfr __at (0x97) AUXR2;
__sbit __at (0x9A) CANSEL;
__sbit __at (0x99) CAN2EN;
__sbit __at (0x98) CANEN;
__sbit __at (0x97) LINEN;
__sfr __at (0x98) SCON;
__sbit __at (0x9F) SM0;
__sbit __at (0x9E) SM1;
__sbit __at (0x9D) SM2;
__sbit __at (0x9C) REN;
__sbit __at (0x9B) TB8;
__sbit __at (0x9A) RB8;
__sbit __at (0x99) TI;
__sbit __at (0x98) RI;
__sfr __at (0x99) SBUF;
__sfr __at (0x9a) S2CON;
__sbit __at (0xA1) S2SM0;
__sbit __at (0xA0) S2SM1;
__sbit __at (0x9F) S2SM2;
__sbit __at (0x9E) S2REN;
__sbit __at (0x9D) S2TB8;
__sbit __at (0x9C) S2RB8;
__sbit __at (0x9B) S2TI;
__sbit __at (0x9A) S2RI;
__sfr __at (0x9b) S2BUF;
__sfr __at (0x9d) IRCBAND;
__sbit __at (0xA4) USBCKS;
__sbit __at (0xA3) USBCKS2;
__sbit __at (0x9E) HIRCSEL1;
__sbit __at (0x9D) HIRCSEL0;
__sfr __at (0x9e) LIRTRIM;
__sfr __at (0x9f) IRTRIM;
__sfr __at (0xa0) P2;
__sbit __at (0xA0) P20;
__sbit __at (0xA1) P21;
__sbit __at (0xA2) P22;
__sbit __at (0xA3) P23;
__sbit __at (0xA4) P24;
__sbit __at (0xA5) P25;
__sbit __at (0xA6) P26;
__sbit __at (0xA7) P27;
__sfr __at (0xa1) BUS_SPEED;
__sfr __at (0xa2) P_SW1;
__sbit __at (0xA9) S1_S1;
__sbit __at (0xA8) S1_S0;
__sbit __at (0xA7) CAN_S1;
__sbit __at (0xA6) CAN_S0;
__sbit __at (0xA5) SPI_S1;
__sbit __at (0xA4) SPI_S0;
__sbit __at (0xA3) LIN_S1;
__sbit __at (0xA2) LIN_S0;
__sfr __at (0xa3) V33TRIM;
__sfr __at (0xa5) BGTRIM;
__sfr __at (0xa6) VRTRIM;
__sfr __at (0xa8) IE;
__sbit __at (0xAF) EA;
__sbit __at (0xAE) ELVD;
__sbit __at (0xAD) EADC;
__sbit __at (0xAC) ES;
__sbit __at (0xAB) ET1;
__sbit __at (0xAA) EX1;
__sbit __at (0xA9) ET0;
__sbit __at (0xA8) EX0;
__sfr __at (0xa9) SADDR;
__sfr __at (0xaa) WKTCL;
__sfr __at (0xab) WKTCH;
__sfr __at (0xac) S3CON;
__sbit __at (0xB3) S3SM0;
__sbit __at (0xB2) S3ST3;
__sbit __at (0xB1) S3SM2;
__sbit __at (0xB0) S3REN;
__sbit __at (0xAF) S3TB8;
__sbit __at (0xAE) S3RB8;
__sbit __at (0xAD) S3TI;
__sbit __at (0xAC) S3RI;
__sfr __at (0xad) S3BUF;
__sfr __at (0xae) TA;
__sfr __at (0xaf) IE2;
__sbit __at (0xB6) EUSB;
__sbit __at (0xB5) ET4;
__sbit __at (0xB4) ET3;
__sbit __at (0xB3) ES4;
__sbit __at (0xB2) ES3;
__sbit __at (0xB1) ET2;
__sbit __at (0xB0) ESPI;
__sbit __at (0xAF) ES2;
__sfr __at (0xb0) P3;
__sbit __at (0xB0) P30;
__sbit __at (0xB1) P31;
__sbit __at (0xB2) P32;
__sbit __at (0xB3) P33;
__sbit __at (0xB4) P34;
__sbit __at (0xB5) P35;
__sbit __at (0xB6) P36;
__sbit __at (0xB7) P37;
__sfr __at (0xb1) P3M1;
__sfr __at (0xb2) P3M0;
__sfr __at (0xb3) P4M1;
__sfr __at (0xb4) P4M0;
__sfr __at (0xb5) IP2;
__sbit __at (0xBC) PUSB;
__sbit __at (0xBB) PI2C;
__sbit __at (0xBA) PCMP;
__sbit __at (0xB9) PX4;
__sbit __at (0xB8) PPWMB;
__sbit __at (0xB7) PPWMA;
__sbit __at (0xB6) PSPI;
__sbit __at (0xB5) PS2;
__sfr __at (0xb6) IP2H;
__sbit __at (0xBD) PUSBH;
__sbit __at (0xBC) PI2CH;
__sbit __at (0xBB) PCMPH;
__sbit __at (0xBA) PX4H;
__sbit __at (0xB9) PPWMBH;
__sbit __at (0xB8) PPWMAH;
__sbit __at (0xB7) PSPIH;
__sbit __at (0xB6) PS2H;
__sfr __at (0xb7) IPH;
__sbit __at (0xBD) PLVDH;
__sbit __at (0xBC) PADCH;
__sbit __at (0xBB) PSH;
__sbit __at (0xBA) PT1H;
__sbit __at (0xB9) PX1H;
__sbit __at (0xB8) PT0H;
__sbit __at (0xB7) PX0H;
__sfr __at (0xb8) IP;
__sbit __at (0xBE) PLVD;
__sbit __at (0xBD) PADC;
__sbit __at (0xBC) PS;
__sbit __at (0xBB) PT1;
__sbit __at (0xBA) PX1;
__sbit __at (0xB9) PT0;
__sbit __at (0xB8) PX0;
__sfr __at (0xb9) SADEN;
__sfr __at (0xba) P_SW2;
__sbit __at (0xC1) EAXFR;
__sbit __at (0xBF) I2C_S1;
__sbit __at (0xBE) I2C_S0;
__sbit __at (0xBD) CMPO_S;
__sbit __at (0xBC) S4_S;
__sbit __at (0xBB) S3_S;
__sbit __at (0xBA) S2_S;
__sfr __at (0xbb) P_SW3;
__sbit __at (0xC2) I2S_S1;
__sbit __at (0xC1) I2S_S0;
__sbit __at (0xC0) S2SPI_S1;
__sbit __at (0xBF) S2SPI_S0;
__sbit __at (0xBE) S1SPI_S1;
__sbit __at (0xBD) S1SPI_S0;
__sbit __at (0xBC) CAN2_S1;
__sbit __at (0xBB) CAN2_S0;
__sfr __at (0xbc) ADC_CONTR;
__sbit __at (0xC3) ADC_POWER;
__sbit __at (0xC2) ADC_START;
__sbit __at (0xC1) ADC_FLAG;
__sbit __at (0xC0) ADC_EPWMT;
__sfr __at (0xbd) ADC_RES;
__sfr __at (0xbe) ADC_RESL;
__sfr __at (0xc0) P4;
__sbit __at (0xC0) P40;
__sbit __at (0xC1) P41;
__sbit __at (0xC2) P42;
__sbit __at (0xC3) P43;
__sbit __at (0xC4) P44;
__sbit __at (0xC5) P45;
__sbit __at (0xC6) P46;
__sbit __at (0xC7) P47;
__sfr __at (0xc1) WDT_CONTR;
__sbit __at (0xC8) WDT_FLAG;
__sbit __at (0xC6) EN_WDT;
__sbit __at (0xC5) CLR_WDT;
__sbit __at (0xC4) IDL_WDT;
__sfr __at (0xc2) IAP_DATA;
__sfr __at (0xc3) IAP_ADDRH;
__sfr __at (0xc4) IAP_ADDRL;
__sfr __at (0xc5) IAP_CMD;
__sfr __at (0xc6) IAP_TRIG;
__sfr __at (0xc7) IAP_CONTR;
__sfr __at (0xc8) P5;
__sbit __at (0xC8) P50;
__sbit __at (0xC9) P51;
__sbit __at (0xCA) P52;
__sbit __at (0xCB) P53;
__sbit __at (0xCC) P54;
__sbit __at (0xCD) P55;
__sbit __at (0xCE) P56;
__sbit __at (0xCF) P57;
__sfr __at (0xc9) P5M1;
__sfr __at (0xca) P5M0;
__sfr __at (0xcb) P6M1;
__sfr __at (0xcc) P6M0;
__sfr __at (0xcd) SPSTAT;
__sbit __at (0xD4) SPIF;
__sbit __at (0xD3) WCOL;
__sfr __at (0xce) SPCTL;
__sbit __at (0xD5) SSIG;
__sbit __at (0xD4) SPEN;
__sbit __at (0xD3) DORD;
__sbit __at (0xD2) MSTR;
__sbit __at (0xD1) CPOL;
__sbit __at (0xD0) CPHA;
__sbit __at (0xCF) SPR1;
__sbit __at (0xCE) SPR0;
__sfr __at (0xcf) SPDAT;
__sfr __at (0xd0) PSW;
__sbit __at (0xD7) CY;
__sbit __at (0xD6) AC;
__sbit __at (0xD5) F0;
__sbit __at (0xD4) RS1;
__sbit __at (0xD3) RS0;
__sbit __at (0xD2) OV;
__sbit __at (0xD0) P;
__sfr __at (0xd1) PSW1;
__sfr __at (0xd2) T4H;
__sfr __at (0xd3) T4L;
__sfr __at (0xd4) T3H;
__sfr __at (0xd5) T3L;
__sfr __at (0xd6) T2H;
__sfr __at (0xd7) T2L;
__sfr __at (0xdc) USBCLK;
__sfr __at (0xdd) T4T3M;
__sbit __at (0xE4) T4R;
__sbit __at (0xE3) T4CT;
__sbit __at (0xE2) T4x12;
__sbit __at (0xE1) T4CLKO;
__sbit __at (0xE0) T3R;
__sbit __at (0xDF) T3CT;
__sbit __at (0xDE) T3x12;
__sbit __at (0xDD) T3CLKO;
__sfr __at (0xde) ADCCFG;
__sfr __at (0xdf) IP3;
__sbit __at (0xE2) PI2S;
__sbit __at (0xE1) PRTC;
__sbit __at (0xE0) PS4;
__sbit __at (0xDF) PS3;
__sfr __at (0xe0) ACC;
__sfr __at (0xe1) P7M1;
__sfr __at (0xe2) P7M0;
__sfr __at (0xe3) DPS;
__sfr __at (0xe4) DPL1;
__sfr __at (0xe5) DPH1;
__sfr __at (0xe6) CMPCR1;
__sbit __at (0xED) CMPEN;
__sbit __at (0xEC) CMPIF;
__sbit __at (0xEB) PIE;
__sbit __at (0xEA) NIE;
__sbit __at (0xE7) CMPOE;
__sbit __at (0xE6) CMPRES;
__sfr __at (0xe7) CMPCR2;
__sbit __at (0xEE) INVCMPO;
__sbit __at (0xED) DISFLT;
__sfr __at (0xe8) P6;
__sbit __at (0xE8) P60;
__sbit __at (0xE9) P61;
__sbit __at (0xEA) P62;
__sbit __at (0xEB) P63;
__sbit __at (0xEC) P64;
__sbit __at (0xED) P65;
__sbit __at (0xEE) P66;
__sbit __at (0xEF) P67;
__sfr __at (0xe9) WTST;
__sfr __at (0xea) CKCON;
__sfr __at (0xeb) MXAX;
__sfr __at (0xec) USBDAT;
__sfr __at (0xed) DMAIR;
__sfr __at (0xee) IP3H;
__sbit __at (0xF1) PI2SH;
__sbit __at (0xF0) PRTCH;
__sbit __at (0xEF) PS4H;
__sbit __at (0xEE) PS3H;
__sfr __at (0xef) AUXINTIF;
__sbit __at (0xF5) INT4IF;
__sbit __at (0xF4) INT3IF;
__sbit __at (0xF3) INT2IF;
__sbit __at (0xF1) T4IF;
__sbit __at (0xF0) T3IF;
__sbit __at (0xEF) T2IF;
__sfr __at (0xf0) B;
__sfr __at (0xf1) CANICR;
__sbit __at (0xF8) PCAN2H;
__sbit __at (0xF7) CAN2IF;
__sbit __at (0xF6) CAN2IE;
__sbit __at (0xF5) PCAN2L;
__sbit __at (0xF4) PCANH;
__sbit __at (0xF3) CANIF;
__sbit __at (0xF2) CANIE;
__sbit __at (0xF1) PCANL;
__sfr __at (0xf4) USBCON;
__sbit __at (0xFB) ENUSB;
__sbit __at (0xFA) USBRST;
__sbit __at (0xF9) PS2M;
__sbit __at (0xF8) PUEN;
__sbit __at (0xF7) PDEN;
__sbit __at (0xF6) DFREC;
__sbit __at (0xF5) DP;
__sbit __at (0xF4) DM;
__sfr __at (0xf5) IAP_TPS;
__sfr __at (0xf6) IAP_ADDRE;
__sfr __at (0xf7) ICHECR;
__sfr __at (0xf8) P7;
__sbit __at (0xF8) P70;
__sbit __at (0xF9) P71;
__sbit __at (0xFA) P72;
__sbit __at (0xFB) P73;
__sbit __at (0xFC) P74;
__sbit __at (0xFD) P75;
__sbit __at (0xFE) P76;
__sbit __at (0xFF) P77;
__sfr __at (0xf9) LINICR;
__sbit __at (0xFC) PLINH;
__sbit __at (0xFB) LINIF;
__sbit __at (0xFA) LINIE;
__sbit __at (0xF9) PLINL;
__sfr __at (0xfa) LINAR;
__sfr __at (0xfb) LINDR;
__sfr __at (0xfc) USBADR;
__sfr __at (0xfd) S4CON;
__sbit __at (0x104) S4SM0;
__sbit __at (0x103) S4ST4;
__sbit __at (0x102) S4SM2;
__sbit __at (0x101) S4REN;
__sbit __at (0x100) S4TB8;
__sbit __at (0xFF) S4RB8;
__sbit __at (0xFE) S4TI;
__sbit __at (0xFD) S4RI;
__sfr __at (0xfe) S4BUF;
__sfr __at (0xff) RSTCFG;
__sbit __at (0x105) ENLVR;

/* RSTCFG is not in the MCS-251 bit-addressable page. */
#define P54RST_MASK 0x10U
#define P54RST ((RSTCFG & P54RST_MASK) != 0)

//�������⹦�ܼĴ���λ����չRAM����
//������Щ�Ĵ���,���Ƚ�EAXFR����Ϊ1,�ſ�������д
//    EAXFR = 1;
//����
//    P_SW2 |= 0x80;

/////////////////////////////////////////////////
//7E:FF00H-7E:FFFFH
/////////////////////////////////////////////////



/////////////////////////////////////////////////
//7E:FE00H-7E:FEFFH
/////////////////////////////////////////////////

#define     CLKSEL                  (*(volatile __xdata unsigned char *)0x7efe00)
#define     CLKDIV                  (*(volatile __xdata unsigned char *)0x7efe01)
#define     HIRCCR                  (*(volatile __xdata unsigned char *)0x7efe02)
#define     XOSCCR                  (*(volatile __xdata unsigned char *)0x7efe03)
#define     IRC32KCR                (*(volatile __xdata unsigned char *)0x7efe04)
#define     MCLKOCR                 (*(volatile __xdata unsigned char *)0x7efe05)
#define     IRCDB                   (*(volatile __xdata unsigned char *)0x7efe06)
#define     IRC48MCR                (*(volatile __xdata unsigned char *)0x7efe07)
#define     X32KCR                  (*(volatile __xdata unsigned char *)0x7efe08)
#define     IRC48ATRIM              (*(volatile __xdata unsigned char *)0x7efe09)
#define     IRC48BTRIM              (*(volatile __xdata unsigned char *)0x7efe0a)
#define     HSCLKDIV                (*(volatile __xdata unsigned char *)0x7efe0b)

#define     P0PU                    (*(volatile __xdata unsigned char *)0x7efe10)
#define     P1PU                    (*(volatile __xdata unsigned char *)0x7efe11)
#define     P2PU                    (*(volatile __xdata unsigned char *)0x7efe12)
#define     P3PU                    (*(volatile __xdata unsigned char *)0x7efe13)
#define     P4PU                    (*(volatile __xdata unsigned char *)0x7efe14)
#define     P5PU                    (*(volatile __xdata unsigned char *)0x7efe15)
#define     P6PU                    (*(volatile __xdata unsigned char *)0x7efe16)
#define     P7PU                    (*(volatile __xdata unsigned char *)0x7efe17)
#define     P0NCS                   (*(volatile __xdata unsigned char *)0x7efe18)
#define     P1NCS                   (*(volatile __xdata unsigned char *)0x7efe19)
#define     P2NCS                   (*(volatile __xdata unsigned char *)0x7efe1a)
#define     P3NCS                   (*(volatile __xdata unsigned char *)0x7efe1b)
#define     P4NCS                   (*(volatile __xdata unsigned char *)0x7efe1c)
#define     P5NCS                   (*(volatile __xdata unsigned char *)0x7efe1d)
#define     P6NCS                   (*(volatile __xdata unsigned char *)0x7efe1e)
#define     P7NCS                   (*(volatile __xdata unsigned char *)0x7efe1f)
#define     P0SR                    (*(volatile __xdata unsigned char *)0x7efe20)
#define     P1SR                    (*(volatile __xdata unsigned char *)0x7efe21)
#define     P2SR                    (*(volatile __xdata unsigned char *)0x7efe22)
#define     P3SR                    (*(volatile __xdata unsigned char *)0x7efe23)
#define     P4SR                    (*(volatile __xdata unsigned char *)0x7efe24)
#define     P5SR                    (*(volatile __xdata unsigned char *)0x7efe25)
#define     P6SR                    (*(volatile __xdata unsigned char *)0x7efe26)
#define     P7SR                    (*(volatile __xdata unsigned char *)0x7efe27)
#define     P0DR                    (*(volatile __xdata unsigned char *)0x7efe28)
#define     P1DR                    (*(volatile __xdata unsigned char *)0x7efe29)
#define     P2DR                    (*(volatile __xdata unsigned char *)0x7efe2a)
#define     P3DR                    (*(volatile __xdata unsigned char *)0x7efe2b)
#define     P4DR                    (*(volatile __xdata unsigned char *)0x7efe2c)
#define     P5DR                    (*(volatile __xdata unsigned char *)0x7efe2d)
#define     P6DR                    (*(volatile __xdata unsigned char *)0x7efe2e)
#define     P7DR                    (*(volatile __xdata unsigned char *)0x7efe2f)
#define     P0IE                    (*(volatile __xdata unsigned char *)0x7efe30)
#define     P1IE                    (*(volatile __xdata unsigned char *)0x7efe31)
#define     P2IE                    (*(volatile __xdata unsigned char *)0x7efe32)
#define     P3IE                    (*(volatile __xdata unsigned char *)0x7efe33)
#define     P4IE                    (*(volatile __xdata unsigned char *)0x7efe34)
#define     P5IE                    (*(volatile __xdata unsigned char *)0x7efe35)
#define     P6IE                    (*(volatile __xdata unsigned char *)0x7efe36)
#define     P7IE                    (*(volatile __xdata unsigned char *)0x7efe37)

#define     LCMIFCFG                (*(volatile __xdata unsigned char *)0x7efe50)
#define     LCMIFCFG2               (*(volatile __xdata unsigned char *)0x7efe51)
#define     LCMIFCR                 (*(volatile __xdata unsigned char *)0x7efe52)
#define     LCMIFSTA                (*(volatile __xdata unsigned char *)0x7efe53)
#define     LCMIFDATL               (*(volatile __xdata unsigned char *)0x7efe54)
#define     LCMIFDATH               (*(volatile __xdata unsigned char *)0x7efe55)

#define     RTCCR                   (*(volatile __xdata unsigned char *)0x7efe60)
#define     RTCCFG                  (*(volatile __xdata unsigned char *)0x7efe61)
#define     RTCIEN                  (*(volatile __xdata unsigned char *)0x7efe62)
#define     RTCIF                   (*(volatile __xdata unsigned char *)0x7efe63)
#define     ALAHOUR                 (*(volatile __xdata unsigned char *)0x7efe64)
#define     ALAMIN                  (*(volatile __xdata unsigned char *)0x7efe65)
#define     ALASEC                  (*(volatile __xdata unsigned char *)0x7efe66)
#define     ALASSEC                 (*(volatile __xdata unsigned char *)0x7efe67)
#define     INIYEAR                 (*(volatile __xdata unsigned char *)0x7efe68)
#define     INIMONTH                (*(volatile __xdata unsigned char *)0x7efe69)
#define     INIDAY                  (*(volatile __xdata unsigned char *)0x7efe6a)
#define     INIHOUR                 (*(volatile __xdata unsigned char *)0x7efe6b)
#define     INIMIN                  (*(volatile __xdata unsigned char *)0x7efe6c)
#define     INISEC                  (*(volatile __xdata unsigned char *)0x7efe6d)
#define     INISSEC                 (*(volatile __xdata unsigned char *)0x7efe6e)
#define     YEAR                    (*(volatile __xdata unsigned char *)0x7efe70)
#define     MONTH                   (*(volatile __xdata unsigned char *)0x7efe71)
#define     DAY                     (*(volatile __xdata unsigned char *)0x7efe72)
#define     HOUR                    (*(volatile __xdata unsigned char *)0x7efe73)
#define     MIN                     (*(volatile __xdata unsigned char *)0x7efe74)
#define     SEC                     (*(volatile __xdata unsigned char *)0x7efe75)
#define     SSEC                    (*(volatile __xdata unsigned char *)0x7efe76)

#define     I2CCFG                  (*(volatile __xdata unsigned char *)0x7efe80)
#define     I2CMSCR                 (*(volatile __xdata unsigned char *)0x7efe81)
#define     I2CMSST                 (*(volatile __xdata unsigned char *)0x7efe82)
#define     I2CSLCR                 (*(volatile __xdata unsigned char *)0x7efe83)
#define     I2CSLST                 (*(volatile __xdata unsigned char *)0x7efe84)
#define     I2CSLADR                (*(volatile __xdata unsigned char *)0x7efe85)
#define     I2CTXD                  (*(volatile __xdata unsigned char *)0x7efe86)
#define     I2CRXD                  (*(volatile __xdata unsigned char *)0x7efe87)
#define     I2CMSAUX                (*(volatile __xdata unsigned char *)0x7efe88)

#define     SPFUNC                  (*(volatile __xdata unsigned char *)0x7efe98)
#define     RSTFLAG                 (*(volatile __xdata unsigned char *)0x7efe99)
#define     RSTCR0                  (*(volatile __xdata unsigned char *)0x7efe9a)
#define     RSTCR1                  (*(volatile __xdata unsigned char *)0x7efe9b)
#define     RSTCR2                  (*(volatile __xdata unsigned char *)0x7efe9c)
#define     RSTCR3                  (*(volatile __xdata unsigned char *)0x7efe9d)
#define     RSTCR4                  (*(volatile __xdata unsigned char *)0x7efe9e)
#define     RSTCR5                  (*(volatile __xdata unsigned char *)0x7efe9f)

#define     TM0PS                   (*(volatile __xdata unsigned char *)0x7efea0)
#define     TM1PS                   (*(volatile __xdata unsigned char *)0x7efea1)
#define     TM2PS                   (*(volatile __xdata unsigned char *)0x7efea2)
#define     TM3PS                   (*(volatile __xdata unsigned char *)0x7efea3)
#define     TM4PS                   (*(volatile __xdata unsigned char *)0x7efea4)
#define     ADCTIM                  (*(volatile __xdata unsigned char *)0x7efea8)
#define     T3T4PS                  (*(volatile __xdata unsigned char *)0x7efeac)
#define     ADCEXCFG                (*(volatile __xdata unsigned char *)0x7efead)
#define     CMPEXCFG                (*(volatile __xdata unsigned char *)0x7efeae)

#define     PWMA_ETRPS              (*(volatile __xdata unsigned char *)0x7efeb0)
#define     PWMA_ENO                (*(volatile __xdata unsigned char *)0x7efeb1)
#define     PWMA_PS                 (*(volatile __xdata unsigned char *)0x7efeb2)
#define     PWMA_IOAUX              (*(volatile __xdata unsigned char *)0x7efeb3)
#define     PWMB_ETRPS              (*(volatile __xdata unsigned char *)0x7efeb4)
#define     PWMB_ENO                (*(volatile __xdata unsigned char *)0x7efeb5)
#define     PWMB_PS                 (*(volatile __xdata unsigned char *)0x7efeb6)
#define     PWMB_IOAUX              (*(volatile __xdata unsigned char *)0x7efeb7)
#define     CANAR                   (*(volatile __xdata unsigned char *)0x7efebb)
#define     CANDR                   (*(volatile __xdata unsigned char *)0x7efebc)
#define     PWMA_CR1                (*(volatile __xdata unsigned char *)0x7efec0)
#define     PWMA_CR2                (*(volatile __xdata unsigned char *)0x7efec1)
#define     PWMA_SMCR               (*(volatile __xdata unsigned char *)0x7efec2)
#define     PWMA_ETR                (*(volatile __xdata unsigned char *)0x7efec3)
#define     PWMA_IER                (*(volatile __xdata unsigned char *)0x7efec4)
#define     PWMA_SR1                (*(volatile __xdata unsigned char *)0x7efec5)
#define     PWMA_SR2                (*(volatile __xdata unsigned char *)0x7efec6)
#define     PWMA_EGR                (*(volatile __xdata unsigned char *)0x7efec7)
#define     PWMA_CCMR1              (*(volatile __xdata unsigned char *)0x7efec8)
#define     PWMA_CCMR2              (*(volatile __xdata unsigned char *)0x7efec9)
#define     PWMA_CCMR3              (*(volatile __xdata unsigned char *)0x7efeca)
#define     PWMA_CCMR4              (*(volatile __xdata unsigned char *)0x7efecb)
#define     PWMA_CCER1              (*(volatile __xdata unsigned char *)0x7efecc)
#define     PWMA_CCER2              (*(volatile __xdata unsigned char *)0x7efecd)
#define     PWMA_CNTRH              (*(volatile __xdata unsigned char *)0x7efece)
#define     PWMA_CNTRL              (*(volatile __xdata unsigned char *)0x7efecf)
#define     PWMA_PSCRH              (*(volatile __xdata unsigned char *)0x7efed0)
#define     PWMA_PSCRL              (*(volatile __xdata unsigned char *)0x7efed1)
#define     PWMA_ARRH               (*(volatile __xdata unsigned char *)0x7efed2)
#define     PWMA_ARRL               (*(volatile __xdata unsigned char *)0x7efed3)
#define     PWMA_RCR                (*(volatile __xdata unsigned char *)0x7efed4)
#define     PWMA_CCR1H              (*(volatile __xdata unsigned char *)0x7efed5)
#define     PWMA_CCR1L              (*(volatile __xdata unsigned char *)0x7efed6)
#define     PWMA_CCR2H              (*(volatile __xdata unsigned char *)0x7efed7)
#define     PWMA_CCR2L              (*(volatile __xdata unsigned char *)0x7efed8)
#define     PWMA_CCR3H              (*(volatile __xdata unsigned char *)0x7efed9)
#define     PWMA_CCR3L              (*(volatile __xdata unsigned char *)0x7efeda)
#define     PWMA_CCR4H              (*(volatile __xdata unsigned char *)0x7efedb)
#define     PWMA_CCR4L              (*(volatile __xdata unsigned char *)0x7efedc)
#define     PWMA_BKR                (*(volatile __xdata unsigned char *)0x7efedd)
#define     PWMA_DTR                (*(volatile __xdata unsigned char *)0x7efede)
#define     PWMA_OISR               (*(volatile __xdata unsigned char *)0x7efedf)
#define     PWMB_CR1                (*(volatile __xdata unsigned char *)0x7efee0)
#define     PWMB_CR2                (*(volatile __xdata unsigned char *)0x7efee1)
#define     PWMB_SMCR               (*(volatile __xdata unsigned char *)0x7efee2)
#define     PWMB_ETR                (*(volatile __xdata unsigned char *)0x7efee3)
#define     PWMB_IER                (*(volatile __xdata unsigned char *)0x7efee4)
#define     PWMB_SR1                (*(volatile __xdata unsigned char *)0x7efee5)
#define     PWMB_SR2                (*(volatile __xdata unsigned char *)0x7efee6)
#define     PWMB_EGR                (*(volatile __xdata unsigned char *)0x7efee7)
#define     PWMB_CCMR1              (*(volatile __xdata unsigned char *)0x7efee8)
#define     PWMB_CCMR2              (*(volatile __xdata unsigned char *)0x7efee9)
#define     PWMB_CCMR3              (*(volatile __xdata unsigned char *)0x7efeea)
#define     PWMB_CCMR4              (*(volatile __xdata unsigned char *)0x7efeeb)
#define     PWMB_CCER1              (*(volatile __xdata unsigned char *)0x7efeec)
#define     PWMB_CCER2              (*(volatile __xdata unsigned char *)0x7efeed)
#define     PWMB_CNTRH              (*(volatile __xdata unsigned char *)0x7efeee)
#define     PWMB_CNTRL              (*(volatile __xdata unsigned char *)0x7efeef)
#define     PWMB_PSCRH              (*(volatile __xdata unsigned char *)0x7efef0)
#define     PWMB_PSCRL              (*(volatile __xdata unsigned char *)0x7efef1)
#define     PWMB_ARRH               (*(volatile __xdata unsigned char *)0x7efef2)
#define     PWMB_ARRL               (*(volatile __xdata unsigned char *)0x7efef3)
#define     PWMB_RCR                (*(volatile __xdata unsigned char *)0x7efef4)
#define     PWMB_CCR1H              (*(volatile __xdata unsigned char *)0x7efef5)
#define     PWMB_CCR1L              (*(volatile __xdata unsigned char *)0x7efef6)
#define     PWMB_CCR2H              (*(volatile __xdata unsigned char *)0x7efef7)
#define     PWMB_CCR2L              (*(volatile __xdata unsigned char *)0x7efef8)
#define     PWMB_CCR3H              (*(volatile __xdata unsigned char *)0x7efef9)
#define     PWMB_CCR3L              (*(volatile __xdata unsigned char *)0x7efefa)
#define     PWMB_CCR4H              (*(volatile __xdata unsigned char *)0x7efefb)
#define     PWMB_CCR4L              (*(volatile __xdata unsigned char *)0x7efefc)
#define     PWMB_BKR                (*(volatile __xdata unsigned char *)0x7efefd)
#define     PWMB_DTR                (*(volatile __xdata unsigned char *)0x7efefe)
#define     PWMB_OISR               (*(volatile __xdata unsigned char *)0x7efeff)

typedef struct TAG_PWM_STRUCT
{
    unsigned char CR1;
    unsigned char CR2;
    unsigned char SMCR;
    unsigned char ETR;
    unsigned char IER;
    unsigned char SR1;
    unsigned char SR2;
    unsigned char EGR;
    unsigned char CCMR1;
    unsigned char CCMR2;
    unsigned char CCMR3;
    unsigned char CCMR4;
    unsigned char CCER1;
    unsigned char CCER2;
    unsigned char CNTRH;
    unsigned char CNTRL;
    unsigned char PSCRH;
    unsigned char PSCRL;
    unsigned char ARRH;
    unsigned char ARRL;
    unsigned char RCR;
    unsigned char CCR1H;
    unsigned char CCR1L;
    unsigned char CCR2H;
    unsigned char CCR2L;
    unsigned char CCR3H;
    unsigned char CCR3L;
    unsigned char CCR4H;
    unsigned char CCR4L;
    unsigned char BKR;
    unsigned char DTR;
    unsigned char OISR;
} PWM_STRUCT;

#define     PWMA                    ((volatile __xdata PWM_STRUCT *)0x7efec0)
#define     PWMB                    ((volatile __xdata PWM_STRUCT *)0x7efee0)

/////////////////////////////////////////////////
//7E:FD00H-7E:FDFFH
/////////////////////////////////////////////////
#define     PWM2_OISR               (*(volatile __xdata unsigned char *)0x7efeff)

#define     P0INTE                  (*(volatile __xdata unsigned char *)0x7efd00)
#define     P1INTE                  (*(volatile __xdata unsigned char *)0x7efd01)
#define     P2INTE                  (*(volatile __xdata unsigned char *)0x7efd02)
#define     P3INTE                  (*(volatile __xdata unsigned char *)0x7efd03)
#define     P4INTE                  (*(volatile __xdata unsigned char *)0x7efd04)
#define     P5INTE                  (*(volatile __xdata unsigned char *)0x7efd05)
#define     P6INTE                  (*(volatile __xdata unsigned char *)0x7efd06)
#define     P7INTE                  (*(volatile __xdata unsigned char *)0x7efd07)
#define     P0INTF                  (*(volatile __xdata unsigned char *)0x7efd10)
#define     P1INTF                  (*(volatile __xdata unsigned char *)0x7efd11)
#define     P2INTF                  (*(volatile __xdata unsigned char *)0x7efd12)
#define     P3INTF                  (*(volatile __xdata unsigned char *)0x7efd13)
#define     P4INTF                  (*(volatile __xdata unsigned char *)0x7efd14)
#define     P5INTF                  (*(volatile __xdata unsigned char *)0x7efd15)
#define     P6INTF                  (*(volatile __xdata unsigned char *)0x7efd16)
#define     P7INTF                  (*(volatile __xdata unsigned char *)0x7efd17)
#define     P0IM0                   (*(volatile __xdata unsigned char *)0x7efd20)
#define     P1IM0                   (*(volatile __xdata unsigned char *)0x7efd21)
#define     P2IM0                   (*(volatile __xdata unsigned char *)0x7efd22)
#define     P3IM0                   (*(volatile __xdata unsigned char *)0x7efd23)
#define     P4IM0                   (*(volatile __xdata unsigned char *)0x7efd24)
#define     P5IM0                   (*(volatile __xdata unsigned char *)0x7efd25)
#define     P6IM0                   (*(volatile __xdata unsigned char *)0x7efd26)
#define     P7IM0                   (*(volatile __xdata unsigned char *)0x7efd27)
#define     P0IM1                   (*(volatile __xdata unsigned char *)0x7efd30)
#define     P1IM1                   (*(volatile __xdata unsigned char *)0x7efd31)
#define     P2IM1                   (*(volatile __xdata unsigned char *)0x7efd32)
#define     P3IM1                   (*(volatile __xdata unsigned char *)0x7efd33)
#define     P4IM1                   (*(volatile __xdata unsigned char *)0x7efd34)
#define     P5IM1                   (*(volatile __xdata unsigned char *)0x7efd35)
#define     P6IM1                   (*(volatile __xdata unsigned char *)0x7efd36)
#define     P7IM1                   (*(volatile __xdata unsigned char *)0x7efd37)
#define     P0WKUE                  (*(volatile __xdata unsigned char *)0x7efd40)
#define     P1WKUE                  (*(volatile __xdata unsigned char *)0x7efd41)
#define     P2WKUE                  (*(volatile __xdata unsigned char *)0x7efd42)
#define     P3WKUE                  (*(volatile __xdata unsigned char *)0x7efd43)
#define     P4WKUE                  (*(volatile __xdata unsigned char *)0x7efd44)
#define     P5WKUE                  (*(volatile __xdata unsigned char *)0x7efd45)
#define     P6WKUE                  (*(volatile __xdata unsigned char *)0x7efd46)
#define     P7WKUE                  (*(volatile __xdata unsigned char *)0x7efd47)

#define     PIN_IP                  (*(volatile __xdata unsigned char *)0x7efd60)
#define     PIN_IPH                 (*(volatile __xdata unsigned char *)0x7efd61)

#define     S2CFG                   (*(volatile __xdata unsigned char *)0x7efdb4)
#define     S2ADDR                  (*(volatile __xdata unsigned char *)0x7efdb5)
#define     S2ADEN                  (*(volatile __xdata unsigned char *)0x7efdb6)
#define     USARTCR1                (*(volatile __xdata unsigned char *)0x7efdc0)
#define     USARTCR2                (*(volatile __xdata unsigned char *)0x7efdc1)
#define     USARTCR3                (*(volatile __xdata unsigned char *)0x7efdc2)
#define     USARTCR4                (*(volatile __xdata unsigned char *)0x7efdc3)
#define     USARTCR5                (*(volatile __xdata unsigned char *)0x7efdc4)
#define     USARTGTR                (*(volatile __xdata unsigned char *)0x7efdc5)
#define     USARTBRH                (*(volatile __xdata unsigned char *)0x7efdc6)
#define     USARTBRL                (*(volatile __xdata unsigned char *)0x7efdc7)
#define     USART2CR1               (*(volatile __xdata unsigned char *)0x7efdc8)
#define     USART2CR2               (*(volatile __xdata unsigned char *)0x7efdc9)
#define     USART2CR3               (*(volatile __xdata unsigned char *)0x7efdca)
#define     USART2CR4               (*(volatile __xdata unsigned char *)0x7efdcb)
#define     USART2CR5               (*(volatile __xdata unsigned char *)0x7efdcc)
#define     USART2GTR               (*(volatile __xdata unsigned char *)0x7efdcd)
#define     USART2BRH               (*(volatile __xdata unsigned char *)0x7efdce)
#define     USART2BRL               (*(volatile __xdata unsigned char *)0x7efdcf)

#define     CHIPID                  ( (volatile __xdata unsigned char *)0x7efde0)

#define     CHIPID0                 (*(volatile __xdata unsigned char *)0x7efde0)
#define     CHIPID1                 (*(volatile __xdata unsigned char *)0x7efde1)
#define     CHIPID2                 (*(volatile __xdata unsigned char *)0x7efde2)
#define     CHIPID3                 (*(volatile __xdata unsigned char *)0x7efde3)
#define     CHIPID4                 (*(volatile __xdata unsigned char *)0x7efde4)
#define     CHIPID5                 (*(volatile __xdata unsigned char *)0x7efde5)
#define     CHIPID6                 (*(volatile __xdata unsigned char *)0x7efde6)
#define     CHIPID7                 (*(volatile __xdata unsigned char *)0x7efde7)
#define     CHIPID8                 (*(volatile __xdata unsigned char *)0x7efde8)
#define     CHIPID9                 (*(volatile __xdata unsigned char *)0x7efde9)
#define     CHIPID10                (*(volatile __xdata unsigned char *)0x7efdea)
#define     CHIPID11                (*(volatile __xdata unsigned char *)0x7efdeb)
#define     CHIPID12                (*(volatile __xdata unsigned char *)0x7efdec)
#define     CHIPID13                (*(volatile __xdata unsigned char *)0x7efded)
#define     CHIPID14                (*(volatile __xdata unsigned char *)0x7efdee)
#define     CHIPID15                (*(volatile __xdata unsigned char *)0x7efdef)
#define     CHIPID16                (*(volatile __xdata unsigned char *)0x7efdf0)
#define     CHIPID17                (*(volatile __xdata unsigned char *)0x7efdf1)
#define     CHIPID18                (*(volatile __xdata unsigned char *)0x7efdf2)
#define     CHIPID19                (*(volatile __xdata unsigned char *)0x7efdf3)
#define     CHIPID20                (*(volatile __xdata unsigned char *)0x7efdf4)
#define     CHIPID21                (*(volatile __xdata unsigned char *)0x7efdf5)
#define     CHIPID22                (*(volatile __xdata unsigned char *)0x7efdf6)
#define     CHIPID23                (*(volatile __xdata unsigned char *)0x7efdf7)
#define     CHIPID24                (*(volatile __xdata unsigned char *)0x7efdf8)
#define     CHIPID25                (*(volatile __xdata unsigned char *)0x7efdf9)
#define     CHIPID26                (*(volatile __xdata unsigned char *)0x7efdfa)
#define     CHIPID27                (*(volatile __xdata unsigned char *)0x7efdfb)
#define     CHIPID28                (*(volatile __xdata unsigned char *)0x7efdfc)
#define     CHIPID29                (*(volatile __xdata unsigned char *)0x7efdfd)
#define     CHIPID30                (*(volatile __xdata unsigned char *)0x7efdfe)
#define     CHIPID31                (*(volatile __xdata unsigned char *)0x7efdff)

/////////////////////////////////////////////////
//7E:FC00H-7E:FCFFH
/////////////////////////////////////////////////



/////////////////////////////////////////////////
//7E:FB00H-7E:FBFFH
/////////////////////////////////////////////////

#define     HSPWMA_CFG              (*(volatile __xdata unsigned char *)0x7efbf0)
#define     HSPWMA_ADR              (*(volatile __xdata unsigned char *)0x7efbf1)
#define     HSPWMA_DAT              (*(volatile __xdata unsigned char *)0x7efbf2)

#define     HSPWMB_CFG              (*(volatile __xdata unsigned char *)0x7efbf4)
#define     HSPWMB_ADR              (*(volatile __xdata unsigned char *)0x7efbf5)
#define     HSPWMB_DAT              (*(volatile __xdata unsigned char *)0x7efbf6)

#define     HSSPI_CFG               (*(volatile __xdata unsigned char *)0x7efbf8)
#define     HSSPI_CFG2              (*(volatile __xdata unsigned char *)0x7efbf9)
#define     HSSPI_STA               (*(volatile __xdata unsigned char *)0x7efbfa)

//ʹ������ĺ�,���Ƚ�EAXFR����Ϊ1
//ʹ�÷���:
//      char val;
//
//      EAXFR = 1;                      //ʹ�ܷ���XFR
//      READ_HSPWMA(PWMA_CR1, val);     //�첽��PWMA��Ĵ���
//      val |= 0x01;
//      WRITE_HSPWMA(PWMA_CR1, val);    //�첽дPWMA��Ĵ���

#define     READ_HSPWMA(reg, dat)           \
            {                               \
                while (HSPWMA_ADR & 0x80);  \
                HSPWMA_ADR = ((char)&(reg)) | 0x80;  \
                while (HSPWMA_ADR & 0x80);  \
                (dat) = HSPWMA_DAT;         \
            }

#define     WRITE_HSPWMA(reg, dat)          \
            {                               \
                while (HSPWMA_ADR & 0x80);  \
                HSPWMA_DAT = (dat);         \
                HSPWMA_ADR = ((char)&(reg)) & 0x7f;  \
            }

#define     READ_HSPWMB(reg, dat)           \
            {                               \
                while (HSPWMB_ADR & 0x80);  \
                HSPWMB_ADR = ((char)&(reg)) | 0x80;  \
                while (HSPWMB_ADR & 0x80);  \
                (dat) = HSPWMB_DAT;         \
            }

#define     WRITE_HSPWMB(reg, dat)          \
            {                               \
                while (HSPWMB_ADR & 0x80);  \
                HSPWMB_DAT = (dat);         \
                HSPWMB_ADR = ((char)&(reg)) & 0x7f;  \
            }

/////////////////////////////////////////////////
//7E:FA00H-7E:FAFFH
/////////////////////////////////////////////////

#define     DMA_M2M_CFG             (*(volatile __xdata unsigned char *)0x7efa00)
#define     DMA_M2M_CR              (*(volatile __xdata unsigned char *)0x7efa01)
#define     DMA_M2M_STA             (*(volatile __xdata unsigned char *)0x7efa02)
#define     DMA_M2M_AMT             (*(volatile __xdata unsigned char *)0x7efa03)
#define     DMA_M2M_DONE            (*(volatile __xdata unsigned char *)0x7efa04)
#define     DMA_M2M_TXAH            (*(volatile __xdata unsigned char *)0x7efa05)
#define     DMA_M2M_TXAL            (*(volatile __xdata unsigned char *)0x7efa06)
#define     DMA_M2M_RXAH            (*(volatile __xdata unsigned char *)0x7efa07)
#define     DMA_M2M_RXAL            (*(volatile __xdata unsigned char *)0x7efa08)

#define     DMA_ADC_CFG             (*(volatile __xdata unsigned char *)0x7efa10)
#define     DMA_ADC_CR              (*(volatile __xdata unsigned char *)0x7efa11)
#define     DMA_ADC_STA             (*(volatile __xdata unsigned char *)0x7efa12)
#define     DMA_ADC_RXAH            (*(volatile __xdata unsigned char *)0x7efa17)
#define     DMA_ADC_RXAL            (*(volatile __xdata unsigned char *)0x7efa18)
#define     DMA_ADC_CFG2            (*(volatile __xdata unsigned char *)0x7efa19)
#define     DMA_ADC_CHSW0           (*(volatile __xdata unsigned char *)0x7efa1a)
#define     DMA_ADC_CHSW1           (*(volatile __xdata unsigned char *)0x7efa1b)

#define     DMA_SPI_CFG             (*(volatile __xdata unsigned char *)0x7efa20)
#define     DMA_SPI_CR              (*(volatile __xdata unsigned char *)0x7efa21)
#define     DMA_SPI_STA             (*(volatile __xdata unsigned char *)0x7efa22)
#define     DMA_SPI_AMT             (*(volatile __xdata unsigned char *)0x7efa23)
#define     DMA_SPI_DONE            (*(volatile __xdata unsigned char *)0x7efa24)
#define     DMA_SPI_TXAH            (*(volatile __xdata unsigned char *)0x7efa25)
#define     DMA_SPI_TXAL            (*(volatile __xdata unsigned char *)0x7efa26)
#define     DMA_SPI_RXAH            (*(volatile __xdata unsigned char *)0x7efa27)
#define     DMA_SPI_RXAL            (*(volatile __xdata unsigned char *)0x7efa28)
#define     DMA_SPI_CFG2            (*(volatile __xdata unsigned char *)0x7efa29)

#define     DMA_UR1T_CFG            (*(volatile __xdata unsigned char *)0x7efa30)
#define     DMA_UR1T_CR             (*(volatile __xdata unsigned char *)0x7efa31)
#define     DMA_UR1T_STA            (*(volatile __xdata unsigned char *)0x7efa32)
#define     DMA_UR1T_AMT            (*(volatile __xdata unsigned char *)0x7efa33)
#define     DMA_UR1T_DONE           (*(volatile __xdata unsigned char *)0x7efa34)
#define     DMA_UR1T_TXAH           (*(volatile __xdata unsigned char *)0x7efa35)
#define     DMA_UR1T_TXAL           (*(volatile __xdata unsigned char *)0x7efa36)
#define     DMA_UR1R_CFG            (*(volatile __xdata unsigned char *)0x7efa38)
#define     DMA_UR1R_CR             (*(volatile __xdata unsigned char *)0x7efa39)
#define     DMA_UR1R_STA            (*(volatile __xdata unsigned char *)0x7efa3a)
#define     DMA_UR1R_AMT            (*(volatile __xdata unsigned char *)0x7efa3b)
#define     DMA_UR1R_DONE           (*(volatile __xdata unsigned char *)0x7efa3c)
#define     DMA_UR1R_RXAH           (*(volatile __xdata unsigned char *)0x7efa3d)
#define     DMA_UR1R_RXAL           (*(volatile __xdata unsigned char *)0x7efa3e)

#define     DMA_UR2T_CFG            (*(volatile __xdata unsigned char *)0x7efa40)
#define     DMA_UR2T_CR             (*(volatile __xdata unsigned char *)0x7efa41)
#define     DMA_UR2T_STA            (*(volatile __xdata unsigned char *)0x7efa42)
#define     DMA_UR2T_AMT            (*(volatile __xdata unsigned char *)0x7efa43)
#define     DMA_UR2T_DONE           (*(volatile __xdata unsigned char *)0x7efa44)
#define     DMA_UR2T_TXAH           (*(volatile __xdata unsigned char *)0x7efa45)
#define     DMA_UR2T_TXAL           (*(volatile __xdata unsigned char *)0x7efa46)
#define     DMA_UR2R_CFG            (*(volatile __xdata unsigned char *)0x7efa48)
#define     DMA_UR2R_CR             (*(volatile __xdata unsigned char *)0x7efa49)
#define     DMA_UR2R_STA            (*(volatile __xdata unsigned char *)0x7efa4a)
#define     DMA_UR2R_AMT            (*(volatile __xdata unsigned char *)0x7efa4b)
#define     DMA_UR2R_DONE           (*(volatile __xdata unsigned char *)0x7efa4c)
#define     DMA_UR2R_RXAH           (*(volatile __xdata unsigned char *)0x7efa4d)
#define     DMA_UR2R_RXAL           (*(volatile __xdata unsigned char *)0x7efa4e)

#define     DMA_UR3T_CFG            (*(volatile __xdata unsigned char *)0x7efa50)
#define     DMA_UR3T_CR             (*(volatile __xdata unsigned char *)0x7efa51)
#define     DMA_UR3T_STA            (*(volatile __xdata unsigned char *)0x7efa52)
#define     DMA_UR3T_AMT            (*(volatile __xdata unsigned char *)0x7efa53)
#define     DMA_UR3T_DONE           (*(volatile __xdata unsigned char *)0x7efa54)
#define     DMA_UR3T_TXAH           (*(volatile __xdata unsigned char *)0x7efa55)
#define     DMA_UR3T_TXAL           (*(volatile __xdata unsigned char *)0x7efa56)
#define     DMA_UR3R_CFG            (*(volatile __xdata unsigned char *)0x7efa58)
#define     DMA_UR3R_CR             (*(volatile __xdata unsigned char *)0x7efa59)
#define     DMA_UR3R_STA            (*(volatile __xdata unsigned char *)0x7efa5a)
#define     DMA_UR3R_AMT            (*(volatile __xdata unsigned char *)0x7efa5b)
#define     DMA_UR3R_DONE           (*(volatile __xdata unsigned char *)0x7efa5c)
#define     DMA_UR3R_RXAH           (*(volatile __xdata unsigned char *)0x7efa5d)
#define     DMA_UR3R_RXAL           (*(volatile __xdata unsigned char *)0x7efa5e)

#define     DMA_UR4T_CFG            (*(volatile __xdata unsigned char *)0x7efa60)
#define     DMA_UR4T_CR             (*(volatile __xdata unsigned char *)0x7efa61)
#define     DMA_UR4T_STA            (*(volatile __xdata unsigned char *)0x7efa62)
#define     DMA_UR4T_AMT            (*(volatile __xdata unsigned char *)0x7efa63)
#define     DMA_UR4T_DONE           (*(volatile __xdata unsigned char *)0x7efa64)
#define     DMA_UR4T_TXAH           (*(volatile __xdata unsigned char *)0x7efa65)
#define     DMA_UR4T_TXAL           (*(volatile __xdata unsigned char *)0x7efa66)
#define     DMA_UR4R_CFG            (*(volatile __xdata unsigned char *)0x7efa68)
#define     DMA_UR4R_CR             (*(volatile __xdata unsigned char *)0x7efa69)
#define     DMA_UR4R_STA            (*(volatile __xdata unsigned char *)0x7efa6a)
#define     DMA_UR4R_AMT            (*(volatile __xdata unsigned char *)0x7efa6b)
#define     DMA_UR4R_DONE           (*(volatile __xdata unsigned char *)0x7efa6c)
#define     DMA_UR4R_RXAH           (*(volatile __xdata unsigned char *)0x7efa6d)
#define     DMA_UR4R_RXAL           (*(volatile __xdata unsigned char *)0x7efa6e)

#define     DMA_LCM_CFG             (*(volatile __xdata unsigned char *)0x7efa70)
#define     DMA_LCM_CR              (*(volatile __xdata unsigned char *)0x7efa71)
#define     DMA_LCM_STA             (*(volatile __xdata unsigned char *)0x7efa72)
#define     DMA_LCM_AMT             (*(volatile __xdata unsigned char *)0x7efa73)
#define     DMA_LCM_DONE            (*(volatile __xdata unsigned char *)0x7efa74)
#define     DMA_LCM_TXAH            (*(volatile __xdata unsigned char *)0x7efa75)
#define     DMA_LCM_TXAL            (*(volatile __xdata unsigned char *)0x7efa76)
#define     DMA_LCM_RXAH            (*(volatile __xdata unsigned char *)0x7efa77)
#define     DMA_LCM_RXAL            (*(volatile __xdata unsigned char *)0x7efa78)

#define     DMA_M2M_AMTH            (*(volatile __xdata unsigned char *)0x7efa80)
#define     DMA_M2M_DONEH           (*(volatile __xdata unsigned char *)0x7efa81)
#define     DMA_SPI_AMTH            (*(volatile __xdata unsigned char *)0x7efa84)
#define     DMA_SPI_DONEH           (*(volatile __xdata unsigned char *)0x7efa85)
#define     DMA_LCM_AMTH            (*(volatile __xdata unsigned char *)0x7efa86)
#define     DMA_LCM_DONEH           (*(volatile __xdata unsigned char *)0x7efa87)
#define     DMA_UR1T_AMTH           (*(volatile __xdata unsigned char *)0x7efa88)
#define     DMA_UR1T_DONEH          (*(volatile __xdata unsigned char *)0x7efa89)
#define     DMA_UR1R_AMTH           (*(volatile __xdata unsigned char *)0x7efa8a)
#define     DMA_UR1R_DONEH          (*(volatile __xdata unsigned char *)0x7efa8b)
#define     DMA_UR2T_AMTH           (*(volatile __xdata unsigned char *)0x7efa8c)
#define     DMA_UR2T_DONEH          (*(volatile __xdata unsigned char *)0x7efa8d)
#define     DMA_UR2R_AMTH           (*(volatile __xdata unsigned char *)0x7efa8e)
#define     DMA_UR2R_DONEH          (*(volatile __xdata unsigned char *)0x7efa8f)
#define     DMA_UR3T_AMTH           (*(volatile __xdata unsigned char *)0x7efa90)
#define     DMA_UR3T_DONEH          (*(volatile __xdata unsigned char *)0x7efa91)
#define     DMA_UR3R_AMTH           (*(volatile __xdata unsigned char *)0x7efa92)
#define     DMA_UR3R_DONEH          (*(volatile __xdata unsigned char *)0x7efa93)
#define     DMA_UR4T_AMTH           (*(volatile __xdata unsigned char *)0x7efa94)
#define     DMA_UR4T_DONEH          (*(volatile __xdata unsigned char *)0x7efa95)
#define     DMA_UR4R_AMTH           (*(volatile __xdata unsigned char *)0x7efa96)
#define     DMA_UR4R_DONEH          (*(volatile __xdata unsigned char *)0x7efa97)

#define     DMA_I2CT_CFG            (*(volatile __xdata unsigned char *)0x7efa98)
#define     DMA_I2CT_CR             (*(volatile __xdata unsigned char *)0x7efa99)
#define     DMA_I2CT_STA            (*(volatile __xdata unsigned char *)0x7efa9a)
#define     DMA_I2CT_AMT            (*(volatile __xdata unsigned char *)0x7efa9b)
#define     DMA_I2CT_DONE           (*(volatile __xdata unsigned char *)0x7efa9c)
#define     DMA_I2CT_TXAH           (*(volatile __xdata unsigned char *)0x7efa9d)
#define     DMA_I2CT_TXAL           (*(volatile __xdata unsigned char *)0x7efa9e)
#define     DMA_I2CR_CFG            (*(volatile __xdata unsigned char *)0x7efaa0)
#define     DMA_I2CR_CR             (*(volatile __xdata unsigned char *)0x7efaa1)
#define     DMA_I2CR_STA            (*(volatile __xdata unsigned char *)0x7efaa2)
#define     DMA_I2CR_AMT            (*(volatile __xdata unsigned char *)0x7efaa3)
#define     DMA_I2CR_DONE           (*(volatile __xdata unsigned char *)0x7efaa4)
#define     DMA_I2CR_RXAH           (*(volatile __xdata unsigned char *)0x7efaa5)
#define     DMA_I2CR_RXAL           (*(volatile __xdata unsigned char *)0x7efaa6)

#define     DMA_I2CT_AMTH           (*(volatile __xdata unsigned char *)0x7efaa8)
#define     DMA_I2CT_DONEH          (*(volatile __xdata unsigned char *)0x7efaa9)
#define     DMA_I2CR_AMTH           (*(volatile __xdata unsigned char *)0x7efaaa)
#define     DMA_I2CR_DONEH          (*(volatile __xdata unsigned char *)0x7efaab)

#define     DMA_I2C_CR              (*(volatile __xdata unsigned char *)0x7efaad)
#define     DMA_I2C_ST1             (*(volatile __xdata unsigned char *)0x7efaae)
#define     DMA_I2C_ST2             (*(volatile __xdata unsigned char *)0x7efaaf)


/////////////////////////////////////////////////

// Optional CAN control register compatibility is provided by the extended-register helpers.
//#define   CANAR                   (*(volatile __xdata unsigned char *)0x7efebb)
//#define   CANDR                   (*(volatile __xdata unsigned char *)0x7efebc)

//ʹ������ĺ�,���Ƚ�EAXFR����Ϊ1
//ʹ�÷���:
//      char dat;
//
//      EAXFR = 1;                  //ʹ�ܷ���XFR
//      dat = READ_CAN(RX_BUF0);    //��CAN�Ĵ���
//      WRITE_CAN(TX_BUF0, 0x55);   //дCAN�Ĵ���

#define     READ_CAN(reg)           (CANAR = (reg), CANDR)
#define     WRITE_CAN(reg, dat)     (CANAR = (reg), CANDR = (dat))

#define     MR                      0x00 
#define     CMR                     0x01 
#define     SR                      0x02 
#define     ISR                     0x03 
#define     IMR                     0x04 
#define     RMC                     0x05 
#define     BTR0                    0x06 
#define     BTR1                    0x07 
#define     TM0                     0x06 
#define     TM1                     0x07 
#define     TX_BUF0                 0x08 
#define     TX_BUF1                 0x09 
#define     TX_BUF2                 0x0a 
#define     TX_BUF3                 0x0b 
#define     RX_BUF0                 0x0c 
#define     RX_BUF1                 0x0d 
#define     RX_BUF2                 0x0e 
#define     RX_BUF3                 0x0f 
#define     ACR0                    0x10 
#define     ACR1                    0x11 
#define     ACR2                    0x12 
#define     ACR3                    0x13 
#define     AMR0                    0x14 
#define     AMR1                    0x15 
#define     AMR2                    0x16 
#define     AMR3                    0x17 
#define     ECC                     0x18 
#define     RXERR                   0x19 
#define     TXERR                   0x1a 
#define     ALC                     0x1b 

/////////////////////////////////////////////////
//LIN Control Regiter
/////////////////////////////////////////////////

// Optional LIN control registers are provided by the extended-register helpers.

//ʹ�÷���:
//      char dat;
//
//      dat = READ_LIN(LBUF);       //��CAN�Ĵ���
//      WRITE_LIN(LBUF, 0x55);      //дCAN�Ĵ���

#define     READ_LIN(reg)           (LINAR = (reg), LINDR)
#define     WRITE_LIN(reg, dat)     (LINAR = (reg), LINDR = (dat))

#define     LBUF                    0x00 
#define     LSEL                    0x01 
#define     LID                     0x02 
#define     LER                     0x03 
#define     LIE                     0x04 
#define     LSR                     0x05 
#define     LCR                     0x05 
#define     DLL                     0x06 
#define     DLH                     0x07 
#define     HDRL                    0x08 
#define     HDRH                    0x09 
#define     HDP                     0x0A 

/////////////////////////////////////////////////
//USB Control Regiter
/////////////////////////////////////////////////

// Optional USB control registers are provided by the extended-register helpers.

//ʹ�÷���:
//      char dat;
//
//      READ_USB(CSR0, dat);        //��USB�Ĵ���
//      WRITE_USB(FADDR, 0x00);     //дUSB�Ĵ���

#define     READ_USB(reg, dat)          \
            {                           \
                while (USBADR & 0x80);  \
                USBADR = (reg) | 0x80;  \
                while (USBADR & 0x80);  \
                (dat) = USBDAT;         \
            }

#define     WRITE_USB(reg, dat)         \
            {                           \
                while (USBADR & 0x80);  \
                USBADR = (reg) & 0x7f;  \
                USBDAT = (dat);         \
            }

#define     FADDR                   0x00
#define     POWER                   0x01
#define     INTRIN1                 0x02
#define     INTROUT1                0x04
#define     INTRUSB                 0x06
#define     INTRIN1E                0x07
#define     INTROUT1E               0x09
#define     INTRUSBE                0x0b
#define     FRAME1                  0x0c
#define     FRAME2                  0x0d
#define     INDEX                   0x0e
#define     INMAXP                  0x10
#define     CSR0                    0x11
#define     INCSR1                  0x11
#define     INCSR2                  0x12
#define     OUTMAXP                 0x13
#define     OUTCSR1                 0x14
#define     OUTCSR2                 0x15
#define     COUNT0                  0x16
#define     OUTCOUNT1               0x16
#define     OUTCOUNT2               0x17
#define     FIFO0                   0x20
#define     FIFO1                   0x21
#define     FIFO2                   0x22
#define     FIFO3                   0x23
#define     FIFO4                   0x24
#define     FIFO5                   0x25
#define     UTRKCTL                 0x30
#define     UTRKSTS                 0x31

/////////////////////////////////////////////////

#define     INT0_VECTOR             0       //0003H
#define     TMR0_VECTOR             1       //000BH
#define     INT1_VECTOR             2       //0013H
#define     TMR1_VECTOR             3       //001BH
#define     UART1_VECTOR            4       //0023H
#define     ADC_VECTOR              5       //002BH
#define     LVD_VECTOR              6       //0033H
#define     PCA_VECTOR              7       //003BH
#define     UART2_VECTOR            8       //0043H
#define     SPI_VECTOR              9       //004BH
#define     INT2_VECTOR             10      //0053H
#define     INT3_VECTOR             11      //005BH
#define     TMR2_VECTOR             12      //0063H
#define     USER_VECTOR             13      //006BH
#define     INT4_VECTOR             16      //0083H
#define     UART3_VECTOR            17      //008BH
#define     UART4_VECTOR            18      //0093H
#define     TMR3_VECTOR             19      //009BH
#define     TMR4_VECTOR             20      //00A3H
#define     CMP_VECTOR              21      //00ABH
#define     I2C_VECTOR              24      //00C3H
#define     USB_VECTOR              25      //00CBH
#define     PWMA_VECTOR             26      //00D3H
#define     PWMB_VECTOR             27      //00DBH
#define     CAN_VECTOR              28      //00E3H
#define     CAN2_VECTOR             29      //00EBH
#define     LIN_VECTOR              30      //00F3H
#define     RTC_VECTOR              36      //0123H
#define     P0INT_VECTOR            37      //012BH
#define     P1INT_VECTOR            38      //0133H
#define     P2INT_VECTOR            39      //013BH
#define     P3INT_VECTOR            40      //0143H
#define     P4INT_VECTOR            41      //014BH
#define     P5INT_VECTOR            42      //0153H
#define     P6INT_VECTOR            43      //015BH
#define     P7INT_VECTOR            44      //0163H
#define     M2MDMA_VECTOR           47      //017BH
#define     ADCDMA_VECTOR           48      //0183H
#define     SPIDMA_VECTOR           49      //018BH
#define     U1TXDMA_VECTOR          50      //0193H
#define     U1RXDMA_VECTOR          51      //019BH
#define     U2TXDMA_VECTOR          52      //01A3H
#define     U2RXDMA_VECTOR          53      //01ABH
#define     U3TXDMA_VECTOR          54      //01B3H
#define     U3RXDMA_VECTOR          55      //01BBH
#define     U4TXDMA_VECTOR          56      //01C3H
#define     U4RXDMA_VECTOR          57      //01CBH
#define     LCMDMA_VECTOR           58      //01D3H
#define     LCM_VECTOR              59      //01DBH
#define     I2CTXDMA_VECTOR         60      //01E3H
#define     I2CRXDMA_VECTOR         61      //01EBH
#define     I2S_VECTOR              62      //01F3H
#define     I2STXDMA_VECTOR         63      //01FBH
#define     I2SRXDMA_VECTOR         64      //0203H

/////////////////////////////////////////////////


#define T22M_ADDR CHIPID11 //22.1184MHz
#define T24M_ADDR CHIPID12 //24MHz
#define T27M_ADDR CHIPID13 //27MHz
#define T30M_ADDR CHIPID14 //30MHz
#define T33M_ADDR CHIPID15 //33.1776MHz
#define T35M_ADDR CHIPID16 //35MHz
#define T36M_ADDR CHIPID17 //36.864MHz
#define T40M_ADDR CHIPID18 //40MHz
#define T44M_ADDR CHIPID19 //44.2368MHz
#define T48M_ADDR CHIPID20 //48MHz
#define VRT6M_ADDR CHIPID21 //VRTRIM_6M
#define VRT10M_ADDR CHIPID22 //VRTRIM_10M
#define VRT27M_ADDR CHIPID23 //VRTRIM_27M
#define VRT44M_ADDR CHIPID24 //VRTRIM_44M

#define ENABLE       1
#define DISABLE      0
#endif



#endif

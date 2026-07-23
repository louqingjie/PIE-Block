/*--------------------------------------------------------------------------
REG251A1.H

Header file for 8xC251A1
Copyright (c) 1988-2002 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#ifndef __REG251A1_H__
#define __REG251A1_H__

/*  BYTE Registers  */
sfr P0   = 0x80;
sfr P1   = 0x90;
sfr P2   = 0xA0;
sfr P3   = 0xB0;
sfr PSW  = 0xD0;
sfr PSW1 = 0xD1;
sfr ACC  = 0xE0;
sfr B    = 0xF0;
sfr SP   = 0x81;
sfr SPH  = 0xBE;
sfr DPL  = 0x82;
sfr DPH  = 0x83;
sfr DPXL = 0x84;
sfr PCON = 0x87;
sfr TCON = 0x88;
sfr TMOD = 0x89;
sfr TL0  = 0x8A;
sfr TL1  = 0x8B;
sfr TH0  = 0x8C;
sfr TH1  = 0x8D;
sfr IE0  = 0xA8;
sfr IPL0 = 0xB8;
sfr IPH0 = 0xB7;
sfr IE1  = 0xB1;
sfr IPL1 = 0xB2;
sfr IPH1 = 0xB3;
sfr SCON = 0x98;
sfr SBUF = 0x99;
sfr WDTRST = 0xA7;
sfr SADDR  = 0xA9;
sfr SADEN  = 0xB9;
sfr CCON   = 0xD8;
sfr CMOD   = 0xD9;
sfr CCAPM0 = 0xDA;
sfr CCAPM1 = 0xDB;
sfr CCAPM2 = 0xDC;
sfr CCAPM3 = 0xDD;
sfr CCAPM4 = 0xDE;
sfr CL0    = 0xE9;
sfr CCAP0L = 0xEA;
sfr CCAP1L = 0xEB;
sfr CCAP2L = 0xEC;
sfr CCAP3L = 0xED;
sfr CCAP4L = 0xEE;
sfr CH0    = 0xF9;
sfr CCAP0H = 0xFA;
sfr CCAP1H = 0xFB;
sfr CCAP2H = 0xFC;
sfr CCAP3H = 0xFD;
sfr CCAP4H = 0xFE;

sfr PFILT  = 0x86;
sfr CKRL   = 0x8E;
sfr POWM   = 0x8F;
sfr TBAM   = 0x97;
sfr BRL    = 0x9A;
sfr BDRCON = 0x9B;
sfr PMPER0 = 0xA2;
sfr PMWID0 = 0xA3;
sfr PMPER1 = 0xA4;
sfr PMWID1 = 0xA5;
sfr PMPER2 = 0xA6;
sfr PMWID2 = 0xA7;
sfr PMSCAL0 = 0xAA;
sfr PMSCAL1 = 0xAB;
sfr PMSCAL2 = 0xAC;
sfr PMCON  = 0xAD;
sfr PMSTAT = 0xAE;

sfr ADCON  = 0xC5;
sfr ADAT   = 0xC6;
sfr CMOD1  = 0xDF;
sfr COF	   = 0xE1;
sfr CRC	   = 0xE2;
sfr ECOF   = 0xE3;
sfr CL1	   = 0xE4;
sfr CL2	   = 0xE5;
sfr CL3	   = 0xE6;
sfr CL4	   = 0xE7;
sfr CMOD2  = 0xEF;
sfr CH1	   = 0xF4;
sfr CH2	   = 0xF5;
sfr CH3	   = 0xF6;
sfr CH4	   = 0xF7;
sfr CMOD3  = 0xFF;

/*  BIT Registers  */
/*  PSW   */
sbit CY   = 0xD7;
sbit AC   = 0xD6;
sbit F0   = 0xD5;
sbit RS1  = 0xD4;
sbit RS0  = 0xD3;
sbit OV   = 0xD2;
sbit UD   = 0xD1;
sbit P    = 0xD0;

/*  TCON  */
sbit TF1  = 0x8F;
sbit TR1  = 0x8E;
sbit TF0  = 0x8D;
sbit TR0  = 0x8C;
sbit IE1_ = 0x8B;
sbit IT1  = 0x8A;
sbit IE0_ = 0x89;
sbit IT0  = 0x88;

/*  IE0   */
sbit EA   = 0xAF;
sbit EC   = 0xAE;
sbit EADC = 0xAD;
sbit ES   = 0xAC;
sbit ET1  = 0xAB;
sbit EX1  = 0xAA;
sbit ET0  = 0xA9;
sbit EX0  = 0xA8;

/*  IPL0  */ 
sbit IPHC   = 0xBE;
sbit IPHADC = 0xBD;
sbit IPHS   = 0xBC;
sbit IPHT1  = 0xBB;
sbit IPHX1  = 0xBA;
sbit IPT0   = 0xB9;
sbit IPHX0  = 0xB8;

/*  P3  */
sbit RD   = 0xB7;
sbit WR   = 0xB6;
sbit T1   = 0xB5;
sbit T0   = 0xB4;
sbit INT1 = 0xB3;
sbit INT0 = 0xB2;
sbit TXD  = 0xB1;
sbit RXD  = 0xB0;

/*  SCON  */
sbit FE   = 0x9F;
sbit SM0  = 0x9F;
sbit SM1  = 0x9E;
sbit SM2  = 0x9D;
sbit REN  = 0x9C;
sbit TB8  = 0x9B;
sbit RB8  = 0x9A;
sbit TI   = 0x99;
sbit RI   = 0x98;

/*  P1  */
sbit CEX4 = 0x97;
sbit CEX3 = 0x96;
sbit CEX2 = 0x95;
sbit CEX1 = 0x94;
sbit CEX0 = 0x93;
sbit ECI  = 0x92;

/*  CCON  */
sbit CF    = 0xDF;
sbit CR    = 0xDE;
sbit CCF4  = 0xDC;
sbit CCF3  = 0xDB;
sbit CCF2  = 0xDA;
sbit CCF1  = 0xD9;
sbit CCF0  = 0xD8;

#endif

/*--------------------------------------------------------------------------
REG251G1.H

Header file for 8xC251G1
Copyright (c) 1988-2002 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#ifndef __REG251G1_H__
#define __REG251G1_H__

//  Registers
sfr P0     = 0x80;
sfr P1     = 0x90;
sfr P2     = 0xA0;
sfr P3     = 0xB0;
sfr PSW    = 0xD0;
sfr PSW1   = 0xD1;
sfr ACC    = 0xE0;
sfr B      = 0xF0;
sfr SP     = 0x81;
sfr SPH    = 0xBE;
sfr DPL    = 0x82;
sfr DPH    = 0x83;
sfr DPXL   = 0x84;
sfr PFILT  = 0x86;
sfr PCON   = 0x87;

sfr TCON   = 0x88;
sfr TMOD   = 0x89;
sfr TL0    = 0x8A;
sfr TL1    = 0x8B;
sfr TH0    = 0x8C;
sfr TH1    = 0x8D;
sfr CKRL   = 0x8E;
sfr POWM   = 0x8F;

sfr SSBR   = 0x92;
sfr SSCON  = 0x93;
sfr SSCS   = 0x94;
sfr SSDAT  = 0x95;
sfr SSADR  = 0x96;

sfr SCON   = 0x98;
sfr SBUF   = 0x99;
sfr BRL    = 0x9A;
sfr BDRCON = 0x9B;
sfr P1LS   = 0x9C;
sfr P1IE   = 0x9D;
sfr P1F    = 0x9E;

sfr WDTRST = 0xA6;
sfr WCON   = 0xA7;

sfr IE0    = 0xA8;
sfr SADDR  = 0xA9;

sfr IE1    = 0xB1;
sfr IPL1   = 0xB2;
sfr IPH1   = 0xB3;
sfr IPH0   = 0xB7;

sfr IPL0   = 0xB8;
sfr SADEN  = 0xB9;

sfr T2CON  = 0xC8;
sfr T2MOD  = 0xC9;
sfr RCAP2L = 0xCA;
sfr RCAP2H = 0xCB;
sfr TL2    = 0xCC;
sfr TH2    = 0xCD;

sfr CCON   = 0xD8;
sfr CMOD   = 0xD9;
sfr CCAPM0 = 0xDA;
sfr CCAPM1 = 0xDB;
sfr CCAPM2 = 0xDC;
sfr CCAPM3 = 0xDD;
sfr CCAPM4 = 0xDE;

sfr CL     = 0xE9;
sfr CCAP0L = 0xEA;
sfr CCAP1L = 0xEB;
sfr CCAP2L = 0xEC;
sfr CCAP3L = 0xED;
sfr CCAP4L = 0xEE;

sfr CH     = 0xF9;
sfr CCAP0H = 0xFA;
sfr CCAP1H = 0xFB;
sfr CCAP2H = 0xFC;
sfr CCAP3H = 0xFD;
sfr CCAP4H = 0xFE;

//  BIT Registers

/*  BDRCON  Baud Rate Control Register */
sbit SRC  = BDRCON ^ 0;
sbit SPD  = BDRCON ^ 1;
sbit RBCK = BDRCON ^ 2;
sbit TBCK = BDRCON ^ 3;
sbit BRR  = BDRCON ^ 4;

/*  CCON    Timer/Counter Control Register */
sbit CF   = CCON ^ 7;
sbit CR   = CCON ^ 6;
sbit CCF4 = CCON ^ 4;
sbit CCF3 = CCON ^ 3;
sbit CCF2 = CCON ^ 2;
sbit CCF1 = CCON ^ 1;
sbit CCF0 = CCON ^ 0;

/*  CMOD    Timer/Counter Mode Register*/
sbit EFC  = CMOD ^ 0;
sbit CPS0 = CMOD ^ 1;
sbit CPS1 = CMOD ^ 2;
sbit WDTE = CMOD ^ 6;
sbit CIDL = CMOD ^ 7;

/*  IE0     Interrupt Enable Register 0 */
sbit EA   = IE0 ^ 7;
sbit EC   = IE0 ^ 6;
sbit ET2  = IE0 ^ 5;
sbit ES   = IE0 ^ 4;
sbit ET1  = IE0 ^ 3;
sbit EX1  = IE0 ^ 2;
sbit ET0  = IE0 ^ 1;
sbit EX0  = IE0 ^ 0;

/*  IE1     Interrupt Enable Register 1 */
sbit SSIE = IE1 ^ 5;

/*  IPH0     Interrupt Priority High Register 0 */ 
sbit IPHC  = IPH0 ^ 6;
sbit IPHT2 = IPH0 ^ 5;
sbit IPHS  = IPH0 ^ 4;
sbit IPHT1 = IPH0 ^ 3;
sbit IPHX1 = IPH0 ^ 2;
sbit IPHT0 = IPH0 ^ 1;
sbit IPHX0 = IPH0 ^ 0;

/*  IPH1     Interrupt Priority High Register 1 */
sbit IPHSS = IPH1 ^ 5;

/*  IPL0     Interrupt Priority Low Register 0 */ 
sbit IPLC  = IPL0 ^ 6;
sbit IPLT2 = IPL0 ^ 5;
sbit IPLS  = IPL0 ^ 4;
sbit IPLT1 = IPL0 ^ 3;
sbit IPLX1 = IPL0 ^ 2;
sbit IPLT0 = IPL0 ^ 1;
sbit IPLX0 = IPL0 ^ 0;

/*  IPL1     Interrupt Priority Low Register 1 */
sbit IPLSS = IPL1 ^ 5;

/*  PCON     Power Configuration Register */
sbit IDL   = PCON ^ 0;
sbit PD    = PCON ^ 1;
sbit GF0   = PCON ^ 2;
sbit GF1   = PCON ^ 3;
sbit POF   = PCON ^ 4;
sbit RPD   = PCON ^ 5;
sbit SMOD0 = PCON ^ 6;
sbit SMOD1 = PCON ^ 7;

/*  POWM     Power Management Register   */
sbit RSTD  = POWM ^ 3;
sbit CKSRC = POWM ^ 7;

/*  PSW     Program Status Word Register */
sbit CY   = PSW ^ 7;  //0xD7;
sbit AC   = PSW ^ 6;  //0xD6;
sbit F0   = PSW ^ 5;  //0xD5;
sbit RS1  = PSW ^ 4;  //0xD4;
sbit RS0  = PSW ^ 3;  //0xD3;
sbit OV   = PSW ^ 2;  //0xD2;
sbit UD   = PSW ^ 1;  //0xD1;
sbit P    = PSW ^ 0;  //0xD0;

/*  PSW1    Program Status Word 1 Register */
sbit N    = PSW1 ^ 5;  // Negative flag
sbit Z    = PSW1 ^ 1;  // Zero flag

/*  SCON    Serial Control Register */
sbit FE   = SCON ^ 7;  //0x9F;
sbit SM0  = SCON ^ 7;  //0x9F;
sbit SM1  = SCON ^ 6;  //0x9E;
sbit OVR  = SCON ^ 6;  //0x9E;
sbit SM2  = SCON ^ 5;  //0x9D;
sbit REN  = SCON ^ 4;  //0x9C;
sbit TB8  = SCON ^ 3;  //0x9B;
sbit RB8  = SCON ^ 2;  //0x9A;
sbit TI   = SCON ^ 1;  //0x99;
sbit RI   = SCON ^ 0;  //0x98;

/*  SSADR   Synchronous Serial Address Register */
sbit SSGC = SSADR ^ 0;

/*  SSCON    Synchronous Serial Control Register */
sbit SSCR2 = SSCON ^ 7;
sbit SSPE  = SSCON ^ 6;
sbit SSSTA = SSCON ^ 5;
sbit SSSTO = SSCON ^ 4;
sbit SSI   = SSCON ^ 3;
sbit SSAA  = SSCON ^ 2;
sbit SSCR1 = SSCON ^ 1;
sbit SSCR0 = SSCON ^ 0;

/*  SSCS     Synchronous Serial Control and Status */
sbit SSBRS = SSCS ^ 7;
sbit SSMOD = SSCS ^ 0;

/*  SSDAT    Synchronous Serial Data Register */
sbit SSRD  = SSDAT ^ 0; 

/*  TCON     Timer/Counter Control Register */
sbit TF1   = TCON ^ 7;
sbit TR1   = TCON ^ 6;
sbit TF0   = TCON ^ 5;
sbit TR0   = TCON ^ 4;
sbit IE1_  = TCON ^ 3;
sbit IT1   = TCON ^ 2;
sbit IE0_  = TCON ^ 1;
sbit IT0   = TCON ^ 0;

/*  T2CON    Timer/Counter 2 Control Register */
sbit TF2   = T2CON ^ 7;
sbit EXF2  = T2CON ^ 6;
sbit RCLK  = T2CON ^ 5;
sbit TCLK  = T2CON ^ 4;
sbit EXEN2 = T2CON ^ 3;
sbit TR2   = T2CON ^ 2;
sbit CT2_  = T2CON ^ 1;
sbit CPRL2 = T2CON ^ 0;

/*  TMOD     Timer/Counter Mode Control Register */
sbit M00   = TMOD ^ 0;
sbit M10   = TMOD ^ 1;
sbit CT0_  = TMOD ^ 2;
sbit GATE0 = TMOD ^ 3;
sbit M01   = TMOD ^ 4;
sbit M11   = TMOD ^ 5;
sbit CT1_  = TMOD ^ 6;
sbit GATE1 = TMOD ^ 7;

/*  T2MOD    Timer/Counter 2 Mode Control Register */
sbit DCEN  = T2MOD ^ 0;
sbit T2OE  = T2MOD ^ 1;

/*  WCON     Real-Time Synchronous Wait State Ctrl */
sbit RTWE  = WCON ^ 0;
sbit RTWCE = WCON ^ 1;

/*  P1  */
sbit CEX4 = 0x97;
sbit CEX3 = 0x96;
sbit CEX2 = 0x95;
sbit CEX1 = 0x94;
sbit CEX0 = 0x93;
sbit ECI  = 0x92;

/*  P3  */
sbit RD   = 0xB7;
sbit WR   = 0xB6;
sbit T1   = 0xB5;
sbit T0   = 0xB4;
sbit INT1 = 0xB3;
sbit INT0 = 0xB2;
sbit TXD  = 0xB1;
sbit RXD  = 0xB0;

#endif

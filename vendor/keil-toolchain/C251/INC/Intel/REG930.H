/*--------------------------------------------------------------------------
REG930.H

Header file for 8xC930Ax and 8xC930Hx
Copyright (c) 1988-2002 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#ifndef __REG930_H__
#define __REG930_H__

/*------------------------------------------------
Byte Registers
------------------------------------------------*/
sfr P0      = 0x80;
sfr SP      = 0x81;
sfr DPL     = 0x82;
sfr DPH     = 0x83;
sfr DPXL    = 0x84;
sfr DPXH    = 0x85;
sfr PCON    = 0x87;
sfr TCON    = 0x88;
sfr TMOD    = 0x89;
sfr TL0     = 0x8A;
sfr TL1     = 0x8B;
sfr TH0     = 0x8C;
sfr TH1     = 0x8D;
sfr FADDR   = 0x8F;

sfr P1      = 0x90;
sfr HADDR   = 0x97;  /* 930Hx only */
sfr SCON    = 0x98;
sfr SBUF    = 0x99;
sfr HPPWR   = 0x9A;  /* 930Hx only */

sfr P2      = 0xA0;
sfr FIE     = 0xA2;
sfr FIE1    = 0xA3;
sfr WDTRST  = 0xA6;
sfr WCON    = 0xA7;
sfr IE0     = 0xA8;  /* Renamed SFR identical to IEN0 */
sfr IEN0    = 0xA8;
sfr SADDR   = 0xA9;
sfr HSTAT   = 0xAE;  /* 930Hx only */

sfr P3      = 0xB0;
sfr IE1     = 0xB1;  /* Renamed SFR identical to IEN1 */
sfr IEN1    = 0xB1;
sfr IPL1    = 0xB2;
sfr IPH1    = 0xB3;
sfr IPH0    = 0xB7;
sfr IPL0    = 0xB8;
sfr SADEN   = 0xB9;
sfr SPH     = 0xBD;

sfr FIFLG   = 0xC0;
sfr FIFLG1  = 0xC1;
sfr EPCONFIG= 0xC7;
sfr T2CON   = 0xC8;
sfr T2MOD   = 0xC9;
sfr RCAP2L  = 0xCA;
sfr RCAP2H  = 0xCB;
sfr TL2     = 0xCC;
sfr TH2     = 0xCD;
sfr HPCON   = 0xCF;  /* 930Hx only */

sfr PSW     = 0xD0;
sfr PSW1    = 0xD1;
sfr SOFL    = 0xD2;
sfr SOFH    = 0xD3;
sfr HPINDEX = 0xD4;  /* 930Hx only */
sfr HPSC    = 0xD5;  /* 930Hx only */
sfr HPSTAT  = 0xD7;  /* 930Hx only */
sfr CCON    = 0xD8;
sfr CMOD    = 0xD9;
sfr CCAPM0  = 0xDA;
sfr CCAPM1  = 0xDB;
sfr CCAPM2  = 0xDC;
sfr CCAPM3  = 0xDD;
sfr CCAPM4  = 0xDE;
sfr PCON1   = 0xDF;

sfr ACC     = 0xE0;
sfr EPCON   = 0xE1;
sfr RXSTAT  = 0xE2;
sfr RXDAT   = 0xE3;
sfr RXCON   = 0xE4;
sfr RXFLG   = 0xE5;
sfr RXCNTL  = 0xE6;
sfr RXCNTH  = 0xE7;
sfr HIFLG   = 0xE8;  /* 930Hx only */
sfr CL      = 0xE9;
sfr CCAP0L  = 0xEA;
sfr CCAP1L  = 0xEB;
sfr CCAP2L  = 0xEC;
sfr CCAP3L  = 0xED;
sfr CCAP4L  = 0xEE;

sfr B       = 0xF0;
sfr EPINDEX = 0xF1;
sfr TXSTAT  = 0xF2;
sfr TXDAT   = 0xF3;
sfr TXCON   = 0xF4;
sfr TXFLG   = 0xF5;
sfr TXCNTL  = 0xF6;
sfr TXCNTH  = 0xF7;
sfr CH      = 0xF9;
sfr CCAP0H  = 0xFA;
sfr CCAP1H  = 0xFB;
sfr CCAP2H  = 0xFC;
sfr CCAP3H  = 0xFD;
sfr CCAP4H  = 0xFE;
sfr HTXDAT  = 0xF4;  /* 930Hx only */
sfr HTXCNTL = 0xF6;  /* 930Hx only */

/*------------------------------------------------
P0 Bit Registers
------------------------------------------------*/
sbit P0_0 = 0x80;
sbit P0_1 = 0x81;
sbit P0_2 = 0x82;
sbit P0_3 = 0x83;
sbit P0_4 = 0x84;
sbit P0_5 = 0x85;
sbit P0_6 = 0x86;
sbit P0_7 = 0x87;

/*------------------------------------------------
PCON Bit Values
------------------------------------------------*/
#define IDL_    0x01
#define PD_     0x02
#define GF0_    0x04
#define GF1_    0x08
#define POF_    0x10

#define SMOD0_  0x40
#define SMOD1_  0x80

/*------------------------------------------------
TCON Bit Registers
------------------------------------------------*/
sbit IT0  = 0x88;
sbit IE0_ = 0x89;
sbit IT1  = 0x8A;
sbit IE1_ = 0x8B;
sbit TR0  = 0x8C;
sbit TF0  = 0x8D;
sbit TR1  = 0x8E;
sbit TF1  = 0x8F;

/*------------------------------------------------
TMOD Bit Values
------------------------------------------------*/
#define T0_M0_   0x01
#define T0_M1_   0x02
#define T0_CT_   0x04
#define T0_GATE_ 0x08
#define T1_M0_   0x10
#define T1_M1_   0x20
#define T1_CT_   0x40
#define T1_GATE_ 0x80

#define T1_MASK_ 0xF0
#define T0_MASK_ 0x0F

/*------------------------------------------------
P1 Bit Registers (Mnemonics & Ports)
------------------------------------------------*/
sbit CEX4 = 0x97;
sbit CEX3 = 0x96;
sbit CEX2 = 0x95;
sbit CEX1 = 0x94;
sbit CEX0 = 0x93;
sbit ECI  = 0x92;
sbit T2EX = 0x91;
sbit T2   = 0x90;

sbit P1_0 = 0x90;
sbit P1_1 = 0x91;
sbit P1_2 = 0x92;
sbit P1_3 = 0x93;
sbit P1_4 = 0x94;
sbit P1_5 = 0x95;
sbit P1_6 = 0x96;
sbit P1_7 = 0x97;

/*------------------------------------------------
SCON Bit Registers
------------------------------------------------*/
sbit RI   = 0x98;
sbit TI   = 0x99;
sbit RB8  = 0x9A;
sbit TB8  = 0x9B;
sbit REN  = 0x9C;
sbit SM2  = 0x9D;
sbit SM1  = 0x9E;
sbit SM0  = 0x9F;

/*------------------------------------------------
P2 Bit Registers
------------------------------------------------*/
sbit P2_0 = 0xA0;
sbit P2_1 = 0xA1;
sbit P2_2 = 0xA2;
sbit P2_3 = 0xA3;
sbit P2_4 = 0xA4;
sbit P2_5 = 0xA5;
sbit P2_6 = 0xA6;
sbit P2_7 = 0xA7;

/*------------------------------------------------
HSTAT Bit Values
------------------------------------------------*/
#define LPS_    0x01
#define OVI_    0x02
#define LPSC_   0x04
#define OVISC_  0x08
#define EP1EN_  0x10
#define EP1STL_ 0x20
#define HRWUPE_ 0x40

/*------------------------------------------------
HPSC Bit Values
------------------------------------------------*/
#define PCSC_   0x01
#define PESC_   0x02
#define PSSC_   0x04
#define POVSC_  0x08
#define RSTSC_  0x10

/*------------------------------------------------
HPSTAT Bit Values
------------------------------------------------*/
#define PCSTAT_ 0x01
#define PESTAT_ 0x02
#define PSSTAT_ 0x04
#define PRSTAT_ 0x08
#define PPSTAT_ 0x10
#define LSSTAT_ 0x20
#define VMSTAT_ 0x40
#define VPSTAT_ 0x80

/*------------------------------------------------
FIE Bit Values
------------------------------------------------*/
#define FTXIE0_ 0x01
#define FRXIE0_ 0x02
#define FTXIE1_ 0x04
#define FRXIE1_ 0x08
#define FTXIE2_ 0x10
#define FRXIE2_ 0x20
#define FTXIE3_ 0x40
#define FRXIE3_ 0x80

/*------------------------------------------------
FIE1 Bit Values
------------------------------------------------*/
#define FTXIE4_ 0x01
#define FRXIE4_ 0x02
#define FTXIE5_ 0x04
#define FRXIE5_ 0x08

/*------------------------------------------------
FIFLG Bit Registers
------------------------------------------------*/
sbit FTXD0 = 0xC0;
sbit FRXD0 = 0xC1;
sbit FTXD1 = 0xC2;
sbit FRXD1 = 0xC3;
sbit FTXD2 = 0xC4;
sbit FRXD2 = 0xC5;
sbit FTXD3 = 0xC6;
sbit FRXD3 = 0xC7;

/*------------------------------------------------
FIFLG1 Bit Values
------------------------------------------------*/
#define FTXD4_ 0x01
#define FRXD4_ 0x02
#define FTXD5_ 0x04
#define FRXD5_ 0x08

/*------------------------------------------------
EPCONFIG Bit Values
------------------------------------------------*/
#define SIXEPPEN_ 0x01

/*------------------------------------------------
IEN0 Bit Registers
------------------------------------------------*/
sbit EX0  = 0xA8;
sbit ET0  = 0xA9;
sbit EX1  = 0xAA;
sbit ET1  = 0xAB;
sbit ES   = 0xAC;
sbit ET2  = 0xAD;
sbit EC   = 0xAE;
sbit EA   = 0xAF;

/*------------------------------------------------
P3 Bit Registers (Mnemonics & Ports)
------------------------------------------------*/
sbit RD   = 0xB7;
sbit WR   = 0xB6;
sbit T1   = 0xB5;
sbit T0   = 0xB4;
sbit INT1 = 0xB3;
sbit INT0 = 0xB2;
sbit TXD  = 0xB1;
sbit RXD  = 0xB0;

sbit P3_0 = 0xB0;
sbit P3_1 = 0xB1;
sbit P3_2 = 0xB2;
sbit P3_3 = 0xB3;
sbit P3_4 = 0xB4;
sbit P3_5 = 0xB5;
sbit P3_6 = 0xB6;
sbit P3_7 = 0xB7;

/*------------------------------------------------
IEN1 Bit Values
------------------------------------------------*/
#define IE1_0_   0x01
#define IE1_1_   0x02
#define IE1_2_   0x04
#define IE1_3_   0x08

/*------------------------------------------------
IPL1 Bit Values
------------------------------------------------*/
#define IPL1_0_   0x01
#define IPL1_1_   0x02
#define IPL1_2_   0x04
#define IPL1_3_   0x08

/*------------------------------------------------
IPH1 Bit Values
------------------------------------------------*/
#define IPH1_0_   0x01
#define IPH1_1_   0x02
#define IPH1_2_   0x04
#define IPH1_3_   0x08

/*------------------------------------------------
IPH0 Bit Values
------------------------------------------------*/
#define IPH0_PX0_   0x01
#define IPH0_PT0_   0x02
#define IPH0_PX1_   0x04
#define IPH0_PT1_   0x08
#define IPH0_PS_    0x10
#define IPH0_PT2_   0x20
#define IPH0_PPC_   0x40

/*------------------------------------------------
IPL0 Bit Registers
------------------------------------------------*/
sbit PX0  = 0xB8;
sbit PT0  = 0xB9;
sbit PX1  = 0xBA;
sbit PT1  = 0xBB;
sbit PS   = 0xBC;
sbit PT2  = 0xBD;
sbit PPC  = 0xBE;

/*------------------------------------------------
T2CON Bit Registers
------------------------------------------------*/
sbit CP_RL2= 0xC8;
sbit C_T2  = 0xC9;
sbit TR2   = 0xCA;
sbit EXEN2 = 0xCB;
sbit TCLK  = 0xCC;
sbit RCLK  = 0xCD;
sbit EXF2  = 0xCE;
sbit TF2   = 0xCF;

/*------------------------------------------------
T2MOD Bit Values
------------------------------------------------*/
#define DCEN_   0x01
#define T2OE_   0x02

/*------------------------------------------------
PSW Bit Registers
------------------------------------------------*/
sbit P    = 0xD0;
sbit FL   = 0xD1;
sbit OV   = 0xD2;
sbit RS0  = 0xD3;
sbit RS1  = 0xD4;
sbit F0   = 0xD5;
sbit AC   = 0xD6;
sbit CY   = 0xD7;

/*------------------------------------------------
HIFLG Bit Registers
------------------------------------------------*/
sbit HTXD0 = 0xE8;
sbit HRXD0 = 0xE9;



/*------------------------------------------------
PSW1 Bit Values
------------------------------------------------*/
#define PSW1_Z_   0x02
#define PSW1_OV_  0x04
#define PSW1_RS0_ 0x08
#define PSW1_RS1_ 0x10
#define PSW1_N_   0x20
#define PSW1_AC_  0x40
#define PSW1_CY_  0x80

/*------------------------------------------------
SOFH Bit Values
------------------------------------------------*/
#define TS_MASK_  0x07
#define SOFODIS_  0x08
#define F_LOCK_   0x10
#define SOFIE_    0x20
#define ASOF_     0x40
#define SFACK_    0x80


/*------------------------------------------------
PCON1 Bit Values
------------------------------------------------*/
#define GSUS_     0x01
#define GRSM_     0x02
#define RWU_      0x04
#define URST_     0x08
#define URDIS_    0x10

/*------------------------------------------------
CCON Bit Registers
------------------------------------------------*/
sbit CCF0  = 0xD8;
sbit CCF1  = 0xD9;
sbit CCF2  = 0xDA;
sbit CCF3  = 0xDB;
sbit CCF4  = 0xDC;
sbit CR    = 0xDE;
sbit CF    = 0xDF;

/*------------------------------------------------
CMOD Bit Values
------------------------------------------------*/
#define ECF_  0x01
#define CPS0_ 0x02
#define CPS1_ 0x04

#define WDTE_ 0x40
#define CIDL_ 0x80

/*------------------------------------------------
CCAPM? Bit Values
------------------------------------------------*/
#define ECCF_ 0x01
#define PWM_  0x02
#define TOG_  0x04
#define MAT_  0x08
#define CAPN_ 0x10
#define CAPP_ 0x20
#define ECOM_ 0x40

/*------------------------------------------------
EPINDEX Bit Values
------------------------------------------------*/

#define EPIDX0_    0x01
#define EPIDX1_    0x02
#define EPIDX2_    0x04
#define HORF_      0x80

/*------------------------------------------------
EPCON  Bit Values
------------------------------------------------*/
#define TXEPEN_  0x01
#define TXOE_    0x02
#define RXEPEN_  0x04 
#define RXIE_    0x08
#define RXSPM_   0x10 
#define CTLEP_   0x20
#define TXSTL_   0x40
#define RXSTL_   0x80

/*------------------------------------------------
TXSTAT  Bit Values
------------------------------------------------*/
#define TXACK_    0x01
#define TXERR_    0x02
#define TXVOID_   0x04
#define TXSOVW_   0x08
#define TXFLUSH_  0x10
#define TXSEQ_    0x80

/*------------------------------------------------
RXSTAT Bit Values   
------------------------------------------------*/
#define RXACK_    0x01
#define RXERR_    0x02
#define RXVOID_   0x04
#define RXDTO_    0x08
#define EDOVW_    0x10
#define STOVW_    0x20
#define RXSETUP_  0x40
#define RXSEQ_    0x80

/*------------------------------------------------
TXCON Bit Values    
------------------------------------------------*/
#define REVRP_    0x01
#define ADVRM_    0x02
#define ATM_      0x04
#define TXISO_    0x08
#define FFSZ0_    0x20
#define FFSZ1_    0x40
#define TXCLR_    0x80

/*------------------------------------------------
TXFLG Bit Values    
------------------------------------------------*/
#define TXOVF_    0x01
#define TXURF_    0x02
#define TXFULL_   0x04
#define TXEMP_    0x08
#define TXFIF0_   0x40
#define TXFIF1_   0x80

/*------------------------------------------------
RXCON Bit Values    
------------------------------------------------*/
#define REVWP_    0x01
#define ADVWM_    0x02
#define ARM_      0x04
#define RXISO_    0x08
#define RXFFRC_   0x10
#define RXWS_     0x20
#define RXCLR_    0x80

/*------------------------------------------------
RXFLG Bit Values    
------------------------------------------------*/
#define RXOVF_    0x01
#define RXURF_    0x02
#define RXFULL_   0x04
#define RXEMP_    0x08
#define RXFIF0_   0x40
#define RXFIF1_   0x80

/*------------------------------------------------
Interrupt Vectors:
Interrupt Address = (Number * 8) + 3
------------------------------------------------*/
#define IE0_VECTOR	 0	/* 0x03 */
#define TF0_VECTOR	 1	/* 0x0B */
#define IE1_VECTOR	 2	/* 0x13 */
#define TF1_VECTOR	 3	/* 0x1B */
#define SIO_VECTOR	 4	/* 0x23 */
#define TF2_VECTOR	 5	/* 0x2B */
#define CF_VECTOR	 6	/* 0x33 */

#define SOF_VECTOR	 8	/* 0x43 */
#define ESOF_VECTOR	 8	/* 0x43 */ 
#define USB_VECTOR	 9	/* 0x4B */
#define EF_VECTOR	 9	/* 0x4B */
#define ESR_VECTOR	10	/* 0x53 */
#define GUSS_GRSM_VEC	10	/* 0x53 */

#define TRAP_VECTOR	15	/* 0x7B */


/* 930Ax SFR Bits  */

sbit EEP3    =     IEN1^3;
sbit EEP2    =     IEN1^2;
sbit EEP1    =     IEN1^1;
sbit EEP0    =     IEN1^0;

sbit PEP3L   =     IPL1^3;
sbit PEP2L   =     IPL1^2;
sbit PEP1L   =     IPL1^1;
sbit PEP0L   =     IPL1^0;
sbit PEP3H   =     IPH1^3;
sbit PEP2H   =     IPH1^2;
sbit PEP1H   =     IPH1^1;
sbit PEP0H   =     IPH1^0;

sbit RTWCE   =     WCON^1;
sbit RTWE    =     WCON^0;

sbit PD      =     PCON^1;
sbit LC      =     PCON^5;

sbit URDIS   =     PCON1^4;
sbit URST    =     PCON1^3;
sbit RWU     =     PCON1^2;
sbit GRSM    =     PCON1^1;
sbit GSUS    =     PCON1^0;

sbit A6      =     FADDR^6;
sbit A5      =     FADDR^5;
sbit A4      =     FADDR^4;
sbit A3      =     FADDR^3;
sbit A2      =     FADDR^2;
sbit A1      =     FADDR^1;
sbit A0      =     FADDR^0;

sbit TS7     =     SOFL^7;
sbit TS6     =     SOFL^6;
sbit TS5     =     SOFL^5;
sbit TS4     =     SOFL^4;
sbit TS3     =     SOFL^3;
sbit TS2     =     SOFL^2;
sbit TS1     =     SOFL^1;
sbit TS0     =     SOFL^0;

sbit SFACK   =     SOFH^7;
sbit ASOF    =     SOFH^6;
sbit SOFIE   =     SOFH^5;
sbit FTLOCK  =     SOFH^4;
sbit SOFODIS =     SOFH^3;
sbit TS10    =     SOFH^2;
sbit TS9     =     SOFH^1;
sbit TS8     =     SOFH^0;

sbit FRXIE3  =     FIE^7;
sbit FTXIE3  =     FIE^6;
sbit FRXIE2  =     FIE^5;
sbit FTXIE2  =     FIE^4;
sbit FRXIE1  =     FIE^3;
sbit FTXIE1  =     FIE^2;
sbit FRXIE0  =     FIE^1;
sbit FTXIE0  =     FIE^0;

sbit FRXD3   =     FIFLG^7;
sbit FTXD3   =     FIFLG^6;
sbit FRXD2   =     FIFLG^5;
sbit FTXD2   =     FIFLG^4;
sbit FRXD1   =     FIFLG^3;
sbit FTXD1   =     FIFLG^2;
sbit FRXD0   =     FIFLG^1;
sbit FTXD0   =     FIFLG^0;

sbit RXSTL   =     EPCON^7;
sbit TXSTL   =     EPCON^6;
sbit CTLEP   =     EPCON^5;
sbit RXSPM   =     EPCON^4;
sbit RXIE    =     EPCON^3;
sbit RXEPEN  =     EPCON^2;
sbit TXOE    =     EPCON^1;
sbit TXEPEN  =     EPCON^0;

sbit RXSEQ   =     RXSTAT^7; 
sbit RXSETUP =     RXSTAT^6;
sbit STOVW   =     RXSTAT^5;
sbit EDOVW   =     RXSTAT^4;
sbit RXDTO   =     RXSTAT^3;
sbit RXVOID  =     RXSTAT^2;
sbit RXERR   =     RXSTAT^1;
sbit RXACK   =     RXSTAT^0;

sbit RXCLR   =     RXCON^7;
sbit RXWS    =     RXCON^5;
sbit RXFFRC  =     RXCON^4;
sbit RXISO   =     RXCON^3;
sbit ARM     =     RXCON^2;
sbit ADVWM   =     RXCON^1;
sbit REVWP   =     RXCON^0;

sbit RXFIF1  =     RXFLG^7;
sbit RXFIF0  =     RXFLG^6;
sbit RXEMP   =     RXFLG^3;
sbit RXFULL  =     RXFLG^2;
sbit RXURF   =     RXFLG^1;
sbit RXOVF   =     RXFLG^0;

sbit TXSEQ   =     TXSTAT^7;
sbit TXFLUSH =     TXSTAT^4;
sbit TXSOVW  =     TXSTAT^3;
sbit TXVOID  =     TXSTAT^2;
sbit TXERR   =     TXSTAT^1;
sbit TXACK   =     TXSTAT^0;

sbit TXCLR   =     TXCON^7;
sbit FFSZ1   =     TXCON^6;
sbit FFSZ0   =     TXCON^5;
sbit TXISO   =     TXCON^3;
sbit ATM     =     TXCON^2;
sbit ADVRM   =     TXCON^1;
sbit REVRP   =     TXCON^0;

sbit TXFIF1  =     TXFLG^7;
sbit TXFIF0  =     TXFLG^6;
sbit TXEMP   =     TXFLG^3;
sbit TXFULL  =     TXFLG^2;
sbit TXURF   =     TXFLG^1;
sbit TXOVF   =     TXFLG^0;


/* 930Hx SFR Bits */

sbit HRWUPE  =     HSTAT^6;
sbit EP1STL  =     HSTAT^5;
sbit EP1EN   =     HSTAT^4;
sbit OVISC   =     HSTAT^3;
sbit LPSC    =     HSTAT^2;
sbit OVI     =     HSTAT^1;
sbit LPS     =     HSTAT^0;

sbit HTXD0   =     HIFLG^0;
sbit HRXD0   =     HIFLG^1;

sbit HPPWR4  =     HPPWR^4;
sbit HPPWR3  =     HPPWR^3;
sbit HPPWR2  =     HPPWR^2;
sbit HPPWR1  =     HPPWR^1;

sbit VPSTAT  =     HPSTAT^7;
sbit VMSTAT  =     HPSTAT^6;
sbit LSSTAT  =     HPSTAT^5;
sbit PPSTAT  =     HPSTAT^4;
sbit PRSTAT  =     HPSTAT^3;
sbit PSSTAT  =     HPSTAT^2;
sbit PESTAT  =     HPSTAT^1;
sbit PCSTAT  =     HPSTAT^0;

sbit PSTSC   =     HPSC^4;
sbit POTSC   =     HPSC^3;
sbit PSSC    =     HPSC^2;
sbit PESC    =     HPSC^1;
sbit PCSC    =     HPSC^0;

#endif



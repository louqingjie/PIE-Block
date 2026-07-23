$NOCOND
;------------------------------------------------------------------------------
;  This file is part of the L251 Banked Linker/Locater package
;  Copyright KEIL ELEKTRONIK GmbH 1995 - 2002
;  Version 3.0 (for C251 Compiler Version 3.5 or higher)
;------------------------------------------------------------------------------
;************************ Configuration Section *******************************
?B_NBANKS    EQU  4    ; Define max. Number of Banks                          *
;                      ; following values are allowed: 2, 4, 8, 16, 32, 64    *
;                      ; the max. value for ?B_BANKS is 64                    *
;                                                                             *
?B_MODE      EQU  0    ; 0 for bank switching via on-chip I/O port            *
;                      ; 1 for bank switching via memory-mapped XDATA port    *
;                      ; 3 for bank switching via memory-mapped EDATA port    *
;                      ; 4 for user-provided bank switch code                 *
;                                                                             *
?B_RST_BANK  EQU  0xFF ; specifies the active code bank number after CPU      *
;                      ; Reset.  Used to reduce the entries in the            *
;                      ; INTERBANK CALL TABLE.  The value 0xFF disables       *
;                      ; this L251 linker/locater optimization.               *
;                                                                             *
IF  ?B_MODE = 0;                                                              *
;-----------------------------------------------------------------------------*
; if ?BANK?MODE is 0 define the following values                              *
; For bank switching via on-chip Port define port Address and bits            *
?B_PORT         EQU  DATA 090H   ; default is P1                              *
?B_FIRSTBIT     EQU  3           ; default is Bit 3                           *
;-----------------------------------------------------------------------------*
ENDIF;                                                                        *
;                                                                             *
IF  ?B_MODE = 1;                                                              *
;-----------------------------------------------------------------------------*
; if ?BANK?MODE is 1 define the following values                              *
; For bank switching via memory-mapped XDATA Port set off-chip port address   *
?B_XDATAPORT    EQU     0FFFFH   ; default is XDATA port address 0FFFFH       *
;-----------------------------------------------------------------------------*
ENDIF;                                                                        *
;                                                                             *
IF  ?B_MODE = 3;                                                              *
;-----------------------------------------------------------------------------*
; if ?BANK?MODE is 3 define the following values                              *
; For bank switching via memory-mapped EDATA port set off-chip port address   *
?B_EDATAPORT    EQU     0FFFFH   ; default is NDATA port address 0FFFFH       *
;-----------------------------------------------------------------------------*
ENDIF;                                                                        *
;                                                                             *
IF  ?B_MODE = 4;                                                              *
;-----------------------------------------------------------------------------*
; if ?BANK?MODE is 4 define the following switch macros                       *
; For bank switching via user-provided bank switch code you must define for   *
; each memory bank a own macro which contains the bank switch code.  The      *
; following example shows how to use the I/O lines P1.4 and P1.7 for bank     *
; switching.  Since you can select just 4 banks with two address lines, just  *
; four macros are defined.  The number of macros must conform with the number *
; ?B_NBANKS number, i.e. for an application with 16 memory banks you must     *
; define 16 macros.                                                           *
;                                                                             *
; IMPORTANT NOTE:  each SWITCH macro must generate the same code size,        *
;                  otherwise the BANKSWITCH code does not work correctly.     *
;                                                                             *
P1              EQU DATA 90H     ; I/O Port Address                           *
;                                                                             *
SWITCH0         MACRO            ; Switch to Memory Bank #0                   *
                CLR     P1.4     ; Clear Port 1 Bit 4                         *
                CLR     P1.7     ; Clear Port 1 Bit 7                         *
                ENDM                                                          *
;                                                                             *
SWITCH1         MACRO            ; Switch to Memory Bank #0                   *
                SETB    P1.4     ; Set   Port 1 Bit 4                         *
                CLR     P1.7     ; Clear Port 1 Bit 7                         *
                ENDM                                                          *
;                                                                             *
SWITCH2         MACRO            ; Switch to Memory Bank #0                   *
                CLR     P1.4     ; Clear Port 1 Bit 4                         *
                SETB    P1.7     ; Set   Port 1 Bit 7                         *
                ENDM                                                          *
;                                                                             *
SWITCH3         MACRO            ; Switch to Memory Bank #0                   *
                SETB    P1.4     ; Set   Port 1 Bit 4                         *
                SETB    P1.7     ; Set   Port 1 Bit 7                         *
                ENDM                                                          *
;                                                                             *
;-----------------------------------------------------------------------------*
ENDIF;                                                                        *
;                                                                             *
;******************************************************************************
;                                                                             *
; THEORY OF OPERATION                                                         *
; -------------------                                                         *
; The section below describes the code generated by L251 and the operation of *
; the L251BANK.A51 module.  L251 generates for each function which is located *
; in a code memory bank and called from the common area or a different code   *
; bank and entry into the INTRABANK CALL TABLE.  The INTRABANK CALL TABLE is  *
; located in the SEGMENT ?BANK?SELECT and listed in the Linker MAP file. The  *
; entries in that TABLE have the following format:                            *
;                                                                             *
;   ?FCT?1:  MOV  DPTR,#FCT     ; Load Address of target FCT                  *
;            JMP  ?B_BANKn      ; Switch to Bank and Jump to Target Code      *
;                                                                             *
; Instead of directly calling the function FCT, the Linker changes the entry  *
; to ?FCT?1.  This entry selects the bank where the function FCT is located   *
; and calls that function via the routines defined in this L251BANK.A51 file. *
; The L251BANK.A51 file contains two sets of functions for each bank:         *
;                                                                             *
; ?B_BANKn    is a routine which saves the entry of the ?B_SWITCHn function   *
;             for the current active bank on the STACK and switches to the    *
;             bank 'n'.  The it jumps to the address specified by the DPTR    *
;             register.  It is allowed to modify the following registers in   *
;             the ?B_BANKn routine:  WR8, R10, DPTR, PSW                      *
;                                                                             *
; ?B_SWITCHn  is a function which selects the bank 'n'.  This function is     *
;             used at the end of a user function to return to the calling     *
;             code bank.  Only the following registers may be altered in the  *
;             ?B_SWITCHn function:  WR8, R10, DPTR                            *
;                                                                             *
;******************************************************************************



; Define SFR Registers
ACC     DATA    0E0H
B       DATA    0F0H
PSW     DATA    0D0H
DPL     DATA    082H
DPH     DATA    083H

                NAME    ?BANK?SWITCHING

PUBLIC  ?B_NBANKS, ?B_MODE, ?B_CURRENTBANK
PUBLIC  SWITCHBANK

IF  ?B_MODE = 0 ;**************************************************************

PUBLIC ?B_MASK, ?B_FACTOR

?B_CURRENTBANK  EQU     ?B_PORT
?B_FACTOR       EQU     1 SHL ?B_FIRSTBIT

; generate Mask and Bank Number Information
IF      ?B_NBANKS <= 2
  MASK          EQU     00000001B
ELSEIF  ?B_NBANKS <= 4
  MASK          EQU     00000011B
ELSEIF  ?B_NBANKS <= 8
  MASK          EQU     00000111B
ELSEIF  ?B_NBANKS <= 16
  MASK          EQU     00001111B
ELSEIF  ?B_NBANKS <= 32
  MASK          EQU     00011111B
ELSE
  MASK          EQU     00111111B
ENDIF     

?B_MASK         EQU     MASK SHL ?B_FIRSTBIT

BANKN           MACRO   N
BANK&N          EQU     N SHL ?B_FIRSTBIT
                ENDM

CNT             SET     0

                REPT    ?B_NBANKS
                BANKN   %CNT
CNT             SET     CNT+1
                ENDM


; Convert Bank No in R9 to Address * 8

IF ?B_NBANKS <= 32

  IF  ?B_FIRSTBIT = 0
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHL     R9
                SHL     R9
                SHL     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 1
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHL     R9
                SHL     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 2
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHL     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 3
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 4
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHR     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 5
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHR     R9
                SHR     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 6
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHR     R9
                SHR     R9
                SHR     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 7
  CONVBANKNO    MACRO
                ANL     R9,#?B_MASK
                SHR     R9
                SHR     R9
                SHR     R9
                SHR     R9
                MOV     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

ELSE
; Support for more than 32 Banks
  IF  ?B_FIRSTBIT = 0
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHL     WR8
                SHL     WR8
                SHL     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 1
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHL     WR8
                SHL     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 2
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHL     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 3
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 4
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHR     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 5
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHR     WR8
                SHR     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 6
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHR     WR8
                SHR     WR8
                SHR     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

  IF  ?B_FIRSTBIT = 7
  CONVBANKNO    MACRO
                ANL     WR8,#?B_MASK
                SHR     WR8
                SHR     WR8
                SHR     WR8
                SHR     WR8
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                ENDM
  ENDIF

ENDIF


BANK            MACRO   N
                PUBLIC  ?B_BANK&N
?B_BANK&N:      MOV     B,#BANK&N
                JMP     BANKSWITCH
                ENDM

SWITCH          MACRO   N
                PUBLIC  ?B_SWITCH&N
                ORG     N * 8
?B_SWITCH&N:
                ORL     ?B_CURRENTBANK,#?B_MASK
                ANL     ?B_CURRENTBANK,#(BANK&N OR NOT ?B_MASK) 
                RET
                ENDM

?BANK?SWITCH    SEGMENT CODE PAGE

                RSEG    ?BANK?SWITCH
; Generate ?B_SWITCHn functions
CNT             SET     0

                REPT    ?B_NBANKS
                SWITCH  %CNT
CNT             SET     CNT+1
                ENDM

?BANK?SELECT    SEGMENT CODE
                RSEG    ?BANK?SELECT
; Generate ?B_BANKn entries
CNT             SET     0

                REPT    ?B_NBANKS
                BANK    %CNT
CNT             SET     CNT+1
                ENDM

BANKSWITCH:     MOV     R9,?B_CURRENTBANK
                CONVBANKNO
                PUSH    R9
                PUSH    R8
                PUSH    DPL
                PUSH    DPH
                MOV     R8,#8                           ; sizeof switch fuct.
                MUL     R8,R10
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                JMP     @WR8                            ; switch to new bank


;************************  SWITCHBANK FUNCTION  *******************************
;                                                                             *
; SWITCHBANK allows use of bank-switching for C programs                      *
;                                                                             *
; prototype:   extern switchbank (unsigned char bank_number);                 *
;                                                                             *
;******************************************************************************

SWITCHBANK:     MOV     B,#(?B_SWITCH1-?B_SWITCH0)      ; sizeof switch fuct.
                MUL     AB
                ADD     R10,#BYTE1 ?BANK?SWITCH         ; entry offset
                JMP     @WR10                           ; switch to new bank

ENDIF  ; close block IF ?B_MODE = 0 *******************************************


IF  ?B_MODE = 1 ;**************************************************************

?BANK?DATA      SEGMENT DATA
                RSEG    ?BANK?DATA
?B_CURRENTBANK: DS      1

BANK            MACRO   N
                PUBLIC  ?B_BANK&N
?B_BANK&N:      MOV     B,#N
                JMP     BANKSWITCH
                ENDM

SWITCH          MACRO   N
                PUBLIC  ?B_SWITCH&N
?B_SWITCH&N:
                MOV     B,#N
                MOV     DPTR,#?B_XDATAPORT
                MOV     ?B_CURRENTBANK,B
                MOV     @DR56,R10
                RET
                ENDM

?BANK?SWITCH    SEGMENT CODE PAGE

                RSEG    ?BANK?SWITCH
; Generate ?B_SWITCHn functions
CNT             SET     0

                REPT    ?B_NBANKS
                SWITCH  %CNT
CNT             SET     CNT+1
                ENDM

?BANK?SELECT    SEGMENT CODE
                RSEG    ?BANK?SELECT
; Generate ?B_BANKn entries
CNT             SET     0

                REPT    ?B_NBANKS
                BANK    %CNT
CNT             SET     CNT+1
                ENDM

BANKSWITCH:     MOV     R9,?B_CURRENTBANK
                MOV     R8,#(?B_SWITCH1-?B_SWITCH0)     ; sizeof switch fuct.
                MUL     R8,R9
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                PUSH    R9
                PUSH    R8
                PUSH    DPL
                PUSH    DPH
                MOV     DPTR,#?B_XDATAPORT
                MOV     ?B_CURRENTBANK,B
                MOV     @DR56,R10
                RET
                
;************************  SWITCHBANK FUNCTION  *******************************
;                                                                             *
; SWITCHBANK allows use of bank-switching for C programs                      *
;                                                                             *
; prototype:   extern switchbank (unsigned char bank_number);                 *
;                                                                             *
;******************************************************************************

SWITCHBANK:     MOV     DPTR,#?B_XDATAPORT
                MOV     ?B_CURRENTBANK,A
                MOVX    @DPTR,A
                RET


;---- Initialization of ?B_CURRENTBANK and ?B_XDATAPORT:
?C_C51STARTUP?1 SEGMENT CODE  
                RSEG    ?C_C51STARTUP?1
IF ?B_RST_BANK <> 0FFH
                MOV     A,#?B_RST_BANK
ELSE
                CLR     A
ENDIF
                MOV     ?B_CURRENTBANK,A      ; Init Current Bank
                MOV     DPTR,#?B_XDATAPORT    ; Init XDATA Port
                MOVX    @DPTR,A

ENDIF  ; close block IF ?B_MODE = 1 *******************************************


IF  ?B_MODE = 3 ;**************************************************************

?BANK?DATA      SEGMENT DATA
                RSEG    ?BANK?DATA
?B_CURRENTBANK: DS      1

BANK            MACRO   N
                PUBLIC  ?B_BANK&N
?B_BANK&N:      MOV     B,#N
                JMP     BANKSWITCH
                ENDM

SWITCH          MACRO   N
                PUBLIC  ?B_SWITCH&N
?B_SWITCH&N:
                MOV     B,#N
                MOV     ?B_CURRENTBANK,B
                MOV     EDATA ?B_EDATAPORT,R10
                RET
                ENDM

?BANK?SWITCH    SEGMENT CODE PAGE

                RSEG    ?BANK?SWITCH
; Generate ?B_SWITCHn functions
CNT             SET     0

                REPT    ?B_NBANKS
                SWITCH  %CNT
CNT             SET     CNT+1
                ENDM

?BANK?SELECT    SEGMENT CODE
                RSEG    ?BANK?SELECT
; Generate ?B_BANKn entries
CNT             SET     0

                REPT    ?B_NBANKS
                BANK    %CNT
CNT             SET     CNT+1
                ENDM

BANKSWITCH:     MOV     R9,?B_CURRENTBANK
                MOV     R8,#(?B_SWITCH1-?B_SWITCH0)     ; sizeof switch fuct.
                MUL     R8,R9
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                PUSH    R9
                PUSH    R8
                PUSH    DPL
                PUSH    DPH
                MOV     ?B_CURRENTBANK,B
                MOV     EDATA ?B_EDATAPORT,R10
                RET
                
;************************  SWITCHBANK FUNCTION  *******************************
;                                                                             *
; SWITCHBANK allows use of bank-switching for C programs                      *
;                                                                             *
; prototype:   extern switchbank (unsigned char bank_number);                 *
;                                                                             *
;******************************************************************************

SWITCHBANK:     MOV     ?B_CURRENTBANK,A
                MOV     EDATA ?B_EDATAPORT,R11
                RET


;---- Initialization of ?B_CURRENTBANK and ?B_EDATAPORT:
?C_C51STARTUP?1 SEGMENT CODE  
                RSEG    ?C_C51STARTUP?1
IF ?B_RST_BANK <> 0FFH
                MOV     A,#?B_RST_BANK
ELSE
                CLR     A
ENDIF
                MOV     ?B_CURRENTBANK,A       ; Init Current Bank
                MOV     EDATA ?B_EDATAPORT,R11 ; Init EDATA Port

ENDIF  ; close block IF ?B_MODE = 3 *******************************************


IF  ?B_MODE = 4 ;**************************************************************

?BANK?DATA      SEGMENT DATA
                RSEG    ?BANK?DATA
?B_CURRENTBANK: DS      1

BANK            MACRO   N
                PUBLIC  ?B_BANK&N
?B_BANK&N:      MOV     B,#N
                JMP     BANKSWITCH
                ENDM

SWITCH          MACRO   N
                PUBLIC  ?B_SWITCH&N
?B_SWITCH&N:
                SWITCH&N
                RET
                ENDM

?BANK?SWITCH    SEGMENT CODE PAGE

                RSEG    ?BANK?SWITCH
; Generate ?B_SWITCHn functions
CNT             SET     0

                REPT    ?B_NBANKS
                SWITCH  %CNT
CNT             SET     CNT+1
                ENDM

?BANK?SELECT    SEGMENT CODE
                RSEG    ?BANK?SELECT
; Generate ?B_BANKn entries
CNT             SET     0

                REPT    ?B_NBANKS
                BANK    %CNT
CNT             SET     CNT+1
                ENDM

BANKSWITCH:     MOV     R9,?B_CURRENTBANK
                MOV     R8,#(?B_SWITCH1-?B_SWITCH0)     ; sizeof switch fuct.
                MUL     R8,R9
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                PUSH    R9
                PUSH    R8
                PUSH    DPL
                PUSH    DPH
                MOV     R8,#(?B_SWITCH1-?B_SWITCH0)     ; sizeof switch fuct.
                MUL     R8,R10
                ADD     R8,#BYTE1 ?BANK?SWITCH          ; entry offset
                JMP     @WR8                            ; switch to new bank


;************************  SWITCHBANK FUNCTION  *******************************
;                                                                             *
; SWITCHBANK allows use of bank-switching for C programs                      *
;                                                                             *
; prototype:   extern switchbank (unsigned char bank_number);                 *
;                                                                             *
;******************************************************************************

SWITCHBANK:     MOV     B,#(?B_SWITCH1-?B_SWITCH0)      ; sizeof switch fuct.
                MUL     AB
                ADD     R10,#BYTE1 ?BANK?SWITCH         ; entry offset
                JMP     @WR10                           ; switch to new bank

;---- Initialization of ?B_CURRENTBANK and execution of SWITCH0:
?C_C51STARTUP?1 SEGMENT CODE  
                RSEG    ?C_C51STARTUP?1
IF ?B_RST_BANK <> 0FFH

  IF ?B_RST_BANK <> 0
    __ERROR__ "DEFAULT BANK NOT 0: CHECK SWITCH MACRO BELOW"
  ENDIF
                MOV     A,#?B_RST_BANK
ELSE
                CLR     A
ENDIF
                MOV     ?B_CURRENTBANK,A       ; Init Current Bank
                SWITCH0                        ; Execute SWITCH0 Macro

ENDIF  ; close block IF ?B_MODE = 4 *******************************************



                END

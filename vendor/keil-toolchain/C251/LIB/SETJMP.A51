$NOMOD51
;------------------------------------------------------------------------------
;  This file is part of the C251 Compiler package
;  Copyright (c) 1998-2008 Keil Elektronik GmbH and Keil Software, Inc.
;------------------------------------------------------------------------------
;  SETJMP.A51: setjmp / longjmp ANSI C library functions
;------------------------------------------------------------------------------
;
;  To translate this file use A251 with the following invocation:
;
;     A251 SETJMP.A51  [ MODSRC ] SET (model) [ SET (ROMHUGE) ]
;  whereby:
;     MODSRC         defines the 251 Source Mode  (default is Binary Mode)
;     SET (ROMHUGE)  defines the ROM (HUGE) Mode  (default is ROM(LARGE) )
;     SET (model)    defines the memory model (default SET (TINY))
;
;------------------------------------------------------------------------------

$IF ROMHUGE
POST	LIT	'?'		    ; postfix for static functions
POSTR	LIT	'??'		; postfix for reentrant functions
PRSEG	LIT	'ECODE'		; code segment
PRATTR  LIT	'INSEG'		; code segment attribute
CModel	LIT	'FAR'		; model
$ELSE
POST	LIT	''
POSTR	LIT	'?_'
PRSEG	LIT	'CODE'
PRATTR  LIT	''
CModel	LIT	'NEAR'
$ENDIF


		NAME	setjmp{POSTR}

		PUBLIC	setjmp{POSTR}, longjmp{POSTR}

?C?LIB_CODE{POST}	SEGMENT	PRSEG PRATTR
		RSEG	?C?LIB_CODE{POST}

; int  setjmp (jmp_buf);

$IF TINY OR XTINY
sptr	LIT	'WR6'
$ELSE
sptr	LIT	'DR0'
$ENDIF

setjmp{POSTR}	PROC	CModel
		MOV	@sptr+2,WR12
		MOV	@sptr+4,WR14
		POP	WR10
		MOV	@sptr+6,WR10
$IF ROMHUGE
		POP	R9
		MOV	@sptr+8,R9
		XRL	R8,R8
		MOV	DR16,DR60
		MOV	@sptr,WR18
		XRL	WR6,WR6
		PUSH	R9
		PUSH	WR10
		ERET
$ELSE
		MOV	DR16,DR60
		MOV	@sptr,WR18
		XRL	WR6,WR6
		PUSH	WR10
		RET
$ENDIF
		ENDP

longjmp{POSTR}	PROC	CModel
		MOV	WR12,@sptr+2
		MOV	WR14,@sptr+4
		MOV	WR10,@sptr
		XRL	WR8,WR8		; 23.6.2004
		MOV	DR60,DR8
		MOV	WR10,@sptr+6
$IF ROMHUGE
		MOV	R9,@sptr+8
$IF TINY OR XTINY
		MOV	WR6,WR4
$ENDIF
		ANL	WR6,WR6
		JNE	L001
		INC	WR6,#1
L001:		PUSH	R9
		PUSH	WR10
		ERET
$ELSE
$IF TINY OR XTINY
		MOV	WR6,WR4
$ENDIF
		ANL	WR6,WR6
		JNE	L001
		INC	WR6,#1
L001:		PUSH	WR10
		RET
$ENDIF
		ENDP

		END

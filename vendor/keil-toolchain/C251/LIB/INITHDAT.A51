;----------------------------------------------------------------------------
;
; Init records for HDATA (near) memory.  The record structure is as follows:
;
;    Byte 0  Byte 1  Byte 2  Byte 3  Byte 4  Byte 5
;   +-------+-------+-------+-------+-------+-------+
;   |Len MSB|Len LSB|Adr MSB|Adr Mid|Adr LSB|Content|
;   +-------+-------+-------+-------+-------+-------+
;   |                                       +Rep Len+
;   +--- Repeated for each Object ------------------+
;
; The complete HDATA initilization is placed into the segment ?C_INITHDATA 
; (segment class is HCONST).  
;
;----------------------------------------------------------------------------

		NAME	?C?INITHDATA
PUBLIC		?C?INITHDATA
EXTRN HCONST (?C?INITHDATA_END)

$include (reg251s.inc)

?C_C51STARTUP?2	SEGMENT   CODE          ; Code for table driven Init 
?C_INITHDATA	SEGMENT   HCONST	; Segment with init tables (records)

		RSEG	?C_C51STARTUP?2
?C?INITHDATA:	MOV	WR0,#WORD2 ?C_INITHDATA
		MOV	WR2,#WORD0 ?C_INITHDATA
INIT_LOOP:	MOV	WR8,@DR0	; WR8 contains Length
		ANL	WR8,WR8
		JE	INIT_END
		MOV	R5,@DR0+2
		MOVZ	WR4,R5
		MOV	WR6,@DR0+3	; DR4 contains Address
		ADD	DR0,#5
		INC	WR8,#1
		SJMP	INIT_OBJ1
INIT_OBJ0:	MOV	R11,@DR0
		MOV	@DR4,R11
		INC	DR4,#1
		INC	DR0,#1
INIT_OBJ1:	DEC	WR8,#1
		JNE	INIT_OBJ0
		SJMP	INIT_LOOP
INIT_END:

		END


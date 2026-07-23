/*--------------------------------------------------------------------------
SETJMP.H

Prototypes for longjmp facility for C251 Version 5
Copyright (c) 1995-2012 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/
/* define the buffer type for holding the state information */

#pragma SAVE
#pragma PARM251
#pragma NOCCODE

#if __C251__ >= 200

#if defined (__CC7__) && __CC7__ >= 0
#ifndef _JMP_BUF_DEFINED
#define _JBLEN	11  /* WR60, WR62, WR12, WR14, RET-ADDR */
typedef  char jmp_buf[_JBLEN];
#define _JMP_BUF_DEFINED
#endif

#define setjmp  __CC7_setjmp
#define longjmp __CC7_longjmp

/* function prototypes */
int  far __CC7_setjmp  (void huge *)       reentrant;
void far __CC7_longjmp (void huge *, int)  reentrant;

#else

#ifndef _JMP_BUF_DEFINED
#define _JBLEN	9  /* WR62, WR12, WR14, RET-ADDR */
typedef  char jmp_buf[_JBLEN];
#define _JMP_BUF_DEFINED
#endif

/* function prototypes */
int  setjmp  (void *)       reentrant;
void longjmp (void *, int)  reentrant;

#endif

#else

#ifndef _JMP_BUF_DEFINED
#define _JBLEN	8  /* RET-ADDR, ?C_XBP, ?C_IBP, ?C_BP, SP, SPH */
typedef  char jmp_buf[_JBLEN];
#define _JMP_BUF_DEFINED
#endif

/* function prototypes */
int  setjmp  (jmp_buf);
void longjmp (jmp_buf, int);
#endif

#pragma RESTORE

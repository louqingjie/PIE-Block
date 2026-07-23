/*--------------------------------------------------------------------------
INTRINS.H

Intrinsic functions for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#pragma SAVE
#pragma PARM251

#if __C251__ >= 200
#pragma FUNCTIONS(STATIC)
/* intrinsic functions are reentrant, but need static attribute */
#endif

extern void          _nop_     (void);
extern bit           _testbit_ (bit);
extern unsigned char _cror_    (unsigned char, unsigned char);
extern unsigned int  _iror_    (unsigned int,  unsigned char);
extern unsigned long _lror_    (unsigned long, unsigned char);
extern unsigned char _crol_    (unsigned char, unsigned char);
extern unsigned int  _irol_    (unsigned int,  unsigned char);
extern unsigned long _lrol_    (unsigned long, unsigned char);
extern unsigned char _chkfloat_  (float x)  reentrant;
extern unsigned char _chkdouble_ (double x) reentrant;

#pragma RESTORE

/*--------------------------------------------------------------------------
STDARG.H

Prototypes for variable argument lists for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#pragma SAVE
#pragma PARM251

#ifndef _STDARG_

#define _STDARG_

#ifndef NULL
 #define NULL ((void *) 0)
#endif

#ifndef _VA_LIST_DEFINED
typedef char *va_list;
#define _VA_LIST_DEFINED
#endif

#if (__C251__ >= 200) 

  #define va_start(ap,v)  ap = _va_start_ (&v, sizeof(v))
  #define va_arg(ap,t) (ap-=sizeof(t),*((t *)ap))
  #define va_end(ap)
  extern void *_va_start_ (void *ap, int sz);   // intrinsic

#else

  #define va_start(ap,v) ap = (va_list)&v + sizeof(v)
  #define va_arg(ap,t) (((t *)ap)++[0])
  #define va_end(ap)

#endif

#endif

#pragma RESTORE

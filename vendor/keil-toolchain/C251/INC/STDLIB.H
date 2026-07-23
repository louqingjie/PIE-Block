/*--------------------------------------------------------------------------
STDLIB.H

Standard functions for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#pragma SAVE
#pragma PARM251

#ifndef _SIZE_T
 #define _SIZE_T
 typedef unsigned int size_t;
#endif

#ifndef NULL
 #define NULL ((void *) 0L)
#endif

#ifndef _WCHAR_T_DEFINED_
#define _WCHAR_T_DEFINED_
typedef char wchar_t;
#endif

#ifndef RAND_MAX
 #define RAND_MAX  32767u
#endif

#if __C251__ >= 200
extern int     abs  (int   val) reentrant;
extern long   labs  (long  val) reentrant;

extern double atof (char *s1) reentrant;
extern long   atol (char *s1) reentrant;
extern int    atoi (char *s1) reentrant;
extern int    rand ()         reentrant;
extern void   srand (int)     reentrant;

#pragma SAVE
#pragma functions (static)
#if (__MODEL__ == 3 || __MODEL__ == 4)   /* TINY & XTINY */
extern void near  *malloc        (unsigned int size);
extern void        free          (void near *p);
extern void        init_mempool  (void near *p, unsigned int size);
extern void near  *realloc       (void near *p, unsigned int size);
extern void near  *calloc        (unsigned int size, unsigned int len);
#else
extern void far   *malloc        (unsigned int size);
extern void        free          (void far *p);
extern void        init_mempool  (void far *p, unsigned int size);
extern void far   *realloc       (void far *p, unsigned int size);
extern void far   *calloc        (unsigned int size, unsigned int len);
#endif

extern void far   *fmalloc       (unsigned int size);
extern void        ffree         (void far *p);
extern void        finit_mempool (void far *p, unsigned int size);
extern void far   *frealloc      (void far *p, unsigned int size);
extern void far   *fcalloc       (unsigned int size, unsigned int len);

extern void xdata *xmalloc       (unsigned int size);
extern void        xfree         (void xdata *p);
extern void        xinit_mempool (void xdata *p, unsigned int size);
extern void xdata *xrealloc      (void xdata *p, unsigned int size);
extern void xdata *xcalloc       (unsigned int size, unsigned int len);
#pragma RESTORE
#else
extern int     abs  (int   val);
extern long   labs  (long  val);

extern float  atof (char *s1);
extern long   atol (char *s1);
extern int    atoi (char *s1);
extern int    rand ();
extern void   srand (int);

extern void *malloc      (unsigned int size);
extern void free         (void xdata *p);
extern void init_mempool (void xdata *p, unsigned int size);
extern void *realloc     (void xdata *p, unsigned int size);
extern void *calloc      (unsigned int size, unsigned int len);
#endif

#pragma RESTORE

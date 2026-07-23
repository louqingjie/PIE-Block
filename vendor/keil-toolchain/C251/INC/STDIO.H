/*--------------------------------------------------------------------------
STDIO.H

Prototypes for standard I/O functions for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#pragma SAVE
#pragma PARM251

#ifndef EOF
 #define EOF -1
#endif

#ifndef NULL
 #define NULL ((void *) 0)
#endif

#ifndef _SIZE_T
 #define _SIZE_T
 typedef unsigned int size_t;
#endif

#if (__C251__ >= 200) 
#pragma SAVE
#pragma FUNCTIONS(STATIC)
/* only static functions available */
extern char _getkey  (void);
extern char getchar  (void);
extern char ungetchar(char);
extern char putchar  (char);
extern int  printf   (const char *, ...); 
extern char *gets    (char *, int n);
extern int  scanf    (const char *, ...);
extern int  vprintf  (const char *, char *);
extern int  puts     (const char *);
#pragma RESTORE
/* available as reentrant & non-reentrant version */
extern int  sprintf  (char *, const char *, ...);
extern int  vsprintf (char *, const char *, char *);
extern int  sscanf   (char *, const char *, ...);
#else
extern char _getkey (void);
extern char getchar (void);
extern char ungetchar (char);
extern char putchar (char);
extern int printf   (const char *, ...);
extern int sprintf  (char *, const char *, ...);
extern int vprintf  (const char *, char *);
extern int vsprintf (char *, const char *, char *);
extern char *gets (char *, int n);
extern int scanf (const char *, ...);
extern int sscanf (char *, const char *, ...);
extern int puts (const char *);
#endif

#pragma RESTORE

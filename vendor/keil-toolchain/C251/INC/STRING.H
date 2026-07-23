/*--------------------------------------------------------------------------
STRING.H

String functions for C251 Version 4.
Copyright (c) 1995-2007 Keil Elektronik GmbH and Keil Software, Inc.
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

#if (__C251__ >= 200) 
extern char *strcat (char *s1, const char *s2) reentrant;
extern char *strncat (char *s1, const char *s2, size_t n) reentrant;

extern char strcmp (const char *s1, const char *s2) reentrant;
extern char strncmp (const char *s1, const char *s2, size_t n) reentrant;

extern char *strcpy (char *s1, const char *s2) reentrant;
extern char *strncpy (char *s1, const char *s2, size_t n) reentrant;

extern size_t strlen (const char *) reentrant;

extern char *strchr (const char *s, char c) reentrant;
extern int strpos (const char *s, char c) reentrant;
extern char *strrchr (const char *s, char c) reentrant;
extern int strrpos (const char *s, char c) reentrant;

extern size_t strspn (const char *s, const char *set) reentrant;
extern size_t strcspn (const char *s, const char *set) reentrant;
extern char *strpbrk (const char *s, const char *set) reentrant;
extern char *strrpbrk (const char *s, const char *set) reentrant;

extern char memcmp (const void *s1, const void *s2, size_t n) reentrant;
extern void *memcpy (void *s1, const void *s2, size_t n) reentrant;
extern void *memchr (const void *s, char val, size_t n) reentrant;
extern void *memccpy (void *s1, const void *s2, char val, size_t n) reentrant;
extern void *memmove (void *s1, const void *s2, size_t n) reentrant;
extern void *memset  (void *s, char val, size_t n) reentrant;

extern void far   *fmemset  (void far *s,   char val, unsigned int n) reentrant;
extern void xdata *xmemset  (void xdata *s, char val, unsigned int n) reentrant;
extern void far   *fmemcpy  (void far *s1,  void far *s2, unsigned int n) reentrant;
extern void xdata *xmemcpy  (void xdata *s1, void xdata *s2, unsigned int n) reentrant;

extern unsigned long hstrlen (const char huge *s)  reentrant;
extern          char hstrcmp (const char huge *s1, const char huge *s2)  reentrant;
extern    char huge *hstrcpy (char huge *s1, const char huge *s2)  reentrant;

#pragma PARM4  // allow a maximum of 4 long as register parameters
extern char huge *hstrncpy (char huge *s1, const char huge *s2, unsigned long n) reentrant; 

extern      char  hmemcmp (const void huge *s1, const void huge *s2, unsigned long len) reentrant;
extern void huge *hmemcpy (void huge *s1, const void huge *s2, unsigned long len) reentrant;
extern void huge *hmemchr (const void huge *ptr, char val, unsigned long len) reentrant;
extern char huge *hmemccpy (char huge *dest, const char huge *src, char val, unsigned long len) reentrant;
extern void huge *hmemmove (void huge *s1, const void huge *s2, unsigned long len) reentrant;
extern void huge *hmemset (void huge *ptr, char val, unsigned long len) reentrant;

#else
extern char *strcat (char *s1, char *s2);
extern char *strncat (char *s1, char *s2, int n);

extern char strcmp (char *s1, char *s2);
extern char strncmp (char *s1, char *s2, int n);

extern char *strcpy (char *s1, char *s2);
extern char *strncpy (char *s1, char *s2, int n);

extern int strlen (char *);

extern char *strchr (const char *s, char c);
extern int strpos (const char *s, char c);
extern char *strrchr (const char *s, char c);
extern int strrpos (const char *s, char c);

extern int strspn (char *s, char *set);
extern int strcspn (char *s, char *set);
extern char *strpbrk (char *s, char *set);
extern char *strrpbrk (char *s, char *set);

extern char memcmp (void *s1, void *s2, int n);
extern void *memcpy (void *s1, void *s2, int n);
extern void *memchr (void *s, char val, int n);
extern void *memccpy (void *s1, void *s2, char val, int n);
extern void *memmove (void *s1, void *s2, int n);
extern void *memset  (void *s, char val, int n);

#endif

#pragma RESTORE

/*--------------------------------------------------------------------------
CTYPE.H

Prototypes for character functions for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#pragma SAVE
#pragma PARM251

#if __C251__ >= 200
extern bit isalpha (unsigned char) reentrant;
extern bit isalnum (unsigned char) reentrant;
extern bit iscntrl (unsigned char) reentrant;
extern bit isdigit (unsigned char) reentrant;
extern bit isgraph (unsigned char) reentrant;
extern bit isprint (unsigned char) reentrant;
extern bit ispunct (unsigned char) reentrant;
extern bit islower (unsigned char) reentrant;
extern bit isupper (unsigned char) reentrant;
extern bit isspace (unsigned char) reentrant;
extern bit isxdigit (unsigned char) reentrant;
extern unsigned char tolower (unsigned char) reentrant;
extern unsigned char toupper (unsigned char) reentrant;
extern unsigned char toint (unsigned char) reentrant;
#else
extern bit isalpha (unsigned char);
extern bit isalnum (unsigned char);
extern bit iscntrl (unsigned char);
extern bit isdigit (unsigned char);
extern bit isgraph (unsigned char);
extern bit isprint (unsigned char);
extern bit ispunct (unsigned char);
extern bit islower (unsigned char);
extern bit isupper (unsigned char);
extern bit isspace (unsigned char);
extern bit isxdigit (unsigned char);
extern unsigned char tolower (unsigned char);
extern unsigned char toupper (unsigned char);
extern unsigned char toint (unsigned char);
#endif

#define _tolower(c) ( (c)-'A'+'a' )
#define _toupper(c) ( (c)-'a'+'A' )
#define toascii(c)  ( (c) & 0x7F )

#pragma RESTORE

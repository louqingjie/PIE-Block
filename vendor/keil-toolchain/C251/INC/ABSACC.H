/*--------------------------------------------------------------------------
ABSACC.H

Direct access to 8051 & 251 memory areas for C251 Version 3.
Copyright (c) 1995-2001 Keil Elektronik GmbH and Keil Software, Inc.
All rights reserved.
--------------------------------------------------------------------------*/

#define CBYTE ((unsigned char volatile code  *) 0)
#define DBYTE ((unsigned char volatile data  *) 0)
#define PBYTE ((unsigned char volatile pdata *) 0) /* for C51 compatiblity */
#define XBYTE ((unsigned char volatile xdata *) 0)
#define NBYTE ((unsigned char volatile near *)  0)
#if __C251__ >= 200
#define HBYTE ((unsigned char volatile huge *)  0)
#endif


/* Note: this macros are defined for C51 compatiblity, you may use for  */
/*       new designs the ARRAY or VAR macros defined below              */

#define CWORD ((unsigned int volatile code  *) 0)
#define DWORD ((unsigned int volatile data  *) 0)
#define PWORD ((unsigned int volatile pdata *) 0)
#define XWORD ((unsigned int volatile xdata *) 0)
#define NWORD ((unsigned int volatile near *)  0)
#if __C251__ >= 200
#define HWORD ((unsigned int volatile huge *)  0)
#endif


#if __C251__ >= 200
#define CVAR(object, addr)   (*((object volatile code *) (addr)))
#define CARRAY(object, base) ((object volatile code *) (base))
#define DVAR(object, addr)   (*((object volatile data *) (addr)))
#define DARRAY(object, base) ((object volatile data *) (base))
#define HVAR(object, addr)   (*((object volatile huge *) (addr)))
#define HARRAY(object, base) ((object volatile huge *) (base))
#define NVAR(object, addr)   (*((object volatile near *) (addr)))
#define NARRAY(object, base) ((object volatile near *) (base))
#define XVAR(object, addr)   (*((object volatile xdata *) (addr)))
#define XARRAY(object, base) ((object volatile xdata *) (base))
#endif

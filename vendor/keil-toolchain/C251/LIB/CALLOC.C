/*-----------------------------------------------------------------------------
 *  CALLOC.C is part of the C251 Compiler package from Keil Software.
 *  Copyright (c) 1995-2000 Keil Software.  All rights reserved.
 *---------------------------------------------------------------------------*/

#include <stdlib.h>
#include <string.h>

#pragma functions (static)

#if defined (XMEM)  
#define MTYP          xdata
#define init_mempool  xinit_mempool
#define calloc        xcalloc
#define malloc        xmalloc
#define free          xfree
#define realloc       xrealloc
#define memset        xmemset
#define __mp__        __xmp__
#elif defined (FMEM)
#define MTYP          far
#define init_mempool  finit_mempool
#define calloc        fcalloc
#define malloc        fmalloc
#define free          ffree
#define realloc       frealloc
#define memset        fmemset
#define __mp__        __fmp__
#else
#define MTYP
#endif


void MTYP *calloc (unsigned int size, unsigned int len)  {
  void MTYP *p;

  size *= len;
  p = malloc (size);
  if (p)  memset (p, 0, size);
  return (p);
}


/*-----------------------------------------------------------------------------
REALLOC.C is part of the C251 Compiler package from Keil Software.
Copyright (c) 1995-2000 Keil Software.  All rights reserved.
-----------------------------------------------------------------------------*/
#include <string.h>
#include <stdlib.h>

#pragma functions (static)

#if defined (XMEM)  
  #define MTYP          xdata
  #define init_mempool  xinit_mempool
  #define calloc        xcalloc
  #define malloc        xmalloc
  #define free          xfree
  #define realloc       xrealloc
  #define __mp__        __xmp__
  #define memcpy        xmemcpy
#elif defined (FMEM)
  #define MTYP          far
  #define init_mempool  finit_mempool
  #define calloc        fcalloc
  #define malloc        fmalloc
  #define free          ffree
  #define realloc       frealloc
  #define __mp__        __fmp__
  #define memcpy        fmemcpy
#else
  #if (__MODEL__ == 3 || __MODEL__ == 4)   /* TINY & XTINY */
    #define MTYP          near
  #else
    #define MTYP          far
  #endif
#endif

struct __mp__  {                      /* memory pool */
  struct __mp__ MTYP    *next;        /* single-linked list */
  unsigned int            len;        /* length of following block */
};

extern void MTYP * MTYP __mp__;       /* Memory Pool Header */
#define	HLEN	(sizeof(struct __mp__))

/*  Memory pool header:  __mp__ points to the first available.
 *
 *  Note that the list is maintained in address order.  __mp__ points to the
 *  block with the lowest address.  That block points to the block with the
 *  next higher address and so on.                                          */

#define MIN_BLOCK	(HLEN * 4)

void MTYP *realloc (void MTYP *oldp, unsigned int size)  {
#define p   ((struct __mp__ MTYP *) oldp)   
#define p0  ((struct __mp__ MTYP *)&p[-1]) /* block to realloc */
  void MTYP *newp;

  newp = malloc (size);
  if (!newp) return (NULL);
  if (oldp)  {
    if (size > p0->len)  size = p0->len;
    memcpy (newp, oldp, size);
    free (oldp);
  }
  return (newp);
}



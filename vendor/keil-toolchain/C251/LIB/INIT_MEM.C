/*-----------------------------------------------------------------------------
 *  INIT_MEM.C is part of the C251 Compiler package from Keil Software.
 *  Copyright (c) 1995 - 2016 Keil Software.  All rights reserved.
 *---------------------------------------------------------------------------*/

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
#elif defined (FMEM)
  #define MTYP          far
  #define init_mempool  finit_mempool
  #define calloc        fcalloc
  #define malloc        fmalloc
  #define free          ffree
  #define realloc       frealloc
  #define __mp__        __fmp__
#else
  #if (__MODEL__ == 3 || __MODEL__ == 4)   /* TINY & XTINY */
    #define MTYP          near
  #else
    #define MTYP          far
  #endif
#endif

/*
 * Memory pool block structure and typedefs.
 * Memory is laid out as follows:
 *
 * {[NEXT | LEN] [BLOCK (LEN bytes)]} {[NEXT | LEN][BLOCK] } ...
 *
 * Note that the size of a node is:
 *          mp.len + sizeof (struct mp)
 */

struct __mp__  {                   /* memory pool */
  struct __mp__ MTYP *next;        /* single-linked list */
  unsigned int         len;        /* length of following block */
};

extern void MTYP * MTYP __mp__;    /* Memory Pool Head */

#define HLEN  (sizeof (struct __mp__))

/*
 *  Memory pool headers.  __mp__ points to the first available block or is
 *  NULL if there are no free blocks.
 *
 *  Note that the list is maintained in address order.  __mp__ points to the
 *  block with the lowest address.  That block points to the block with the
 *  next higher address and so on.
 */

void init_mempool (
  void MTYP *pool,           /* address of the memory pool  */
  unsigned int size)  {      /* size of the pool in bytes   */

#if defined (XMEM)
/*  If the pool points to the beginning of a memory area (NULL), change
 *  it to point to 1 and decrease the pool size by 1 byte.                 */

  if (!pool)  {
    pool = ((void MTYP *) 1);
    size--;
  }
#endif

/*  Set the __mp__ to point to the beginning of the pool and set
 *  the pool size.                                                         */

  __mp__ = pool;

/*  Set the link of the block in the pool to NULL (since it's the only
 *  block) and initialize the size of its data area.                       */

  ((struct __mp__ MTYP *) pool)->next       = NULL;
  ((struct __mp__ MTYP *) pool)->len        = size - HLEN;
}

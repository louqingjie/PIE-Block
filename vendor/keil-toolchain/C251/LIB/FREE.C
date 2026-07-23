/*-----------------------------------------------------------------------------
 *  FREE.C is part of the C251 Compiler package from Keil Software.
 *  Copyright (c) 1995-2016 Keil Software.  All rights reserved.
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

struct __mp__  {                      /* memory pool */
  struct __mp__ MTYP    *next;        /* single-linked list */
  unsigned int            len;        /* length of following block */
};

extern void MTYP * MTYP __mp__;       /* Memory Pool Header */

#define HLEN    (sizeof(struct __mp__))

/*  Memory pool headers.  __mp__ points to the first available block or is
 *  NULL if there are no free blocks.
 *
 *  Note that the list is maintained in address order.  AVAIL points to the
 *  block with the lowest address.  That block points to the block with the
 *  next higher address and so on.                                          */


void free (void MTYP *memp)  {
/*  FREE attempts to organize Q, P0, and P so that Q < P0 < P.  Then, P0 is
 *  inserted into the free list so that the list is maintained in address
 *  order.
 *
 *  FREE also attempts to consolidate small blocks into the largest block
 *  possible.  So, after allocating all memory and freeing all memory,
 *  you will have a single block that is the size of the memory pool.  The
 *  overhead for the merge is very minimal.                                */

  struct __mp__ MTYP *q;                  /* ptr to free block */
  struct __mp__ MTYP *p;                  /* q->next */
#define p0 ((struct __mp__ MTYP *) memp)  /* block to free */

/*  If the user tried to free NULL, get out now.  Otherwise, get the address
 *  of the header of the memp block (P0).  Then, try to locate Q and P such
 *  that Q < P0 < P.                                                       */

  if (!memp)
    return;

  memp = &p0[-1];             /* get address of header */

/*  Initialize.  Q = Location of first available block.                    */
  q = __mp__;
  if (!q)  {                  /* no block available yet */
    __mp__   = p0;            /* this block is now the only free one */
    p0->next = NULL;
    return;
  }

/*  B1. If P0 is before Q the block to free is before the first available
 *  block. Set P to Q, clear Q, initialize P0 as first available block.    */

  if (p0 < q)  {
    __mp__ = p0;              /* this block is now the first free one */
    p      = q;
    q      = NULL;            /* there is no lower block, this is the first */
  } else {

/*  B2. Advance P. Hop through the list until we find a free block that is
 *  located in memory BEHIND the block we're trying to free.                */

    while (1)  {
      p = q->next;
      if (!p || p > memp)     /* end of chain or behind the one to be freed */
        break;
      q = p;
    }
  }

/*  B3. Check upper bound. If P0 and P are contiguous, merge block P into
 *  block P0.                                                              */

  if (p && (((char MTYP *)p0) + p0->len + HLEN == (char MTYP *)p))  {
    p0->len += p->len + HLEN; /* merge the two blocks */
    p0->next = p->next;
  } else
    p0->next = p;             /* chain to next free block */

/*  B4. Check lower bound. If Q and P0 are contiguous, merge P0 into Q.  */

  if (q) {                    /* there is a lower bound before this one */
    if (((char MTYP *)q) + q->len + HLEN == (char MTYP *)p0)  {
      q->len += p0->len + HLEN; /* merge the two blocks */
      q->next = p0->next;
    } else
      q->next = p0;           /* chain us behind the lower free one */
  }
}

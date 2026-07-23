/*-----------------------------------------------------------------------------
 *  MALLOC.C is part of the C251 Compiler package from Keil Software.
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

/*  Memory pool header:  __mp__ points to the first available.
 *
 *  Note that the list is maintained in address order.  __mp__ points to the
 *  block with the lowest address.  That block points to the block with the
 *  next higher address and so on.                                          */

#define MIN_BLOCK   (HLEN * 4)

void MTYP *malloc (unsigned int size)   {
  struct __mp__ MTYP *q;    /* ptr to free block */
  struct __mp__ MTYP *p;    /* q->next */
  unsigned int k;           /* space remaining in the allocated block */

/*  Initialization:  Q is the pointer to the next available block.          */
  q = (struct __mp__ MTYP *) &__mp__;

/*  End-Of-List:  P points to the next block. If that block does not
 *  exist (P==NULL) we are at the end of the list.                          */

  while (1)  {
    p = q->next;
    if (!p)
      return NULL;          /* FAILURE */

/*  Found Space:  If block is large enough, reserve if.  Otherwise, copy P
 *  to Q and try the next free block.                                       */
    if (p->len >= size)
      break;
    q = p;
  }

/*  Reserve P:  Use at least part of the P block to satisfy the allocation
 *  request.  At this time, the following pointers are setup:
 *  P points to the block from which we allocate Q->next points to P        */

  k = p->len - size;        /* calc. remaining bytes in block */

  if (k < MIN_BLOCK)  {     /* rem. bytes too small for new block */
    q->next = p->next;      /* take whole remaining block */
    return &p[1];           /* SUCCESS */
  }

/*  Split P Block:  If P is larger than we need, we split P into two blocks:
 *  the leftover space and the allocated space.  That means, we need to
 *  create a header in the allocated space.                                 */

  k -= HLEN;
  p->len = k;

  q = (struct __mp__ MTYP *) (((char MTYP *)&p[1]) + k);
  q->len = size;
  return &q[1];             /* SUCCESS */
}

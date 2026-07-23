/***********************************************************************/
/*  This file is part of the C251 Compiler package                     */
/*  Copyright KEIL ELEKTRONIK GmbH 1990 - 2000                         */
/***********************************************************************/
/*                                                                     */
/*  PUTCHAR.C:  This routine is the general character output of C251.  */
/*                                                                     */
/*  To translate this file use C251 with the following invocation:     */
/*                                                                     */
/*     C51 PUTCHAR.C <memory model>                                    */
/*                                                                     */
/*  To link the modified PUTCHAR.OBJ file to your application use the  */
/*  following L251 invocation:                                         */
/*                                                                     */
/*     L251 <your object file list>, PUTCHAR.OBJ <controls>            */
/*                                                                     */
/***********************************************************************/

#include <reg251s.h>

#pragma functions (static)

#define XON  0x11
#define XOFF 0x13

char putchar (char c)  {

  if (c == '\n')  {
    if (RI)  {
      if (SBUF == XOFF)  {
        do  {
          RI = 0;
          while (!RI);
        }
        while (SBUF != XON);
        RI = 0; 
      }
    }
    while (!TI);
    TI = 0;
    SBUF = 0x0d;                         /* output CR  */
  }
  if (RI)  {
    if (SBUF == XOFF)  {
      do  {
        RI = 0;
        while (!RI);
      }
      while (SBUF != XON);
      RI = 0; 
    }
  }
  while (!TI);
  TI = 0;
  return (SBUF = c);
}

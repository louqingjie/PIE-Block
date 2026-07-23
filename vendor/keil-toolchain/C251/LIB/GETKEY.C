/***********************************************************************/
/*  This file is part of the C251 Compiler package                     */
/*  Copyright KEIL ELEKTRONIK GmbH 1993 - 2000                         */
/***********************************************************************/
/*                                                                     */
/*  GETKEY.C:  This routine is the general character input of C251.    */
/*                                                                     */
/*  To translate this file use C251 with the following invocation:     */
/*                                                                     */
/*     C251 GETKEY.C  <memory model>                                   */
/*                                                                     */
/*  To link the modified GETKEY.OBJ file to your application use the   */
/*  following L251 invocation:                                         */
/*                                                                     */
/*     L251 <your object file list>, GETKEY.OBJ <controls>             */
/*                                                                     */
/***********************************************************************/

#include <reg251s.h>

#pragma functions (static)

char _getkey ()  {
  char c;

  while (!RI);
  c = SBUF;
  RI = 0;
  return (c);
}

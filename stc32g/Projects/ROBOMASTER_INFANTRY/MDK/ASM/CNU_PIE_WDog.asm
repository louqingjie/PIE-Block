C251 COMPILER V5.60.0,  CNU_PIE_WDog                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_WDog
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_WDog.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_WDog.c XSMALL ROM(HUGE) BROWSE 
                    -INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTO
                    -R(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_WDog.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_WDog.obj) 

stmt  level    source

    1          /********************************************************************************************************
             -*************
    2           *     COPYRIGHT NOTICE
    3           *     Copyright (c) 2023,CNU_W.PIE
    4           *     All rights reserved.
    5           *     本库函数参考STC官方函数库
    6           *     除注明出处外，以下所有内容版权均属胖胖个人所有，未经允许，不得用于商业用途，
    7           *     修改内容时必须保留PP的版权声明。
    8           *     Except where indicated, the copyright of all the contents below is owned by PP 
    9           *     and can not be used for commercial purposes without permission. 
   10           *     The copyright notice of PP must be preserved when modifying the content.
   11           *
   12           * @file       CNU_PIE_WDog.c
   13           * @brief      WDog
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_WDog.h"
   20           /*******************************************************************************************************
             -*******************
   21           * @brief  看门狗初始化程序
   22           * @param[in]  WDT   结构参数,请参考WDT.h里的定义
   23          *********************************************************************************************************
             -******************/
   24          void WDog_Init(WDog_InitTypeDef *WDT)
   25          {
   26   1        if(WDT->WDT_Enable == ENABLE)   EN_WDT = 1; //使能看门狗
   27   1      
   28   1        WDT_PS_Set(WDT->WDT_PS);  //看门狗定时器时钟分频系数    WDT_SCALE_2,WDT_SCALE_4,WDT_SCALE_8,WDT_SCALE_16,WD
             -T_SCALE_32,WDT_SCALE_64,WDT_SCALE_128,WDT_SCALE_256
   29   1        if(WDT->WDT_IDLE_Mode == WDT_IDLE_STOP) IDL_WDT = 0;  //IDLE模式停止计数
   30   1        else                  IDL_WDT = 1;  //IDLE模式继续计数
   31   1      }
   32          
   33           /*******************************************************************************************************
             -*******************
   34           * @brief  清除看门狗初始化程序 喂狗
   35          *********************************************************************************************************
             -******************/
   36          void WDog_Clear (void)
   37          {
   38   1        CLR_WDT = 1;    // 喂狗
   39   1      }
C251 COMPILER V5.60.0,  CNU_PIE_WDog                                                       24/08/26  10:23:43  PAGE 2   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION WDog_Init? (BEGIN)
                                                ; SOURCE LINE # 24
;---- Variable 'WDT' assigned to Register 'DR0' ----
                                                ; SOURCE LINE # 26
000000 7E0BB0         MOV      R11,@DR0         ; A=R11
000003 B40103         CJNE     A,#01H,?C0001    ; A=R11
000006 A9D5C1         SETB     EN_WDT
               ?C0001:
                                                ; SOURCE LINE # 28
000009 29A00002       MOV      R10,@DR0+0x2
00000D 5EA007         ANL      R10,#07H
000010 E5C1           MOV      A,WDT_CONTR      ; A=R11
000012 54F8           ANL      A,#0F8H          ; A=R11
000014 4CBA           ORL      R11,R10          ; A=R11
000016 F5C1           MOV      WDT_CONTR,A      ; A=R11
                                                ; SOURCE LINE # 29
000018 29B00001       MOV      R11,@DR0+0x1     ; A=R11
00001C 7004           JNZ      ?C0002
00001E A9C3C1         CLR      IDL_WDT
000021 AA             ERET     
               ?C0002:
                                                ; SOURCE LINE # 30
000022 A9D3C1         SETB     IDL_WDT
                                                ; SOURCE LINE # 31
000025 AA             ERET     
;       FUNCTION WDog_Init? (END)

;       FUNCTION WDog_Clear? (BEGIN)
                                                ; SOURCE LINE # 36
                                                ; SOURCE LINE # 38
000026 A9D4C1         SETB     CLR_WDT
                                                ; SOURCE LINE # 39
000029 AA             ERET     
;       FUNCTION WDog_Clear? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =        42     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------     ------
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =    ------     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

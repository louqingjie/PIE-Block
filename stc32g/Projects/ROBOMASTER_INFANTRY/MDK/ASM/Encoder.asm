C251 COMPILER V5.60.0,  Encoder                                                            24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE Encoder
OBJECT MODULE PLACED IN .\Objects\ASM\Encoder.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\Encoder.c XSMALL ROM(HUGE) BROWSE INCDIR
                    -(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X10
                    -00) DEBUG CODE PRINT(.\ASM\Encoder.asm) TABS(2) OBJECT(.\Objects\ASM\Encoder.obj) 

stmt  level    source

    1          #include "Encoder.h"
    2          #include "CNU_PIE_TIMER.h"
    3          #include "CNU_PIE_GPIO.h"
    4          
    5          #define Encoder_Dir   P52  //编码器方向引脚定义 
    6          #define Encoder_Tim   P04  //编码器计数引脚定义 
    7          
    8          Encoder_TypeDef Encoder_X;
    9          
   10          void Encoder_Init(void)
   11          {
   12   1        Timer_Count_Init(TIMER3_P04);//编码器脉冲引脚捕获引脚初始化
   13   1        
   14   1        GPIO_Init(GPIO_P5 , GPIO_Pin_2 , GPIO_PullUp);
   15   1      }
   16          
   17          int Encoder_Count_Read(void)
   18          {
   19   1        Encoder_X.pouse = Timer_Count_Read(TIMER3_P04); 
   20   1        
   21   1        if(Encoder_Dir==0) Encoder_X.pouse_t = Encoder_X.pouse_t - (Encoder_X.pouse - Encoder_X.pouse_last);
   22   1                        else Encoder_X.pouse_t = Encoder_X.pouse_t + (Encoder_X.pouse - Encoder_X.pouse_last);
   23   1        
   24   1        Encoder_X.pouse_last = Encoder_X.pouse;
   25   1        
   26   1        return Encoder_X.pouse_t;
   27   1      }
   28          
   29          void Encoder_Clear(void)
   30          {
   31   1        Timer_Count_Clear(TIMER3_P04);
   32   1        Encoder_X.pouse = 0;
   33   1        Encoder_X.pouse_last = 0;
   34   1        Encoder_X.pouse_t = 0;
   35   1      }
C251 COMPILER V5.60.0,  Encoder                                                            24/08/26  10:23:43  PAGE 2   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION Encoder_Init? (BEGIN)
                                                ; SOURCE LINE # 10
                                                ; SOURCE LINE # 12
000000 7E340003       MOV      WR6,#03H
000004 9A000000    E  ECALL    Timer_Count_Init?
                                                ; SOURCE LINE # 14
000008 7E340005       MOV      WR6,#05H
00000C 7E240004       MOV      WR4,#04H
000010 6D11           XRL      WR2,WR2
000012 8A000000    E  EJMP     GPIO_Init?
;       FUNCTION Encoder_Init? (END)

;       FUNCTION Encoder_Count_Read? (BEGIN)
                                                ; SOURCE LINE # 17
                                                ; SOURCE LINE # 19
000016 7E340003       MOV      WR6,#03H
00001A 9A000000    E  ECALL    Timer_Count_Read?
00001E 7A370000    R  MOV      Encoder_X+3,WR6
                                                ; SOURCE LINE # 21
000022 A2CA           MOV      C,P52
000024 E4             CLR      A                ; A=R11
000025 33             RLC      A                ; A=R11
000026 7810           JNE      ?C0001
000028 7E270000    R  MOV      WR4,Encoder_X+3
00002C 9E270000    R  SUB      WR4,Encoder_X+5
000030 7E370000    R  MOV      WR6,Encoder_X+7
000034 9D32           SUB      WR6,WR4
000036 800C           SJMP     ?C0004
               ?C0001:
                                                ; SOURCE LINE # 22
000038 7E370000    R  MOV      WR6,Encoder_X+3
00003C 9E370000    R  SUB      WR6,Encoder_X+5
000040 2E370000    R  ADD      WR6,Encoder_X+7
               ?C0004:
000044 7A370000    R  MOV      Encoder_X+7,WR6
                                                ; SOURCE LINE # 24
000048 7E370000    R  MOV      WR6,Encoder_X+3
00004C 7A370000    R  MOV      Encoder_X+5,WR6
                                                ; SOURCE LINE # 26
000050 7E370000    R  MOV      WR6,Encoder_X+7
                                                ; SOURCE LINE # 27
000054 AA             ERET     
;       FUNCTION Encoder_Count_Read? (END)

;       FUNCTION Encoder_Clear? (BEGIN)
                                                ; SOURCE LINE # 29
                                                ; SOURCE LINE # 31
000055 7E340003       MOV      WR6,#03H
000059 9A000000    E  ECALL    Timer_Count_Clear?
                                                ; SOURCE LINE # 32
00005D 6D33           XRL      WR6,WR6
00005F 7A370000    R  MOV      Encoder_X+3,WR6
                                                ; SOURCE LINE # 33
000063 7A370000    R  MOV      Encoder_X+5,WR6
                                                ; SOURCE LINE # 34
000067 7A370000    R  MOV      Encoder_X+7,WR6
                                                ; SOURCE LINE # 35
00006B AA             ERET     
;       FUNCTION Encoder_Clear? (END)



Module Information          Static   Overlayable
------------------------------------------------
C251 COMPILER V5.60.0,  Encoder                                                            24/08/26  10:23:43  PAGE 3   

  code size            =    ------     ------
  ecode size           =       108     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =        11     ------
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

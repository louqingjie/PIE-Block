C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_TIMER
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_TIMER.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_TIMER.c XSMALL ROM(HUGE) BROWSE
                    - INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECT
                    -OR(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_TIMER.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_TIMER.obj) 

stmt  level    source

    1          /********************************************************************************************************
             -*************
    2           *     COPYRIGHT NOTICE
    3           *     Copyright (c) 2023,CNU_W.PIE
    4           *     All rights reserved.
    5           *
    6           *     除注明出处外，以下所有内容版权均属胖胖个人所有，未经允许，不得用于商业用途，
    7           *     修改内容时必须保留PP的版权声明。
    8           *     Except where indicated, the copyright of all the contents below is owned by PP 
    9           *     and can not be used for commercial purposes without permission. 
   10           *     The copyright notice of PP must be preserved when modifying the content.
   11           *
   12           * @file       CNU_PIE_TIMER.c
   13           * @brief      TIMER
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19           
   20          #include "CNU_PIE_TIMER.h"
   21          
   22           /*******************************************************************************************************
             -*******************
   23           * @brief  TIMER初始化函数
   24           * @exampleCode
   25           *      Timer_Count_Init(TIMER3_P04); //初始化定时器3 P04引脚作为计数引脚
   26           * @endcode
   27           * @param[in]  Timer_Count_Pin  定时器计数引脚
   28          *********************************************************************************************************
             -******************/
   29          void Timer_Count_Init(TIMER_COUNT_PIN_Enum Timer_Count_Pin)
   30          {
   31   1        switch(Timer_Count_Pin)
   32   1        {
   33   2          case TIMER0_P34:
   34   2            TL0 = 0;      TH0 = 0; 
   35   2            TMOD |= 0x04; TR0 = 1; break;
   36   2          case TIMER1_P35:
   37   2            TL1 = 0x00;   TH1 = 0x00;
   38   2            TMOD |= 0x40; TR1 = 1; break;
   39   2          case TIMER2_P12:
   40   2            T2L = 0x00;   T2H = 0x00;
   41   2            AUXR |= 0x18;          break;
   42   2          case TIMER3_P04:
   43   2            T3L = 0;      T3H = 0;
   44   2            T4T3M |= 0x0c;         break;
   45   2          case TIMER4_P06:
   46   2            T4L = 0;      T4H = 0;
   47   2            T4T3M |= 0xc0;         break;
   48   2        }
   49   1      }
   50          
   51           /*******************************************************************************************************
             -*******************
   52           * @brief  TIMER读取计数引脚脉冲数据
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 2   

   53           * @exampleCode
   54           *      Timer_Count_Read(TIMER3_P04); //定时器3 P04引脚读取计数数值
   55           * @endcode
   56           * @retval   count  计数数据
   57          *********************************************************************************************************
             -******************/
   58          
   59          uint16_t Timer_Count_Read(TIMER_COUNT_PIN_Enum Timer_Count_Pin)
   60          {
   61   1        uint16_t count = 0;
   62   1        switch(Timer_Count_Pin)
   63   1        {
   64   2          case TIMER0_P34:
   65   2               count = (uint16_t)TH0 << 8; count = ((uint8_t)TL0) | count;
   66   2          break;
   67   2          
   68   2          case TIMER1_P35:
   69   2               count = (uint16_t)TH1 << 8; count = ((uint8_t)TL1) | count;
   70   2          break;
   71   2          
   72   2          case TIMER2_P12:
   73   2               count = (uint16_t)T2H << 8; count = ((uint8_t)T2L) | count;
   74   2          break;
   75   2          
   76   2          case TIMER3_P04:
   77   2               count = (uint16_t)T3H << 8; count = ((uint8_t)T3L) | count;  
   78   2          break;
   79   2          
   80   2          case TIMER4_P06:
   81   2               count = (uint16_t)T4H << 8; count = ((uint8_t)T4L) | count;
   82   2          break;
   83   2        }
   84   1        return count;
   85   1      }
   86          
   87           /*******************************************************************************************************
             -*******************
   88           * @brief  TIMER计数清零
   89           * @exampleCode
   90           *      Timer_Count_Clear(TIMER3_P04); //初始化定时器3 P04引脚计数清零
   91           * @endcode
   92          *********************************************************************************************************
             -******************/
   93          void Timer_Count_Clear(TIMER_COUNT_PIN_Enum Timer_Count_Pin)
   94          { 
   95   1        switch(Timer_Count_Pin)
   96   1        {
   97   2          case TIMER0_P34:
   98   2            TR0 = 0; TH0 = 0; TL0 = 0; TR0 = 1; break;
   99   2          case TIMER1_P35:
  100   2            TR1 = 0; TH1 = 0; TL1 = 0; TR1 = 1; break;
  101   2          case TIMER2_P12:
  102   2            AUXR &= ~(1<<4);  T2H = 0; T2L = 0; AUXR |= 1<<4; break;
  103   2          case TIMER3_P04:
  104   2            T4T3M &= ~(1<<3); T3H = 0; T3L = 0; T4T3M |= (1<<3); break;
  105   2          case TIMER4_P06:
  106   2            T4T3M &= ~(1<<7); T4H = 0; T4L = 0; T4T3M |= (1<<7); break;
  107   2        }
  108   1      }
  109          
  110           /*******************************************************************************************************
             -*******************
  111           * @brief  TIMER定时中断初始化
  112           * @exampleCode
  113           *      PIT_Timer_Ms(TIM0 ， 20); //初始化定时器0作为中断源，20ms定时中断
  114           * @endcode
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 3   

  115           * @param[in]  Timer_CHN  定时器通道号
  116           * @param[in]  Time       中断时间
  117          *********************************************************************************************************
             -******************/
  118          void PIT_Timer_Ms(TIMER_CHN_Enum Timer_CHN , uint16_t Time)
  119          {
  120   1        uint16_t time_reg;
  121   1        time_reg = (uint16_t)65536 - (uint16_t)(FOSC / (12 * (1000 / Time)));
  122   1        switch(Timer_CHN)
  123   1        {
  124   2          case TIM0:
  125   2          TMOD |= 0x00; TL0 = time_reg; TH0 = time_reg >> 8; TR0 = 1; ET0 = 1;
  126   2          break;
  127   2          case TIM1:
  128   2          TMOD |= 0x00; TL1 = time_reg; TH1 = time_reg >> 8; TR1 = 1; ET1 = 1;
  129   2          break;
  130   2          case TIM2:
  131   2          T2L = time_reg;   T2H = time_reg >> 8;     AUXR |= 0x10; IE2 |= 0x04;
  132   2          break;
  133   2          case TIM3:
  134   2          T3L = time_reg;   T3H = time_reg >> 8;     T4T3M |= 0x08; IE2 |= 0x20;
  135   2          break;
  136   2          case TIM4:
  137   2          T4L = time_reg;   T4H = time_reg >> 8;     T4T3M |= 0x80; IE2 |= 0x40;
  138   2          break;
  139   2        }
  140   1      }
  141           /*******************************************************************************************************
             -*******************
  142           * @brief  TIMER定时中断清空中断标志位
  143           * @exampleCode
  144           *      PIT_Timer_Clear(TIM0); //TIM0中断标志位清空
  145           * @endcode
  146           * @param[in]  Timer_CHN  定时器通道号
  147          *********************************************************************************************************
             -******************/
  148          void PIT_Timer_Clear(TIMER_CHN_Enum Timer_CHN)
  149          {
  150   1        switch(Timer_CHN)
  151   1        {
  152   2          case TIM0: TCON &= ~0x80; break;
  153   2          case TIM1: TCON &= ~0x10; break;
  154   2          case TIM2: AUXINTIF &= ~0x01; break;
  155   2          case TIM3: AUXINTIF &= ~0x02; break;
  156   2          case TIM4: AUXINTIF &= ~0x04; break;
  157   2        }
  158   1      }
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 4   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION Timer_Count_Init? (BEGIN)
                                                ; SOURCE LINE # 29
;---- Variable 'Timer_Count_Pin' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 31
000000 1B34           DEC      WR6,#01H
000002 681C           JE       ?C0003
000004 1B34           DEC      WR6,#01H
000006 6824           JE       ?C0004
000008 1B34           DEC      WR6,#01H
00000A 682A           JE       ?C0005
00000C 1B34           DEC      WR6,#01H
00000E 6830           JE       ?C0006
000010 0B36           INC      WR6,#04H
000012 7835           JNE      ?C0001
                                                ; SOURCE LINE # 33
               ?C0002:
                                                ; SOURCE LINE # 34
000014 758A00         MOV      TL0,#00H
000017 758C00         MOV      TH0,#00H
                                                ; SOURCE LINE # 35
00001A 438904         ORL      TMOD,#04H
00001D D28C           SETB     TR0
00001F AA             ERET     
                                                ; SOURCE LINE # 36
               ?C0003:
                                                ; SOURCE LINE # 37
000020 758B00         MOV      TL1,#00H
000023 758D00         MOV      TH1,#00H
                                                ; SOURCE LINE # 38
000026 438940         ORL      TMOD,#040H
000029 D28E           SETB     TR1
00002B AA             ERET     
                                                ; SOURCE LINE # 39
               ?C0004:
                                                ; SOURCE LINE # 40
00002C 75D700         MOV      T2L,#00H
00002F 75D600         MOV      T2H,#00H
                                                ; SOURCE LINE # 41
000032 438E18         ORL      AUXR,#018H
000035 AA             ERET     
                                                ; SOURCE LINE # 42
               ?C0005:
                                                ; SOURCE LINE # 43
000036 75D500         MOV      T3L,#00H
000039 75D400         MOV      T3H,#00H
                                                ; SOURCE LINE # 44
00003C 43DD0C         ORL      T4T3M,#0CH
00003F AA             ERET     
                                                ; SOURCE LINE # 45
               ?C0006:
                                                ; SOURCE LINE # 46
000040 75D300         MOV      T4L,#00H
000043 75D200         MOV      T4H,#00H
                                                ; SOURCE LINE # 47
000046 43DDC0         ORL      T4T3M,#0C0H
                                                ; SOURCE LINE # 48
               ?C0001:
                                                ; SOURCE LINE # 49
000049 AA             ERET     
;       FUNCTION Timer_Count_Init? (END)

;       FUNCTION Timer_Count_Read? (BEGIN)
                                                ; SOURCE LINE # 59
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 5   

00004A 7D23           MOV      WR4,WR6
;---- Variable 'Timer_Count_Pin' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 60
                                                ; SOURCE LINE # 61
00004C 6D33           XRL      WR6,WR6
;---- Variable 'count' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 62
00004E 1B24           DEC      WR4,#01H
000050 681A           JE       ?C0009
000052 1B24           DEC      WR4,#01H
000054 6820           JE       ?C0010
000056 1B24           DEC      WR4,#01H
000058 6826           JE       ?C0011
00005A 1B24           DEC      WR4,#01H
00005C 682C           JE       ?C0012
00005E 0B26           INC      WR4,#04H
000060 7834           JNE      ?C0007
                                                ; SOURCE LINE # 64
               ?C0008:
                                                ; SOURCE LINE # 65
000062 E58C           MOV      A,TH0            ; A=R11
000064 7C6B           MOV      R6,R11           ; A=R11
000066 6C77           XRL      R7,R7
000068 E58A           MOV      A,TL0            ; A=R11
                                                ; SOURCE LINE # 66
00006A 8026           SJMP     ?C0035
                                                ; SOURCE LINE # 68
               ?C0009:
                                                ; SOURCE LINE # 69
00006C E58D           MOV      A,TH1            ; A=R11
00006E 7C6B           MOV      R6,R11           ; A=R11
000070 6C77           XRL      R7,R7
000072 E58B           MOV      A,TL1            ; A=R11
                                                ; SOURCE LINE # 70
000074 801C           SJMP     ?C0035
                                                ; SOURCE LINE # 72
               ?C0010:
                                                ; SOURCE LINE # 73
000076 E5D6           MOV      A,T2H            ; A=R11
000078 7C6B           MOV      R6,R11           ; A=R11
00007A 6C77           XRL      R7,R7
00007C E5D7           MOV      A,T2L            ; A=R11
                                                ; SOURCE LINE # 74
00007E 8012           SJMP     ?C0035
                                                ; SOURCE LINE # 76
               ?C0011:
                                                ; SOURCE LINE # 77
000080 E5D4           MOV      A,T3H            ; A=R11
000082 7C6B           MOV      R6,R11           ; A=R11
000084 6C77           XRL      R7,R7
000086 E5D5           MOV      A,T3L            ; A=R11
                                                ; SOURCE LINE # 78
000088 8008           SJMP     ?C0035
                                                ; SOURCE LINE # 80
               ?C0012:
                                                ; SOURCE LINE # 81
00008A E5D2           MOV      A,T4H            ; A=R11
00008C 7C6B           MOV      R6,R11           ; A=R11
00008E 6C77           XRL      R7,R7
000090 E5D3           MOV      A,T4L            ; A=R11
               ?C0035:
000092 0A2B           MOVZ     WR4,R11          ; A=R11
000094 4D32           ORL      WR6,WR4
                                                ; SOURCE LINE # 82
                                                ; SOURCE LINE # 83
               ?C0007:
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 6   

                                                ; SOURCE LINE # 84
                                                ; SOURCE LINE # 85
000096 AA             ERET     
;       FUNCTION Timer_Count_Read? (END)

;       FUNCTION Timer_Count_Clear? (BEGIN)
                                                ; SOURCE LINE # 93
;---- Variable 'Timer_Count_Pin' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 95
000097 1B34           DEC      WR6,#01H
000099 681B           JE       ?C0016
00009B 1B34           DEC      WR6,#01H
00009D 6822           JE       ?C0017
00009F 1B34           DEC      WR6,#01H
0000A1 682B           JE       ?C0018
0000A3 1B34           DEC      WR6,#01H
0000A5 6834           JE       ?C0019
0000A7 0B36           INC      WR6,#04H
0000A9 783C           JNE      ?C0014
                                                ; SOURCE LINE # 97
               ?C0015:
                                                ; SOURCE LINE # 98
0000AB C28C           CLR      TR0
0000AD 758C00         MOV      TH0,#00H
0000B0 758A00         MOV      TL0,#00H
0000B3 D28C           SETB     TR0
0000B5 AA             ERET     
                                                ; SOURCE LINE # 99
               ?C0016:
                                                ; SOURCE LINE # 100
0000B6 C28E           CLR      TR1
0000B8 758D00         MOV      TH1,#00H
0000BB 758B00         MOV      TL1,#00H
0000BE D28E           SETB     TR1
0000C0 AA             ERET     
                                                ; SOURCE LINE # 101
               ?C0017:
                                                ; SOURCE LINE # 102
0000C1 538EEF         ANL      AUXR,#0EFH
0000C4 75D600         MOV      T2H,#00H
0000C7 75D700         MOV      T2L,#00H
0000CA 438E10         ORL      AUXR,#010H
0000CD AA             ERET     
                                                ; SOURCE LINE # 103
               ?C0018:
                                                ; SOURCE LINE # 104
0000CE 53DDF7         ANL      T4T3M,#0F7H
0000D1 75D400         MOV      T3H,#00H
0000D4 75D500         MOV      T3L,#00H
0000D7 43DD08         ORL      T4T3M,#08H
0000DA AA             ERET     
                                                ; SOURCE LINE # 105
               ?C0019:
                                                ; SOURCE LINE # 106
0000DB 53DD7F         ANL      T4T3M,#07FH
0000DE 75D200         MOV      T4H,#00H
0000E1 75D300         MOV      T4L,#00H
0000E4 43DD80         ORL      T4T3M,#080H
                                                ; SOURCE LINE # 107
               ?C0014:
                                                ; SOURCE LINE # 108
0000E7 AA             ERET     
;       FUNCTION Timer_Count_Clear? (END)

;       FUNCTION PIT_Timer_Ms? (BEGIN)
                                                ; SOURCE LINE # 118
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 7   

;---- Variable 'Time' assigned to Register 'WR2' ----
0000E8 7DF3           MOV      WR30,WR6
;---- Variable 'Timer_CHN' assigned to Register 'WR30' ----
                                                ; SOURCE LINE # 119
                                                ; SOURCE LINE # 121
0000EA 7E3403E8       MOV      WR6,#03E8H
0000EE 8D32           DIV      WR6,WR4
0000F0 7E14000C       MOV      WR2,#0CH
0000F4 AD13           MUL      WR2,WR6
0000F6 6D00           XRL      WR0,WR0
0000F8 7E344000       MOV      WR6,#04000H
0000FC 7E2401FA       MOV      WR4,#01FAH
000100 9A000000    E  ECALL    ?C?SLDIV?
000104 7DE3           MOV      WR28,WR6
000106 6EE4FFFF       XRL      WR28,#0FFFFH
00010A 0BE4           INC      WR28,#01H
;---- Variable 'time_reg' assigned to Register 'WR28' ----
                                                ; SOURCE LINE # 122
00010C 1BF4           DEC      WR30,#01H
00010E 6823           JE       ?C0022
000110 1BF4           DEC      WR30,#01H
000112 6832           JE       ?C0023
000114 1BF4           DEC      WR30,#01H
000116 683F           JE       ?C0024
000118 1BF4           DEC      WR30,#01H
00011A 684C           JE       ?C0025
00011C 0BF6           INC      WR30,#04H
00011E 7858           JNE      ?C0020
                                                ; SOURCE LINE # 124
               ?C0021:
                                                ; SOURCE LINE # 125
000120 E589           MOV      A,TMOD           ; A=R11
000122 F589           MOV      TMOD,A           ; A=R11
000124 7D3E           MOV      WR6,WR28
000126 7CB7           MOV      R11,R7           ; A=R11
000128 F58A           MOV      TL0,A            ; A=R11
00012A 0A56           MOVZ     WR10,R6
00012C F58C           MOV      TH0,A            ; A=R11
00012E D28C           SETB     TR0
000130 D2A9           SETB     ET0
                                                ; SOURCE LINE # 126
000132 AA             ERET     
                                                ; SOURCE LINE # 127
               ?C0022:
                                                ; SOURCE LINE # 128
000133 E589           MOV      A,TMOD           ; A=R11
000135 F589           MOV      TMOD,A           ; A=R11
000137 7D3E           MOV      WR6,WR28
000139 7CB7           MOV      R11,R7           ; A=R11
00013B F58B           MOV      TL1,A            ; A=R11
00013D 0A56           MOVZ     WR10,R6
00013F F58D           MOV      TH1,A            ; A=R11
000141 D28E           SETB     TR1
000143 D2AB           SETB     ET1
                                                ; SOURCE LINE # 129
000145 AA             ERET     
                                                ; SOURCE LINE # 130
               ?C0023:
                                                ; SOURCE LINE # 131
000146 7D3E           MOV      WR6,WR28
000148 7CB7           MOV      R11,R7           ; A=R11
00014A F5D7           MOV      T2L,A            ; A=R11
00014C 0A56           MOVZ     WR10,R6
00014E F5D6           MOV      T2H,A            ; A=R11
000150 438E10         ORL      AUXR,#010H
000153 43AF04         ORL      IE2,#04H
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 8   

                                                ; SOURCE LINE # 132
000156 AA             ERET     
                                                ; SOURCE LINE # 133
               ?C0024:
                                                ; SOURCE LINE # 134
000157 7D3E           MOV      WR6,WR28
000159 7CB7           MOV      R11,R7           ; A=R11
00015B F5D5           MOV      T3L,A            ; A=R11
00015D 0A56           MOVZ     WR10,R6
00015F F5D4           MOV      T3H,A            ; A=R11
000161 43DD08         ORL      T4T3M,#08H
000164 43AF20         ORL      IE2,#020H
                                                ; SOURCE LINE # 135
000167 AA             ERET     
                                                ; SOURCE LINE # 136
               ?C0025:
                                                ; SOURCE LINE # 137
000168 7D3E           MOV      WR6,WR28
00016A 7CB7           MOV      R11,R7           ; A=R11
00016C F5D3           MOV      T4L,A            ; A=R11
00016E 0A56           MOVZ     WR10,R6
000170 F5D2           MOV      T4H,A            ; A=R11
000172 43DD80         ORL      T4T3M,#080H
000175 43AF40         ORL      IE2,#040H
                                                ; SOURCE LINE # 138
                                                ; SOURCE LINE # 139
               ?C0020:
                                                ; SOURCE LINE # 140
000178 AA             ERET     
;       FUNCTION PIT_Timer_Ms? (END)

;       FUNCTION PIT_Timer_Clear? (BEGIN)
                                                ; SOURCE LINE # 148
;---- Variable 'Timer_CHN' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 150
000179 1B34           DEC      WR6,#01H
00017B 6814           JE       ?C0028
00017D 1B34           DEC      WR6,#01H
00017F 6814           JE       ?C0029
000181 1B34           DEC      WR6,#01H
000183 6814           JE       ?C0030
000185 1B34           DEC      WR6,#01H
000187 6814           JE       ?C0031
000189 0B36           INC      WR6,#04H
00018B 7813           JNE      ?C0026
                                                ; SOURCE LINE # 152
               ?C0027:
00018D 53887F         ANL      TCON,#07FH
000190 AA             ERET     
                                                ; SOURCE LINE # 153
               ?C0028:
000191 5388EF         ANL      TCON,#0EFH
000194 AA             ERET     
                                                ; SOURCE LINE # 154
               ?C0029:
000195 53EFFE         ANL      AUXINTIF,#0FEH
000198 AA             ERET     
                                                ; SOURCE LINE # 155
               ?C0030:
000199 53EFFD         ANL      AUXINTIF,#0FDH
00019C AA             ERET     
                                                ; SOURCE LINE # 156
               ?C0031:
00019D 53EFFB         ANL      AUXINTIF,#0FBH
                                                ; SOURCE LINE # 157
               ?C0026:
C251 COMPILER V5.60.0,  CNU_PIE_TIMER                                                      24/08/26  10:23:43  PAGE 9   

                                                ; SOURCE LINE # 158
0001A0 AA             ERET     
;       FUNCTION PIT_Timer_Clear? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       417     ------
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

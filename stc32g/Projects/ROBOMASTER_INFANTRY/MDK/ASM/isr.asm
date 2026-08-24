C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE isr
OBJECT MODULE PLACED IN .\Objects\ASM\isr.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\USER\src\isr.c XSMALL ROM(HUGE) BROWSE INCDIR(..\..\..\Libraries\bo
                    -ards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X1000) DEBUG CODE PRINT(.
                    -\ASM\isr.asm) TABS(2) OBJECT(.\Objects\ASM\isr.obj) 

stmt  level    source

    1          /********************************************************************************************************
             -*************
    2           *     COPYRIGHT NOTICE
    3           *     Copyright (c) 2023,CNU_W.PIE
    4           *     All rights reserved.
    5           *
    6           *     除注明出处外，以下所有内容版权均属胖胖个人所有，未经允许，不得用�
             -�商业用途，
    7           *     修改内容时必须保留PP的版权声明。
    8           *     Except where indicated, the copyright of all the contents below is owned by PP
    9           *     and can not be used for commercial purposes without permission.
   10           *     The copyright notice of PP must be preserved when modifying the content.
   11           *
   12           * @file       isr.c
   13           * @brief      中断服务
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include <math.h>
   20          #include <stdio.h>
   21          #include <stdlib.h>
   22          
   23          #include "isr.h"
   24          #include "common.h"
   25          
   26          #include "CNU_PIE_UART.h"
   27          #include "CNU_PIE_EXTI.h"
   28          void UART1_Isr() interrupt 4
   29          {
   30   1        char dat;
   31   1        if (UART1_GET_TX_FLAG)
   32   1        {
   33   2          UART1_CLEAR_TX_FLAG;
   34   2          UART_BUSY[1] = 0;
   35   2        }
   36   1        if (UART1_GET_RX_FLAG)
   37   1        {
   38   2          UART1_CLEAR_RX_FLAG;
   39   2          uart_receive[0]++;
   40   2          dat = SBUF;
   41   2          // 接收数据寄存器为：SBUF
   42   2        }
   43   1      }
   44          void UART2_Isr() interrupt 8
   45          {
   46   1        if (UART2_GET_TX_FLAG)
   47   1        {
   48   2          UART2_CLEAR_TX_FLAG;
   49   2          UART_BUSY[2] = 0;
   50   2        }
   51   1        if (UART2_GET_RX_FLAG)
   52   1        {
   53   2          UART2_CLEAR_RX_FLAG;
   54   2          uart_receive[1]++;
C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 2   

   55   2          // 接收数据寄存器为：S2BUF
   56   2        }
   57   1      }
   58          void UART3_Isr() interrupt 17
   59          {
   60   1        if (UART3_GET_TX_FLAG)
   61   1        {
   62   2          UART3_CLEAR_TX_FLAG;
   63   2          UART_BUSY[3] = 0;
   64   2        }
   65   1        if (UART3_GET_RX_FLAG)
   66   1        {
   67   2          UART3_CLEAR_RX_FLAG;
   68   2          uart_receive[2]++;
   69   2          // 接收数据寄存器为：S3BUF
   70   2        }
   71   1      }
   72          void UART4_Isr() interrupt 18
   73          {
   74   1        if (UART4_GET_TX_FLAG)
   75   1        {
   76   2          UART4_CLEAR_TX_FLAG;
   77   2          UART_BUSY[4] = 0;
   78   2        }
   79   1        if (UART4_GET_RX_FLAG)
   80   1        {
   81   2          UART4_CLEAR_RX_FLAG;
   82   2          uart_receive[3]++;
   83   2          // 接收数据寄存器为：S4BUF;
   84   2        }
   85   1      }
   86          
   87          // void INT0_Isr() interrupt 0
   88          //{
   89          // }
   90          // void INT1_Isr() interrupt 2
   91          //{
   92          // }
   93          // void INT2_Isr() interrupt 10
   94          //{
   95          // }
   96          // void INT3_Isr() interrupt 11
   97          //{
   98          // }
   99          // void INT4_Isr() interrupt 16
  100          //{
  101          // }
  102          // void TM1_Isr() interrupt 3
  103          //{
  104          // }
  105          // void TM2_Isr() interrupt 12
  106          //{
  107          // }
  108          
  109          // void TM4_Isr() interrupt 20
  110          //{
  111          // }
  112          // void DMA_ADC_ISR_Handler (void) interrupt ADCDMA_VECTOR
  113          //{
  114          // }
  115          // void  INT0_Isr()  interrupt 0;
  116          // void  TM0_Isr()   interrupt 1;
  117          // void  INT1_Isr()  interrupt 2;id  TM1_Isr()   interrupt 3;
  118          // void  UART1_Isr() interrupt 4;
  119          // void  ADC_Isr()   interrupt 5;
  120          // void  LVD_Isr()   interrupt 6;
C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 3   

  121          // void  PCA_Isr()   interrupt 7;
  122          // void  UART2_Isr() interrupt 8;
  123          // void  SPI_Isr()   interrupt 9;
  124          // void  INT2_Isr()  interrupt 10;
  125          // void  INT3_Isr()  interrupt 11;
  126          // void  TM2_Isr()   interrupt 12;
  127          // void  INT4_Isr()  interrupt 16;
  128          // void  UART3_Isr() interrupt 17;
  129          // void  UART4_Isr() interrupt 18;
  130          // void  TM3_Isr()   interrupt 19;
  131          // void  TM4_Isr()   interrupt 20;
  132          // void  CMP_Isr()   interrupt 21;
  133          // void  I2C_Isr()   interrupt 24;
  134          // void  USB_Isr()   interrupt 25;
  135          // void  PWM1_Isr()  interrupt 26;
  136          // void  PWM2_Isr()  interrupt 27;
C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 4   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION UART1_Isr? (BEGIN)
                                                ; SOURCE LINE # 28
000000 CAB8           PUSH     R11              ; A=R11
000002 CA39           PUSH     WR6
                                                ; SOURCE LINE # 29
                                                ; SOURCE LINE # 31
000004 E598           MOV      A,SCON           ; A=R11
000006 30E108         JNB      ACC.1,?C0001
                                                ; SOURCE LINE # 33
000009 5398FD         ANL      SCON,#0FDH
                                                ; SOURCE LINE # 34
00000C E4             CLR      A                ; A=R11
00000D 7AB30000    E  MOV      UART_BUSY+1,R11  ; A=R11
                                                ; SOURCE LINE # 35
               ?C0001:
                                                ; SOURCE LINE # 36
000011 E598           MOV      A,SCON           ; A=R11
000013 30E00F         JNB      ACC.0,?C0002
                                                ; SOURCE LINE # 38
000016 5398FE         ANL      SCON,#0FEH
                                                ; SOURCE LINE # 39
000019 7E370000    E  MOV      WR6,uart_receive
00001D 0B34           INC      WR6,#01H
00001F 7A370000    E  MOV      uart_receive,WR6
                                                ; SOURCE LINE # 40
000023 E599           MOV      A,SBUF           ; A=R11
                                                ; SOURCE LINE # 42
               ?C0002:
000025 DA39           POP      WR6
000027 DAB8           POP      R11              ; A=R11
000029 32             RETI     
;       FUNCTION UART1_Isr? (END)

;       FUNCTION UART2_Isr? (BEGIN)
                                                ; SOURCE LINE # 44
00002A CAB8           PUSH     R11              ; A=R11
00002C CA39           PUSH     WR6
                                                ; SOURCE LINE # 46
00002E E59A           MOV      A,S2CON          ; A=R11
000030 30E108         JNB      ACC.1,?C0003
                                                ; SOURCE LINE # 48
000033 539AFD         ANL      S2CON,#0FDH
                                                ; SOURCE LINE # 49
000036 E4             CLR      A                ; A=R11
000037 7AB30000    E  MOV      UART_BUSY+2,R11  ; A=R11
                                                ; SOURCE LINE # 50
               ?C0003:
                                                ; SOURCE LINE # 51
00003B E59A           MOV      A,S2CON          ; A=R11
00003D 30E00D         JNB      ACC.0,?C0004
                                                ; SOURCE LINE # 53
000040 539AFE         ANL      S2CON,#0FEH
                                                ; SOURCE LINE # 54
000043 7E370000    E  MOV      WR6,uart_receive+2
000047 0B34           INC      WR6,#01H
000049 7A370000    E  MOV      uart_receive+2,WR6
                                                ; SOURCE LINE # 56
               ?C0004:
00004D DA39           POP      WR6
00004F DAB8           POP      R11              ; A=R11
000051 32             RETI     
;       FUNCTION UART2_Isr? (END)

C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 5   

;       FUNCTION UART3_Isr? (BEGIN)
                                                ; SOURCE LINE # 58
000052 CAB8           PUSH     R11              ; A=R11
000054 CA39           PUSH     WR6
                                                ; SOURCE LINE # 60
000056 E5AC           MOV      A,S3CON          ; A=R11
000058 30E108         JNB      ACC.1,?C0005
                                                ; SOURCE LINE # 62
00005B 53ACFD         ANL      S3CON,#0FDH
                                                ; SOURCE LINE # 63
00005E E4             CLR      A                ; A=R11
00005F 7AB30000    E  MOV      UART_BUSY+3,R11  ; A=R11
                                                ; SOURCE LINE # 64
               ?C0005:
                                                ; SOURCE LINE # 65
000063 E5AC           MOV      A,S3CON          ; A=R11
000065 30E00D         JNB      ACC.0,?C0006
                                                ; SOURCE LINE # 67
000068 53ACFE         ANL      S3CON,#0FEH
                                                ; SOURCE LINE # 68
00006B 7E370000    E  MOV      WR6,uart_receive+4
00006F 0B34           INC      WR6,#01H
000071 7A370000    E  MOV      uart_receive+4,WR6
                                                ; SOURCE LINE # 70
               ?C0006:
000075 DA39           POP      WR6
000077 DAB8           POP      R11              ; A=R11
000079 32             RETI     
;       FUNCTION UART3_Isr? (END)

;       FUNCTION UART4_Isr? (BEGIN)
                                                ; SOURCE LINE # 72
00007A CAB8           PUSH     R11              ; A=R11
00007C CA39           PUSH     WR6
                                                ; SOURCE LINE # 74
00007E E5FD           MOV      A,S4CON          ; A=R11
000080 30E108         JNB      ACC.1,?C0007
                                                ; SOURCE LINE # 76
000083 53FDFD         ANL      S4CON,#0FDH
                                                ; SOURCE LINE # 77
000086 E4             CLR      A                ; A=R11
000087 7AB30000    E  MOV      UART_BUSY+4,R11  ; A=R11
                                                ; SOURCE LINE # 78
               ?C0007:
                                                ; SOURCE LINE # 79
00008B E5FD           MOV      A,S4CON          ; A=R11
00008D 30E00D         JNB      ACC.0,?C0008
                                                ; SOURCE LINE # 81
000090 53FDFE         ANL      S4CON,#0FEH
                                                ; SOURCE LINE # 82
000093 7E370000    E  MOV      WR6,uart_receive+6
000097 0B34           INC      WR6,#01H
000099 7A370000    E  MOV      uart_receive+6,WR6
                                                ; SOURCE LINE # 84
               ?C0008:
00009D DA39           POP      WR6
00009F DAB8           POP      R11              ; A=R11
0000A1 32             RETI     
;       FUNCTION UART4_Isr? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =        16     ------
  ecode size           =       162     ------
  data size            =    ------     ------
C251 COMPILER V5.60.0,  isr                                                                24/08/26  10:23:16  PAGE 6   

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

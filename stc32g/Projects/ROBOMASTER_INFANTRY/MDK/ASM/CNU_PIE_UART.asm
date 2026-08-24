C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_UART
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_UART.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_UART.c XSMALL ROM(HUGE) BROWSE 
                    -INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTO
                    -R(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_UART.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_UART.obj) 

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
   12           * @file       CNU_PIE_UART.c
   13           * @brief      UART
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_UART.h"
   20          
   21          int uart_receive[4];
   22          uint8_t UART_BUSY[5];            // 串口接收忙标志位
   23          uint8_t uart1_tx_buff[UART1_TX_BUFFER_SIZE]; // 发送缓冲
   24          uint8_t uart1_rx_buff[UART1_RX_BUFFER_SIZE]; // 接收缓冲
   25          volatile uint8_t uart1_rx_head = 0;      // 环形缓冲区写入指针（ISR 更新）
   26          volatile uint8_t uart1_rx_tail = 0;      // 环形缓冲区读取指针（主循环更新）
   27          
   28          /********************************************************************************************************
             -******************
   29          * @brief  UART引脚初始化
   30          * @exampleCode
   31          *       UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
   32           //初始化串口1 波特率115200 发送引脚使用P31 接收引脚使用P30 ,使用定时器1作为�
             -�特率发生器
   33          * @endcode
   34          * @param[in]  UART_N        UART串口号
   35          * @param[in]  UART_Rx_Pin   RX引脚
   36          * @param[in]  UART_Tx_Pin   TX引脚
   37          * @param[in]  BaudRate      波特率
   38          * @param[in]  Timer_CHN     波特率发生器-定时器
   39          *********************************************************************************************************
             -******************/
   40          void UART_Init(UARTN_Enum UART_N, UART_PIN_Enum UART_Rx_Pin, UART_PIN_Enum UART_Tx_Pin, uint32_t BaudRate
             -, TIMER_CHN_Enum Timer_CHN)
   41          {
   42   1        uint16_t brt;
   43   1        brt = (uint16_t)(65536 - (FOSC / BaudRate / 4));
   44   1        switch (UART_N)
   45   1        {
   46   2        case UART_1:
   47   2        {
   48   3          if (TIM1 == Timer_CHN)
   49   3          {
   50   4            SCON |= 0x50;
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 2   

   51   4            TMOD |= 0x00;
   52   4            TL1 = brt;
   53   4            TH1 = brt >> 8;
   54   4            AUXR |= 0x40;
   55   4            TR1 = 1;
   56   4            UART_BUSY[1] = 0;
   57   4          }
   58   3          else if (TIM2 == Timer_CHN)
   59   3          {
   60   4            SCON |= 0x50;
   61   4            T2L = brt;
   62   4            T2H = brt >> 8;
   63   4            AUXR |= 0x15;
   64   4          }
   65   3          P_SW1 &= ~(0x03 << 6);
   66   3          if ((UART1_RX_P30 == UART_Rx_Pin) && (UART1_TX_P31 == UART_Tx_Pin))
   67   3            P_SW1 |= 0x00;
   68   3          else if ((UART1_RX_P36 == UART_Rx_Pin) && (UART1_TX_P37 == UART_Tx_Pin))
   69   3            P_SW1 |= 0x40;
   70   3          else if ((UART1_RX_P16 == UART_Rx_Pin) && (UART1_TX_P17 == UART_Tx_Pin))
   71   3            P_SW1 |= 0x80;
   72   3          else if ((UART1_RX_P43 == UART_Rx_Pin) && (UART1_TX_P44 == UART_Tx_Pin))
   73   3            P_SW1 |= 0xc0;
   74   3          UART_BUSY[1] = 0;
   75   3          ES = 1;
   76   3          break;
   77   3        }
   78   2        case UART_2:
   79   2        {
   80   3          if (TIM2 == Timer_CHN)
   81   3          {
   82   4            S2CON |= 0x10;
   83   4            T2L = brt;
   84   4            T2H = brt >> 8;
   85   4            AUXR |= 0x14;
   86   4          }
   87   3          P_SW2 &= ~(0x01 << 0);
   88   3          if ((UART2_RX_P10 == UART_Rx_Pin) && (UART2_TX_P11 == UART_Tx_Pin))
   89   3            P_SW2 |= 0x00;
   90   3          else if ((UART2_RX_P46 == UART_Rx_Pin) && (UART2_TX_P47 == UART_Tx_Pin))
   91   3            P_SW2 |= 0x01;
   92   3          UART_BUSY[2] = 0;
   93   3          ES2 = 1;
   94   3          break;
   95   3          break;
   96   3        }
   97   2        case UART_3:
   98   2        {
   99   3          if (TIM2 == Timer_CHN)
  100   3          {
  101   4            S3CON |= 0x10;
  102   4            T2L = brt;
  103   4            T2H = brt >> 8;
  104   4            AUXR |= 0x14;
  105   4          }
  106   3          else if (TIM3 == Timer_CHN)
  107   3          {
  108   4            S3CON |= 0x50;
  109   4            T3L = brt;
  110   4            T3H = brt >> 8;
  111   4            T4T3M |= 0x0a;
  112   4            P_SW2 &= ~(0x01 << 1);
  113   4          }
  114   3          if ((UART3_RX_P00 == UART_Rx_Pin) && (UART3_TX_P01 == UART_Tx_Pin))
  115   3            P_SW2 |= 0x00;
  116   3          else if ((UART3_RX_P50 == UART_Rx_Pin) && (UART3_TX_P51 == UART_Tx_Pin))
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 3   

  117   3            P_SW2 |= 0x02;
  118   3          UART_BUSY[3] = 0;
  119   3          ES3 = 1;
  120   3          break;
  121   3        }
  122   2        case UART_4:
  123   2        {
  124   3          if (TIM2 == Timer_CHN)
  125   3          {
  126   4            S4CON |= 0x10;
  127   4            T2L = brt;
  128   4            T2H = brt >> 8;
  129   4            AUXR |= 0x14;
  130   4          }
  131   3          else if (TIM4 == Timer_CHN)
  132   3          {
  133   4            S4CON |= 0x50;
  134   4            T4L = brt;
  135   4            T4H = brt >> 8;
  136   4            T4T3M |= 0xa0;
  137   4          }
  138   3          P_SW2 &= ~(0x01 << 2);
  139   3          if ((UART4_RX_P02 == UART_Rx_Pin) && (UART4_TX_P03 == UART_Tx_Pin))
  140   3            P_SW2 |= 0x00;
  141   3          else if ((UART4_RX_P52 == UART_Rx_Pin) && (UART4_TX_P53 == UART_Tx_Pin))
  142   3          {
  143   4            P5M0 = 0x00;
  144   4            P5M1 = 0x01 << 2;
  145   4            P_SW2 |= 0x04;
  146   4          }
  147   3          UART_BUSY[4] = 0;
  148   3          ES4 = 1;
  149   3          break;
  150   3        }
  151   2        }
  152   1      }
  153          /********************************************************************************************************
             -******************
  154           * @brief  UART发送一个字节
  155           * @exampleCode
  156           *       UART_PutChar(UART_1, 0xff);        //串口1发送0xff
  157           * @endcode
  158           * @param[in]  UART_N        UART串口号
  159           * @param[in]  data_t        发送的数据
  160           ********************************************************************************************************
             -*******************/
  161          void UART_PutChar(UARTN_Enum UART_N, uint8_t data_t)
  162          {
  163   1        switch (UART_N)
  164   1        {
  165   2        case UART_1:
  166   2          while (UART_BUSY[1])
  167   2            ;
  168   2          UART_BUSY[1] = 1;
  169   2          SBUF = data_t;
  170   2          break;
  171   2        case UART_2:
  172   2          while (UART_BUSY[2])
  173   2            ;
  174   2          UART_BUSY[2] = 1;
  175   2          S2BUF = data_t;
  176   2          break;
  177   2        case UART_3:
  178   2          while (UART_BUSY[3])
  179   2            ;
  180   2          UART_BUSY[3] = 1;
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 4   

  181   2          S3BUF = data_t;
  182   2          break;
  183   2        case UART_4:
  184   2          while (UART_BUSY[4])
  185   2            ;
  186   2          UART_BUSY[4] = 1;
  187   2          S4BUF = data_t;
  188   2          break;
  189   2        }
  190   1      }
  191          /********************************************************************************************************
             -******************
  192           * @brief  UART发送数组
  193           * @exampleCode
  194           *       UART_PutBuff(UART_1, &data[0] ,5);        //串口1发送data数组 发送五个字节
  195           * @endcode
  196           * @param[in]  UART_N        UART串口号
  197           * @param[in]  *p            地址
  198           * @param[in]  lenth         数据长度
  199           ********************************************************************************************************
             -*******************/
  200          void UART_PutBuff(UARTN_Enum UART_N, uint8_t *p, uint16_t lenth)
  201          {
  202   1        while (lenth--)
  203   1          UART_PutChar(UART_N, *p++);
  204   1      }
  205          /********************************************************************************************************
             -******************
  206           * @brief  UART发送字符串
  207           * @exampleCode
  208           *       UART_PutBuff(UART_1,“w.pie”);        //串口1发送字符串
  209           * @endcode
  210           * @param[in]  UART_N        UART串口号
  211           * @param[in]  *str          字符串/字符串首地址
  212           ********************************************************************************************************
             -*******************/
  213          void UART_PutStr(UARTN_Enum UART_N, uint8_t *str)
  214          {
  215   1        while (*str)
  216   1        {
  217   2          UART_PutChar(UART_N, *str++);
  218   2        }
  219   1      }
  220          
  221          uint8_t UART_Receive_t(UARTN_Enum UART_N)
  222          {
  223   1        uint8_t data_t;
  224   1        switch (UART_N)
  225   1        {
  226   2        case UART_1:
  227   2          data_t = SBUF;
  228   2          return data_t;
  229   2          break;
  230   2        case UART_2:
  231   2          data_t = S2BUF;
  232   2          return data_t;
  233   2          break;
  234   2        case UART_3:
  235   2          data_t = S3BUF;
  236   2          return data_t;
  237   2          break;
  238   2        case UART_4:
  239   2          data_t = S4BUF;
  240   2          return data_t;
  241   2          break;
  242   2        default:
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 5   

  243   2          return 0;
  244   2          break;
  245   2        }
  246   1      }
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 6   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION UART_Init? (BEGIN)
                                                ; SOURCE LINE # 40
000000 7DD0           MOV      WR26,WR0
;---- Variable 'Timer_CHN' assigned to Register 'WR26' ----
000002 7DF1           MOV      WR30,WR2
;---- Variable 'UART_Tx_Pin' assigned to Register 'WR30' ----
000004 7DE2           MOV      WR28,WR4
;---- Variable 'UART_Rx_Pin' assigned to Register 'WR28' ----
000006 7DC3           MOV      WR24,WR6
;---- Variable 'UART_N' assigned to Register 'WR24' ----
                                                ; SOURCE LINE # 41
                                                ; SOURCE LINE # 43
000008 7E0F0000    R  MOV      DR0,BaudRate
00000C 7E344000       MOV      WR6,#04000H
000010 7E2401FA       MOV      WR4,#01FAH
000014 9A000000    E  ECALL    ?C?ULDIV?
000018 7402           MOV      A,#02H           ; A=R11
00001A 7F01           MOV      DR0,DR4
               ?C0068:
00001C 1E14           SRL      WR2
00001E 1E04           SRL      WR0
000020 5003           JNC      ?C0069
000022 4E2080         ORL      R2,#080H
               ?C0069:
000025 14             DEC      A                ; A=R11
000026 78F4           JNE      ?C0068
000028 6D33           XRL      WR6,WR6
00002A 7E240001       MOV      WR4,#01H
00002E 9F10           SUB      DR4,DR0
;---- Variable 'brt' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 44
000030 1BC4           DEC      WR24,#01H
000032 7803        R  JNE      $ + 5H
000034 020000      R  LJMP     ?C0003
000037 1BC4           DEC      WR24,#01H
000039 7803        R  JNE      $ + 5H
00003B 020000      R  LJMP     ?C0004
00003E 1BC4           DEC      WR24,#01H
000040 7803        R  JNE      $ + 5H
000042 020000      R  LJMP     ?C0005
000045 2EC40003       ADD      WR24,#03H
000049 6803        R  JE       $ + 5H
00004B 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 46
               ?C0002:
                                                ; SOURCE LINE # 48
00004E BED40001       CMP      WR26,#01H
000052 781B           JNE      ?C0006
                                                ; SOURCE LINE # 50
000054 439850         ORL      SCON,#050H
                                                ; SOURCE LINE # 51
000057 E589           MOV      A,TMOD           ; A=R11
000059 F589           MOV      TMOD,A           ; A=R11
                                                ; SOURCE LINE # 52
00005B 7CB7           MOV      R11,R7           ; A=R11
00005D F58B           MOV      TL1,A            ; A=R11
                                                ; SOURCE LINE # 53
00005F 0A56           MOVZ     WR10,R6
000061 F58D           MOV      TH1,A            ; A=R11
                                                ; SOURCE LINE # 54
000063 438E40         ORL      AUXR,#040H
                                                ; SOURCE LINE # 55
000066 D28E           SETB     TR1
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 7   

                                                ; SOURCE LINE # 56
000068 E4             CLR      A                ; A=R11
000069 7AB30000    R  MOV      UART_BUSY+1,R11  ; A=R11
                                                ; SOURCE LINE # 57
00006D 8014           SJMP     ?C0007
               ?C0006:
                                                ; SOURCE LINE # 58
00006F BED40002       CMP      WR26,#02H
000073 780E           JNE      ?C0007
                                                ; SOURCE LINE # 60
000075 439850         ORL      SCON,#050H
                                                ; SOURCE LINE # 61
000078 7CB7           MOV      R11,R7           ; A=R11
00007A F5D7           MOV      T2L,A            ; A=R11
                                                ; SOURCE LINE # 62
00007C 0A56           MOVZ     WR10,R6
00007E F5D6           MOV      T2H,A            ; A=R11
                                                ; SOURCE LINE # 63
000080 438E15         ORL      AUXR,#015H
                                                ; SOURCE LINE # 64
               ?C0007:
                                                ; SOURCE LINE # 65
000083 53A23F         ANL      P_SW1,#03FH
                                                ; SOURCE LINE # 66
000086 4DEE           ORL      WR28,WR28
000088 780C           JNE      ?C0009
00008A BEF40001       CMP      WR30,#01H
00008E 7806           JNE      ?C0009
                                                ; SOURCE LINE # 67
000090 E5A2           MOV      A,P_SW1          ; A=R11
000092 F5A2           MOV      P_SW1,A          ; A=R11
000094 8031           SJMP     ?C0010
               ?C0009:
                                                ; SOURCE LINE # 68
000096 BEE40002       CMP      WR28,#02H
00009A 780B           JNE      ?C0011
00009C BEF40003       CMP      WR30,#03H
0000A0 7805           JNE      ?C0011
                                                ; SOURCE LINE # 69
0000A2 43A240         ORL      P_SW1,#040H
0000A5 8020           SJMP     ?C0010
               ?C0011:
                                                ; SOURCE LINE # 70
0000A7 BEE40004       CMP      WR28,#04H
0000AB 780B           JNE      ?C0013
0000AD BEF40005       CMP      WR30,#05H
0000B1 7805           JNE      ?C0013
                                                ; SOURCE LINE # 71
0000B3 43A280         ORL      P_SW1,#080H
0000B6 800F           SJMP     ?C0010
               ?C0013:
                                                ; SOURCE LINE # 72
0000B8 BEE40006       CMP      WR28,#06H
0000BC 7809           JNE      ?C0010
0000BE BEF40007       CMP      WR30,#07H
0000C2 7803           JNE      ?C0010
                                                ; SOURCE LINE # 73
0000C4 43A2C0         ORL      P_SW1,#0C0H
               ?C0010:
                                                ; SOURCE LINE # 74
0000C7 E4             CLR      A                ; A=R11
0000C8 7AB30000    R  MOV      UART_BUSY+1,R11  ; A=R11
                                                ; SOURCE LINE # 75
0000CC D2AC           SETB     ES
                                                ; SOURCE LINE # 76
0000CE AA             ERET     
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 8   

                                                ; SOURCE LINE # 78
               ?C0003:
                                                ; SOURCE LINE # 80
0000CF BED40002       CMP      WR26,#02H
0000D3 780E           JNE      ?C0016
                                                ; SOURCE LINE # 82
0000D5 439A10         ORL      S2CON,#010H
                                                ; SOURCE LINE # 83
0000D8 7CB7           MOV      R11,R7           ; A=R11
0000DA F5D7           MOV      T2L,A            ; A=R11
                                                ; SOURCE LINE # 84
0000DC 0A56           MOVZ     WR10,R6
0000DE F5D6           MOV      T2H,A            ; A=R11
                                                ; SOURCE LINE # 85
0000E0 438E14         ORL      AUXR,#014H
                                                ; SOURCE LINE # 86
               ?C0016:
                                                ; SOURCE LINE # 87
0000E3 53BAFE         ANL      P_SW2,#0FEH
                                                ; SOURCE LINE # 88
0000E6 BEE40008       CMP      WR28,#08H
0000EA 780C           JNE      ?C0017
0000EC BEF40009       CMP      WR30,#09H
0000F0 7806           JNE      ?C0017
                                                ; SOURCE LINE # 89
0000F2 E5BA           MOV      A,P_SW2          ; A=R11
0000F4 F5BA           MOV      P_SW2,A          ; A=R11
0000F6 800F           SJMP     ?C0018
               ?C0017:
                                                ; SOURCE LINE # 90
0000F8 BEE4000A       CMP      WR28,#0AH
0000FC 7809           JNE      ?C0018
0000FE BEF4000B       CMP      WR30,#0BH
000102 7803           JNE      ?C0018
                                                ; SOURCE LINE # 91
000104 43BA01         ORL      P_SW2,#01H
               ?C0018:
                                                ; SOURCE LINE # 92
000107 E4             CLR      A                ; A=R11
000108 7AB30000    R  MOV      UART_BUSY+2,R11  ; A=R11
                                                ; SOURCE LINE # 93
00010C A9D0AF         SETB     ES2
                                                ; SOURCE LINE # 94
00010F AA             ERET     
                                                ; SOURCE LINE # 95
                                                ; SOURCE LINE # 97
               ?C0004:
                                                ; SOURCE LINE # 99
000110 BED40002       CMP      WR26,#02H
000114 7810           JNE      ?C0020
                                                ; SOURCE LINE # 101
000116 43AC10         ORL      S3CON,#010H
                                                ; SOURCE LINE # 102
000119 7CB7           MOV      R11,R7           ; A=R11
00011B F5D7           MOV      T2L,A            ; A=R11
                                                ; SOURCE LINE # 103
00011D 0A56           MOVZ     WR10,R6
00011F F5D6           MOV      T2H,A            ; A=R11
                                                ; SOURCE LINE # 104
000121 438E14         ORL      AUXR,#014H
                                                ; SOURCE LINE # 105
000124 8017           SJMP     ?C0021
               ?C0020:
                                                ; SOURCE LINE # 106
000126 BED40003       CMP      WR26,#03H
00012A 7811           JNE      ?C0021
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 9   

                                                ; SOURCE LINE # 108
00012C 43AC50         ORL      S3CON,#050H
                                                ; SOURCE LINE # 109
00012F 7CB7           MOV      R11,R7           ; A=R11
000131 F5D5           MOV      T3L,A            ; A=R11
                                                ; SOURCE LINE # 110
000133 0A56           MOVZ     WR10,R6
000135 F5D4           MOV      T3H,A            ; A=R11
                                                ; SOURCE LINE # 111
000137 43DD0A         ORL      T4T3M,#0AH
                                                ; SOURCE LINE # 112
00013A 53BAFD         ANL      P_SW2,#0FDH
                                                ; SOURCE LINE # 113
               ?C0021:
                                                ; SOURCE LINE # 114
00013D BEE4000C       CMP      WR28,#0CH
000141 780C           JNE      ?C0023
000143 BEF4000D       CMP      WR30,#0DH
000147 7806           JNE      ?C0023
                                                ; SOURCE LINE # 115
000149 E5BA           MOV      A,P_SW2          ; A=R11
00014B F5BA           MOV      P_SW2,A          ; A=R11
00014D 800F           SJMP     ?C0024
               ?C0023:
                                                ; SOURCE LINE # 116
00014F BEE4000E       CMP      WR28,#0EH
000153 7809           JNE      ?C0024
000155 BEF4000F       CMP      WR30,#0FH
000159 7803           JNE      ?C0024
                                                ; SOURCE LINE # 117
00015B 43BA02         ORL      P_SW2,#02H
               ?C0024:
                                                ; SOURCE LINE # 118
00015E E4             CLR      A                ; A=R11
00015F 7AB30000    R  MOV      UART_BUSY+3,R11  ; A=R11
                                                ; SOURCE LINE # 119
000163 A9D3AF         SETB     ES3
                                                ; SOURCE LINE # 120
000166 AA             ERET     
                                                ; SOURCE LINE # 122
               ?C0005:
                                                ; SOURCE LINE # 124
000167 BED40002       CMP      WR26,#02H
00016B 7810           JNE      ?C0026
                                                ; SOURCE LINE # 126
00016D 43FD10         ORL      S4CON,#010H
                                                ; SOURCE LINE # 127
000170 7CB7           MOV      R11,R7           ; A=R11
000172 F5D7           MOV      T2L,A            ; A=R11
                                                ; SOURCE LINE # 128
000174 0A56           MOVZ     WR10,R6
000176 F5D6           MOV      T2H,A            ; A=R11
                                                ; SOURCE LINE # 129
000178 438E14         ORL      AUXR,#014H
                                                ; SOURCE LINE # 130
00017B 8014           SJMP     ?C0027
               ?C0026:
                                                ; SOURCE LINE # 131
00017D BED40004       CMP      WR26,#04H
000181 780E           JNE      ?C0027
                                                ; SOURCE LINE # 133
000183 43FD50         ORL      S4CON,#050H
                                                ; SOURCE LINE # 134
000186 7CB7           MOV      R11,R7           ; A=R11
000188 F5D3           MOV      T4L,A            ; A=R11
                                                ; SOURCE LINE # 135
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 10  

00018A 0A56           MOVZ     WR10,R6
00018C F5D2           MOV      T4H,A            ; A=R11
                                                ; SOURCE LINE # 136
00018E 43DDA0         ORL      T4T3M,#0A0H
                                                ; SOURCE LINE # 137
               ?C0027:
                                                ; SOURCE LINE # 138
000191 53BAFB         ANL      P_SW2,#0FBH
                                                ; SOURCE LINE # 139
000194 BEE40010       CMP      WR28,#010H
000198 780C           JNE      ?C0029
00019A BEF40011       CMP      WR30,#011H
00019E 7806           JNE      ?C0029
                                                ; SOURCE LINE # 140
0001A0 E5BA           MOV      A,P_SW2          ; A=R11
0001A2 F5BA           MOV      P_SW2,A          ; A=R11
0001A4 8015           SJMP     ?C0030
               ?C0029:
                                                ; SOURCE LINE # 141
0001A6 BEE40012       CMP      WR28,#012H
0001AA 780F           JNE      ?C0030
0001AC BEF40013       CMP      WR30,#013H
0001B0 7809           JNE      ?C0030
                                                ; SOURCE LINE # 143
0001B2 75CA00         MOV      P5M0,#00H
                                                ; SOURCE LINE # 144
0001B5 75C904         MOV      P5M1,#04H
                                                ; SOURCE LINE # 145
0001B8 43BA04         ORL      P_SW2,#04H
                                                ; SOURCE LINE # 146
               ?C0030:
                                                ; SOURCE LINE # 147
0001BB E4             CLR      A                ; A=R11
0001BC 7AB30000    R  MOV      UART_BUSY+4,R11  ; A=R11
                                                ; SOURCE LINE # 148
0001C0 A9D4AF         SETB     ES4
                                                ; SOURCE LINE # 149
                                                ; SOURCE LINE # 151
               ?C0001:
                                                ; SOURCE LINE # 152
0001C3 AA             ERET     
;       FUNCTION UART_Init? (END)

;       FUNCTION UART_PutChar? (BEGIN)
                                                ; SOURCE LINE # 161
0001C4 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'data_t' assigned to Register 'R10' ----
;---- Variable 'UART_N' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 163
0001C6 1B34           DEC      WR6,#01H
0001C8 681E           JE       ?C0041
0001CA 1B34           DEC      WR6,#01H
0001CC 682A           JE       ?C0045
0001CE 1B34           DEC      WR6,#01H
0001D0 6836           JE       ?C0049
0001D2 2E340003       ADD      WR6,#03H
0001D6 783F           JNE      ?C0032
                                                ; SOURCE LINE # 165
                                                ; SOURCE LINE # 166
                                                ; SOURCE LINE # 167
               ?C0037:
0001D8 7EB30000    R  MOV      R11,UART_BUSY+1  ; A=R11
0001DC 70FA           JNZ      ?C0037
                                                ; SOURCE LINE # 168
0001DE 7401           MOV      A,#01H           ; A=R11
0001E0 7AB30000    R  MOV      UART_BUSY+1,R11  ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 11  

                                                ; SOURCE LINE # 169
0001E4 7AA199         MOV      SBUF,R10
                                                ; SOURCE LINE # 170
0001E7 AA             ERET     
                                                ; SOURCE LINE # 171
                                                ; SOURCE LINE # 172
                                                ; SOURCE LINE # 173
               ?C0041:
0001E8 7EB30000    R  MOV      R11,UART_BUSY+2  ; A=R11
0001EC 70FA           JNZ      ?C0041
                                                ; SOURCE LINE # 174
0001EE 7401           MOV      A,#01H           ; A=R11
0001F0 7AB30000    R  MOV      UART_BUSY+2,R11  ; A=R11
                                                ; SOURCE LINE # 175
0001F4 7AA19B         MOV      S2BUF,R10
                                                ; SOURCE LINE # 176
0001F7 AA             ERET     
                                                ; SOURCE LINE # 177
                                                ; SOURCE LINE # 178
                                                ; SOURCE LINE # 179
               ?C0045:
0001F8 7EB30000    R  MOV      R11,UART_BUSY+3  ; A=R11
0001FC 70FA           JNZ      ?C0045
                                                ; SOURCE LINE # 180
0001FE 7401           MOV      A,#01H           ; A=R11
000200 7AB30000    R  MOV      UART_BUSY+3,R11  ; A=R11
                                                ; SOURCE LINE # 181
000204 7AA1AD         MOV      S3BUF,R10
                                                ; SOURCE LINE # 182
000207 AA             ERET     
                                                ; SOURCE LINE # 183
                                                ; SOURCE LINE # 184
                                                ; SOURCE LINE # 185
               ?C0049:
000208 7EB30000    R  MOV      R11,UART_BUSY+4  ; A=R11
00020C 70FA           JNZ      ?C0049
                                                ; SOURCE LINE # 186
00020E 7401           MOV      A,#01H           ; A=R11
000210 7AB30000    R  MOV      UART_BUSY+4,R11  ; A=R11
                                                ; SOURCE LINE # 187
000214 7AA1FE         MOV      S4BUF,R10
                                                ; SOURCE LINE # 188
                                                ; SOURCE LINE # 189
               ?C0032:
                                                ; SOURCE LINE # 190
000217 AA             ERET     
;       FUNCTION UART_PutChar? (END)

;       FUNCTION UART_PutBuff? (BEGIN)
                                                ; SOURCE LINE # 200
000218 CA3B           PUSH     DR12
00021A 7A270000    R  MOV      lenth,WR4
00021E 7F30           MOV      DR12,DR0
;---- Variable 'p' assigned to Register 'DR12' ----
000220 7A370000    R  MOV      UART_N,WR6
                                                ; SOURCE LINE # 202
000224 800D           SJMP     ?C0053
               ?C0055:
000226 7E370000    R  MOV      WR6,UART_N
00022A 7E3BB0         MOV      R11,@DR12        ; A=R11
00022D 0B74           INC      WR14,#01H
00022F 9A000000    R  ECALL    UART_PutChar?
               ?C0053:
000233 7E370000    R  MOV      WR6,lenth
000237 7D23           MOV      WR4,WR6
000239 1B24           DEC      WR4,#01H
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 12  

00023B 7A270000    R  MOV      lenth,WR4
00023F 4D33           ORL      WR6,WR6
000241 78E3           JNE      ?C0055
                                                ; SOURCE LINE # 204
000243 DA3B           POP      DR12
000245 AA             ERET     
;       FUNCTION UART_PutBuff? (END)

;       FUNCTION UART_PutStr? (BEGIN)
                                                ; SOURCE LINE # 213
000246 CA3B           PUSH     DR12
000248 7F30           MOV      DR12,DR0
;---- Variable 'str' assigned to Register 'DR12' ----
00024A 7A370000    R  MOV      UART_N,WR6
                                                ; SOURCE LINE # 215
00024E 800D           SJMP     ?C0057
               ?C0059:
                                                ; SOURCE LINE # 217
000250 7E370000    R  MOV      WR6,UART_N
000254 7E3BB0         MOV      R11,@DR12        ; A=R11
000257 0B74           INC      WR14,#01H
000259 9A000000    R  ECALL    UART_PutChar?
                                                ; SOURCE LINE # 218
               ?C0057:
00025D 7E3BB0         MOV      R11,@DR12        ; A=R11
000260 70EE           JNZ      ?C0059
                                                ; SOURCE LINE # 219
000262 DA3B           POP      DR12
000264 AA             ERET     
;       FUNCTION UART_PutStr? (END)

;       FUNCTION UART_Receive_t? (BEGIN)
                                                ; SOURCE LINE # 221
;---- Variable 'UART_N' assigned to Register 'WR6' ----
;---- Variable 'data_t' assigned to Register 'R10' ----
                                                ; SOURCE LINE # 222
                                                ; SOURCE LINE # 224
000265 1B34           DEC      WR6,#01H
000267 6814           JE       ?C0064
000269 1B34           DEC      WR6,#01H
00026B 6816           JE       ?C0065
00026D 1B34           DEC      WR6,#01H
00026F 6818           JE       ?C0066
000271 2E340003       ADD      WR6,#03H
000275 7818           JNE      ?C0063
                                                ; SOURCE LINE # 226
               ?C0062:
                                                ; SOURCE LINE # 227
000277 7EA199         MOV      R10,SBUF
                                                ; SOURCE LINE # 228
00027A 7CBA           MOV      R11,R10          ; A=R11
00027C AA             ERET     
                                                ; SOURCE LINE # 229
                                                ; SOURCE LINE # 230
               ?C0064:
                                                ; SOURCE LINE # 231
00027D 7EA19B         MOV      R10,S2BUF
                                                ; SOURCE LINE # 232
000280 7CBA           MOV      R11,R10          ; A=R11
000282 AA             ERET     
                                                ; SOURCE LINE # 233
                                                ; SOURCE LINE # 234
               ?C0065:
                                                ; SOURCE LINE # 235
000283 7EA1AD         MOV      R10,S3BUF
                                                ; SOURCE LINE # 236
C251 COMPILER V5.60.0,  CNU_PIE_UART                                                       24/08/26  10:23:43  PAGE 13  

000286 7CBA           MOV      R11,R10          ; A=R11
000288 AA             ERET     
                                                ; SOURCE LINE # 237
                                                ; SOURCE LINE # 238
               ?C0066:
                                                ; SOURCE LINE # 239
000289 7EA1FE         MOV      R10,S4BUF
                                                ; SOURCE LINE # 240
00028C 7CBA           MOV      R11,R10          ; A=R11
00028E AA             ERET     
                                                ; SOURCE LINE # 241
                                                ; SOURCE LINE # 242
               ?C0063:
                                                ; SOURCE LINE # 243
00028F E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 244
                                                ; SOURCE LINE # 245
                                                ; SOURCE LINE # 246
000290 AA             ERET     
;       FUNCTION UART_Receive_t? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       657     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =       215         12
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        10     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

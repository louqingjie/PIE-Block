C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_SPI
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_SPI.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_SPI.c XSMALL ROM(HUGE) BROWSE I
                    -NCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR
                    -(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_SPI.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_SPI.obj) 

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
   12           * @file       CNU_PIE_SPI.c
   13           * @brief      SPI
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_SPI.h"
   20          #include "CNU_PIE_GPIO.h"
   21          
   22          uint8_t   SPI_RxTimerOut;
   23          uint8_t   SPI_BUF_type SPI_RxBuffer[SPI_BUF_LENTH];
   24          bit B_SPI_Busy; //发送忙标志
   25          
   26           /*******************************************************************************************************
             -*******************
   27           * @brief  SPI初始化
   28           * @exampleCode
   29           *      SPI_Init(SPI_1, 1 , SPI_LSB , SPI_CPOL_High , SPI_CPHA_2Edge , SPI_Speed_16 , SPI_Mode_Master , 1
             -); //初始化SPI1 , 启用CS引脚 CPOL高 CPHA双边 时钟分频16分频 主机模式 开启SPI
   30           * @endcode
   31           * @param[in]  SPI_CHN    SPI组号 
   32           * @param[in]  SS_CFG     是否启用SS引脚              
   33           * @param[in]  FirstBit   SPI接收模式
   34           * @param[in]  cpol/cpha  SPI时钟/相位极性控制
   35           * @param[in]  Clock_Div  SPI总线速率
   36           * @param[in]  SPI_Mode   SPI主机/从机
   37           * @param[in]  SPI_EN     是否开启SPI
   38          *********************************************************************************************************
             -******************/
   39          void SPI_Init(SPI_ENUM SPI_CHN , uint8_t SS_CFG , uint8_t FirstBit , uint8_t cpol , uint8_t cpha , uint8_
             -t Clock_Div , uint8_t SPI_Mode , uint8_t SPI_EN)
   40          {
   41   1          switch(SPI_CHN)
   42   1        {
   43   2          case SPI_1:P_SW1 |= (0x00<<2);
   44   2              break;
   45   2          case SPI_2:P_SW1 |= (0x01<<2);
   46   2              break;
   47   2          case SPI_3:P_SW1 |= (0x02<<2);
   48   2              break;
   49   2          case SPI_4:P_SW1 |= (0x03<<2);
   50   2              break;
   51   2        }
C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 2   

   52   1        if(SS_CFG) SSIG = 0;//使能SS 通过SS引脚确认主设备还是从设备
   53   1        else SSIG = 1;      //禁用SS 通过SPI模式选择主从设备
   54   1        SPEN = SPI_EN;      //使能SPI
   55   1        DORD = FirstBit;    //选择接收模式 大端MSB 小端LSB
   56   1        MSTR = SPI_Mode;   //主从设置
   57   1        CPOL = cpol;        //SPI时钟极性控制
   58   1        CPHA = cpha;        //SPI时钟相位控制
   59   1        SPCTL = (SPCTL & ~0x03) | (Clock_Div);//速度/SPI时钟分频设置
   60   1        SPI_RxTimerOut = 0;
   61   1        B_SPI_Busy = 0;
   62   1      }
   63           /*******************************************************************************************************
             -*******************
   64           * @brief  SPI初始化
   65           * @exampleCode
   66           *      SPI_SetMode(SPI_Mode_Slave); //设置SPI为从机模式
   67           * @endcode
   68           * @param[in]  SPI_Mode   SPI模式
   69          *********************************************************************************************************
             -******************/
   70          void SPI_SetMode(uint8_t SPI_Mode)
   71          {
   72   1        if(SPI_Mode == SPI_Mode_Slave)
   73   1        {
   74   2          MSTR = 0;   //重新设置为从机待机
   75   2          SSIG = 0;   //SS引脚确定主从
   76   2        }
   77   1        else
   78   1        {
   79   2          MSTR = 1;   //使能 SPI 主机模式
   80   2          SSIG = 1;   //忽略SS引脚功能
   81   2        }
   82   1      }
   83           /*******************************************************************************************************
             -*******************
   84           * @brief  SPI写一个字节数据
   85           * @exampleCode
   86           *      SPI_WriteByte(0xFF); //SPI写一个字节数据 0xff
   87           * @endcode
   88           * @param[in]  dat   SPI写入的数据
   89          *********************************************************************************************************
             -******************/
   90          void SPI_WriteByte(uint8_t dat)
   91          {
   92   1        if(ESPI)
   93   1        {
   94   2          B_SPI_Busy = 1;
   95   2          SPDAT = dat;
   96   2          while(B_SPI_Busy);  //中断模式
   97   2        }
   98   1        else
   99   1        {
  100   2          SPDAT = dat;
  101   2          while(SPIF == 0); //查询模式
  102   2          {SPIF = 1; WCOL = 1;}  //清除SPIF和WCOL标志
  103   2        }
  104   1      }
  105           /*******************************************************************************************************
             -*******************
  106           * @brief  SPI读取一个字节数据
  107           * @exampleCode
  108           * uint8_t data;
  109           * data = SPI_ReadByte(); //SPI读取一个字节数据
  110           * @endcode
  111           * @retval data   SPI读取的数据
  112          *********************************************************************************************************
C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 3   

             -******************/
  113          uint8_t SPI_ReadByte(void)
  114          {
  115   1        SPDAT = 0xff;
  116   1        while(SPIF == 0) ;
  117   1        {SPIF = 1; WCOL = 1;}    //清0 SPIF和WCOL标志
  118   1        return (SPDAT);
  119   1      }
  120          
  121          uint8_t SPI_ReadWriteByte(uint8_t TxData)
  122          {
  123   1          SPDAT = TxData;                 //DATA寄存器赋值
  124   1          while (!(SPSTAT & 0x80));     //查询完成标志
  125   1          SPSTAT = 0xc0;                //清中断标志
  126   1          return SPDAT;
  127   1      }
C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 4   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION SPI_Init? (BEGIN)
                                                ; SOURCE LINE # 39
;---- Variable 'SPI_EN' assigned to Register 'R0' ----
;---- Variable 'SPI_Mode' assigned to Register 'R1' ----
;---- Variable 'Clock_Div' assigned to Register 'R2' ----
;---- Variable 'cpha' assigned to Register 'R3' ----
;---- Variable 'cpol' assigned to Register 'R4' ----
;---- Variable 'FirstBit' assigned to Register 'R5' ----
000000 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'SS_CFG' assigned to Register 'R10' ----
;---- Variable 'SPI_CHN' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 41
000002 1B34           DEC      WR6,#01H
000004 6814           JE       ?C0003
000006 1B34           DEC      WR6,#01H
000008 6815           JE       ?C0004
00000A 1B34           DEC      WR6,#01H
00000C 6816           JE       ?C0005
00000E 2E340003       ADD      WR6,#03H
000012 7813           JNE      ?C0001
                                                ; SOURCE LINE # 43
               ?C0002:
000014 E5A2           MOV      A,P_SW1          ; A=R11
000016 F5A2           MOV      P_SW1,A          ; A=R11
                                                ; SOURCE LINE # 44
000018 800D           SJMP     ?C0001
                                                ; SOURCE LINE # 45
               ?C0003:
00001A 43A204         ORL      P_SW1,#04H
                                                ; SOURCE LINE # 46
00001D 8008           SJMP     ?C0001
                                                ; SOURCE LINE # 47
               ?C0004:
00001F 43A208         ORL      P_SW1,#08H
                                                ; SOURCE LINE # 48
000022 8003           SJMP     ?C0001
                                                ; SOURCE LINE # 49
               ?C0005:
000024 43A20C         ORL      P_SW1,#0CH
                                                ; SOURCE LINE # 50
                                                ; SOURCE LINE # 51
               ?C0001:
                                                ; SOURCE LINE # 52
000027 4CAA           ORL      R10,R10
000029 6805           JE       ?C0006
00002B A9C7CE         CLR      SSIG
00002E 8003           SJMP     ?C0007
               ?C0006:
                                                ; SOURCE LINE # 53
000030 A9D7CE         SETB     SSIG
               ?C0007:
                                                ; SOURCE LINE # 54
000033 2E00FF         ADD      R0,#0FFH
000036 A996CE         MOV      SPEN,C
                                                ; SOURCE LINE # 55
000039 2E50FF         ADD      R5,#0FFH
00003C A995CE         MOV      DORD,C
                                                ; SOURCE LINE # 56
00003F 2E10FF         ADD      R1,#0FFH
000042 A994CE         MOV      MSTR,C
                                                ; SOURCE LINE # 57
000045 2E40FF         ADD      R4,#0FFH
000048 A993CE         MOV      CPOL,C
C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 5   

                                                ; SOURCE LINE # 58
00004B 2E30FF         ADD      R3,#0FFH
00004E A992CE         MOV      CPHA,C
                                                ; SOURCE LINE # 59
000051 E5CE           MOV      A,SPCTL          ; A=R11
000053 54FC           ANL      A,#0FCH          ; A=R11
000055 4CB2           ORL      R11,R2           ; A=R11
000057 F5CE           MOV      SPCTL,A          ; A=R11
                                                ; SOURCE LINE # 60
000059 E4             CLR      A                ; A=R11
00005A 7AB30000    R  MOV      SPI_RxTimerOut,R11
                                                ; SOURCE LINE # 61
00005E C200        R  CLR      B_SPI_Busy
                                                ; SOURCE LINE # 62
000060 AA             ERET     
;       FUNCTION SPI_Init? (END)

;       FUNCTION SPI_SetMode? (BEGIN)
                                                ; SOURCE LINE # 70
000061 7C7B           MOV      R7,R11           ; A=R11
;---- Variable 'SPI_Mode' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 72
000063 A5BF0007       CJNE     R7,#00H,?C0008
                                                ; SOURCE LINE # 74
000067 A9C4CE         CLR      MSTR
                                                ; SOURCE LINE # 75
00006A A9C7CE         CLR      SSIG
                                                ; SOURCE LINE # 76
00006D AA             ERET     
               ?C0008:
                                                ; SOURCE LINE # 79
00006E A9D4CE         SETB     MSTR
                                                ; SOURCE LINE # 80
000071 A9D7CE         SETB     SSIG
                                                ; SOURCE LINE # 81
                                                ; SOURCE LINE # 82
000074 AA             ERET     
;       FUNCTION SPI_SetMode? (END)

;       FUNCTION SPI_WriteByte? (BEGIN)
                                                ; SOURCE LINE # 90
000075 7C7B           MOV      R7,R11           ; A=R11
;---- Variable 'dat' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 92
000077 A931AF09       JNB      ESPI,?C0010
                                                ; SOURCE LINE # 94
00007B D200        R  SETB     B_SPI_Busy
                                                ; SOURCE LINE # 95
00007D 7A71CF         MOV      SPDAT,R7
                                                ; SOURCE LINE # 96
               ?C0011:
000080 2000FD         JB       B_SPI_Busy,?C0011
                                                ; SOURCE LINE # 97
000083 AA             ERET     
               ?C0010:
                                                ; SOURCE LINE # 100
000084 7A71CF         MOV      SPDAT,R7
                                                ; SOURCE LINE # 101
               ?C0016:
000087 A9A7CD         MOV      C,SPIF
00008A E4             CLR      A                ; A=R11
00008B 33             RLC      A                ; A=R11
00008C 68F9           JE       ?C0016
                                                ; SOURCE LINE # 102
00008E A9D7CD         SETB     SPIF
000091 A9D6CD         SETB     WCOL
C251 COMPILER V5.60.0,  CNU_PIE_SPI                                                        24/08/26  10:23:43  PAGE 6   

                                                ; SOURCE LINE # 103
                                                ; SOURCE LINE # 104
000094 AA             ERET     
;       FUNCTION SPI_WriteByte? (END)

;       FUNCTION SPI_ReadByte? (BEGIN)
                                                ; SOURCE LINE # 113
                                                ; SOURCE LINE # 115
000095 75CFFF         MOV      SPDAT,#0FFH
                                                ; SOURCE LINE # 116
               ?C0020:
000098 A9A7CD         MOV      C,SPIF
00009B E4             CLR      A                ; A=R11
00009C 33             RLC      A                ; A=R11
00009D 68F9           JE       ?C0020
                                                ; SOURCE LINE # 117
00009F A9D7CD         SETB     SPIF
0000A2 A9D6CD         SETB     WCOL
                                                ; SOURCE LINE # 118
0000A5 E5CF           MOV      A,SPDAT          ; A=R11
                                                ; SOURCE LINE # 119
0000A7 AA             ERET     
;       FUNCTION SPI_ReadByte? (END)

;       FUNCTION SPI_ReadWriteByte? (BEGIN)
                                                ; SOURCE LINE # 121
;---- Variable 'TxData' assigned to Register 'R11' ----
                                                ; SOURCE LINE # 123
0000A8 7AB1CF         MOV      SPDAT,R11        ; A=R11
                                                ; SOURCE LINE # 124
               ?C0025:
0000AB E5CD           MOV      A,SPSTAT         ; A=R11
0000AD 30E7FB         JNB      ACC.7,?C0025
                                                ; SOURCE LINE # 125
0000B0 75CDC0         MOV      SPSTAT,#0C0H
                                                ; SOURCE LINE # 126
0000B3 E5CF           MOV      A,SPDAT          ; A=R11
                                                ; SOURCE LINE # 127
0000B5 AA             ERET     
;       FUNCTION SPI_ReadWriteByte? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       182     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =        65     ------
  bit size             =         1     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =    ------     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

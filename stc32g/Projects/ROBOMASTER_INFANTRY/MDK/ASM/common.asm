C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE common
OBJECT MODULE PLACED IN .\Objects\ASM\common.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\startup\src\common.c XSMALL ROM(HUGE) BROWSE INCDIR
                    -(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X10
                    -00) DEBUG CODE PRINT(.\ASM\common.asm) TABS(2) OBJECT(.\Objects\ASM\common.obj) 

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
   12           * @file       common.c
   13           * @brief      通用
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "common.h"
   20          #include "intrins.h"
   21           #include "CNU_PIE_GPIO.h"
   22          volatile unsigned int DELAY_MS = 0;
   23          volatile unsigned int DELAY_US = 0;
   24          unsigned long system_clock;
   25           /*******************************************************************************************************
             -*******************
   26           * @brief  设置主时钟频率
   27           * @note   内部调用用户无需关心
   28           * @param[in]  NULL
   29           * @retval  设置的主时钟频率
   30          *********************************************************************************************************
             -******************/
   31          uint32_t System_Clock_Set(void)
   32          {
   33   1        system_clock = FOSC;
   34   1        P_SW2 |= 0x80;//使能访问特殊寄存器
   35   1        switch (system_clock)
   36   1        {
   37   2          case 22118400://22.1184MHz
   38   2            CLKDIV = 0x04; IRTRIM = T22M_ADDR; VRTRIM = VRT27M_ADDR;
   39   2            IRCBAND = 0x02; CLKDIV = 0x00; break;
   40   2          case 24000000://24MHz
   41   2            CLKDIV = 0x04; IRTRIM = T24M_ADDR; VRTRIM = VRT27M_ADDR;
   42   2            IRCBAND = 0x02; CLKDIV = 0x00; break;
   43   2          case 27000000://27MHz
   44   2            CLKDIV = 0x04; IRTRIM = T27M_ADDR; VRTRIM = VRT27M_ADDR;
   45   2            IRCBAND = 0x02; CLKDIV = 0x00; break;
   46   2          case 30000000://30MHz
   47   2            CLKDIV = 0x04; IRTRIM = T30M_ADDR; VRTRIM = VRT27M_ADDR;
   48   2            IRCBAND = 0x02; CLKDIV = 0x00; break;
   49   2          case 33177600://33.1776MHz
   50   2            CLKDIV = 0x04; IRTRIM = T33M_ADDR; VRTRIM = VRT27M_ADDR;
   51   2            IRCBAND = 0x02; CLKDIV = 0x00; break;
   52   2          case 35000000://35MHz
   53   2            CLKDIV = 0x04; IRTRIM = T35M_ADDR; VRTRIM = VRT44M_ADDR;
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 2   

   54   2            IRCBAND = 0x03; CLKDIV = 0x00; break;
   55   2          default://默认35MHz
   56   2            CLKDIV = 0x04; IRTRIM = T35M_ADDR; VRTRIM = VRT44M_ADDR;
   57   2            IRCBAND = 0x03; CLKDIV = 0x00; break;
   58   2        }
   59   1        return system_clock;
   60   1      }
   61           /*******************************************************************************************************
             -*******************
   62           * @brief  延时函数初始化
   63           * @note   内部调用用户无需关心
   64           * @param[in]  NULL
   65           * @retval     NULL
   66          *********************************************************************************************************
             -******************/
   67          void Delay_Init(void)
   68          {
   69   1        DELAY_MS = system_clock / 6000; DELAY_US = system_clock / 7000000;
   70   1        if(system_clock <= 12000000) DELAY_US++;//自适应主时钟
   71   1      }
   72           /*******************************************************************************************************
             -*******************
   73           * @brief  寄存器相关配置
   74           * @note   内部调用用户无需关心
   75           * @param[in]  NULL
   76           * @retval     NULL
   77          *********************************************************************************************************
             -******************/
   78          void Register_Set(void)
   79          {
   80   1        EAXFR = 1;        // 使能访问XFR
   81   1        CKCON = 0x00;     // 设置外部数据总线为最快
   82   1        WTST = 0;
   83   1        P54RST = 1;       // 使P54为复位引脚
   84   1        P_SW2 = 0x80;     // 开启特殊地址访问
   85   1        //if(System_Clock_Set() != 35000000)  WTST = 0;//CPU读取程序存储器的等待时间 0为最快
   86   1        //else WTST = 0x07; //当主频在35MHz时或超频工作，需要设置等待时长，默认为7个时钟周期  
   87   1      #if (1 == EXTERNAL_CRYSTA_ENABLE)
                 XOSCCR = 0xc0;      //启动外部晶振
                 while (!(XOSCCR & 1));  //等待时钟稳定
                 CLKDIV = 0x00;      //时钟不分频
                 CLKSEL = 0x01;      //选择外部晶振
               #else
   93   1        //自动设置系统频率
   94   1        #if (33177600 == FOSC)
   95   1          system_clock = System_Clock_Set();
   96   1        #else
                   system_clock = FOSC;
                 #endif
   99   1      #endif
  100   1         
  101   1        Delay_Init();       //延时函数初始化
  102   1        //ENLVR = 0;        // 禁止开发板低电压复位
  103   1        
  104   1        WTST = 0;
  105   1        P_SW2 |= 0x80;
  106   1        CLKDIV = 0;       //24MHz主频，分频设置
  107   1        
  108   1        P0M0 = 0x00;P0M1 = 0x00;// P0
  109   1        P1M0 = 0x00;P1M1 = 0x00;// P1
  110   1        P2M0 = 0x00;P2M1 = 0x00;// P2
  111   1        P3M0 = 0x00;P3M1 = 0x00;// P3
  112   1        P4M0 = 0x00;P4M1 = 0x00;// P4
  113   1        P5M0 = 0x00;P5M1 = 0x00;// P5
  114   1        P6M0 = 0x00;P6M1 = 0x00;// P6
  115   1        P7M0 = 0x00;P7M1 = 0x00;// P7
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 3   

  116   1        
  117   1        ADCCFG = 0;
  118   1        AUXR = 0;
  119   1        SCON = 0;
  120   1        S2CON = 0;
  121   1        S3CON = 0;
  122   1        S4CON = 0;
  123   1        P_SW1 = 0;
  124   1        IE2 = 0;
  125   1        TMOD = 0;
  126   1      }
  127           /*******************************************************************************************************
             -*******************
  128           * @brief  毫秒级延时函数
  129           * @note   实现毫秒延时，自适应主时钟
  130           * @param[in]  延时时间
  131           * @retval     NULL
  132          *********************************************************************************************************
             -******************/
  133          void Ms_Delay(uint16_t ms)
  134          {
  135   1        uint16_t i;
  136   1        do{
  137   2          i = DELAY_MS;
  138   2          while(--i);
  139   2        }while(--ms);
  140   1      }
  141           /*******************************************************************************************************
             -*******************
  142           * @brief  微秒级延时函数
  143           * @note   实现微秒延时，自适应主时钟，不准确延时
  144           * @param[in]  延时时间
  145           * @retval     NULL
  146          *********************************************************************************************************
             -******************/
  147          void Us_Delay(uint32_t us)
  148          {
  149   1        uint16_t i;
  150   1        do {
  151   2            i = DELAY_US;
  152   2            while(--i);
  153   2           }while(--us);
  154   1      }
  155           /*******************************************************************************************************
             -*******************
  156           * @brief  禁用全局中断
  157           * @note   禁止中断
  158           * @param[in]  NULL
  159           * @retval     NULL
  160          *********************************************************************************************************
             -******************/
  161          void DisableGlobalIRQ(void)
  162          {
  163   1        EA = 0;
  164   1      }
  165           /*******************************************************************************************************
             -*******************
  166           * @brief  开启全局中断
  167           * @note   开始中断
  168           * @param[in]  NULL
  169           * @retval     NULL
  170          *********************************************************************************************************
             -******************/
  171          void EnableGlobalIRQ(void)
  172          {
  173   1        EA = 1;
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 4   

  174   1      }
  175           /*******************************************************************************************************
             -*******************
  176           * @brief  开发板初始化
  177           * @note   寄存器配置+中断是否开启+延时初始化
  178           * @param[in]  NULL
  179           * @retval     NULL
  180          *********************************************************************************************************
             -******************/
  181          void Board_Init(void)
  182          {
  183   1        Register_Set();    //寄存器配置
  184   1        EnableGlobalIRQ();//启用全局中断
  185   1      }
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 5   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION System_Clock_Set? (BEGIN)
                                                ; SOURCE LINE # 31
                                                ; SOURCE LINE # 33
000000 7E344000       MOV      WR6,#04000H
000004 7E2401FA       MOV      WR4,#01FAH
000008 7A1F0000    R  MOV      system_clock,DR4
                                                ; SOURCE LINE # 34
00000C 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 35
                                                ; SOURCE LINE # 37
                                                ; SOURCE LINE # 38
                                                ; SOURCE LINE # 40
                                                ; SOURCE LINE # 41
                                                ; SOURCE LINE # 43
                                                ; SOURCE LINE # 44
                                                ; SOURCE LINE # 46
                                                ; SOURCE LINE # 47
                                                ; SOURCE LINE # 49
                                                ; SOURCE LINE # 50
00000F 7404           MOV      A,#04H           ; A=R11
000011 7E14FE01       MOV      WR2,#0FE01H
000015 7E04007E       MOV      WR0,#07EH
000019 7A0BB0         MOV      @DR0,R11         ; A=R11
00001C 7E54FDEF       MOV      WR10,#0FDEFH
000020 7E44007E       MOV      WR8,#07EH
000024 7E2BB0         MOV      R11,@DR8         ; A=R11
000027 F59F           MOV      IRTRIM,A         ; A=R11
000029 7E54FDF7       MOV      WR10,#0FDF7H
00002D 7E2BB0         MOV      R11,@DR8         ; A=R11
000030 F5A6           MOV      VRTRIM,A         ; A=R11
                                                ; SOURCE LINE # 51
000032 759D02         MOV      IRCBAND,#02H
000035 E4             CLR      A                ; A=R11
000036 7A0BB0         MOV      @DR0,R11         ; A=R11
                                                ; SOURCE LINE # 52
                                                ; SOURCE LINE # 53
                                                ; SOURCE LINE # 55
                                                ; SOURCE LINE # 56
                                                ; SOURCE LINE # 58
                                                ; SOURCE LINE # 59
                                                ; SOURCE LINE # 60
000039 AA             ERET     
;       FUNCTION System_Clock_Set? (END)

;       FUNCTION Delay_Init? (BEGIN)
                                                ; SOURCE LINE # 67
                                                ; SOURCE LINE # 69
00003A 7E141770       MOV      WR2,#01770H
00003E 7E7F0000    R  MOV      DR28,system_clock
000042 7F17           MOV      DR4,DR28
000044 9A000000    E  ECALL    ?C?ULIDIV?
000048 7A370000    R  MOV      DELAY_MS,WR6
00004C 7E14CFC0       MOV      WR2,#0CFC0H
000050 7E04006A       MOV      WR0,#06AH
000054 7F17           MOV      DR4,DR28
000056 9A000000    E  ECALL    ?C?ULDIV?
00005A 7A370000    R  MOV      DELAY_US,WR6
                                                ; SOURCE LINE # 70
00005E 7E341B00       MOV      WR6,#01B00H
000062 7E2400B7       MOV      WR4,#0B7H
000066 BF71           CMP      DR28,DR4
000068 380A           JG       ?C0010
00006A 7E370000    R  MOV      WR6,DELAY_US
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 6   

00006E 0B34           INC      WR6,#01H
000070 7A370000    R  MOV      DELAY_US,WR6
               ?C0010:
                                                ; SOURCE LINE # 71
000074 AA             ERET     
;       FUNCTION Delay_Init? (END)

;       FUNCTION Register_Set? (BEGIN)
                                                ; SOURCE LINE # 78
                                                ; SOURCE LINE # 80
000075 A9D7BA         SETB     EAXFR
                                                ; SOURCE LINE # 81
000078 75EA00         MOV      CKCON,#00H
                                                ; SOURCE LINE # 82
00007B 75E900         MOV      WTST,#00H
                                                ; SOURCE LINE # 83
00007E A9D4FF         SETB     P54RST
                                                ; SOURCE LINE # 84
000081 75BA80         MOV      P_SW2,#080H
                                                ; SOURCE LINE # 95
000084 9A000000    R  ECALL    System_Clock_Set?
000088 7A1F0000    R  MOV      system_clock,DR4
                                                ; SOURCE LINE # 101
00008C 9A000000    R  ECALL    Delay_Init?
                                                ; SOURCE LINE # 104
000090 75E900         MOV      WTST,#00H
                                                ; SOURCE LINE # 105
000093 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 106
000096 E4             CLR      A                ; A=R11
000097 7E34FE01       MOV      WR6,#0FE01H
00009B 7E24007E       MOV      WR4,#07EH
00009F 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 108
0000A2 759400         MOV      P0M0,#00H
0000A5 759300         MOV      P0M1,#00H
                                                ; SOURCE LINE # 109
0000A8 759200         MOV      P1M0,#00H
0000AB 759100         MOV      P1M1,#00H
                                                ; SOURCE LINE # 110
0000AE 759600         MOV      P2M0,#00H
0000B1 759500         MOV      P2M1,#00H
                                                ; SOURCE LINE # 111
0000B4 75B200         MOV      P3M0,#00H
0000B7 75B100         MOV      P3M1,#00H
                                                ; SOURCE LINE # 112
0000BA 75B400         MOV      P4M0,#00H
0000BD 75B300         MOV      P4M1,#00H
                                                ; SOURCE LINE # 113
0000C0 75CA00         MOV      P5M0,#00H
0000C3 75C900         MOV      P5M1,#00H
                                                ; SOURCE LINE # 114
0000C6 75CC00         MOV      P6M0,#00H
0000C9 75CB00         MOV      P6M1,#00H
                                                ; SOURCE LINE # 115
0000CC 75E200         MOV      P7M0,#00H
0000CF 75E100         MOV      P7M1,#00H
                                                ; SOURCE LINE # 117
0000D2 75DE00         MOV      ADCCFG,#00H
                                                ; SOURCE LINE # 118
0000D5 758E00         MOV      AUXR,#00H
                                                ; SOURCE LINE # 119
0000D8 759800         MOV      SCON,#00H
                                                ; SOURCE LINE # 120
0000DB 759A00         MOV      S2CON,#00H
                                                ; SOURCE LINE # 121
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 7   

0000DE 75AC00         MOV      S3CON,#00H
                                                ; SOURCE LINE # 122
0000E1 75FD00         MOV      S4CON,#00H
                                                ; SOURCE LINE # 123
0000E4 75A200         MOV      P_SW1,#00H
                                                ; SOURCE LINE # 124
0000E7 75AF00         MOV      IE2,#00H
                                                ; SOURCE LINE # 125
0000EA 758900         MOV      TMOD,#00H
                                                ; SOURCE LINE # 126
0000ED AA             ERET     
;       FUNCTION Register_Set? (END)

;       FUNCTION Ms_Delay? (BEGIN)
                                                ; SOURCE LINE # 133
0000EE 7D23           MOV      WR4,WR6
;---- Variable 'ms' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 134
                                                ; SOURCE LINE # 136
               ?C0011:
                                                ; SOURCE LINE # 137
0000F0 7E370000    R  MOV      WR6,DELAY_MS
;---- Variable 'i' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 138
               ?C0015:
0000F4 7D13           MOV      WR2,WR6
0000F6 1B14           DEC      WR2,#01H
0000F8 7D31           MOV      WR6,WR2
0000FA 78F8           JNE      ?C0015
                                                ; SOURCE LINE # 139
0000FC 7D12           MOV      WR2,WR4
0000FE 1B14           DEC      WR2,#01H
000100 7D21           MOV      WR4,WR2
000102 78EC           JNE      ?C0011
                                                ; SOURCE LINE # 140
000104 AA             ERET     
;       FUNCTION Ms_Delay? (END)

;       FUNCTION Us_Delay? (BEGIN)
                                                ; SOURCE LINE # 147
000105 7F01           MOV      DR0,DR4
;---- Variable 'us' assigned to Register 'DR0' ----
                                                ; SOURCE LINE # 148
                                                ; SOURCE LINE # 150
               ?C0019:
                                                ; SOURCE LINE # 151
000107 7E370000    R  MOV      WR6,DELAY_US
;---- Variable 'i' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 152
               ?C0023:
00010B 7D23           MOV      WR4,WR6
00010D 1B24           DEC      WR4,#01H
00010F 7D32           MOV      WR6,WR4
000111 78F8           JNE      ?C0023
                                                ; SOURCE LINE # 153
000113 7F20           MOV      DR8,DR0
000115 1B2C           DEC      DR8,#01H
000117 7F02           MOV      DR0,DR8
000119 4D45           ORL      WR8,WR10
00011B 78EA           JNE      ?C0019
                                                ; SOURCE LINE # 154
00011D AA             ERET     
;       FUNCTION Us_Delay? (END)

;       FUNCTION DisableGlobalIRQ? (BEGIN)
                                                ; SOURCE LINE # 161
C251 COMPILER V5.60.0,  common                                                             24/08/26  10:23:16  PAGE 8   

                                                ; SOURCE LINE # 163
00011E C2AF           CLR      EA
                                                ; SOURCE LINE # 164
000120 AA             ERET     
;       FUNCTION DisableGlobalIRQ? (END)

;       FUNCTION EnableGlobalIRQ? (BEGIN)
                                                ; SOURCE LINE # 171
                                                ; SOURCE LINE # 173
000121 D2AF           SETB     EA
                                                ; SOURCE LINE # 174
000123 AA             ERET     
;       FUNCTION EnableGlobalIRQ? (END)

;       FUNCTION Board_Init? (BEGIN)
                                                ; SOURCE LINE # 181
                                                ; SOURCE LINE # 183
000124 9A000000    R  ECALL    Register_Set?
                                                ; SOURCE LINE # 184
000128 8A000000    R  EJMP     EnableGlobalIRQ?
;       FUNCTION Board_Init? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       300     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =         8     ------
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        12     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

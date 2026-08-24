C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_ADC
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_ADC.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_ADC.c XSMALL ROM(HUGE) BROWSE I
                    -NCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR
                    -(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_ADC.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_ADC.obj) 

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
   12           * @file       CNU_PIE_ADC.c
   13           * @brief      ADC
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_ADC.h"
   20           /*******************************************************************************************************
             -*******************
   21           * @brief  ADC初始化函数
   22           * @exampleCode
   23           *      ADC_Init(ADC_P10 , ADC_SPEED_2X16T); //ADC P10引脚初始化为ADC ，时钟分频ADC_SPEED_2X16T
   24           * @endcode
   25           * @param[in]  ADC_PIN   ADC引脚
   26           * @param[in]  ADC_SPEED ADC时钟分频系输
   27          *********************************************************************************************************
             -******************/
   28          void ADC_Init(ADC_PIN_ENUM ADC_PIN , ADC_SPEED_ENUM ADC_SPEED)
   29          {
   30   1        ADC_CONTR |= 1<<7;        
   31   1        ADC_CONTR &= (0xF0);    
   32   1        ADC_CONTR |= ADC_PIN;
   33   1        
   34   1        if((ADC_PIN >> 3) == 1) //P0端口
   35   1        {
   36   2          //IO口需要设置为高阻输入
   37   2          P0M0 &= ~(1 << (ADC_PIN & 0x07));
   38   2          P0M1 |= (1 << (ADC_PIN & 0x07));
   39   2        }
   40   1        else if((ADC_PIN >> 3) == 0) //P1端口 
   41   1        {
   42   2          //IO口需要设置为高阻输入
   43   2          P1M0 &= ~(1 << (ADC_PIN & 0x07));
   44   2          P1M1 |= (1 << (ADC_PIN & 0x07));
   45   2        }
   46   1      
   47   1        ADCCFG |= ADC_SPEED&0x0F;     //Fosc_ADC = SYSCLK/2(SPEED+1)
   48   1        
   49   1        ADCCFG |= 1<<5;         //转换结果右对齐。 ADC_RES 保存结果的高 2 位， ADC_RESL 保存结果的低 8 位。
   50   1      }
   51           /*******************************************************************************************************
             -*******************
   52           * @brief  ADC初始化函数
C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 2   

   53           * @exampleCode
   54           *      uint16_t data;
   55           *      data = ADC_Init(ADC_P10 , ADC_12BIT); //ADC P10读取一次数据 12位精度
   56           * @endcode
   57           * @retval ADC_Value   ADC读取一次的数据
   58          *********************************************************************************************************
             -******************/
   59          uint16_t ADC_Read_Once(ADC_PIN_ENUM ADC_PIN , uint8_t Precision)
   60          {
   61   1        uint16_t ADC_Value;
   62   1        
   63   1        ADC_CONTR &= (0xF0);      //清除ADC_CHS[3:0] ： ADC 模拟通道选择位
   64   1        ADC_CONTR |= ADC_PIN;
   65   1        
   66   1        ADC_CONTR |= 0x40;        // 启动 AD 转换
   67   1        while (!(ADC_CONTR & 0x20));    // 查询 ADC 完成标志
   68   1        ADC_CONTR &= ~0x20;       // 清完成标志
   69   1        
   70   1        ADC_Value = ADC_RES;        //存储 ADC 的 12 位结果的高 4 位
   71   1        ADC_Value <<= 8;
   72   1        ADC_Value |= ADC_RESL;      //存储 ADC 的 12 位结果的低 8 位
   73   1        
   74   1        ADC_RES = 0;
   75   1        ADC_RESL = 0;
   76   1        
   77   1        ADC_Value >>= Precision;    //取多少位
   78   1        
   79   1        return ADC_Value;
   80   1      }
   81           /*******************************************************************************************************
             -*******************
   82           * @brief  ADC传输取数+滤波（均值冒泡）函数
   83           * @exampleCode
   84           *      uint16_t data;
   85           *      data = ADC_Average(ADC_P10 , ADC_12BIT , 10); //ADC P10读取十次数据 12位精度 返回一个数据
   86           * @endcode
   87           * @retval ADC_Value   ADC读取一次的数据
   88          *********************************************************************************************************
             -******************/
   89          uint16_t ADC_Average(ADC_PIN_ENUM ADC_PIN , uint8_t Precision , uint8_t N) 
   90          {
   91   1        uint32_t sum=0;
   92   1        uint8_t M=N;
   93   1        int i=0;
   94   1        int j=0;
   95   1        int str[20]={0};
   96   1        for(i=0;i<N;i++)str[i]=ADC_Read_Once(ADC_PIN,Precision);
   97   1        for(i=1;i<N;i++)
   98   1          for(j=0;j<N-i;j++)
   99   1          {
  100   2            if(str[j]>str[j+1])
  101   2            {
  102   3              int t=str[j+1];
  103   3              str[j+1]=str[j];
  104   3              str[j]=t;
  105   3            }
  106   2          }
  107   1        for(i=1;i<N-1;i++)sum+=str[i];
  108   1        return ((uint16_t)(sum/M));
  109   1      }
C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 3   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION ADC_Init? (BEGIN)
                                                ; SOURCE LINE # 28
000000 7D12           MOV      WR2,WR4
;---- Variable 'ADC_SPEED' assigned to Register 'WR2' ----
000002 7D23           MOV      WR4,WR6
;---- Variable 'ADC_PIN' assigned to Register 'WR4' ----
                                                ; SOURCE LINE # 30
000004 43BC80         ORL      ADC_CONTR,#080H
                                                ; SOURCE LINE # 31
000007 53BCF0         ANL      ADC_CONTR,#0F0H
                                                ; SOURCE LINE # 32
00000A 7CA7           MOV      R10,R7
00000C 7CB5           MOV      R11,R5           ; A=R11
00000E 42BC           ORL      ADC_CONTR,A      ; A=R11
                                                ; SOURCE LINE # 34
000010 0E34           SRA      WR6
000012 0E34           SRA      WR6
000014 0E34           SRA      WR6
000016 BE340001       CMP      WR6,#01H
00001A 781B           JNE      ?C0001
                                                ; SOURCE LINE # 37
00001C 7CBA           MOV      R11,R10          ; A=R11
00001E 5407           ANL      A,#07H           ; A=R11
000020 7E040001       MOV      WR0,#01H
000024 6005           JZ       ?C0032
               ?C0031:
000026 3E04           SLL      WR0
000028 14             DEC      A                ; A=R11
000029 78FB           JNE      ?C0031
               ?C0032:
00002B 7CB1           MOV      R11,R1           ; A=R11
00002D 64FF           XRL      A,#0FFH          ; A=R11
00002F 5294           ANL      P0M0,A           ; A=R11
                                                ; SOURCE LINE # 38
000031 7CB1           MOV      R11,R1           ; A=R11
000033 4293           ORL      P0M1,A           ; A=R11
                                                ; SOURCE LINE # 39
000035 801D           SJMP     ?C0002
               ?C0001:
                                                ; SOURCE LINE # 40
000037 4D33           ORL      WR6,WR6
000039 7819           JNE      ?C0002
                                                ; SOURCE LINE # 43
00003B 7CB5           MOV      R11,R5           ; A=R11
00003D 5407           ANL      A,#07H           ; A=R11
00003F 7E040001       MOV      WR0,#01H
000043 6005           JZ       ?C0034
               ?C0033:
000045 3E04           SLL      WR0
000047 14             DEC      A                ; A=R11
000048 78FB           JNE      ?C0033
               ?C0034:
00004A 7CB1           MOV      R11,R1           ; A=R11
00004C 64FF           XRL      A,#0FFH          ; A=R11
00004E 5292           ANL      P1M0,A           ; A=R11
                                                ; SOURCE LINE # 44
000050 7CB1           MOV      R11,R1           ; A=R11
000052 4291           ORL      P1M1,A           ; A=R11
                                                ; SOURCE LINE # 45
               ?C0002:
                                                ; SOURCE LINE # 47
000054 7CB3           MOV      R11,R3           ; A=R11
000056 540F           ANL      A,#0FH           ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 4   

000058 42DE           ORL      ADCCFG,A         ; A=R11
                                                ; SOURCE LINE # 49
00005A 43DE20         ORL      ADCCFG,#020H
                                                ; SOURCE LINE # 50
00005D AA             ERET     
;       FUNCTION ADC_Init? (END)

;       FUNCTION ADC_Read_Once? (BEGIN)
                                                ; SOURCE LINE # 59
00005E 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'Precision' assigned to Register 'R10' ----
;---- Variable 'ADC_PIN' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 60
                                                ; SOURCE LINE # 63
000060 53BCF0         ANL      ADC_CONTR,#0F0H
                                                ; SOURCE LINE # 64
000063 7CB7           MOV      R11,R7           ; A=R11
000065 42BC           ORL      ADC_CONTR,A      ; A=R11
                                                ; SOURCE LINE # 66
000067 43BC40         ORL      ADC_CONTR,#040H
                                                ; SOURCE LINE # 67
               ?C0004:
00006A E5BC           MOV      A,ADC_CONTR      ; A=R11
00006C 30E5FB         JNB      ACC.5,?C0004
                                                ; SOURCE LINE # 68
00006F 53BCDF         ANL      ADC_CONTR,#0DFH
                                                ; SOURCE LINE # 70
000072 E5BD           MOV      A,ADC_RES        ; A=R11
;---- Variable 'ADC_Value' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 71
000074 7C6B           MOV      R6,R11           ; A=R11
000076 6C77           XRL      R7,R7
                                                ; SOURCE LINE # 72
000078 E5BE           MOV      A,ADC_RESL       ; A=R11
00007A 0A2B           MOVZ     WR4,R11          ; A=R11
00007C 4D32           ORL      WR6,WR4
                                                ; SOURCE LINE # 74
00007E 75BD00         MOV      ADC_RES,#00H
                                                ; SOURCE LINE # 75
000081 75BE00         MOV      ADC_RESL,#00H
                                                ; SOURCE LINE # 77
000084 7CBA           MOV      R11,R10          ; A=R11
000086 6005           JZ       ?C0036
               ?C0035:
000088 1E34           SRL      WR6
00008A 14             DEC      A                ; A=R11
00008B 78FB           JNE      ?C0035
               ?C0036:
                                                ; SOURCE LINE # 79
                                                ; SOURCE LINE # 80
00008D AA             ERET     
;       FUNCTION ADC_Read_Once? (END)

;       FUNCTION ADC_Average? (BEGIN)
                                                ; SOURCE LINE # 89
00008E CA3B           PUSH     DR12
000090 7CD5           MOV      R13,R5
;---- Variable 'N' assigned to Register 'R13' ----
000092 7CCB           MOV      R12,R11          ; A=R11
;---- Variable 'Precision' assigned to Register 'R12' ----
000094 7D73           MOV      WR14,WR6
;---- Variable 'ADC_PIN' assigned to Register 'WR14' ----
                                                ; SOURCE LINE # 90
                                                ; SOURCE LINE # 91
000096 9F11           SUB      DR4,DR4
000098 7A1F0000    R  MOV      sum,DR4
C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 5   

                                                ; SOURCE LINE # 92
00009C 7AD30000    R  MOV      M,R13
                                                ; SOURCE LINE # 93
                                                ; SOURCE LINE # 94
0000A0 7A370000    R  MOV      j,WR6
                                                ; SOURCE LINE # 95
0000A4 7E340000    R  MOV      WR6,#WORD0 ?tpl?0001
0000A8 7E240000    R  MOV      WR4,#WORD2 ?tpl?0001
0000AC 7E140000    R  MOV      WR2,#WORD0 str
0000B0 7428           MOV      A,#028H          ; A=R11
0000B2 9A000000    E  ECALL    ?C?BMOVENP8?
                                                ; SOURCE LINE # 96
0000B6 6D33           XRL      WR6,WR6
0000B8 8018           SJMP     ?C0037
               ?C0012:
0000BA 7D37           MOV      WR6,WR14
0000BC 7CBC           MOV      R11,R12          ; A=R11
0000BE 9A000000    R  ECALL    ADC_Read_Once?
0000C2 7D23           MOV      WR4,WR6
0000C4 7E370000    R  MOV      WR6,i
0000C8 7D13           MOV      WR2,WR6
0000CA 3E14           SLL      WR2
0000CC 59210000    R  MOV      @WR2+str,WR4
0000D0 0B34           INC      WR6,#01H
               ?C0037:
0000D2 7A370000    R  MOV      i,WR6
               ?C0011:
0000D6 0A3D           MOVZ     WR6,R13
0000D8 BE370000    R  CMP      WR6,i
0000DC 18DC           JSG      ?C0012
                                                ; SOURCE LINE # 97
0000DE 7E240001       MOV      WR4,#01H
0000E2 7A270000    R  MOV      i,WR4
0000E6 8042           SJMP     ?C0016
                                                ; SOURCE LINE # 98
               ?C0023:
0000E8 6D33           XRL      WR6,WR6
0000EA 7A370000    R  MOV      j,WR6
0000EE 8024           SJMP     ?C0021
               ?C0022:
                                                ; SOURCE LINE # 100
0000F0 7E170000    R  MOV      WR2,j
0000F4 3E14           SLL      WR2
0000F6 49310000    R  MOV      WR6,@WR2+str+0x2
0000FA 49010000    R  MOV      WR0,@WR2+str
0000FE BD03           CMP      WR0,WR6
000100 0808           JSLE     ?C0019
                                                ; SOURCE LINE # 101
                                                ; SOURCE LINE # 102
;---- Variable 't' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 103
000102 59010000    R  MOV      @WR2+str+0x2,WR0
                                                ; SOURCE LINE # 104
000106 59310000    R  MOV      @WR2+str,WR6
                                                ; SOURCE LINE # 105
               ?C0019:
00010A 7E170000    R  MOV      WR2,j
00010E 0B14           INC      WR2,#01H
000110 7A170000    R  MOV      j,WR2
               ?C0021:
000114 0A1D           MOVZ     WR2,R13
000116 9E170000    R  SUB      WR2,i
00011A BE170000    R  CMP      WR2,j
00011E 18D0           JSG      ?C0022
000120 7E370000    R  MOV      WR6,i
000124 0B34           INC      WR6,#01H
C251 COMPILER V5.60.0,  CNU_PIE_ADC                                                        24/08/26  10:23:43  PAGE 6   

000126 7A370000    R  MOV      i,WR6
               ?C0016:
00012A 0A3D           MOVZ     WR6,R13
00012C BE370000    R  CMP      WR6,i
000130 18B6           JSG      ?C0023
                                                ; SOURCE LINE # 107
000132 801C           SJMP     ?C0038
               ?C0028:
000134 7E270000    R  MOV      WR4,i
000138 7D12           MOV      WR2,WR4
00013A 3E14           SLL      WR2
00013C 49510000    R  MOV      WR10,@WR2+str
000140 1A4A           MOVS     WR8,R10
000142 1A48           MOVS     WR8,R8
000144 7E0F0000    R  MOV      DR0,sum
000148 2F02           ADD      DR0,DR8
00014A 7A0F0000    R  MOV      sum,DR0
00014E 0B24           INC      WR4,#01H
               ?C0038:
000150 7A270000    R  MOV      i,WR4
               ?C0027:
000154 7D23           MOV      WR4,WR6
000156 1B24           DEC      WR4,#01H
000158 BE270000    R  CMP      WR4,i
00015C 18D6           JSG      ?C0028
                                                ; SOURCE LINE # 108
00015E 7E730000    R  MOV      R7,M
000162 0A17           MOVZ     WR2,R7
000164 6D00           XRL      WR0,WR0
000166 7E1F0000    R  MOV      DR4,sum
00016A 9A000000    E  ECALL    ?C?ULDIV?
                                                ; SOURCE LINE # 109
00016E DA3B           POP      DR12
000170 AA             ERET     
;       FUNCTION ADC_Average? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       369     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------         49
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        40     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

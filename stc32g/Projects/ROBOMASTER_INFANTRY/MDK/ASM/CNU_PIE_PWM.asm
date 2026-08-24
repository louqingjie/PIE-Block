C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_PWM
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_PWM.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_PWM.c XSMALL ROM(HUGE) BROWSE I
                    -NCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR
                    -(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_PWM.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_PWM.obj) 

stmt  level    source

    1          /********************************************************************************************************
             -*************
    2           *     COPYRIGHT NOTICE
    3           *     Copyright (c) 2023,CNU_W.PIE
    4           *     All rights reserved.
    5           *     本库函数参考逐飞科技开源的STC函数库
    6           *     除注明出处外，以下所有内容版权均属胖胖个人所有，未经允许，不得用于商业用途，
    7           *     修改内容时必须保留PP的版权声明。
    8           *     Except where indicated, the copyright of all the contents below is owned by PP 
    9           *     and can not be used for commercial purposes without permission. 
   10           *     The copyright notice of PP must be preserved when modifying the content.
   11           *
   12           * @file       CNU_PIE_PWM.c
   13           * @brief      PWM
   14           * @author     胖胖
   15           * @version    v1.1
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_PWM.h"
   20          #include "CNU_PIE_GPIO.h"
   21          
   22          //捕获比较模式寄存器
   23          const uint32_t PWM_CCMR_ADDR[] = {0x7efec8, 0x7efec9, 0x7efeca ,0x7efecb, 0x7efee8, 0x7efee9, 0x7efeea, 0
             -x7efeeb};
   24          //捕获比较使能寄存器
   25          const uint32_t PWM_CCER_ADDR[] = {0x7efecc, 0x7efecd, 0x7efeec ,0x7efeed};
   26          //控制寄存器,高8位地址  低8位地址 + 1即可
   27          const uint32_t PWM_CCR_ADDR[] = {0x7efed5, 0x7efed7, 0x7efed9, 0x7efedb, 0x7efef5, 0x7efef7, 0x7efef9, 0x
             -7efefb};  
   28          //控制寄存器,高8位地址  低8位地址 + 1即可
   29          const uint32_t PWM_ARR_ADDR[] = {0x7efed2,0x7efef2};
   30          
   31           /*******************************************************************************************************
             -*******************
   32           * @brief  初始化PWM引脚IO模式
   33           * @brief  内部调用，无需关心
   34          *********************************************************************************************************
             -******************/
   35          void PWM_PIN_SET(PWM_CHN_PIN_enum PWM_CHN_PIN)
   36          {
   37   1        switch(PWM_CHN_PIN)
   38   1        {
   39   2          case PWMA_CH1P_P10: GPIO_Init(GPIO_P1,GPIO_Pin_0,GPIO_OUT_PP); break;
   40   2          case PWMA_CH1N_P11: GPIO_Init(GPIO_P1,GPIO_Pin_1,GPIO_OUT_PP); break;
   41   2          case PWMA_CH1P_P20: GPIO_Init(GPIO_P2,GPIO_Pin_0,GPIO_OUT_PP); break;
   42   2          case PWMA_CH1N_P21: GPIO_Init(GPIO_P2,GPIO_Pin_1,GPIO_OUT_PP); break;
   43   2          case PWMA_CH1P_P60: GPIO_Init(GPIO_P6,GPIO_Pin_0,GPIO_OUT_PP); break;
   44   2          case PWMA_CH1N_P61: GPIO_Init(GPIO_P6,GPIO_Pin_1,GPIO_OUT_PP); break;   
   45   2          case PWMA_CH2P_P12: GPIO_Init(GPIO_P1,GPIO_Pin_2,GPIO_OUT_PP); break;
   46   2          case PWMA_CH2N_P13: GPIO_Init(GPIO_P1,GPIO_Pin_3,GPIO_OUT_PP); break;
   47   2          case PWMA_CH2P_P22: GPIO_Init(GPIO_P2,GPIO_Pin_2,GPIO_OUT_PP); break;
   48   2          case PWMA_CH2N_P23: GPIO_Init(GPIO_P2,GPIO_Pin_3,GPIO_OUT_PP); break;
   49   2          case PWMA_CH2P_P62: GPIO_Init(GPIO_P6,GPIO_Pin_2,GPIO_OUT_PP); break;
   50   2          case PWMA_CH2N_P63: GPIO_Init(GPIO_P6,GPIO_Pin_3,GPIO_OUT_PP); break;
   51   2          case PWMA_CH3P_P24: GPIO_Init(GPIO_P2,GPIO_Pin_4,GPIO_OUT_PP); break;
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 2   

   52   2          case PWMA_CH3N_P25: GPIO_Init(GPIO_P2,GPIO_Pin_5,GPIO_OUT_PP); break;
   53   2          case PWMA_CH3P_P64: GPIO_Init(GPIO_P6,GPIO_Pin_4,GPIO_OUT_PP); break;
   54   2          case PWMA_CH3N_P65: GPIO_Init(GPIO_P6,GPIO_Pin_5,GPIO_OUT_PP); break;
   55   2          case PWMA_CH4P_P16: GPIO_Init(GPIO_P1,GPIO_Pin_6,GPIO_OUT_PP); break;
   56   2          case PWMA_CH4N_P17: GPIO_Init(GPIO_P1,GPIO_Pin_7,GPIO_OUT_PP); break;
   57   2          case PWMA_CH4P_P26: GPIO_Init(GPIO_P2,GPIO_Pin_6,GPIO_OUT_PP); break;
   58   2          case PWMA_CH4N_P27: GPIO_Init(GPIO_P2,GPIO_Pin_7,GPIO_OUT_PP); break;
   59   2          case PWMA_CH4P_P66: GPIO_Init(GPIO_P6,GPIO_Pin_6,GPIO_OUT_PP); break;
   60   2          case PWMA_CH4N_P67: GPIO_Init(GPIO_P6,GPIO_Pin_7,GPIO_OUT_PP); break;
   61   2          case PWMA_CH4P_P34: GPIO_Init(GPIO_P3,GPIO_Pin_4,GPIO_OUT_PP); break;
   62   2          case PWMA_CH4N_P33: GPIO_Init(GPIO_P3,GPIO_Pin_3,GPIO_OUT_PP); break;
   63   2          case PWMB_CH1_P20:  GPIO_Init(GPIO_P2,GPIO_Pin_0,GPIO_OUT_PP); break;
   64   2          case PWMB_CH1_P17:  GPIO_Init(GPIO_P1,GPIO_Pin_7,GPIO_OUT_PP); break;
   65   2          case PWMB_CH1_P00:  GPIO_Init(GPIO_P0,GPIO_Pin_0,GPIO_OUT_PP); break;
   66   2          case PWMB_CH1_P74:  GPIO_Init(GPIO_P7,GPIO_Pin_4,GPIO_OUT_PP); break;
   67   2          case PWMB_CH2_P21:  GPIO_Init(GPIO_P2,GPIO_Pin_1,GPIO_OUT_PP); break;
   68   2          case PWMB_CH2_P54:  GPIO_Init(GPIO_P5,GPIO_Pin_4,GPIO_OUT_PP); break;
   69   2          case PWMB_CH2_P01:  GPIO_Init(GPIO_P0,GPIO_Pin_1,GPIO_OUT_PP); break;
   70   2          case PWMB_CH2_P75:  GPIO_Init(GPIO_P7,GPIO_Pin_5,GPIO_OUT_PP); break;
   71   2          case PWMB_CH3_P22:  GPIO_Init(GPIO_P2,GPIO_Pin_2,GPIO_OUT_PP); break;
   72   2          case PWMB_CH3_P33:  GPIO_Init(GPIO_P3,GPIO_Pin_3,GPIO_OUT_PP); break;
   73   2          case PWMB_CH3_P02:  GPIO_Init(GPIO_P0,GPIO_Pin_2,GPIO_OUT_PP); break;
   74   2          case PWMB_CH3_P76:  GPIO_Init(GPIO_P7,GPIO_Pin_6,GPIO_OUT_PP); break;
   75   2          case PWMB_CH4_P23:  GPIO_Init(GPIO_P2,GPIO_Pin_3,GPIO_OUT_PP); break;
   76   2          case PWMB_CH4_P34:  GPIO_Init(GPIO_P3,GPIO_Pin_4,GPIO_OUT_PP); break;
   77   2          case PWMB_CH4_P03:  GPIO_Init(GPIO_P0,GPIO_Pin_3,GPIO_OUT_PP); break;
   78   2          case PWMB_CH4_P77:  GPIO_Init(GPIO_P7,GPIO_Pin_7,GPIO_OUT_PP); break;
   79   2        }
   80   1      }
   81           /*******************************************************************************************************
             -*******************
   82           * @brief  PWM引脚初始化
   83           * @exampleCode
   84           *      PWM_Init(PWMA_CH2P_P62, 50, 0); //初始化P62引脚 频率50 初始占空比0
   85           * @endcode
   86           * @param[in]  PWM_CHN_PIN PWM引脚号 
   87           * @param[in]  frequency   PWM频率              
   88           * @param[in]  pwm_duty    PWM占空比
   89          *********************************************************************************************************
             -******************/
   90          void PWM_Init(PWM_CHN_PIN_enum PWM_CHN_PIN , uint32_t frequency , uint32_t pwm_duty)
   91          {
   92   1        
   93   1        uint32_t match_temp;
   94   1        uint32_t period_temp;
   95   1        uint16_t Frequency_Division = 0;//分频系输
   96   1        
   97   1        P_SW2 |= 0x80;
   98   1        
   99   1        //GPIO需要设置为推挽输出
  100   1        PWM_PIN_SET(PWM_CHN_PIN);//将对应的IO引脚设置为推挽输出
  101   1        
  102   1      //  //分频计算，周期计算，占空比计算
  103   1        Frequency_Division = ( system_clock / frequency ) >> 16;              //多少分频
  104   1        period_temp = system_clock / frequency ;      
  105   1        period_temp = period_temp / ( Frequency_Division +1 ) - 1;        //周期
  106   1      
  107   1        if(pwm_duty != PRECISION)
  108   1        {
  109   2          match_temp = period_temp * ((float)pwm_duty / PRECISION); // 占空比     
  110   2        }
  111   1        else
  112   1        {
  113   2          match_temp = (period_temp + 1);               // duty为100%
  114   2        }
  115   1        if(PWMB_CH1_P20 <= PWM_CHN_PIN)       //PWM5-8
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 3   

  116   1        {
  117   2          //通道选择，引脚选择
  118   2          PWMB_ENO |= (1 << ((2 * ((PWM_CHN_PIN >> 4) - 4))));          //使能通道  
  119   2          PWMB_PS |= ((PWM_CHN_PIN & 0x03) << ((2 * ((PWM_CHN_PIN >> 4) - 4))));    //输出脚选择
  120   2          
  121   2          // 配置通道输出使能和极性 
  122   2          (*(unsigned char volatile far *) (PWM_CCER_ADDR[PWM_CHN_PIN>>5])) |= (uint8_t)(1 << (((PWM_CHN_PIN >> 4
             -) & 0x01) * 4));
  123   2          
  124   2          //设置预分频
  125   2          PWMB_PSCRH = (uint8_t)(Frequency_Division>>8);
  126   2          PWMB_PSCRL = (uint8_t)Frequency_Division;
  127   2          
  128   2          PWMB_BKR = 0x80;  //主输出使能 相当于总开关
  129   2          PWMB_CR1 = 0x01;  //PWM开始计数
  130   2        }
  131   1        else
  132   1        {
  133   2          PWMA_ENO |= (1 << (PWM_CHN_PIN & 0x01)) << ((PWM_CHN_PIN >> 4) * 2);  //使能通道  
  134   2          PWMA_PS  |= ((PWM_CHN_PIN & 0x07) >> 1) << ((PWM_CHN_PIN >> 4) * 2);    //输出脚选择
  135   2          
  136   2          // 配置通道输出使能和极性 
  137   2          (*(unsigned char volatile far *) (PWM_CCER_ADDR[PWM_CHN_PIN>>5])) |= (1 << ((PWM_CHN_PIN & 0x01) * 2 + 
             -((PWM_CHN_PIN >> 4) & 0x01) * 0x04));
  138   2      
  139   2          
  140   2          //设置预分频
  141   2          PWMA_PSCRH = (uint8_t)(Frequency_Division>>8);
  142   2          PWMA_PSCRL = (uint8_t)Frequency_Division;
  143   2      
  144   2          PWMA_BKR = 0x80;  // 主输出使能 相当于总开关
  145   2          PWMA_CR1 = 0x01;  //PWM开始计数
  146   2        }
  147   1        
  148   1        //周期
  149   1        (*(unsigned char volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6])) = (uint8_t)(period_temp>>8);   //高8位
  150   1        (*(unsigned char volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1)) = (uint8_t)period_temp;    //低8位
  151   1      
  152   1        //设置捕获值|比较值
  153   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4]))    = match_temp>>8;      //高8位
  154   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1))  = (uint8_t)match_temp;    //低8位
  155   1        
  156   1        //功能设置
  157   1        (*(unsigned char volatile far *) (PWM_CCMR_ADDR[PWM_CHN_PIN>>4])) |= 0x06<<4;   //设置为PWM模式1
  158   1        (*(unsigned char volatile far *) (PWM_CCMR_ADDR[PWM_CHN_PIN>>4])) |= 1<<3;    //开启PWM寄存器的预装载功
  159   1      }
  160           /*******************************************************************************************************
             -*******************
  161           * @brief  PWM引脚设置占空比
  162           * @exampleCode
  163           *      PWM_SET_Duty(PWMA_CH2P_P62, 1000); //设置P62引脚 占空比1000
  164           * @endcode
  165           * @param[in]  PWM_CHN_PIN PWM引脚号             
  166           * @param[in]  pwm_duty    PWM占空比
  167          *********************************************************************************************************
             -******************/
  168          void PWM_SET_Duty(PWM_CHN_PIN_enum PWM_CHN_PIN , uint32_t pwm_duty)
  169          {
  170   1        uint32_t match_temp;
  171   1        uint32_t arrange = ((*(unsigned char volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6]))<<8) | (*(unsigned c
             -har volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1 ));
  172   1        
  173   1        P_SW2 |= 0x80;//确定使能访问XFR
  174   1        
  175   1        if(pwm_duty != PRECISION)
  176   1        {
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 4   

  177   2          match_temp = arrange * ((float)pwm_duty/PRECISION);       //占空比
  178   2        }
  179   1        else
  180   1        {
  181   2          match_temp = arrange + 1;
  182   2        }
  183   1        //设置捕获值|比较值
  184   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4]))    = match_temp>>8;      //高8位
  185   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1))  = (uint8_t)match_temp;    //低8位
  186   1        
  187   1      }
  188           /*******************************************************************************************************
             -*******************
  189           * @brief  PWM引脚设置频率
  190           * @exampleCode
  191           *      PWM_SET_Frequency (PWMB_CH3_P33,200,5000); //设置P33引脚 频率200 占空比5000
  192           * @endcode
  193           * @param[in]  PWM_CHN_PIN PWM引脚号 
  194           * @param[in]  frequency   PWM频率              
  195           * @param[in]  pwm_duty    PWM占空比
  196          *********************************************************************************************************
             -******************/
  197          void PWM_SET_Frequency(PWM_CHN_PIN_enum PWM_CHN_PIN, uint32_t frequency, uint32_t pwm_duty )
  198          {
  199   1        uint32_t match_temp;
  200   1        uint32_t period_temp; 
  201   1        uint16_t Frequency_Division = 0;//分频系输
  202   1        
  203   1        P_SW2 |= 0x80;//确定使能访问XFR
  204   1        
  205   1        //分频计算，周期计算，占空比计算
  206   1        Frequency_Division = (FOSC / frequency) >> 16;                  //分频
  207   1        period_temp = FOSC / frequency ;      
  208   1        period_temp = period_temp / (Frequency_Division + 1) - 1;       //周期
  209   1      
  210   1        if(pwm_duty != PRECISION)//判断占空比是否超最大精度
  211   1        {
  212   2          match_temp = period_temp * ((float)pwm_duty / PRECISION); // 占空比     
  213   2        }
  214   1        else
  215   1        {
  216   2          match_temp = period_temp + 1;                         //否则占空比为最大
  217   2        }
  218   1        
  219   1        if(PWMB_CH1_P20 <= PWM_CHN_PIN)//PWMA
  220   1        {
  221   2          //设置预分频
  222   2          PWMB_PSCRH = (uint8_t)(Frequency_Division>>8);
  223   2          PWMB_PSCRL = (uint8_t)Frequency_Division;
  224   2        }
  225   1        else//PWMB
  226   1        {
  227   2          //设置预分频
  228   2          PWMA_PSCRH = (uint8_t)(Frequency_Division>>8);
  229   2          PWMA_PSCRL = (uint8_t)Frequency_Division;
  230   2        }
  231   1        
  232   1        //周期
  233   1        (*(unsigned char volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6])) = (uint8_t)(period_temp>>8);   //高8位
  234   1        (*(unsigned char volatile far *) (PWM_ARR_ADDR[PWM_CHN_PIN>>6] + 1)) = (uint8_t)period_temp;    //低8位
  235   1      
  236   1        //设置捕获值|比较值
  237   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4]))    = match_temp>>8;      //高8位
  238   1        (*(unsigned char volatile far *) (PWM_CCR_ADDR[PWM_CHN_PIN>>4] + 1))  = (uint8_t)match_temp;    //低8位
  239   1      }
  240          
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 5   

  241          
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 6   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION PWM_PIN_SET? (BEGIN)
                                                ; SOURCE LINE # 35
;---- Variable 'PWM_CHN_PIN' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 37
000000 7D53           MOV      WR10,WR6
000002 BE540074       CMP      WR10,#074H
000006 4003        R  JC       $ + 5H
000008 020000      R  LJMP     ?C0001
00000B 7E340003       MOV      WR6,#03H
00000F AD53           MUL      WR10,WR6
000011 2E540000    R  ADD      WR10,#?C0053
000015 8954           LJMP     @WR10
               ?C0053:
000017 020000      R  LJMP     ?C0002
00001A 020000      R  LJMP     ?C0003
00001D 020000      R  LJMP     ?C0004
000020 020000      R  LJMP     ?C0005
000023 020000      R  LJMP     ?C0006
000026 020000      R  LJMP     ?C0007
000029 020000      R  LJMP     ?C0001
00002C 020000      R  LJMP     ?C0001
00002F 020000      R  LJMP     ?C0001
000032 020000      R  LJMP     ?C0001
000035 020000      R  LJMP     ?C0001
000038 020000      R  LJMP     ?C0001
00003B 020000      R  LJMP     ?C0001
00003E 020000      R  LJMP     ?C0001
000041 020000      R  LJMP     ?C0001
000044 020000      R  LJMP     ?C0001
000047 020000      R  LJMP     ?C0008
00004A 020000      R  LJMP     ?C0009
00004D 020000      R  LJMP     ?C0010
000050 020000      R  LJMP     ?C0011
000053 020000      R  LJMP     ?C0012
000056 020000      R  LJMP     ?C0013
000059 020000      R  LJMP     ?C0001
00005C 020000      R  LJMP     ?C0001
00005F 020000      R  LJMP     ?C0001
000062 020000      R  LJMP     ?C0001
000065 020000      R  LJMP     ?C0001
000068 020000      R  LJMP     ?C0001
00006B 020000      R  LJMP     ?C0001
00006E 020000      R  LJMP     ?C0001
000071 020000      R  LJMP     ?C0001
000074 020000      R  LJMP     ?C0001
000077 020000      R  LJMP     ?C0001
00007A 020000      R  LJMP     ?C0001
00007D 020000      R  LJMP     ?C0014
000080 020000      R  LJMP     ?C0015
000083 020000      R  LJMP     ?C0016
000086 020000      R  LJMP     ?C0017
000089 020000      R  LJMP     ?C0001
00008C 020000      R  LJMP     ?C0001
00008F 020000      R  LJMP     ?C0001
000092 020000      R  LJMP     ?C0001
000095 020000      R  LJMP     ?C0001
000098 020000      R  LJMP     ?C0001
00009B 020000      R  LJMP     ?C0001
00009E 020000      R  LJMP     ?C0001
0000A1 020000      R  LJMP     ?C0001
0000A4 020000      R  LJMP     ?C0001
0000A7 020000      R  LJMP     ?C0018
0000AA 020000      R  LJMP     ?C0019
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 7   

0000AD 020000      R  LJMP     ?C0020
0000B0 020000      R  LJMP     ?C0021
0000B3 020000      R  LJMP     ?C0022
0000B6 020000      R  LJMP     ?C0023
0000B9 020000      R  LJMP     ?C0024
0000BC 020000      R  LJMP     ?C0025
0000BF 020000      R  LJMP     ?C0001
0000C2 020000      R  LJMP     ?C0001
0000C5 020000      R  LJMP     ?C0001
0000C8 020000      R  LJMP     ?C0001
0000CB 020000      R  LJMP     ?C0001
0000CE 020000      R  LJMP     ?C0001
0000D1 020000      R  LJMP     ?C0001
0000D4 020000      R  LJMP     ?C0001
0000D7 020000      R  LJMP     ?C0026
0000DA 020000      R  LJMP     ?C0027
0000DD 020000      R  LJMP     ?C0028
0000E0 020000      R  LJMP     ?C0029
0000E3 020000      R  LJMP     ?C0001
0000E6 020000      R  LJMP     ?C0001
0000E9 020000      R  LJMP     ?C0001
0000EC 020000      R  LJMP     ?C0001
0000EF 020000      R  LJMP     ?C0001
0000F2 020000      R  LJMP     ?C0001
0000F5 020000      R  LJMP     ?C0001
0000F8 020000      R  LJMP     ?C0001
0000FB 020000      R  LJMP     ?C0001
0000FE 020000      R  LJMP     ?C0001
000101 020000      R  LJMP     ?C0001
000104 020000      R  LJMP     ?C0001
000107 020000      R  LJMP     ?C0030
00010A 020000      R  LJMP     ?C0031
00010D 020000      R  LJMP     ?C0032
000110 020000      R  LJMP     ?C0033
000113 020000      R  LJMP     ?C0001
000116 020000      R  LJMP     ?C0001
000119 020000      R  LJMP     ?C0001
00011C 020000      R  LJMP     ?C0001
00011F 020000      R  LJMP     ?C0001
000122 020000      R  LJMP     ?C0001
000125 020000      R  LJMP     ?C0001
000128 020000      R  LJMP     ?C0001
00012B 020000      R  LJMP     ?C0001
00012E 020000      R  LJMP     ?C0001
000131 020000      R  LJMP     ?C0001
000134 020000      R  LJMP     ?C0001
000137 020000      R  LJMP     ?C0034
00013A 020000      R  LJMP     ?C0035
00013D 020000      R  LJMP     ?C0036
000140 020000      R  LJMP     ?C0037
000143 020000      R  LJMP     ?C0001
000146 020000      R  LJMP     ?C0001
000149 020000      R  LJMP     ?C0001
00014C 020000      R  LJMP     ?C0001
00014F 020000      R  LJMP     ?C0001
000152 020000      R  LJMP     ?C0001
000155 020000      R  LJMP     ?C0001
000158 020000      R  LJMP     ?C0001
00015B 020000      R  LJMP     ?C0001
00015E 020000      R  LJMP     ?C0001
000161 020000      R  LJMP     ?C0001
000164 020000      R  LJMP     ?C0001
000167 020000      R  LJMP     ?C0038
00016A 020000      R  LJMP     ?C0039
00016D 020000      R  LJMP     ?C0040
000170 020000      R  LJMP     ?C0041
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 8   

                                                ; SOURCE LINE # 39
               ?C0002:
000173 7E240001       MOV      WR4,#01H
000177 020000      R  LJMP     ?C0071
                                                ; SOURCE LINE # 40
               ?C0003:
00017A 7E340001       MOV      WR6,#01H
00017E 020000      R  LJMP     ?C0073
                                                ; SOURCE LINE # 41
               ?C0004:
000181 020000      R  LJMP     ?C0070
                                                ; SOURCE LINE # 42
               ?C0005:
000184 7E240002       MOV      WR4,#02H
000188 020000      R  LJMP     ?C0071
                                                ; SOURCE LINE # 43
               ?C0006:
00018B 7E340006       MOV      WR6,#06H
00018F 020000      R  LJMP     ?C0092
                                                ; SOURCE LINE # 44
               ?C0007:
000192 7E340006       MOV      WR6,#06H
000196 020000      R  LJMP     ?C0073
                                                ; SOURCE LINE # 45
               ?C0008:
000199 7E340001       MOV      WR6,#01H
00019D 020000      R  LJMP     ?C0078
                                                ; SOURCE LINE # 46
               ?C0009:
0001A0 7E340001       MOV      WR6,#01H
0001A4 020000      R  LJMP     ?C0079
                                                ; SOURCE LINE # 47
               ?C0010:
0001A7 7E340002       MOV      WR6,#02H
0001AB 020000      R  LJMP     ?C0078
                                                ; SOURCE LINE # 48
               ?C0011:
0001AE 7E340002       MOV      WR6,#02H
0001B2 020000      R  LJMP     ?C0079
                                                ; SOURCE LINE # 49
               ?C0012:
0001B5 7E340006       MOV      WR6,#06H
0001B9 020000      R  LJMP     ?C0078
                                                ; SOURCE LINE # 50
               ?C0013:
0001BC 7E340006       MOV      WR6,#06H
0001C0 020000      R  LJMP     ?C0079
                                                ; SOURCE LINE # 51
               ?C0014:
0001C3 7E340002       MOV      WR6,#02H
0001C7 8054           SJMP     ?C0082
                                                ; SOURCE LINE # 52
               ?C0015:
0001C9 7E340002       MOV      WR6,#02H
0001CD 8072           SJMP     ?C0083
                                                ; SOURCE LINE # 53
               ?C0016:
0001CF 7E340006       MOV      WR6,#06H
0001D3 8048           SJMP     ?C0082
                                                ; SOURCE LINE # 54
               ?C0017:
0001D5 7E340006       MOV      WR6,#06H
0001D9 8066           SJMP     ?C0083
                                                ; SOURCE LINE # 55
               ?C0018:
0001DB 7E340001       MOV      WR6,#01H
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 9   

0001DF 020000      R  LJMP     ?C0088
                                                ; SOURCE LINE # 56
               ?C0019:
0001E2 8026           SJMP     ?C0085
                                                ; SOURCE LINE # 57
               ?C0020:
0001E4 7E340002       MOV      WR6,#02H
0001E8 020000      R  LJMP     ?C0088
                                                ; SOURCE LINE # 58
               ?C0021:
0001EB 7E340002       MOV      WR6,#02H
0001EF 020000      R  LJMP     ?C0093
                                                ; SOURCE LINE # 59
               ?C0022:
0001F2 7E340006       MOV      WR6,#06H
0001F6 8075           SJMP     ?C0088
                                                ; SOURCE LINE # 60
               ?C0023:
0001F8 7E340006       MOV      WR6,#06H
0001FC 020000      R  LJMP     ?C0093
                                                ; SOURCE LINE # 61
               ?C0024:
0001FF 020000      R  LJMP     ?C0090
                                                ; SOURCE LINE # 62
               ?C0025:
000202 804D           SJMP     ?C0091
                                                ; SOURCE LINE # 63
               ?C0026:
               ?C0070:
000204 7E340002       MOV      WR6,#02H
000208 8009           SJMP     ?C0092
                                                ; SOURCE LINE # 64
               ?C0027:
               ?C0085:
00020A 7E340001       MOV      WR6,#01H
00020E 020000      R  LJMP     ?C0093
                                                ; SOURCE LINE # 65
               ?C0028:
000211 6D33           XRL      WR6,WR6
               ?C0092:
000213 7E240001       MOV      WR4,#01H
000217 804A           SJMP     ?C0100
                                                ; SOURCE LINE # 66
               ?C0029:
000219 7E340007       MOV      WR6,#07H
               ?C0082:
00021D 7E240010       MOV      WR4,#010H
000221 8040           SJMP     ?C0100
                                                ; SOURCE LINE # 67
               ?C0030:
000223 7E240002       MOV      WR4,#02H
               ?C0071:
000227 7D32           MOV      WR6,WR4
000229 8038           SJMP     ?C0100
                                                ; SOURCE LINE # 68
               ?C0031:
00022B 7E340005       MOV      WR6,#05H
00022F 7E240010       MOV      WR4,#010H
000233 802E           SJMP     ?C0100
                                                ; SOURCE LINE # 69
               ?C0032:
000235 6D33           XRL      WR6,WR6
               ?C0073:
000237 7E240002       MOV      WR4,#02H
00023B 8026           SJMP     ?C0100
                                                ; SOURCE LINE # 70
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 10  

               ?C0033:
00023D 7E340007       MOV      WR6,#07H
               ?C0083:
000241 7E240020       MOV      WR4,#020H
000245 801C           SJMP     ?C0100
                                                ; SOURCE LINE # 71
               ?C0034:
000247 7E340002       MOV      WR6,#02H
               ?C0078:
00024B 7E240004       MOV      WR4,#04H
00024F 8012           SJMP     ?C0100
                                                ; SOURCE LINE # 72
               ?C0035:
               ?C0091:
000251 7E140003       MOV      WR2,#03H
000255 7D31           MOV      WR6,WR2
000257 7E240008       MOV      WR4,#08H
00025B 804C           SJMP     ?C0106
                                                ; SOURCE LINE # 73
               ?C0036:
00025D 6D33           XRL      WR6,WR6
00025F 7E240004       MOV      WR4,#04H
               ?C0100:
000263 7E140003       MOV      WR2,#03H
000267 8040           SJMP     ?C0106
                                                ; SOURCE LINE # 74
               ?C0037:
000269 7E340007       MOV      WR6,#07H
               ?C0088:
00026D 7E240040       MOV      WR4,#040H
000271 7E140003       MOV      WR2,#03H
000275 8032           SJMP     ?C0106
                                                ; SOURCE LINE # 75
               ?C0038:
000277 7E340002       MOV      WR6,#02H
               ?C0079:
00027B 7E240008       MOV      WR4,#08H
00027F 7E140003       MOV      WR2,#03H
000283 8024           SJMP     ?C0106
                                                ; SOURCE LINE # 76
               ?C0039:
               ?C0090:
000285 7E140003       MOV      WR2,#03H
000289 7D31           MOV      WR6,WR2
00028B 7E240010       MOV      WR4,#010H
00028F 8018           SJMP     ?C0106
                                                ; SOURCE LINE # 77
               ?C0040:
000291 6D33           XRL      WR6,WR6
000293 7E240008       MOV      WR4,#08H
000297 7E140003       MOV      WR2,#03H
00029B 800C           SJMP     ?C0106
                                                ; SOURCE LINE # 78
               ?C0041:
00029D 7E340007       MOV      WR6,#07H
               ?C0093:
0002A1 7E240080       MOV      WR4,#080H
0002A5 7E140003       MOV      WR2,#03H
               ?C0106:
0002A9 8A000000    E  EJMP     GPIO_Init?
                                                ; SOURCE LINE # 79
               ?C0001:
                                                ; SOURCE LINE # 80
0002AD AA             ERET     
;       FUNCTION PWM_PIN_SET? (END)

C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 11  

;       FUNCTION PWM_Init? (BEGIN)
                                                ; SOURCE LINE # 90
0002AE CA79           PUSH     WR14
0002B0 7A0F0000    R  MOV      frequency,DR0
0002B4 7D73           MOV      WR14,WR6
;---- Variable 'PWM_CHN_PIN' assigned to Register 'WR14' ----
                                                ; SOURCE LINE # 91
                                                ; SOURCE LINE # 95
                                                ; SOURCE LINE # 97
0002B6 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 100
0002B9 9A000000    R  ECALL    PWM_PIN_SET?
                                                ; SOURCE LINE # 103
0002BD 7E0F0000    R  MOV      DR0,frequency
0002C1 7E1F0000    E  MOV      DR4,system_clock
0002C5 9A000000    E  ECALL    ?C?ULDIV?
0002C9 7D12           MOV      WR2,WR4
0002CB 6D00           XRL      WR0,WR0
0002CD 7DD2           MOV      WR26,WR4
;---- Variable 'Frequency_Division' assigned to Register 'WR26' ----
                                                ; SOURCE LINE # 104
;---- Variable 'period_temp' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 105
0002CF 0B14           INC      WR2,#01H
0002D1 9A000000    E  ECALL    ?C?ULIDIV?
0002D5 7F71           MOV      DR28,DR4
0002D7 1B7C           DEC      DR28,#01H
                                                ; SOURCE LINE # 107
0002D9 7E1F0000    R  MOV      DR4,pwm_duty
0002DD E4             CLR      A                ; A=R11
0002DE 9A000000    E  ECALL    ?C?FCASTL?
0002E2 7F51           MOV      DR20,DR4
0002E4 7E144000       MOV      WR2,#04000H
0002E8 7E04461C       MOV      WR0,#0461CH
0002EC 9A000000    E  ECALL    ?C?FPCMP3?
0002F0 6821           JE       ?C0042
                                                ; SOURCE LINE # 109
0002F2 7E144000       MOV      WR2,#04000H
0002F6 7E04461C       MOV      WR0,#0461CH
0002FA 7F15           MOV      DR4,DR20
0002FC 9A000000    E  ECALL    ?C?FPDIV?
000300 7F01           MOV      DR0,DR4
000302 7F17           MOV      DR4,DR28
000304 E4             CLR      A                ; A=R11
000305 9A000000    E  ECALL    ?C?FCASTL?
000309 9A000000    E  ECALL    ?C?FPMUL?
00030D 9A000000    E  ECALL    ?C?CASTF?
                                                ; SOURCE LINE # 110
000311 8004           SJMP     ?C0107
               ?C0042:
                                                ; SOURCE LINE # 113
000313 7F17           MOV      DR4,DR28
000315 0B1C           INC      DR4,#01H
               ?C0107:
000317 7A1F0000    R  MOV      match_temp,DR4
                                                ; SOURCE LINE # 114
                                                ; SOURCE LINE # 115
00031B BE740040       CMP      WR14,#040H
00031F 5803        R  JSGE     $ + 5H
000321 020000      R  LJMP     ?C0044
                                                ; SOURCE LINE # 118
000324 7D57           MOV      WR10,WR14
000326 0E54           SRA      WR10
000328 0E54           SRA      WR10
00032A 0E54           SRA      WR10
00032C 0E54           SRA      WR10
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 12  

00032E 1B56           DEC      WR10,#04H
000330 3E54           SLL      WR10
000332 7CAB           MOV      R10,R11          ; A=R11
000334 7E140001       MOV      WR2,#01H
000338 6005           JZ       ?C0055
               ?C0054:
00033A 3E14           SLL      WR2
00033C 14             DEC      A                ; A=R11
00033D 78FB           JNE      ?C0054
               ?C0055:
00033F 7E34FEB5       MOV      WR6,#0FEB5H
000343 7E24007E       MOV      WR4,#07EH
000347 7E1BB0         MOV      R11,@DR4         ; A=R11
00034A 4CB3           ORL      R11,R3           ; A=R11
00034C 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 119
00034F 7D37           MOV      WR6,WR14
000351 5E340003       ANL      WR6,#03H
000355 7CBA           MOV      R11,R10          ; A=R11
000357 6005           JZ       ?C0057
               ?C0056:
000359 3E34           SLL      WR6
00035B 14             DEC      A                ; A=R11
00035C 78FB           JNE      ?C0056
               ?C0057:
00035E 7C67           MOV      R6,R7
000360 7E14FEB6       MOV      WR2,#0FEB6H
000364 7E04007E       MOV      WR0,#07EH
000368 7E0B70         MOV      R7,@DR0
00036B 4C76           ORL      R7,R6
00036D 7A0B70         MOV      @DR0,R7
                                                ; SOURCE LINE # 122
000370 7D57           MOV      WR10,WR14
000372 0E54           SRA      WR10
000374 0E54           SRA      WR10
000376 0E54           SRA      WR10
000378 0E54           SRA      WR10
00037A 5E540001       ANL      WR10,#01H
00037E 3E54           SLL      WR10
000380 3E54           SLL      WR10
000382 7E340001       MOV      WR6,#01H
000386 6005           JZ       ?C0059
               ?C0058:
000388 3E34           SLL      WR6
00038A 14             DEC      A                ; A=R11
00038B 78FB           JNE      ?C0058
               ?C0059:
00038D 7C67           MOV      R6,R7
00038F 7D17           MOV      WR2,WR14
000391 0E14           SRA      WR2
000393 0E14           SRA      WR2
000395 0E14           SRA      WR2
000397 0E14           SRA      WR2
000399 0E14           SRA      WR2
00039B 1A02           MOVS     WR0,R2
00039D 1A00           MOVS     WR0,R0
00039F 7F20           MOV      DR8,DR0
0003A1 2F20           ADD      DR8,DR0
0003A3 2F22           ADD      DR8,DR8
0003A5 2E440000    R  ADD      WR8,#WORD2 PWM_CCER_ADDR
0003A9 2E280000    R  ADD      DR8,#WORD0 PWM_CCER_ADDR
0003AD 69120002       MOV      WR2,@DR8+0x2
0003B1 0B2A00         MOV      WR0,@DR8
0003B4 7E0B70         MOV      R7,@DR0
0003B7 4C76           ORL      R7,R6
0003B9 7A0B70         MOV      @DR0,R7
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 13  

                                                ; SOURCE LINE # 125
0003BC 7D1D           MOV      WR2,WR26
0003BE 0A12           MOVZ     WR2,R2
0003C0 7E34FEF0       MOV      WR6,#0FEF0H
0003C4 7E24007E       MOV      WR4,#07EH
0003C8 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 126
0003CB 7D3D           MOV      WR6,WR26
0003CD 7C37           MOV      R3,R7
0003CF 7E34FEF1       MOV      WR6,#0FEF1H
0003D3 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 128
0003D6 7480           MOV      A,#080H          ; A=R11
0003D8 7E34FEFD       MOV      WR6,#0FEFDH
0003DC 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 129
0003DF 7401           MOV      A,#01H           ; A=R11
0003E1 7E34FEE0       MOV      WR6,#0FEE0H
                                                ; SOURCE LINE # 130
0003E5 020000      R  LJMP     ?C0108
               ?C0044:
                                                ; SOURCE LINE # 133
0003E8 7D57           MOV      WR10,WR14
0003EA 0E54           SRA      WR10
0003EC 0E54           SRA      WR10
0003EE 0E54           SRA      WR10
0003F0 0E54           SRA      WR10
0003F2 3E54           SLL      WR10
0003F4 7CAB           MOV      R10,R11          ; A=R11
0003F6 7CBF           MOV      R11,R15          ; A=R11
0003F8 5401           ANL      A,#01H           ; A=R11
0003FA 7E340001       MOV      WR6,#01H
0003FE 7D23           MOV      WR4,WR6
000400 6005           JZ       ?C0061
               ?C0060:
000402 3E24           SLL      WR4
000404 14             DEC      A                ; A=R11
000405 78FB           JNE      ?C0060
               ?C0061:
000407 7CBA           MOV      R11,R10          ; A=R11
000409 6005           JZ       ?C0063
               ?C0062:
00040B 3E24           SLL      WR4
00040D 14             DEC      A                ; A=R11
00040E 78FB           JNE      ?C0062
               ?C0063:
000410 7E14FEB1       MOV      WR2,#0FEB1H
000414 7E04007E       MOV      WR0,#07EH
000418 7E0BB0         MOV      R11,@DR0         ; A=R11
00041B 4CB5           ORL      R11,R5           ; A=R11
00041D 7A0BB0         MOV      @DR0,R11         ; A=R11
                                                ; SOURCE LINE # 134
000420 7D27           MOV      WR4,WR14
000422 5E240007       ANL      WR4,#07H
000426 0E24           SRA      WR4
000428 7CBA           MOV      R11,R10          ; A=R11
00042A 6005           JZ       ?C0065
               ?C0064:
00042C 3E24           SLL      WR4
00042E 14             DEC      A                ; A=R11
00042F 78FB           JNE      ?C0064
               ?C0065:
000431 7C45           MOV      R4,R5
000433 7E14FEB2       MOV      WR2,#0FEB2H
000437 7E04007E       MOV      WR0,#07EH
00043B 7E0B50         MOV      R5,@DR0
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 14  

00043E 4C54           ORL      R5,R4
000440 7A0B50         MOV      @DR0,R5
                                                ; SOURCE LINE # 137
000443 7D27           MOV      WR4,WR14
000445 0E24           SRA      WR4
000447 0E24           SRA      WR4
000449 0E24           SRA      WR4
00044B 0E24           SRA      WR4
00044D 5E240001       ANL      WR4,#01H
000451 3E24           SLL      WR4
000453 3E24           SLL      WR4
000455 7D57           MOV      WR10,WR14
000457 5E540001       ANL      WR10,#01H
00045B 3E54           SLL      WR10
00045D 2D52           ADD      WR10,WR4
00045F 6005           JZ       ?C0067
               ?C0066:
000461 3E34           SLL      WR6
000463 14             DEC      A                ; A=R11
000464 78FB           JNE      ?C0066
               ?C0067:
000466 7C67           MOV      R6,R7
000468 7D17           MOV      WR2,WR14
00046A 0E14           SRA      WR2
00046C 0E14           SRA      WR2
00046E 0E14           SRA      WR2
000470 0E14           SRA      WR2
000472 0E14           SRA      WR2
000474 1A02           MOVS     WR0,R2
000476 1A00           MOVS     WR0,R0
000478 7F20           MOV      DR8,DR0
00047A 2F20           ADD      DR8,DR0
00047C 2F22           ADD      DR8,DR8
00047E 2E440000    R  ADD      WR8,#WORD2 PWM_CCER_ADDR
000482 2E280000    R  ADD      DR8,#WORD0 PWM_CCER_ADDR
000486 69120002       MOV      WR2,@DR8+0x2
00048A 0B2A00         MOV      WR0,@DR8
00048D 7E0B70         MOV      R7,@DR0
000490 4C76           ORL      R7,R6
000492 7A0B70         MOV      @DR0,R7
                                                ; SOURCE LINE # 141
000495 7D1D           MOV      WR2,WR26
000497 0A12           MOVZ     WR2,R2
000499 7E34FED0       MOV      WR6,#0FED0H
00049D 7E24007E       MOV      WR4,#07EH
0004A1 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 142
0004A4 7D3D           MOV      WR6,WR26
0004A6 7C37           MOV      R3,R7
0004A8 7E34FED1       MOV      WR6,#0FED1H
0004AC 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 144
0004AF 7480           MOV      A,#080H          ; A=R11
0004B1 7E34FEDD       MOV      WR6,#0FEDDH
0004B5 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 145
0004B8 7401           MOV      A,#01H           ; A=R11
0004BA 7E34FEC0       MOV      WR6,#0FEC0H
               ?C0108:
0004BE 7E24007E       MOV      WR4,#07EH
0004C2 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 146
                                                ; SOURCE LINE # 149
0004C5 7D1F           MOV      WR2,WR30
0004C7 7D37           MOV      WR6,WR14
0004C9 0E34           SRA      WR6
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 15  

0004CB 0E34           SRA      WR6
0004CD 0E34           SRA      WR6
0004CF 0E34           SRA      WR6
0004D1 0E34           SRA      WR6
0004D3 0E34           SRA      WR6
0004D5 1A26           MOVS     WR4,R6
0004D7 1A24           MOVS     WR4,R4
0004D9 7F21           MOV      DR8,DR4
0004DB 2F21           ADD      DR8,DR4
0004DD 2F22           ADD      DR8,DR8
0004DF 2E440000    R  ADD      WR8,#WORD2 PWM_ARR_ADDR
0004E3 2E280000    R  ADD      DR8,#WORD0 PWM_ARR_ADDR
0004E7 69320002       MOV      WR6,@DR8+0x2
0004EB 0B2A20         MOV      WR4,@DR8
0004EE 7A1B20         MOV      @DR4,R2
                                                ; SOURCE LINE # 150
0004F1 7D3F           MOV      WR6,WR30
0004F3 7D37           MOV      WR6,WR14
0004F5 0E34           SRA      WR6
0004F7 0E34           SRA      WR6
0004F9 0E34           SRA      WR6
0004FB 0E34           SRA      WR6
0004FD 0E34           SRA      WR6
0004FF 0E34           SRA      WR6
000501 1A26           MOVS     WR4,R6
000503 1A24           MOVS     WR4,R4
000505 7F21           MOV      DR8,DR4
000507 2F21           ADD      DR8,DR4
000509 2F22           ADD      DR8,DR8
00050B 2E440000    R  ADD      WR8,#WORD2 PWM_ARR_ADDR
00050F 2E280000    R  ADD      DR8,#WORD0 PWM_ARR_ADDR
000513 69320002       MOV      WR6,@DR8+0x2
000517 0B2A20         MOV      WR4,@DR8
00051A 0B1C           INC      DR4,#01H
00051C 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 153
00051F 7E1F0000    R  MOV      DR4,match_temp
000523 7C36           MOV      R3,R6
000525 7D37           MOV      WR6,WR14
000527 0E34           SRA      WR6
000529 0E34           SRA      WR6
00052B 0E34           SRA      WR6
00052D 0E34           SRA      WR6
00052F 1A26           MOVS     WR4,R6
000531 1A24           MOVS     WR4,R4
000533 7F21           MOV      DR8,DR4
000535 2F21           ADD      DR8,DR4
000537 2F22           ADD      DR8,DR8
000539 2E440000    R  ADD      WR8,#WORD2 PWM_CCR_ADDR
00053D 2E280000    R  ADD      DR8,#WORD0 PWM_CCR_ADDR
000541 69320002       MOV      WR6,@DR8+0x2
000545 0B2A20         MOV      WR4,@DR8
000548 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 154
00054B 7E2F0000    R  MOV      DR8,match_temp
00054F 7D37           MOV      WR6,WR14
000551 0E34           SRA      WR6
000553 0E34           SRA      WR6
000555 0E34           SRA      WR6
000557 0E34           SRA      WR6
000559 1A26           MOVS     WR4,R6
00055B 1A24           MOVS     WR4,R4
00055D 7F01           MOV      DR0,DR4
00055F 2F01           ADD      DR0,DR4
000561 2F00           ADD      DR0,DR0
000563 7F70           MOV      DR28,DR0
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 16  

000565 2EE40000    R  ADD      WR28,#WORD2 PWM_CCR_ADDR
000569 2E780000    R  ADD      DR28,#WORD0 PWM_CCR_ADDR
00056D 69370002       MOV      WR6,@DR28+0x2
000571 0B7A20         MOV      WR4,@DR28
000574 0B1C           INC      DR4,#01H
000576 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 157
000579 2E040000    R  ADD      WR0,#WORD2 PWM_CCMR_ADDR
00057D 2E080000    R  ADD      DR0,#WORD0 PWM_CCMR_ADDR
000581 69300002       MOV      WR6,@DR0+0x2
000585 0B0A20         MOV      WR4,@DR0
000588 7E1BB0         MOV      R11,@DR4         ; A=R11
00058B 4460           ORL      A,#060H          ; A=R11
00058D 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 158
000590 7D37           MOV      WR6,WR14
000592 0E34           SRA      WR6
000594 0E34           SRA      WR6
000596 0E34           SRA      WR6
000598 0E34           SRA      WR6
00059A 1A26           MOVS     WR4,R6
00059C 1A24           MOVS     WR4,R4
00059E 7F01           MOV      DR0,DR4
0005A0 2F01           ADD      DR0,DR4
0005A2 2F00           ADD      DR0,DR0
0005A4 2E040000    R  ADD      WR0,#WORD2 PWM_CCMR_ADDR
0005A8 2E080000    R  ADD      DR0,#WORD0 PWM_CCMR_ADDR
0005AC 69300002       MOV      WR6,@DR0+0x2
0005B0 0B0A20         MOV      WR4,@DR0
0005B3 7E1BB0         MOV      R11,@DR4         ; A=R11
0005B6 4408           ORL      A,#08H           ; A=R11
0005B8 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 159
0005BB DA79           POP      WR14
0005BD AA             ERET     
;       FUNCTION PWM_Init? (END)

;       FUNCTION PWM_SET_Duty? (BEGIN)
                                                ; SOURCE LINE # 168
0005BE 7F60           MOV      DR24,DR0
;---- Variable 'pwm_duty' assigned to Register 'DR24' ----
0005C0 7DF3           MOV      WR30,WR6
;---- Variable 'PWM_CHN_PIN' assigned to Register 'WR30' ----
;---- Variable 'match_temp' assigned to Register 'DR20' ----
                                                ; SOURCE LINE # 169
                                                ; SOURCE LINE # 171
0005C2 0E34           SRA      WR6
0005C4 0E34           SRA      WR6
0005C6 0E34           SRA      WR6
0005C8 0E34           SRA      WR6
0005CA 0E34           SRA      WR6
0005CC 0E34           SRA      WR6
0005CE 1A26           MOVS     WR4,R6
0005D0 1A24           MOVS     WR4,R4
0005D2 7F01           MOV      DR0,DR4
0005D4 2F01           ADD      DR0,DR4
0005D6 2F00           ADD      DR0,DR0
0005D8 2E040000    R  ADD      WR0,#WORD2 PWM_ARR_ADDR
0005DC 2E080000    R  ADD      DR0,#WORD0 PWM_ARR_ADDR
0005E0 69300002       MOV      WR6,@DR0+0x2
0005E4 0B0A20         MOV      WR4,@DR0
0005E7 0B1C           INC      DR4,#01H
0005E9 7E1B70         MOV      R7,@DR4
0005EC 0AE7           MOVZ     WR28,R7
0005EE 69300002       MOV      WR6,@DR0+0x2
0005F2 0B0A20         MOV      WR4,@DR0
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 17  

0005F5 7E1B70         MOV      R7,@DR4
0005F8 0A97           MOVZ     WR18,R7
0005FA 7D39           MOV      WR6,WR18
0005FC 7C67           MOV      R6,R7
0005FE 6C77           XRL      R7,R7
000600 7D93           MOV      WR18,WR6
000602 4D9E           ORL      WR18,WR28
000604 6D88           XRL      WR16,WR16
;---- Variable 'arrange' assigned to Register 'DR16' ----
                                                ; SOURCE LINE # 173
000606 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 175
000609 7F16           MOV      DR4,DR24
00060B E4             CLR      A                ; A=R11
00060C 9A000000    E  ECALL    ?C?FCASTL?
000610 7F61           MOV      DR24,DR4
000612 7E144000       MOV      WR2,#04000H
000616 7E04461C       MOV      WR0,#0461CH
00061A 9A000000    E  ECALL    ?C?FPCMP3?
00061E 6823           JE       ?C0046
                                                ; SOURCE LINE # 177
000620 7E144000       MOV      WR2,#04000H
000624 7E04461C       MOV      WR0,#0461CH
000628 7F16           MOV      DR4,DR24
00062A 9A000000    E  ECALL    ?C?FPDIV?
00062E 7F01           MOV      DR0,DR4
000630 7F14           MOV      DR4,DR16
000632 E4             CLR      A                ; A=R11
000633 9A000000    E  ECALL    ?C?FCASTL?
000637 9A000000    E  ECALL    ?C?FPMUL?
00063B 9A000000    E  ECALL    ?C?CASTF?
00063F 7F51           MOV      DR20,DR4
                                                ; SOURCE LINE # 178
000641 8004           SJMP     ?C0047
               ?C0046:
                                                ; SOURCE LINE # 181
000643 7F54           MOV      DR20,DR16
000645 0B5C           INC      DR20,#01H
                                                ; SOURCE LINE # 182
               ?C0047:
                                                ; SOURCE LINE # 184
000647 7D1B           MOV      WR2,WR22
000649 7D3F           MOV      WR6,WR30
00064B 0E34           SRA      WR6
00064D 0E34           SRA      WR6
00064F 0E34           SRA      WR6
000651 0E34           SRA      WR6
000653 1A26           MOVS     WR4,R6
000655 1A24           MOVS     WR4,R4
000657 7F21           MOV      DR8,DR4
000659 2F21           ADD      DR8,DR4
00065B 2F22           ADD      DR8,DR8
00065D 2E440000    R  ADD      WR8,#WORD2 PWM_CCR_ADDR
000661 2E280000    R  ADD      DR8,#WORD0 PWM_CCR_ADDR
000665 69320002       MOV      WR6,@DR8+0x2
000669 0B2A20         MOV      WR4,@DR8
00066C 7A1B20         MOV      @DR4,R2
                                                ; SOURCE LINE # 185
00066F 7D3B           MOV      WR6,WR22
000671 7D3F           MOV      WR6,WR30
000673 0E34           SRA      WR6
000675 0E34           SRA      WR6
000677 0E34           SRA      WR6
000679 0E34           SRA      WR6
00067B 1A26           MOVS     WR4,R6
00067D 1A24           MOVS     WR4,R4
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 18  

00067F 7F21           MOV      DR8,DR4
000681 2F21           ADD      DR8,DR4
000683 2F22           ADD      DR8,DR8
000685 2E440000    R  ADD      WR8,#WORD2 PWM_CCR_ADDR
000689 2E280000    R  ADD      DR8,#WORD0 PWM_CCR_ADDR
00068D 69320002       MOV      WR6,@DR8+0x2
000691 0B2A20         MOV      WR4,@DR8
000694 0B1C           INC      DR4,#01H
000696 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 187
000699 AA             ERET     
;       FUNCTION PWM_SET_Duty? (END)

;       FUNCTION PWM_SET_Frequency? (BEGIN)
                                                ; SOURCE LINE # 197
;---- Variable 'frequency' assigned to Register 'DR24' ----
00069A 7DF3           MOV      WR30,WR6
;---- Variable 'PWM_CHN_PIN' assigned to Register 'WR30' ----
;---- Variable 'match_temp' assigned to Register 'DR20' ----
                                                ; SOURCE LINE # 198
                                                ; SOURCE LINE # 201
                                                ; SOURCE LINE # 203
00069C 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 206
00069F 7E344000       MOV      WR6,#04000H
0006A3 7E2401FA       MOV      WR4,#01FAH
0006A7 9A000000    E  ECALL    ?C?ULDIV?
0006AB 7D12           MOV      WR2,WR4
0006AD 6D00           XRL      WR0,WR0
0006AF 7DE2           MOV      WR28,WR4
;---- Variable 'Frequency_Division' assigned to Register 'WR28' ----
                                                ; SOURCE LINE # 207
;---- Variable 'period_temp' assigned to Register 'DR24' ----
                                                ; SOURCE LINE # 208
0006B1 0B14           INC      WR2,#01H
0006B3 9A000000    E  ECALL    ?C?ULIDIV?
0006B7 7F61           MOV      DR24,DR4
0006B9 1B6C           DEC      DR24,#01H
                                                ; SOURCE LINE # 210
0006BB 7E1F0000    R  MOV      DR4,pwm_duty
0006BF E4             CLR      A                ; A=R11
0006C0 9A000000    E  ECALL    ?C?FCASTL?
0006C4 7F41           MOV      DR16,DR4
0006C6 7E144000       MOV      WR2,#04000H
0006CA 7E04461C       MOV      WR0,#0461CH
0006CE 9A000000    E  ECALL    ?C?FPCMP3?
0006D2 6823           JE       ?C0048
                                                ; SOURCE LINE # 212
0006D4 7E144000       MOV      WR2,#04000H
0006D8 7E04461C       MOV      WR0,#0461CH
0006DC 7F14           MOV      DR4,DR16
0006DE 9A000000    E  ECALL    ?C?FPDIV?
0006E2 7F01           MOV      DR0,DR4
0006E4 7F16           MOV      DR4,DR24
0006E6 E4             CLR      A                ; A=R11
0006E7 9A000000    E  ECALL    ?C?FCASTL?
0006EB 9A000000    E  ECALL    ?C?FPMUL?
0006EF 9A000000    E  ECALL    ?C?CASTF?
0006F3 7F51           MOV      DR20,DR4
                                                ; SOURCE LINE # 213
0006F5 8004           SJMP     ?C0049
               ?C0048:
                                                ; SOURCE LINE # 216
0006F7 7F56           MOV      DR20,DR24
0006F9 0B5C           INC      DR20,#01H
                                                ; SOURCE LINE # 217
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 19  

               ?C0049:
                                                ; SOURCE LINE # 219
0006FB BEF40040       CMP      WR30,#040H
0006FF 4819           JSL      ?C0050
                                                ; SOURCE LINE # 222
000701 7D1E           MOV      WR2,WR28
000703 0A12           MOVZ     WR2,R2
000705 7E34FEF0       MOV      WR6,#0FEF0H
000709 7E24007E       MOV      WR4,#07EH
00070D 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 223
000710 7D3E           MOV      WR6,WR28
000712 7C37           MOV      R3,R7
000714 7E34FEF1       MOV      WR6,#0FEF1H
                                                ; SOURCE LINE # 224
000718 8017           SJMP     ?C0109
               ?C0050:
                                                ; SOURCE LINE # 228
00071A 7D1E           MOV      WR2,WR28
00071C 0A12           MOVZ     WR2,R2
00071E 7E34FED0       MOV      WR6,#0FED0H
000722 7E24007E       MOV      WR4,#07EH
000726 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 229
000729 7D3E           MOV      WR6,WR28
00072B 7C37           MOV      R3,R7
00072D 7E34FED1       MOV      WR6,#0FED1H
               ?C0109:
000731 7E24007E       MOV      WR4,#07EH
000735 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 230
                                                ; SOURCE LINE # 233
000738 7D1D           MOV      WR2,WR26
00073A 7D3F           MOV      WR6,WR30
00073C 0E34           SRA      WR6
00073E 0E34           SRA      WR6
000740 0E34           SRA      WR6
000742 0E34           SRA      WR6
000744 0E34           SRA      WR6
000746 0E34           SRA      WR6
000748 1A26           MOVS     WR4,R6
00074A 1A24           MOVS     WR4,R4
00074C 7F21           MOV      DR8,DR4
00074E 2F21           ADD      DR8,DR4
000750 2F22           ADD      DR8,DR8
000752 2E440000    R  ADD      WR8,#WORD2 PWM_ARR_ADDR
000756 2E280000    R  ADD      DR8,#WORD0 PWM_ARR_ADDR
00075A 69320002       MOV      WR6,@DR8+0x2
00075E 0B2A20         MOV      WR4,@DR8
000761 7A1B20         MOV      @DR4,R2
                                                ; SOURCE LINE # 234
000764 7D3D           MOV      WR6,WR26
000766 7D3F           MOV      WR6,WR30
000768 0E34           SRA      WR6
00076A 0E34           SRA      WR6
00076C 0E34           SRA      WR6
00076E 0E34           SRA      WR6
000770 0E34           SRA      WR6
000772 0E34           SRA      WR6
000774 1A26           MOVS     WR4,R6
000776 1A24           MOVS     WR4,R4
000778 7F21           MOV      DR8,DR4
00077A 2F21           ADD      DR8,DR4
00077C 2F22           ADD      DR8,DR8
00077E 2E440000    R  ADD      WR8,#WORD2 PWM_ARR_ADDR
000782 2E280000    R  ADD      DR8,#WORD0 PWM_ARR_ADDR
C251 COMPILER V5.60.0,  CNU_PIE_PWM                                                        24/08/26  10:23:43  PAGE 20  

000786 69320002       MOV      WR6,@DR8+0x2
00078A 0B2A20         MOV      WR4,@DR8
00078D 0B1C           INC      DR4,#01H
00078F 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 237
000792 7D1B           MOV      WR2,WR22
000794 7D3F           MOV      WR6,WR30
000796 0E34           SRA      WR6
000798 0E34           SRA      WR6
00079A 0E34           SRA      WR6
00079C 0E34           SRA      WR6
00079E 1A26           MOVS     WR4,R6
0007A0 1A24           MOVS     WR4,R4
0007A2 7F21           MOV      DR8,DR4
0007A4 2F21           ADD      DR8,DR4
0007A6 2F22           ADD      DR8,DR8
0007A8 2E440000    R  ADD      WR8,#WORD2 PWM_CCR_ADDR
0007AC 2E280000    R  ADD      DR8,#WORD0 PWM_CCR_ADDR
0007B0 69320002       MOV      WR6,@DR8+0x2
0007B4 0B2A20         MOV      WR4,@DR8
0007B7 7A1B20         MOV      @DR4,R2
                                                ; SOURCE LINE # 238
0007BA 7D3B           MOV      WR6,WR22
0007BC 7D3F           MOV      WR6,WR30
0007BE 0E34           SRA      WR6
0007C0 0E34           SRA      WR6
0007C2 0E34           SRA      WR6
0007C4 0E34           SRA      WR6
0007C6 1A26           MOVS     WR4,R6
0007C8 1A24           MOVS     WR4,R4
0007CA 7F21           MOV      DR8,DR4
0007CC 2F21           ADD      DR8,DR4
0007CE 2F22           ADD      DR8,DR8
0007D0 2E440000    R  ADD      WR8,#WORD2 PWM_CCR_ADDR
0007D4 2E280000    R  ADD      DR8,#WORD0 PWM_CCR_ADDR
0007D8 69320002       MOV      WR6,@DR8+0x2
0007DC 0B2A20         MOV      WR4,@DR8
0007DF 0B1C           INC      DR4,#01H
0007E1 7A1B30         MOV      @DR4,R3
                                                ; SOURCE LINE # 239
0007E4 AA             ERET     
;       FUNCTION PWM_SET_Frequency? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      2021     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------         16
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        88     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

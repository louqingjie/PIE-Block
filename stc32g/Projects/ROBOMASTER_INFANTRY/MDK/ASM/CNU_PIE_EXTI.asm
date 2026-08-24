C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_EXTI
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_EXTI.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_EXTI.c XSMALL ROM(HUGE) BROWSE 
                    -INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTO
                    -R(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_EXTI.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_EXTI.obj) 

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
   12           * @file       CNU_PIE_EXTI.c
   13           * @brief      EXTI
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_EXTI.h"
   20           
   21           uint8_t Port_Exti_Flag[8];
   22           
   23          uint8_t GPIO_EXTI_Init(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin , EXTI_MODE_Enum EXTI_Mode)
   24           {
   25   1         if(GPIO_Port > GPIO_P7)      return FAIL; //初始化错误值返回FAIL
   26   1         if(GPIO_Pin  > GPIO_Pin_All) return FAIL; //初始化错误值返回FAIL
   27   1         if(EXTI_Mode > HIGH_LEVEL)   return FAIL; //初始化错误值返回FAIL
   28   1         
   29   1         switch (GPIO_Port)
   30   1         {
   31   2           case GPIO_P0://端口0
   32   2             switch (EXTI_Mode)
   33   2             {
   34   3               P0INTE |= GPIO_Pin;//使能P0段口对应引脚开启外部中断
   35   3               case FALLING_EDGE:
   36   3                 P0IM1 &= ~GPIO_Pin,  P0IM0 &= ~GPIO_Pin;  break; //下降沿中断     
   37   3               case RISING_EDGE:
   38   3                 P0IM1 &= ~GPIO_Pin,  P0IM0 |=  GPIO_Pin;   break;//上升沿中断
   39   3               case LOW_LEVEL:
   40   3                 P0IM1 |=  GPIO_Pin,  P0IM0 &= ~GPIO_Pin;  break; //低电平中断
   41   3               case HIGH_LEVEL:
   42   3                 P0IM1 |=  GPIO_Pin,  P0IM0 |=  GPIO_Pin;   break;//高电平中断
   43   3               default:
   44   3                 return FAIL; break;//初始化失败
   45   3             }break;
   46   2           case GPIO_P1://端口1
   47   2             switch (EXTI_Mode)
   48   2             {
   49   3               P1INTE |= GPIO_Pin;//使能P1段口对应引脚开启外部中断
   50   3               case FALLING_EDGE:
   51   3                 P1IM1 &= ~GPIO_Pin,  P1IM0 &= ~GPIO_Pin;  break; //下降沿中断     
   52   3               case RISING_EDGE:
   53   3                 P1IM1 &= ~GPIO_Pin,  P1IM0 |=  GPIO_Pin;   break;//上升沿中断
   54   3               case LOW_LEVEL:
   55   3                 P1IM1 |=  GPIO_Pin,  P1IM0 &= ~GPIO_Pin;  break; //低电平中断
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 2   

   56   3               case HIGH_LEVEL:
   57   3                 P1IM1 |=  GPIO_Pin,  P1IM0 |=  GPIO_Pin;   break;//高电平中断
   58   3               default:
   59   3                 return FAIL; break;//初始化失败
   60   3             }break;    
   61   2           case GPIO_P2://端口2
   62   2             switch (EXTI_Mode)
   63   2             {
   64   3               P2INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
   65   3               case FALLING_EDGE:
   66   3                 P2IM1 &= ~GPIO_Pin,  P2IM0 &= ~GPIO_Pin;  break; //下降沿中断     
   67   3               case RISING_EDGE:
   68   3                 P2IM1 &= ~GPIO_Pin,  P2IM0 |=  GPIO_Pin;   break;//上升沿中断
   69   3               case LOW_LEVEL:
   70   3                 P2IM1 |=  GPIO_Pin,  P2IM0 &= ~GPIO_Pin;  break; //低电平中断
   71   3               case HIGH_LEVEL:
   72   3                 P2IM1 |=  GPIO_Pin,  P2IM0 |=  GPIO_Pin;   break;//高电平中断
   73   3               default:
   74   3                 return FAIL; break;//初始化失败
   75   3             }break;    
   76   2           case GPIO_P3://端口3
   77   2             switch (EXTI_Mode)
   78   2             {
   79   3               P3INTE |= GPIO_Pin;//使能P3段口对应引脚开启外部中断
   80   3               case FALLING_EDGE:
   81   3                 P3IM1 &= ~GPIO_Pin,  P3IM0 &= ~GPIO_Pin;  break; //下降沿中断     
   82   3               case RISING_EDGE:
   83   3                 P3IM1 &= ~GPIO_Pin,  P3IM0 |=  GPIO_Pin;   break;//上升沿中断
   84   3               case LOW_LEVEL:
   85   3                 P3IM1 |=  GPIO_Pin,  P3IM0 &= ~GPIO_Pin;  break; //低电平中断
   86   3               case HIGH_LEVEL:
   87   3                 P3IM1 |=  GPIO_Pin,  P3IM0 |=  GPIO_Pin;   break;//高电平中断
   88   3               default:
   89   3                 return FAIL; break;//初始化失败
   90   3             }break;  
   91   2           case GPIO_P4://端口4
   92   2             switch (EXTI_Mode)
   93   2             {
   94   3               P4INTE |= GPIO_Pin;//使能P4段口对应引脚开启外部中断
   95   3               case FALLING_EDGE:
   96   3                 P4IM1 &= ~GPIO_Pin,  P4IM0 &= ~GPIO_Pin;  break; //下降沿中断     
   97   3               case RISING_EDGE:
   98   3                 P4IM1 &= ~GPIO_Pin,  P4IM0 |=  GPIO_Pin;   break;//上升沿中断
   99   3               case LOW_LEVEL:
  100   3                 P4IM1 |=  GPIO_Pin,  P4IM0 &= ~GPIO_Pin;  break; //低电平中断
  101   3               case HIGH_LEVEL:
  102   3                 P4IM1 |=  GPIO_Pin,  P4IM0 |=  GPIO_Pin;   break;//高电平中断
  103   3               default:
  104   3                 return FAIL; break;//初始化失败
  105   3             }break;  
  106   2           case GPIO_P5://端口5
  107   2             switch (EXTI_Mode)
  108   2             {
  109   3               P5INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
  110   3               case FALLING_EDGE:
  111   3                 P5IM1 &= ~GPIO_Pin,  P5IM0 &= ~GPIO_Pin;  break; //下降沿中断     
  112   3               case RISING_EDGE:
  113   3                 P5IM1 &= ~GPIO_Pin,  P5IM0 |=  GPIO_Pin;   break;//上升沿中断
  114   3               case LOW_LEVEL:
  115   3                 P5IM1 |=  GPIO_Pin,  P5IM0 &= ~GPIO_Pin;  break; //低电平中断
  116   3               case HIGH_LEVEL:
  117   3                 P5IM1 |=  GPIO_Pin,  P5IM0 |=  GPIO_Pin;   break;//高电平中断
  118   3               default:
  119   3                 return FAIL; break;//初始化失败
  120   3             }break;    
  121   2           case GPIO_P6://端口6
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 3   

  122   2             switch (EXTI_Mode)
  123   2             {
  124   3               P6INTE |= GPIO_Pin;//使能P6段口对应引脚开启外部中断
  125   3               case FALLING_EDGE:
  126   3                 P6IM1 &= ~GPIO_Pin,  P6IM0 &= ~GPIO_Pin;  break; //下降沿中断     
  127   3               case RISING_EDGE:
  128   3                 P6IM1 &= ~GPIO_Pin,  P6IM0 |=  GPIO_Pin;   break;//上升沿中断
  129   3               case LOW_LEVEL:
  130   3                 P6IM1 |=  GPIO_Pin,  P6IM0 &= ~GPIO_Pin;  break; //低电平中断
  131   3               case HIGH_LEVEL:
  132   3                 P6IM1 |=  GPIO_Pin,  P6IM0 |=  GPIO_Pin;   break;//高电平中断
  133   3               default:
  134   3                 return FAIL; break;//初始化失败
  135   3             }break;
  136   2           case GPIO_P7://端口7
  137   2             switch (EXTI_Mode)
  138   2             {
  139   3               P7INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
  140   3               case FALLING_EDGE:
  141   3                 P7IM1 &= ~GPIO_Pin,  P7IM0 &= ~GPIO_Pin;  break; //下降沿中断     
  142   3               case RISING_EDGE:
  143   3                 P7IM1 &= ~GPIO_Pin,  P7IM0 |=  GPIO_Pin;   break;//上升沿中断
  144   3               case LOW_LEVEL:
  145   3                 P7IM1 |=  GPIO_Pin,  P7IM0 &= ~GPIO_Pin;  break; //低电平中断
  146   3               case HIGH_LEVEL:
  147   3                 P7IM1 |=  GPIO_Pin,  P7IM0 |=  GPIO_Pin;   break;//高电平中断
  148   3               default:
  149   3                 return FAIL; break;//初始化失败
  150   3             }break;
  151   2           default:
  152   2             return FAIL; break;         
  153   2         }
  154   1        return SUCCEED; //成功
  155   1       }
  156           
  157           uint8_t GPIO_EXTI_Open(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin)
  158           {
  159   1         if(GPIO_Port > GPIO_P7)      return FAIL; //初始化错误值返回FAIL
  160   1         if(GPIO_Pin  > GPIO_Pin_All) return FAIL; //初始化错误值返回FAIL
  161   1         
  162   1         switch (GPIO_Port)
  163   1         {
  164   2           case GPIO_P0://端口0
  165   2                P0INTE |= GPIO_Pin;//使能P0段口对应引脚开启外部中断
  166   2           break;
  167   2           case GPIO_P1://端口1
  168   2                P1INTE |= GPIO_Pin;//使能P1段口对应引脚开启外部中断
  169   2           break;   
  170   2           case GPIO_P2://端口2
  171   2                P2INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
  172   2           break;   
  173   2           case GPIO_P3://端口3
  174   2                P3INTE |= GPIO_Pin;//使能P3段口对应引脚开启外部中断
  175   2           break; 
  176   2           case GPIO_P4://端口4
  177   2                P4INTE |= GPIO_Pin;//使能P4段口对应引脚开启外部中断
  178   2           break; 
  179   2           case GPIO_P5://端口5
  180   2                P5INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
  181   2           break;   
  182   2           case GPIO_P6://端口6
  183   2                P6INTE |= GPIO_Pin;//使能P6段口对应引脚开启外部中断
  184   2           break;
  185   2           case GPIO_P7://端口7
  186   2                P7INTE |= GPIO_Pin;//使能P2段口对应引脚开启外部中断
  187   2           break;
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 4   

  188   2           default:
  189   2             return FAIL; break;         
  190   2         }
  191   1        return SUCCEED; //成功
  192   1       }
  193           
  194           uint8_t GPIO_EXTI_Set_Priority(GPIO_Port_enum GPIO_Port , EXTI_PRIORITY_Enum EXTI_Priority)
  195           {
  196   1         if(GPIO_Port > GPIO_P7)              return FAIL; //初始化错误值返回FAIL
  197   1         if(EXTI_Priority  > Lowest_priority) return FAIL; //初始化错误值返回FAIL
  198   1         
  199   1         switch (GPIO_Port)
  200   1         {
  201   2           case GPIO_P0://端口0
  202   2             switch (EXTI_Priority)
  203   2             {
  204   3               case Highest_priority:
  205   3                 PIN_IP &= ~P0_PRI0RITY,  PIN_IPH &= ~P0_PRI0RITY;   break;  
  206   3               case Second_priority:
  207   3                 PIN_IP |=  P0_PRI0RITY,  PIN_IPH &= ~P0_PRI0RITY;   break;
  208   3               case Third_priority:
  209   3                 PIN_IP &= ~P0_PRI0RITY,  PIN_IPH |=  P0_PRI0RITY;   break;
  210   3               case Lowest_priority:
  211   3                 PIN_IP |=  P0_PRI0RITY,  PIN_IPH |=  P0_PRI0RITY;   break;
  212   3               default:
  213   3                 return FAIL; break;//初始化失败
  214   3             }break;
  215   2           case GPIO_P1://端口1
  216   2             switch (EXTI_Priority)
  217   2             {
  218   3               case Highest_priority:
  219   3                 PIN_IP &= ~P1_PRI0RITY,  PIN_IPH &= ~P1_PRI0RITY;   break; 
  220   3               case Second_priority:
  221   3                 PIN_IP |=  P1_PRI0RITY,  PIN_IPH |=  P1_PRI0RITY;   break;
  222   3               case Third_priority:
  223   3                 PIN_IP |=  P1_PRI0RITY,  PIN_IPH &= ~P1_PRI0RITY;   break;
  224   3               case Lowest_priority:
  225   3                 PIN_IP |=  P1_PRI0RITY,  PIN_IPH |=  P1_PRI0RITY;   break;
  226   3               default:
  227   3                 return FAIL; break;//初始化失败
  228   3             }break;    
  229   2           case GPIO_P2://端口2
  230   2             switch (EXTI_Priority)
  231   2             {
  232   3               case Highest_priority:
  233   3                 PIN_IP &= ~P2_PRI0RITY,  PIN_IPH &= ~P2_PRI0RITY;   break; 
  234   3               case Second_priority:
  235   3                 PIN_IP |=  P2_PRI0RITY,  PIN_IPH |=  P2_PRI0RITY;   break;
  236   3               case Third_priority:
  237   3                 PIN_IP |=  P2_PRI0RITY,  PIN_IPH &= ~P2_PRI0RITY;   break;
  238   3               case Lowest_priority:
  239   3                 PIN_IP |=  P2_PRI0RITY,  PIN_IPH |=  P2_PRI0RITY;   break;
  240   3               default:
  241   3                 return FAIL; break;//初始化失败
  242   3             }break;    
  243   2           case GPIO_P3://端口3
  244   2             switch (EXTI_Priority)
  245   2             {
  246   3               case Highest_priority:
  247   3                 PIN_IP &= ~P3_PRI0RITY,  PIN_IPH &= ~P3_PRI0RITY;   break; 
  248   3               case Second_priority:
  249   3                 PIN_IP |=  P3_PRI0RITY,  PIN_IPH |=  P3_PRI0RITY;   break;
  250   3               case Third_priority:
  251   3                 PIN_IP |=  P3_PRI0RITY,  PIN_IPH &= ~P3_PRI0RITY;   break;
  252   3               case Lowest_priority:
  253   3                 PIN_IP |=  P3_PRI0RITY,  PIN_IPH |=  P3_PRI0RITY;   break;
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 5   

  254   3               default:
  255   3                 return FAIL; break;//初始化失败
  256   3             }break;  
  257   2           case GPIO_P4://端口4
  258   2             switch (EXTI_Priority)
  259   2             {
  260   3               case Highest_priority:
  261   3                 PIN_IP &= ~P4_PRI0RITY,  PIN_IPH &= ~P4_PRI0RITY;   break; 
  262   3               case Second_priority:
  263   3                 PIN_IP |=  P4_PRI0RITY,  PIN_IPH |=  P4_PRI0RITY;   break;
  264   3               case Third_priority:
  265   3                 PIN_IP |=  P4_PRI0RITY,  PIN_IPH &= ~P4_PRI0RITY;   break;
  266   3               case Lowest_priority:
  267   3                 PIN_IP |=  P4_PRI0RITY,  PIN_IPH |=  P4_PRI0RITY;   break;
  268   3               default:
  269   3                 return FAIL; break;//初始化失败
  270   3             }break;  
  271   2           case GPIO_P5://端口5
  272   2             switch (EXTI_Priority)
  273   2             {
  274   3               case Highest_priority:
  275   3                 PIN_IP &= ~P5_PRI0RITY,  PIN_IPH &= ~P5_PRI0RITY;   break; 
  276   3               case Second_priority:
  277   3                 PIN_IP |=  P5_PRI0RITY,  PIN_IPH |=  P5_PRI0RITY;   break;
  278   3               case Third_priority:
  279   3                 PIN_IP |=  P5_PRI0RITY,  PIN_IPH &= ~P5_PRI0RITY;   break;
  280   3               case Lowest_priority:
  281   3                 PIN_IP |=  P5_PRI0RITY,  PIN_IPH |=  P5_PRI0RITY;   break;
  282   3               default:
  283   3                 return FAIL; break;//初始化失败
  284   3             }break;    
  285   2           case GPIO_P6://端口6
  286   2             switch (EXTI_Priority)
  287   2             {
  288   3               case Highest_priority:
  289   3                 PIN_IP &= ~P6_PRI0RITY,  PIN_IPH &= ~P6_PRI0RITY;   break; 
  290   3               case Second_priority:
  291   3                 PIN_IP |=  P6_PRI0RITY,  PIN_IPH |=  P6_PRI0RITY;   break;
  292   3               case Third_priority:
  293   3                 PIN_IP |=  P6_PRI0RITY,  PIN_IPH &= ~P6_PRI0RITY;   break;
  294   3               case Lowest_priority:
  295   3                 PIN_IP |=  P6_PRI0RITY,  PIN_IPH |=  P6_PRI0RITY;   break;
  296   3               default:
  297   3                 return FAIL; break;//初始化失败
  298   3             }break;
  299   2           case GPIO_P7://端口7
  300   2             switch (EXTI_Priority)
  301   2             {
  302   3               case Highest_priority:
  303   3                 PIN_IP &= ~P7_PRI0RITY,  PIN_IPH &= ~P7_PRI0RITY;   break; 
  304   3               case Second_priority:
  305   3                 PIN_IP |=  P7_PRI0RITY,  PIN_IPH |=  P7_PRI0RITY;   break;
  306   3               case Third_priority:
  307   3                 PIN_IP |=  P7_PRI0RITY,  PIN_IPH &= ~P7_PRI0RITY;   break;
  308   3               case Lowest_priority:
  309   3                 PIN_IP |=  P7_PRI0RITY,  PIN_IPH |=  P7_PRI0RITY;   break;
  310   3               default:
  311   3                 return FAIL; break;//初始化失败
  312   3             }break;
  313   2           default:
  314   2             return FAIL; break;         
  315   2         }
  316   1        return SUCCEED; //成功
  317   1       }
  318           
  319          uint8_t GPIO_EXTI_Flag_Read(GPIO_Port_enum GPIO_Port)
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 6   

  320          {
  321   1         switch (GPIO_Port)
  322   1         {
  323   2           case GPIO_P0://端口0
  324   2            Port_Exti_Flag[0] = P0INTF  ;break; 
  325   2           case GPIO_P1://端口1         
  326   2            Port_Exti_Flag[1] = P1INTF  ;break; 
  327   2           case GPIO_P2://端口2         
  328   2            Port_Exti_Flag[2] = P2INTF  ;break; 
  329   2           case GPIO_P3://端口3         
  330   2            Port_Exti_Flag[3] = P3INTF  ;break;  
  331   2           case GPIO_P4://端口4         
  332   2            Port_Exti_Flag[4] = P4INTF  ;break; 
  333   2           case GPIO_P5://端口5         
  334   2            Port_Exti_Flag[5] = P5INTF  ;break; 
  335   2           case GPIO_P6://端口6         
  336   2            Port_Exti_Flag[6] = P6INTF  ;break; 
  337   2           case GPIO_P7://端口7         
  338   2            Port_Exti_Flag[7] = P7INTF  ;break; 
  339   2           default:
  340   2             return FAIL; break;         
  341   2         }
  342   1        return SUCCEED; //成功
  343   1      }
  344           
  345          uint8_t GPIO_EXTI_Flag_Clear(GPIO_Port_enum GPIO_Port)
  346          {
  347   1         switch (GPIO_Port)
  348   1         {
  349   2           case GPIO_P0://端口0
  350   2            P0INTF = 0;break; 
  351   2           case GPIO_P1://端口1
  352   2            P1INTF = 0;break; 
  353   2           case GPIO_P2://端口2
  354   2            P2INTF = 0;break; 
  355   2           case GPIO_P3://端口3
  356   2            P3INTF = 0;break;  
  357   2           case GPIO_P4://端口4
  358   2            P4INTF = 0;break; 
  359   2           case GPIO_P5://端口5
  360   2            P5INTF = 0;break; 
  361   2           case GPIO_P6://端口6
  362   2            P6INTF = 0;break; 
  363   2           case GPIO_P7://端口7
  364   2            P7INTF = 0;break; 
  365   2           default:
  366   2             return FAIL; break;         
  367   2         }
  368   1        return SUCCEED; //成功
  369   1      }
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 7   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION GPIO_EXTI_Init? (BEGIN)
                                                ; SOURCE LINE # 23
000000 7D41           MOV      WR8,WR2
;---- Variable 'EXTI_Mode' assigned to Register 'WR8' ----
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
000002 7D13           MOV      WR2,WR6
;---- Variable 'GPIO_Port' assigned to Register 'WR2' ----
                                                ; SOURCE LINE # 25
000004 BE140007       CMP      WR2,#07H
000008 0802           JSLE     ?C0001
00000A E4             CLR      A                ; A=R11
00000B AA             ERET     
               ?C0001:
                                                ; SOURCE LINE # 26
00000C BE2400FF       CMP      WR4,#0FFH
000010 0802           JSLE     ?C0003
000012 E4             CLR      A                ; A=R11
000013 AA             ERET     
               ?C0003:
                                                ; SOURCE LINE # 27
000014 BE440003       CMP      WR8,#03H
000018 0802           JSLE     ?C0004
00001A E4             CLR      A                ; A=R11
00001B AA             ERET     
               ?C0004:
                                                ; SOURCE LINE # 29
00001C 7D51           MOV      WR10,WR2
00001E BE540008       CMP      WR10,#08H
000022 4003        R  JC       $ + 5H
000024 020000      R  LJMP     ?C0007
000027 7EA003         MOV      R10,#03H
00002A A4             MUL      AB
00002B 900000      R  MOV      DPTR,#?C0160
00002E 73             JMP      @A+DPTR
               ?C0160:
00002F 020000      R  LJMP     ?C0006
000032 020000      R  LJMP     ?C0008
000035 020000      R  LJMP     ?C0009
000038 020000      R  LJMP     ?C0010
00003B 020000      R  LJMP     ?C0011
00003E 020000      R  LJMP     ?C0012
000041 020000      R  LJMP     ?C0013
000044 020000      R  LJMP     ?C0014
                                                ; SOURCE LINE # 31
               ?C0006:
                                                ; SOURCE LINE # 32
000047 7D34           MOV      WR6,WR8
000049 1B34           DEC      WR6,#01H
00004B 6824           JE       ?C0018
00004D 1B34           DEC      WR6,#01H
00004F 6835           JE       ?C0019
000051 1B34           DEC      WR6,#01H
000053 684C           JE       ?C0020
000055 2E340003       ADD      WR6,#03H
000059 785F           JNE      ?C0017
                                                ; SOURCE LINE # 34
                                                ; SOURCE LINE # 35
               ?C0016:
                                                ; SOURCE LINE # 36
00005B 7CB5           MOV      R11,R5           ; A=R11
00005D 64FF           XRL      A,#0FFH          ; A=R11
00005F 7E14FD30       MOV      WR2,#0FD30H
000063 7E04007E       MOV      WR0,#07EH
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 8   

000067 7E0BA0         MOV      R10,@DR0
00006A 5CAB           ANL      R10,R11          ; A=R11
00006C 7A0BA0         MOV      @DR0,R10
00006F 8029           SJMP     ?C0169
                                                ; SOURCE LINE # 37
               ?C0018:
                                                ; SOURCE LINE # 38
000071 7C65           MOV      R6,R5
000073 7CB5           MOV      R11,R5           ; A=R11
000075 64FF           XRL      A,#0FFH          ; A=R11
000077 7E14FD30       MOV      WR2,#0FD30H
00007B 7E04007E       MOV      WR0,#07EH
00007F 7E0B70         MOV      R7,@DR0
000082 5C7B           ANL      R7,R11           ; A=R11
000084 802A           SJMP     ?C0170
                                                ; SOURCE LINE # 39
               ?C0019:
                                                ; SOURCE LINE # 40
000086 7CB5           MOV      R11,R5           ; A=R11
000088 7E14FD30       MOV      WR2,#0FD30H
00008C 7E04007E       MOV      WR0,#07EH
000090 7E0BA0         MOV      R10,@DR0
000093 4CA5           ORL      R10,R5
000095 7A0BA0         MOV      @DR0,R10
000098 64FF           XRL      A,#0FFH          ; A=R11
               ?C0169:
00009A 7E14FD20       MOV      WR2,#0FD20H
00009E 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 41
               ?C0020:
                                                ; SOURCE LINE # 42
0000A1 7C65           MOV      R6,R5
0000A3 7E14FD30       MOV      WR2,#0FD30H
0000A7 7E04007E       MOV      WR0,#07EH
0000AB 7E0B70         MOV      R7,@DR0
0000AE 4C75           ORL      R7,R5
               ?C0170:
0000B0 7A0B70         MOV      @DR0,R7
0000B3 7E14FD20       MOV      WR2,#0FD20H
0000B7 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 43
               ?C0017:
                                                ; SOURCE LINE # 44
0000BA E4             CLR      A                ; A=R11
0000BB AA             ERET     
                                                ; SOURCE LINE # 45
                                                ; SOURCE LINE # 46
               ?C0008:
                                                ; SOURCE LINE # 47
0000BC 7D34           MOV      WR6,WR8
0000BE 1B34           DEC      WR6,#01H
0000C0 6829           JE       ?C0024
0000C2 1B34           DEC      WR6,#01H
0000C4 6842           JE       ?C0025
0000C6 1B34           DEC      WR6,#01H
0000C8 6859           JE       ?C0026
0000CA 2E340003       ADD      WR6,#03H
0000CE 786C           JNE      ?C0023
                                                ; SOURCE LINE # 49
                                                ; SOURCE LINE # 50
               ?C0022:
                                                ; SOURCE LINE # 51
0000D0 7CB5           MOV      R11,R5           ; A=R11
0000D2 64FF           XRL      A,#0FFH          ; A=R11
0000D4 7E14FD31       MOV      WR2,#0FD31H
0000D8 7E04007E       MOV      WR0,#07EH
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 9   

0000DC 7E0BA0         MOV      R10,@DR0
0000DF 5CAB           ANL      R10,R11          ; A=R11
0000E1 7A0BA0         MOV      @DR0,R10
0000E4 7E14FD21       MOV      WR2,#0FD21H
0000E8 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 52
               ?C0024:
                                                ; SOURCE LINE # 53
0000EB 7C65           MOV      R6,R5
0000ED 7CB5           MOV      R11,R5           ; A=R11
0000EF 64FF           XRL      A,#0FFH          ; A=R11
0000F1 7E14FD31       MOV      WR2,#0FD31H
0000F5 7E04007E       MOV      WR0,#07EH
0000F9 7E0B70         MOV      R7,@DR0
0000FC 5C7B           ANL      R7,R11           ; A=R11
0000FE 7A0B70         MOV      @DR0,R7
000101 7E14FD21       MOV      WR2,#0FD21H
000105 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 54
               ?C0025:
                                                ; SOURCE LINE # 55
000108 7CB5           MOV      R11,R5           ; A=R11
00010A 7E14FD31       MOV      WR2,#0FD31H
00010E 7E04007E       MOV      WR0,#07EH
000112 7E0BA0         MOV      R10,@DR0
000115 4CA5           ORL      R10,R5
000117 7A0BA0         MOV      @DR0,R10
00011A 64FF           XRL      A,#0FFH          ; A=R11
00011C 7E14FD21       MOV      WR2,#0FD21H
000120 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 56
               ?C0026:
                                                ; SOURCE LINE # 57
000123 7C65           MOV      R6,R5
000125 7E14FD31       MOV      WR2,#0FD31H
000129 7E04007E       MOV      WR0,#07EH
00012D 7E0B70         MOV      R7,@DR0
000130 4C75           ORL      R7,R5
000132 7A0B70         MOV      @DR0,R7
000135 7E14FD21       MOV      WR2,#0FD21H
000139 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 58
               ?C0023:
                                                ; SOURCE LINE # 59
00013C E4             CLR      A                ; A=R11
00013D AA             ERET     
                                                ; SOURCE LINE # 60
                                                ; SOURCE LINE # 61
               ?C0009:
                                                ; SOURCE LINE # 62
00013E 7D34           MOV      WR6,WR8
000140 1B34           DEC      WR6,#01H
000142 6829           JE       ?C0030
000144 1B34           DEC      WR6,#01H
000146 6842           JE       ?C0031
000148 1B34           DEC      WR6,#01H
00014A 6859           JE       ?C0032
00014C 2E340003       ADD      WR6,#03H
000150 786C           JNE      ?C0029
                                                ; SOURCE LINE # 64
                                                ; SOURCE LINE # 65
               ?C0028:
                                                ; SOURCE LINE # 66
000152 7CB5           MOV      R11,R5           ; A=R11
000154 64FF           XRL      A,#0FFH          ; A=R11
000156 7E14FD32       MOV      WR2,#0FD32H
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 10  

00015A 7E04007E       MOV      WR0,#07EH
00015E 7E0BA0         MOV      R10,@DR0
000161 5CAB           ANL      R10,R11          ; A=R11
000163 7A0BA0         MOV      @DR0,R10
000166 7E14FD22       MOV      WR2,#0FD22H
00016A 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 67
               ?C0030:
                                                ; SOURCE LINE # 68
00016D 7C65           MOV      R6,R5
00016F 7CB5           MOV      R11,R5           ; A=R11
000171 64FF           XRL      A,#0FFH          ; A=R11
000173 7E14FD32       MOV      WR2,#0FD32H
000177 7E04007E       MOV      WR0,#07EH
00017B 7E0B70         MOV      R7,@DR0
00017E 5C7B           ANL      R7,R11           ; A=R11
000180 7A0B70         MOV      @DR0,R7
000183 7E14FD22       MOV      WR2,#0FD22H
000187 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 69
               ?C0031:
                                                ; SOURCE LINE # 70
00018A 7CB5           MOV      R11,R5           ; A=R11
00018C 7E14FD32       MOV      WR2,#0FD32H
000190 7E04007E       MOV      WR0,#07EH
000194 7E0BA0         MOV      R10,@DR0
000197 4CA5           ORL      R10,R5
000199 7A0BA0         MOV      @DR0,R10
00019C 64FF           XRL      A,#0FFH          ; A=R11
00019E 7E14FD22       MOV      WR2,#0FD22H
0001A2 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 71
               ?C0032:
                                                ; SOURCE LINE # 72
0001A5 7C65           MOV      R6,R5
0001A7 7E14FD32       MOV      WR2,#0FD32H
0001AB 7E04007E       MOV      WR0,#07EH
0001AF 7E0B70         MOV      R7,@DR0
0001B2 4C75           ORL      R7,R5
0001B4 7A0B70         MOV      @DR0,R7
0001B7 7E14FD22       MOV      WR2,#0FD22H
0001BB 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 73
               ?C0029:
                                                ; SOURCE LINE # 74
0001BE E4             CLR      A                ; A=R11
0001BF AA             ERET     
                                                ; SOURCE LINE # 75
                                                ; SOURCE LINE # 76
               ?C0010:
                                                ; SOURCE LINE # 77
0001C0 7D34           MOV      WR6,WR8
0001C2 1B34           DEC      WR6,#01H
0001C4 6829           JE       ?C0036
0001C6 1B34           DEC      WR6,#01H
0001C8 6842           JE       ?C0037
0001CA 1B34           DEC      WR6,#01H
0001CC 6859           JE       ?C0038
0001CE 2E340003       ADD      WR6,#03H
0001D2 786C           JNE      ?C0035
                                                ; SOURCE LINE # 79
                                                ; SOURCE LINE # 80
               ?C0034:
                                                ; SOURCE LINE # 81
0001D4 7CB5           MOV      R11,R5           ; A=R11
0001D6 64FF           XRL      A,#0FFH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 11  

0001D8 7E14FD33       MOV      WR2,#0FD33H
0001DC 7E04007E       MOV      WR0,#07EH
0001E0 7E0BA0         MOV      R10,@DR0
0001E3 5CAB           ANL      R10,R11          ; A=R11
0001E5 7A0BA0         MOV      @DR0,R10
0001E8 7E14FD23       MOV      WR2,#0FD23H
0001EC 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 82
               ?C0036:
                                                ; SOURCE LINE # 83
0001EF 7C65           MOV      R6,R5
0001F1 7CB5           MOV      R11,R5           ; A=R11
0001F3 64FF           XRL      A,#0FFH          ; A=R11
0001F5 7E14FD33       MOV      WR2,#0FD33H
0001F9 7E04007E       MOV      WR0,#07EH
0001FD 7E0B70         MOV      R7,@DR0
000200 5C7B           ANL      R7,R11           ; A=R11
000202 7A0B70         MOV      @DR0,R7
000205 7E14FD23       MOV      WR2,#0FD23H
000209 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 84
               ?C0037:
                                                ; SOURCE LINE # 85
00020C 7CB5           MOV      R11,R5           ; A=R11
00020E 7E14FD33       MOV      WR2,#0FD33H
000212 7E04007E       MOV      WR0,#07EH
000216 7E0BA0         MOV      R10,@DR0
000219 4CA5           ORL      R10,R5
00021B 7A0BA0         MOV      @DR0,R10
00021E 64FF           XRL      A,#0FFH          ; A=R11
000220 7E14FD23       MOV      WR2,#0FD23H
000224 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 86
               ?C0038:
                                                ; SOURCE LINE # 87
000227 7C65           MOV      R6,R5
000229 7E14FD33       MOV      WR2,#0FD33H
00022D 7E04007E       MOV      WR0,#07EH
000231 7E0B70         MOV      R7,@DR0
000234 4C75           ORL      R7,R5
000236 7A0B70         MOV      @DR0,R7
000239 7E14FD23       MOV      WR2,#0FD23H
00023D 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 88
               ?C0035:
                                                ; SOURCE LINE # 89
000240 E4             CLR      A                ; A=R11
000241 AA             ERET     
                                                ; SOURCE LINE # 90
                                                ; SOURCE LINE # 91
               ?C0011:
                                                ; SOURCE LINE # 92
000242 7D34           MOV      WR6,WR8
000244 1B34           DEC      WR6,#01H
000246 6829           JE       ?C0042
000248 1B34           DEC      WR6,#01H
00024A 6842           JE       ?C0043
00024C 1B34           DEC      WR6,#01H
00024E 6859           JE       ?C0044
000250 2E340003       ADD      WR6,#03H
000254 786C           JNE      ?C0041
                                                ; SOURCE LINE # 94
                                                ; SOURCE LINE # 95
               ?C0040:
                                                ; SOURCE LINE # 96
000256 7CB5           MOV      R11,R5           ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 12  

000258 64FF           XRL      A,#0FFH          ; A=R11
00025A 7E14FD34       MOV      WR2,#0FD34H
00025E 7E04007E       MOV      WR0,#07EH
000262 7E0BA0         MOV      R10,@DR0
000265 5CAB           ANL      R10,R11          ; A=R11
000267 7A0BA0         MOV      @DR0,R10
00026A 7E14FD24       MOV      WR2,#0FD24H
00026E 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 97
               ?C0042:
                                                ; SOURCE LINE # 98
000271 7C65           MOV      R6,R5
000273 7CB5           MOV      R11,R5           ; A=R11
000275 64FF           XRL      A,#0FFH          ; A=R11
000277 7E14FD34       MOV      WR2,#0FD34H
00027B 7E04007E       MOV      WR0,#07EH
00027F 7E0B70         MOV      R7,@DR0
000282 5C7B           ANL      R7,R11           ; A=R11
000284 7A0B70         MOV      @DR0,R7
000287 7E14FD24       MOV      WR2,#0FD24H
00028B 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 99
               ?C0043:
                                                ; SOURCE LINE # 100
00028E 7CB5           MOV      R11,R5           ; A=R11
000290 7E14FD34       MOV      WR2,#0FD34H
000294 7E04007E       MOV      WR0,#07EH
000298 7E0BA0         MOV      R10,@DR0
00029B 4CA5           ORL      R10,R5
00029D 7A0BA0         MOV      @DR0,R10
0002A0 64FF           XRL      A,#0FFH          ; A=R11
0002A2 7E14FD24       MOV      WR2,#0FD24H
0002A6 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 101
               ?C0044:
                                                ; SOURCE LINE # 102
0002A9 7C65           MOV      R6,R5
0002AB 7E14FD34       MOV      WR2,#0FD34H
0002AF 7E04007E       MOV      WR0,#07EH
0002B3 7E0B70         MOV      R7,@DR0
0002B6 4C75           ORL      R7,R5
0002B8 7A0B70         MOV      @DR0,R7
0002BB 7E14FD24       MOV      WR2,#0FD24H
0002BF 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 103
               ?C0041:
                                                ; SOURCE LINE # 104
0002C2 E4             CLR      A                ; A=R11
0002C3 AA             ERET     
                                                ; SOURCE LINE # 105
                                                ; SOURCE LINE # 106
               ?C0012:
                                                ; SOURCE LINE # 107
0002C4 7D34           MOV      WR6,WR8
0002C6 1B34           DEC      WR6,#01H
0002C8 6829           JE       ?C0048
0002CA 1B34           DEC      WR6,#01H
0002CC 6842           JE       ?C0049
0002CE 1B34           DEC      WR6,#01H
0002D0 6859           JE       ?C0050
0002D2 2E340003       ADD      WR6,#03H
0002D6 786C           JNE      ?C0047
                                                ; SOURCE LINE # 109
                                                ; SOURCE LINE # 110
               ?C0046:
                                                ; SOURCE LINE # 111
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 13  

0002D8 7CB5           MOV      R11,R5           ; A=R11
0002DA 64FF           XRL      A,#0FFH          ; A=R11
0002DC 7E14FD35       MOV      WR2,#0FD35H
0002E0 7E04007E       MOV      WR0,#07EH
0002E4 7E0BA0         MOV      R10,@DR0
0002E7 5CAB           ANL      R10,R11          ; A=R11
0002E9 7A0BA0         MOV      @DR0,R10
0002EC 7E14FD25       MOV      WR2,#0FD25H
0002F0 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 112
               ?C0048:
                                                ; SOURCE LINE # 113
0002F3 7C65           MOV      R6,R5
0002F5 7CB5           MOV      R11,R5           ; A=R11
0002F7 64FF           XRL      A,#0FFH          ; A=R11
0002F9 7E14FD35       MOV      WR2,#0FD35H
0002FD 7E04007E       MOV      WR0,#07EH
000301 7E0B70         MOV      R7,@DR0
000304 5C7B           ANL      R7,R11           ; A=R11
000306 7A0B70         MOV      @DR0,R7
000309 7E14FD25       MOV      WR2,#0FD25H
00030D 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 114
               ?C0049:
                                                ; SOURCE LINE # 115
000310 7CB5           MOV      R11,R5           ; A=R11
000312 7E14FD35       MOV      WR2,#0FD35H
000316 7E04007E       MOV      WR0,#07EH
00031A 7E0BA0         MOV      R10,@DR0
00031D 4CA5           ORL      R10,R5
00031F 7A0BA0         MOV      @DR0,R10
000322 64FF           XRL      A,#0FFH          ; A=R11
000324 7E14FD25       MOV      WR2,#0FD25H
000328 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 116
               ?C0050:
                                                ; SOURCE LINE # 117
00032B 7C65           MOV      R6,R5
00032D 7E14FD35       MOV      WR2,#0FD35H
000331 7E04007E       MOV      WR0,#07EH
000335 7E0B70         MOV      R7,@DR0
000338 4C75           ORL      R7,R5
00033A 7A0B70         MOV      @DR0,R7
00033D 7E14FD25       MOV      WR2,#0FD25H
000341 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 118
               ?C0047:
                                                ; SOURCE LINE # 119
000344 E4             CLR      A                ; A=R11
000345 AA             ERET     
                                                ; SOURCE LINE # 120
                                                ; SOURCE LINE # 121
               ?C0013:
                                                ; SOURCE LINE # 122
000346 7D34           MOV      WR6,WR8
000348 1B34           DEC      WR6,#01H
00034A 6829           JE       ?C0054
00034C 1B34           DEC      WR6,#01H
00034E 6842           JE       ?C0055
000350 1B34           DEC      WR6,#01H
000352 6858           JE       ?C0056
000354 2E340003       ADD      WR6,#03H
000358 786B           JNE      ?C0053
                                                ; SOURCE LINE # 124
                                                ; SOURCE LINE # 125
               ?C0052:
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 14  

                                                ; SOURCE LINE # 126
00035A 7CB5           MOV      R11,R5           ; A=R11
00035C 64FF           XRL      A,#0FFH          ; A=R11
00035E 7E14FD36       MOV      WR2,#0FD36H
000362 7E04007E       MOV      WR0,#07EH
000366 7E0BA0         MOV      R10,@DR0
000369 5CAB           ANL      R10,R11          ; A=R11
00036B 7A0BA0         MOV      @DR0,R10
00036E 7E14FD26       MOV      WR2,#0FD26H
000372 020000      R  LJMP     ?C0197
                                                ; SOURCE LINE # 127
               ?C0054:
                                                ; SOURCE LINE # 128
000375 7C65           MOV      R6,R5
000377 7CB5           MOV      R11,R5           ; A=R11
000379 64FF           XRL      A,#0FFH          ; A=R11
00037B 7E14FD36       MOV      WR2,#0FD36H
00037F 7E04007E       MOV      WR0,#07EH
000383 7E0B70         MOV      R7,@DR0
000386 5C7B           ANL      R7,R11           ; A=R11
000388 7A0B70         MOV      @DR0,R7
00038B 7E14FD26       MOV      WR2,#0FD26H
00038F 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 129
               ?C0055:
                                                ; SOURCE LINE # 130
000392 7CB5           MOV      R11,R5           ; A=R11
000394 7E14FD36       MOV      WR2,#0FD36H
000398 7E04007E       MOV      WR0,#07EH
00039C 7E0BA0         MOV      R10,@DR0
00039F 4CA5           ORL      R10,R5
0003A1 7A0BA0         MOV      @DR0,R10
0003A4 64FF           XRL      A,#0FFH          ; A=R11
0003A6 7E14FD26       MOV      WR2,#0FD26H
0003AA 807E           SJMP     ?C0197
                                                ; SOURCE LINE # 131
               ?C0056:
                                                ; SOURCE LINE # 132
0003AC 7C65           MOV      R6,R5
0003AE 7E14FD36       MOV      WR2,#0FD36H
0003B2 7E04007E       MOV      WR0,#07EH
0003B6 7E0B70         MOV      R7,@DR0
0003B9 4C75           ORL      R7,R5
0003BB 7A0B70         MOV      @DR0,R7
0003BE 7E14FD26       MOV      WR2,#0FD26H
0003C2 020000      R  LJMP     ?C0198
                                                ; SOURCE LINE # 133
               ?C0053:
                                                ; SOURCE LINE # 134
0003C5 E4             CLR      A                ; A=R11
0003C6 AA             ERET     
                                                ; SOURCE LINE # 135
                                                ; SOURCE LINE # 136
               ?C0014:
                                                ; SOURCE LINE # 137
0003C7 1B44           DEC      WR8,#01H
0003C9 682B           JE       ?C0060
0003CB 1B44           DEC      WR8,#01H
0003CD 6843           JE       ?C0061
0003CF 1B44           DEC      WR8,#01H
0003D1 6862           JE       ?C0062
0003D3 2E440003       ADD      WR8,#03H
0003D7 6803        R  JE       $ + 5H
0003D9 020000      R  LJMP     ?C0059
                                                ; SOURCE LINE # 139
                                                ; SOURCE LINE # 140
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 15  

               ?C0058:
                                                ; SOURCE LINE # 141
0003DC 7CB5           MOV      R11,R5           ; A=R11
0003DE 64FF           XRL      A,#0FFH          ; A=R11
0003E0 7E14FD37       MOV      WR2,#0FD37H
0003E4 7E04007E       MOV      WR0,#07EH
0003E8 7E0BA0         MOV      R10,@DR0
0003EB 5CAB           ANL      R10,R11          ; A=R11
0003ED 7A0BA0         MOV      @DR0,R10
0003F0 7E14FD27       MOV      WR2,#0FD27H
0003F4 8034           SJMP     ?C0197
                                                ; SOURCE LINE # 142
               ?C0060:
                                                ; SOURCE LINE # 143
0003F6 7C65           MOV      R6,R5
0003F8 7CB5           MOV      R11,R5           ; A=R11
0003FA 64FF           XRL      A,#0FFH          ; A=R11
0003FC 7E14FD37       MOV      WR2,#0FD37H
000400 7E04007E       MOV      WR0,#07EH
000404 7E0B70         MOV      R7,@DR0
000407 5C7B           ANL      R7,R11           ; A=R11
000409 7A0B70         MOV      @DR0,R7
00040C 7E14FD27       MOV      WR2,#0FD27H
000410 8039           SJMP     ?C0198
                                                ; SOURCE LINE # 144
               ?C0061:
                                                ; SOURCE LINE # 145
000412 7CB5           MOV      R11,R5           ; A=R11
000414 7E14FD37       MOV      WR2,#0FD37H
000418 7E04007E       MOV      WR0,#07EH
00041C 7E0BA0         MOV      R10,@DR0
00041F 4CA5           ORL      R10,R5
000421 7A0BA0         MOV      @DR0,R10
000424 64FF           XRL      A,#0FFH          ; A=R11
000426 7E14FD27       MOV      WR2,#0FD27H
               ?C0197:
00042A 7E04007E       MOV      WR0,#07EH
00042E 7E0B70         MOV      R7,@DR0
000431 5C7B           ANL      R7,R11           ; A=R11
000433 801F           SJMP     ?C0199
                                                ; SOURCE LINE # 146
               ?C0062:
                                                ; SOURCE LINE # 147
000435 7C65           MOV      R6,R5
000437 7E14FD37       MOV      WR2,#0FD37H
00043B 7E04007E       MOV      WR0,#07EH
00043F 7E0B70         MOV      R7,@DR0
000442 4C75           ORL      R7,R5
000444 7A0B70         MOV      @DR0,R7
000447 7E14FD27       MOV      WR2,#0FD27H
               ?C0198:
00044B 7E04007E       MOV      WR0,#07EH
00044F 7E0B70         MOV      R7,@DR0
000452 4C76           ORL      R7,R6
               ?C0199:
000454 7A0B70         MOV      @DR0,R7
000457 8004           SJMP     ?C0005
                                                ; SOURCE LINE # 148
               ?C0059:
                                                ; SOURCE LINE # 149
000459 E4             CLR      A                ; A=R11
00045A AA             ERET     
                                                ; SOURCE LINE # 150
                                                ; SOURCE LINE # 151
               ?C0007:
                                                ; SOURCE LINE # 152
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 16  

00045B E4             CLR      A                ; A=R11
00045C AA             ERET     
                                                ; SOURCE LINE # 153
               ?C0005:
                                                ; SOURCE LINE # 154
00045D 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 155
00045F AA             ERET     
;       FUNCTION GPIO_EXTI_Init? (END)

;       FUNCTION GPIO_EXTI_Open? (BEGIN)
                                                ; SOURCE LINE # 157
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
000460 7D43           MOV      WR8,WR6
;---- Variable 'GPIO_Port' assigned to Register 'WR8' ----
                                                ; SOURCE LINE # 159
000462 BE440007       CMP      WR8,#07H
000466 0802           JSLE     ?C0063
000468 E4             CLR      A                ; A=R11
000469 AA             ERET     
               ?C0063:
                                                ; SOURCE LINE # 160
00046A BE2400FF       CMP      WR4,#0FFH
00046E 0802           JSLE     ?C0065
000470 E4             CLR      A                ; A=R11
000471 AA             ERET     
               ?C0065:
                                                ; SOURCE LINE # 162
000472 7D54           MOV      WR10,WR8
000474 BE540008       CMP      WR10,#08H
000478 506C           JNC      ?C0068
00047A 7EA003         MOV      R10,#03H
00047D A4             MUL      AB
00047E 900000      R  MOV      DPTR,#?C0162
000481 73             JMP      @A+DPTR
               ?C0162:
000482 020000      R  LJMP     ?C0067
000485 020000      R  LJMP     ?C0069
000488 020000      R  LJMP     ?C0070
00048B 020000      R  LJMP     ?C0071
00048E 020000      R  LJMP     ?C0072
000491 020000      R  LJMP     ?C0073
000494 020000      R  LJMP     ?C0074
000497 020000      R  LJMP     ?C0075
                                                ; SOURCE LINE # 164
               ?C0067:
                                                ; SOURCE LINE # 165
00049A 7C65           MOV      R6,R5
00049C 7E14FD00       MOV      WR2,#0FD00H
                                                ; SOURCE LINE # 166
0004A0 8036           SJMP     ?C0206
                                                ; SOURCE LINE # 167
               ?C0069:
                                                ; SOURCE LINE # 168
0004A2 7C65           MOV      R6,R5
0004A4 7E14FD01       MOV      WR2,#0FD01H
                                                ; SOURCE LINE # 169
0004A8 802E           SJMP     ?C0206
                                                ; SOURCE LINE # 170
               ?C0070:
                                                ; SOURCE LINE # 171
0004AA 7C65           MOV      R6,R5
0004AC 7E14FD02       MOV      WR2,#0FD02H
                                                ; SOURCE LINE # 172
0004B0 8026           SJMP     ?C0206
                                                ; SOURCE LINE # 173
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 17  

               ?C0071:
                                                ; SOURCE LINE # 174
0004B2 7C65           MOV      R6,R5
0004B4 7E14FD03       MOV      WR2,#0FD03H
                                                ; SOURCE LINE # 175
0004B8 801E           SJMP     ?C0206
                                                ; SOURCE LINE # 176
               ?C0072:
                                                ; SOURCE LINE # 177
0004BA 7C65           MOV      R6,R5
0004BC 7E14FD04       MOV      WR2,#0FD04H
                                                ; SOURCE LINE # 178
0004C0 8016           SJMP     ?C0206
                                                ; SOURCE LINE # 179
               ?C0073:
                                                ; SOURCE LINE # 180
0004C2 7C65           MOV      R6,R5
0004C4 7E14FD05       MOV      WR2,#0FD05H
                                                ; SOURCE LINE # 181
0004C8 800E           SJMP     ?C0206
                                                ; SOURCE LINE # 182
               ?C0074:
                                                ; SOURCE LINE # 183
0004CA 7C65           MOV      R6,R5
0004CC 7E14FD06       MOV      WR2,#0FD06H
                                                ; SOURCE LINE # 184
0004D0 8006           SJMP     ?C0206
                                                ; SOURCE LINE # 185
               ?C0075:
                                                ; SOURCE LINE # 186
0004D2 7C65           MOV      R6,R5
0004D4 7E14FD07       MOV      WR2,#0FD07H
               ?C0206:
0004D8 7E04007E       MOV      WR0,#07EH
0004DC 7E0B70         MOV      R7,@DR0
0004DF 4C76           ORL      R7,R6
0004E1 7A0B70         MOV      @DR0,R7
                                                ; SOURCE LINE # 187
0004E4 8002           SJMP     ?C0066
                                                ; SOURCE LINE # 188
               ?C0068:
                                                ; SOURCE LINE # 189
0004E6 E4             CLR      A                ; A=R11
0004E7 AA             ERET     
                                                ; SOURCE LINE # 190
               ?C0066:
                                                ; SOURCE LINE # 191
0004E8 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 192
0004EA AA             ERET     
;       FUNCTION GPIO_EXTI_Open? (END)

;       FUNCTION GPIO_EXTI_Set_Priority? (BEGIN)
                                                ; SOURCE LINE # 194
;---- Variable 'EXTI_Priority' assigned to Register 'WR4' ----
0004EB 7D43           MOV      WR8,WR6
;---- Variable 'GPIO_Port' assigned to Register 'WR8' ----
                                                ; SOURCE LINE # 196
0004ED BE440007       CMP      WR8,#07H
0004F1 0802           JSLE     ?C0076
0004F3 E4             CLR      A                ; A=R11
0004F4 AA             ERET     
               ?C0076:
                                                ; SOURCE LINE # 197
0004F5 BE240003       CMP      WR4,#03H
0004F9 0802           JSLE     ?C0078
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 18  

0004FB E4             CLR      A                ; A=R11
0004FC AA             ERET     
               ?C0078:
                                                ; SOURCE LINE # 199
0004FD 7D54           MOV      WR10,WR8
0004FF BE540008       CMP      WR10,#08H
000503 4003        R  JC       $ + 5H
000505 020000      R  LJMP     ?C0081
000508 7EA003         MOV      R10,#03H
00050B A4             MUL      AB
00050C 900000      R  MOV      DPTR,#?C0164
00050F 73             JMP      @A+DPTR
               ?C0164:
000510 020000      R  LJMP     ?C0080
000513 020000      R  LJMP     ?C0082
000516 020000      R  LJMP     ?C0083
000519 020000      R  LJMP     ?C0084
00051C 020000      R  LJMP     ?C0085
00051F 020000      R  LJMP     ?C0086
000522 020000      R  LJMP     ?C0087
000525 020000      R  LJMP     ?C0088
                                                ; SOURCE LINE # 201
               ?C0080:
                                                ; SOURCE LINE # 202
000528 7D32           MOV      WR6,WR4
00052A 1B34           DEC      WR6,#01H
00052C 681D           JE       ?C0092
00052E 1B34           DEC      WR6,#01H
000530 6839           JE       ?C0093
000532 1B34           DEC      WR6,#01H
000534 6851           JE       ?C0094
000536 2E340003       ADD      WR6,#03H
00053A 7867           JNE      ?C0091
                                                ; SOURCE LINE # 204
               ?C0090:
                                                ; SOURCE LINE # 205
00053C 7E34FD60       MOV      WR6,#0FD60H
000540 7E24007E       MOV      WR4,#07EH
000544 7E1BB0         MOV      R11,@DR4         ; A=R11
000547 54FE           ANL      A,#0FEH          ; A=R11
000549 800D           SJMP     ?C0207
                                                ; SOURCE LINE # 206
               ?C0092:
                                                ; SOURCE LINE # 207
00054B 7E34FD60       MOV      WR6,#0FD60H
00054F 7E24007E       MOV      WR4,#07EH
000553 7E1BB0         MOV      R11,@DR4         ; A=R11
000556 4401           ORL      A,#01H           ; A=R11
               ?C0207:
000558 7A1BB0         MOV      @DR4,R11         ; A=R11
00055B 7E34FD61       MOV      WR6,#0FD61H
00055F 7E24007E       MOV      WR4,#07EH
000563 7E1BB0         MOV      R11,@DR4         ; A=R11
000566 54FE           ANL      A,#0FEH          ; A=R11
000568 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 208
               ?C0093:
                                                ; SOURCE LINE # 209
00056B 7E34FD60       MOV      WR6,#0FD60H
00056F 7E24007E       MOV      WR4,#07EH
000573 7E1BB0         MOV      R11,@DR4         ; A=R11
000576 54FE           ANL      A,#0FEH          ; A=R11
000578 7A1BB0         MOV      @DR4,R11         ; A=R11
00057B 7E34FD61       MOV      WR6,#0FD61H
00057F 7E1BB0         MOV      R11,@DR4         ; A=R11
000582 4401           ORL      A,#01H           ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 19  

000584 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 210
               ?C0094:
                                                ; SOURCE LINE # 211
000587 7E34FD60       MOV      WR6,#0FD60H
00058B 7E24007E       MOV      WR4,#07EH
00058F 7E1BB0         MOV      R11,@DR4         ; A=R11
000592 4401           ORL      A,#01H           ; A=R11
000594 7A1BB0         MOV      @DR4,R11         ; A=R11
000597 7E34FD61       MOV      WR6,#0FD61H
00059B 7E1BB0         MOV      R11,@DR4         ; A=R11
00059E 4401           ORL      A,#01H           ; A=R11
0005A0 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 212
               ?C0091:
                                                ; SOURCE LINE # 213
0005A3 E4             CLR      A                ; A=R11
0005A4 AA             ERET     
                                                ; SOURCE LINE # 214
                                                ; SOURCE LINE # 215
               ?C0082:
                                                ; SOURCE LINE # 216
0005A5 7D32           MOV      WR6,WR4
0005A7 1B34           DEC      WR6,#01H
0005A9 682A           JE       ?C0098
0005AB 1B34           DEC      WR6,#01H
0005AD 6842           JE       ?C0099
0005AF 1B34           DEC      WR6,#01H
0005B1 685A           JE       ?C0100
0005B3 2E340003       ADD      WR6,#03H
0005B7 7870           JNE      ?C0097
                                                ; SOURCE LINE # 218
               ?C0096:
                                                ; SOURCE LINE # 219
0005B9 7E34FD60       MOV      WR6,#0FD60H
0005BD 7E24007E       MOV      WR4,#07EH
0005C1 7E1BB0         MOV      R11,@DR4         ; A=R11
0005C4 54FD           ANL      A,#0FDH          ; A=R11
0005C6 7A1BB0         MOV      @DR4,R11         ; A=R11
0005C9 7E34FD61       MOV      WR6,#0FD61H
0005CD 7E1BB0         MOV      R11,@DR4         ; A=R11
0005D0 54FD           ANL      A,#0FDH          ; A=R11
0005D2 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 220
               ?C0098:
                                                ; SOURCE LINE # 221
0005D5 7E34FD60       MOV      WR6,#0FD60H
0005D9 7E24007E       MOV      WR4,#07EH
0005DD 7E1BB0         MOV      R11,@DR4         ; A=R11
0005E0 4402           ORL      A,#02H           ; A=R11
0005E2 7A1BB0         MOV      @DR4,R11         ; A=R11
0005E5 7E34FD61       MOV      WR6,#0FD61H
0005E9 7E1BB0         MOV      R11,@DR4         ; A=R11
0005EC 4402           ORL      A,#02H           ; A=R11
0005EE 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 222
               ?C0099:
                                                ; SOURCE LINE # 223
0005F1 7E34FD60       MOV      WR6,#0FD60H
0005F5 7E24007E       MOV      WR4,#07EH
0005F9 7E1BB0         MOV      R11,@DR4         ; A=R11
0005FC 4402           ORL      A,#02H           ; A=R11
0005FE 7A1BB0         MOV      @DR4,R11         ; A=R11
000601 7E34FD61       MOV      WR6,#0FD61H
000605 7E1BB0         MOV      R11,@DR4         ; A=R11
000608 54FD           ANL      A,#0FDH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 20  

00060A 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 224
               ?C0100:
                                                ; SOURCE LINE # 225
00060D 7E34FD60       MOV      WR6,#0FD60H
000611 7E24007E       MOV      WR4,#07EH
000615 7E1BB0         MOV      R11,@DR4         ; A=R11
000618 4402           ORL      A,#02H           ; A=R11
00061A 7A1BB0         MOV      @DR4,R11         ; A=R11
00061D 7E34FD61       MOV      WR6,#0FD61H
000621 7E1BB0         MOV      R11,@DR4         ; A=R11
000624 4402           ORL      A,#02H           ; A=R11
000626 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 226
               ?C0097:
                                                ; SOURCE LINE # 227
000629 E4             CLR      A                ; A=R11
00062A AA             ERET     
                                                ; SOURCE LINE # 228
                                                ; SOURCE LINE # 229
               ?C0083:
                                                ; SOURCE LINE # 230
00062B 7D32           MOV      WR6,WR4
00062D 1B34           DEC      WR6,#01H
00062F 682A           JE       ?C0104
000631 1B34           DEC      WR6,#01H
000633 6842           JE       ?C0105
000635 1B34           DEC      WR6,#01H
000637 685A           JE       ?C0106
000639 2E340003       ADD      WR6,#03H
00063D 7870           JNE      ?C0103
                                                ; SOURCE LINE # 232
               ?C0102:
                                                ; SOURCE LINE # 233
00063F 7E34FD60       MOV      WR6,#0FD60H
000643 7E24007E       MOV      WR4,#07EH
000647 7E1BB0         MOV      R11,@DR4         ; A=R11
00064A 54FB           ANL      A,#0FBH          ; A=R11
00064C 7A1BB0         MOV      @DR4,R11         ; A=R11
00064F 7E34FD61       MOV      WR6,#0FD61H
000653 7E1BB0         MOV      R11,@DR4         ; A=R11
000656 54FB           ANL      A,#0FBH          ; A=R11
000658 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 234
               ?C0104:
                                                ; SOURCE LINE # 235
00065B 7E34FD60       MOV      WR6,#0FD60H
00065F 7E24007E       MOV      WR4,#07EH
000663 7E1BB0         MOV      R11,@DR4         ; A=R11
000666 4404           ORL      A,#04H           ; A=R11
000668 7A1BB0         MOV      @DR4,R11         ; A=R11
00066B 7E34FD61       MOV      WR6,#0FD61H
00066F 7E1BB0         MOV      R11,@DR4         ; A=R11
000672 4404           ORL      A,#04H           ; A=R11
000674 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 236
               ?C0105:
                                                ; SOURCE LINE # 237
000677 7E34FD60       MOV      WR6,#0FD60H
00067B 7E24007E       MOV      WR4,#07EH
00067F 7E1BB0         MOV      R11,@DR4         ; A=R11
000682 4404           ORL      A,#04H           ; A=R11
000684 7A1BB0         MOV      @DR4,R11         ; A=R11
000687 7E34FD61       MOV      WR6,#0FD61H
00068B 7E1BB0         MOV      R11,@DR4         ; A=R11
00068E 54FB           ANL      A,#0FBH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 21  

000690 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 238
               ?C0106:
                                                ; SOURCE LINE # 239
000693 7E34FD60       MOV      WR6,#0FD60H
000697 7E24007E       MOV      WR4,#07EH
00069B 7E1BB0         MOV      R11,@DR4         ; A=R11
00069E 4404           ORL      A,#04H           ; A=R11
0006A0 7A1BB0         MOV      @DR4,R11         ; A=R11
0006A3 7E34FD61       MOV      WR6,#0FD61H
0006A7 7E1BB0         MOV      R11,@DR4         ; A=R11
0006AA 4404           ORL      A,#04H           ; A=R11
0006AC 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 240
               ?C0103:
                                                ; SOURCE LINE # 241
0006AF E4             CLR      A                ; A=R11
0006B0 AA             ERET     
                                                ; SOURCE LINE # 242
                                                ; SOURCE LINE # 243
               ?C0084:
                                                ; SOURCE LINE # 244
0006B1 7D32           MOV      WR6,WR4
0006B3 1B34           DEC      WR6,#01H
0006B5 682A           JE       ?C0110
0006B7 1B34           DEC      WR6,#01H
0006B9 6842           JE       ?C0111
0006BB 1B34           DEC      WR6,#01H
0006BD 685A           JE       ?C0112
0006BF 2E340003       ADD      WR6,#03H
0006C3 7870           JNE      ?C0109
                                                ; SOURCE LINE # 246
               ?C0108:
                                                ; SOURCE LINE # 247
0006C5 7E34FD60       MOV      WR6,#0FD60H
0006C9 7E24007E       MOV      WR4,#07EH
0006CD 7E1BB0         MOV      R11,@DR4         ; A=R11
0006D0 54F7           ANL      A,#0F7H          ; A=R11
0006D2 7A1BB0         MOV      @DR4,R11         ; A=R11
0006D5 7E34FD61       MOV      WR6,#0FD61H
0006D9 7E1BB0         MOV      R11,@DR4         ; A=R11
0006DC 54F7           ANL      A,#0F7H          ; A=R11
0006DE 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 248
               ?C0110:
                                                ; SOURCE LINE # 249
0006E1 7E34FD60       MOV      WR6,#0FD60H
0006E5 7E24007E       MOV      WR4,#07EH
0006E9 7E1BB0         MOV      R11,@DR4         ; A=R11
0006EC 4408           ORL      A,#08H           ; A=R11
0006EE 7A1BB0         MOV      @DR4,R11         ; A=R11
0006F1 7E34FD61       MOV      WR6,#0FD61H
0006F5 7E1BB0         MOV      R11,@DR4         ; A=R11
0006F8 4408           ORL      A,#08H           ; A=R11
0006FA 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 250
               ?C0111:
                                                ; SOURCE LINE # 251
0006FD 7E34FD60       MOV      WR6,#0FD60H
000701 7E24007E       MOV      WR4,#07EH
000705 7E1BB0         MOV      R11,@DR4         ; A=R11
000708 4408           ORL      A,#08H           ; A=R11
00070A 7A1BB0         MOV      @DR4,R11         ; A=R11
00070D 7E34FD61       MOV      WR6,#0FD61H
000711 7E1BB0         MOV      R11,@DR4         ; A=R11
000714 54F7           ANL      A,#0F7H          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 22  

000716 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 252
               ?C0112:
                                                ; SOURCE LINE # 253
000719 7E34FD60       MOV      WR6,#0FD60H
00071D 7E24007E       MOV      WR4,#07EH
000721 7E1BB0         MOV      R11,@DR4         ; A=R11
000724 4408           ORL      A,#08H           ; A=R11
000726 7A1BB0         MOV      @DR4,R11         ; A=R11
000729 7E34FD61       MOV      WR6,#0FD61H
00072D 7E1BB0         MOV      R11,@DR4         ; A=R11
000730 4408           ORL      A,#08H           ; A=R11
000732 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 254
               ?C0109:
                                                ; SOURCE LINE # 255
000735 E4             CLR      A                ; A=R11
000736 AA             ERET     
                                                ; SOURCE LINE # 256
                                                ; SOURCE LINE # 257
               ?C0085:
                                                ; SOURCE LINE # 258
000737 7D32           MOV      WR6,WR4
000739 1B34           DEC      WR6,#01H
00073B 682A           JE       ?C0116
00073D 1B34           DEC      WR6,#01H
00073F 6842           JE       ?C0117
000741 1B34           DEC      WR6,#01H
000743 685A           JE       ?C0118
000745 2E340003       ADD      WR6,#03H
000749 7870           JNE      ?C0115
                                                ; SOURCE LINE # 260
               ?C0114:
                                                ; SOURCE LINE # 261
00074B 7E34FD60       MOV      WR6,#0FD60H
00074F 7E24007E       MOV      WR4,#07EH
000753 7E1BB0         MOV      R11,@DR4         ; A=R11
000756 54EF           ANL      A,#0EFH          ; A=R11
000758 7A1BB0         MOV      @DR4,R11         ; A=R11
00075B 7E34FD61       MOV      WR6,#0FD61H
00075F 7E1BB0         MOV      R11,@DR4         ; A=R11
000762 54EF           ANL      A,#0EFH          ; A=R11
000764 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 262
               ?C0116:
                                                ; SOURCE LINE # 263
000767 7E34FD60       MOV      WR6,#0FD60H
00076B 7E24007E       MOV      WR4,#07EH
00076F 7E1BB0         MOV      R11,@DR4         ; A=R11
000772 4410           ORL      A,#010H          ; A=R11
000774 7A1BB0         MOV      @DR4,R11         ; A=R11
000777 7E34FD61       MOV      WR6,#0FD61H
00077B 7E1BB0         MOV      R11,@DR4         ; A=R11
00077E 4410           ORL      A,#010H          ; A=R11
000780 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 264
               ?C0117:
                                                ; SOURCE LINE # 265
000783 7E34FD60       MOV      WR6,#0FD60H
000787 7E24007E       MOV      WR4,#07EH
00078B 7E1BB0         MOV      R11,@DR4         ; A=R11
00078E 4410           ORL      A,#010H          ; A=R11
000790 7A1BB0         MOV      @DR4,R11         ; A=R11
000793 7E34FD61       MOV      WR6,#0FD61H
000797 7E1BB0         MOV      R11,@DR4         ; A=R11
00079A 54EF           ANL      A,#0EFH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 23  

00079C 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 266
               ?C0118:
                                                ; SOURCE LINE # 267
00079F 7E34FD60       MOV      WR6,#0FD60H
0007A3 7E24007E       MOV      WR4,#07EH
0007A7 7E1BB0         MOV      R11,@DR4         ; A=R11
0007AA 4410           ORL      A,#010H          ; A=R11
0007AC 7A1BB0         MOV      @DR4,R11         ; A=R11
0007AF 7E34FD61       MOV      WR6,#0FD61H
0007B3 7E1BB0         MOV      R11,@DR4         ; A=R11
0007B6 4410           ORL      A,#010H          ; A=R11
0007B8 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 268
               ?C0115:
                                                ; SOURCE LINE # 269
0007BB E4             CLR      A                ; A=R11
0007BC AA             ERET     
                                                ; SOURCE LINE # 270
                                                ; SOURCE LINE # 271
               ?C0086:
                                                ; SOURCE LINE # 272
0007BD 7D32           MOV      WR6,WR4
0007BF 1B34           DEC      WR6,#01H
0007C1 682A           JE       ?C0122
0007C3 1B34           DEC      WR6,#01H
0007C5 6842           JE       ?C0123
0007C7 1B34           DEC      WR6,#01H
0007C9 685A           JE       ?C0124
0007CB 2E340003       ADD      WR6,#03H
0007CF 7870           JNE      ?C0121
                                                ; SOURCE LINE # 274
               ?C0120:
                                                ; SOURCE LINE # 275
0007D1 7E34FD60       MOV      WR6,#0FD60H
0007D5 7E24007E       MOV      WR4,#07EH
0007D9 7E1BB0         MOV      R11,@DR4         ; A=R11
0007DC 54DF           ANL      A,#0DFH          ; A=R11
0007DE 7A1BB0         MOV      @DR4,R11         ; A=R11
0007E1 7E34FD61       MOV      WR6,#0FD61H
0007E5 7E1BB0         MOV      R11,@DR4         ; A=R11
0007E8 54DF           ANL      A,#0DFH          ; A=R11
0007EA 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 276
               ?C0122:
                                                ; SOURCE LINE # 277
0007ED 7E34FD60       MOV      WR6,#0FD60H
0007F1 7E24007E       MOV      WR4,#07EH
0007F5 7E1BB0         MOV      R11,@DR4         ; A=R11
0007F8 4420           ORL      A,#020H          ; A=R11
0007FA 7A1BB0         MOV      @DR4,R11         ; A=R11
0007FD 7E34FD61       MOV      WR6,#0FD61H
000801 7E1BB0         MOV      R11,@DR4         ; A=R11
000804 4420           ORL      A,#020H          ; A=R11
000806 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 278
               ?C0123:
                                                ; SOURCE LINE # 279
000809 7E34FD60       MOV      WR6,#0FD60H
00080D 7E24007E       MOV      WR4,#07EH
000811 7E1BB0         MOV      R11,@DR4         ; A=R11
000814 4420           ORL      A,#020H          ; A=R11
000816 7A1BB0         MOV      @DR4,R11         ; A=R11
000819 7E34FD61       MOV      WR6,#0FD61H
00081D 7E1BB0         MOV      R11,@DR4         ; A=R11
000820 54DF           ANL      A,#0DFH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 24  

000822 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 280
               ?C0124:
                                                ; SOURCE LINE # 281
000825 7E34FD60       MOV      WR6,#0FD60H
000829 7E24007E       MOV      WR4,#07EH
00082D 7E1BB0         MOV      R11,@DR4         ; A=R11
000830 4420           ORL      A,#020H          ; A=R11
000832 7A1BB0         MOV      @DR4,R11         ; A=R11
000835 7E34FD61       MOV      WR6,#0FD61H
000839 7E1BB0         MOV      R11,@DR4         ; A=R11
00083C 4420           ORL      A,#020H          ; A=R11
00083E 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 282
               ?C0121:
                                                ; SOURCE LINE # 283
000841 E4             CLR      A                ; A=R11
000842 AA             ERET     
                                                ; SOURCE LINE # 284
                                                ; SOURCE LINE # 285
               ?C0087:
                                                ; SOURCE LINE # 286
000843 7D32           MOV      WR6,WR4
000845 1B34           DEC      WR6,#01H
000847 682A           JE       ?C0128
000849 1B34           DEC      WR6,#01H
00084B 6842           JE       ?C0129
00084D 1B34           DEC      WR6,#01H
00084F 685A           JE       ?C0130
000851 2E340003       ADD      WR6,#03H
000855 7870           JNE      ?C0127
                                                ; SOURCE LINE # 288
               ?C0126:
                                                ; SOURCE LINE # 289
000857 7E34FD60       MOV      WR6,#0FD60H
00085B 7E24007E       MOV      WR4,#07EH
00085F 7E1BB0         MOV      R11,@DR4         ; A=R11
000862 54BF           ANL      A,#0BFH          ; A=R11
000864 7A1BB0         MOV      @DR4,R11         ; A=R11
000867 7E34FD61       MOV      WR6,#0FD61H
00086B 7E1BB0         MOV      R11,@DR4         ; A=R11
00086E 54BF           ANL      A,#0BFH          ; A=R11
000870 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 290
               ?C0128:
                                                ; SOURCE LINE # 291
000873 7E34FD60       MOV      WR6,#0FD60H
000877 7E24007E       MOV      WR4,#07EH
00087B 7E1BB0         MOV      R11,@DR4         ; A=R11
00087E 4440           ORL      A,#040H          ; A=R11
000880 7A1BB0         MOV      @DR4,R11         ; A=R11
000883 7E34FD61       MOV      WR6,#0FD61H
000887 7E1BB0         MOV      R11,@DR4         ; A=R11
00088A 4440           ORL      A,#040H          ; A=R11
00088C 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 292
               ?C0129:
                                                ; SOURCE LINE # 293
00088F 7E34FD60       MOV      WR6,#0FD60H
000893 7E24007E       MOV      WR4,#07EH
000897 7E1BB0         MOV      R11,@DR4         ; A=R11
00089A 4440           ORL      A,#040H          ; A=R11
00089C 7A1BB0         MOV      @DR4,R11         ; A=R11
00089F 7E34FD61       MOV      WR6,#0FD61H
0008A3 7E1BB0         MOV      R11,@DR4         ; A=R11
0008A6 54BF           ANL      A,#0BFH          ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 25  

0008A8 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 294
               ?C0130:
                                                ; SOURCE LINE # 295
0008AB 7E34FD60       MOV      WR6,#0FD60H
0008AF 7E24007E       MOV      WR4,#07EH
0008B3 7E1BB0         MOV      R11,@DR4         ; A=R11
0008B6 4440           ORL      A,#040H          ; A=R11
0008B8 7A1BB0         MOV      @DR4,R11         ; A=R11
0008BB 7E34FD61       MOV      WR6,#0FD61H
0008BF 7E1BB0         MOV      R11,@DR4         ; A=R11
0008C2 4440           ORL      A,#040H          ; A=R11
0008C4 020000      R  LJMP     ?C0237
                                                ; SOURCE LINE # 296
               ?C0127:
                                                ; SOURCE LINE # 297
0008C7 E4             CLR      A                ; A=R11
0008C8 AA             ERET     
                                                ; SOURCE LINE # 298
                                                ; SOURCE LINE # 299
               ?C0088:
                                                ; SOURCE LINE # 300
0008C9 1B24           DEC      WR4,#01H
0008CB 6829           JE       ?C0134
0008CD 1B24           DEC      WR4,#01H
0008CF 6840           JE       ?C0135
0008D1 1B24           DEC      WR4,#01H
0008D3 6857           JE       ?C0136
0008D5 2E240003       ADD      WR4,#03H
0008D9 786F           JNE      ?C0133
                                                ; SOURCE LINE # 302
               ?C0132:
                                                ; SOURCE LINE # 303
0008DB 7E34FD60       MOV      WR6,#0FD60H
0008DF 7E24007E       MOV      WR4,#07EH
0008E3 7E1BB0         MOV      R11,@DR4         ; A=R11
0008E6 547F           ANL      A,#07FH          ; A=R11
0008E8 7A1BB0         MOV      @DR4,R11         ; A=R11
0008EB 7E34FD61       MOV      WR6,#0FD61H
0008EF 7E1BB0         MOV      R11,@DR4         ; A=R11
0008F2 547F           ANL      A,#07FH          ; A=R11
0008F4 804F           SJMP     ?C0237
                                                ; SOURCE LINE # 304
               ?C0134:
                                                ; SOURCE LINE # 305
0008F6 7E34FD60       MOV      WR6,#0FD60H
0008FA 7E24007E       MOV      WR4,#07EH
0008FE 7E1BB0         MOV      R11,@DR4         ; A=R11
000901 4480           ORL      A,#080H          ; A=R11
000903 7A1BB0         MOV      @DR4,R11         ; A=R11
000906 7E34FD61       MOV      WR6,#0FD61H
00090A 7E1BB0         MOV      R11,@DR4         ; A=R11
00090D 4480           ORL      A,#080H          ; A=R11
00090F 8034           SJMP     ?C0237
                                                ; SOURCE LINE # 306
               ?C0135:
                                                ; SOURCE LINE # 307
000911 7E34FD60       MOV      WR6,#0FD60H
000915 7E24007E       MOV      WR4,#07EH
000919 7E1BB0         MOV      R11,@DR4         ; A=R11
00091C 4480           ORL      A,#080H          ; A=R11
00091E 7A1BB0         MOV      @DR4,R11         ; A=R11
000921 7E34FD61       MOV      WR6,#0FD61H
000925 7E1BB0         MOV      R11,@DR4         ; A=R11
000928 547F           ANL      A,#07FH          ; A=R11
00092A 8019           SJMP     ?C0237
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 26  

                                                ; SOURCE LINE # 308
               ?C0136:
                                                ; SOURCE LINE # 309
00092C 7E34FD60       MOV      WR6,#0FD60H
000930 7E24007E       MOV      WR4,#07EH
000934 7E1BB0         MOV      R11,@DR4         ; A=R11
000937 4480           ORL      A,#080H          ; A=R11
000939 7A1BB0         MOV      @DR4,R11         ; A=R11
00093C 7E34FD61       MOV      WR6,#0FD61H
000940 7E1BB0         MOV      R11,@DR4         ; A=R11
000943 4480           ORL      A,#080H          ; A=R11
               ?C0237:
000945 7A1BB0         MOV      @DR4,R11         ; A=R11
000948 8004           SJMP     ?C0079
                                                ; SOURCE LINE # 310
               ?C0133:
                                                ; SOURCE LINE # 311
00094A E4             CLR      A                ; A=R11
00094B AA             ERET     
                                                ; SOURCE LINE # 312
                                                ; SOURCE LINE # 313
               ?C0081:
                                                ; SOURCE LINE # 314
00094C E4             CLR      A                ; A=R11
00094D AA             ERET     
                                                ; SOURCE LINE # 315
               ?C0079:
                                                ; SOURCE LINE # 316
00094E 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 317
000950 AA             ERET     
;       FUNCTION GPIO_EXTI_Set_Priority? (END)

;       FUNCTION GPIO_EXTI_Flag_Read? (BEGIN)
                                                ; SOURCE LINE # 319
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 321
000951 7D53           MOV      WR10,WR6
000953 BE540008       CMP      WR10,#08H
000957 4003        R  JC       $ + 5H
000959 020000      R  LJMP     ?C0139
00095C 7EA003         MOV      R10,#03H
00095F A4             MUL      AB
000960 900000      R  MOV      DPTR,#?C0166
000963 73             JMP      @A+DPTR
               ?C0166:
000964 020000      R  LJMP     ?C0138
000967 020000      R  LJMP     ?C0140
00096A 020000      R  LJMP     ?C0141
00096D 020000      R  LJMP     ?C0142
000970 020000      R  LJMP     ?C0143
000973 020000      R  LJMP     ?C0144
000976 020000      R  LJMP     ?C0145
000979 020000      R  LJMP     ?C0146
                                                ; SOURCE LINE # 323
               ?C0138:
                                                ; SOURCE LINE # 324
00097C 7E34FD10       MOV      WR6,#0FD10H
000980 7E24007E       MOV      WR4,#07EH
000984 7E1B70         MOV      R7,@DR4
000987 7A730000    R  MOV      Port_Exti_Flag,R7
00098B 8079           SJMP     ?C0137
                                                ; SOURCE LINE # 325
               ?C0140:
                                                ; SOURCE LINE # 326
00098D 7E34FD11       MOV      WR6,#0FD11H
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 27  

000991 7E24007E       MOV      WR4,#07EH
000995 7E1B70         MOV      R7,@DR4
000998 7A730000    R  MOV      Port_Exti_Flag+1,R7
00099C 8068           SJMP     ?C0137
                                                ; SOURCE LINE # 327
               ?C0141:
                                                ; SOURCE LINE # 328
00099E 7E34FD12       MOV      WR6,#0FD12H
0009A2 7E24007E       MOV      WR4,#07EH
0009A6 7E1B70         MOV      R7,@DR4
0009A9 7A730000    R  MOV      Port_Exti_Flag+2,R7
0009AD 8057           SJMP     ?C0137
                                                ; SOURCE LINE # 329
               ?C0142:
                                                ; SOURCE LINE # 330
0009AF 7E34FD13       MOV      WR6,#0FD13H
0009B3 7E24007E       MOV      WR4,#07EH
0009B7 7E1B70         MOV      R7,@DR4
0009BA 7A730000    R  MOV      Port_Exti_Flag+3,R7
0009BE 8046           SJMP     ?C0137
                                                ; SOURCE LINE # 331
               ?C0143:
                                                ; SOURCE LINE # 332
0009C0 7E34FD14       MOV      WR6,#0FD14H
0009C4 7E24007E       MOV      WR4,#07EH
0009C8 7E1B70         MOV      R7,@DR4
0009CB 7A730000    R  MOV      Port_Exti_Flag+4,R7
0009CF 8035           SJMP     ?C0137
                                                ; SOURCE LINE # 333
               ?C0144:
                                                ; SOURCE LINE # 334
0009D1 7E34FD15       MOV      WR6,#0FD15H
0009D5 7E24007E       MOV      WR4,#07EH
0009D9 7E1B70         MOV      R7,@DR4
0009DC 7A730000    R  MOV      Port_Exti_Flag+5,R7
0009E0 8024           SJMP     ?C0137
                                                ; SOURCE LINE # 335
               ?C0145:
                                                ; SOURCE LINE # 336
0009E2 7E34FD16       MOV      WR6,#0FD16H
0009E6 7E24007E       MOV      WR4,#07EH
0009EA 7E1B70         MOV      R7,@DR4
0009ED 7A730000    R  MOV      Port_Exti_Flag+6,R7
0009F1 8013           SJMP     ?C0137
                                                ; SOURCE LINE # 337
               ?C0146:
                                                ; SOURCE LINE # 338
0009F3 7E34FD17       MOV      WR6,#0FD17H
0009F7 7E24007E       MOV      WR4,#07EH
0009FB 7E1B70         MOV      R7,@DR4
0009FE 7A730000    R  MOV      Port_Exti_Flag+7,R7
000A02 8002           SJMP     ?C0137
                                                ; SOURCE LINE # 339
               ?C0139:
                                                ; SOURCE LINE # 340
000A04 E4             CLR      A                ; A=R11
000A05 AA             ERET     
                                                ; SOURCE LINE # 341
               ?C0137:
                                                ; SOURCE LINE # 342
000A06 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 343
000A08 AA             ERET     
;       FUNCTION GPIO_EXTI_Flag_Read? (END)

;       FUNCTION GPIO_EXTI_Flag_Clear? (BEGIN)
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 28  

                                                ; SOURCE LINE # 345
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 347
000A09 7D53           MOV      WR10,WR6
000A0B BE540008       CMP      WR10,#08H
000A0F 505F           JNC      ?C0150
000A11 7EA003         MOV      R10,#03H
000A14 A4             MUL      AB
000A15 900000      R  MOV      DPTR,#?C0168
000A18 73             JMP      @A+DPTR
               ?C0168:
000A19 020000      R  LJMP     ?C0149
000A1C 020000      R  LJMP     ?C0151
000A1F 020000      R  LJMP     ?C0152
000A22 020000      R  LJMP     ?C0153
000A25 020000      R  LJMP     ?C0154
000A28 020000      R  LJMP     ?C0155
000A2B 020000      R  LJMP     ?C0156
000A2E 020000      R  LJMP     ?C0157
                                                ; SOURCE LINE # 349
               ?C0149:
                                                ; SOURCE LINE # 350
000A31 E4             CLR      A                ; A=R11
000A32 7E34FD10       MOV      WR6,#0FD10H
000A36 802F           SJMP     ?C0244
                                                ; SOURCE LINE # 351
               ?C0151:
                                                ; SOURCE LINE # 352
000A38 E4             CLR      A                ; A=R11
000A39 7E34FD11       MOV      WR6,#0FD11H
000A3D 8028           SJMP     ?C0244
                                                ; SOURCE LINE # 353
               ?C0152:
                                                ; SOURCE LINE # 354
000A3F E4             CLR      A                ; A=R11
000A40 7E34FD12       MOV      WR6,#0FD12H
000A44 8021           SJMP     ?C0244
                                                ; SOURCE LINE # 355
               ?C0153:
                                                ; SOURCE LINE # 356
000A46 E4             CLR      A                ; A=R11
000A47 7E34FD13       MOV      WR6,#0FD13H
000A4B 801A           SJMP     ?C0244
                                                ; SOURCE LINE # 357
               ?C0154:
                                                ; SOURCE LINE # 358
000A4D E4             CLR      A                ; A=R11
000A4E 7E34FD14       MOV      WR6,#0FD14H
000A52 8013           SJMP     ?C0244
                                                ; SOURCE LINE # 359
               ?C0155:
                                                ; SOURCE LINE # 360
000A54 E4             CLR      A                ; A=R11
000A55 7E34FD15       MOV      WR6,#0FD15H
000A59 800C           SJMP     ?C0244
                                                ; SOURCE LINE # 361
               ?C0156:
                                                ; SOURCE LINE # 362
000A5B E4             CLR      A                ; A=R11
000A5C 7E34FD16       MOV      WR6,#0FD16H
000A60 8005           SJMP     ?C0244
                                                ; SOURCE LINE # 363
               ?C0157:
                                                ; SOURCE LINE # 364
000A62 E4             CLR      A                ; A=R11
000A63 7E34FD17       MOV      WR6,#0FD17H
C251 COMPILER V5.60.0,  CNU_PIE_EXTI                                                       24/08/26  10:23:43  PAGE 29  

               ?C0244:
000A67 7E24007E       MOV      WR4,#07EH
000A6B 7A1BB0         MOV      @DR4,R11         ; A=R11
000A6E 8002           SJMP     ?C0148
                                                ; SOURCE LINE # 365
               ?C0150:
                                                ; SOURCE LINE # 366
000A70 E4             CLR      A                ; A=R11
000A71 AA             ERET     
                                                ; SOURCE LINE # 367
               ?C0148:
                                                ; SOURCE LINE # 368
000A72 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 369
000A74 AA             ERET     
;       FUNCTION GPIO_EXTI_Flag_Clear? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      2677     ------
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
  hconst size          =    ------     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_GPIO
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_GPIO.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_GPIO.c XSMALL ROM(HUGE) BROWSE 
                    -INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTO
                    -R(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_GPIO.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_GPIO.obj) 

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
   12           * @file       CNU_PIE_GPIO.c
   13           * @brief      GPIO
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19           #include "CNU_PIE_GPIO.h"
   20           
   21           /*******************************************************************************************************
             -*******************
   22           * @brief  初始化GPIO引脚
   23           * @exampleCode
   24                  GPIO_Init(GPIO_P0, GPIO_Pin_0, GPIO_PullUp); //初始化P00引脚并设置为准双向IO
   25           * @endcode
   26           * @param[in]  GPIO_Port GPIO端口号
   27           * @param[in]  GPIO_Pin  GPIO引脚号              
   28           * @param[in]  GPIO_Mode GPIO引脚配置
   29          *********************************************************************************************************
             -******************/
   30          void GPIO_Init(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin , GPIO_Mode_enum GPIO_Mode)
   31           {
   32   1         switch (GPIO_Port)
   33   1         {
   34   2           case GPIO_P0://端口0
   35   2             switch (GPIO_Mode)
   36   2             {
   37   3               case GPIO_PullUp:
   38   3                 P0M1 &= ~GPIO_Pin, P0M0 &= ~GPIO_Pin;   break;//上拉准双向口      
   39   3               case GPIO_HighZ:
   40   3                 P0M1 |=  GPIO_Pin, P0M0 &= ~GPIO_Pin;   break;//高阻输入
   41   3               case GPIO_OUT_OD:
   42   3                 P0M1 |=  GPIO_Pin, P0M0 |=  GPIO_Pin;   break;//开漏输出
   43   3               case GPIO_OUT_PP:
   44   3                 P0M1 &= ~GPIO_Pin, P0M0 |=  GPIO_Pin;   break;//推挽输出
   45   3               default:
   46   3               break;//初始化失败
   47   3             }break;
   48   2           case GPIO_P1://端口1
   49   2             switch (GPIO_Mode)
   50   2             {
   51   3               case GPIO_PullUp:
   52   3                 P1M1 &= ~GPIO_Pin, P1M0 &= ~GPIO_Pin;   break;//上拉准双向口      
   53   3               case GPIO_HighZ:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 2   

   54   3                 P1M1 |=  GPIO_Pin, P1M0 &= ~GPIO_Pin;   break;//高阻输入
   55   3               case GPIO_OUT_OD:
   56   3                 P1M1 |=  GPIO_Pin, P1M0 |=  GPIO_Pin;   break;//开漏输出
   57   3               case GPIO_OUT_PP:
   58   3                 P1M1 &= ~GPIO_Pin, P1M0 |=  GPIO_Pin;   break;//推挽输出
   59   3               default:
   60   3               break;//初始化失败
   61   3             }break;    
   62   2           case GPIO_P2://端口2
   63   2             switch (GPIO_Mode)
   64   2             {
   65   3               case GPIO_PullUp:
   66   3                 P2M1 &= ~GPIO_Pin, P2M0 &= ~GPIO_Pin;   break;//上拉准双向口      
   67   3               case GPIO_HighZ:
   68   3                 P2M1 |=  GPIO_Pin, P2M0 &= ~GPIO_Pin;   break;//高阻输入
   69   3               case GPIO_OUT_OD:
   70   3                 P2M1 |=  GPIO_Pin, P2M0 |=  GPIO_Pin;   break;//开漏输出
   71   3               case GPIO_OUT_PP:
   72   3                 P2M1 &= ~GPIO_Pin, P2M0 |=  GPIO_Pin;   break;//推挽输出
   73   3               default:
   74   3               break;//初始化失败
   75   3             }break;    
   76   2           case GPIO_P3://端口3
   77   2             switch (GPIO_Mode)
   78   2             {
   79   3               case GPIO_PullUp:
   80   3                 P3M1 &= ~GPIO_Pin, P3M0 &= ~GPIO_Pin;   break;//上拉准双向口      
   81   3               case GPIO_HighZ:
   82   3                 P3M1 |=  GPIO_Pin, P3M0 &= ~GPIO_Pin;   break;//高阻输入
   83   3               case GPIO_OUT_OD:
   84   3                 P3M1 |=  GPIO_Pin, P3M0 |=  GPIO_Pin;   break;//开漏输出
   85   3               case GPIO_OUT_PP:
   86   3                 P3M1 &= ~GPIO_Pin, P3M0 |=  GPIO_Pin;   break;//推挽输出
   87   3               default:
   88   3               break;//初始化失败
   89   3             }break;  
   90   2           case GPIO_P4://端口4
   91   2             switch (GPIO_Mode)
   92   2             {
   93   3               case GPIO_PullUp:
   94   3                 P4M1 &= ~GPIO_Pin, P4M0 &= ~GPIO_Pin;   break;//上拉准双向口      
   95   3               case GPIO_HighZ:
   96   3                 P4M1 |=  GPIO_Pin, P4M0 &= ~GPIO_Pin;   break;//高阻输入
   97   3               case GPIO_OUT_OD:
   98   3                 P4M1 |=  GPIO_Pin, P4M0 |=  GPIO_Pin;   break;//开漏输出
   99   3               case GPIO_OUT_PP:
  100   3                 P4M1 &= ~GPIO_Pin, P4M0 |=  GPIO_Pin;   break;//推挽输出
  101   3               default:
  102   3               break;//初始化失败
  103   3             }break;  
  104   2           case GPIO_P5://端口5
  105   2             switch (GPIO_Mode)
  106   2             {
  107   3               case GPIO_PullUp:
  108   3                 P5M1 &= ~GPIO_Pin, P5M0 &= ~GPIO_Pin;   break;//上拉准双向口      
  109   3               case GPIO_HighZ:
  110   3                 P5M1 |=  GPIO_Pin, P5M0 &= ~GPIO_Pin;   break;//高阻输入
  111   3               case GPIO_OUT_OD:
  112   3                 P5M1 |=  GPIO_Pin, P5M0 |=  GPIO_Pin;   break;//开漏输出
  113   3               case GPIO_OUT_PP:
  114   3                 P5M1 &= ~GPIO_Pin, P5M0 |=  GPIO_Pin;   break;//推挽输出
  115   3               default:
  116   3               break;//初始化失败
  117   3             }break;    
  118   2           case GPIO_P6://端口6
  119   2             switch (GPIO_Mode)
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 3   

  120   2             {
  121   3               case GPIO_PullUp:
  122   3                 P6M1 &= ~GPIO_Pin, P6M0 &= ~GPIO_Pin;   break;//上拉准双向口      
  123   3               case GPIO_HighZ:
  124   3                 P6M1 |=  GPIO_Pin, P6M0 &= ~GPIO_Pin;   break;//高阻输入
  125   3               case GPIO_OUT_OD:
  126   3                 P6M1 |=  GPIO_Pin, P6M0 |=  GPIO_Pin;   break;//开漏输出
  127   3               case GPIO_OUT_PP:
  128   3                 P6M1 &= ~GPIO_Pin, P6M0 |=  GPIO_Pin;   break;//推挽输出
  129   3               default:
  130   3               break;//初始化失败
  131   3             }break;
  132   2           case GPIO_P7://端口7
  133   2             switch (GPIO_Mode)
  134   2             {
  135   3               case GPIO_PullUp:
  136   3                 P7M1 &= ~GPIO_Pin, P7M0 &= ~GPIO_Pin;   break;//上拉准双向口      
  137   3               case GPIO_HighZ:
  138   3                 P7M1 |=  GPIO_Pin, P7M0 &= ~GPIO_Pin;   break;//高阻输入
  139   3               case GPIO_OUT_OD:
  140   3                 P7M1 |=  GPIO_Pin, P7M0 |=  GPIO_Pin;   break;//开漏输出
  141   3               case GPIO_OUT_PP:
  142   3                 P7M1 &= ~GPIO_Pin, P7M0 |=  GPIO_Pin;   break;//推挽输出
  143   3               default:
  144   3               break;//初始化失败
  145   3             }break;
  146   2           default:
  147   2            break;         
  148   2         }
  149   1       }
  150           /*******************************************************************************************************
             -*******************
  151           * @brief  设置GPIO引脚上拉电阻 -4.1k
  152           * @exampleCode
  153           *      uint8_t status ; //用于存储初始化状态
  154           *      status = GPIO_PinPullConfig(GPIO_P0, GPIO_Pin_0, GPIO_Pull_Up); //设置P00引脚上拉4.1k电阻
  155           * @endcode
  156           * @param[in]  GPIO_Port GPIO端口号
  157           * @param[in]  GPIO_Pin  GPIO引脚号              
  158           * @param[in]  GPIO_Pin_Config GPIO引脚是否上拉电阻
  159           * @retval 0 失败
  160           * @retval 1 成功
  161          *********************************************************************************************************
             -******************/
  162          uint8_t GPIO_PinPullConfig(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin , GPIO_PinConfig GPIO_Pin_Co
             -nfig)
  163           {
  164   1         if(GPIO_Port > GPIO_P7)             return FAIL; //初始化错误值返回FAIL
  165   1         if(GPIO_Pin  > GPIO_Pin_All)        return FAIL; //初始化错误值返回FAIL
  166   1         if(GPIO_Pin_Config > GPIO_NO_PULL)  return FAIL; //初始化错误值返回FAIL
  167   1         
  168   1         switch (GPIO_Port)
  169   1         {
  170   2           case GPIO_P0://端口0
  171   2             switch (GPIO_Pin_Config)
  172   2             {
  173   3               case GPIO_NO_PULL:
  174   3                 P0PU &= ~GPIO_Pin;  break;//引脚不配置上拉电阻  
  175   3               case GPIO_Pull_Up:
  176   3                 P0PU |=  GPIO_Pin;   break;//引脚配置上拉电阻
  177   3               default:
  178   3                 return FAIL; break;//初始化失败
  179   3             }break;
  180   2           case GPIO_P1://端口1
  181   2             switch (GPIO_Pin_Config)
  182   2             {
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 4   

  183   3               case GPIO_NO_PULL:
  184   3                 P1PU &= ~GPIO_Pin;  break;
  185   3               case GPIO_Pull_Up:
  186   3                 P1PU |=  GPIO_Pin;   break;
  187   3               default:
  188   3                 return FAIL; break;
  189   3             }break;    
  190   2           case GPIO_P2://端口2
  191   2             switch (GPIO_Pin_Config)
  192   2             {
  193   3               case GPIO_NO_PULL:
  194   3                 P2PU &= ~GPIO_Pin;  break;
  195   3               case GPIO_Pull_Up:
  196   3                 P2PU |=  GPIO_Pin;   break;
  197   3               default:
  198   3                 return FAIL; break;
  199   3             }break;    
  200   2           case GPIO_P3://端口3
  201   2             switch (GPIO_Pin_Config)
  202   2             {
  203   3               case GPIO_NO_PULL:
  204   3                 P3PU &= ~GPIO_Pin;  break;
  205   3               case GPIO_Pull_Up:
  206   3                 P3PU |=  GPIO_Pin;   break;
  207   3               default:
  208   3                 return FAIL; break;
  209   3             }break;  
  210   2           case GPIO_P4://端口4
  211   2             switch (GPIO_Pin_Config)
  212   2             {
  213   3               case GPIO_NO_PULL:
  214   3                 P4PU &= ~GPIO_Pin;  break;
  215   3               case GPIO_Pull_Up:
  216   3                 P4PU |=  GPIO_Pin;   break;
  217   3               default:
  218   3                 return FAIL; break;
  219   3             }break;  
  220   2           case GPIO_P5://端口5
  221   2             switch (GPIO_Pin_Config)
  222   2             {
  223   3               case GPIO_NO_PULL:
  224   3                 P5PU &= ~GPIO_Pin;  break;
  225   3               case GPIO_Pull_Up:
  226   3                 P5PU |=  GPIO_Pin;   break;
  227   3               default:
  228   3                 return FAIL; break;
  229   3             }break;    
  230   2           case GPIO_P6://端口6
  231   2             switch (GPIO_Pin_Config)
  232   2             {
  233   3               case GPIO_NO_PULL:
  234   3                 P6PU &= ~GPIO_Pin;  break;
  235   3               case GPIO_Pull_Up:
  236   3                 P6PU |=  GPIO_Pin;   break;
  237   3               default:
  238   3                 return FAIL; break;
  239   3             }break;
  240   2           case GPIO_P7://端口7
  241   2             switch (GPIO_Pin_Config)
  242   2             {
  243   3               case GPIO_NO_PULL:
  244   3                 P7PU &= ~GPIO_Pin;  break;
  245   3               case GPIO_Pull_Up:
  246   3                 P7PU |=  GPIO_Pin;   break;
  247   3               default:
  248   3                 return FAIL; break;
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 5   

  249   3             }break;
  250   2           default:
  251   2             return FAIL; break;         
  252   2         }
  253   1        return SUCCEED; //成功
  254   1       }
  255           /*******************************************************************************************************
             -*******************
  256           * @brief  设置GPIO引脚电平
  257           * @exampleCode
  258           *      GPIO_Write_Bit(GPIO_P0, GPIO_Pin_0, 0);   //设置P00引脚为低电平
  259           * @endcode
  260           * @param[in]  GPIO_Port GPIO端口号
  261           * @param[in]  GPIO_Pin  GPIO引脚号              
  262           * @param[in]  data_t    GPIO引脚电平
  263          *********************************************************************************************************
             -******************/
  264          void GPIO_Write_Bit(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin , uint8_t data_t)
  265           {
  266   1         
  267   1         switch (GPIO_Port)
  268   1         {
  269   2           case GPIO_P0://端口0
  270   2             switch (data_t)
  271   2             {
  272   3               case GPIO_LOW:
  273   3                 P0 &= ~GPIO_Pin;  break;//引脚电平拉低  
  274   3               case GPIO_HIGH:
  275   3                 P0 |=  GPIO_Pin;   break;//引脚电平拉高
  276   3               default:
  277   3                 break;//初始化失败
  278   3             }break;
  279   2           case GPIO_P1://端口1
  280   2             switch (data_t)
  281   2             {
  282   3               case GPIO_LOW:
  283   3                 P1 &= ~GPIO_Pin;  break;
  284   3               case GPIO_HIGH:
  285   3                 P1 |=  GPIO_Pin;   break;
  286   3               default:
  287   3               break;
  288   3             }break;    
  289   2           case GPIO_P2://端口2
  290   2             switch (data_t)
  291   2             {
  292   3               case GPIO_LOW:
  293   3                 P2 &= ~GPIO_Pin;  break;
  294   3               case GPIO_HIGH:
  295   3                 P2 |=  GPIO_Pin;   break;
  296   3               default:
  297   3                break;
  298   3             }break;    
  299   2           case GPIO_P3://端口3
  300   2             switch (data_t)
  301   2             {
  302   3               case GPIO_LOW:
  303   3                 P3 &= ~GPIO_Pin;  break;
  304   3               case GPIO_HIGH:
  305   3                 P3 |=  GPIO_Pin;   break;
  306   3               default:
  307   3                break;
  308   3             }break;  
  309   2           case GPIO_P4://端口4
  310   2             switch (data_t)
  311   2             {
  312   3               case GPIO_LOW:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 6   

  313   3                 P4 &= ~GPIO_Pin;  break;
  314   3               case GPIO_HIGH:
  315   3                 P4 |=  GPIO_Pin;   break;
  316   3               default:
  317   3                break;
  318   3             }break;  
  319   2           case GPIO_P5://端口5
  320   2             switch (data_t)
  321   2             {
  322   3               case GPIO_LOW:
  323   3                 P5 &= ~GPIO_Pin;  break;
  324   3               case GPIO_HIGH:
  325   3                 P5 |=  GPIO_Pin;   break;
  326   3               default:
  327   3                break;
  328   3             }break;    
  329   2           case GPIO_P6://端口6
  330   2             switch (data_t)
  331   2             {
  332   3               case GPIO_LOW:
  333   3                 P6 &= ~GPIO_Pin;  break;
  334   3               case GPIO_HIGH:
  335   3                 P6 |=  GPIO_Pin;   break;
  336   3               default:
  337   3                 break;
  338   3             }break;
  339   2           case GPIO_P7://端口7
  340   2             switch (data_t)
  341   2             {
  342   3               case GPIO_LOW:
  343   3                 P7 &= ~GPIO_Pin;  break;
  344   3               case GPIO_HIGH:
  345   3                 P7 |=  GPIO_Pin;   break;
  346   3               default:
  347   3                 break;
  348   3             }break;
  349   2             default:
  350   2             break;        
  351   2         }  
  352   1       }
  353           /*******************************************************************************************************
             -*******************
  354           * @brief  读取GPIO引脚电平
  355           * @exampleCode
  356           *      uint8_t status ; //用于存储引脚电平
  357           *      status = GPIO_Read_Bit(GPIO_P0, GPIO_Pin_0); //读取P00引脚电平
  358           * @endcode
  359           * @param[in]  GPIO_Port GPIO端口号
  360           * @param[in]  GPIO_Pin  GPIO引脚号              
  361           * @retval 0 低电平
  362           * @retval 1 高电平
  363          *********************************************************************************************************
             -******************/
  364          uint8_t GPIO_Read_Bit(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin)
  365           {
  366   1         uint8_t Bit_Value;
  367   1         switch (GPIO_Port)
  368   1         {
  369   2           case GPIO_P0://端口0
  370   2             switch (GPIO_Pin)
  371   2             {
  372   3               case GPIO_Pin_0: Bit_Value = P00; return Bit_Value; break;
  373   3               case GPIO_Pin_1: Bit_Value = P01; return Bit_Value; break;
  374   3               case GPIO_Pin_2: Bit_Value = P02; return Bit_Value; break;
  375   3               case GPIO_Pin_3: Bit_Value = P03; return Bit_Value; break;
  376   3               case GPIO_Pin_4: Bit_Value = P04; return Bit_Value; break;
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 7   

  377   3               case GPIO_Pin_5: Bit_Value = P05; return Bit_Value; break;
  378   3               case GPIO_Pin_6: Bit_Value = P06; return Bit_Value; break;
  379   3               case GPIO_Pin_7: Bit_Value = P07; return Bit_Value; break;
  380   3               default:  return FAIL ;break;  
  381   3             }break;
  382   2           case GPIO_P1://端口1
  383   2             switch (GPIO_Pin)
  384   2             {
  385   3               case GPIO_Pin_0: Bit_Value = P10; return Bit_Value; break;
  386   3               case GPIO_Pin_1: Bit_Value = P11; return Bit_Value; break;
  387   3               case GPIO_Pin_2: Bit_Value = P12; return Bit_Value; break;
  388   3               case GPIO_Pin_3: Bit_Value = P13; return Bit_Value; break;
  389   3               case GPIO_Pin_4: Bit_Value = P14; return Bit_Value; break;
  390   3               case GPIO_Pin_5: Bit_Value = P15; return Bit_Value; break;
  391   3               case GPIO_Pin_6: Bit_Value = P16; return Bit_Value; break;
  392   3               case GPIO_Pin_7: Bit_Value = P17; return Bit_Value; break;
  393   3               default:  return FAIL ;break;  
  394   3             }break;       
  395   2          case GPIO_P2://端口2
  396   2             switch (GPIO_Pin)
  397   2             {
  398   3               case GPIO_Pin_0: Bit_Value = P20; return Bit_Value; break;
  399   3               case GPIO_Pin_1: Bit_Value = P21; return Bit_Value; break;
  400   3               case GPIO_Pin_2: Bit_Value = P22; return Bit_Value; break;
  401   3               case GPIO_Pin_3: Bit_Value = P23; return Bit_Value; break;
  402   3               case GPIO_Pin_4: Bit_Value = P24; return Bit_Value; break;
  403   3               case GPIO_Pin_5: Bit_Value = P25; return Bit_Value; break;
  404   3               case GPIO_Pin_6: Bit_Value = P26; return Bit_Value; break;
  405   3               case GPIO_Pin_7: Bit_Value = P27; return Bit_Value; break;
  406   3               default:  return FAIL ;break;  
  407   3             }break;
  408   2          case GPIO_P3://端口3
  409   2             switch (GPIO_Pin)
  410   2             {
  411   3               case GPIO_Pin_0: Bit_Value = P30; return Bit_Value; break;
  412   3               case GPIO_Pin_1: Bit_Value = P31; return Bit_Value; break;
  413   3               case GPIO_Pin_2: Bit_Value = P32; return Bit_Value; break;
  414   3               case GPIO_Pin_3: Bit_Value = P33; return Bit_Value; break;
  415   3               case GPIO_Pin_4: Bit_Value = P34; return Bit_Value; break;
  416   3               case GPIO_Pin_5: Bit_Value = P35; return Bit_Value; break;
  417   3               case GPIO_Pin_6: Bit_Value = P36; return Bit_Value; break;
  418   3               case GPIO_Pin_7: Bit_Value = P37; return Bit_Value; break;
  419   3               default:  return FAIL ;break;  
  420   3             }break;       
  421   2          case GPIO_P4://端口4
  422   2             switch (GPIO_Pin)
  423   2             {
  424   3               case GPIO_Pin_0: Bit_Value = P40; return Bit_Value; break;
  425   3               case GPIO_Pin_1: Bit_Value = P41; return Bit_Value; break;
  426   3               case GPIO_Pin_2: Bit_Value = P42; return Bit_Value; break;
  427   3               case GPIO_Pin_3: Bit_Value = P43; return Bit_Value; break;
  428   3               case GPIO_Pin_4: Bit_Value = P44; return Bit_Value; break;
  429   3               case GPIO_Pin_5: Bit_Value = P45; return Bit_Value; break;
  430   3               case GPIO_Pin_6: Bit_Value = P46; return Bit_Value; break;
  431   3               case GPIO_Pin_7: Bit_Value = P47; return Bit_Value; break;
  432   3               default:  return FAIL ;break;  
  433   3             }break;     
  434   2          case GPIO_P5://端口5
  435   2             switch (GPIO_Pin)
  436   2             {
  437   3               case GPIO_Pin_0: Bit_Value = P50; return Bit_Value; break;
  438   3               case GPIO_Pin_1: Bit_Value = P51; return Bit_Value; break;
  439   3               case GPIO_Pin_2: Bit_Value = P52; return Bit_Value; break;
  440   3               case GPIO_Pin_3: Bit_Value = P53; return Bit_Value; break;
  441   3               case GPIO_Pin_4: Bit_Value = P54; return Bit_Value; break;
  442   3               case GPIO_Pin_5: Bit_Value = P55; return Bit_Value; break;
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 8   

  443   3               default:  return FAIL ;break;  
  444   3             }break;      
  445   2          case GPIO_P6://端口6
  446   2             switch (GPIO_Pin)
  447   2             {
  448   3               case GPIO_Pin_0: Bit_Value = P60; return Bit_Value; break;
  449   3               case GPIO_Pin_1: Bit_Value = P61; return Bit_Value; break;
  450   3               case GPIO_Pin_2: Bit_Value = P62; return Bit_Value; break;
  451   3               case GPIO_Pin_3: Bit_Value = P63; return Bit_Value; break;
  452   3               case GPIO_Pin_4: Bit_Value = P64; return Bit_Value; break;
  453   3               case GPIO_Pin_5: Bit_Value = P65; return Bit_Value; break;
  454   3               case GPIO_Pin_6: Bit_Value = P66; return Bit_Value; break;
  455   3               case GPIO_Pin_7: Bit_Value = P67; return Bit_Value; break;
  456   3               default:  return FAIL ;break;  
  457   3             }break;
  458   2          case GPIO_P7://端口6
  459   2             switch (GPIO_Pin)
  460   2             {
  461   3               case GPIO_Pin_0: Bit_Value = P70; return Bit_Value; break;
  462   3               case GPIO_Pin_1: Bit_Value = P71; return Bit_Value; break;
  463   3               case GPIO_Pin_2: Bit_Value = P72; return Bit_Value; break;
  464   3               case GPIO_Pin_3: Bit_Value = P73; return Bit_Value; break;
  465   3               case GPIO_Pin_4: Bit_Value = P74; return Bit_Value; break;
  466   3               case GPIO_Pin_5: Bit_Value = P75; return Bit_Value; break;
  467   3               case GPIO_Pin_6: Bit_Value = P76; return Bit_Value; break;
  468   3               case GPIO_Pin_7: Bit_Value = P77; return Bit_Value; break;
  469   3               default:  return FAIL ;break;  
  470   3             }break;
  471   2             default:  return FAIL ;break;         
  472   2         }
  473   1      }
  474           /*******************************************************************************************************
             -*******************
  475           * @brief  翻转GPIO引脚电平
  476           * @exampleCode
  477           *      GPIO_Toggle_Bit(GPIO_P0, GPIO_Pin_0);   //翻转P00引脚电平
  478           * @endcode
  479           * @param[in]  GPIO_Port GPIO端口号
  480           * @param[in]  GPIO_Pin  GPIO引脚号              
  481          *********************************************************************************************************
             -******************/
  482          void GPIO_Toggle_Bit(GPIO_Port_enum GPIO_Port , GPIO_Pin_enum GPIO_Pin)
  483           {
  484   1        
  485   1         
  486   1         switch (GPIO_Port)
  487   1         {
  488   2           case GPIO_P0:  P0 ^= GPIO_Pin ; break; //端口0     
  489   2           case GPIO_P1:  P1 ^= GPIO_Pin ; break; //端口1     
  490   2           case GPIO_P2:  P2 ^= GPIO_Pin ; break; //端口2      
  491   2           case GPIO_P3:  P3 ^= GPIO_Pin ; break; //端口3      
  492   2           case GPIO_P4:  P4 ^= GPIO_Pin ; break; //端口4     
  493   2           case GPIO_P5:  P5 ^= GPIO_Pin ; break; //端口5      
  494   2           case GPIO_P6:  P6 ^= GPIO_Pin ; break; //端口6   
  495   2           case GPIO_P7:  P7 ^= GPIO_Pin ; break; //端口7
  496   2           default:
  497   2           break;        
  498   2         }
  499   1       }
  500           
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 9   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION GPIO_Init? (BEGIN)
                                                ; SOURCE LINE # 30
000000 7D41           MOV      WR8,WR2
;---- Variable 'GPIO_Mode' assigned to Register 'WR8' ----
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 32
000002 7D53           MOV      WR10,WR6
000004 BE540008       CMP      WR10,#08H
000008 4003        R  JC       $ + 5H
00000A 020000      R  LJMP     ?C0001
00000D 7EA003         MOV      R10,#03H
000010 A4             MUL      AB
000011 900000      R  MOV      DPTR,#?C0247
000014 73             JMP      @A+DPTR
               ?C0247:
000015 020000      R  LJMP     ?C0002
000018 020000      R  LJMP     ?C0004
00001B 020000      R  LJMP     ?C0005
00001E 020000      R  LJMP     ?C0006
000021 020000      R  LJMP     ?C0007
000024 020000      R  LJMP     ?C0008
000027 020000      R  LJMP     ?C0009
00002A 020000      R  LJMP     ?C0010
                                                ; SOURCE LINE # 34
               ?C0002:
                                                ; SOURCE LINE # 35
00002D 7D34           MOV      WR6,WR8
00002F 1B34           DEC      WR6,#01H
000031 681D           JE       ?C0014
000033 1B34           DEC      WR6,#01H
000035 6822           JE       ?C0015
000037 1B34           DEC      WR6,#01H
000039 6826           JE       ?C0016
00003B 2E340003       ADD      WR6,#03H
00003F 6803        R  JE       $ + 5H
000041 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 37
               ?C0012:
                                                ; SOURCE LINE # 38
000044 7CA5           MOV      R10,R5
000046 6EA0FF         XRL      R10,#0FFH
000049 7CBA           MOV      R11,R10          ; A=R11
00004B 5293           ANL      P0M1,A           ; A=R11
00004D 5294           ANL      P0M0,A           ; A=R11
00004F AA             ERET     
                                                ; SOURCE LINE # 39
               ?C0014:
                                                ; SOURCE LINE # 40
000050 7CB5           MOV      R11,R5           ; A=R11
000052 4293           ORL      P0M1,A           ; A=R11
000054 64FF           XRL      A,#0FFH          ; A=R11
000056 5294           ANL      P0M0,A           ; A=R11
000058 AA             ERET     
                                                ; SOURCE LINE # 41
               ?C0015:
                                                ; SOURCE LINE # 42
000059 7CA5           MOV      R10,R5
00005B 7CBA           MOV      R11,R10          ; A=R11
00005D 4293           ORL      P0M1,A           ; A=R11
00005F 8008           SJMP     ?C0256
                                                ; SOURCE LINE # 43
               ?C0016:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 10  

                                                ; SOURCE LINE # 44
000061 7CA5           MOV      R10,R5
000063 7CBA           MOV      R11,R10          ; A=R11
000065 64FF           XRL      A,#0FFH          ; A=R11
000067 5293           ANL      P0M1,A           ; A=R11
               ?C0256:
000069 7CBA           MOV      R11,R10          ; A=R11
00006B 4294           ORL      P0M0,A           ; A=R11
00006D AA             ERET     
                                                ; SOURCE LINE # 45
                                                ; SOURCE LINE # 46
                                                ; SOURCE LINE # 47
                                                ; SOURCE LINE # 48
               ?C0004:
                                                ; SOURCE LINE # 49
00006E 7D34           MOV      WR6,WR8
000070 1B34           DEC      WR6,#01H
000072 681D           JE       ?C0020
000074 1B34           DEC      WR6,#01H
000076 6822           JE       ?C0021
000078 1B34           DEC      WR6,#01H
00007A 6826           JE       ?C0022
00007C 2E340003       ADD      WR6,#03H
000080 6803        R  JE       $ + 5H
000082 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 51
               ?C0018:
                                                ; SOURCE LINE # 52
000085 7CA5           MOV      R10,R5
000087 6EA0FF         XRL      R10,#0FFH
00008A 7CBA           MOV      R11,R10          ; A=R11
00008C 5291           ANL      P1M1,A           ; A=R11
00008E 5292           ANL      P1M0,A           ; A=R11
000090 AA             ERET     
                                                ; SOURCE LINE # 53
               ?C0020:
                                                ; SOURCE LINE # 54
000091 7CB5           MOV      R11,R5           ; A=R11
000093 4291           ORL      P1M1,A           ; A=R11
000095 64FF           XRL      A,#0FFH          ; A=R11
000097 5292           ANL      P1M0,A           ; A=R11
000099 AA             ERET     
                                                ; SOURCE LINE # 55
               ?C0021:
                                                ; SOURCE LINE # 56
00009A 7CA5           MOV      R10,R5
00009C 7CBA           MOV      R11,R10          ; A=R11
00009E 4291           ORL      P1M1,A           ; A=R11
0000A0 8008           SJMP     ?C0257
                                                ; SOURCE LINE # 57
               ?C0022:
                                                ; SOURCE LINE # 58
0000A2 7CA5           MOV      R10,R5
0000A4 7CBA           MOV      R11,R10          ; A=R11
0000A6 64FF           XRL      A,#0FFH          ; A=R11
0000A8 5291           ANL      P1M1,A           ; A=R11
               ?C0257:
0000AA 7CBA           MOV      R11,R10          ; A=R11
0000AC 4292           ORL      P1M0,A           ; A=R11
0000AE AA             ERET     
                                                ; SOURCE LINE # 59
                                                ; SOURCE LINE # 60
                                                ; SOURCE LINE # 61
                                                ; SOURCE LINE # 62
               ?C0005:
                                                ; SOURCE LINE # 63
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 11  

0000AF 7D34           MOV      WR6,WR8
0000B1 1B34           DEC      WR6,#01H
0000B3 681D           JE       ?C0026
0000B5 1B34           DEC      WR6,#01H
0000B7 6822           JE       ?C0027
0000B9 1B34           DEC      WR6,#01H
0000BB 6826           JE       ?C0028
0000BD 2E340003       ADD      WR6,#03H
0000C1 6803        R  JE       $ + 5H
0000C3 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 65
               ?C0024:
                                                ; SOURCE LINE # 66
0000C6 7CA5           MOV      R10,R5
0000C8 6EA0FF         XRL      R10,#0FFH
0000CB 7CBA           MOV      R11,R10          ; A=R11
0000CD 5295           ANL      P2M1,A           ; A=R11
0000CF 5296           ANL      P2M0,A           ; A=R11
0000D1 AA             ERET     
                                                ; SOURCE LINE # 67
               ?C0026:
                                                ; SOURCE LINE # 68
0000D2 7CB5           MOV      R11,R5           ; A=R11
0000D4 4295           ORL      P2M1,A           ; A=R11
0000D6 64FF           XRL      A,#0FFH          ; A=R11
0000D8 5296           ANL      P2M0,A           ; A=R11
0000DA AA             ERET     
                                                ; SOURCE LINE # 69
               ?C0027:
                                                ; SOURCE LINE # 70
0000DB 7CA5           MOV      R10,R5
0000DD 7CBA           MOV      R11,R10          ; A=R11
0000DF 4295           ORL      P2M1,A           ; A=R11
0000E1 8008           SJMP     ?C0258
                                                ; SOURCE LINE # 71
               ?C0028:
                                                ; SOURCE LINE # 72
0000E3 7CA5           MOV      R10,R5
0000E5 7CBA           MOV      R11,R10          ; A=R11
0000E7 64FF           XRL      A,#0FFH          ; A=R11
0000E9 5295           ANL      P2M1,A           ; A=R11
               ?C0258:
0000EB 7CBA           MOV      R11,R10          ; A=R11
0000ED 4296           ORL      P2M0,A           ; A=R11
0000EF AA             ERET     
                                                ; SOURCE LINE # 73
                                                ; SOURCE LINE # 74
                                                ; SOURCE LINE # 75
                                                ; SOURCE LINE # 76
               ?C0006:
                                                ; SOURCE LINE # 77
0000F0 7D34           MOV      WR6,WR8
0000F2 1B34           DEC      WR6,#01H
0000F4 681D           JE       ?C0032
0000F6 1B34           DEC      WR6,#01H
0000F8 6822           JE       ?C0033
0000FA 1B34           DEC      WR6,#01H
0000FC 6826           JE       ?C0034
0000FE 2E340003       ADD      WR6,#03H
000102 6803        R  JE       $ + 5H
000104 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 79
               ?C0030:
                                                ; SOURCE LINE # 80
000107 7CA5           MOV      R10,R5
000109 6EA0FF         XRL      R10,#0FFH
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 12  

00010C 7CBA           MOV      R11,R10          ; A=R11
00010E 52B1           ANL      P3M1,A           ; A=R11
000110 52B2           ANL      P3M0,A           ; A=R11
000112 AA             ERET     
                                                ; SOURCE LINE # 81
               ?C0032:
                                                ; SOURCE LINE # 82
000113 7CB5           MOV      R11,R5           ; A=R11
000115 42B1           ORL      P3M1,A           ; A=R11
000117 64FF           XRL      A,#0FFH          ; A=R11
000119 52B2           ANL      P3M0,A           ; A=R11
00011B AA             ERET     
                                                ; SOURCE LINE # 83
               ?C0033:
                                                ; SOURCE LINE # 84
00011C 7CA5           MOV      R10,R5
00011E 7CBA           MOV      R11,R10          ; A=R11
000120 42B1           ORL      P3M1,A           ; A=R11
000122 8008           SJMP     ?C0259
                                                ; SOURCE LINE # 85
               ?C0034:
                                                ; SOURCE LINE # 86
000124 7CA5           MOV      R10,R5
000126 7CBA           MOV      R11,R10          ; A=R11
000128 64FF           XRL      A,#0FFH          ; A=R11
00012A 52B1           ANL      P3M1,A           ; A=R11
               ?C0259:
00012C 7CBA           MOV      R11,R10          ; A=R11
00012E 42B2           ORL      P3M0,A           ; A=R11
000130 AA             ERET     
                                                ; SOURCE LINE # 87
                                                ; SOURCE LINE # 88
                                                ; SOURCE LINE # 89
                                                ; SOURCE LINE # 90
               ?C0007:
                                                ; SOURCE LINE # 91
000131 7D34           MOV      WR6,WR8
000133 1B34           DEC      WR6,#01H
000135 681D           JE       ?C0038
000137 1B34           DEC      WR6,#01H
000139 6822           JE       ?C0039
00013B 1B34           DEC      WR6,#01H
00013D 6826           JE       ?C0040
00013F 2E340003       ADD      WR6,#03H
000143 6803        R  JE       $ + 5H
000145 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 93
               ?C0036:
                                                ; SOURCE LINE # 94
000148 7CA5           MOV      R10,R5
00014A 6EA0FF         XRL      R10,#0FFH
00014D 7CBA           MOV      R11,R10          ; A=R11
00014F 52B3           ANL      P4M1,A           ; A=R11
000151 52B4           ANL      P4M0,A           ; A=R11
000153 AA             ERET     
                                                ; SOURCE LINE # 95
               ?C0038:
                                                ; SOURCE LINE # 96
000154 7CB5           MOV      R11,R5           ; A=R11
000156 42B3           ORL      P4M1,A           ; A=R11
000158 64FF           XRL      A,#0FFH          ; A=R11
00015A 52B4           ANL      P4M0,A           ; A=R11
00015C AA             ERET     
                                                ; SOURCE LINE # 97
               ?C0039:
                                                ; SOURCE LINE # 98
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 13  

00015D 7CA5           MOV      R10,R5
00015F 7CBA           MOV      R11,R10          ; A=R11
000161 42B3           ORL      P4M1,A           ; A=R11
000163 8008           SJMP     ?C0260
                                                ; SOURCE LINE # 99
               ?C0040:
                                                ; SOURCE LINE # 100
000165 7CA5           MOV      R10,R5
000167 7CBA           MOV      R11,R10          ; A=R11
000169 64FF           XRL      A,#0FFH          ; A=R11
00016B 52B3           ANL      P4M1,A           ; A=R11
               ?C0260:
00016D 7CBA           MOV      R11,R10          ; A=R11
00016F 42B4           ORL      P4M0,A           ; A=R11
000171 AA             ERET     
                                                ; SOURCE LINE # 101
                                                ; SOURCE LINE # 102
                                                ; SOURCE LINE # 103
                                                ; SOURCE LINE # 104
               ?C0008:
                                                ; SOURCE LINE # 105
000172 7D34           MOV      WR6,WR8
000174 1B34           DEC      WR6,#01H
000176 681D           JE       ?C0044
000178 1B34           DEC      WR6,#01H
00017A 6822           JE       ?C0045
00017C 1B34           DEC      WR6,#01H
00017E 6826           JE       ?C0046
000180 2E340003       ADD      WR6,#03H
000184 6803        R  JE       $ + 5H
000186 020000      R  LJMP     ?C0001
                                                ; SOURCE LINE # 107
               ?C0042:
                                                ; SOURCE LINE # 108
000189 7CA5           MOV      R10,R5
00018B 6EA0FF         XRL      R10,#0FFH
00018E 7CBA           MOV      R11,R10          ; A=R11
000190 52C9           ANL      P5M1,A           ; A=R11
000192 52CA           ANL      P5M0,A           ; A=R11
000194 AA             ERET     
                                                ; SOURCE LINE # 109
               ?C0044:
                                                ; SOURCE LINE # 110
000195 7CB5           MOV      R11,R5           ; A=R11
000197 42C9           ORL      P5M1,A           ; A=R11
000199 64FF           XRL      A,#0FFH          ; A=R11
00019B 52CA           ANL      P5M0,A           ; A=R11
00019D AA             ERET     
                                                ; SOURCE LINE # 111
               ?C0045:
                                                ; SOURCE LINE # 112
00019E 7CA5           MOV      R10,R5
0001A0 7CBA           MOV      R11,R10          ; A=R11
0001A2 42C9           ORL      P5M1,A           ; A=R11
0001A4 8008           SJMP     ?C0261
                                                ; SOURCE LINE # 113
               ?C0046:
                                                ; SOURCE LINE # 114
0001A6 7CA5           MOV      R10,R5
0001A8 7CBA           MOV      R11,R10          ; A=R11
0001AA 64FF           XRL      A,#0FFH          ; A=R11
0001AC 52C9           ANL      P5M1,A           ; A=R11
               ?C0261:
0001AE 7CBA           MOV      R11,R10          ; A=R11
0001B0 42CA           ORL      P5M0,A           ; A=R11
0001B2 AA             ERET     
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 14  

                                                ; SOURCE LINE # 115
                                                ; SOURCE LINE # 116
                                                ; SOURCE LINE # 117
                                                ; SOURCE LINE # 118
               ?C0009:
                                                ; SOURCE LINE # 119
0001B3 7D34           MOV      WR6,WR8
0001B5 1B34           DEC      WR6,#01H
0001B7 681A           JE       ?C0050
0001B9 1B34           DEC      WR6,#01H
0001BB 681F           JE       ?C0051
0001BD 1B34           DEC      WR6,#01H
0001BF 6823           JE       ?C0052
0001C1 2E340003       ADD      WR6,#03H
0001C5 7865           JNE      ?C0001
                                                ; SOURCE LINE # 121
               ?C0048:
                                                ; SOURCE LINE # 122
0001C7 7CA5           MOV      R10,R5
0001C9 6EA0FF         XRL      R10,#0FFH
0001CC 7CBA           MOV      R11,R10          ; A=R11
0001CE 52CB           ANL      P6M1,A           ; A=R11
0001D0 52CC           ANL      P6M0,A           ; A=R11
0001D2 AA             ERET     
                                                ; SOURCE LINE # 123
               ?C0050:
                                                ; SOURCE LINE # 124
0001D3 7CB5           MOV      R11,R5           ; A=R11
0001D5 42CB           ORL      P6M1,A           ; A=R11
0001D7 64FF           XRL      A,#0FFH          ; A=R11
0001D9 52CC           ANL      P6M0,A           ; A=R11
0001DB AA             ERET     
                                                ; SOURCE LINE # 125
               ?C0051:
                                                ; SOURCE LINE # 126
0001DC 7CA5           MOV      R10,R5
0001DE 7CBA           MOV      R11,R10          ; A=R11
0001E0 42CB           ORL      P6M1,A           ; A=R11
0001E2 8008           SJMP     ?C0262
                                                ; SOURCE LINE # 127
               ?C0052:
                                                ; SOURCE LINE # 128
0001E4 7CA5           MOV      R10,R5
0001E6 7CBA           MOV      R11,R10          ; A=R11
0001E8 64FF           XRL      A,#0FFH          ; A=R11
0001EA 52CB           ANL      P6M1,A           ; A=R11
               ?C0262:
0001EC 7CBA           MOV      R11,R10          ; A=R11
0001EE 42CC           ORL      P6M0,A           ; A=R11
0001F0 AA             ERET     
                                                ; SOURCE LINE # 129
                                                ; SOURCE LINE # 130
                                                ; SOURCE LINE # 131
                                                ; SOURCE LINE # 132
               ?C0010:
                                                ; SOURCE LINE # 133
0001F1 1B44           DEC      WR8,#01H
0001F3 681A           JE       ?C0056
0001F5 1B44           DEC      WR8,#01H
0001F7 681F           JE       ?C0057
0001F9 1B44           DEC      WR8,#01H
0001FB 6823           JE       ?C0058
0001FD 2E440003       ADD      WR8,#03H
000201 7829           JNE      ?C0001
                                                ; SOURCE LINE # 135
               ?C0054:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 15  

                                                ; SOURCE LINE # 136
000203 7CA5           MOV      R10,R5
000205 6EA0FF         XRL      R10,#0FFH
000208 7CBA           MOV      R11,R10          ; A=R11
00020A 52E1           ANL      P7M1,A           ; A=R11
00020C 52E2           ANL      P7M0,A           ; A=R11
00020E AA             ERET     
                                                ; SOURCE LINE # 137
               ?C0056:
                                                ; SOURCE LINE # 138
00020F 7CB5           MOV      R11,R5           ; A=R11
000211 42E1           ORL      P7M1,A           ; A=R11
000213 64FF           XRL      A,#0FFH          ; A=R11
000215 52E2           ANL      P7M0,A           ; A=R11
000217 AA             ERET     
                                                ; SOURCE LINE # 139
               ?C0057:
                                                ; SOURCE LINE # 140
000218 7CA5           MOV      R10,R5
00021A 7CBA           MOV      R11,R10          ; A=R11
00021C 42E1           ORL      P7M1,A           ; A=R11
00021E 8008           SJMP     ?C0263
                                                ; SOURCE LINE # 141
               ?C0058:
                                                ; SOURCE LINE # 142
000220 7CA5           MOV      R10,R5
000222 7CBA           MOV      R11,R10          ; A=R11
000224 64FF           XRL      A,#0FFH          ; A=R11
000226 52E1           ANL      P7M1,A           ; A=R11
               ?C0263:
000228 7CBA           MOV      R11,R10          ; A=R11
00022A 42E2           ORL      P7M0,A           ; A=R11
                                                ; SOURCE LINE # 143
                                                ; SOURCE LINE # 144
                                                ; SOURCE LINE # 145
                                                ; SOURCE LINE # 146
                                                ; SOURCE LINE # 147
                                                ; SOURCE LINE # 148
               ?C0001:
                                                ; SOURCE LINE # 149
00022C AA             ERET     
;       FUNCTION GPIO_Init? (END)

;       FUNCTION GPIO_PinPullConfig? (BEGIN)
                                                ; SOURCE LINE # 162
00022D 7D41           MOV      WR8,WR2
;---- Variable 'GPIO_Pin_Config' assigned to Register 'WR8' ----
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
00022F 7D13           MOV      WR2,WR6
;---- Variable 'GPIO_Port' assigned to Register 'WR2' ----
                                                ; SOURCE LINE # 164
000231 BE140007       CMP      WR2,#07H
000235 0802           JSLE     ?C0059
000237 E4             CLR      A                ; A=R11
000238 AA             ERET     
               ?C0059:
                                                ; SOURCE LINE # 165
000239 BE2400FF       CMP      WR4,#0FFH
00023D 0802           JSLE     ?C0061
00023F E4             CLR      A                ; A=R11
000240 AA             ERET     
               ?C0061:
                                                ; SOURCE LINE # 166
000241 BE440000       CMP      WR8,#00H
000245 0802           JSLE     ?C0062
000247 E4             CLR      A                ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 16  

000248 AA             ERET     
               ?C0062:
                                                ; SOURCE LINE # 168
000249 7D51           MOV      WR10,WR2
00024B BE540008       CMP      WR10,#08H
00024F 4003        R  JC       $ + 5H
000251 020000      R  LJMP     ?C0065
000254 7EA003         MOV      R10,#03H
000257 A4             MUL      AB
000258 900000      R  MOV      DPTR,#?C0249
00025B 73             JMP      @A+DPTR
               ?C0249:
00025C 020000      R  LJMP     ?C0064
00025F 020000      R  LJMP     ?C0066
000262 020000      R  LJMP     ?C0067
000265 020000      R  LJMP     ?C0068
000268 020000      R  LJMP     ?C0069
00026B 020000      R  LJMP     ?C0070
00026E 020000      R  LJMP     ?C0071
000271 020000      R  LJMP     ?C0072
                                                ; SOURCE LINE # 170
               ?C0064:
                                                ; SOURCE LINE # 171
000274 7D34           MOV      WR6,WR8
000276 1B34           DEC      WR6,#01H
000278 680F           JE       ?C0076
00027A 0B34           INC      WR6,#01H
00027C 7814           JNE      ?C0075
                                                ; SOURCE LINE # 173
               ?C0074:
                                                ; SOURCE LINE # 174
00027E 7CB5           MOV      R11,R5           ; A=R11
000280 64FF           XRL      A,#0FFH          ; A=R11
000282 7E14FE10       MOV      WR2,#0FE10H
000286 020000      R  LJMP     ?C0276
                                                ; SOURCE LINE # 175
               ?C0076:
                                                ; SOURCE LINE # 176
000289 7C65           MOV      R6,R5
00028B 7E14FE10       MOV      WR2,#0FE10H
00028F 020000      R  LJMP     ?C0277
                                                ; SOURCE LINE # 177
               ?C0075:
                                                ; SOURCE LINE # 178
000292 E4             CLR      A                ; A=R11
000293 AA             ERET     
                                                ; SOURCE LINE # 179
                                                ; SOURCE LINE # 180
               ?C0066:
                                                ; SOURCE LINE # 181
000294 7D34           MOV      WR6,WR8
000296 1B34           DEC      WR6,#01H
000298 680F           JE       ?C0080
00029A 0B34           INC      WR6,#01H
00029C 7814           JNE      ?C0079
                                                ; SOURCE LINE # 183
               ?C0078:
                                                ; SOURCE LINE # 184
00029E 7CB5           MOV      R11,R5           ; A=R11
0002A0 64FF           XRL      A,#0FFH          ; A=R11
0002A2 7E14FE11       MOV      WR2,#0FE11H
0002A6 020000      R  LJMP     ?C0276
                                                ; SOURCE LINE # 185
               ?C0080:
                                                ; SOURCE LINE # 186
0002A9 7C65           MOV      R6,R5
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 17  

0002AB 7E14FE11       MOV      WR2,#0FE11H
0002AF 020000      R  LJMP     ?C0277
                                                ; SOURCE LINE # 187
               ?C0079:
                                                ; SOURCE LINE # 188
0002B2 E4             CLR      A                ; A=R11
0002B3 AA             ERET     
                                                ; SOURCE LINE # 189
                                                ; SOURCE LINE # 190
               ?C0067:
                                                ; SOURCE LINE # 191
0002B4 7D34           MOV      WR6,WR8
0002B6 1B34           DEC      WR6,#01H
0002B8 680F           JE       ?C0084
0002BA 0B34           INC      WR6,#01H
0002BC 7814           JNE      ?C0083
                                                ; SOURCE LINE # 193
               ?C0082:
                                                ; SOURCE LINE # 194
0002BE 7CB5           MOV      R11,R5           ; A=R11
0002C0 64FF           XRL      A,#0FFH          ; A=R11
0002C2 7E14FE12       MOV      WR2,#0FE12H
0002C6 020000      R  LJMP     ?C0276
                                                ; SOURCE LINE # 195
               ?C0084:
                                                ; SOURCE LINE # 196
0002C9 7C65           MOV      R6,R5
0002CB 7E14FE12       MOV      WR2,#0FE12H
0002CF 020000      R  LJMP     ?C0277
                                                ; SOURCE LINE # 197
               ?C0083:
                                                ; SOURCE LINE # 198
0002D2 E4             CLR      A                ; A=R11
0002D3 AA             ERET     
                                                ; SOURCE LINE # 199
                                                ; SOURCE LINE # 200
               ?C0068:
                                                ; SOURCE LINE # 201
0002D4 7D34           MOV      WR6,WR8
0002D6 1B34           DEC      WR6,#01H
0002D8 680E           JE       ?C0088
0002DA 0B34           INC      WR6,#01H
0002DC 7812           JNE      ?C0087
                                                ; SOURCE LINE # 203
               ?C0086:
                                                ; SOURCE LINE # 204
0002DE 7CB5           MOV      R11,R5           ; A=R11
0002E0 64FF           XRL      A,#0FFH          ; A=R11
0002E2 7E14FE13       MOV      WR2,#0FE13H
0002E6 8074           SJMP     ?C0276
                                                ; SOURCE LINE # 205
               ?C0088:
                                                ; SOURCE LINE # 206
0002E8 7C65           MOV      R6,R5
0002EA 7E14FE13       MOV      WR2,#0FE13H
0002EE 807D           SJMP     ?C0277
                                                ; SOURCE LINE # 207
               ?C0087:
                                                ; SOURCE LINE # 208
0002F0 E4             CLR      A                ; A=R11
0002F1 AA             ERET     
                                                ; SOURCE LINE # 209
                                                ; SOURCE LINE # 210
               ?C0069:
                                                ; SOURCE LINE # 211
0002F2 7D34           MOV      WR6,WR8
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 18  

0002F4 1B34           DEC      WR6,#01H
0002F6 680E           JE       ?C0092
0002F8 0B34           INC      WR6,#01H
0002FA 7812           JNE      ?C0091
                                                ; SOURCE LINE # 213
               ?C0090:
                                                ; SOURCE LINE # 214
0002FC 7CB5           MOV      R11,R5           ; A=R11
0002FE 64FF           XRL      A,#0FFH          ; A=R11
000300 7E14FE14       MOV      WR2,#0FE14H
000304 8056           SJMP     ?C0276
                                                ; SOURCE LINE # 215
               ?C0092:
                                                ; SOURCE LINE # 216
000306 7C65           MOV      R6,R5
000308 7E14FE14       MOV      WR2,#0FE14H
00030C 805F           SJMP     ?C0277
                                                ; SOURCE LINE # 217
               ?C0091:
                                                ; SOURCE LINE # 218
00030E E4             CLR      A                ; A=R11
00030F AA             ERET     
                                                ; SOURCE LINE # 219
                                                ; SOURCE LINE # 220
               ?C0070:
                                                ; SOURCE LINE # 221
000310 7D34           MOV      WR6,WR8
000312 1B34           DEC      WR6,#01H
000314 680E           JE       ?C0096
000316 0B34           INC      WR6,#01H
000318 7812           JNE      ?C0095
                                                ; SOURCE LINE # 223
               ?C0094:
                                                ; SOURCE LINE # 224
00031A 7CB5           MOV      R11,R5           ; A=R11
00031C 64FF           XRL      A,#0FFH          ; A=R11
00031E 7E14FE15       MOV      WR2,#0FE15H
000322 8038           SJMP     ?C0276
                                                ; SOURCE LINE # 225
               ?C0096:
                                                ; SOURCE LINE # 226
000324 7C65           MOV      R6,R5
000326 7E14FE15       MOV      WR2,#0FE15H
00032A 8041           SJMP     ?C0277
                                                ; SOURCE LINE # 227
               ?C0095:
                                                ; SOURCE LINE # 228
00032C E4             CLR      A                ; A=R11
00032D AA             ERET     
                                                ; SOURCE LINE # 229
                                                ; SOURCE LINE # 230
               ?C0071:
                                                ; SOURCE LINE # 231
00032E 7D34           MOV      WR6,WR8
000330 1B34           DEC      WR6,#01H
000332 680E           JE       ?C0100
000334 0B34           INC      WR6,#01H
000336 7812           JNE      ?C0099
                                                ; SOURCE LINE # 233
               ?C0098:
                                                ; SOURCE LINE # 234
000338 7CB5           MOV      R11,R5           ; A=R11
00033A 64FF           XRL      A,#0FFH          ; A=R11
00033C 7E14FE16       MOV      WR2,#0FE16H
000340 801A           SJMP     ?C0276
                                                ; SOURCE LINE # 235
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 19  

               ?C0100:
                                                ; SOURCE LINE # 236
000342 7C65           MOV      R6,R5
000344 7E14FE16       MOV      WR2,#0FE16H
000348 8023           SJMP     ?C0277
                                                ; SOURCE LINE # 237
               ?C0099:
                                                ; SOURCE LINE # 238
00034A E4             CLR      A                ; A=R11
00034B AA             ERET     
                                                ; SOURCE LINE # 239
                                                ; SOURCE LINE # 240
               ?C0072:
                                                ; SOURCE LINE # 241
00034C 1B44           DEC      WR8,#01H
00034E 6817           JE       ?C0104
000350 0B44           INC      WR8,#01H
000352 7827           JNE      ?C0103
                                                ; SOURCE LINE # 243
               ?C0102:
                                                ; SOURCE LINE # 244
000354 7CB5           MOV      R11,R5           ; A=R11
000356 64FF           XRL      A,#0FFH          ; A=R11
000358 7E14FE17       MOV      WR2,#0FE17H
               ?C0276:
00035C 7E04007E       MOV      WR0,#07EH
000360 7E0B70         MOV      R7,@DR0
000363 5C7B           ANL      R7,R11           ; A=R11
000365 800F           SJMP     ?C0278
                                                ; SOURCE LINE # 245
               ?C0104:
                                                ; SOURCE LINE # 246
000367 7C65           MOV      R6,R5
000369 7E14FE17       MOV      WR2,#0FE17H
               ?C0277:
00036D 7E04007E       MOV      WR0,#07EH
000371 7E0B70         MOV      R7,@DR0
000374 4C76           ORL      R7,R6
               ?C0278:
000376 7A0B70         MOV      @DR0,R7
000379 8004           SJMP     ?C0063
                                                ; SOURCE LINE # 247
               ?C0103:
                                                ; SOURCE LINE # 248
00037B E4             CLR      A                ; A=R11
00037C AA             ERET     
                                                ; SOURCE LINE # 249
                                                ; SOURCE LINE # 250
               ?C0065:
                                                ; SOURCE LINE # 251
00037D E4             CLR      A                ; A=R11
00037E AA             ERET     
                                                ; SOURCE LINE # 252
               ?C0063:
                                                ; SOURCE LINE # 253
00037F 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 254
000381 AA             ERET     
;       FUNCTION GPIO_PinPullConfig? (END)

;       FUNCTION GPIO_Write_Bit? (BEGIN)
                                                ; SOURCE LINE # 264
000382 7C3B           MOV      R3,R11           ; A=R11
;---- Variable 'data_t' assigned to Register 'R3' ----
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 20  

                                                ; SOURCE LINE # 267
000384 7D53           MOV      WR10,WR6
000386 BE540008       CMP      WR10,#08H
00038A 4003        R  JC       $ + 5H
00038C 020000      R  LJMP     ?C0105
00038F 7EA003         MOV      R10,#03H
000392 A4             MUL      AB
000393 900000      R  MOV      DPTR,#?C0251
000396 73             JMP      @A+DPTR
               ?C0251:
000397 020000      R  LJMP     ?C0106
00039A 020000      R  LJMP     ?C0108
00039D 020000      R  LJMP     ?C0109
0003A0 020000      R  LJMP     ?C0110
0003A3 020000      R  LJMP     ?C0111
0003A6 020000      R  LJMP     ?C0112
0003A9 020000      R  LJMP     ?C0113
0003AC 020000      R  LJMP     ?C0114
                                                ; SOURCE LINE # 269
               ?C0106:
                                                ; SOURCE LINE # 270
0003AF 7CB3           MOV      R11,R3           ; A=R11
0003B1 14             DEC      A                ; A=R11
0003B2 680D           JE       ?C0118
0003B4 04             INC      A                ; A=R11
0003B5 6803        R  JE       $ + 5H
0003B7 020000      R  LJMP     ?C0105
                                                ; SOURCE LINE # 272
               ?C0116:
                                                ; SOURCE LINE # 273
0003BA 7CB5           MOV      R11,R5           ; A=R11
0003BC 64FF           XRL      A,#0FFH          ; A=R11
0003BE 5280           ANL      P0,A             ; A=R11
0003C0 AA             ERET     
                                                ; SOURCE LINE # 274
               ?C0118:
                                                ; SOURCE LINE # 275
0003C1 7CB5           MOV      R11,R5           ; A=R11
0003C3 4280           ORL      P0,A             ; A=R11
0003C5 AA             ERET     
                                                ; SOURCE LINE # 276
                                                ; SOURCE LINE # 277
                                                ; SOURCE LINE # 278
                                                ; SOURCE LINE # 279
               ?C0108:
                                                ; SOURCE LINE # 280
0003C6 7CB3           MOV      R11,R3           ; A=R11
0003C8 14             DEC      A                ; A=R11
0003C9 680D           JE       ?C0122
0003CB 04             INC      A                ; A=R11
0003CC 6803        R  JE       $ + 5H
0003CE 020000      R  LJMP     ?C0105
                                                ; SOURCE LINE # 282
               ?C0120:
                                                ; SOURCE LINE # 283
0003D1 7CB5           MOV      R11,R5           ; A=R11
0003D3 64FF           XRL      A,#0FFH          ; A=R11
0003D5 5290           ANL      P1,A             ; A=R11
0003D7 AA             ERET     
                                                ; SOURCE LINE # 284
               ?C0122:
                                                ; SOURCE LINE # 285
0003D8 7CB5           MOV      R11,R5           ; A=R11
0003DA 4290           ORL      P1,A             ; A=R11
0003DC AA             ERET     
                                                ; SOURCE LINE # 286
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 21  

                                                ; SOURCE LINE # 287
                                                ; SOURCE LINE # 288
                                                ; SOURCE LINE # 289
               ?C0109:
                                                ; SOURCE LINE # 290
0003DD 7CB3           MOV      R11,R3           ; A=R11
0003DF 14             DEC      A                ; A=R11
0003E0 680A           JE       ?C0126
0003E2 04             INC      A                ; A=R11
0003E3 786F           JNE      ?C0105
                                                ; SOURCE LINE # 292
               ?C0124:
                                                ; SOURCE LINE # 293
0003E5 7CB5           MOV      R11,R5           ; A=R11
0003E7 64FF           XRL      A,#0FFH          ; A=R11
0003E9 52A0           ANL      P2,A             ; A=R11
0003EB AA             ERET     
                                                ; SOURCE LINE # 294
               ?C0126:
                                                ; SOURCE LINE # 295
0003EC 7CB5           MOV      R11,R5           ; A=R11
0003EE 42A0           ORL      P2,A             ; A=R11
0003F0 AA             ERET     
                                                ; SOURCE LINE # 296
                                                ; SOURCE LINE # 297
                                                ; SOURCE LINE # 298
                                                ; SOURCE LINE # 299
               ?C0110:
                                                ; SOURCE LINE # 300
0003F1 7CB3           MOV      R11,R3           ; A=R11
0003F3 14             DEC      A                ; A=R11
0003F4 680A           JE       ?C0130
0003F6 04             INC      A                ; A=R11
0003F7 785B           JNE      ?C0105
                                                ; SOURCE LINE # 302
               ?C0128:
                                                ; SOURCE LINE # 303
0003F9 7CB5           MOV      R11,R5           ; A=R11
0003FB 64FF           XRL      A,#0FFH          ; A=R11
0003FD 52B0           ANL      P3,A             ; A=R11
0003FF AA             ERET     
                                                ; SOURCE LINE # 304
               ?C0130:
                                                ; SOURCE LINE # 305
000400 7CB5           MOV      R11,R5           ; A=R11
000402 42B0           ORL      P3,A             ; A=R11
000404 AA             ERET     
                                                ; SOURCE LINE # 306
                                                ; SOURCE LINE # 307
                                                ; SOURCE LINE # 308
                                                ; SOURCE LINE # 309
               ?C0111:
                                                ; SOURCE LINE # 310
000405 7CB3           MOV      R11,R3           ; A=R11
000407 14             DEC      A                ; A=R11
000408 680A           JE       ?C0134
00040A 04             INC      A                ; A=R11
00040B 7847           JNE      ?C0105
                                                ; SOURCE LINE # 312
               ?C0132:
                                                ; SOURCE LINE # 313
00040D 7CB5           MOV      R11,R5           ; A=R11
00040F 64FF           XRL      A,#0FFH          ; A=R11
000411 52C0           ANL      P4,A             ; A=R11
000413 AA             ERET     
                                                ; SOURCE LINE # 314
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 22  

               ?C0134:
                                                ; SOURCE LINE # 315
000414 7CB5           MOV      R11,R5           ; A=R11
000416 42C0           ORL      P4,A             ; A=R11
000418 AA             ERET     
                                                ; SOURCE LINE # 316
                                                ; SOURCE LINE # 317
                                                ; SOURCE LINE # 318
                                                ; SOURCE LINE # 319
               ?C0112:
                                                ; SOURCE LINE # 320
000419 7CB3           MOV      R11,R3           ; A=R11
00041B 14             DEC      A                ; A=R11
00041C 680A           JE       ?C0138
00041E 04             INC      A                ; A=R11
00041F 7833           JNE      ?C0105
                                                ; SOURCE LINE # 322
               ?C0136:
                                                ; SOURCE LINE # 323
000421 7CB5           MOV      R11,R5           ; A=R11
000423 64FF           XRL      A,#0FFH          ; A=R11
000425 52C8           ANL      P5,A             ; A=R11
000427 AA             ERET     
                                                ; SOURCE LINE # 324
               ?C0138:
                                                ; SOURCE LINE # 325
000428 7CB5           MOV      R11,R5           ; A=R11
00042A 42C8           ORL      P5,A             ; A=R11
00042C AA             ERET     
                                                ; SOURCE LINE # 326
                                                ; SOURCE LINE # 327
                                                ; SOURCE LINE # 328
                                                ; SOURCE LINE # 329
               ?C0113:
                                                ; SOURCE LINE # 330
00042D 7CB3           MOV      R11,R3           ; A=R11
00042F 14             DEC      A                ; A=R11
000430 680A           JE       ?C0142
000432 04             INC      A                ; A=R11
000433 781F           JNE      ?C0105
                                                ; SOURCE LINE # 332
               ?C0140:
                                                ; SOURCE LINE # 333
000435 7CB5           MOV      R11,R5           ; A=R11
000437 64FF           XRL      A,#0FFH          ; A=R11
000439 52E8           ANL      P6,A             ; A=R11
00043B AA             ERET     
                                                ; SOURCE LINE # 334
               ?C0142:
                                                ; SOURCE LINE # 335
00043C 7CB5           MOV      R11,R5           ; A=R11
00043E 42E8           ORL      P6,A             ; A=R11
000440 AA             ERET     
                                                ; SOURCE LINE # 336
                                                ; SOURCE LINE # 337
                                                ; SOURCE LINE # 338
                                                ; SOURCE LINE # 339
               ?C0114:
                                                ; SOURCE LINE # 340
000441 1B30           DEC      R3,#01H
000443 680B           JE       ?C0146
000445 0B30           INC      R3,#01H
000447 780B           JNE      ?C0105
                                                ; SOURCE LINE # 342
               ?C0144:
                                                ; SOURCE LINE # 343
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 23  

000449 7CB5           MOV      R11,R5           ; A=R11
00044B 64FF           XRL      A,#0FFH          ; A=R11
00044D 52F8           ANL      P7,A             ; A=R11
00044F AA             ERET     
                                                ; SOURCE LINE # 344
               ?C0146:
                                                ; SOURCE LINE # 345
000450 7CB5           MOV      R11,R5           ; A=R11
000452 42F8           ORL      P7,A             ; A=R11
                                                ; SOURCE LINE # 346
                                                ; SOURCE LINE # 347
                                                ; SOURCE LINE # 348
                                                ; SOURCE LINE # 349
                                                ; SOURCE LINE # 350
                                                ; SOURCE LINE # 351
               ?C0105:
                                                ; SOURCE LINE # 352
000454 AA             ERET     
;       FUNCTION GPIO_Write_Bit? (END)

;       FUNCTION GPIO_Read_Bit? (BEGIN)
                                                ; SOURCE LINE # 364
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
;---- Variable 'Bit_Value' assigned to Register 'R3' ----
                                                ; SOURCE LINE # 365
                                                ; SOURCE LINE # 367
000455 7D53           MOV      WR10,WR6
000457 BE540008       CMP      WR10,#08H
00045B 4003        R  JC       $ + 5H
00045D 020000      R  LJMP     ?C0149
000460 7EA003         MOV      R10,#03H
000463 A4             MUL      AB
000464 900000      R  MOV      DPTR,#?C0253
000467 73             JMP      @A+DPTR
               ?C0253:
000468 020000      R  LJMP     ?C0148
00046B 020000      R  LJMP     ?C0150
00046E 020000      R  LJMP     ?C0151
000471 020000      R  LJMP     ?C0152
000474 020000      R  LJMP     ?C0153
000477 020000      R  LJMP     ?C0154
00047A 020000      R  LJMP     ?C0155
00047D 020000      R  LJMP     ?C0156
                                                ; SOURCE LINE # 369
               ?C0148:
                                                ; SOURCE LINE # 370
000480 7D32           MOV      WR6,WR4
000482 1B35           DEC      WR6,#02H
000484 682B           JE       ?C0160
000486 1B35           DEC      WR6,#02H
000488 682C           JE       ?C0161
00048A 1B36           DEC      WR6,#04H
00048C 682D           JE       ?C0162
00048E 2E34FFF8       ADD      WR6,#0FFF8H
000492 682C           JE       ?C0163
000494 2E34FFF0       ADD      WR6,#0FFF0H
000498 682B           JE       ?C0164
00049A 2E34FFE0       ADD      WR6,#0FFE0H
00049E 682A           JE       ?C0165
0004A0 2E34FFC0       ADD      WR6,#0FFC0H
0004A4 6829           JE       ?C0166
0004A6 2E34007F       ADD      WR6,#07FH
0004AA 7828           JNE      ?C0159
                                                ; SOURCE LINE # 372
               ?C0158:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 24  

0004AC A280           MOV      C,P00
0004AE 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 373
               ?C0160:
0004B1 A281           MOV      C,P01
0004B3 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 374
               ?C0161:
0004B6 A282           MOV      C,P02
0004B8 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 375
               ?C0162:
0004BB A283           MOV      C,P03
0004BD 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 376
               ?C0163:
0004C0 A284           MOV      C,P04
0004C2 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 377
               ?C0164:
0004C5 A285           MOV      C,P05
0004C7 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 378
               ?C0165:
0004CA A286           MOV      C,P06
0004CC 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 379
               ?C0166:
0004CF A287           MOV      C,P07
0004D1 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 380
               ?C0159:
0004D4 E4             CLR      A                ; A=R11
0004D5 AA             ERET     
                                                ; SOURCE LINE # 381
                                                ; SOURCE LINE # 382
               ?C0150:
                                                ; SOURCE LINE # 383
0004D6 7D32           MOV      WR6,WR4
0004D8 1B35           DEC      WR6,#02H
0004DA 682B           JE       ?C0171
0004DC 1B35           DEC      WR6,#02H
0004DE 682C           JE       ?C0172
0004E0 1B36           DEC      WR6,#04H
0004E2 682D           JE       ?C0173
0004E4 2E34FFF8       ADD      WR6,#0FFF8H
0004E8 682C           JE       ?C0174
0004EA 2E34FFF0       ADD      WR6,#0FFF0H
0004EE 682B           JE       ?C0175
0004F0 2E34FFE0       ADD      WR6,#0FFE0H
0004F4 682A           JE       ?C0176
0004F6 2E34FFC0       ADD      WR6,#0FFC0H
0004FA 6829           JE       ?C0177
0004FC 2E34007F       ADD      WR6,#07FH
000500 7828           JNE      ?C0170
                                                ; SOURCE LINE # 385
               ?C0169:
000502 A290           MOV      C,P10
000504 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 386
               ?C0171:
000507 A291           MOV      C,P11
000509 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 387
               ?C0172:
00050C A292           MOV      C,P12
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 25  

00050E 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 388
               ?C0173:
000511 A293           MOV      C,P13
000513 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 389
               ?C0174:
000516 A294           MOV      C,P14
000518 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 390
               ?C0175:
00051B A295           MOV      C,P15
00051D 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 391
               ?C0176:
000520 A296           MOV      C,P16
000522 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 392
               ?C0177:
000525 A297           MOV      C,P17
000527 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 393
               ?C0170:
00052A E4             CLR      A                ; A=R11
00052B AA             ERET     
                                                ; SOURCE LINE # 394
                                                ; SOURCE LINE # 395
               ?C0151:
                                                ; SOURCE LINE # 396
00052C 7D32           MOV      WR6,WR4
00052E 1B35           DEC      WR6,#02H
000530 682B           JE       ?C0181
000532 1B35           DEC      WR6,#02H
000534 682C           JE       ?C0182
000536 1B36           DEC      WR6,#04H
000538 682D           JE       ?C0183
00053A 2E34FFF8       ADD      WR6,#0FFF8H
00053E 682C           JE       ?C0184
000540 2E34FFF0       ADD      WR6,#0FFF0H
000544 682B           JE       ?C0185
000546 2E34FFE0       ADD      WR6,#0FFE0H
00054A 682A           JE       ?C0186
00054C 2E34FFC0       ADD      WR6,#0FFC0H
000550 6829           JE       ?C0187
000552 2E34007F       ADD      WR6,#07FH
000556 7828           JNE      ?C0180
                                                ; SOURCE LINE # 398
               ?C0179:
000558 A2A0           MOV      C,P20
00055A 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 399
               ?C0181:
00055D A2A1           MOV      C,P21
00055F 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 400
               ?C0182:
000562 A2A2           MOV      C,P22
000564 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 401
               ?C0183:
000567 A2A3           MOV      C,P23
000569 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 402
               ?C0184:
00056C A2A4           MOV      C,P24
00056E 020000      R  LJMP     ?C0339
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 26  

                                                ; SOURCE LINE # 403
               ?C0185:
000571 A2A5           MOV      C,P25
000573 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 404
               ?C0186:
000576 A2A6           MOV      C,P26
000578 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 405
               ?C0187:
00057B A2A7           MOV      C,P27
00057D 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 406
               ?C0180:
000580 E4             CLR      A                ; A=R11
000581 AA             ERET     
                                                ; SOURCE LINE # 407
                                                ; SOURCE LINE # 408
               ?C0152:
                                                ; SOURCE LINE # 409
000582 7D32           MOV      WR6,WR4
000584 1B35           DEC      WR6,#02H
000586 682B           JE       ?C0191
000588 1B35           DEC      WR6,#02H
00058A 682C           JE       ?C0192
00058C 1B36           DEC      WR6,#04H
00058E 682D           JE       ?C0193
000590 2E34FFF8       ADD      WR6,#0FFF8H
000594 682C           JE       ?C0194
000596 2E34FFF0       ADD      WR6,#0FFF0H
00059A 682B           JE       ?C0195
00059C 2E34FFE0       ADD      WR6,#0FFE0H
0005A0 682A           JE       ?C0196
0005A2 2E34FFC0       ADD      WR6,#0FFC0H
0005A6 6829           JE       ?C0197
0005A8 2E34007F       ADD      WR6,#07FH
0005AC 7828           JNE      ?C0190
                                                ; SOURCE LINE # 411
               ?C0189:
0005AE A2B0           MOV      C,P30
0005B0 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 412
               ?C0191:
0005B3 A2B1           MOV      C,P31
0005B5 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 413
               ?C0192:
0005B8 A2B2           MOV      C,P32
0005BA 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 414
               ?C0193:
0005BD A2B3           MOV      C,P33
0005BF 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 415
               ?C0194:
0005C2 A2B4           MOV      C,P34
0005C4 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 416
               ?C0195:
0005C7 A2B5           MOV      C,P35
0005C9 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 417
               ?C0196:
0005CC A2B6           MOV      C,P36
0005CE 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 418
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 27  

               ?C0197:
0005D1 A2B7           MOV      C,P37
0005D3 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 419
               ?C0190:
0005D6 E4             CLR      A                ; A=R11
0005D7 AA             ERET     
                                                ; SOURCE LINE # 420
                                                ; SOURCE LINE # 421
               ?C0153:
                                                ; SOURCE LINE # 422
0005D8 7D32           MOV      WR6,WR4
0005DA 1B35           DEC      WR6,#02H
0005DC 682B           JE       ?C0201
0005DE 1B35           DEC      WR6,#02H
0005E0 682C           JE       ?C0202
0005E2 1B36           DEC      WR6,#04H
0005E4 682D           JE       ?C0203
0005E6 2E34FFF8       ADD      WR6,#0FFF8H
0005EA 682C           JE       ?C0204
0005EC 2E34FFF0       ADD      WR6,#0FFF0H
0005F0 682B           JE       ?C0205
0005F2 2E34FFE0       ADD      WR6,#0FFE0H
0005F6 682A           JE       ?C0206
0005F8 2E34FFC0       ADD      WR6,#0FFC0H
0005FC 6829           JE       ?C0207
0005FE 2E34007F       ADD      WR6,#07FH
000602 7828           JNE      ?C0200
                                                ; SOURCE LINE # 424
               ?C0199:
000604 A2C0           MOV      C,P40
000606 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 425
               ?C0201:
000609 A2C1           MOV      C,P41
00060B 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 426
               ?C0202:
00060E A2C2           MOV      C,P42
000610 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 427
               ?C0203:
000613 A2C3           MOV      C,P43
000615 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 428
               ?C0204:
000618 A2C4           MOV      C,P44
00061A 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 429
               ?C0205:
00061D A2C5           MOV      C,P45
00061F 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 430
               ?C0206:
000622 A2C6           MOV      C,P46
000624 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 431
               ?C0207:
000627 A2C7           MOV      C,P47
000629 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 432
               ?C0200:
00062C E4             CLR      A                ; A=R11
00062D AA             ERET     
                                                ; SOURCE LINE # 433
                                                ; SOURCE LINE # 434
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 28  

               ?C0154:
                                                ; SOURCE LINE # 435
00062E 7D32           MOV      WR6,WR4
000630 1B35           DEC      WR6,#02H
000632 681F           JE       ?C0211
000634 1B35           DEC      WR6,#02H
000636 6820           JE       ?C0212
000638 1B36           DEC      WR6,#04H
00063A 6821           JE       ?C0213
00063C 2E34FFF8       ADD      WR6,#0FFF8H
000640 6820           JE       ?C0214
000642 2E34FFF0       ADD      WR6,#0FFF0H
000646 681F           JE       ?C0215
000648 2E34001F       ADD      WR6,#01FH
00064C 781E           JNE      ?C0210
                                                ; SOURCE LINE # 437
               ?C0209:
00064E A2C8           MOV      C,P50
000650 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 438
               ?C0211:
000653 A2C9           MOV      C,P51
000655 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 439
               ?C0212:
000658 A2CA           MOV      C,P52
00065A 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 440
               ?C0213:
00065D A2CB           MOV      C,P53
00065F 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 441
               ?C0214:
000662 A2CC           MOV      C,P54
000664 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 442
               ?C0215:
000667 A2CD           MOV      C,P55
000669 020000      R  LJMP     ?C0339
                                                ; SOURCE LINE # 443
               ?C0210:
00066C E4             CLR      A                ; A=R11
00066D AA             ERET     
                                                ; SOURCE LINE # 444
                                                ; SOURCE LINE # 445
               ?C0155:
                                                ; SOURCE LINE # 446
00066E 7D32           MOV      WR6,WR4
000670 1B35           DEC      WR6,#02H
000672 682A           JE       ?C0219
000674 1B35           DEC      WR6,#02H
000676 682A           JE       ?C0220
000678 1B36           DEC      WR6,#04H
00067A 682A           JE       ?C0221
00067C 2E34FFF8       ADD      WR6,#0FFF8H
000680 6828           JE       ?C0222
000682 2E34FFF0       ADD      WR6,#0FFF0H
000686 6826           JE       ?C0223
000688 2E34FFE0       ADD      WR6,#0FFE0H
00068C 6824           JE       ?C0224
00068E 2E34FFC0       ADD      WR6,#0FFC0H
000692 6822           JE       ?C0225
000694 2E34007F       ADD      WR6,#07FH
000698 7820           JNE      ?C0218
                                                ; SOURCE LINE # 448
               ?C0217:
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 29  

00069A A2E8           MOV      C,P60
00069C 8066           SJMP     ?C0339
                                                ; SOURCE LINE # 449
               ?C0219:
00069E A2E9           MOV      C,P61
0006A0 8062           SJMP     ?C0339
                                                ; SOURCE LINE # 450
               ?C0220:
0006A2 A2EA           MOV      C,P62
0006A4 805E           SJMP     ?C0339
                                                ; SOURCE LINE # 451
               ?C0221:
0006A6 A2EB           MOV      C,P63
0006A8 805A           SJMP     ?C0339
                                                ; SOURCE LINE # 452
               ?C0222:
0006AA A2EC           MOV      C,P64
0006AC 8056           SJMP     ?C0339
                                                ; SOURCE LINE # 453
               ?C0223:
0006AE A2ED           MOV      C,P65
0006B0 8052           SJMP     ?C0339
                                                ; SOURCE LINE # 454
               ?C0224:
0006B2 A2EE           MOV      C,P66
0006B4 804E           SJMP     ?C0339
                                                ; SOURCE LINE # 455
               ?C0225:
0006B6 A2EF           MOV      C,P67
0006B8 804A           SJMP     ?C0339
                                                ; SOURCE LINE # 456
               ?C0218:
0006BA E4             CLR      A                ; A=R11
0006BB AA             ERET     
                                                ; SOURCE LINE # 457
                                                ; SOURCE LINE # 458
               ?C0156:
                                                ; SOURCE LINE # 459
0006BC 1B25           DEC      WR4,#02H
0006BE 682A           JE       ?C0229
0006C0 1B25           DEC      WR4,#02H
0006C2 682A           JE       ?C0230
0006C4 1B26           DEC      WR4,#04H
0006C6 682A           JE       ?C0231
0006C8 2E24FFF8       ADD      WR4,#0FFF8H
0006CC 6828           JE       ?C0232
0006CE 2E24FFF0       ADD      WR4,#0FFF0H
0006D2 6826           JE       ?C0233
0006D4 2E24FFE0       ADD      WR4,#0FFE0H
0006D8 6824           JE       ?C0234
0006DA 2E24FFC0       ADD      WR4,#0FFC0H
0006DE 6822           JE       ?C0235
0006E0 2E24007F       ADD      WR4,#07FH
0006E4 7821           JNE      ?C0228
                                                ; SOURCE LINE # 461
               ?C0227:
0006E6 A2F8           MOV      C,P70
0006E8 801A           SJMP     ?C0339
                                                ; SOURCE LINE # 462
               ?C0229:
0006EA A2F9           MOV      C,P71
0006EC 8016           SJMP     ?C0339
                                                ; SOURCE LINE # 463
               ?C0230:
0006EE A2FA           MOV      C,P72
0006F0 8012           SJMP     ?C0339
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 30  

                                                ; SOURCE LINE # 464
               ?C0231:
0006F2 A2FB           MOV      C,P73
0006F4 800E           SJMP     ?C0339
                                                ; SOURCE LINE # 465
               ?C0232:
0006F6 A2FC           MOV      C,P74
0006F8 800A           SJMP     ?C0339
                                                ; SOURCE LINE # 466
               ?C0233:
0006FA A2FD           MOV      C,P75
0006FC 8006           SJMP     ?C0339
                                                ; SOURCE LINE # 467
               ?C0234:
0006FE A2FE           MOV      C,P76
000700 8002           SJMP     ?C0339
                                                ; SOURCE LINE # 468
               ?C0235:
000702 A2FF           MOV      C,P77
               ?C0339:
000704 E4             CLR      A                ; A=R11
000705 33             RLC      A                ; A=R11
000706 AA             ERET     
                                                ; SOURCE LINE # 469
               ?C0228:
000707 E4             CLR      A                ; A=R11
000708 AA             ERET     
                                                ; SOURCE LINE # 470
                                                ; SOURCE LINE # 471
               ?C0149:
000709 E4             CLR      A                ; A=R11
                                                ; SOURCE LINE # 472
                                                ; SOURCE LINE # 473
00070A AA             ERET     
;       FUNCTION GPIO_Read_Bit? (END)

;       FUNCTION GPIO_Toggle_Bit? (BEGIN)
                                                ; SOURCE LINE # 482
;---- Variable 'GPIO_Pin' assigned to Register 'WR4' ----
;---- Variable 'GPIO_Port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 486
00070B 7D53           MOV      WR10,WR6
00070D BE540008       CMP      WR10,#08H
000711 5047           JNC      ?C0236
000713 7EA003         MOV      R10,#03H
000716 A4             MUL      AB
000717 900000      R  MOV      DPTR,#?C0255
00071A 73             JMP      @A+DPTR
               ?C0255:
00071B 020000      R  LJMP     ?C0237
00071E 020000      R  LJMP     ?C0239
000721 020000      R  LJMP     ?C0240
000724 020000      R  LJMP     ?C0241
000727 020000      R  LJMP     ?C0242
00072A 020000      R  LJMP     ?C0243
00072D 020000      R  LJMP     ?C0244
000730 020000      R  LJMP     ?C0245
                                                ; SOURCE LINE # 488
               ?C0237:
000733 7CB5           MOV      R11,R5           ; A=R11
000735 6280           XRL      P0,A             ; A=R11
000737 AA             ERET     
                                                ; SOURCE LINE # 489
               ?C0239:
000738 7CB5           MOV      R11,R5           ; A=R11
00073A 6290           XRL      P1,A             ; A=R11
C251 COMPILER V5.60.0,  CNU_PIE_GPIO                                                       24/08/26  10:23:43  PAGE 31  

00073C AA             ERET     
                                                ; SOURCE LINE # 490
               ?C0240:
00073D 7CB5           MOV      R11,R5           ; A=R11
00073F 62A0           XRL      P2,A             ; A=R11
000741 AA             ERET     
                                                ; SOURCE LINE # 491
               ?C0241:
000742 7CB5           MOV      R11,R5           ; A=R11
000744 62B0           XRL      P3,A             ; A=R11
000746 AA             ERET     
                                                ; SOURCE LINE # 492
               ?C0242:
000747 7CB5           MOV      R11,R5           ; A=R11
000749 62C0           XRL      P4,A             ; A=R11
00074B AA             ERET     
                                                ; SOURCE LINE # 493
               ?C0243:
00074C 7CB5           MOV      R11,R5           ; A=R11
00074E 62C8           XRL      P5,A             ; A=R11
000750 AA             ERET     
                                                ; SOURCE LINE # 494
               ?C0244:
000751 7CB5           MOV      R11,R5           ; A=R11
000753 62E8           XRL      P6,A             ; A=R11
000755 AA             ERET     
                                                ; SOURCE LINE # 495
               ?C0245:
000756 7CB5           MOV      R11,R5           ; A=R11
000758 62F8           XRL      P7,A             ; A=R11
                                                ; SOURCE LINE # 496
                                                ; SOURCE LINE # 497
                                                ; SOURCE LINE # 498
               ?C0236:
                                                ; SOURCE LINE # 499
00075A AA             ERET     
;       FUNCTION GPIO_Toggle_Bit? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      1883     ------
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

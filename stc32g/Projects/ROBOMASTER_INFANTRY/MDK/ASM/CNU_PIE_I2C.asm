C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_I2C
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_I2C.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_I2C.c XSMALL ROM(HUGE) BROWSE I
                    -NCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR
                    -(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_I2C.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_I2C.obj) 

stmt  level    source

    1          /********************************************************************************************************
             -*************
    2           *     COPYRIGHT NOTICE
    3           *     Copyright (c) 2023,CNU_W.PIE
    4           *     All rights reserved.
    5           *
    6           *     ³ý×¢Ã÷³ö´¦Íâ£¬ÒÔÏÂËùÓÐÄÚÈÝ°æÈ¨¾ùÊôÅÖÅÖ¸öÈËËùÓÐ£¬Î´¾­ÔÊÐí£¬²»µÃÓÃÓÚÉÌÒµÓÃÍ¾£¬
    7           *     ÐÞ¸ÄÄÚÈÝÊ±±ØÐë±£ÁôPPµÄ°æÈ¨ÉùÃ÷¡£
    8           *     Except where indicated, the copyright of all the contents below is owned by PP 
    9           *     and can not be used for commercial purposes without permission. 
   10           *     The copyright notice of PP must be preserved when modifying the content.
   11           *
   12           * @file       CNU_PIE_I2C.c
   13           * @brief      I2C
   14           * @author     ÅÖÅÖ
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19          #include "CNU_PIE_I2C.h"
   20          #include "CNU_PIE_GPIO.h"
   21          
   22           /*******************************************************************************************************
             -*******************
   23           * @brief  I2CÖ÷»úÒý½Å³õÊ¼»¯
   24           * @exampleCode
   25           *      I2C_Init_Master(IIC_1, 400*1000, 0 , 1); //³õÊ¼»¯I2C1 ×ÜÏßËÙÂÊ400k ½ûÖ¹×ÜÏß×Ô¶¯·¢ËÍ ¿ªÆôI2C×ÜÏß
   26           * @endcode
   27           * @param[in]  I2C_enum       IICÍ¨µÀÃ¶¾Ù
   28           * @param[in]  I2C_BUS_Rate   IIC×ÜÏßËÙÂÊ              
   29           * @param[in]  I2C_WDTA_EN    IIC×Ô¶¯·¢ËÍÎ»
   30           * @param[in]  I2C_Enable     IICÊ¹ÄÜÎ»
   31          *********************************************************************************************************
             -******************/
   32          void  I2C_Init_Master(IIC_ENUM I2C_enum , uint32_t I2C_BUS_Rate , uint8_t I2C_WDTA_EN , uint8_t I2C_Enable
             -)
   33          {
   34   1        uint8_t Bus_Speed;
   35   1        switch(I2C_enum)
   36   1          {
   37   2          case IIC_1:
   38   2              P_SW2 |= (0x00<<4); //SCL:P1.5  SDA:P1.4
   39   2              break;
   40   2          case IIC_2:
   41   2              P_SW2 |= (0x01<<4); //SCL:P2.5  SDA:P2.4
   42   2              break;
   43   2          case IIC_3:
   44   2              P_SW2 |= (0x02<<4); //SCL:P7.7  SDA:P7.6
   45   2              break;
   46   2          case IIC_4:
   47   2              P_SW2 |= (0x03<<4); //SCL:P3.2  SDA:P3.3
   48   2              break;
   49   2          }
   50   1      
   51   1        I2CCFG |=  0x40;  //ÉèÖÃµ±Ç°Éè±¸ÎªI2CÖ÷»ú
   52   1        I2CMSST = 0x00;   //Çå³ýI2CÖ÷»ú×´Ì¬¼Ä´æÆ÷
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 2   

   53   1        /* I2C_BUS_Rate=Fosc/2/(Bus_Speed*2+4) */
   54   1        Bus_Speed = (uint8_t)(FOSC/4*I2C_BUS_Rate)-4;
   55   1        I2CCFG = ((I2CCFG & ~0x3f) | (Bus_Speed & 0x3f));//ÉèÖÃ×ÜÏßËÙ¶È
   56   1        if(I2C_WDTA_EN) I2CMSAUX |= 0x01;//Ê¹ÄÜ×Ô¶¯·¢ËÍ
   57   1        else I2CMSAUX &= ~0x01;          //½ûÖ¹×Ô¶¯·¢ËÍ
   58   1        (I2C_Enable==0?(I2CCFG &= ~0x80):(I2CCFG |= 0x80));       
   59   1      }
   60           /*******************************************************************************************************
             -*******************
   61           * @brief  I2C´Ó»úÒý½Å³õÊ¼»¯
   62           * @exampleCode
   63           *      I2C_Init_Slave(IIC_1, 0xab , 1 , 1 , 1); //³õÊ¼»¯I2C1Îª´Ó»ú µØÖ·0xab Ö»½ÓÊÜÏàÆ¥ÅäµØÖ· ¿ªÆôI2C×ÜÏß
   64           * @endcode
   65           * @param[in]  I2C_enum        IICÍ¨µÀÃ¶¾Ù
   66           * @param[in]  I2C_Slave_Add   IIC´Ó»úµØÖ·              
   67           * @param[in]  I2C_MATCH_EN    IIC´Ó»úµØÖ·±È½Ï
   68           * @param[in]  I2C_Enable      IICÊ¹ÄÜÎ»
   69          *********************************************************************************************************
             -******************/
   70          void  I2C_Init_Slave(IIC_ENUM I2C_enum , uint8_t I2C_Slave_Add , uint8_t I2C_MATCH_EN , uint8_t I2C_Enable
             -)
   71          {
   72   1        switch(I2C_enum)
   73   1          {
   74   2          case IIC_1:
   75   2              P_SW2 |= (0x00<<4); //SCL:P1.5  SDA:P1.4
   76   2              break;
   77   2          case IIC_2:
   78   2              P_SW2 |= (0x01<<4); //SCL:P2.5  SDA:P2.4
   79   2              break;
   80   2          case IIC_3:
   81   2              P_SW2 |= (0x02<<4); //SCL:P7.7  SDA:P7.6
   82   2              break;
   83   2          case IIC_4:
   84   2              P_SW2 |= (0x03<<4); //SCL:P3.2  SDA:P3.3
   85   2              break;
   86   2          }
   87   1      
   88   1        I2CCFG &= ~0x40;  //ÉèÖÃµ±Ç°Éè±¸ÎªI2CÖ÷»ú
   89   1        I2CSLST = 0x00;   //Çå³ýI2C´Ó»ú×´Ì¬¼Ä´æÆ÷
   90   1          
   91   1      //  I2CSLST = 0X00;   //½ÓÊÕÖÐ¶Ï
   92   1      //  I2CSLCR = 0x78;   //½ÓÊÜÖÐ¶Ï
   93   1          
   94   1        I2CSLADR = ((I2CSLADR & 0x01) | (I2C_Slave_Add << 1));//ÉèÖÃµ±Ç°Éè±¸µØÖ·
   95   1        if(I2C_MATCH_EN) I2CSLADR &= ~0x01;//Ê¹ÄÜ´Ó»úµØÖ·±È½Ï¹¦ÄÜ£¬Ö»½ÓÊÜÏàÆ¥ÅäµØÖ·
   96   1        else I2CSLADR |= 0x01;             //½ûÖ¹´Ó»úµØÖ·±È½Ï¹¦ÄÜ£¬½ÓÊÜËùÓÐÉè±¸µØÖ·
   97   1        (I2C_Enable==0?(I2CCFG &= ~0x80):(I2CCFG |= 0x80));       
   98   1      } 
   99           /*******************************************************************************************************
             -*******************
  100           * @brief  »ñÈ¡Ö÷»úÃ¦Âµ×´Ì¬.
  101           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  102          *********************************************************************************************************
             -******************/
  103          uint8_t Get_MSBusy_Status(void)
  104          {
  105   1        return (I2CMSST & 0x80);
  106   1      }
  107           /*******************************************************************************************************
             -*******************
  108           * @brief  µÈ´ýÖ÷»úÄ£Ê½I2C¿ØÖÆÆ÷Ö´ÐÐÍê³ÉI2CMSCR.
  109           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  110          *********************************************************************************************************
             -******************/
  111          void Wait()
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 3   

  112          {
  113   1        while (!(I2CMSST & 0x40));
  114   1        I2CMSST &= ~0x40;
  115   1      }
  116           /*******************************************************************************************************
             -*******************
  117           * @brief  I2C×ÜÏßÆðÊ¼º¯Êý.
  118           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  119          *********************************************************************************************************
             -******************/
  120          void Start()
  121          {
  122   1        I2CMSCR = 0x01;                         //·¢ËÍSTARTÃüÁî
  123   1        Wait();
  124   1      }
  125           /*******************************************************************************************************
             -*******************
  126           * @brief  I2C·¢ËÍÒ»¸ö×Ö½ÚÊý¾Ýº¯Êý.
  127           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  128          *********************************************************************************************************
             -******************/
  129          void SendData(char dat)
  130          {
  131   1        I2CTXD = dat;                           //Ð´Êý¾Ýµ½Êý¾Ý»º³åÇø
  132   1        I2CMSCR = 0x02;                         //·¢ËÍSENDÃüÁî
  133   1        Wait();
  134   1      }
  135           /*******************************************************************************************************
             -*******************
  136           * @brief  I2C»ñÈ¡ACKº¯Êý.
  137           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  138          *********************************************************************************************************
             -******************/
  139          void RecvACK()
  140          {
  141   1        I2CMSCR = 0x03;                         //·¢ËÍ¶ÁACKÃüÁî
  142   1        Wait();
  143   1      }
  144           /*******************************************************************************************************
             -*******************
  145           * @brief  I2C¶ÁÈ¡Ò»¸ö×Ö½ÚÊý¾Ýº¯Êý.
  146           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  147          *********************************************************************************************************
             -******************/
  148          char RecvData()
  149          {
  150   1        I2CMSCR = 0x04;                         //·¢ËÍRECVÃüÁî
  151   1        Wait();
  152   1        return I2CRXD;
  153   1      }
  154           /*******************************************************************************************************
             -*******************
  155           * @brief  I2C·¢ËÍACKº¯Êý.
  156           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  157          *********************************************************************************************************
             -******************/
  158          void SendACK()
  159          {
  160   1        I2CMSST = 0x00;                         //ÉèÖÃACKÐÅºÅ
  161   1        I2CMSCR = 0x05;                         //·¢ËÍACKÃüÁî
  162   1        Wait();
  163   1      }
  164           /*******************************************************************************************************
             -*******************
  165           * @brief  I2C·¢ËÍNAKº¯Êý.
  166           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 4   

  167          *********************************************************************************************************
             -******************/
  168          void SendNAK()
  169          {
  170   1        I2CMSST = 0x01;                         //ÉèÖÃNAKÐÅºÅ
  171   1        I2CMSCR = 0x05;                         //·¢ËÍACKÃüÁî
  172   1        Wait();
  173   1      }
  174           /*******************************************************************************************************
             -*******************
  175           * @brief  I2C×ÜÏßÍ£Ö¹º¯Êý.
  176           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  177          *********************************************************************************************************
             -******************/
  178          void Stop()
  179          {
  180   1        I2CMSCR = 0x06;                         //·¢ËÍSTOPÃüÁî
  181   1        Wait();
  182   1      }
  183           /*******************************************************************************************************
             -*******************
  184           * @brief  I2C·¢ËÍÒ»¸ö×Ö½ÚÊý¾Ýº¯Êý.
  185           * @brief  ÄÚ²¿µ÷ÓÃ£¬ÎÞÐè¹ØÐÄ
  186          *********************************************************************************************************
             -******************/
  187          void SendCmdData(uint8_t cmd, uint8_t dat)
  188          {
  189   1        I2CTXD = dat;                           //Ð´Êý¾Ýµ½Êý¾Ý»º³åÇø
  190   1        I2CMSCR = cmd;                          //ÉèÖÃÃüÁî
  191   1        Wait();
  192   1      }
  193           /*******************************************************************************************************
             -*******************
  194           * @brief  I2CÐ´ÈëÊý¾Ýº¯Êý
  195           * @exampleCode
  196            uint8_t cmd[2];
  197            cmd[0]=0x00;
  198            cmd[1]=WrCmd;
  199            I2C_WriteNbyte(0x7a,cmd[0],&cmd[1],1); //Ïò0x7aÎªµØÖ·µÄÉè±¸ µÄ0x00µØÖ·µÄ¼Ä´æÆ÷ Ð´Èë WrcmdÊý¾Ý ³¤¶È1×Ö½Ú
  200           * @endcode
  201           * @param[in]  addr    Ö¸¶¨µØÖ· 
  202           * @param[in]  reg     ¼Ä´æÆ÷µØÖ·              
  203           * @param[in]  *p      Ð´ÈëÊý¾Ý´æ´¢Î»ÖÃ
  204           * @param[in]  number  Ð´ÈëÊý¾Ý¸öÊý
  205          *********************************************************************************************************
             -******************/
  206          void I2C_WriteNbyte(uint8_t addr, uint8_t reg , uint8_t *p, uint8_t number) reentrant /*  WordAddress,Fir
             -st Data Address,Byte lenth   */
  207          {
  208   1        Start();                                //·¢ËÍÆðÊ¼ÃüÁî
  209   1        SendData(addr);                         //·¢ËÍÉè±¸µØÖ·+Ð´ÃüÁî
  210   1        RecvACK();
  211   1        SendData(reg);                         //·¢ËÍ´æ´¢µØÖ·
  212   1        RecvACK();
  213   1        do
  214   1        {
  215   2          SendData(*p++);
  216   2          RecvACK();
  217   2        }
  218   1        while(--number);
  219   1        Stop();                                 //·¢ËÍÍ£Ö¹ÃüÁî
  220   1      }
  221           /*******************************************************************************************************
             -*******************
  222           * @brief  I2C¶ÁÈ¡Êý¾Ýº¯Êý
  223           * @exampleCode
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 5   

  224            uint8_t reg,uint8_t *pbuf
  225            I2C_ReadNbyte(0x7a,reg,pbuf,1); //Ïò0x7aÎªµØÖ·µÄÉè±¸ µÄregµØÖ·µÄ¼Ä´æÆ÷ ¶ÁÈ¡Êý¾Ý ³¤¶È1×Ö½Ú ²¢´æÈëpbufµÄµ
             -ØÖ·ÄÚ
  226           * @endcode
  227           * @param[in]  addr    Ö¸¶¨µØÖ· 
  228           * @param[in]  reg     ¼Ä´æÆ÷µØÖ·              
  229           * @param[in]  *p      Ð´ÈëÊý¾Ý´æ´¢Î»ÖÃ
  230           * @param[in]  number  ¶ÁÈ¡Êý¾Ý¸öÊý
  231          *********************************************************************************************************
             -******************/
  232          void I2C_ReadNbyte(uint8_t addr, uint8_t reg , uint8_t *p, uint8_t number)   
  233          {
  234   1        Start();                                //·¢ËÍÆðÊ¼ÃüÁî
  235   1        SendData(addr);                         //·¢ËÍÉè±¸µØÖ·+Ð´ÃüÁî
  236   1        RecvACK();
  237   1        SendData(reg);                         //·¢ËÍ´æ´¢µØÖ·
  238   1        RecvACK();
  239   1        Start();                                //·¢ËÍÆðÊ¼ÃüÁî
  240   1        SendData((uint8_t)(addr+1));                         //·¢ËÍÉè±¸µØÖ·+¶ÁÃüÁî
  241   1        RecvACK();
  242   1        do
  243   1        {
  244   2          *p = RecvData();
  245   2          p++;
  246   2          if(number != 1) SendACK();          //send ACK
  247   2        }
  248   1        while(--number);
  249   1        SendNAK();                              //send no ACK 
  250   1        Stop();                               //·¢ËÍÍ£Ö¹ÃüÁî 
  251   1      }
  252           /*******************************************************************************************************
             -*******************
  253           * @brief  I2CÒý½ÅÇÐ»»º¯Êý
  254           * @exampleCode
  255             I2C_Change_Pin(IIC_3);
  256           * @endcode
  257           * @param[in]  I2C_enum    ÐèÒªÇÐ»»µ½ÄÄ×éIICÒý½Å 
  258          *********************************************************************************************************
             -******************/
  259          void I2C_Change_Pin(IIC_ENUM I2C_enum)
  260          {
  261   1          P_SW2 |= 0x80;//È·¶¨Ê¹ÄÜ·ÃÎÊXFR
  262   1        
  263   1          P_SW2 &= ~(0x03<<4);  //Çå³ýÒý½ÅÇÐ»»Î»
  264   1          switch(I2C_enum)  
  265   1          {
  266   2          case IIC_1:
  267   2              P_SW2 |= (0x00<<4); //SCL:P1.5  SDA:P1.4
  268   2              break;
  269   2          case IIC_2:
  270   2              P_SW2 |= (0x01<<4); //SCL:P2.5  SDA:P2.4
  271   2              break;
  272   2          case IIC_3:
  273   2              P_SW2 |= (0x02<<4); //SCL:P7.7  SDA:P7.6 STC8H 48½ÅºËÐÄ°åÃ»ÓÐ¸Ã×éÒý½Å¡£
  274   2              break;
  275   2          case IIC_4:
  276   2              P_SW2 |= (0x03<<4); //SCL:P3.2  SDA:P3.3
  277   2              break;
  278   2          }
  279   1        
  280   1        P_SW2 |= 0x80;//È·¶¨Ê¹ÄÜ·ÃÎÊXFR
  281   1      }
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 6   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION I2C_Init_Master? (BEGIN)
                                                ; SOURCE LINE # 32
000000 7C95           MOV      R9,R5
;---- Variable 'I2C_Enable' assigned to Register 'R9' ----
000002 7C8B           MOV      R8,R11           ; A=R11
;---- Variable 'I2C_WDTA_EN' assigned to Register 'R8' ----
000004 7F70           MOV      DR28,DR0
;---- Variable 'I2C_BUS_Rate' assigned to Register 'DR28' ----
000006 7D53           MOV      WR10,WR6
;---- Variable 'I2C_enum' assigned to Register 'WR10' ----
                                                ; SOURCE LINE # 33
                                                ; SOURCE LINE # 35
000008 1B54           DEC      WR10,#01H
00000A 6814           JE       ?C0003
00000C 1B54           DEC      WR10,#01H
00000E 6815           JE       ?C0004
000010 1B54           DEC      WR10,#01H
000012 6816           JE       ?C0005
000014 2E540003       ADD      WR10,#03H
000018 7813           JNE      ?C0001
                                                ; SOURCE LINE # 37
               ?C0002:
                                                ; SOURCE LINE # 38
00001A E5BA           MOV      A,P_SW2          ; A=R11
00001C F5BA           MOV      P_SW2,A          ; A=R11
                                                ; SOURCE LINE # 39
00001E 800D           SJMP     ?C0001
                                                ; SOURCE LINE # 40
               ?C0003:
                                                ; SOURCE LINE # 41
000020 43BA10         ORL      P_SW2,#010H
                                                ; SOURCE LINE # 42
000023 8008           SJMP     ?C0001
                                                ; SOURCE LINE # 43
               ?C0004:
                                                ; SOURCE LINE # 44
000025 43BA20         ORL      P_SW2,#020H
                                                ; SOURCE LINE # 45
000028 8003           SJMP     ?C0001
                                                ; SOURCE LINE # 46
               ?C0005:
                                                ; SOURCE LINE # 47
00002A 43BA30         ORL      P_SW2,#030H
                                                ; SOURCE LINE # 48
                                                ; SOURCE LINE # 49
               ?C0001:
                                                ; SOURCE LINE # 51
00002D 7ED4FE80       MOV      WR26,#0FE80H
000031 7EC4007E       MOV      WR24,#07EH
000035 7E6BB0         MOV      R11,@DR24        ; A=R11
000038 4440           ORL      A,#040H          ; A=R11
00003A 7A6BB0         MOV      @DR24,R11        ; A=R11
                                                ; SOURCE LINE # 52
00003D E4             CLR      A                ; A=R11
00003E 7E34FE82       MOV      WR6,#0FE82H
000042 7E24007E       MOV      WR4,#07EH
000046 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 54
000049 7E149000       MOV      WR2,#09000H
00004D 7E04007E       MOV      WR0,#07EH
000051 7F17           MOV      DR4,DR28
000053 9A000000    E  ECALL    ?C?LMUL?
000057 0A37           MOVZ     WR6,R7
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 7   

000059 1B36           DEC      WR6,#04H
00005B 7C67           MOV      R6,R7
;---- Variable 'Bus_Speed' assigned to Register 'R6' ----
                                                ; SOURCE LINE # 55
00005D 7E6B70         MOV      R7,@DR24
000060 5E70C0         ANL      R7,#0C0H
000063 7CB6           MOV      R11,R6           ; A=R11
000065 543F           ANL      A,#03FH          ; A=R11
000067 4C7B           ORL      R7,R11           ; A=R11
000069 7A6B70         MOV      @DR24,R7
                                                ; SOURCE LINE # 56
00006C 4C88           ORL      R8,R8
00006E 680F           JE       ?C0006
000070 7E34FE88       MOV      WR6,#0FE88H
000074 7E24007E       MOV      WR4,#07EH
000078 7E1BB0         MOV      R11,@DR4         ; A=R11
00007B 4401           ORL      A,#01H           ; A=R11
00007D 800D           SJMP     ?C0039
               ?C0006:
                                                ; SOURCE LINE # 57
00007F 7E34FE88       MOV      WR6,#0FE88H
000083 7E24007E       MOV      WR4,#07EH
000087 7E1BB0         MOV      R11,@DR4         ; A=R11
00008A 54FE           ANL      A,#0FEH          ; A=R11
               ?C0039:
00008C 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 58
00008F 4C99           ORL      R9,R9
000091 7807           JNE      ?C0008
000093 7E6BB0         MOV      R11,@DR24        ; A=R11
000096 547F           ANL      A,#07FH          ; A=R11
000098 8005           SJMP     ?C0040
               ?C0008:
00009A 7E6BB0         MOV      R11,@DR24        ; A=R11
00009D 4480           ORL      A,#080H          ; A=R11
               ?C0040:
00009F 7A6BB0         MOV      @DR24,R11        ; A=R11
                                                ; SOURCE LINE # 59
0000A2 AA             ERET     
;       FUNCTION I2C_Init_Master? (END)

;       FUNCTION I2C_Init_Slave? (BEGIN)
                                                ; SOURCE LINE # 70
0000A3 7CA4           MOV      R10,R4
;---- Variable 'I2C_Enable' assigned to Register 'R10' ----
0000A5 7C15           MOV      R1,R5
;---- Variable 'I2C_MATCH_EN' assigned to Register 'R1' ----
0000A7 7C0B           MOV      R0,R11           ; A=R11
;---- Variable 'I2C_Slave_Add' assigned to Register 'R0' ----
0000A9 7D13           MOV      WR2,WR6
;---- Variable 'I2C_enum' assigned to Register 'WR2' ----
                                                ; SOURCE LINE # 72
0000AB 1B14           DEC      WR2,#01H
0000AD 6814           JE       ?C0012
0000AF 1B14           DEC      WR2,#01H
0000B1 6815           JE       ?C0013
0000B3 1B14           DEC      WR2,#01H
0000B5 6816           JE       ?C0014
0000B7 2E140003       ADD      WR2,#03H
0000BB 7813           JNE      ?C0010
                                                ; SOURCE LINE # 74
               ?C0011:
                                                ; SOURCE LINE # 75
0000BD E5BA           MOV      A,P_SW2          ; A=R11
0000BF F5BA           MOV      P_SW2,A          ; A=R11
                                                ; SOURCE LINE # 76
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 8   

0000C1 800D           SJMP     ?C0010
                                                ; SOURCE LINE # 77
               ?C0012:
                                                ; SOURCE LINE # 78
0000C3 43BA10         ORL      P_SW2,#010H
                                                ; SOURCE LINE # 79
0000C6 8008           SJMP     ?C0010
                                                ; SOURCE LINE # 80
               ?C0013:
                                                ; SOURCE LINE # 81
0000C8 43BA20         ORL      P_SW2,#020H
                                                ; SOURCE LINE # 82
0000CB 8003           SJMP     ?C0010
                                                ; SOURCE LINE # 83
               ?C0014:
                                                ; SOURCE LINE # 84
0000CD 43BA30         ORL      P_SW2,#030H
                                                ; SOURCE LINE # 85
                                                ; SOURCE LINE # 86
               ?C0010:
                                                ; SOURCE LINE # 88
0000D0 7E34FE80       MOV      WR6,#0FE80H
0000D4 7E24007E       MOV      WR4,#07EH
0000D8 7E1BB0         MOV      R11,@DR4         ; A=R11
0000DB 54BF           ANL      A,#0BFH          ; A=R11
0000DD 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 89
0000E0 E4             CLR      A                ; A=R11
0000E1 7EF4FE84       MOV      WR30,#0FE84H
0000E5 7EE4007E       MOV      WR28,#07EH
0000E9 7A7BB0         MOV      @DR28,R11        ; A=R11
                                                ; SOURCE LINE # 94
0000EC 7C30           MOV      R3,R0
0000EE 3E30           SLL      R3
0000F0 7EF4FE85       MOV      WR30,#0FE85H
0000F4 7E7B00         MOV      R0,@DR28
0000F7 5E0001         ANL      R0,#01H
0000FA 4C03           ORL      R0,R3
0000FC 7A7B00         MOV      @DR28,R0
                                                ; SOURCE LINE # 95
0000FF 4C11           ORL      R1,R1
000101 6807           JE       ?C0015
000103 7E7BB0         MOV      R11,@DR28        ; A=R11
000106 54FE           ANL      A,#0FEH          ; A=R11
000108 8005           SJMP     ?C0041
               ?C0015:
                                                ; SOURCE LINE # 96
00010A 7E7BB0         MOV      R11,@DR28        ; A=R11
00010D 4401           ORL      A,#01H           ; A=R11
               ?C0041:
00010F 7A7BB0         MOV      @DR28,R11        ; A=R11
                                                ; SOURCE LINE # 97
000112 4CAA           ORL      R10,R10
000114 7807           JNE      ?C0017
000116 7E1BB0         MOV      R11,@DR4         ; A=R11
000119 547F           ANL      A,#07FH          ; A=R11
00011B 8005           SJMP     ?C0042
               ?C0017:
00011D 7E1BB0         MOV      R11,@DR4         ; A=R11
000120 4480           ORL      A,#080H          ; A=R11
               ?C0042:
000122 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 98
000125 AA             ERET     
;       FUNCTION I2C_Init_Slave? (END)

C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 9   

;       FUNCTION Get_MSBusy_Status? (BEGIN)
                                                ; SOURCE LINE # 103
                                                ; SOURCE LINE # 105
000126 7E34FE82       MOV      WR6,#0FE82H
00012A 7E24007E       MOV      WR4,#07EH
00012E 7E1BB0         MOV      R11,@DR4         ; A=R11
000131 5480           ANL      A,#080H          ; A=R11
                                                ; SOURCE LINE # 106
000133 AA             ERET     
;       FUNCTION Get_MSBusy_Status? (END)

;       FUNCTION Wait? (BEGIN)
                                                ; SOURCE LINE # 111
                                                ; SOURCE LINE # 113
               ?C0020:
000134 7E34FE82       MOV      WR6,#0FE82H
000138 7E24007E       MOV      WR4,#07EH
00013C 7E1BB0         MOV      R11,@DR4         ; A=R11
00013F 30E6F2         JNB      ACC.6,?C0020
                                                ; SOURCE LINE # 114
000142 7E1BB0         MOV      R11,@DR4         ; A=R11
000145 54BF           ANL      A,#0BFH          ; A=R11
000147 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 115
00014A AA             ERET     
;       FUNCTION Wait? (END)

;       FUNCTION Start? (BEGIN)
                                                ; SOURCE LINE # 120
                                                ; SOURCE LINE # 122
00014B 7401           MOV      A,#01H           ; A=R11
00014D 7E34FE81       MOV      WR6,#0FE81H
000151 7E24007E       MOV      WR4,#07EH
000155 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 123
000158 8A000000    R  EJMP     Wait?
;       FUNCTION Start? (END)

;       FUNCTION SendData? (BEGIN)
                                                ; SOURCE LINE # 129
;---- Variable 'dat' assigned to Register 'R11' ----
                                                ; SOURCE LINE # 131
00015C 7E34FE86       MOV      WR6,#0FE86H
000160 7E24007E       MOV      WR4,#07EH
000164 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 132
000167 7402           MOV      A,#02H           ; A=R11
000169 7E34FE81       MOV      WR6,#0FE81H
00016D 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 133
000170 8A000000    R  EJMP     Wait?
;       FUNCTION SendData? (END)

;       FUNCTION RecvACK? (BEGIN)
                                                ; SOURCE LINE # 139
                                                ; SOURCE LINE # 141
000174 7403           MOV      A,#03H           ; A=R11
000176 7E34FE81       MOV      WR6,#0FE81H
00017A 7E24007E       MOV      WR4,#07EH
00017E 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 142
000181 8A000000    R  EJMP     Wait?
;       FUNCTION RecvACK? (END)

;       FUNCTION RecvData? (BEGIN)
                                                ; SOURCE LINE # 148
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 10  

                                                ; SOURCE LINE # 150
000185 7404           MOV      A,#04H           ; A=R11
000187 7E34FE81       MOV      WR6,#0FE81H
00018B 7E24007E       MOV      WR4,#07EH
00018F 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 151
000192 9A000000    R  ECALL    Wait?
                                                ; SOURCE LINE # 152
000196 7E34FE87       MOV      WR6,#0FE87H
00019A 7E24007E       MOV      WR4,#07EH
00019E 7E1BB0         MOV      R11,@DR4         ; A=R11
                                                ; SOURCE LINE # 153
0001A1 AA             ERET     
;       FUNCTION RecvData? (END)

;       FUNCTION SendACK? (BEGIN)
                                                ; SOURCE LINE # 158
                                                ; SOURCE LINE # 160
0001A2 E4             CLR      A                ; A=R11
0001A3 7E34FE82       MOV      WR6,#0FE82H
0001A7 7E24007E       MOV      WR4,#07EH
0001AB 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 161
0001AE 7405           MOV      A,#05H           ; A=R11
0001B0 7E34FE81       MOV      WR6,#0FE81H
0001B4 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 162
0001B7 8A000000    R  EJMP     Wait?
;       FUNCTION SendACK? (END)

;       FUNCTION SendNAK? (BEGIN)
                                                ; SOURCE LINE # 168
                                                ; SOURCE LINE # 170
0001BB 7401           MOV      A,#01H           ; A=R11
0001BD 7E34FE82       MOV      WR6,#0FE82H
0001C1 7E24007E       MOV      WR4,#07EH
0001C5 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 171
0001C8 7405           MOV      A,#05H           ; A=R11
0001CA 7E34FE81       MOV      WR6,#0FE81H
0001CE 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 172
0001D1 8A000000    R  EJMP     Wait?
;       FUNCTION SendNAK? (END)

;       FUNCTION Stop? (BEGIN)
                                                ; SOURCE LINE # 178
                                                ; SOURCE LINE # 180
0001D5 7406           MOV      A,#06H           ; A=R11
0001D7 7E34FE81       MOV      WR6,#0FE81H
0001DB 7E24007E       MOV      WR4,#07EH
0001DF 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 181
0001E2 8A000000    R  EJMP     Wait?
;       FUNCTION Stop? (END)

;       FUNCTION SendCmdData? (BEGIN)
                                                ; SOURCE LINE # 187
0001E6 7CA7           MOV      R10,R7
;---- Variable 'dat' assigned to Register 'R10' ----
;---- Variable 'cmd' assigned to Register 'R11' ----
                                                ; SOURCE LINE # 189
0001E8 7E34FE86       MOV      WR6,#0FE86H
0001EC 7E24007E       MOV      WR4,#07EH
0001F0 7A1BA0         MOV      @DR4,R10
                                                ; SOURCE LINE # 190
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 11  

0001F3 7E34FE81       MOV      WR6,#0FE81H
0001F7 7A1BB0         MOV      @DR4,R11         ; A=R11
                                                ; SOURCE LINE # 191
0001FA 8A000000    R  EJMP     Wait?
;       FUNCTION SendCmdData? (END)

;       FUNCTION I2C_WriteNbyte?? (BEGIN)
                                                ; SOURCE LINE # 206
0001FE CA3B           PUSH     DR12
000200 CA68           PUSH     R6
000202 7F30           MOV      DR12,DR0
;---- Variable 'p' assigned to Register 'DR12' ----
000204 CA78           PUSH     R7
000206 CAB8           PUSH     R11              ; A=R11
                                                ; SOURCE LINE # 208
000208 9A000000    R  ECALL    Start?
                                                ; SOURCE LINE # 209
00020C 7EFBB0         MOV      R11,@DR60        ; addr
00020F 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 210
000213 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 211
000217 29BFFFFF       MOV      R11,@DR60-0x1    ; reg
00021B 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 212
00021F 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 213
               ?C0025:
                                                ; SOURCE LINE # 215
000223 7E3BB0         MOV      R11,@DR12        ; A=R11
000226 0B74           INC      WR14,#01H
000228 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 216
00022C 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 217
000230 29BFFFFE       MOV      R11,@DR60-0x2    ; number
000234 14             DEC      A                ; A=R11
000235 39BFFFFE       MOV      @DR60-0x2,R11    ; number
000239 78E8           JNE      ?C0025
                                                ; SOURCE LINE # 219
00023B 9A000000    R  ECALL    Stop?
                                                ; SOURCE LINE # 220
00023F 9EF80003       SUB      DR60,#03H
000243 DA3B           POP      DR12
000245 AA             ERET     
;       FUNCTION I2C_WriteNbyte?? (END)

;       FUNCTION I2C_ReadNbyte? (BEGIN)
                                                ; SOURCE LINE # 232
000246 CA3B           PUSH     DR12
000248 7A630000    R  MOV      number,R6
00024C 7F30           MOV      DR12,DR0
;---- Variable 'p' assigned to Register 'DR12' ----
00024E 7A730000    R  MOV      reg,R7
000252 7AB30000    R  MOV      addr,R11         ; A=R11
                                                ; SOURCE LINE # 234
000256 9A000000    R  ECALL    Start?
                                                ; SOURCE LINE # 235
00025A 7EB30000    R  MOV      R11,addr         ; A=R11
00025E 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 236
000262 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 237
000266 7EB30000    R  MOV      R11,reg          ; A=R11
00026A 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 238
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 12  

00026E 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 239
000272 9A000000    R  ECALL    Start?
                                                ; SOURCE LINE # 240
000276 7E730000    R  MOV      R7,addr
00027A 0A57           MOVZ     WR10,R7
00027C 0B54           INC      WR10,#01H
00027E 9A000000    R  ECALL    SendData?
                                                ; SOURCE LINE # 241
000282 9A000000    R  ECALL    RecvACK?
                                                ; SOURCE LINE # 242
               ?C0029:
                                                ; SOURCE LINE # 244
000286 9A000000    R  ECALL    RecvData?
00028A 7A3BB0         MOV      @DR12,R11        ; A=R11
                                                ; SOURCE LINE # 245
00028D 0B74           INC      WR14,#01H
                                                ; SOURCE LINE # 246
00028F 7EB30000    R  MOV      R11,number       ; A=R11
000293 BEB001         CMP      R11,#01H         ; A=R11
000296 6804           JE       ?C0031
000298 9A000000    R  ECALL    SendACK?
                                                ; SOURCE LINE # 247
               ?C0031:
00029C 7EB30000    R  MOV      R11,number       ; A=R11
0002A0 14             DEC      A                ; A=R11
0002A1 7AB30000    R  MOV      number,R11       ; A=R11
0002A5 78DF           JNE      ?C0029
                                                ; SOURCE LINE # 249
0002A7 9A000000    R  ECALL    SendNAK?
                                                ; SOURCE LINE # 250
0002AB 9A000000    R  ECALL    Stop?
                                                ; SOURCE LINE # 251
0002AF DA3B           POP      DR12
0002B1 AA             ERET     
;       FUNCTION I2C_ReadNbyte? (END)

;       FUNCTION I2C_Change_Pin? (BEGIN)
                                                ; SOURCE LINE # 259
;---- Variable 'I2C_enum' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 261
0002B2 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 263
0002B5 53BACF         ANL      P_SW2,#0CFH
                                                ; SOURCE LINE # 264
0002B8 1B34           DEC      WR6,#01H
0002BA 6814           JE       ?C0036
0002BC 1B34           DEC      WR6,#01H
0002BE 6815           JE       ?C0037
0002C0 1B34           DEC      WR6,#01H
0002C2 6816           JE       ?C0038
0002C4 2E340003       ADD      WR6,#03H
0002C8 7813           JNE      ?C0034
                                                ; SOURCE LINE # 266
               ?C0035:
                                                ; SOURCE LINE # 267
0002CA E5BA           MOV      A,P_SW2          ; A=R11
0002CC F5BA           MOV      P_SW2,A          ; A=R11
                                                ; SOURCE LINE # 268
0002CE 800D           SJMP     ?C0034
                                                ; SOURCE LINE # 269
               ?C0036:
                                                ; SOURCE LINE # 270
0002D0 43BA10         ORL      P_SW2,#010H
                                                ; SOURCE LINE # 271
0002D3 8008           SJMP     ?C0034
C251 COMPILER V5.60.0,  CNU_PIE_I2C                                                        24/08/26  10:23:43  PAGE 13  

                                                ; SOURCE LINE # 272
               ?C0037:
                                                ; SOURCE LINE # 273
0002D5 43BA20         ORL      P_SW2,#020H
                                                ; SOURCE LINE # 274
0002D8 8003           SJMP     ?C0034
                                                ; SOURCE LINE # 275
               ?C0038:
                                                ; SOURCE LINE # 276
0002DA 43BA30         ORL      P_SW2,#030H
                                                ; SOURCE LINE # 277
                                                ; SOURCE LINE # 278
               ?C0034:
                                                ; SOURCE LINE # 280
0002DD 43BA80         ORL      P_SW2,#080H
                                                ; SOURCE LINE # 281
0002E0 AA             ERET     
;       FUNCTION I2C_Change_Pin? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       737     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------          3
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

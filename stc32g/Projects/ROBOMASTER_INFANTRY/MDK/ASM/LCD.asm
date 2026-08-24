C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE LCD
OBJECT MODULE PLACED IN .\Objects\ASM\LCD.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\LCD.c XSMALL ROM(HUGE) BROWSE INCDIR(..\
                    -..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X1000) 
                    -DEBUG CODE PRINT(.\ASM\LCD.asm) TABS(2) OBJECT(.\Objects\ASM\LCD.obj) 

stmt  level    source

    1          #include <math.h>
    2          #include "intrins.h"
    3          #include "LCD.h" 
    4          #include "Font.h" 
    5          #include "CNU_PIE_SPI.h"
    6          const unsigned char gImage_Wpie[1024] = { /* 0X22,0X01,0X80,0X00,0X40,0X00, */
    7          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    8          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
    9          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   10          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   11          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   12          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   13          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   14          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   15          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0XE0,0XE0,0XE0,0XE0,0XF0,0XE0,0XC0,0X00,
   16          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X80,0XE0,0XF0,0XE0,0XC0,0X80,0X00,0X00,
   17          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X80,0XE0,0XE0,0XE0,0XC0,0XC0,0X00,0X00,0X00,
   18          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   19          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   20          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   21          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   22          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   23          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X03,0X1F,0XFF,0XFF,0XFF,0XFF,0XFE,
   24          0XF0,0X00,0X00,0X00,0X00,0X00,0X80,0XFC,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFC,0XC0,
   25          0X00,0X00,0X00,0X00,0X80,0XE0,0XFC,0XFF,0XFF,0XFF,0X3F,0X0F,0X03,0X00,0X00,0X00,
   26          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   27          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   28          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   29          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X80,0XC0,0XC0,0XE0,0XE0,0XE0,0XE0,
   30          0XE0,0XE0,0XC0,0XC0,0X80,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   31          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X03,0X1F,0X7F,0XFF,0XFF,
   32          0XFF,0XFE,0XF8,0XC0,0XC0,0XFC,0XFF,0XFF,0XFF,0XFF,0X0F,0X1F,0XFF,0XFF,0XFF,0XFF,
   33          0XFE,0XF0,0X80,0XFC,0XFF,0XFF,0XFF,0XFF,0X7F,0X0F,0X00,0X00,0X00,0X00,0X00,0X00,
   34          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0XFC,0XFC,0XFC,0XFC,0X78,0X78,0XF0,
   35          0XF0,0XE0,0XC0,0XC0,0XC0,0X80,0X00,0X00,0X00,0X00,0X20,0X30,0X38,0X7C,0X3C,0X3C,
   36          0X08,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X80,0XC0,0XF8,0XFC,0XFC,0X3C,0X3C,0X1C,
   37          0X0C,0X00,0X00,0X00,0X00,0X00,0X80,0XF0,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,
   38          0XFF,0XFF,0XFF,0X7F,0X3F,0X1E,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   39          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X03,0X1F,
   40          0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0XFF,0X1F,0X07,0X00,0X00,0X00,0X00,0X3F,0XFF,0XFF,
   41          0XFF,0XFF,0XFF,0XFF,0XFF,0X7F,0X1F,0X03,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   42          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0XFF,0XFF,0XFF,0XFF,0XC0,0XE0,0XE0,
   43          0XF1,0XF9,0X3F,0X1F,0X1F,0X0F,0X07,0X03,0X00,0X00,0X00,0X0C,0XFC,0XFC,0XF8,0XF0,
   44          0X00,0X00,0X00,0X00,0X70,0XFC,0XFC,0XFF,0XFF,0XDF,0X33,0XF9,0XF8,0XF8,0XF0,0XE0,
   45          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X01,0X03,0X03,0X03,
   46          0X01,0X01,0X01,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   47          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   48          0X01,0X7F,0XFF,0XFF,0XFF,0X7F,0X0F,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X1F,
   49          0XFF,0XFF,0XFF,0X1F,0X03,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0XC0,0XE0,
   50          0XE0,0XF0,0XE0,0XE0,0X40,0X00,0X00,0X00,0X00,0XFF,0XFF,0XFF,0XEF,0X07,0X03,0X01,
   51          0X01,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0XFF,0XFF,0XFF,0XFF,
   52          0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X03,0X07,0X0F,0X3F,0X7E,0XFD,0XF9,0XF0,0XE0,
   53          0XC0,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   54          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   55          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   56          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   57          0X00,0X01,0X01,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 2   

   58          0X01,0X01,0X01,0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X01,0X01,0X00,0X00,0X00,0X00,
   59          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X01,0X01,0X01,
   60          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X01,0X01,0X01,
   61          0X01,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   62          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   63          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   64          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   65          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   66          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   67          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   68          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   69          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   70          0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,0X00,
   71          };
   72           /*******************************************************************************************************
             -*******************
   73           * @brief  OLED写数据
   74           * @brief  内部调用，无需关心
   75          *********************************************************************************************************
             -******************/
   76          void LCD_WrDat(unsigned char data_t)
   77          {
   78   1        unsigned char i=8;
   79   1        OLED_CS_Clear();
   80   1        OLED_DC_Set();
   81   1        OLED_CLK_Clear();
   82   1        while(i--)
   83   1        {
   84   2          if(data_t&0x80)OLED_D1_Set();
   85   2          else OLED_D1_Clear();
   86   2          OLED_CLK_Set();
   87   2      _nop_();
   88   2          OLED_CLK_Clear();
   89   2          data_t<<=1;
   90   2        }
   91   1        OLED_CS_Set();
   92   1      }
   93           /*******************************************************************************************************
             -*******************
   94           * @brief  OLED写命令
   95           * @brief  内部调用，无需关心
   96          *********************************************************************************************************
             -******************/
   97          void LCD_WrCmd(unsigned char cmd)
   98          {
   99   1        unsigned char i=8;
  100   1        OLED_CS_Clear();
  101   1        OLED_DC_Clear();
  102   1        OLED_CLK_Clear();
  103   1        while(i--)
  104   1        {
  105   2          if(cmd&0x80)OLED_D1_Set();
  106   2          else OLED_D1_Clear();
  107   2          OLED_CLK_Set();
  108   2      _nop_();
  109   2          OLED_CLK_Clear();
  110   2          cmd<<=1;
  111   2        }
  112   1        OLED_CS_Set();
  113   1      }
  114           /*******************************************************************************************************
             -*******************
  115           * @brief  OLED图像填充
  116           * @brief  内部调用，无需关心
  117          *********************************************************************************************************
             -******************/
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 3   

  118          void LCD_Fill(unsigned char bmp_data)
  119          {
  120   1        unsigned char y,x;
  121   1        
  122   1        for(y=0;y<8;y++)
  123   1        {
  124   2          LCD_WrCmd((uint8_t)(0xb0+y));
  125   2          LCD_WrCmd(0x01);
  126   2          LCD_WrCmd(0x10);
  127   2          for(x=0;x<128;x++)
  128   2            LCD_WrDat(bmp_data);
  129   2        }
  130   1      }
  131           /*******************************************************************************************************
             -*******************
  132           * @brief  OLED画点
  133           * @brief  内部调用，无需关心
  134          *********************************************************************************************************
             -******************/
  135          void LCD_Set_Pos(uint8_t x, uint8_t y) 
  136          {
  137   1        LCD_WrCmd((uint8_t)(0xb0+y));
  138   1        LCD_WrCmd(((x&0xf0)>>4)|0x10);
  139   1        LCD_WrCmd((x&0x0f)|0x01);
  140   1      }
  141           /*******************************************************************************************************
             -*******************
  142           * @brief  OLED清屏
  143           * @exampleCode
  144           *      LCD_CLS; //屏幕清屏
  145           * @endcode
  146          *********************************************************************************************************
             -******************/
  147          void LCD_CLS(void)
  148          {
  149   1        unsigned char y,x;
  150   1        for(y=0;y<8;y++)
  151   1        {
  152   2          LCD_WrCmd((uint8_t)(0xb0+y));
  153   2          LCD_WrCmd(0x01);
  154   2          LCD_WrCmd(0x10);
  155   2          for(x=0;x<128;x++)
  156   2            LCD_WrDat(0);
  157   2        }
  158   1      }
  159           /*******************************************************************************************************
             -*******************
  160           * @brief  OLED画logo
  161           * @brief  内部调用，无需关心
  162          *********************************************************************************************************
             -******************/
  163          void Draw_WPIELogo(void)
  164          {
  165   1        uint8_t x,y;
  166   1        unsigned int ii=0;
  167   1        for(y=0;y<8;y++)
  168   1        {
  169   2          for(x=0;x<128;x++)
  170   2          {
  171   3            LCD_Set_Pos(x,y);
  172   3            LCD_WrDat(gImage_Wpie[ii++]);
  173   3          }
  174   2        }
  175   1      }
  176           /*******************************************************************************************************
             -*******************
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 4   

  177           * @brief  OLED初始化
  178           * @exampleCode
  179           *      LCD_Init(); //OLED屏幕初始化
  180           * @endcode
  181          *********************************************************************************************************
             -******************/
  182          void LCD_Init(void)
  183          {
  184   1        GPIO_Init(OLED_CS_PORT ,OLED_CS_PIN ,GPIO_OUT_PP);
  185   1        GPIO_Init(OLED_RST_PORT,OLED_RST_PIN,GPIO_OUT_PP);
  186   1        GPIO_Init(OLED_DC_PORT ,OLED_DC_PIN ,GPIO_OUT_PP);
  187   1        GPIO_Init(OLED_D1_PORT ,OLED_D1_PIN ,GPIO_OUT_PP);
  188   1        GPIO_Init(OLED_CLK_PORT,OLED_CLK_PIN,GPIO_OUT_PP);
  189   1        Ms_Delay(200);
  190   1         
  191   1        
  192   1        OLED_CLK_Set();
  193   1        //OLED_CS_Set();  //预制SLK和SS为高电平
  194   1        
  195   1        OLED_RST_Clear();
  196   1        Ms_Delay(50);
  197   1        OLED_RST_Set();
  198   1        
  199   1        LCD_WrCmd(0xae);//--turn off oled panel
  200   1        LCD_WrCmd(0x00);//---set low column address
  201   1        LCD_WrCmd(0x10);//---set high column address
  202   1        LCD_WrCmd(0x40);//--set start line address  Set Mapping RAM Display Start Line (0x00~0x3F)
  203   1        LCD_WrCmd(0x81);//--set contrast control register
  204   1        LCD_WrCmd(0xc8); // Set SEG Output Current Brightness
  205   1        LCD_WrCmd(0xa1);//--Set SEG/Column Mapping     0xa0左右反置 0xa1正常
  206   1        LCD_WrCmd(0xc8);//Set COM/Row Scan Direction   0xc0上下反置 0xc8正常
  207   1        LCD_WrCmd(0xa6);//--set normal display
  208   1        // LCD_WrCmd(0xa8);//--set multiplex ratio(1 to 64)
  209   1        // LCD_WrCmd(0x3f);//--1/64 duty
  210   1        LCD_WrCmd(0xd3);//-set display offset Shift Mapping RAM Counter (0x00~0x3F)
  211   1        LCD_WrCmd(0x00);//-not offset
  212   1        LCD_WrCmd(0xd5);//--set display clock divide ratio/oscillator frequency
  213   1        LCD_WrCmd(0x80);//--set divide ratio, Set Clock as 100 Frames/Sec
  214   1        LCD_WrCmd(0xd9);//--set pre-charge period
  215   1        LCD_WrCmd(0xf1);//Set Pre-Charge as 15 Clocks & Discharge as 1 Clock
  216   1        LCD_WrCmd(0xda);//--set com pins hardware configuration
  217   1        LCD_WrCmd(0x12);
  218   1        LCD_WrCmd(0xdb);//--set vcomh
  219   1        LCD_WrCmd(0x40);//Set VCOM Deselect Level
  220   1        LCD_WrCmd(0x20);//-Set Page Addressing Mode (0x00/0x01/0x02)
  221   1        LCD_WrCmd(0x00);//
  222   1        LCD_WrCmd(0x8d);//--set Charge Pump enable/disable
  223   1        LCD_WrCmd(0x14);//--set(0x10) disable
  224   1        LCD_WrCmd(0xa4);// Disable Entire Display On (0xa4/0xa5)
  225   1        LCD_WrCmd(0xa6);// Disable Inverse Display On (0xa6/a7)
  226   1        LCD_WrCmd(0xaf);//--turn on oled panel
  227   1        LCD_Fill(0x00);  //初始清屏  
  228   1        LCD_Set_Pos(0,0);
  229   1        Draw_WPIELogo();
  230   1        Ms_Delay(1000);
  231   1        LCD_CLS();
  232   1        LCD_Set_Pos(0,0);
  233   1      }
  234           /*******************************************************************************************************
             -*******************
  235           * @brief  OLED画字符串
  236           * @exampleCode
  237           *      LCD_P6x8Str(0,0,"w.pie") //在起始坐标x为0，y为0绘制一个w.pie的字符串
  238           * @endcode
  239           * @param[in]  x    x起始坐标
  240           * @param[in]  y    y起始坐标(行数)             
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 5   

  241           * @param[in]  ch[] 字符串
  242          *********************************************************************************************************
             -******************/
  243          void LCD_P6x8Str(unsigned char x,unsigned char y,char ch[])
  244          {
  245   1        unsigned char c=0,i=0,j=0;
  246   1        while (ch[j]!='\0')
  247   1        {
  248   2          c =ch[j]-32;
  249   2          if(x>120){x=0;y++;}
  250   2          LCD_Set_Pos(x,y);
  251   2          for(i=0;i<6;i++)
  252   2          LCD_WrDat(F6x8[c][i]);
  253   2          x+=6;
  254   2          j++;
  255   2        }
  256   1      }
  257           /*******************************************************************************************************
             -*******************
  258           * @brief  OLED画字符串
  259           * @exampleCode
  260           *      LCD_P8x16Str(0,0,"w.pie") //在起始坐标x为0，y为0绘制一个w.pie的字符串
  261           * @endcode
  262           * @param[in]  x    x起始坐标
  263           * @param[in]  y    y起始坐标(行数)             
  264           * @param[in]  ch[] 字符串
  265          *********************************************************************************************************
             -******************/
  266          void LCD_P8x16Str(unsigned char x,unsigned char y,char ch[])
  267          {
  268   1        unsigned char c=0,i=0,j=0;
  269   1        
  270   1        while (ch[j]!='\0')
  271   1        {
  272   2          c =ch[j]-32;
  273   2          if(x>120){x=0;y++;}
  274   2          LCD_Set_Pos(x,y);
  275   2          for(i=0;i<8;i++)
  276   2            LCD_WrDat(F8X16[c*16+i]);
  277   2          LCD_Set_Pos(x,(uint8_t)(y+1));
  278   2          for(i=0;i<8;i++)
  279   2            LCD_WrDat(F8X16[c*16+i+8]);
  280   2          x+=8;
  281   2          j++;
  282   2        }
  283   1      }
  284           /*******************************************************************************************************
             -*******************
  285           * @brief  OLED画无符号整形
  286           * @exampleCode
  287                  unsigned int a;
  288           *      LCD_PrintU16(0,0,a) //在起始坐标x为0，y为0的地方显示变量a的值
  289           * @endcode
  290           * @param[in]  x    x起始坐标
  291           * @param[in]  y    y起始坐标(行数)             
  292           * @param[in]  num  要显示的变量
  293          *********************************************************************************************************
             -******************/
  294          void LCD_PrintU16(unsigned char x,unsigned char y,unsigned int num)
  295          {
  296   1        int j=0;
  297   1        char tmp[6],i;
  298   1        tmp[5]=0;
  299   1        tmp[4]=(unsigned char)(num%10+0x30);
  300   1        tmp[3]=(unsigned char)(num/10%10+0x30);
  301   1        tmp[2]=(unsigned char)(num/100%10+0x30);
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 6   

  302   1        tmp[1]=(unsigned char)(num/1000%10+0x30);
  303   1        tmp[0]=(unsigned char)(num/10000%10+0x30);
  304   1        
  305   1        for(i=0;i<4;i++)
  306   1        {
  307   2          if(tmp[0]=='0')//移位
  308   2          {
  309   3            for(j=0;j<5-i;j++)
  310   3              tmp[j]=tmp[j+1];
  311   3          } 
  312   2          else
  313   2            break;
  314   2        }
  315   1        
  316   1        LCD_P6x8Str(x,y,tmp);
  317   1        
  318   1      }
  319           /*******************************************************************************************************
             -*******************
  320           * @brief  OLED画浮点型
  321           * @exampleCode
  322                  float a;
  323           *      LCD_PrintFloat(0 , 0 , a , 7) //在起始坐标x为0，y为0的地方显示变量a的值,一共显示7位
  324           * @endcode
  325           * @param[in]  x    x起始坐标
  326           * @param[in]  y    y起始坐标(行数)             
  327           * @param[in]  num  要显示的变量
  328          *********************************************************************************************************
             -******************/
  329          void LCD_PrintFloat(unsigned char x,unsigned char y,float num,unsigned int N)
  330          {
  331   1        #define MAX_STR 12 
  332   1        char tmp[MAX_STR]={0};int n=3;
  333   1        float NUM=num;
  334   1        float _num=fabs(NUM);
  335   1        int i;
  336   1        uint32_t num0;
  337   1       if(NUM<0)
  338   1       {
  339   2         NUM=_num;
  340   2         tmp[0]='-';
  341   2       }
  342   1       else tmp[0]='+';
  343   1       for(i=0;i<MAX_STR+1;i++)
  344   1       {
  345   2         _num/=10;
  346   2         if(_num<1)break;
  347   2         else  n++;
  348   2       }
  349   1       if(N>7)N=7;
  350   1       if(((int)(N)+2-n)>0)for(i=0;i<(N+2-n);i++)NUM*=10;
  351   1       num0=(uint32_t)NUM;
  352   1       for(i=N>=n?(N+2-1):n-1;i>0;i--)
  353   1        {
  354   2          if(i!=n-1)
  355   2          {
  356   3            tmp[i]=(char)(num0%10+0x30);
  357   3            num0/=10;
  358   3          }
  359   2          else
  360   2            tmp[i]='.';
  361   2        }
  362   1        tmp[N+2]=0;
  363   1        LCD_P6x8Str(x,y,tmp);
  364   1      }
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 7   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION LCD_WrDat? (BEGIN)
                                                ; SOURCE LINE # 76
000000 CA79           PUSH     WR14
000002 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'data_t' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 77
                                                ; SOURCE LINE # 78
000004 7EE008         MOV      R14,#08H
;---- Variable 'i' assigned to Register 'R14' ----
                                                ; SOURCE LINE # 79
000007 7E340002       MOV      WR6,#02H
00000B 7E240004       MOV      WR4,#04H
00000F E4             CLR      A                ; A=R11
000010 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 80
000014 7E340002       MOV      WR6,#02H
000018 7E240040       MOV      WR4,#040H
00001C 7401           MOV      A,#01H           ; A=R11
00001E 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 81
000022 7E340002       MOV      WR6,#02H
000026 7E240020       MOV      WR4,#020H
00002A E4             CLR      A                ; A=R11
00002B 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 82
00002F 803C           SJMP     ?C0001
               ?C0003:
                                                ; SOURCE LINE # 84
000031 7CBF           MOV      R11,R15          ; A=R11
000033 30E70C         JNB      ACC.7,?C0005
000036 7E340002       MOV      WR6,#02H
00003A 7E240008       MOV      WR4,#08H
00003E 7401           MOV      A,#01H           ; A=R11
000040 8009           SJMP     ?C0107
               ?C0005:
                                                ; SOURCE LINE # 85
000042 7E340002       MOV      WR6,#02H
000046 7E240008       MOV      WR4,#08H
00004A E4             CLR      A                ; A=R11
               ?C0107:
00004B 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 86
00004F 7E340002       MOV      WR6,#02H
000053 7E240020       MOV      WR4,#020H
000057 7401           MOV      A,#01H           ; A=R11
000059 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 87
00005D 00             NOP      
                                                ; SOURCE LINE # 88
00005E 7E340002       MOV      WR6,#02H
000062 7E240020       MOV      WR4,#020H
000066 E4             CLR      A                ; A=R11
000067 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 89
00006B 3EF0           SLL      R15
                                                ; SOURCE LINE # 90
               ?C0001:
00006D 7CAE           MOV      R10,R14
00006F 1BE0           DEC      R14,#01H
000071 4CAA           ORL      R10,R10
000073 78BC           JNE      ?C0003
                                                ; SOURCE LINE # 91
000075 7E340002       MOV      WR6,#02H
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 8   

000079 7E240004       MOV      WR4,#04H
00007D 7401           MOV      A,#01H           ; A=R11
00007F 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 92
000083 DA79           POP      WR14
000085 AA             ERET     
;       FUNCTION LCD_WrDat? (END)

;       FUNCTION LCD_WrCmd? (BEGIN)
                                                ; SOURCE LINE # 97
000086 CA79           PUSH     WR14
000088 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'cmd' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 98
                                                ; SOURCE LINE # 99
00008A 7EE008         MOV      R14,#08H
;---- Variable 'i' assigned to Register 'R14' ----
                                                ; SOURCE LINE # 100
00008D 7E340002       MOV      WR6,#02H
000091 7E240004       MOV      WR4,#04H
000095 E4             CLR      A                ; A=R11
000096 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 101
00009A 7E340002       MOV      WR6,#02H
00009E 7E240040       MOV      WR4,#040H
0000A2 E4             CLR      A                ; A=R11
0000A3 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 102
0000A7 7E340002       MOV      WR6,#02H
0000AB 7E240020       MOV      WR4,#020H
0000AF E4             CLR      A                ; A=R11
0000B0 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 103
0000B4 803C           SJMP     ?C0007
               ?C0009:
                                                ; SOURCE LINE # 105
0000B6 7CBF           MOV      R11,R15          ; A=R11
0000B8 30E70C         JNB      ACC.7,?C0011
0000BB 7E340002       MOV      WR6,#02H
0000BF 7E240008       MOV      WR4,#08H
0000C3 7401           MOV      A,#01H           ; A=R11
0000C5 8009           SJMP     ?C0108
               ?C0011:
                                                ; SOURCE LINE # 106
0000C7 7E340002       MOV      WR6,#02H
0000CB 7E240008       MOV      WR4,#08H
0000CF E4             CLR      A                ; A=R11
               ?C0108:
0000D0 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 107
0000D4 7E340002       MOV      WR6,#02H
0000D8 7E240020       MOV      WR4,#020H
0000DC 7401           MOV      A,#01H           ; A=R11
0000DE 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 108
0000E2 00             NOP      
                                                ; SOURCE LINE # 109
0000E3 7E340002       MOV      WR6,#02H
0000E7 7E240020       MOV      WR4,#020H
0000EB E4             CLR      A                ; A=R11
0000EC 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 110
0000F0 3EF0           SLL      R15
                                                ; SOURCE LINE # 111
               ?C0007:
0000F2 7CAE           MOV      R10,R14
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 9   

0000F4 1BE0           DEC      R14,#01H
0000F6 4CAA           ORL      R10,R10
0000F8 78BC           JNE      ?C0009
                                                ; SOURCE LINE # 112
0000FA 7E340002       MOV      WR6,#02H
0000FE 7E240004       MOV      WR4,#04H
000102 7401           MOV      A,#01H           ; A=R11
000104 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 113
000108 DA79           POP      WR14
00010A AA             ERET     
;       FUNCTION LCD_WrCmd? (END)

;       FUNCTION LCD_Fill? (BEGIN)
                                                ; SOURCE LINE # 118
00010B CAD8           PUSH     R13
00010D CA79           PUSH     WR14
00010F 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'bmp_data' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 119
                                                ; SOURCE LINE # 122
000111 6CEE           XRL      R14,R14
;---- Variable 'y' assigned to Register 'R14' ----
               ?C0016:
                                                ; SOURCE LINE # 124
000113 7CBE           MOV      R11,R14          ; A=R11
000115 24B0           ADD      A,#0B0H          ; A=R11
000117 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 125
00011B 7401           MOV      A,#01H           ; A=R11
00011D 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 126
000121 7410           MOV      A,#010H          ; A=R11
000123 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 127
000127 6CDD           XRL      R13,R13
;---- Variable 'x' assigned to Register 'R13' ----
               ?C0021:
                                                ; SOURCE LINE # 128
000129 7CBF           MOV      R11,R15          ; A=R11
00012B 9A000000    R  ECALL    LCD_WrDat?
00012F 0BD0           INC      R13,#01H
000131 BED080         CMP      R13,#080H
000134 78F3           JNE      ?C0021
                                                ; SOURCE LINE # 129
000136 0BE0           INC      R14,#01H
000138 BEE008         CMP      R14,#08H
00013B 40D6           JC       ?C0016
                                                ; SOURCE LINE # 130
00013D DA79           POP      WR14
00013F DAD8           POP      R13
000141 AA             ERET     
;       FUNCTION LCD_Fill? (END)

;       FUNCTION LCD_Set_Pos? (BEGIN)
                                                ; SOURCE LINE # 135
000142 CAF8           PUSH     R15
;---- Variable 'y' assigned to Register 'R10' ----
000144 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'x' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 137
000146 7CB7           MOV      R11,R7           ; A=R11
000148 24B0           ADD      A,#0B0H          ; A=R11
00014A 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 138
00014E 7CBF           MOV      R11,R15          ; A=R11
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 10  

000150 54F0           ANL      A,#0F0H          ; A=R11
000152 C4             SWAP     A                ; A=R11
000153 540F           ANL      A,#0FH           ; A=R11
000155 4410           ORL      A,#010H          ; A=R11
000157 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 139
00015B 7CBF           MOV      R11,R15          ; A=R11
00015D 540F           ANL      A,#0FH           ; A=R11
00015F 4401           ORL      A,#01H           ; A=R11
000161 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 140
000165 DAF8           POP      R15
000167 AA             ERET     
;       FUNCTION LCD_Set_Pos? (END)

;       FUNCTION LCD_CLS? (BEGIN)
                                                ; SOURCE LINE # 147
000168 CA79           PUSH     WR14
                                                ; SOURCE LINE # 148
                                                ; SOURCE LINE # 150
00016A 6CFF           XRL      R15,R15
;---- Variable 'y' assigned to Register 'R15' ----
               ?C0026:
                                                ; SOURCE LINE # 152
00016C 7CBF           MOV      R11,R15          ; A=R11
00016E 24B0           ADD      A,#0B0H          ; A=R11
000170 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 153
000174 7401           MOV      A,#01H           ; A=R11
000176 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 154
00017A 7410           MOV      A,#010H          ; A=R11
00017C 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 155
000180 6CEE           XRL      R14,R14
;---- Variable 'x' assigned to Register 'R14' ----
               ?C0031:
                                                ; SOURCE LINE # 156
000182 E4             CLR      A                ; A=R11
000183 9A000000    R  ECALL    LCD_WrDat?
000187 0BE0           INC      R14,#01H
000189 BEE080         CMP      R14,#080H
00018C 78F4           JNE      ?C0031
                                                ; SOURCE LINE # 157
00018E 0BF0           INC      R15,#01H
000190 BEF008         CMP      R15,#08H
000193 40D7           JC       ?C0026
                                                ; SOURCE LINE # 158
000195 DA79           POP      WR14
000197 AA             ERET     
;       FUNCTION LCD_CLS? (END)

;       FUNCTION Draw_WPIELogo? (BEGIN)
                                                ; SOURCE LINE # 163
000198 CA3B           PUSH     DR12
                                                ; SOURCE LINE # 164
                                                ; SOURCE LINE # 166
00019A 6D77           XRL      WR14,WR14
;---- Variable 'ii' assigned to Register 'WR14' ----
                                                ; SOURCE LINE # 167
00019C 6CDD           XRL      R13,R13
;---- Variable 'y' assigned to Register 'R13' ----
                                                ; SOURCE LINE # 169
               ?C0042:
00019E 6CCC           XRL      R12,R12
;---- Variable 'x' assigned to Register 'R12' ----
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 11  

               ?C0041:
                                                ; SOURCE LINE # 171
0001A0 7CBC           MOV      R11,R12          ; A=R11
0001A2 7C7D           MOV      R7,R13
0001A4 9A000000    R  ECALL    LCD_Set_Pos?
                                                ; SOURCE LINE # 172
0001A8 7D37           MOV      WR6,WR14
0001AA 0B74           INC      WR14,#01H
0001AC 6D22           XRL      WR4,WR4
0001AE 2E240000    R  ADD      WR4,#WORD2 gImage_Wpie
0001B2 2E180000    R  ADD      DR4,#WORD0 gImage_Wpie
0001B6 7E1BB0         MOV      R11,@DR4         ; A=R11
0001B9 9A000000    R  ECALL    LCD_WrDat?
                                                ; SOURCE LINE # 173
0001BD 0BC0           INC      R12,#01H
0001BF BEC080         CMP      R12,#080H
0001C2 78DC           JNE      ?C0041
                                                ; SOURCE LINE # 174
0001C4 0BD0           INC      R13,#01H
0001C6 BED008         CMP      R13,#08H
0001C9 40D3           JC       ?C0042
                                                ; SOURCE LINE # 175
0001CB DA3B           POP      DR12
0001CD AA             ERET     
;       FUNCTION Draw_WPIELogo? (END)

;       FUNCTION LCD_Init? (BEGIN)
                                                ; SOURCE LINE # 182
                                                ; SOURCE LINE # 184
0001CE 7E340002       MOV      WR6,#02H
0001D2 7E240004       MOV      WR4,#04H
0001D6 7E140003       MOV      WR2,#03H
0001DA 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 185
0001DE 7E340002       MOV      WR6,#02H
0001E2 7E240010       MOV      WR4,#010H
0001E6 7E140003       MOV      WR2,#03H
0001EA 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 186
0001EE 7E340002       MOV      WR6,#02H
0001F2 7E240040       MOV      WR4,#040H
0001F6 7E140003       MOV      WR2,#03H
0001FA 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 187
0001FE 7E340002       MOV      WR6,#02H
000202 7E240008       MOV      WR4,#08H
000206 7E140003       MOV      WR2,#03H
00020A 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 188
00020E 7E340002       MOV      WR6,#02H
000212 7E240020       MOV      WR4,#020H
000216 7E140003       MOV      WR2,#03H
00021A 9A000000    E  ECALL    GPIO_Init?
                                                ; SOURCE LINE # 189
00021E 7E3400C8       MOV      WR6,#0C8H
000222 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 192
000226 7E340002       MOV      WR6,#02H
00022A 7E240020       MOV      WR4,#020H
00022E 7401           MOV      A,#01H           ; A=R11
000230 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 195
000234 7E340002       MOV      WR6,#02H
000238 7E240010       MOV      WR4,#010H
00023C E4             CLR      A                ; A=R11
00023D 9A000000    E  ECALL    GPIO_Write_Bit?
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 12  

                                                ; SOURCE LINE # 196
000241 7E340032       MOV      WR6,#032H
000245 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 197
000249 7E340002       MOV      WR6,#02H
00024D 7E240010       MOV      WR4,#010H
000251 7401           MOV      A,#01H           ; A=R11
000253 9A000000    E  ECALL    GPIO_Write_Bit?
                                                ; SOURCE LINE # 199
000257 74AE           MOV      A,#0AEH          ; A=R11
000259 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 200
00025D E4             CLR      A                ; A=R11
00025E 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 201
000262 7410           MOV      A,#010H          ; A=R11
000264 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 202
000268 7440           MOV      A,#040H          ; A=R11
00026A 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 203
00026E 7481           MOV      A,#081H          ; A=R11
000270 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 204
000274 74C8           MOV      A,#0C8H          ; A=R11
000276 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 205
00027A 74A1           MOV      A,#0A1H          ; A=R11
00027C 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 206
000280 74C8           MOV      A,#0C8H          ; A=R11
000282 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 207
000286 74A6           MOV      A,#0A6H          ; A=R11
000288 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 210
00028C 74D3           MOV      A,#0D3H          ; A=R11
00028E 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 211
000292 E4             CLR      A                ; A=R11
000293 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 212
000297 74D5           MOV      A,#0D5H          ; A=R11
000299 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 213
00029D 7480           MOV      A,#080H          ; A=R11
00029F 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 214
0002A3 74D9           MOV      A,#0D9H          ; A=R11
0002A5 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 215
0002A9 74F1           MOV      A,#0F1H          ; A=R11
0002AB 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 216
0002AF 74DA           MOV      A,#0DAH          ; A=R11
0002B1 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 217
0002B5 7412           MOV      A,#012H          ; A=R11
0002B7 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 218
0002BB 74DB           MOV      A,#0DBH          ; A=R11
0002BD 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 219
0002C1 7440           MOV      A,#040H          ; A=R11
0002C3 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 220
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 13  

0002C7 7420           MOV      A,#020H          ; A=R11
0002C9 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 221
0002CD E4             CLR      A                ; A=R11
0002CE 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 222
0002D2 748D           MOV      A,#08DH          ; A=R11
0002D4 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 223
0002D8 7414           MOV      A,#014H          ; A=R11
0002DA 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 224
0002DE 74A4           MOV      A,#0A4H          ; A=R11
0002E0 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 225
0002E4 74A6           MOV      A,#0A6H          ; A=R11
0002E6 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 226
0002EA 74AF           MOV      A,#0AFH          ; A=R11
0002EC 9A000000    R  ECALL    LCD_WrCmd?
                                                ; SOURCE LINE # 227
0002F0 E4             CLR      A                ; A=R11
0002F1 9A000000    R  ECALL    LCD_Fill?
                                                ; SOURCE LINE # 228
0002F5 E4             CLR      A                ; A=R11
0002F6 6C77           XRL      R7,R7
0002F8 9A000000    R  ECALL    LCD_Set_Pos?
                                                ; SOURCE LINE # 229
0002FC 9A000000    R  ECALL    Draw_WPIELogo?
                                                ; SOURCE LINE # 230
000300 7E3403E8       MOV      WR6,#03E8H
000304 9A000000    E  ECALL    Ms_Delay?
                                                ; SOURCE LINE # 231
000308 9A000000    R  ECALL    LCD_CLS?
                                                ; SOURCE LINE # 232
00030C E4             CLR      A                ; A=R11
00030D 6C77           XRL      R7,R7
00030F 8A000000    R  EJMP     LCD_Set_Pos?
;       FUNCTION LCD_Init? (END)

;       FUNCTION LCD_P6x8Str? (BEGIN)
                                                ; SOURCE LINE # 243
000313 CA3B           PUSH     DR12
000315 7F30           MOV      DR12,DR0
;---- Variable 'ch' assigned to Register 'DR12' ----
000317 7A730000    R  MOV      y,R7
00031B 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 244
                                                ; SOURCE LINE # 245
00031F E4             CLR      A                ; A=R11
000320 7AB30000    R  MOV      c,R11            ; A=R11
000324 7AB30000    R  MOV      i,R11            ; A=R11
                                                ; SOURCE LINE # 246
000328 020000      R  LJMP     ?C0109
               ?C0045:
                                                ; SOURCE LINE # 248
00032B 7E730000    R  MOV      R7,j
00032F 0A37           MOVZ     WR6,R7
000331 2D37           ADD      WR6,WR14
000333 7D26           MOV      WR4,WR12
000335 7E1B70         MOV      R7,@DR4
000338 1A37           MOVS     WR6,R7
00033A 9E340020       SUB      WR6,#020H
00033E 7A730000    R  MOV      c,R7
                                                ; SOURCE LINE # 249
000342 7E730000    R  MOV      R7,x
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 14  

000346 BE7078         CMP      R7,#078H
000349 280E           JLE      ?C0047
00034B E4             CLR      A                ; A=R11
00034C 7AB30000    R  MOV      x,R11            ; A=R11
000350 7EB30000    R  MOV      R11,y            ; A=R11
000354 04             INC      A                ; A=R11
000355 7AB30000    R  MOV      y,R11            ; A=R11
               ?C0047:
                                                ; SOURCE LINE # 250
000359 7EB30000    R  MOV      R11,x            ; A=R11
00035D 7E730000    R  MOV      R7,y
000361 9A000000    R  ECALL    LCD_Set_Pos?
                                                ; SOURCE LINE # 251
000365 E4             CLR      A                ; A=R11
000366 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0051:
                                                ; SOURCE LINE # 252
00036A 7E730000    R  MOV      R7,c
00036E 0A37           MOVZ     WR6,R7
000370 6D22           XRL      WR4,WR4
000372 7E140006       MOV      WR2,#06H
000376 9A000000    E  ECALL    ?C?LIMUL?
00037A 7E330000    R  MOV      R3,i
00037E 0A13           MOVZ     WR2,R3
000380 6D00           XRL      WR0,WR0
000382 2F10           ADD      DR4,DR0
000384 2E240000    E  ADD      WR4,#WORD2 F6x8
000388 2E180000    E  ADD      DR4,#WORD0 F6x8
00038C 7E1BB0         MOV      R11,@DR4         ; A=R11
00038F 9A000000    R  ECALL    LCD_WrDat?
000393 7EB30000    R  MOV      R11,i            ; A=R11
000397 04             INC      A                ; A=R11
000398 7AB30000    R  MOV      i,R11            ; A=R11
00039C B406CB         CJNE     A,#06H,?C0051    ; A=R11
                                                ; SOURCE LINE # 253
00039F 7EB30000    R  MOV      R11,x            ; A=R11
0003A3 2406           ADD      A,#06H           ; A=R11
0003A5 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 254
0003A9 7EB30000    R  MOV      R11,j            ; A=R11
0003AD 04             INC      A                ; A=R11
               ?C0109:
0003AE 7AB30000    R  MOV      j,R11            ; A=R11
                                                ; SOURCE LINE # 255
               ?C0043:
0003B2 7E730000    R  MOV      R7,j
0003B6 0A37           MOVZ     WR6,R7
0003B8 2D37           ADD      WR6,WR14
0003BA 7D26           MOV      WR4,WR12
0003BC 7E1BB0         MOV      R11,@DR4         ; A=R11
0003BF 6003        R  JZ       $ + 5H
0003C1 020000      R  LJMP     ?C0045
                                                ; SOURCE LINE # 256
0003C4 DA3B           POP      DR12
0003C6 AA             ERET     
;       FUNCTION LCD_P6x8Str? (END)

;       FUNCTION LCD_P8x16Str? (BEGIN)
                                                ; SOURCE LINE # 266
0003C7 CA3B           PUSH     DR12
0003C9 7F30           MOV      DR12,DR0
;---- Variable 'ch' assigned to Register 'DR12' ----
0003CB 7A730000    R  MOV      y,R7
0003CF 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 267
                                                ; SOURCE LINE # 268
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 15  

0003D3 E4             CLR      A                ; A=R11
0003D4 7AB30000    R  MOV      c,R11            ; A=R11
0003D8 7AB30000    R  MOV      i,R11            ; A=R11
                                                ; SOURCE LINE # 270
0003DC 020000      R  LJMP     ?C0110
               ?C0055:
                                                ; SOURCE LINE # 272
0003DF 7E730000    R  MOV      R7,j
0003E3 0A37           MOVZ     WR6,R7
0003E5 2D37           ADD      WR6,WR14
0003E7 7D26           MOV      WR4,WR12
0003E9 7E1B70         MOV      R7,@DR4
0003EC 1A37           MOVS     WR6,R7
0003EE 9E340020       SUB      WR6,#020H
0003F2 7A730000    R  MOV      c,R7
                                                ; SOURCE LINE # 273
0003F6 7E730000    R  MOV      R7,x
0003FA BE7078         CMP      R7,#078H
0003FD 280E           JLE      ?C0057
0003FF E4             CLR      A                ; A=R11
000400 7AB30000    R  MOV      x,R11            ; A=R11
000404 7EB30000    R  MOV      R11,y            ; A=R11
000408 04             INC      A                ; A=R11
000409 7AB30000    R  MOV      y,R11            ; A=R11
               ?C0057:
                                                ; SOURCE LINE # 274
00040D 7EB30000    R  MOV      R11,x            ; A=R11
000411 7E730000    R  MOV      R7,y
000415 9A000000    R  ECALL    LCD_Set_Pos?
                                                ; SOURCE LINE # 275
000419 E4             CLR      A                ; A=R11
00041A 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0061:
                                                ; SOURCE LINE # 276
00041E 7E730000    R  MOV      R7,c
000422 0A17           MOVZ     WR2,R7
000424 6D00           XRL      WR0,WR0
000426 7404           MOV      A,#04H           ; A=R11
               ?C0105:
000428 2F00           ADD      DR0,DR0
00042A 14             DEC      A                ; A=R11
00042B 78FB           JNE      ?C0105
00042D 7E730000    R  MOV      R7,i
000431 0A37           MOVZ     WR6,R7
000433 6D22           XRL      WR4,WR4
000435 2F10           ADD      DR4,DR0
000437 2E240000    E  ADD      WR4,#WORD2 F8X16
00043B 2E180000    E  ADD      DR4,#WORD0 F8X16
00043F 7E1BB0         MOV      R11,@DR4         ; A=R11
000442 9A000000    R  ECALL    LCD_WrDat?
000446 7EB30000    R  MOV      R11,i            ; A=R11
00044A 04             INC      A                ; A=R11
00044B 7AB30000    R  MOV      i,R11            ; A=R11
00044F B408CC         CJNE     A,#08H,?C0061    ; A=R11
                                                ; SOURCE LINE # 277
000452 7EB30000    R  MOV      R11,x            ; A=R11
000456 7E730000    R  MOV      R7,y
00045A 0B70           INC      R7,#01H
00045C 9A000000    R  ECALL    LCD_Set_Pos?
                                                ; SOURCE LINE # 278
000460 E4             CLR      A                ; A=R11
000461 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0066:
                                                ; SOURCE LINE # 279
000465 7E730000    R  MOV      R7,c
000469 0A17           MOVZ     WR2,R7
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 16  

00046B 6D00           XRL      WR0,WR0
00046D 7404           MOV      A,#04H           ; A=R11
               ?C0106:
00046F 2F00           ADD      DR0,DR0
000471 14             DEC      A                ; A=R11
000472 78FB           JNE      ?C0106
000474 7E730000    R  MOV      R7,i
000478 0A37           MOVZ     WR6,R7
00047A 6D22           XRL      WR4,WR4
00047C 2F10           ADD      DR4,DR0
00047E 2E240000    E  ADD      WR4,#WORD2 F8X16+8
000482 2E180000    E  ADD      DR4,#WORD0 F8X16+8
000486 7E1BB0         MOV      R11,@DR4         ; A=R11
000489 9A000000    R  ECALL    LCD_WrDat?
00048D 7EB30000    R  MOV      R11,i            ; A=R11
000491 04             INC      A                ; A=R11
000492 7AB30000    R  MOV      i,R11            ; A=R11
000496 B408CC         CJNE     A,#08H,?C0066    ; A=R11
                                                ; SOURCE LINE # 280
000499 7EB30000    R  MOV      R11,x            ; A=R11
00049D 2408           ADD      A,#08H           ; A=R11
00049F 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 281
0004A3 7EB30000    R  MOV      R11,j            ; A=R11
0004A7 04             INC      A                ; A=R11
               ?C0110:
0004A8 7AB30000    R  MOV      j,R11            ; A=R11
                                                ; SOURCE LINE # 282
               ?C0053:
0004AC 7E730000    R  MOV      R7,j
0004B0 0A37           MOVZ     WR6,R7
0004B2 2D37           ADD      WR6,WR14
0004B4 7D26           MOV      WR4,WR12
0004B6 7E1BB0         MOV      R11,@DR4         ; A=R11
0004B9 6003        R  JZ       $ + 5H
0004BB 020000      R  LJMP     ?C0055
                                                ; SOURCE LINE # 283
0004BE DA3B           POP      DR12
0004C0 AA             ERET     
;       FUNCTION LCD_P8x16Str? (END)

;       FUNCTION LCD_PrintU16? (BEGIN)
                                                ; SOURCE LINE # 294
0004C1 7D12           MOV      WR2,WR4
;---- Variable 'num' assigned to Register 'WR2' ----
0004C3 7CA7           MOV      R10,R7
;---- Variable 'y' assigned to Register 'R10' ----
0004C5 7C1B           MOV      R1,R11           ; A=R11
;---- Variable 'x' assigned to Register 'R1' ----
                                                ; SOURCE LINE # 295
                                                ; SOURCE LINE # 296
;---- Variable 'j' assigned to Register 'WR8' ----
                                                ; SOURCE LINE # 298
0004C7 E4             CLR      A                ; A=R11
0004C8 7AB30000    R  MOV      tmp+5,R11        ; A=R11
                                                ; SOURCE LINE # 299
0004CC 7EF4000A       MOV      WR30,#0AH
0004D0 7D32           MOV      WR6,WR4
0004D2 8D3F           DIV      WR6,WR30
0004D4 7DE2           MOV      WR28,WR4
0004D6 2EE40030       ADD      WR28,#030H
0004DA 7D3E           MOV      WR6,WR28
0004DC 7A730000    R  MOV      tmp+4,R7
                                                ; SOURCE LINE # 300
0004E0 7D31           MOV      WR6,WR2
0004E2 8D3F           DIV      WR6,WR30
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 17  

0004E4 8D3F           DIV      WR6,WR30
0004E6 7DE2           MOV      WR28,WR4
0004E8 2EE40030       ADD      WR28,#030H
0004EC 7D3E           MOV      WR6,WR28
0004EE 7A730000    R  MOV      tmp+3,R7
                                                ; SOURCE LINE # 301
0004F2 7E240064       MOV      WR4,#064H
0004F6 7D31           MOV      WR6,WR2
0004F8 8D32           DIV      WR6,WR4
0004FA 8D3F           DIV      WR6,WR30
0004FC 7DE2           MOV      WR28,WR4
0004FE 2EE40030       ADD      WR28,#030H
000502 7D3E           MOV      WR6,WR28
000504 7A730000    R  MOV      tmp+2,R7
                                                ; SOURCE LINE # 302
000508 7E2403E8       MOV      WR4,#03E8H
00050C 7D31           MOV      WR6,WR2
00050E 8D32           DIV      WR6,WR4
000510 8D3F           DIV      WR6,WR30
000512 7DE2           MOV      WR28,WR4
000514 2EE40030       ADD      WR28,#030H
000518 7D3E           MOV      WR6,WR28
00051A 7A730000    R  MOV      tmp+1,R7
                                                ; SOURCE LINE # 303
00051E 7E242710       MOV      WR4,#02710H
000522 7D31           MOV      WR6,WR2
000524 8D32           DIV      WR6,WR4
000526 8D3F           DIV      WR6,WR30
000528 7D32           MOV      WR6,WR4
00052A 2E340030       ADD      WR6,#030H
00052E 7A730000    R  MOV      tmp,R7
                                                ; SOURCE LINE # 305
000532 6C00           XRL      R0,R0
;---- Variable 'i' assigned to Register 'R0' ----
               ?C0071:
                                                ; SOURCE LINE # 307
000534 7EB30000    R  MOV      R11,tmp          ; A=R11
000538 B43021         CJNE     A,#030H,?C0069   ; A=R11
                                                ; SOURCE LINE # 309
00053B 6D44           XRL      WR8,WR8
00053D 800A           SJMP     ?C0076
               ?C0077:
                                                ; SOURCE LINE # 310
00053F 09B40000    R  MOV      R11,@WR8+tmp+0x1 ; A=R11
000543 19B40000    R  MOV      @WR8+tmp,R11     ; A=R11
000547 0B44           INC      WR8,#01H
               ?C0076:
000549 1A30           MOVS     WR6,R0
00054B 7E140005       MOV      WR2,#05H
00054F 9D13           SUB      WR2,WR6
000551 BD14           CMP      WR2,WR8
000553 18EA           JSG      ?C0077
                                                ; SOURCE LINE # 311
                                                ; SOURCE LINE # 313
                                                ; SOURCE LINE # 314
000555 0B00           INC      R0,#01H
000557 BE0004         CMP      R0,#04H
00055A 48D8           JSL      ?C0071
               ?C0069:
                                                ; SOURCE LINE # 316
00055C 7CB1           MOV      R11,R1           ; A=R11
00055E 7C7A           MOV      R7,R10
000560 7E000000    R  MOV      DR0,#WORD0 tmp
000564 8A000000    R  EJMP     LCD_P6x8Str?
;       FUNCTION LCD_PrintU16? (END)

C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 18  

;       FUNCTION LCD_PrintFloat? (BEGIN)
                                                ; SOURCE LINE # 329
000568 CA3B           PUSH     DR12
00056A 7D72           MOV      WR14,WR4
;---- Variable 'N' assigned to Register 'WR14' ----
00056C 7F70           MOV      DR28,DR0
;---- Variable 'num' assigned to Register 'DR28' ----
00056E 7CD7           MOV      R13,R7
;---- Variable 'y' assigned to Register 'R13' ----
000570 7CCB           MOV      R12,R11          ; A=R11
;---- Variable 'x' assigned to Register 'R12' ----
                                                ; SOURCE LINE # 330
                                                ; SOURCE LINE # 332
000572 7E340000    R  MOV      WR6,#WORD0 ?tpl?0001
000576 7E240000    R  MOV      WR4,#WORD2 ?tpl?0001
00057A 7E140000    R  MOV      WR2,#WORD0 tmp
00057E 740C           MOV      A,#0CH           ; A=R11
000580 9A000000    E  ECALL    ?C?BMOVENP8?
000584 7E340003       MOV      WR6,#03H
000588 7A370000    R  MOV      n,WR6
                                                ; SOURCE LINE # 333
00058C 7A7F0000    R  MOV      NUM,DR28
                                                ; SOURCE LINE # 334
000590 7F17           MOV      DR4,DR28
000592 9A000000    E  ECALL    fabs??
000596 7F61           MOV      DR24,DR4
;---- Variable '_num' assigned to Register 'DR24' ----
                                                ; SOURCE LINE # 337
000598 9F00           SUB      DR0,DR0
00059A 7E1F0000    R  MOV      DR4,NUM
00059E 9A000000    E  ECALL    ?C?FPCMP3?
0005A2 5008           JNC      ?C0080
                                                ; SOURCE LINE # 339
0005A4 7A6F0000    R  MOV      NUM,DR24
                                                ; SOURCE LINE # 340
0005A8 742D           MOV      A,#02DH          ; A=R11
                                                ; SOURCE LINE # 341
0005AA 8002           SJMP     ?C0111
               ?C0080:
                                                ; SOURCE LINE # 342
0005AC 742B           MOV      A,#02BH          ; A=R11
               ?C0111:
0005AE 7AB30000    R  MOV      tmp,R11          ; A=R11
                                                ; SOURCE LINE # 343
0005B2 6DFF           XRL      WR30,WR30
0005B4 7AF70000    R  MOV      i,WR30
               ?C0085:
                                                ; SOURCE LINE # 345
0005B8 6D11           XRL      WR2,WR2
0005BA 7E044120       MOV      WR0,#04120H
0005BE 7F16           MOV      DR4,DR24
0005C0 9A000000    E  ECALL    ?C?FPDIV?
0005C4 7F61           MOV      DR24,DR4
                                                ; SOURCE LINE # 346
0005C6 6D11           XRL      WR2,WR2
0005C8 7E043F80       MOV      WR0,#03F80H
0005CC 9A000000    E  ECALL    ?C?FPCMP3?
0005D0 401A           JC       ?C0083
                                                ; SOURCE LINE # 347
0005D2 7EE70000    R  MOV      WR28,n
0005D6 0BE4           INC      WR28,#01H
0005D8 7AE70000    R  MOV      n,WR28
                                                ; SOURCE LINE # 348
0005DC 7EE70000    R  MOV      WR28,i
0005E0 0BE4           INC      WR28,#01H
0005E2 7AE70000    R  MOV      i,WR28
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 19  

0005E6 BEE4000D       CMP      WR28,#0DH
0005EA 48CC           JSL      ?C0085
               ?C0083:
                                                ; SOURCE LINE # 349
0005EC BE740007       CMP      WR14,#07H
0005F0 2804           JLE      ?C0089
0005F2 7E740007       MOV      WR14,#07H
               ?C0089:
                                                ; SOURCE LINE # 350
0005F6 7DE7           MOV      WR28,WR14
0005F8 0BE5           INC      WR28,#02H
0005FA BEE70000    R  CMP      WR28,n
0005FE 0830           JSLE     ?C0090
000600 7AF70000    R  MOV      i,WR30
000604 801C           SJMP     ?C0093
               ?C0094:
000606 6D11           XRL      WR2,WR2
000608 7E044120       MOV      WR0,#04120H
00060C 7E1F0000    R  MOV      DR4,NUM
000610 9A000000    E  ECALL    ?C?FPMUL?
000614 7A1F0000    R  MOV      NUM,DR4
000618 7E370000    R  MOV      WR6,i
00061C 0B34           INC      WR6,#01H
00061E 7A370000    R  MOV      i,WR6
               ?C0093:
000622 7D37           MOV      WR6,WR14
000624 0B35           INC      WR6,#02H
000626 9E370000    R  SUB      WR6,n
00062A BE370000    R  CMP      WR6,i
00062E 38D6           JG       ?C0094
               ?C0090:
                                                ; SOURCE LINE # 351
000630 7E1F0000    R  MOV      DR4,NUM
000634 9A000000    E  ECALL    ?C?CASTF?
000638 7F71           MOV      DR28,DR4
;---- Variable 'num0' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 352
00063A 7ED70000    R  MOV      WR26,n
00063E BDD7           CMP      WR26,WR14
000640 3806           JG       ?C0101
000642 7DC7           MOV      WR24,WR14
000644 0BC4           INC      WR24,#01H
000646 8046           SJMP     ?C0112
               ?C0101:
000648 7DCD           MOV      WR24,WR26
00064A 1BC4           DEC      WR24,#01H
00064C 8040           SJMP     ?C0112
               ?C0099:
                                                ; SOURCE LINE # 354
00064E 7DCD           MOV      WR24,WR26
000650 1BC4           DEC      WR24,#01H
000652 BEC70000    R  CMP      WR24,i
000656 6826           JE       ?C0103
                                                ; SOURCE LINE # 356
000658 7EC4000A       MOV      WR24,#0AH
00065C 7F17           MOV      DR4,DR28
00065E 7D1C           MOV      WR2,WR24
000660 9A000000    E  ECALL    ?C?ULIDIV?
000664 7F10           MOV      DR4,DR0
000666 2E180030       ADD      DR4,#030H
00066A 7E270000    R  MOV      WR4,i
00066E 19720000    R  MOV      @WR4+tmp,R7
                                                ; SOURCE LINE # 357
000672 7F17           MOV      DR4,DR28
000674 7D1C           MOV      WR2,WR24
000676 9A000000    E  ECALL    ?C?ULIDIV?
C251 COMPILER V5.60.0,  LCD                                                                24/08/26  10:23:44  PAGE 20  

00067A 7F71           MOV      DR28,DR4
                                                ; SOURCE LINE # 358
00067C 800A           SJMP     ?C0096
               ?C0103:
                                                ; SOURCE LINE # 360
00067E 742E           MOV      A,#02EH          ; A=R11
000680 7EC70000    R  MOV      WR24,i
000684 19BC0000    R  MOV      @WR24+tmp,R11    ; A=R11
                                                ; SOURCE LINE # 361
               ?C0096:
000688 7EC70000    R  MOV      WR24,i
00068C 1BC4           DEC      WR24,#01H
               ?C0112:
00068E 7AC70000    R  MOV      i,WR24
               ?C0098:
000692 7EC70000    R  MOV      WR24,i
000696 BEC40000       CMP      WR24,#00H
00069A 18B2           JSG      ?C0099
                                                ; SOURCE LINE # 362
00069C E4             CLR      A                ; A=R11
00069D 19B70000    R  MOV      @WR14+tmp+0x2,R11
                                                ; SOURCE LINE # 363
0006A1 7CBC           MOV      R11,R12          ; A=R11
0006A3 7C7D           MOV      R7,R13
0006A5 7E000000    R  MOV      DR0,#WORD0 tmp
0006A9 9A000000    R  ECALL    LCD_P6x8Str?
                                                ; SOURCE LINE # 364
0006AD DA3B           POP      DR12
0006AF AA             ERET     
;       FUNCTION LCD_PrintFloat? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      1712     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------         36
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =      1036     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

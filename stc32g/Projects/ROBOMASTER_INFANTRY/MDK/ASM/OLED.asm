C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE OLED
OBJECT MODULE PLACED IN .\Objects\ASM\OLED.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\OLED.c XSMALL ROM(HUGE) BROWSE INCDIR(..
                    -\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTOR(0X1000)
                    - DEBUG CODE PRINT(.\ASM\OLED.asm) TABS(2) OBJECT(.\Objects\ASM\OLED.obj) 

stmt  level    source

    1          #include <math.h>
    2          #include <stdio.h>
    3          #include <stdarg.h>
    4          
    5          #include "Font.h" 
    6          #include "OLED.h" 
    7          #include "string.h"
    8          #include "CNU_PIE_I2C.h"
    9          
   10          void oled_init(void)
   11          {
   12   1        oled_wrcmd(0xae);
   13   1        oled_wrcmd(0x00);
   14   1        oled_wrcmd(0x10);
   15   1        oled_wrcmd(0x40);
   16   1        oled_wrcmd(0x81);
   17   1        oled_wrcmd(0xcf);
   18   1        oled_wrcmd(0xa0);
   19   1        oled_wrcmd(0xc0);
   20   1        oled_wrcmd(0xa6);
   21   1        oled_wrcmd(0xa8);
   22   1        oled_wrcmd(0x3f);
   23   1        oled_wrcmd(0xd3);
   24   1        oled_wrcmd(0x00);
   25   1        oled_wrcmd(0xd5);
   26   1        oled_wrcmd(0x80);
   27   1        oled_wrcmd(0xd9);
   28   1        oled_wrcmd(0xf1);
   29   1        oled_wrcmd(0xda);
   30   1        oled_wrcmd(0x12);
   31   1        oled_wrcmd(0xdb);
   32   1        oled_wrcmd(0x40);
   33   1        oled_wrcmd(0x20);
   34   1        oled_wrcmd(0x02);
   35   1        oled_wrcmd(0x8d);
   36   1        oled_wrcmd(0x14);
   37   1        oled_wrcmd(0xa4);
   38   1        oled_wrcmd(0xa6);
   39   1        oled_wrcmd(0xaf);
   40   1        oled_cls();
   41   1        oled_setpos(0,0);
   42   1      }
   43          
   44          void oled_wrcmd(unsigned char WrCmd) 
   45          {
   46   1        uint8_t cmd[2];
   47   1        cmd[0]=0x00;
   48   1        cmd[1]=WrCmd;
   49   1        I2C_WriteNbyte(OLED_ID,cmd[0],&cmd[1],1);
   50   1      }
   51          void oled_wrdata(unsigned char WrData) 
   52          {
   53   1        uint8_t dat[2];
   54   1        dat[0]=0x40;
   55   1        dat[1]=WrData;
   56   1        I2C_WriteNbyte(OLED_ID,dat[0],&dat[1],1);
   57   1      }
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 2   

   58          void oled_cls(void)
   59          {
   60   1        unsigned char i,n;
   61   1        for(i=0;i<8;i++)
   62   1        {
   63   2          oled_wrcmd((uint8_t)(0xb0+i));
   64   2          oled_wrcmd(0x00);
   65   2          oled_wrcmd(0x10);
   66   2          for(n=0;n<128;n++)
   67   2            oled_wrdata(0x00);
   68   2        }
   69   1      }
   70          void oled_cls_line(unsigned char i)
   71          {
   72   1        int n = 0;
   73   1          oled_wrcmd((uint8_t)(0xb0+i));
   74   1          oled_wrcmd(0x01);
   75   1          oled_wrcmd(0x10);
   76   1          for(n=0;n<128;n++)
   77   1           oled_wrdata(0x00);
   78   1      }
   79          
   80          void oled_setpos(unsigned char x,unsigned char y)
   81          {
   82   1          oled_wrcmd((uint8_t)(0xb0+y));
   83   1          oled_wrcmd(((x&0xf0)>>4)|0x10);
   84   1          oled_wrcmd((x&0x0f));
   85   1      }
   86          void oled_on(void)
   87          {
   88   1          oled_wrcmd(0x8d);
   89   1          oled_wrcmd(0x14);
   90   1          oled_wrcmd(0xaf);
   91   1      }
   92          void oled_off(void)
   93          {
   94   1          oled_wrcmd(0x8d);
   95   1          oled_wrcmd(0x10);
   96   1          oled_wrcmd(0xae);
   97   1      }
   98          void oled_p8x16_str(unsigned char x,unsigned char y,char ch[]) 
   99          {
  100   1        unsigned char c=0,i=0,j=0;
  101   1      
  102   1        while (ch[j]!='\0')
  103   1        {
  104   2          c =ch[j]-32;
  105   2          if(x>120){x=0;y++;}
  106   2          oled_setpos(x,y);
  107   2          for(i=0;i<8;i++)
  108   2            oled_wrdata(F8X16[c*16+i]);
  109   2          oled_setpos(x,(uint8_t)(y+1));
  110   2          for(i=0;i<8;i++)
  111   2            oled_wrdata(F8X16[c*16+i+8]);
  112   2          x+=8;
  113   2          j++;
  114   2        }
  115   1      }
  116          void oled_p6x8_str(unsigned char x,unsigned char y,char ch[]) 
  117          {
  118   1        unsigned char c=0,i=0,j=0;
  119   1        while (ch[j]!='\0')
  120   1        {
  121   2          c =ch[j]-32;
  122   2          if(x>120){x=0;y++;}
  123   2          oled_setpos(x,y);
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 3   

  124   2          for(i=0;i<6;i++)
  125   2          oled_wrdata(F6x8[c][i]);
  126   2          x+=6;
  127   2          j++;
  128   2        }
  129   1      }
  130          void oled_show_float(unsigned char x,unsigned char y,float num,unsigned int N) 
  131          {
  132   1       #define MAX_STR 12 
  133   1        char tmp[MAX_STR]={0};int n=3;
  134   1        float NUM=num;
  135   1        float _num=fabs(NUM);
  136   1        int i;
  137   1        uint32_t num0;
  138   1       if(NUM<0)
  139   1       {
  140   2         NUM=_num;
  141   2         tmp[0]='-';
  142   2       }
  143   1       else tmp[0]='+';
  144   1       for(i=0;i<MAX_STR+1;i++)
  145   1       {
  146   2         _num/=10;
  147   2         if(_num<1)break;
  148   2         else  n++;
  149   2       }
  150   1       if(N>7)N=7;
  151   1       if(((int)(N)+2-n)>0)for(i=0;i<(N+2-n);i++)NUM*=10;
  152   1       num0=(uint32_t)NUM;
  153   1       for(i=N>=n?(N+2-1):n-1;i>0;i--)
  154   1        {
  155   2          if(i!=n-1)
  156   2          {
  157   3            tmp[i]=(char)(num0%10+0x30);
  158   3            num0/=10;
  159   3          }
  160   2          else
  161   2            tmp[i]='.';
  162   2        }
  163   1        tmp[N+2]=0;
  164   1        oled_p6x8_str(x,y,tmp);
  165   1      }
  166          
  167          //////////////////////////////////////////////////////////////
  168          
  169          ///////////////////////////////////////////////////////////////
  170          
  171          #define MCP_IODIR   0x00 
  172          #define MCP_IPOL    0x02 
  173          #define MCP_GPINTEN 0x04 
  174          #define MCP_DEFVAL  0x06 
  175                                   
  176                                   
  177          #define MCP_INTCON  0x08 
  178          #define MCP_GPPU    0x0c 
  179          #define MCP_INTF    0x0e 
  180          #define MCP_INTCAP  0x10 
  181          #define MCP_GPIO    0x12 
  182          #define MCP_OLAT    0x14 
  183          
  184          #define MCP_IOCON   0X0a 
  185          
  186          
  187          #define CON_BANK    0       
  188          #define CON_MIRROR  0       
  189          #define CON_SEQOP   1       
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 4   

  190          #define CON_DISSLW  0       
  191          #define CON_HAEN    1       
  192          #define CON_ODR     0       
  193          #define CON_INTPOL  0       
  194          
  195          
  196          void writ_mcp_iic(unsigned char reg,unsigned char pbuf)
  197          {
  198   1        uint8_t cmd[2];
  199   1        cmd[0]=reg;
  200   1        cmd[1]=pbuf;
  201   1        I2C_WriteNbyte(MCP_ID,cmd[0],&cmd[1],1);
  202   1      }
  203          int read_mcp_iic(uint8_t reg,uint8_t *pbuf)
  204          {
  205   1        I2C_ReadNbyte(MCP_ID,reg,pbuf,1);
  206   1        return *pbuf;
  207   1      }
  208          
  209          void init_mcp23017(void)
  210          {
  211   1              writ_mcp_iic(MCP_IOCON,(CON_BANK  <<7)|       
  212   1                                     (CON_MIRROR<<6)|       
  213   1                                     (CON_SEQOP <<5)|       
  214   1                                     (CON_DISSLW<<4)|       
  215   1                                     (CON_HAEN  <<3)|       
  216   1                                     (CON_ODR   <<2)|       
  217   1                                     (CON_INTPOL<<1) );     
  218   1      }
  219          
  220          //0 out,1 in
  221          void gpio_iic_init(PORTn_23n17 port,unsigned char set)
  222          {
  223   1        if(port==portA)
  224   1        {
  225   2          writ_mcp_iic(MCP_IODIR,set); 
  226   2          writ_mcp_iic(MCP_GPIO,set^0xff);
  227   2        }
  228   1        else if(port==portB)
  229   1        {
  230   2          writ_mcp_iic(MCP_IODIR+0x01,set); 
  231   2          writ_mcp_iic(MCP_GPIO+0x01,set^0xff);
  232   2        }
  233   1      }
  234          
  235          int gpio_iic_set(PORTn_23n17 port,unsigned char set)
  236          {
  237   1        unsigned char pbuf;
  238   1        if(port==portA)
  239   1        {
  240   2          read_mcp_iic(MCP_IODIR,&pbuf);
  241   2          writ_mcp_iic(MCP_OLAT,(pbuf^0xff)&set);
  242   2          read_mcp_iic(MCP_OLAT,&pbuf);
  243   2        }
  244   1        else
  245   1        {
  246   2          read_mcp_iic(MCP_IODIR+0x01,&pbuf);
  247   2          writ_mcp_iic(MCP_OLAT+0x01,(pbuf^0xff)&set);
  248   2          read_mcp_iic(MCP_OLAT+0x01,&pbuf);
  249   2        } 
  250   1        if(pbuf==set)return 1;
  251   1        else return 0;
  252   1      }
  253          
  254          
  255          unsigned char gpio_iic_read(PORTn_23n17 port)
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 5   

  256          {
  257   1        unsigned char pbuf;
  258   1        if(port==portA)
  259   1        read_mcp_iic(MCP_GPIO,&pbuf);
  260   1        else
  261   1         read_mcp_iic(MCP_GPIO+0x01,&pbuf);
  262   1        return pbuf;
  263   1      }
  264          int Scan_Keyboard(void)              
  265          {
  266   1          if(gpio_iic_read(portA)==239)     //key7 A4
  267   1              return 9;
  268   1          if(gpio_iic_read(portA)==223)     //key4 A5
  269   1              return 4;
  270   1          if(gpio_iic_read(portA)==191)     //key4 A6
  271   1              return 10;
  272   1          if(gpio_iic_read(portA)==127)     //key4 A6
  273   1              return 12;
  274   1          if(gpio_iic_read(portB)==251)     //key1 B2
  275   1              return 1;
  276   1          if(gpio_iic_read(portB)==223)     //key2 B5
  277   1              return 2;
  278   1          if(gpio_iic_read(portB)==254)     //key3 B0
  279   1              return 3;
  280   1          if(gpio_iic_read(portB)==253)     //key5 B1
  281   1              return 5;
  282   1          if(gpio_iic_read(portB)==127)     //key6 B7
  283   1              return 6;
  284   1          if(gpio_iic_read(portB)==247)     //key7 B3
  285   1              return 7;
  286   1          if(gpio_iic_read(portB)==239)     //key7 B4
  287   1              return 8;
  288   1          if(gpio_iic_read(portB)==191)     //key4 A6
  289   1              return 11;
  290   1      
  291   1          return 0;
  292   1      }
  293          
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 6   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION oled_init? (BEGIN)
                                                ; SOURCE LINE # 10
                                                ; SOURCE LINE # 12
000000 74AE           MOV      A,#0AEH          ; A=R11
000002 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 13
000006 E4             CLR      A                ; A=R11
000007 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 14
00000B 7410           MOV      A,#010H          ; A=R11
00000D 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 15
000011 7440           MOV      A,#040H          ; A=R11
000013 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 16
000017 7481           MOV      A,#081H          ; A=R11
000019 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 17
00001D 74CF           MOV      A,#0CFH          ; A=R11
00001F 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 18
000023 74A0           MOV      A,#0A0H          ; A=R11
000025 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 19
000029 74C0           MOV      A,#0C0H          ; A=R11
00002B 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 20
00002F 74A6           MOV      A,#0A6H          ; A=R11
000031 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 21
000035 74A8           MOV      A,#0A8H          ; A=R11
000037 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 22
00003B 743F           MOV      A,#03FH          ; A=R11
00003D 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 23
000041 74D3           MOV      A,#0D3H          ; A=R11
000043 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 24
000047 E4             CLR      A                ; A=R11
000048 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 25
00004C 74D5           MOV      A,#0D5H          ; A=R11
00004E 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 26
000052 7480           MOV      A,#080H          ; A=R11
000054 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 27
000058 74D9           MOV      A,#0D9H          ; A=R11
00005A 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 28
00005E 74F1           MOV      A,#0F1H          ; A=R11
000060 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 29
000064 74DA           MOV      A,#0DAH          ; A=R11
000066 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 30
00006A 7412           MOV      A,#012H          ; A=R11
00006C 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 31
000070 74DB           MOV      A,#0DBH          ; A=R11
000072 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 32
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 7   

000076 7440           MOV      A,#040H          ; A=R11
000078 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 33
00007C 7420           MOV      A,#020H          ; A=R11
00007E 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 34
000082 7402           MOV      A,#02H           ; A=R11
000084 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 35
000088 748D           MOV      A,#08DH          ; A=R11
00008A 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 36
00008E 7414           MOV      A,#014H          ; A=R11
000090 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 37
000094 74A4           MOV      A,#0A4H          ; A=R11
000096 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 38
00009A 74A6           MOV      A,#0A6H          ; A=R11
00009C 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 39
0000A0 74AF           MOV      A,#0AFH          ; A=R11
0000A2 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 40
0000A6 9A000000    R  ECALL    oled_cls?
                                                ; SOURCE LINE # 41
0000AA E4             CLR      A                ; A=R11
0000AB 6C77           XRL      R7,R7
0000AD 8A000000    R  EJMP     oled_setpos?
;       FUNCTION oled_init? (END)

;       FUNCTION oled_wrcmd? (BEGIN)
                                                ; SOURCE LINE # 44
0000B1 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'WrCmd' assigned to Register 'R10' ----
                                                ; SOURCE LINE # 45
                                                ; SOURCE LINE # 47
0000B3 E4             CLR      A                ; A=R11
0000B4 7AB30000    R  MOV      cmd,R11          ; A=R11
                                                ; SOURCE LINE # 48
0000B8 7AA30000    R  MOV      cmd+1,R10
                                                ; SOURCE LINE # 49
0000BC 7E000000    R  MOV      DR0,#WORD0 cmd+1
0000C0 7E730000    R  MOV      R7,cmd
0000C4 7E6001         MOV      R6,#01H
0000C7 747A           MOV      A,#07AH          ; A=R11
0000C9 8A000000    E  EJMP     I2C_WriteNbyte??
;       FUNCTION oled_wrcmd? (END)

;       FUNCTION oled_wrdata? (BEGIN)
                                                ; SOURCE LINE # 51
0000CD 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'WrData' assigned to Register 'R10' ----
                                                ; SOURCE LINE # 52
                                                ; SOURCE LINE # 54
0000CF 7440           MOV      A,#040H          ; A=R11
0000D1 7AB30000    R  MOV      dat,R11          ; A=R11
                                                ; SOURCE LINE # 55
0000D5 7AA30000    R  MOV      dat+1,R10
                                                ; SOURCE LINE # 56
0000D9 7E000000    R  MOV      DR0,#WORD0 dat+1
0000DD 7E730000    R  MOV      R7,dat
0000E1 7E6001         MOV      R6,#01H
0000E4 747A           MOV      A,#07AH          ; A=R11
0000E6 8A000000    E  EJMP     I2C_WriteNbyte??
;       FUNCTION oled_wrdata? (END)
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 8   


;       FUNCTION oled_cls? (BEGIN)
                                                ; SOURCE LINE # 58
0000EA CA79           PUSH     WR14
                                                ; SOURCE LINE # 59
                                                ; SOURCE LINE # 61
0000EC 6CFF           XRL      R15,R15
;---- Variable 'i' assigned to Register 'R15' ----
               ?C0004:
                                                ; SOURCE LINE # 63
0000EE 7CBF           MOV      R11,R15          ; A=R11
0000F0 24B0           ADD      A,#0B0H          ; A=R11
0000F2 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 64
0000F6 E4             CLR      A                ; A=R11
0000F7 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 65
0000FB 7410           MOV      A,#010H          ; A=R11
0000FD 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 66
000101 6CEE           XRL      R14,R14
;---- Variable 'n' assigned to Register 'R14' ----
               ?C0009:
                                                ; SOURCE LINE # 67
000103 E4             CLR      A                ; A=R11
000104 9A000000    R  ECALL    oled_wrdata?
000108 0BE0           INC      R14,#01H
00010A BEE080         CMP      R14,#080H
00010D 78F4           JNE      ?C0009
                                                ; SOURCE LINE # 68
00010F 0BF0           INC      R15,#01H
000111 BEF008         CMP      R15,#08H
000114 40D8           JC       ?C0004
                                                ; SOURCE LINE # 69
000116 DA79           POP      WR14
000118 AA             ERET     
;       FUNCTION oled_cls? (END)

;       FUNCTION oled_cls_line? (BEGIN)
                                                ; SOURCE LINE # 70
000119 CA79           PUSH     WR14
;---- Variable 'i' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 71
                                                ; SOURCE LINE # 72
                                                ; SOURCE LINE # 73
00011B 24B0           ADD      A,#0B0H          ; A=R11
00011D 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 74
000121 7401           MOV      A,#01H           ; A=R11
000123 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 75
000127 7410           MOV      A,#010H          ; A=R11
000129 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 76
00012D 6D77           XRL      WR14,WR14
;---- Variable 'n' assigned to Register 'WR14' ----
               ?C0014:
                                                ; SOURCE LINE # 77
00012F E4             CLR      A                ; A=R11
000130 9A000000    R  ECALL    oled_wrdata?
000134 0B74           INC      WR14,#01H
000136 BE740080       CMP      WR14,#080H
00013A 48F3           JSL      ?C0014
                                                ; SOURCE LINE # 78
00013C DA79           POP      WR14
00013E AA             ERET     
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 9   

;       FUNCTION oled_cls_line? (END)

;       FUNCTION oled_setpos? (BEGIN)
                                                ; SOURCE LINE # 80
00013F CAF8           PUSH     R15
;---- Variable 'y' assigned to Register 'R10' ----
000141 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'x' assigned to Register 'R15' ----
                                                ; SOURCE LINE # 82
000143 7CB7           MOV      R11,R7           ; A=R11
000145 24B0           ADD      A,#0B0H          ; A=R11
000147 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 83
00014B 7CBF           MOV      R11,R15          ; A=R11
00014D 54F0           ANL      A,#0F0H          ; A=R11
00014F C4             SWAP     A                ; A=R11
000150 540F           ANL      A,#0FH           ; A=R11
000152 4410           ORL      A,#010H          ; A=R11
000154 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 84
000158 7CBF           MOV      R11,R15          ; A=R11
00015A 540F           ANL      A,#0FH           ; A=R11
00015C 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 85
000160 DAF8           POP      R15
000162 AA             ERET     
;       FUNCTION oled_setpos? (END)

;       FUNCTION oled_on? (BEGIN)
                                                ; SOURCE LINE # 86
                                                ; SOURCE LINE # 88
000163 748D           MOV      A,#08DH          ; A=R11
000165 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 89
000169 7414           MOV      A,#014H          ; A=R11
00016B 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 90
00016F 74AF           MOV      A,#0AFH          ; A=R11
000171 8A000000    R  EJMP     oled_wrcmd?
;       FUNCTION oled_on? (END)

;       FUNCTION oled_off? (BEGIN)
                                                ; SOURCE LINE # 92
                                                ; SOURCE LINE # 94
000175 748D           MOV      A,#08DH          ; A=R11
000177 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 95
00017B 7410           MOV      A,#010H          ; A=R11
00017D 9A000000    R  ECALL    oled_wrcmd?
                                                ; SOURCE LINE # 96
000181 74AE           MOV      A,#0AEH          ; A=R11
000183 8A000000    R  EJMP     oled_wrcmd?
;       FUNCTION oled_off? (END)

;       FUNCTION oled_p8x16_str? (BEGIN)
                                                ; SOURCE LINE # 98
000187 CA3B           PUSH     DR12
000189 7F30           MOV      DR12,DR0
;---- Variable 'ch' assigned to Register 'DR12' ----
00018B 7A730000    R  MOV      y,R7
00018F 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 99
                                                ; SOURCE LINE # 100
000193 E4             CLR      A                ; A=R11
000194 7AB30000    R  MOV      c,R11            ; A=R11
000198 7AB30000    R  MOV      i,R11            ; A=R11
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 10  

                                                ; SOURCE LINE # 102
00019C 020000      R  LJMP     ?C0093
               ?C0018:
                                                ; SOURCE LINE # 104
00019F 7E730000    R  MOV      R7,j
0001A3 0A37           MOVZ     WR6,R7
0001A5 2D37           ADD      WR6,WR14
0001A7 7D26           MOV      WR4,WR12
0001A9 7E1B70         MOV      R7,@DR4
0001AC 1A37           MOVS     WR6,R7
0001AE 9E340020       SUB      WR6,#020H
0001B2 7A730000    R  MOV      c,R7
                                                ; SOURCE LINE # 105
0001B6 7E730000    R  MOV      R7,x
0001BA BE7078         CMP      R7,#078H
0001BD 280E           JLE      ?C0020
0001BF E4             CLR      A                ; A=R11
0001C0 7AB30000    R  MOV      x,R11            ; A=R11
0001C4 7EB30000    R  MOV      R11,y            ; A=R11
0001C8 04             INC      A                ; A=R11
0001C9 7AB30000    R  MOV      y,R11            ; A=R11
               ?C0020:
                                                ; SOURCE LINE # 106
0001CD 7EB30000    R  MOV      R11,x            ; A=R11
0001D1 7E730000    R  MOV      R7,y
0001D5 9A000000    R  ECALL    oled_setpos?
                                                ; SOURCE LINE # 107
0001D9 E4             CLR      A                ; A=R11
0001DA 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0024:
                                                ; SOURCE LINE # 108
0001DE 7E730000    R  MOV      R7,c
0001E2 0A17           MOVZ     WR2,R7
0001E4 6D00           XRL      WR0,WR0
0001E6 7404           MOV      A,#04H           ; A=R11
               ?C0091:
0001E8 2F00           ADD      DR0,DR0
0001EA 14             DEC      A                ; A=R11
0001EB 78FB           JNE      ?C0091
0001ED 7E730000    R  MOV      R7,i
0001F1 0A37           MOVZ     WR6,R7
0001F3 6D22           XRL      WR4,WR4
0001F5 2F10           ADD      DR4,DR0
0001F7 2E240000    E  ADD      WR4,#WORD2 F8X16
0001FB 2E180000    E  ADD      DR4,#WORD0 F8X16
0001FF 7E1BB0         MOV      R11,@DR4         ; A=R11
000202 9A000000    R  ECALL    oled_wrdata?
000206 7EB30000    R  MOV      R11,i            ; A=R11
00020A 04             INC      A                ; A=R11
00020B 7AB30000    R  MOV      i,R11            ; A=R11
00020F B408CC         CJNE     A,#08H,?C0024    ; A=R11
                                                ; SOURCE LINE # 109
000212 7EB30000    R  MOV      R11,x            ; A=R11
000216 7E730000    R  MOV      R7,y
00021A 0B70           INC      R7,#01H
00021C 9A000000    R  ECALL    oled_setpos?
                                                ; SOURCE LINE # 110
000220 E4             CLR      A                ; A=R11
000221 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0029:
                                                ; SOURCE LINE # 111
000225 7E730000    R  MOV      R7,c
000229 0A17           MOVZ     WR2,R7
00022B 6D00           XRL      WR0,WR0
00022D 7404           MOV      A,#04H           ; A=R11
               ?C0092:
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 11  

00022F 2F00           ADD      DR0,DR0
000231 14             DEC      A                ; A=R11
000232 78FB           JNE      ?C0092
000234 7E730000    R  MOV      R7,i
000238 0A37           MOVZ     WR6,R7
00023A 6D22           XRL      WR4,WR4
00023C 2F10           ADD      DR4,DR0
00023E 2E240000    E  ADD      WR4,#WORD2 F8X16+8
000242 2E180000    E  ADD      DR4,#WORD0 F8X16+8
000246 7E1BB0         MOV      R11,@DR4         ; A=R11
000249 9A000000    R  ECALL    oled_wrdata?
00024D 7EB30000    R  MOV      R11,i            ; A=R11
000251 04             INC      A                ; A=R11
000252 7AB30000    R  MOV      i,R11            ; A=R11
000256 B408CC         CJNE     A,#08H,?C0029    ; A=R11
                                                ; SOURCE LINE # 112
000259 7EB30000    R  MOV      R11,x            ; A=R11
00025D 2408           ADD      A,#08H           ; A=R11
00025F 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 113
000263 7EB30000    R  MOV      R11,j            ; A=R11
000267 04             INC      A                ; A=R11
               ?C0093:
000268 7AB30000    R  MOV      j,R11            ; A=R11
                                                ; SOURCE LINE # 114
               ?C0016:
00026C 7E730000    R  MOV      R7,j
000270 0A37           MOVZ     WR6,R7
000272 2D37           ADD      WR6,WR14
000274 7D26           MOV      WR4,WR12
000276 7E1BB0         MOV      R11,@DR4         ; A=R11
000279 6003        R  JZ       $ + 5H
00027B 020000      R  LJMP     ?C0018
                                                ; SOURCE LINE # 115
00027E DA3B           POP      DR12
000280 AA             ERET     
;       FUNCTION oled_p8x16_str? (END)

;       FUNCTION oled_p6x8_str? (BEGIN)
                                                ; SOURCE LINE # 116
000281 CA3B           PUSH     DR12
000283 7F30           MOV      DR12,DR0
;---- Variable 'ch' assigned to Register 'DR12' ----
000285 7A730000    R  MOV      y,R7
000289 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 117
                                                ; SOURCE LINE # 118
00028D E4             CLR      A                ; A=R11
00028E 7AB30000    R  MOV      c,R11            ; A=R11
000292 7AB30000    R  MOV      i,R11            ; A=R11
                                                ; SOURCE LINE # 119
000296 020000      R  LJMP     ?C0094
               ?C0033:
                                                ; SOURCE LINE # 121
000299 7E730000    R  MOV      R7,j
00029D 0A37           MOVZ     WR6,R7
00029F 2D37           ADD      WR6,WR14
0002A1 7D26           MOV      WR4,WR12
0002A3 7E1B70         MOV      R7,@DR4
0002A6 1A37           MOVS     WR6,R7
0002A8 9E340020       SUB      WR6,#020H
0002AC 7A730000    R  MOV      c,R7
                                                ; SOURCE LINE # 122
0002B0 7E730000    R  MOV      R7,x
0002B4 BE7078         CMP      R7,#078H
0002B7 280E           JLE      ?C0035
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 12  

0002B9 E4             CLR      A                ; A=R11
0002BA 7AB30000    R  MOV      x,R11            ; A=R11
0002BE 7EB30000    R  MOV      R11,y            ; A=R11
0002C2 04             INC      A                ; A=R11
0002C3 7AB30000    R  MOV      y,R11            ; A=R11
               ?C0035:
                                                ; SOURCE LINE # 123
0002C7 7EB30000    R  MOV      R11,x            ; A=R11
0002CB 7E730000    R  MOV      R7,y
0002CF 9A000000    R  ECALL    oled_setpos?
                                                ; SOURCE LINE # 124
0002D3 E4             CLR      A                ; A=R11
0002D4 7AB30000    R  MOV      i,R11            ; A=R11
               ?C0039:
                                                ; SOURCE LINE # 125
0002D8 7E730000    R  MOV      R7,c
0002DC 0A37           MOVZ     WR6,R7
0002DE 6D22           XRL      WR4,WR4
0002E0 7E140006       MOV      WR2,#06H
0002E4 9A000000    E  ECALL    ?C?LIMUL?
0002E8 7E330000    R  MOV      R3,i
0002EC 0A13           MOVZ     WR2,R3
0002EE 6D00           XRL      WR0,WR0
0002F0 2F10           ADD      DR4,DR0
0002F2 2E240000    E  ADD      WR4,#WORD2 F6x8
0002F6 2E180000    E  ADD      DR4,#WORD0 F6x8
0002FA 7E1BB0         MOV      R11,@DR4         ; A=R11
0002FD 9A000000    R  ECALL    oled_wrdata?
000301 7EB30000    R  MOV      R11,i            ; A=R11
000305 04             INC      A                ; A=R11
000306 7AB30000    R  MOV      i,R11            ; A=R11
00030A B406CB         CJNE     A,#06H,?C0039    ; A=R11
                                                ; SOURCE LINE # 126
00030D 7EB30000    R  MOV      R11,x            ; A=R11
000311 2406           ADD      A,#06H           ; A=R11
000313 7AB30000    R  MOV      x,R11            ; A=R11
                                                ; SOURCE LINE # 127
000317 7EB30000    R  MOV      R11,j            ; A=R11
00031B 04             INC      A                ; A=R11
               ?C0094:
00031C 7AB30000    R  MOV      j,R11            ; A=R11
                                                ; SOURCE LINE # 128
               ?C0031:
000320 7E730000    R  MOV      R7,j
000324 0A37           MOVZ     WR6,R7
000326 2D37           ADD      WR6,WR14
000328 7D26           MOV      WR4,WR12
00032A 7E1BB0         MOV      R11,@DR4         ; A=R11
00032D 6003        R  JZ       $ + 5H
00032F 020000      R  LJMP     ?C0033
                                                ; SOURCE LINE # 129
000332 DA3B           POP      DR12
000334 AA             ERET     
;       FUNCTION oled_p6x8_str? (END)

;       FUNCTION oled_show_float? (BEGIN)
                                                ; SOURCE LINE # 130
000335 CA3B           PUSH     DR12
000337 7D72           MOV      WR14,WR4
;---- Variable 'N' assigned to Register 'WR14' ----
000339 7F70           MOV      DR28,DR0
;---- Variable 'num' assigned to Register 'DR28' ----
00033B 7CD7           MOV      R13,R7
;---- Variable 'y' assigned to Register 'R13' ----
00033D 7CCB           MOV      R12,R11          ; A=R11
;---- Variable 'x' assigned to Register 'R12' ----
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 13  

                                                ; SOURCE LINE # 131
                                                ; SOURCE LINE # 133
00033F 7E340000    R  MOV      WR6,#WORD0 ?tpl?0001
000343 7E240000    R  MOV      WR4,#WORD2 ?tpl?0001
000347 7E140000    R  MOV      WR2,#WORD0 tmp
00034B 740C           MOV      A,#0CH           ; A=R11
00034D 9A000000    E  ECALL    ?C?BMOVENP8?
000351 7E340003       MOV      WR6,#03H
000355 7A370000    R  MOV      n,WR6
                                                ; SOURCE LINE # 134
000359 7A7F0000    R  MOV      NUM,DR28
                                                ; SOURCE LINE # 135
00035D 7F17           MOV      DR4,DR28
00035F 9A000000    E  ECALL    fabs??
000363 7F61           MOV      DR24,DR4
;---- Variable '_num' assigned to Register 'DR24' ----
                                                ; SOURCE LINE # 138
000365 9F00           SUB      DR0,DR0
000367 7E1F0000    R  MOV      DR4,NUM
00036B 9A000000    E  ECALL    ?C?FPCMP3?
00036F 5008           JNC      ?C0041
                                                ; SOURCE LINE # 140
000371 7A6F0000    R  MOV      NUM,DR24
                                                ; SOURCE LINE # 141
000375 742D           MOV      A,#02DH          ; A=R11
                                                ; SOURCE LINE # 142
000377 8002           SJMP     ?C0095
               ?C0041:
                                                ; SOURCE LINE # 143
000379 742B           MOV      A,#02BH          ; A=R11
               ?C0095:
00037B 7AB30000    R  MOV      tmp,R11          ; A=R11
                                                ; SOURCE LINE # 144
00037F 6DFF           XRL      WR30,WR30
000381 7AF70000    R  MOV      i,WR30
               ?C0046:
                                                ; SOURCE LINE # 146
000385 6D11           XRL      WR2,WR2
000387 7E044120       MOV      WR0,#04120H
00038B 7F16           MOV      DR4,DR24
00038D 9A000000    E  ECALL    ?C?FPDIV?
000391 7F61           MOV      DR24,DR4
                                                ; SOURCE LINE # 147
000393 6D11           XRL      WR2,WR2
000395 7E043F80       MOV      WR0,#03F80H
000399 9A000000    E  ECALL    ?C?FPCMP3?
00039D 401A           JC       ?C0044
                                                ; SOURCE LINE # 148
00039F 7EE70000    R  MOV      WR28,n
0003A3 0BE4           INC      WR28,#01H
0003A5 7AE70000    R  MOV      n,WR28
                                                ; SOURCE LINE # 149
0003A9 7EE70000    R  MOV      WR28,i
0003AD 0BE4           INC      WR28,#01H
0003AF 7AE70000    R  MOV      i,WR28
0003B3 BEE4000D       CMP      WR28,#0DH
0003B7 48CC           JSL      ?C0046
               ?C0044:
                                                ; SOURCE LINE # 150
0003B9 BE740007       CMP      WR14,#07H
0003BD 2804           JLE      ?C0050
0003BF 7E740007       MOV      WR14,#07H
               ?C0050:
                                                ; SOURCE LINE # 151
0003C3 7DE7           MOV      WR28,WR14
0003C5 0BE5           INC      WR28,#02H
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 14  

0003C7 BEE70000    R  CMP      WR28,n
0003CB 0830           JSLE     ?C0051
0003CD 7AF70000    R  MOV      i,WR30
0003D1 801C           SJMP     ?C0054
               ?C0055:
0003D3 6D11           XRL      WR2,WR2
0003D5 7E044120       MOV      WR0,#04120H
0003D9 7E1F0000    R  MOV      DR4,NUM
0003DD 9A000000    E  ECALL    ?C?FPMUL?
0003E1 7A1F0000    R  MOV      NUM,DR4
0003E5 7E370000    R  MOV      WR6,i
0003E9 0B34           INC      WR6,#01H
0003EB 7A370000    R  MOV      i,WR6
               ?C0054:
0003EF 7D37           MOV      WR6,WR14
0003F1 0B35           INC      WR6,#02H
0003F3 9E370000    R  SUB      WR6,n
0003F7 BE370000    R  CMP      WR6,i
0003FB 38D6           JG       ?C0055
               ?C0051:
                                                ; SOURCE LINE # 152
0003FD 7E1F0000    R  MOV      DR4,NUM
000401 9A000000    E  ECALL    ?C?CASTF?
000405 7F71           MOV      DR28,DR4
;---- Variable 'num0' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 153
000407 7ED70000    R  MOV      WR26,n
00040B BDD7           CMP      WR26,WR14
00040D 3806           JG       ?C0062
00040F 7DC7           MOV      WR24,WR14
000411 0BC4           INC      WR24,#01H
000413 8046           SJMP     ?C0096
               ?C0062:
000415 7DCD           MOV      WR24,WR26
000417 1BC4           DEC      WR24,#01H
000419 8040           SJMP     ?C0096
               ?C0060:
                                                ; SOURCE LINE # 155
00041B 7DCD           MOV      WR24,WR26
00041D 1BC4           DEC      WR24,#01H
00041F BEC70000    R  CMP      WR24,i
000423 6826           JE       ?C0064
                                                ; SOURCE LINE # 157
000425 7EC4000A       MOV      WR24,#0AH
000429 7F17           MOV      DR4,DR28
00042B 7D1C           MOV      WR2,WR24
00042D 9A000000    E  ECALL    ?C?ULIDIV?
000431 7F10           MOV      DR4,DR0
000433 2E180030       ADD      DR4,#030H
000437 7E270000    R  MOV      WR4,i
00043B 19720000    R  MOV      @WR4+tmp,R7
                                                ; SOURCE LINE # 158
00043F 7F17           MOV      DR4,DR28
000441 7D1C           MOV      WR2,WR24
000443 9A000000    E  ECALL    ?C?ULIDIV?
000447 7F71           MOV      DR28,DR4
                                                ; SOURCE LINE # 159
000449 800A           SJMP     ?C0057
               ?C0064:
                                                ; SOURCE LINE # 161
00044B 742E           MOV      A,#02EH          ; A=R11
00044D 7EC70000    R  MOV      WR24,i
000451 19BC0000    R  MOV      @WR24+tmp,R11    ; A=R11
                                                ; SOURCE LINE # 162
               ?C0057:
000455 7EC70000    R  MOV      WR24,i
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 15  

000459 1BC4           DEC      WR24,#01H
               ?C0096:
00045B 7AC70000    R  MOV      i,WR24
               ?C0059:
00045F 7EC70000    R  MOV      WR24,i
000463 BEC40000       CMP      WR24,#00H
000467 18B2           JSG      ?C0060
                                                ; SOURCE LINE # 163
000469 E4             CLR      A                ; A=R11
00046A 19B70000    R  MOV      @WR14+tmp+0x2,R11
                                                ; SOURCE LINE # 164
00046E 7CBC           MOV      R11,R12          ; A=R11
000470 7C7D           MOV      R7,R13
000472 7E000000    R  MOV      DR0,#WORD0 tmp
000476 9A000000    R  ECALL    oled_p6x8_str?
                                                ; SOURCE LINE # 165
00047A DA3B           POP      DR12
00047C AA             ERET     
;       FUNCTION oled_show_float? (END)

;       FUNCTION writ_mcp_iic? (BEGIN)
                                                ; SOURCE LINE # 196
00047D 7C67           MOV      R6,R7
;---- Variable 'pbuf' assigned to Register 'R6' ----
;---- Variable 'reg' assigned to Register 'R7' ----
                                                ; SOURCE LINE # 197
                                                ; SOURCE LINE # 199
00047F 7AB30000    R  MOV      cmd,R11          ; A=R11
                                                ; SOURCE LINE # 200
000483 7A730000    R  MOV      cmd+1,R7
                                                ; SOURCE LINE # 201
000487 7E000000    R  MOV      DR0,#WORD0 cmd+1
00048B 7E730000    R  MOV      R7,cmd
00048F 7E6001         MOV      R6,#01H
000492 7442           MOV      A,#042H          ; A=R11
000494 8A000000    E  EJMP     I2C_WriteNbyte??
;       FUNCTION writ_mcp_iic? (END)

;       FUNCTION read_mcp_iic? (BEGIN)
                                                ; SOURCE LINE # 203
000498 CA3B           PUSH     DR12
00049A 7F30           MOV      DR12,DR0
;---- Variable 'pbuf' assigned to Register 'DR12' ----
00049C 7CAB           MOV      R10,R11          ; A=R11
;---- Variable 'reg' assigned to Register 'R10' ----
                                                ; SOURCE LINE # 205
00049E 7442           MOV      A,#042H          ; A=R11
0004A0 7C7A           MOV      R7,R10
0004A2 7E6001         MOV      R6,#01H
0004A5 9A000000    E  ECALL    I2C_ReadNbyte?
                                                ; SOURCE LINE # 206
0004A9 7E3B70         MOV      R7,@DR12
0004AC 0A37           MOVZ     WR6,R7
                                                ; SOURCE LINE # 207
0004AE DA3B           POP      DR12
0004B0 AA             ERET     
;       FUNCTION read_mcp_iic? (END)

;       FUNCTION init_mcp23017? (BEGIN)
                                                ; SOURCE LINE # 209
                                                ; SOURCE LINE # 211
0004B1 740A           MOV      A,#0AH           ; A=R11
0004B3 7E7028         MOV      R7,#028H
0004B6 8A000000    R  EJMP     writ_mcp_iic?
;       FUNCTION init_mcp23017? (END)

C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 16  

;       FUNCTION gpio_iic_init? (BEGIN)
                                                ; SOURCE LINE # 221
0004BA CAF8           PUSH     R15
0004BC 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'set' assigned to Register 'R15' ----
;---- Variable 'port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 223
0004BE 4D33           ORL      WR6,WR6
0004C0 780B           JNE      ?C0067
                                                ; SOURCE LINE # 225
0004C2 E4             CLR      A                ; A=R11
0004C3 7C7F           MOV      R7,R15
0004C5 9A000000    R  ECALL    writ_mcp_iic?
                                                ; SOURCE LINE # 226
0004C9 7412           MOV      A,#012H          ; A=R11
                                                ; SOURCE LINE # 227
0004CB 8010           SJMP     ?C0097
               ?C0067:
                                                ; SOURCE LINE # 228
0004CD BE340001       CMP      WR6,#01H
0004D1 7813           JNE      ?C0068
                                                ; SOURCE LINE # 230
0004D3 7401           MOV      A,#01H           ; A=R11
0004D5 7C7F           MOV      R7,R15
0004D7 9A000000    R  ECALL    writ_mcp_iic?
                                                ; SOURCE LINE # 231
0004DB 7413           MOV      A,#013H          ; A=R11
               ?C0097:
0004DD 7C7F           MOV      R7,R15
0004DF 6E70FF         XRL      R7,#0FFH
0004E2 9A000000    R  ECALL    writ_mcp_iic?
                                                ; SOURCE LINE # 232
               ?C0068:
0004E6 DAF8           POP      R15
0004E8 AA             ERET     
;       FUNCTION gpio_iic_init? (END)

;       FUNCTION gpio_iic_set? (BEGIN)
                                                ; SOURCE LINE # 235
0004E9 CAF8           PUSH     R15
0004EB 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'set' assigned to Register 'R15' ----
;---- Variable 'port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 236
                                                ; SOURCE LINE # 238
0004ED 4D33           ORL      WR6,WR6
0004EF 781C           JNE      ?C0070
                                                ; SOURCE LINE # 240
0004F1 E4             CLR      A                ; A=R11
0004F2 7E000000    R  MOV      DR0,#WORD0 pbuf
0004F6 9A000000    R  ECALL    read_mcp_iic?
                                                ; SOURCE LINE # 241
0004FA 7414           MOV      A,#014H          ; A=R11
0004FC 7E730000    R  MOV      R7,pbuf
000500 6E70FF         XRL      R7,#0FFH
000503 5C7F           ANL      R7,R15
000505 9A000000    R  ECALL    writ_mcp_iic?
                                                ; SOURCE LINE # 242
000509 7414           MOV      A,#014H          ; A=R11
                                                ; SOURCE LINE # 243
00050B 801B           SJMP     ?C0098
               ?C0070:
                                                ; SOURCE LINE # 246
00050D 7401           MOV      A,#01H           ; A=R11
00050F 7E000000    R  MOV      DR0,#WORD0 pbuf
000513 9A000000    R  ECALL    read_mcp_iic?
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 17  

                                                ; SOURCE LINE # 247
000517 7415           MOV      A,#015H          ; A=R11
000519 7E730000    R  MOV      R7,pbuf
00051D 6E70FF         XRL      R7,#0FFH
000520 5C7F           ANL      R7,R15
000522 9A000000    R  ECALL    writ_mcp_iic?
                                                ; SOURCE LINE # 248
000526 7415           MOV      A,#015H          ; A=R11
               ?C0098:
000528 7E000000    R  MOV      DR0,#WORD0 pbuf
00052C 9A000000    R  ECALL    read_mcp_iic?
                                                ; SOURCE LINE # 249
                                                ; SOURCE LINE # 250
000530 BEF30000    R  CMP      R15,pbuf
000534 7806           JNE      ?C0072
000536 7E340001       MOV      WR6,#01H
00053A 8002           SJMP     ?C0073
               ?C0072:
                                                ; SOURCE LINE # 251
00053C 6D33           XRL      WR6,WR6
                                                ; SOURCE LINE # 252
               ?C0073:
00053E DAF8           POP      R15
000540 AA             ERET     
;       FUNCTION gpio_iic_set? (END)

;       FUNCTION gpio_iic_read? (BEGIN)
                                                ; SOURCE LINE # 255
;---- Variable 'port' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 256
                                                ; SOURCE LINE # 258
000541 4D33           ORL      WR6,WR6
000543 7804           JNE      ?C0075
                                                ; SOURCE LINE # 259
000545 7412           MOV      A,#012H          ; A=R11
000547 8002           SJMP     ?C0099
               ?C0075:
                                                ; SOURCE LINE # 261
000549 7413           MOV      A,#013H          ; A=R11
               ?C0099:
00054B 7E000000    R  MOV      DR0,#WORD0 pbuf
00054F 9A000000    R  ECALL    read_mcp_iic?
                                                ; SOURCE LINE # 262
000553 7EB30000    R  MOV      R11,pbuf         ; A=R11
                                                ; SOURCE LINE # 263
000557 AA             ERET     
;       FUNCTION gpio_iic_read? (END)

;       FUNCTION Scan_Keyboard? (BEGIN)
                                                ; SOURCE LINE # 264
                                                ; SOURCE LINE # 266
000558 6D33           XRL      WR6,WR6
00055A 9A000000    R  ECALL    gpio_iic_read?
00055E B4EF05         CJNE     A,#0EFH,?C0078   ; A=R11
                                                ; SOURCE LINE # 267
000561 7E340009       MOV      WR6,#09H
000565 AA             ERET     
               ?C0078:
                                                ; SOURCE LINE # 268
000566 6D33           XRL      WR6,WR6
000568 9A000000    R  ECALL    gpio_iic_read?
00056C B4DF05         CJNE     A,#0DFH,?C0080   ; A=R11
                                                ; SOURCE LINE # 269
00056F 7E340004       MOV      WR6,#04H
000573 AA             ERET     
               ?C0080:
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 18  

                                                ; SOURCE LINE # 270
000574 6D33           XRL      WR6,WR6
000576 9A000000    R  ECALL    gpio_iic_read?
00057A B4BF05         CJNE     A,#0BFH,?C0081   ; A=R11
                                                ; SOURCE LINE # 271
00057D 7E34000A       MOV      WR6,#0AH
000581 AA             ERET     
               ?C0081:
                                                ; SOURCE LINE # 272
000582 6D33           XRL      WR6,WR6
000584 9A000000    R  ECALL    gpio_iic_read?
000588 B47F05         CJNE     A,#07FH,?C0082   ; A=R11
                                                ; SOURCE LINE # 273
00058B 7E34000C       MOV      WR6,#0CH
00058F AA             ERET     
               ?C0082:
                                                ; SOURCE LINE # 274
000590 7E340001       MOV      WR6,#01H
000594 9A000000    R  ECALL    gpio_iic_read?
000598 B4FB05         CJNE     A,#0FBH,?C0083   ; A=R11
                                                ; SOURCE LINE # 275
00059B 7E340001       MOV      WR6,#01H
00059F AA             ERET     
               ?C0083:
                                                ; SOURCE LINE # 276
0005A0 7E340001       MOV      WR6,#01H
0005A4 9A000000    R  ECALL    gpio_iic_read?
0005A8 B4DF05         CJNE     A,#0DFH,?C0084   ; A=R11
                                                ; SOURCE LINE # 277
0005AB 7E340002       MOV      WR6,#02H
0005AF AA             ERET     
               ?C0084:
                                                ; SOURCE LINE # 278
0005B0 7E340001       MOV      WR6,#01H
0005B4 9A000000    R  ECALL    gpio_iic_read?
0005B8 B4FE05         CJNE     A,#0FEH,?C0085   ; A=R11
                                                ; SOURCE LINE # 279
0005BB 7E340003       MOV      WR6,#03H
0005BF AA             ERET     
               ?C0085:
                                                ; SOURCE LINE # 280
0005C0 7E340001       MOV      WR6,#01H
0005C4 9A000000    R  ECALL    gpio_iic_read?
0005C8 B4FD05         CJNE     A,#0FDH,?C0086   ; A=R11
                                                ; SOURCE LINE # 281
0005CB 7E340005       MOV      WR6,#05H
0005CF AA             ERET     
               ?C0086:
                                                ; SOURCE LINE # 282
0005D0 7E340001       MOV      WR6,#01H
0005D4 9A000000    R  ECALL    gpio_iic_read?
0005D8 B47F05         CJNE     A,#07FH,?C0087   ; A=R11
                                                ; SOURCE LINE # 283
0005DB 7E340006       MOV      WR6,#06H
0005DF AA             ERET     
               ?C0087:
                                                ; SOURCE LINE # 284
0005E0 7E340001       MOV      WR6,#01H
0005E4 9A000000    R  ECALL    gpio_iic_read?
0005E8 B4F705         CJNE     A,#0F7H,?C0088   ; A=R11
                                                ; SOURCE LINE # 285
0005EB 7E340007       MOV      WR6,#07H
0005EF AA             ERET     
               ?C0088:
                                                ; SOURCE LINE # 286
0005F0 7E340001       MOV      WR6,#01H
C251 COMPILER V5.60.0,  OLED                                                               24/08/26  10:23:43  PAGE 19  

0005F4 9A000000    R  ECALL    gpio_iic_read?
0005F8 B4EF05         CJNE     A,#0EFH,?C0089   ; A=R11
                                                ; SOURCE LINE # 287
0005FB 7E340008       MOV      WR6,#08H
0005FF AA             ERET     
               ?C0089:
                                                ; SOURCE LINE # 288
000600 7E340001       MOV      WR6,#01H
000604 9A000000    R  ECALL    gpio_iic_read?
000608 B4BF05         CJNE     A,#0BFH,?C0090   ; A=R11
                                                ; SOURCE LINE # 289
00060B 7E34000B       MOV      WR6,#0BH
00060F AA             ERET     
               ?C0090:
                                                ; SOURCE LINE # 291
000610 6D33           XRL      WR6,WR6
                                                ; SOURCE LINE # 292
000612 AA             ERET     
;       FUNCTION Scan_Keyboard? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =      1555     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------         38
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

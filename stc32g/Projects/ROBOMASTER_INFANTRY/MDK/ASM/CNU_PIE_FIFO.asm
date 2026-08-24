C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE CNU_PIE_FIFO
OBJECT MODULE PLACED IN .\Objects\ASM\CNU_PIE_FIFO.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\deivers\src\CNU_PIE_FIFO.c XSMALL ROM(HUGE) BROWSE 
                    -INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECTO
                    -R(0X1000) DEBUG CODE PRINT(.\ASM\CNU_PIE_FIFO.asm) TABS(2) OBJECT(.\Objects\ASM\CNU_PIE_FIFO.obj) 

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
   12           * @file       CNU_PIE_FIFO.c
   13           * @brief      FIFO
   14           * @author     胖胖
   15           * @version    v1.0
   16           * @note       NULL
   17           * @date       2023-07-26
   18           ********************************************************************************************************
             -************/
   19           #include "CNU_PIE_FIFO.h"
   20           
   21          
   22          //-------------------------------------------------------------------------------------------------------
             -------------
   23          // @brief       FIFO 初始化 挂载对应缓冲区
   24          // @param       *fifo           FIFO 对象指针
   25          // @param       *buffer_addr    要挂载的缓冲区
   26          // @param       size            缓冲区大小
   27          // @return      fifo_state_enum 操作状态
   28          // Sample usage:
   29          //-------------------------------------------------------------------------------------------------------
             -------------
   30          fifo_state_enum fifo_init (fifo_struct *fifo, uint8_t *buffer_addr, uint32_t size)
   31          {
   32   1          if(buffer_addr == NULL)
   33   1              return FIFO_BUFFER_NULL;
   34   1          fifo->buffer    = buffer_addr;
   35   1          fifo->head      = 0;
   36   1          fifo->end       = 0;
   37   1          fifo->size      = size;
   38   1          fifo->max       = size;
   39   1          return FIFO_SUCCESS;
   40   1      }
   41          
   42          //-------------------------------------------------------------------------------------------------------
             -------------
   43          // @brief       FIFO 头指针位移
   44          // @param       *fifo           FIFO 对象指针
   45          // @param       offset          偏移量
   46          // @return      void
   47          // Sample usage:
   48          //-------------------------------------------------------------------------------------------------------
             -------------
   49          void fifo_head_offset (fifo_struct *fifo, uint32_t offset)
   50          {
   51   1          fifo->head += offset;
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 2   

   52   1      
   53   1          while(fifo->max <= fifo->head)                                              // 如果范围超过则减缓冲区
             -大小 直到小于最大缓冲区大小
   54   1          {
   55   2              fifo->head -= fifo->max;
   56   2          }
   57   1      }
   58          
   59          //-------------------------------------------------------------------------------------------------------
             -------------
   60          // @brief       FIFO 尾指针位移
   61          // @param       *fifo           FIFO 对象指针
   62          // @param       offset          偏移量
   63          // @return      void
   64          // Sample usage:
   65          //-------------------------------------------------------------------------------------------------------
             -------------
   66          void fifo_end_offset (fifo_struct *fifo, uint32_t offset)
   67          {
   68   1          fifo->end += offset;
   69   1      
   70   1          while(fifo->max <= fifo->end)                                               // 如果范围超过则减缓冲区
             -大小 直到小于最大缓冲区大小
   71   1          {
   72   2              fifo->end -= fifo->max;
   73   2          }
   74   1      }
   75          
   76          //-------------------------------------------------------------------------------------------------------
             -------------
   77          // @brief       FIFO 重置缓冲器
   78          // @param       *fifo           FIFO 对象指针
   79          // @return      void
   80          // Sample usage:
   81          //-------------------------------------------------------------------------------------------------------
             -------------
   82          void fifo_clear (fifo_struct *fifo)
   83          {
   84   1          fifo->head      = 0;
   85   1          fifo->end       = 0;
   86   1          fifo->size      = fifo->max;
   87   1      }
   88          
   89          //-------------------------------------------------------------------------------------------------------
             -------------
   90          // @brief       FIFO 查询当前数据个数
   91          // @param       *fifo           FIFO 对象指针
   92          // @return      void
   93          // Sample usage:
   94          //-------------------------------------------------------------------------------------------------------
             -------------
   95          uint32_t fifo_used (fifo_struct *fifo)
   96          {
   97   1          return (fifo->max - fifo->size);
   98   1      }
   99          
  100          //-------------------------------------------------------------------------------------------------------
             -------------
  101          // @brief       向 FIFO 中写入数据
  102          // @param       *fifo           FIFO 对象指针
  103          // @param       *dat            数据来源缓冲区指针
  104          // @param       length          需要写入的数据长度
  105          // @return      fifo_state_enum 操作状态
  106          // Sample usage:                if(fifo_write_buffer(&fifo,data,32)!=FIFO_SUCCESS) while(1);
  107          //-------------------------------------------------------------------------------------------------------
             -------------
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 3   

  108          fifo_state_enum fifo_write_buffer (fifo_struct *fifo, uint8_t *dat, uint32_t length)
  109          {
  110   1          uint32_t temp_length;
  111   1      
  112   1          if(length < fifo->size)                                                     // 剩余空间足够装下本次数
             -据
  113   1          {
  114   2              temp_length = fifo->max - fifo->head;                                   // 计算头指针距离缓冲区尾
             -还有多少空间
  115   2      
  116   2              if(length > temp_length)                                                // 距离缓冲区尾长度不足写
             -入数据 环形缓冲区分段操作
  117   2              {
  118   3                  memcpy(&fifo->buffer[fifo->head], dat, (uint16_t)temp_length);                // 拷贝第一段数
             -据
  119   3                  fifo_head_offset(fifo, temp_length);                                // 头指针偏移
  120   3                  dat += temp_length;                                                 // 读取缓冲偏移
  121   3                  memcpy(&fifo->buffer[fifo->head], dat, length - temp_length);       // 拷贝第一段数据
  122   3                  fifo_head_offset(fifo, length - temp_length);                       // 头指针偏移
  123   3              }
  124   2              else
  125   2              {
  126   3                  memcpy(&fifo->buffer[fifo->head], dat, (uint16_t)length);                     // 一次完整写入
  127   3                  fifo_head_offset(fifo, length);                                     // 头指针偏移
  128   3              }
  129   2      
  130   2              fifo->size -= length;                                                   // 缓冲区剩余长度减小
  131   2          }
  132   1          else
  133   1          {
  134   2              return FIFO_SPACE_NO_ENOUGH;
  135   2          }
  136   1      
  137   1          return FIFO_SUCCESS;
  138   1      }
  139          
  140          //-------------------------------------------------------------------------------------------------------
             -------------
  141          // @brief       从 FIFO 读取数据
  142          // @param       *fifo           FIFO 对象指针
  143          // @param       *dat            目标缓冲区指针
  144          // @param       *length         读取的数据长度 如果没有这么多数据这里会被修改
  145          // @param       flag            是否变更 FIFO 状态 可选择是否清空读取的数据
  146          // @return      fifo_state_enum 操作状态
  147          // Sample usage:                if(fifo_read_buffer(&fifo,data,32,FIFO_READ_ONLY)!=FIFO_SUCCESS) while(1)
             -;
  148          //-------------------------------------------------------------------------------------------------------
             -------------
  149          fifo_state_enum fifo_read_buffer (fifo_struct *fifo, uint8_t *dat, uint32_t *length, fifo_operation_enum 
             -flag)
  150          {
  151   1          uint8_t data_check = 0;
  152   1          uint32_t temp_length;
  153   1      
  154   1          if(*length > fifo_used(fifo))
  155   1          {
  156   2              *length = (fifo->max - fifo->size);                                     // 纠正读取的长度
  157   2              data_check = 1;                                                         // 标志数据不够
  158   2          }
  159   1      
  160   1          temp_length = fifo->max - fifo->end;                                        // 计算尾指针距离缓冲区尾
             -还有多少空间
  161   1          if(*length <= temp_length)                                                  // 足够一次性读取完毕
  162   1          {
  163   2              if(NULL != dat)    memcpy(dat, &fifo->buffer[fifo->end], (uint16_t)*length);      // 一次性读取完
             -毕
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 4   

  164   2          }
  165   1          else
  166   1          {
  167   2              if(NULL != dat)
  168   2              {
  169   3                  memcpy(dat, &fifo->buffer[fifo->end], (uint16_t)temp_length);                 // 拷贝第一段数
             -据
  170   3                  memcpy(&dat[temp_length], &fifo->buffer[0], *length - temp_length); // 拷贝第二段数据
  171   3              }
  172   2          }
  173   1      
  174   1          if(flag == FIFO_READ_AND_CLEAN)                                             // 如果选择读取并更改 FIF
             -O 状态
  175   1          {
  176   2              fifo_end_offset(fifo, *length);                                         // 移动 FIFO 头指针
  177   2              fifo->size += *length;
  178   2          }
  179   1      
  180   1          return (data_check?FIFO_DATA_NO_ENOUGH:FIFO_SUCCESS);
  181   1      }
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 5   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION fifo_init? (BEGIN)
                                                ; SOURCE LINE # 30
000000 7F71           MOV      DR28,DR4
;---- Variable 'buffer_addr' assigned to Register 'DR28' ----
000002 7F20           MOV      DR8,DR0
;---- Variable 'fifo' assigned to Register 'DR8' ----
                                                ; SOURCE LINE # 32
000004 BE780000       CMP      DR28,#00H
000008 7805           JNE      ?C0001
                                                ; SOURCE LINE # 33
00000A 7E340001       MOV      WR6,#01H
00000E AA             ERET     
               ?C0001:
                                                ; SOURCE LINE # 34
00000F 79F20002       MOV      @DR8+0x2,WR30
000013 1B2AE0         MOV      @DR8,WR28
                                                ; SOURCE LINE # 35
000016 9F11           SUB      DR4,DR4
000018 79320006       MOV      @DR8+0x6,WR6
00001C 79220004       MOV      @DR8+0x4,WR4
                                                ; SOURCE LINE # 36
000020 7932000A       MOV      @DR8+0xA,WR6
000024 79220008       MOV      @DR8+0x8,WR4
                                                ; SOURCE LINE # 37
000028 7E1F0000    R  MOV      DR4,size
00002C 7932000E       MOV      @DR8+0xE,WR6
000030 7922000C       MOV      @DR8+0xC,WR4
                                                ; SOURCE LINE # 38
000034 7E1F0000    R  MOV      DR4,size
000038 79320012       MOV      @DR8+0x12,WR6
00003C 79220010       MOV      @DR8+0x10,WR4
                                                ; SOURCE LINE # 39
000040 6D33           XRL      WR6,WR6
                                                ; SOURCE LINE # 40
000042 AA             ERET     
;       FUNCTION fifo_init? (END)

;       FUNCTION fifo_head_offset? (BEGIN)
                                                ; SOURCE LINE # 49
000043 7F61           MOV      DR24,DR4
;---- Variable 'offset' assigned to Register 'DR24' ----
000045 7F70           MOV      DR28,DR0
;---- Variable 'fifo' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 51
000047 0B16           INC      WR2,#04H
000049 69300002       MOV      WR6,@DR0+0x2
00004D 0B0A20         MOV      WR4,@DR0
000050 2F16           ADD      DR4,DR24
                                                ; SOURCE LINE # 53
000052 8015           SJMP     ?C0026
               ?C0005:
                                                ; SOURCE LINE # 55
000054 69570012       MOV      WR10,@DR28+0x12
000058 69470010       MOV      WR8,@DR28+0x10
00005C 7F07           MOV      DR0,DR28
00005E 0B16           INC      WR2,#04H
000060 69300002       MOV      WR6,@DR0+0x2
000064 0B0A20         MOV      WR4,@DR0
000067 9F12           SUB      DR4,DR8
               ?C0026:
000069 79300002       MOV      @DR0+0x2,WR6
00006D 1B0A20         MOV      @DR0,WR4
                                                ; SOURCE LINE # 56
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 6   

               ?C0003:
000070 69170006       MOV      WR2,@DR28+0x6
000074 69070004       MOV      WR0,@DR28+0x4
000078 69370012       MOV      WR6,@DR28+0x12
00007C 69270010       MOV      WR4,@DR28+0x10
000080 BF10           CMP      DR4,DR0
000082 28D0           JLE      ?C0005
                                                ; SOURCE LINE # 57
000084 AA             ERET     
;       FUNCTION fifo_head_offset? (END)

;       FUNCTION fifo_end_offset? (BEGIN)
                                                ; SOURCE LINE # 66
000085 7F61           MOV      DR24,DR4
;---- Variable 'offset' assigned to Register 'DR24' ----
000087 7F70           MOV      DR28,DR0
;---- Variable 'fifo' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 68
000089 2E140008       ADD      WR2,#08H
00008D 69300002       MOV      WR6,@DR0+0x2
000091 0B0A20         MOV      WR4,@DR0
000094 2F16           ADD      DR4,DR24
                                                ; SOURCE LINE # 70
000096 8017           SJMP     ?C0027
               ?C0009:
                                                ; SOURCE LINE # 72
000098 69570012       MOV      WR10,@DR28+0x12
00009C 69470010       MOV      WR8,@DR28+0x10
0000A0 7F07           MOV      DR0,DR28
0000A2 2E140008       ADD      WR2,#08H
0000A6 69300002       MOV      WR6,@DR0+0x2
0000AA 0B0A20         MOV      WR4,@DR0
0000AD 9F12           SUB      DR4,DR8
               ?C0027:
0000AF 79300002       MOV      @DR0+0x2,WR6
0000B3 1B0A20         MOV      @DR0,WR4
                                                ; SOURCE LINE # 73
               ?C0007:
0000B6 6917000A       MOV      WR2,@DR28+0xA
0000BA 69070008       MOV      WR0,@DR28+0x8
0000BE 69370012       MOV      WR6,@DR28+0x12
0000C2 69270010       MOV      WR4,@DR28+0x10
0000C6 BF10           CMP      DR4,DR0
0000C8 28CE           JLE      ?C0009
                                                ; SOURCE LINE # 74
0000CA AA             ERET     
;       FUNCTION fifo_end_offset? (END)

;       FUNCTION fifo_clear? (BEGIN)
                                                ; SOURCE LINE # 82
0000CB 7F20           MOV      DR8,DR0
;---- Variable 'fifo' assigned to Register 'DR8' ----
                                                ; SOURCE LINE # 84
0000CD 9F11           SUB      DR4,DR4
0000CF 79320006       MOV      @DR8+0x6,WR6
0000D3 79220004       MOV      @DR8+0x4,WR4
                                                ; SOURCE LINE # 85
0000D7 7932000A       MOV      @DR8+0xA,WR6
0000DB 79220008       MOV      @DR8+0x8,WR4
                                                ; SOURCE LINE # 86
0000DF 69320012       MOV      WR6,@DR8+0x12
0000E3 69220010       MOV      WR4,@DR8+0x10
0000E7 7932000E       MOV      @DR8+0xE,WR6
0000EB 7922000C       MOV      @DR8+0xC,WR4
                                                ; SOURCE LINE # 87
0000EF AA             ERET     
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 7   

;       FUNCTION fifo_clear? (END)

;       FUNCTION fifo_used? (BEGIN)
                                                ; SOURCE LINE # 95
0000F0 7F70           MOV      DR28,DR0
;---- Variable 'fifo' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 97
0000F2 6917000E       MOV      WR2,@DR28+0xE
0000F6 6907000C       MOV      WR0,@DR28+0xC
0000FA 69370012       MOV      WR6,@DR28+0x12
0000FE 69270010       MOV      WR4,@DR28+0x10
000102 9F10           SUB      DR4,DR0
                                                ; SOURCE LINE # 98
000104 AA             ERET     
;       FUNCTION fifo_used? (END)

;       FUNCTION fifo_write_buffer? (BEGIN)
                                                ; SOURCE LINE # 108
000105 CA3B           PUSH     DR12
000107 7A1F0000    R  MOV      dat,DR4
00010B 7F30           MOV      DR12,DR0
;---- Variable 'fifo' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 109
                                                ; SOURCE LINE # 112
00010D 6933000E       MOV      WR6,@DR12+0xE
000111 6923000C       MOV      WR4,@DR12+0xC
000115 7E2F0000    R  MOV      DR8,length
000119 BF21           CMP      DR8,DR4
00011B 4003        R  JC       $ + 5H
00011D 020000      R  LJMP     ?C0012
                                                ; SOURCE LINE # 114
000120 69330006       MOV      WR6,@DR12+0x6
000124 69230004       MOV      WR4,@DR12+0x4
000128 69130012       MOV      WR2,@DR12+0x12
00012C 69030010       MOV      WR0,@DR12+0x10
000130 9F01           SUB      DR0,DR4
000132 7A0F0000    R  MOV      temp_length,DR0
                                                ; SOURCE LINE # 116
000136 BF20           CMP      DR8,DR0
000138 2862           JLE      ?C0013
                                                ; SOURCE LINE # 118
00013A 7E0F0000    R  MOV      DR0,temp_length
00013E CA19           PUSH     WR2
000140 69130002       MOV      WR2,@DR12+0x2
000144 0B3A00         MOV      WR0,@DR12
000147 2D13           ADD      WR2,WR6
000149 7E1F0000    R  MOV      DR4,dat
00014D 9A000000    E  ECALL    memcpy??
000151 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 119
000153 7F03           MOV      DR0,DR12
000155 7E1F0000    R  MOV      DR4,temp_length
000159 9A000000    R  ECALL    fifo_head_offset?
                                                ; SOURCE LINE # 120
00015D 7E1F0000    R  MOV      DR4,temp_length
000161 7D23           MOV      WR4,WR6
000163 7E0F0000    R  MOV      DR0,dat
000167 2D13           ADD      WR2,WR6
000169 7A0F0000    R  MOV      dat,DR0
                                                ; SOURCE LINE # 121
00016D 7E0F0000    R  MOV      DR0,length
000171 7D31           MOV      WR6,WR2
000173 9D32           SUB      WR6,WR4
000175 CA39           PUSH     WR6
000177 69330006       MOV      WR6,@DR12+0x6
00017B 69130002       MOV      WR2,@DR12+0x2
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 8   

00017F 0B3A00         MOV      WR0,@DR12
000182 2D13           ADD      WR2,WR6
000184 7E1F0000    R  MOV      DR4,dat
000188 9A000000    E  ECALL    memcpy??
00018C 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 122
00018E 7F03           MOV      DR0,DR12
000190 7E2F0000    R  MOV      DR8,temp_length
000194 7E1F0000    R  MOV      DR4,length
000198 9F12           SUB      DR4,DR8
                                                ; SOURCE LINE # 123
00019A 8023           SJMP     ?C0028
               ?C0013:
                                                ; SOURCE LINE # 126
00019C 7E1F0000    R  MOV      DR4,length
0001A0 CA39           PUSH     WR6
0001A2 69330006       MOV      WR6,@DR12+0x6
0001A6 69130002       MOV      WR2,@DR12+0x2
0001AA 0B3A00         MOV      WR0,@DR12
0001AD 2D13           ADD      WR2,WR6
0001AF 7E1F0000    R  MOV      DR4,dat
0001B3 9A000000    E  ECALL    memcpy??
0001B7 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 127
0001B9 7F03           MOV      DR0,DR12
0001BB 7E1F0000    R  MOV      DR4,length
               ?C0028:
0001BF 9A000000    R  ECALL    fifo_head_offset?
                                                ; SOURCE LINE # 128
                                                ; SOURCE LINE # 130
0001C3 7E2F0000    R  MOV      DR8,length
0001C7 7F03           MOV      DR0,DR12
0001C9 2E14000C       ADD      WR2,#0CH
0001CD 69300002       MOV      WR6,@DR0+0x2
0001D1 0B0A20         MOV      WR4,@DR0
0001D4 9F12           SUB      DR4,DR8
0001D6 79300002       MOV      @DR0+0x2,WR6
0001DA 1B0A20         MOV      @DR0,WR4
                                                ; SOURCE LINE # 131
0001DD 8006           SJMP     ?C0015
               ?C0012:
                                                ; SOURCE LINE # 134
0001DF 7E340002       MOV      WR6,#02H
0001E3 8002           SJMP     ?C0016
                                                ; SOURCE LINE # 135
               ?C0015:
                                                ; SOURCE LINE # 137
0001E5 6D33           XRL      WR6,WR6
                                                ; SOURCE LINE # 138
               ?C0016:
0001E7 DA3B           POP      DR12
0001E9 AA             ERET     
;       FUNCTION fifo_write_buffer? (END)

;       FUNCTION fifo_read_buffer? (BEGIN)
                                                ; SOURCE LINE # 149
0001EA CA3B           PUSH     DR12
0001EC 7A1F0000    R  MOV      dat,DR4
0001F0 7F30           MOV      DR12,DR0
;---- Variable 'fifo' assigned to Register 'DR12' ----
                                                ; SOURCE LINE # 150
                                                ; SOURCE LINE # 151
0001F2 E4             CLR      A                ; A=R11
0001F3 7AB30000    R  MOV      data_check,R11   ; A=R11
                                                ; SOURCE LINE # 154
0001F7 9A000000    R  ECALL    fifo_used?
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 9   

0001FB 7F21           MOV      DR8,DR4
0001FD 7E0F0000    R  MOV      DR0,length
000201 69300002       MOV      WR6,@DR0+0x2
000205 0B0A20         MOV      WR4,@DR0
000208 BF12           CMP      DR4,DR8
00020A 281F           JLE      ?C0017
                                                ; SOURCE LINE # 156
00020C 6953000E       MOV      WR10,@DR12+0xE
000210 6943000C       MOV      WR8,@DR12+0xC
000214 69330012       MOV      WR6,@DR12+0x12
000218 69230010       MOV      WR4,@DR12+0x10
00021C 9F12           SUB      DR4,DR8
00021E 79300002       MOV      @DR0+0x2,WR6
000222 1B0A20         MOV      @DR0,WR4
                                                ; SOURCE LINE # 157
000225 7401           MOV      A,#01H           ; A=R11
000227 7AB30000    R  MOV      data_check,R11   ; A=R11
                                                ; SOURCE LINE # 158
               ?C0017:
                                                ; SOURCE LINE # 160
00022B 6933000A       MOV      WR6,@DR12+0xA
00022F 69230008       MOV      WR4,@DR12+0x8
000233 69130012       MOV      WR2,@DR12+0x12
000237 69030010       MOV      WR0,@DR12+0x10
00023B 9F01           SUB      DR0,DR4
00023D 7A0F0000    R  MOV      temp_length,DR0
                                                ; SOURCE LINE # 161
000241 7E7F0000    R  MOV      DR28,length
000245 69570002       MOV      WR10,@DR28+0x2
000249 0B7A40         MOV      WR8,@DR28
00024C BF20           CMP      DR8,DR0
00024E 3819           JG       ?C0018
                                                ; SOURCE LINE # 163
000250 7E0F0000    R  MOV      DR0,dat
000254 BE080000       CMP      DR0,#00H
000258 685C           JE       ?C0020
00025A CA59           PUSH     WR10
00025C 7D53           MOV      WR10,WR6
00025E 69330002       MOV      WR6,@DR12+0x2
000262 0B3A20         MOV      WR4,@DR12
000265 2D35           ADD      WR6,WR10
                                                ; SOURCE LINE # 164
000267 8047           SJMP     ?C0029
               ?C0018:
                                                ; SOURCE LINE # 167
000269 7E0F0000    R  MOV      DR0,dat
00026D BE080000       CMP      DR0,#00H
000271 6843           JE       ?C0020
                                                ; SOURCE LINE # 169
000273 7E1F0000    R  MOV      DR4,temp_length
000277 CA39           PUSH     WR6
000279 6933000A       MOV      WR6,@DR12+0xA
00027D 7D53           MOV      WR10,WR6
00027F 69330002       MOV      WR6,@DR12+0x2
000283 0B3A20         MOV      WR4,@DR12
000286 2D35           ADD      WR6,WR10
000288 9A000000    E  ECALL    memcpy??
00028C 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 170
00028E 7E0F0000    R  MOV      DR0,length
000292 69300002       MOV      WR6,@DR0+0x2
000296 0B0A20         MOV      WR4,@DR0
000299 7D13           MOV      WR2,WR6
00029B 7E1F0000    R  MOV      DR4,temp_length
00029F 9D13           SUB      WR2,WR6
0002A1 CA19           PUSH     WR2
C251 COMPILER V5.60.0,  CNU_PIE_FIFO                                                       24/08/26  10:23:43  PAGE 10  

0002A3 7E0F0000    R  MOV      DR0,dat
0002A7 2D13           ADD      WR2,WR6
0002A9 69330002       MOV      WR6,@DR12+0x2
0002AD 0B3A20         MOV      WR4,@DR12
               ?C0029:
0002B0 9A000000    E  ECALL    memcpy??
0002B4 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 171
               ?C0020:
                                                ; SOURCE LINE # 174
0002B6 7E370000    R  MOV      WR6,flag
0002BA 4D33           ORL      WR6,WR6
0002BC 7832           JNE      ?C0022
                                                ; SOURCE LINE # 176
0002BE 7F03           MOV      DR0,DR12
0002C0 7E2F0000    R  MOV      DR8,length
0002C4 69320002       MOV      WR6,@DR8+0x2
0002C8 0B2A20         MOV      WR4,@DR8
0002CB 9A000000    R  ECALL    fifo_end_offset?
                                                ; SOURCE LINE # 177
0002CF 7E1F0000    R  MOV      DR4,length
0002D3 69510002       MOV      WR10,@DR4+0x2
0002D7 0B1A40         MOV      WR8,@DR4
0002DA 7F03           MOV      DR0,DR12
0002DC 2E14000C       ADD      WR2,#0CH
0002E0 69300002       MOV      WR6,@DR0+0x2
0002E4 0B0A20         MOV      WR4,@DR0
0002E7 2F12           ADD      DR4,DR8
0002E9 79300002       MOV      @DR0+0x2,WR6
0002ED 1B0A20         MOV      @DR0,WR4
                                                ; SOURCE LINE # 178
               ?C0022:
                                                ; SOURCE LINE # 180
0002F0 7EB30000    R  MOV      R11,data_check   ; A=R11
0002F4 6006           JZ       ?C0024
0002F6 7E340003       MOV      WR6,#03H
0002FA 8002           SJMP     ?C0025
               ?C0024:
0002FC 6D33           XRL      WR6,WR6
               ?C0025:
                                                ; SOURCE LINE # 181
0002FE DA3B           POP      DR12
000300 AA             ERET     
;       FUNCTION fifo_read_buffer? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =    ------     ------
  ecode size           =       769     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =    ------         31
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

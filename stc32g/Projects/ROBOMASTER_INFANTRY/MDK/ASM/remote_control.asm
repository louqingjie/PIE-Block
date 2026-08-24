C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 1   


C251 COMPILER V5.60.0, COMPILATION OF MODULE remote_control
OBJECT MODULE PLACED IN .\Objects\ASM\remote_control.obj
COMPILER INVOKED BY: C:\Keil_v5\C251\BIN\C251.EXE ..\..\..\Libraries\boards\src\remote_control.c XSMALL ROM(HUGE) BROWSE
                    - INCDIR(..\..\..\Libraries\boards\inc;..\..\..\Libraries\startup\inc;..\USER\inc;..\..\..\Libraries\deivers\inc) INTVECT
                    -OR(0X1000) DEBUG CODE PRINT(.\ASM\remote_control.asm) TABS(2) OBJECT(.\Objects\ASM\remote_control.obj) 

stmt  level    source

    1          /*
    2           * remote_control.c
    3           *
    4           *  Created on: 2020��4��5��
    5           *      Author: Фʱ��
    6           */
    7          #include "CNU_PIE_TIMER.h"
    8          #include "remote_control.h"
    9          #include "nrf24l01.h"
   10          #include "main.h"
   11          
   12          RC_ctrl_t rc_ctrl;   // ң����ʵ�廯
   13          SendPack_t sendpack; // ��������ʵ�廯
   14          
   15          // ң������ʼ��
   16          void remote_control_init(void)
   17          {
   18   1        // Ci24R1��ʼ��
   19   1        while (!NRF24L01_Init())
   20   1          ;
   21   1        // NRF24L01_Init();
   22   1      
   23   1        memset(&sendpack, 0, sizeof(SendPack_t));
   24   1      
   25   1        // ��ʼ�����������ж�
   26   1        // PIT4�ж����� 1ms�ж�
   27   1      
   28   1        // PIT_Timer_Ms(TIM4, 1);
   29   1      
   30   1        Ms_Delay(200);
   31   1      }
   32          
   33          // ң����Э����
   34          uint8_t Rc_unpack_data(uint8_t *data_t)
   35          {
   36   1        int i;
   37   1        uint8_t check = 0;
   38   1        if (data_t[0] != 11)
   39   1          return 0; // ֡ͷУ��ʧ��
   40   1        for (i = 1; i < 11; i++)
   41   1          check += data_t[i];
   42   1        if (check != data_t[11])
   43   1          return 0; // ֡βУ��ʧ��
   44   1      
   45   1        // ���
   46   1        rc_ctrl.rocker.value[0] = (int16_t)(data_t[1] | data_t[2] << 8);
   47   1        rc_ctrl.rocker.value[1] = (int16_t)(data_t[3] | data_t[4] << 8);
   48   1        rc_ctrl.rocker.value[2] = (int16_t)(data_t[5] | data_t[6] << 8);
   49   1        rc_ctrl.rocker.value[3] = (int16_t)(data_t[7] | data_t[8] << 8);
   50   1        rc_ctrl.key.value = (uint16_t)(data_t[9] | data_t[10] << 8);
   51   1        return 1;
   52   1      }
   53          
   54          /*
   55           *@brief �������Լ�������ʾ�ڶ�Ӧ����
   56           *@param ��ʾ�����׵�ַ
   57           *@param ��ʾ���ֳ��� ���Ϊ5���ַ�
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 2   

   58           *@param ��ʾ����
   59           *@param λ��ң���������� 0-5 ��6�� ������ʾ
   60           *@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
   61           *@example ShowStringData("abc", 3, 2.55, 0, 1);
   62           */
   63          void ShowStringData(char *name_t, uint8_t namelenth, float num, uint8_t row, uint8_t Size)
   64          {
   65   1        if (row > 5 || (name_t == 0 && namelenth != 0) || sendpack.Mode[row])
   66   1          return;
   67   1        if (namelenth > 5)
   68   1          namelenth = 5;
   69   1        memcpy(sendpack.line[row].Name, name_t, namelenth);
   70   1        sendpack.line[row].Namelenth = namelenth;
   71   1        sendpack.line[row].Number[0] = num;
   72   1        sendpack.line[row].Row = row;
   73   1        sendpack.line[row].Size = Size ? 1 : 0;
   74   1        sendpack.Mode[row] = 1;
   75   1      }
   76          
   77          /*
   78           *@brief ������������������ʾ�ڶ�Ӧ����
   79           *@param ��ʾ������
   80           *@param ��ʾ������
   81           *@param λ��ң���������� 0-5 ��6�� ������ʾ
   82           *@param ��ʾ��С (0) ��6*8��С��ʾ (!0)��8*16��С��ʾ
   83           *@example ShowData(1.0, 0.2, 0, 1);
   84           */
   85          void ShowData(float numleft, float numright, uint8_t row, uint8_t Size)
   86          {
   87   1        if (row > 5 || sendpack.Mode[row])
   88   1          return;
   89   1        sendpack.line[row].Number[0] = numleft;
   90   1        sendpack.line[row].Number[1] = numright;
   91   1        sendpack.line[row].Row = row;
   92   1        sendpack.line[row].Size = Size ? 1 : 0;
   93   1        sendpack.Mode[row] = 2;
   94   1      }
   95          
   96          /*
   97           *@brief ���ĳһ����ʾ����
   98           *@param λ��ң���������� 0-5 ��6�� ������Ч
   99           *@param ��С ��0��һ�����һ�� ����0��һ���������
  100           *@example ShowLineClear(0, 1);  //�����0,1�е���ʾ����
  101           */
  102          void ShowLineClear(uint8_t row, uint8_t Size)
  103          {
  104   1        if (row > 5)
  105   1          return;
  106   1        sendpack.line[row].Row = row;
  107   1        sendpack.line[row].Size = Size ? 1 : 0;
  108   1        sendpack.Mode[row] = 3;
  109   1      }
  110          
  111          /*
  112           *@brief ��ȡң��������ֵ
  113           *@param �������
  114           *@return ���·���1 �ɿ�����0 ������󷵻�-1
  115           */
  116          int8_t RcKeyValueRead(KEY_OFFSET_t offset)
  117          {
  118   1        if (offset > 15)
  119   1          return -1;
  120   1        return (rc_ctrl.key.value & (1 << offset)) ? 1 : 0;
  121   1      }
  122          
  123          /*
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 3   

  124           *@brief ��ȡң����ҡ��adc�ɼ�ֵ
  125           *@param  ҡ�����
  126           *@return ���ض�Ӧ����adc�ɼ�ֵ
  127           */
  128          int16_t RcRockerValueRead(ROCKER_OFFSET_t offset)
  129          {
  130   1        return rc_ctrl.rocker.value[offset];
  131   1      }
  132          
  133          // �жϻص�����
  134          static uint32_t timeline = 0; // ʱ����
  135          uint8_t Clear_Time = 0;       // ң�����Ͽ��������
  136          float Offset = 0;             // �첽����ƫ����
  137          void TM4_Isr() interrupt 20
  138          {
  139   1        PIT_Timer_Clear(TIM4);
  140   1        timeline++;
  141   1        if ((timeline % 20) == 0) // 20ms ����һ��
  142   1        {
  143   2          RCPacket_Send();
  144   2        }
  145   1        Clear_Time++;
  146   1        if (Clear_Time >= 50) // 50msδ���յ�ң�������������������
             -�Ϣ
  147   1        {
  148   2          Clear_Time = 0;
  149   2          memset(&rc_ctrl, 0, sizeof(rc_ctrl));
  150   2          rc_ctrl.key.value |= 1 << KEY_RCDISCONNECTED;
  151   2        }
  152   1      }
  153          // ��������ָ��
  154          SendPack_t *get_sendpack_point(void)
  155          {
  156   1        return &sendpack;
  157   1      }
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 4   

ASSEMBLY LISTING OF GENERATED OBJECT CODE


;       FUNCTION remote_control_init? (BEGIN)
                                                ; SOURCE LINE # 16
                                                ; SOURCE LINE # 19
                                                ; SOURCE LINE # 20
               ?C0001:
000000 9A000000    E  ECALL    NRF24L01_Init?
000004 60FA           JZ       ?C0001
                                                ; SOURCE LINE # 23
000006 7E000000    R  MOV      DR0,#WORD0 sendpack
00000A 7E340066       MOV      WR6,#066H
00000E E4             CLR      A                ; A=R11
00000F 9A000000    E  ECALL    memset??
                                                ; SOURCE LINE # 30
000013 7E3400C8       MOV      WR6,#0C8H
000017 8A000000    E  EJMP     Ms_Delay?
;       FUNCTION remote_control_init? (END)

;       FUNCTION Rc_unpack_data? (BEGIN)
                                                ; SOURCE LINE # 34
00001B 7F70           MOV      DR28,DR0
;---- Variable 'data_t' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 35
                                                ; SOURCE LINE # 37
00001D 6C66           XRL      R6,R6
;---- Variable 'check' assigned to Register 'R6' ----
                                                ; SOURCE LINE # 38
00001F 7E7BB0         MOV      R11,@DR28        ; A=R11
000022 BEB00B         CMP      R11,#0BH         ; A=R11
000025 6802           JE       ?C0011
                                                ; SOURCE LINE # 39
000027 E4             CLR      A                ; A=R11
000028 AA             ERET     
                                                ; SOURCE LINE # 40
               ?C0011:
000029 7E240001       MOV      WR4,#01H
;---- Variable 'i' assigned to Register 'WR4' ----
               ?C0010:
                                                ; SOURCE LINE # 41
00002D 7F07           MOV      DR0,DR28
00002F 2D12           ADD      WR2,WR4
000031 7E0B70         MOV      R7,@DR0
000034 2C67           ADD      R6,R7
000036 0B24           INC      WR4,#01H
000038 BE24000B       CMP      WR4,#0BH
00003C 48EF           JSL      ?C0010
                                                ; SOURCE LINE # 42
00003E 2977000B       MOV      R7,@DR28+0xB
000042 BC76           CMP      R7,R6
000044 6802           JE       ?C0012
                                                ; SOURCE LINE # 43
000046 E4             CLR      A                ; A=R11
000047 AA             ERET     
               ?C0012:
                                                ; SOURCE LINE # 46
000048 29770002       MOV      R7,@DR28+0x2
00004C 7C47           MOV      R4,R7
00004E 29770001       MOV      R7,@DR28+0x1
000052 7C64           MOV      R6,R4
000054 7A370000    R  MOV      rc_ctrl,WR6
                                                ; SOURCE LINE # 47
000058 29770004       MOV      R7,@DR28+0x4
00005C 7C47           MOV      R4,R7
00005E 29770003       MOV      R7,@DR28+0x3
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 5   

000062 7C64           MOV      R6,R4
000064 7A370000    R  MOV      rc_ctrl+2,WR6
                                                ; SOURCE LINE # 48
000068 29770006       MOV      R7,@DR28+0x6
00006C 7C47           MOV      R4,R7
00006E 29770005       MOV      R7,@DR28+0x5
000072 7C64           MOV      R6,R4
000074 7A370000    R  MOV      rc_ctrl+4,WR6
                                                ; SOURCE LINE # 49
000078 29770008       MOV      R7,@DR28+0x8
00007C 7C47           MOV      R4,R7
00007E 29770007       MOV      R7,@DR28+0x7
000082 7C64           MOV      R6,R4
000084 7A370000    R  MOV      rc_ctrl+6,WR6
                                                ; SOURCE LINE # 50
000088 2977000A       MOV      R7,@DR28+0xA
00008C 7C47           MOV      R4,R7
00008E 29770009       MOV      R7,@DR28+0x9
000092 7C64           MOV      R6,R4
000094 7A370000    R  MOV      rc_ctrl+8,WR6
                                                ; SOURCE LINE # 51
000098 7401           MOV      A,#01H           ; A=R11
                                                ; SOURCE LINE # 52
00009A AA             ERET     
;       FUNCTION Rc_unpack_data? (END)

;       FUNCTION ShowStringData? (BEGIN)
                                                ; SOURCE LINE # 63
00009B CAF8           PUSH     R15
00009D 7A1F0000    R  MOV      num,DR4
0000A1 7CFB           MOV      R15,R11          ; A=R11
;---- Variable 'namelenth' assigned to Register 'R15' ----
0000A3 7F70           MOV      DR28,DR0
;---- Variable 'name_t' assigned to Register 'DR28' ----
                                                ; SOURCE LINE # 65
0000A5 7E230000    R  MOV      R2,row
0000A9 BE2005         CMP      R2,#05H
0000AC 2803        R  JLE      $ + 5H
0000AE 020000      R  LJMP     ?C0016
0000B1 BE780000       CMP      DR28,#00H
0000B5 7804           JNE      ?C0015
0000B7 4CFF           ORL      R15,R15
0000B9 787B           JNE      ?C0016
               ?C0015:
0000BB 0A32           MOVZ     WR6,R2
0000BD 09B30000    R  MOV      R11,@WR6+sendpack+0x60
0000C1 7073           JNZ      ?C0016
                                                ; SOURCE LINE # 66
                                                ; SOURCE LINE # 67
0000C3 BEF005         CMP      R15,#05H
0000C6 2803           JLE      ?C0017
                                                ; SOURCE LINE # 68
0000C8 7EF005         MOV      R15,#05H
               ?C0017:
                                                ; SOURCE LINE # 69
0000CB 0A3F           MOVZ     WR6,R15
0000CD CA39           PUSH     WR6
0000CF 7E3010         MOV      R3,#010H
0000D2 AC23           MUL      R2,R3
0000D4 2E140000    R  ADD      WR2,#WORD0 sendpack
0000D8 6D00           XRL      WR0,WR0
0000DA 7F17           MOV      DR4,DR28
0000DC 9A000000    E  ECALL    memcpy??
0000E0 1BFD           DEC      DR60,#02H
                                                ; SOURCE LINE # 70
0000E2 7EB30000    R  MOV      R11,row          ; A=R11
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 6   

0000E6 7E7010         MOV      R7,#010H
0000E9 ACB7           MUL      R11,R7           ; A=R11
0000EB 19F50000    R  MOV      @WR10+sendpack+0x5,R15
                                                ; SOURCE LINE # 71
0000EF 7E1F0000    R  MOV      DR4,num
0000F3 7EB30000    R  MOV      R11,row          ; A=R11
0000F7 7E3010         MOV      R3,#010H
0000FA ACB3           MUL      R11,R3           ; A=R11
0000FC 59350000    R  MOV      @WR10+sendpack+0x8,WR6
000100 59250000    R  MOV      @WR10+sendpack+0x6,WR4
                                                ; SOURCE LINE # 72
000104 7E730000    R  MOV      R7,row
000108 7410           MOV      A,#010H          ; A=R11
00010A ACB7           MUL      R11,R7           ; A=R11
00010C 19750000    R  MOV      @WR10+sendpack+0xE,R7
                                                ; SOURCE LINE # 73
000110 7EB30000    R  MOV      R11,Size         ; A=R11
000114 6005           JZ       ?C0018
000116 7E7001         MOV      R7,#01H
000119 8002           SJMP     ?C0019
               ?C0018:
00011B 6C77           XRL      R7,R7
               ?C0019:
00011D 7EB30000    R  MOV      R11,row          ; A=R11
000121 7E6010         MOV      R6,#010H
000124 ACB6           MUL      R11,R6           ; A=R11
000126 19750000    R  MOV      @WR10+sendpack+0xF,R7
                                                ; SOURCE LINE # 74
00012A 7401           MOV      A,#01H           ; A=R11
00012C 7EA30000    R  MOV      R10,row
000130 0A3A           MOVZ     WR6,R10
000132 19B30000    R  MOV      @WR6+sendpack+0x60,R11
                                                ; SOURCE LINE # 75
               ?C0016:
000136 DAF8           POP      R15
000138 AA             ERET     
;       FUNCTION ShowStringData? (END)

;       FUNCTION ShowData? (BEGIN)
                                                ; SOURCE LINE # 85
000139 7C9B           MOV      R9,R11           ; A=R11
;---- Variable 'row' assigned to Register 'R9' ----
00013B 7F70           MOV      DR28,DR0
;---- Variable 'numright' assigned to Register 'DR28' ----
00013D 7F61           MOV      DR24,DR4
;---- Variable 'numleft' assigned to Register 'DR24' ----
                                                ; SOURCE LINE # 87
00013F BE9005         CMP      R9,#05H
000142 3845           JG       ?C0022
000144 0A39           MOVZ     WR6,R9
000146 09B30000    R  MOV      R11,@WR6+sendpack+0x60
00014A 703D           JNZ      ?C0022
                                                ; SOURCE LINE # 88
                                                ; SOURCE LINE # 89
00014C 7410           MOV      A,#010H          ; A=R11
00014E ACB9           MUL      R11,R9           ; A=R11
000150 59D50000    R  MOV      @WR10+sendpack+0x8,WR26
000154 59C50000    R  MOV      @WR10+sendpack+0x6,WR24
                                                ; SOURCE LINE # 90
000158 7410           MOV      A,#010H          ; A=R11
00015A ACB9           MUL      R11,R9           ; A=R11
00015C 59F50000    R  MOV      @WR10+sendpack+0xC,WR30
000160 59E50000    R  MOV      @WR10+sendpack+0xA,WR28
                                                ; SOURCE LINE # 91
000164 7410           MOV      A,#010H          ; A=R11
000166 ACB9           MUL      R11,R9           ; A=R11
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 7   

000168 19950000    R  MOV      @WR10+sendpack+0xE,R9
                                                ; SOURCE LINE # 92
00016C 7EB30000    R  MOV      R11,Size         ; A=R11
000170 6005           JZ       ?C0023
000172 7E8001         MOV      R8,#01H
000175 8002           SJMP     ?C0024
               ?C0023:
000177 6C88           XRL      R8,R8
               ?C0024:
000179 7410           MOV      A,#010H          ; A=R11
00017B ACB9           MUL      R11,R9           ; A=R11
00017D 19850000    R  MOV      @WR10+sendpack+0xF,R8
                                                ; SOURCE LINE # 93
000181 7402           MOV      A,#02H           ; A=R11
000183 0A39           MOVZ     WR6,R9
000185 19B30000    R  MOV      @WR6+sendpack+0x60,R11
                                                ; SOURCE LINE # 94
               ?C0022:
000189 AA             ERET     
;       FUNCTION ShowData? (END)

;       FUNCTION ShowLineClear? (BEGIN)
                                                ; SOURCE LINE # 102
00018A 7C47           MOV      R4,R7
;---- Variable 'Size' assigned to Register 'R4' ----
00018C 7C5B           MOV      R5,R11           ; A=R11
;---- Variable 'row' assigned to Register 'R5' ----
                                                ; SOURCE LINE # 104
00018E BE5005         CMP      R5,#05H
000191 3823           JG       ?C0026
                                                ; SOURCE LINE # 105
                                                ; SOURCE LINE # 106
000193 7410           MOV      A,#010H          ; A=R11
000195 ACB5           MUL      R11,R5           ; A=R11
000197 19550000    R  MOV      @WR10+sendpack+0xE,R5
                                                ; SOURCE LINE # 107
00019B 4C44           ORL      R4,R4
00019D 6805           JE       ?C0027
00019F 7E4001         MOV      R4,#01H
0001A2 8002           SJMP     ?C0028
               ?C0027:
0001A4 6C44           XRL      R4,R4
               ?C0028:
0001A6 7410           MOV      A,#010H          ; A=R11
0001A8 ACB5           MUL      R11,R5           ; A=R11
0001AA 19450000    R  MOV      @WR10+sendpack+0xF,R4
                                                ; SOURCE LINE # 108
0001AE 7403           MOV      A,#03H           ; A=R11
0001B0 0A35           MOVZ     WR6,R5
0001B2 19B30000    R  MOV      @WR6+sendpack+0x60,R11
                                                ; SOURCE LINE # 109
               ?C0026:
0001B6 AA             ERET     
;       FUNCTION ShowLineClear? (END)

;       FUNCTION RcKeyValueRead? (BEGIN)
                                                ; SOURCE LINE # 116
;---- Variable 'offset' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 118
0001B7 BE34000F       CMP      WR6,#0FH
0001BB 0803           JSLE     ?C0029
                                                ; SOURCE LINE # 119
0001BD 74FF           MOV      A,#0FFH          ; A=R11
0001BF AA             ERET     
               ?C0029:
                                                ; SOURCE LINE # 120
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 8   

0001C0 7CB7           MOV      R11,R7           ; A=R11
0001C2 7E340001       MOV      WR6,#01H
0001C6 6005           JZ       ?C0038
               ?C0037:
0001C8 3E34           SLL      WR6
0001CA 14             DEC      A                ; A=R11
0001CB 78FB           JNE      ?C0037
               ?C0038:
0001CD 5E370000    R  ANL      WR6,rc_ctrl+8
0001D1 6804           JE       ?C0031
0001D3 7401           MOV      A,#01H           ; A=R11
0001D5 8001           SJMP     ?C0032
               ?C0031:
0001D7 E4             CLR      A                ; A=R11
               ?C0032:
                                                ; SOURCE LINE # 121
0001D8 AA             ERET     
;       FUNCTION RcKeyValueRead? (END)

;       FUNCTION RcRockerValueRead? (BEGIN)
                                                ; SOURCE LINE # 128
;---- Variable 'offset' assigned to Register 'WR6' ----
                                                ; SOURCE LINE # 130
0001D9 3E34           SLL      WR6
0001DB 49330000    R  MOV      WR6,@WR6+rc_ctrl
                                                ; SOURCE LINE # 131
0001DF AA             ERET     
;       FUNCTION RcRockerValueRead? (END)

;       FUNCTION TM4_Isr? (BEGIN)
                                                ; SOURCE LINE # 137
0001E0 CA7B           PUSH     DR28
0001E2 CA6B           PUSH     DR24
0001E4 CA5B           PUSH     DR20
0001E6 CA4B           PUSH     DR16
0001E8 CA2B           PUSH     DR8
0001EA CA1B           PUSH     DR4
0001EC CA0B           PUSH     DR0
0001EE C0D0           PUSH     PSW
0001F0 C083           PUSH     DPH              ; WORD0(DR56)=DPTR
0001F2 C082           PUSH     DPL              ; WORD0(DR56)=DPTR
                                                ; SOURCE LINE # 139
0001F4 7E340004       MOV      WR6,#04H
0001F8 9A000000    E  ECALL    PIT_Timer_Clear?
                                                ; SOURCE LINE # 140
0001FC 7E1F0000    R  MOV      DR4,timeline
000200 0B1C           INC      DR4,#01H
000202 7A1F0000    R  MOV      timeline,DR4
                                                ; SOURCE LINE # 141
000206 7E140014       MOV      WR2,#014H
00020A 7E1F0000    R  MOV      DR4,timeline
00020E 9A000000    E  ECALL    ?C?ULIDIV?
000212 4D01           ORL      WR0,WR2
000214 7804           JNE      ?C0034
                                                ; SOURCE LINE # 143
000216 9A000000    E  ECALL    RCPacket_Send?
                                                ; SOURCE LINE # 144
               ?C0034:
                                                ; SOURCE LINE # 145
00021A 7EB30000    R  MOV      R11,Clear_Time   ; A=R11
00021E 04             INC      A                ; A=R11
00021F 7AB30000    R  MOV      Clear_Time,R11   ; A=R11
                                                ; SOURCE LINE # 146
000223 7E730000    R  MOV      R7,Clear_Time
000227 BE7032         CMP      R7,#032H
00022A 401C           JC       ?C0035
C251 COMPILER V5.60.0,  remote_control                                                     24/08/26  10:23:44  PAGE 9   

                                                ; SOURCE LINE # 148
00022C E4             CLR      A                ; A=R11
00022D 7AB30000    R  MOV      Clear_Time,R11   ; A=R11
                                                ; SOURCE LINE # 149
000231 7E000000    R  MOV      DR0,#WORD0 rc_ctrl
000235 7E34000A       MOV      WR6,#0AH
000239 9A000000    E  ECALL    memset??
                                                ; SOURCE LINE # 150
00023D 7E370000    R  MOV      WR6,rc_ctrl+8
000241 4E6080         ORL      R6,#080H
000244 7A370000    R  MOV      rc_ctrl+8,WR6
                                                ; SOURCE LINE # 151
               ?C0035:
000248 D082           POP      DPL              ; WORD0(DR56)=DPTR
00024A D083           POP      DPH              ; WORD0(DR56)=DPTR
00024C D0D0           POP      PSW
00024E DA0B           POP      DR0
000250 DA1B           POP      DR4
000252 DA2B           POP      DR8
000254 DA4B           POP      DR16
000256 DA5B           POP      DR20
000258 DA6B           POP      DR24
00025A DA7B           POP      DR28
00025C 32             RETI     
;       FUNCTION TM4_Isr? (END)

;       FUNCTION get_sendpack_point? (BEGIN)
                                                ; SOURCE LINE # 154
                                                ; SOURCE LINE # 156
00025D 7E100000    R  MOV      DR4,#WORD0 sendpack
                                                ; SOURCE LINE # 157
000261 AA             ERET     
;       FUNCTION get_sendpack_point? (END)



Module Information          Static   Overlayable
------------------------------------------------
  code size            =         4     ------
  ecode size           =       610     ------
  data size            =    ------     ------
  idata size           =    ------     ------
  pdata size           =    ------     ------
  xdata size           =    ------     ------
  xdata-const size     =    ------     ------
  edata size           =       121          7
  bit size             =    ------     ------
  ebit size            =    ------     ------
  bitaddressable size  =    ------     ------
  ebitaddressable size =    ------     ------
  far data size        =    ------     ------
  huge data size       =    ------     ------
  const size           =    ------     ------
  hconst size          =        21     ------
End of Module Information.


C251 COMPILATION COMPLETE.  0 WARNING(S),  0 ERROR(S)

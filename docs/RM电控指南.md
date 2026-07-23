# RM电控指南

在使用过程中，将机械拓展板与主控板连接，将机械拓展板插在STC开发板上的机械拓展板接口上，如下图所示：

![Image](https://internal-api-drive-stream.feishu.cn/space/api/box/stream/download/authcode/?code=ZmM5NzczMTUxNzE2ODc1ODZiOTc2MmE0ZTUzNTZhNzBfYmRkNzMxMTgwZDY0ODk0MjQwMjFlNzFlNTIxZmQ4NWFfSUQ6NzQzMzQyMzE4MDM4NTY0ODY0Ml8xNzg0NzgzMTgyOjE3ODQ4Njk1ODJfVjM)

电控组同学需要编写主控板的程序，主控板指令通过UART通信协议传递给机械拓展板，实现电机，舵机和摩擦轮的使用。

## 机械拓展板

1. 机械拓展板的程序已经由学长学姐烧录好，大家**不需要****也千万不要**给机械拓展板烧录任何程序。

2. 如果拓展板程序被擦除，请联系学长学姐，学长学姐给大家提供**10****积分****/次**的**付费恢复服务。**

3. 关于机械拓展板舵机、电机的端口选择，可以参考[机械拓展板使用指南 ](https://xv25fr194gj.feishu.cn/wiki/YWDMwCXO0iMynSknJ31c3gImnfc?from=from_copylink)。

## 主控板

电控们需要给主控板写程序，程序会通过UART通信协议传递给机械拓展板，实现电机，舵机和摩擦轮的使用。

### 拓展板协议

**请将以下内容****复制****到你的main函数之前**

```C
/*帧头帧尾，内部调用，无需关心*/
  #define COMM_HEADER_1 0xAB
  #define COMM_HEADER_2 0xBC
  #define COMM_END_1 0xCD
  #define COMM_END_2 0xDE
 /*命令码*/
  #define Init_Order 0xAA          //初始化模式
  #define Duty_Change_Order 0xBB   //修改占空比
  #define Freq_Change_Order 0xCC   //修改频率
  #define Dir_Change_Order 0xDD    //修改方向 1为正 0为负 设置一次即可
  #define Zero_Order 0xEE          //0命令
/*内部调用变量，无需关心，请勿定义同名变量*/
  uint16_t control_data[8] = {0};
  uint16_t motor_dir[8] = {0};
  uint8_t control_command = 0x00;

 /**************************************************************************************************************************
 * @brief  板间通信函数，用于主控给拓展版发送
 * @exampleCode  
 * ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000);//初始化模式
 * @explain  初始化模式后是各个引脚的频率，50为舵机或摩擦轮，10000为电机
 *           修改占空比的模式后参数写设置的占空比，以此类推，写NULL则维持之前状态，该引脚的动力源相关参数不被改变       
 * @param[in]  control_cmd 发送的内容
  * @param[in]  data_pxx  xx引脚的频率/占空比/方向
***************************************************************************************************************************/
  void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                             uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                             uint16_t data_p77)
  {
      uint8_t i = 0;
      // 通信数据帧
      uint8_t control_frame_pack[21] = {0};
      // 帧头帧尾
      control_frame_pack[0] = COMM_HEADER_1;
      control_frame_pack[1] = COMM_HEADER_2;
      control_frame_pack[19] = COMM_END_1;
      control_frame_pack[20] = COMM_END_2;
      // 指令
      control_frame_pack[2] = control_cmd;
      // 数据
      control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);
      control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);
      control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);
      control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);
      control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);
      control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);
      control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);
      control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);
      control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);
      control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);
      control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);
      control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);
      control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);
      control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);
      control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);
      control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);

      // 发送
      // UART_PutBuff(UART_1, control_frame_pack, 21);
      for (i = 0; i < 21; i++)
          UART_PutChar(UART_1, control_frame_pack[i]);
  }
```

### 主控板程序使用历程

注意事项：在 ExpansionBoradControl函数后必须使用Ms\_Delay函数，防止数据传输失败并且给硬件留出响应时间。

```C
void main(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000); //初始化
    while (1)
    {  
    ExpansionBoradControl(Duty_Change_Order, 700, 700, 700, 700, 0, 0, 6000, 6000); 
    Ms_Delay(10);           
    }
}
```

### 外设使用注意事项

1. 摩擦轮

    **摩擦轮电机PWM控制的占空比越大转速越快，但对占空比有要求****。****若电控组未按要求写程序****导致摩擦轮或机械拓展板损坏，****需要由电控组员使用****人民币****进行赔偿。**

    1. 初始化摩擦轮

        1. 频率50Hz，初始占空比0%

        2. 初始化延迟：DelayMs\(1000\);
        必须加延迟！！！留给硬件反应时间，否则电流过大易损坏摩擦轮电机。

    2. 使用摩擦轮：           

        1. 摩擦轮启动时**请逐渐增加摩擦轮占空比**，**从500占空比开始，每秒增加100占空比，最大不超过1100**，不要直接提到最高速度。

            

            ```C
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 500, 500, 0, 0, 0, 0); //修改摩擦轮占空比为500    
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 600, 600, 0, 0, 0, 0); //修改摩擦轮占空比为600      
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 700, 700, 0, 0, 0, 0); //修改摩擦轮占空比为700      
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 800, 800, 0, 0, 0, 0); //修改摩擦轮占空比为800      
            Ms_Delay(1500);
            ```

            上面是使用启动示例，当占空比给5%时电机开始转动，然后延时，再将占空比改至6%，以此类推直至达到满意速度，同样是为了给硬件反应的时间，**以避免大幅改变转速导致大电流损坏板子和电机。**
            测试时**必须先试用低转速，**若此占空比不能满足射程需求，且射程低仅由电机转速导致而非机械结构导致时，可以提速。
            但目前为大家开放的**占空比上限是11%**，未经允许不得超过此占空比，否则将受到额度处罚或在比赛中将给予判罚。

        2. **关闭摩擦轮同理，**也从当前占空比每次减1%，中间加延时，逐步降至0%。（启动和停止时不用考虑0\~5%占空比的部分）

            ```C
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 800, 800, 0, 0, 0, 0); //修改摩擦轮占空比为800    
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 700, 700, 0, 0, 0, 0); //修改摩擦轮占空比为700      
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 600, 600, 0, 0, 0, 0); //修改摩擦轮占空比为600      
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 500, 500, 0, 0, 0, 0); //修改摩擦轮占空比为500      
            Ms_Delay(1500);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0); //修改摩擦轮占空比为0     
            Ms_Delay(1500);
            ```

        3. 在使用时必须要有关闭摩擦轮程序，**不得在摩擦轮高速转动时直接断电，**如果因此导致摩擦轮或机械拓展板损坏，**需要电控组员使用****人民币****进行****赔偿****。**

2. 其他端口使用

    电机所有端口都可以作为舵机使用，此时**初始化频率**为50还是10000将决定该端口作为电机使用还是舵机使用，**同一端口不可在同一时刻同时**为电机和舵机所用。




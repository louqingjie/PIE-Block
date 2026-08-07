# RM 电控指南

本指南面向电控组同学：负责编写主控板程序，通过 UART 协议驱动机械拓展板上的
电机、舵机和摩擦轮。

## 硬件连接

将机械拓展板插在 STC 开发板的机械拓展板接口上，与主控板连接后即可使用。

## 板卡职责

| 板卡 | 职责 | 是否可烧录 |
| --- | --- | --- |
| 主控板 | 运行你自己写的程序 | 可以，且只烧这块 |
| 机械拓展板 | 解析主控指令，输出电机 / 舵机 / 摩擦轮信号 | **绝不可烧录** |

> 拓展板程序已由学长学姐烧录好。若被误擦除，联系学长学姐付费恢复
> （10 积分 / 次）。端口选择见 [机械拓展板使用指南](机械拓展板使用指南 .md)。

## 拓展板通信协议

主控板通过 UART1（230400 波特率）发送 21 字节命令帧，控制拓展板 8 个引脚
（P60/P62/P64/P66/P74/P75/P76/P77）。

### 命令码

| 命令码 | 含义 | 参数 |
| --- | --- | --- |
| `Init_Order` 0xAA | 初始化：设定各引脚频率 | `50`=舵机/摩擦轮，`10000`=电机 |
| `Duty_Change_Order` 0xBB | 修改占空比 | 写占空比；不关心的引脚可维持原值 |
| `Freq_Change_Order` 0xCC | 修改频率 | 新频率 |
| `Dir_Change_Order` 0xDD | 修改方向 | `1`=正，`0`=负，设置一次即可 |
| `Zero_Order` 0xEE | 归零 | — |

### 使用方法

**先发 `Init_Order` 设定频率**，之后才能改占空比。每次调用
`ExpansionBoradControl` 后**必须加 `Ms_Delay()`**，防止数据传输失败并给硬件留
响应时间。

```c
void main(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000); /* 初始化 */
    Ms_Delay(100);
    while (1)
    {
        ExpansionBoradControl(Duty_Change_Order, 700, 700, 700, 700, 0, 0, 6000, 6000);
        Ms_Delay(10);
    }
}
```

完整的 `ExpansionBoradControl` 实现（帧封装 + 发送）可直接复制到 main 函数之前：

```c
/* 帧头帧尾，内部调用，无需关心 */
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE

/* 内部调用变量，请勿定义同名变量 */
uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;

/* 板间通信函数：主控向拓展板发送控制帧 */
void ExpansionBoradControl(uint8_t control_cmd,
                           uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75,
                           uint16_t data_p76, uint16_t data_p77)
{
    uint8_t i = 0;
    uint8_t control_frame_pack[21] = {0};
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    control_frame_pack[2] = control_cmd;
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
    for (i = 0; i < 21; i++)
        UART_PutChar(UART_1, control_frame_pack[i]);
}
```

## 外设使用注意事项

### 摩擦轮（红线，违反需用人民币赔偿）

摩擦轮电机 PWM 占空比越大转速越快，但**对启停方式有硬性要求**。若未按要求写
程序导致摩擦轮或机械拓展板损坏，由电控组员使用人民币赔偿。

**初始化**

1. 频率 50Hz，初始占空比 0%
2. **必须加 `Ms_Delay(1000)`** —— 留给硬件反应时间，否则电流过大易损坏电机

**启动**

从占空比 500 开始，**每秒最多增加 100**，逐步提速，不得直接给到目标转速。
电机在 5% 占空比才开始转，0~5% 区间可以跳过：

```c
ExpansionBoradControl(Duty_Change_Order, 0, 0, 500, 500, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 600, 600, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 700, 700, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 800, 800, 0, 0, 0, 0);
Ms_Delay(1500);
```

- 测试时必须**先试用低转速**。若射程不足且确定由电机转速而非机械结构导致，
  才能提速
- **占空比上限 11%（1100）**，未经允许不得超过，否则额度处罚或比赛判罚

**关闭**

与启动同理，每次减 1%，中间加延时，逐步降至 0%：

```c
ExpansionBoradControl(Duty_Change_Order, 0, 0, 800, 800, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 700, 700, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 600, 600, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 500, 500, 0, 0, 0, 0);
Ms_Delay(1500);
ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
Ms_Delay(1500);
```

**程序里必须有关闭摩擦轮的逻辑，不得在高速转动时直接断电。**

### 电机与舵机

- 所有端口都可作舵机使用，**初始化频率决定端口角色**：`50`=舵机/摩擦轮，
  `10000`=电机
- **同一端口在同一时刻不能同时作电机和舵机**
- 底盘电机速度范围通常 `-10000 ~ 10000`（负值通过 `Dir_Change_Order` 或符号处理）

/*
 * PIE-Block 车体串口调试台（独立校内赛工程）
 *
 * 控制基线：麦轮工程.pieproj 的生成结果
 *   - 频道 29，死区 100
 *   - vx = -LY, vy = -LX, turn = -RX
 *   - P74..P77 四路麦轮，±10000 限幅
 *   - 每轮两帧扩展板 UART，每 5 轮一包 22 字节遥测
 *
 * 与生成代码的差异（均为调试台需求）：
 *   1. UART2 P1.0/P1.1 输出调试信息，非阻塞环形缓冲；
 *   2. 遥控器失联 > 500 ms 时清零摇杆输入，底盘停车；
 *   3. nRF 驱动换成本工程私有副本，增加 FIFO/STATUS 统计。
 */
#include "main.h"

#ifndef PIE_BLOCK_FW_HASH
#define PIE_BLOCK_FW_HASH "local"
#endif
#ifndef PIE_BLOCK_BUILD_DATE
#define PIE_BLOCK_BUILD_DATE __DATE__
#endif

#define EXPANSION_FRAME_GAP_MS 5
#define DEAD_BAND 100

#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE

#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Dir_Change_Order 0xDD

#define LED_PORT GPIO_P3
#define LED1_PIN GPIO_Pin_5
#define LED2_PIN GPIO_Pin_6
#define LED3_PIN GPIO_Pin_7
/* 蜂鸣器通道定义在 main.h（PWMA_CH4N_P33，与生成代码一致）。 */

static uint8_t control_frame_pack[21];
static int16_t rocker[4];
static int dutyOfMotor[8];

static void Uart1TxQuery(uint8_t dat)
{
    uint8_t uart1InterruptEnabled = ES;

    ES = 0;
    TI = 0;
    SBUF = dat;
    while (!TI)
        ;
    TI = 0;
    ES = uart1InterruptEnabled;
}

static void ExpansionBoradControl(uint8_t command,
                                  uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
                                  uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;

    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    /* 逐字展开落帧：SDCC 对「数组 + 变址」取字节有误。 */
    control_frame_pack[3] = (uint8_t)((p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(p77 & 0xFF);
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;

    for (i = 0; i < 21; i++)
        Uart1TxQuery(control_frame_pack[i]);
}

static void ReadControllerInputs(void)
{
    uint8_t i;

    for (i = 0; i < 4; i++)
        rocker[i] = Nrf_Rocker(i);

    for (i = 0; i < 4; i++)
    {
        if (abs((int)rocker[i]) <= DEAD_BAND)
            rocker[i] = 0;
    }
}

static void ZeroControllerInputs(void)
{
    uint8_t i;

    for (i = 0; i < 4; i++)
        rocker[i] = 0;
}

static int32_t ClampDuty(int32_t v)
{
    if (v < -10000L)
        return -10000L;
    if (v > 10000L)
        return 10000L;
    return v;
}

static int32_t ScaleDuty(int32_t v)
{
    return ClampDuty((v * 10000L) / 2047L);
}

/*
 * 摇杆索引与 remote_control.h 的 ROCKER_OFFSET_t 一致：
 *   0 = 左摇杆垂直(LY)，1 = 左摇杆水平(LX)，
 *   2 = 右摇杆垂直(RY)，3 = 右摇杆水平(RX)。
 */
static void RunMecanum(void)
{
    int32_t vx = -(int32_t)rocker[0];   /* -LY */
    int32_t vy = -(int32_t)rocker[1];   /* -LX */
    int32_t turn = -(int32_t)rocker[3]; /* -RX */

    dutyOfMotor[0] = 0;
    dutyOfMotor[1] = 0;
    dutyOfMotor[2] = 0;
    dutyOfMotor[3] = 0;
    dutyOfMotor[4] = (int)ScaleDuty(vx - vy - turn);
    dutyOfMotor[5] = (int)ScaleDuty(vx + vy - turn);
    dutyOfMotor[6] = (int)ScaleDuty(-(vx + vy + turn));
    dutyOfMotor[7] = (int)ScaleDuty(-(vx - vy + turn));
}

/*
 * 蜂鸣器：静音 / 试音。
 * 调试台命令 z（静音）与 p（1 kHz 200 ms）直接调用，用来区分
 * “初始化提示音反复响是复位”还是“PWM 停在发声状态”。
 */
void Buzzer_Silence(void)
{
    PWM_SET_Frequency(BUZZER_CH, 500, 0);
}

void Buzzer_Beep(uint16_t freq, uint16_t ms)
{
    PWM_SET_Frequency(BUZZER_CH, freq, 5000);
    Ms_Delay(ms);
    PWM_SET_Frequency(BUZZER_CH, freq, 0);
}

static void Beep(uint16_t freq, uint16_t ms)
{
    Buzzer_Beep(freq, ms);
}

static void All_Init(void)
{
    Board_Init();
    Dbg_Init(PIE_BLOCK_FW_HASH, PIE_BLOCK_BUILD_DATE);

    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
    PWM_Init(BUZZER_CH, 500, 0);

    Nrf_Init();
    P2INTE &= ~GPIO_Pin_6; /* 关闭 nRF IRQ 外部中断，主循环轮询 */
    Dbg_BootNrfReport();   /* nRF 初始化结果与关键寄存器回读（每次启动都打） */

    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000);
    Ms_Delay(EXPANSION_FRAME_GAP_MS);

    Beep(523, 120);
    Beep(659, 120);
    Beep(784, 120);
    Beep(1047, 240);
    Buzzer_Silence();

    /* 初始化完成标记：复位循环时串口会反复出现这一行的 t=0~ 很接近的值。 */
    Dbg_InitDone();
}

void main(void)
{
    uint32_t loop_start;
    uint32_t exp_start;
    uint16_t loop_ms;
    uint16_t exp_ms;

    All_Init();

    while (1)
    {
        loop_start = Dbg_Millis();

        Nrf_Handler();
        Dbg_AfterNrfHandler();
        Dbg_PollCommands();

        ReadControllerInputs();
        if (Dbg_AgeMs() > DBG_LINK_TIMEOUT_MS)
            ZeroControllerInputs();

        RunMecanum();

        exp_start = Dbg_Millis();
        ExpansionBoradControl(Dir_Change_Order,
                              dutyOfMotor[0] >= 0, dutyOfMotor[1] >= 0,
                              dutyOfMotor[2] >= 0, dutyOfMotor[3] >= 0,
                              dutyOfMotor[4] >= 0, dutyOfMotor[5] >= 0,
                              dutyOfMotor[6] >= 0, dutyOfMotor[7] >= 0);
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
        ExpansionBoradControl(Duty_Change_Order,
                              (uint16_t)abs(dutyOfMotor[0]), (uint16_t)abs(dutyOfMotor[1]),
                              (uint16_t)abs(dutyOfMotor[2]), (uint16_t)abs(dutyOfMotor[3]),
                              (uint16_t)abs(dutyOfMotor[4]), (uint16_t)abs(dutyOfMotor[5]),
                              (uint16_t)abs(dutyOfMotor[6]), (uint16_t)abs(dutyOfMotor[7]));
        Ms_Delay(EXPANSION_FRAME_GAP_MS);
        exp_ms = (uint16_t)(Dbg_Millis() - exp_start);

        Nrf_SendTelemetry(dutyOfMotor[0], dutyOfMotor[1], dutyOfMotor[2], dutyOfMotor[3],
                          dutyOfMotor[4], dutyOfMotor[5], dutyOfMotor[6], dutyOfMotor[7],
                          0, 0);
        Ms_Delay(10);

        loop_ms = (uint16_t)(Dbg_Millis() - loop_start);
        Dbg_EndLoop(loop_ms, exp_ms);
    }
}

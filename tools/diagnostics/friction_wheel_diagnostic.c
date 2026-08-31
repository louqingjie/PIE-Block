/*
 * 摩擦轮独立诊断固件（STC32G12K128 + CNU_W.PIE 机械拓展板）
 *
 * 目的：完全绕开 NRF 遥控器、步兵状态机和代码生成器运行时控制逻辑，
 *       只验证 UART1 -> 机械拓展板 -> P64/P66 -> 摩擦轮这条硬件链路。
 *
 * 上电后的自动测试顺序（每阶段开始前停 3 秒）：
 *   1. P35 LED 亮：只测试 P64 右摩擦轮
 *   2. P36 LED 亮：只测试 P66 左摩擦轮
 *   3. P37 LED 亮：P64/P66 两个摩擦轮同时测试
 *   4. P35/P36/P37 全亮：测试结束，所有动力输出保持为 0
 *
 * 每个阶段均按 500 -> 600 -> 700 -> 800 安全升速，再逐级降到 0。
 * 最高占空比 800，低于指南上限 1100。请勿在测试过程中直接切断执行器电源。
 */

#include "main.h"

#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE

#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Dir_Change_Order 0xDD

#define DIAG_LED_PORT GPIO_P3
#define DIAG_LED_LEFT GPIO_Pin_5
#define DIAG_LED_RIGHT GPIO_Pin_6
#define DIAG_LED_BOTH GPIO_Pin_7

#define RAMP_STEP_DELAY_MS 1500
#define PHASE_READY_DELAY_MS 3000
#define PHASE_HOLD_DELAY_MS 3000

/* 工程模板始终链接 nrf24l01.c；即使本诊断不启用 NRF，也需满足其 extern。 */
uint8_t Channal = 3;

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

static void ExpansionBoradControl(uint8_t control_cmd,
                                  uint16_t data_p60, uint16_t data_p62,
                                  uint16_t data_p64, uint16_t data_p66,
                                  uint16_t data_p74, uint16_t data_p75,
                                  uint16_t data_p76, uint16_t data_p77)
{
    uint8_t i;
    uint8_t control_frame_pack[21] = {0};

    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = control_cmd;
    control_frame_pack[3] = (uint8_t)(data_p60 >> 8);
    control_frame_pack[4] = (uint8_t)data_p60;
    control_frame_pack[5] = (uint8_t)(data_p62 >> 8);
    control_frame_pack[6] = (uint8_t)data_p62;
    control_frame_pack[7] = (uint8_t)(data_p64 >> 8);
    control_frame_pack[8] = (uint8_t)data_p64;
    control_frame_pack[9] = (uint8_t)(data_p66 >> 8);
    control_frame_pack[10] = (uint8_t)data_p66;
    control_frame_pack[11] = (uint8_t)(data_p74 >> 8);
    control_frame_pack[12] = (uint8_t)data_p74;
    control_frame_pack[13] = (uint8_t)(data_p75 >> 8);
    control_frame_pack[14] = (uint8_t)data_p75;
    control_frame_pack[15] = (uint8_t)(data_p76 >> 8);
    control_frame_pack[16] = (uint8_t)data_p76;
    control_frame_pack[17] = (uint8_t)(data_p77 >> 8);
    control_frame_pack[18] = (uint8_t)data_p77;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;

    for (i = 0; i < 21; i++)
        Uart1TxQuery(control_frame_pack[i]);
}

static void ShowPhase(uint8_t phase)
{
    GPIO_Write_Bit(DIAG_LED_PORT, DIAG_LED_LEFT, phase == 1 || phase == 4 ? 0 : 1);
    GPIO_Write_Bit(DIAG_LED_PORT, DIAG_LED_RIGHT, phase == 2 || phase == 4 ? 0 : 1);
    GPIO_Write_Bit(DIAG_LED_PORT, DIAG_LED_BOTH, phase == 3 || phase == 4 ? 0 : 1);
}

static void SetFrictionDuty(uint16_t left_duty, uint16_t right_duty)
{
    /* 与官方可运行示例保持相同顺序：先占空比帧，再方向帧。 */
    ExpansionBoradControl(Duty_Change_Order,
                          0, 0, left_duty, right_duty,
                          0, 0, 0, 0);
    ExpansionBoradControl(Dir_Change_Order,
                          1, 1, 0, 0,
                          1, 1, 1, 1);
}

static void SetPhaseDuty(uint8_t phase, uint16_t duty)
{
    if (phase == 1)
        SetFrictionDuty(duty, 0);
    else if (phase == 2)
        SetFrictionDuty(0, duty);
    else
        SetFrictionDuty(duty, duty);
}

static void RunFrictionPhase(uint8_t phase)
{
    ShowPhase(phase);
    SetFrictionDuty(0, 0);
    Ms_Delay(PHASE_READY_DELAY_MS);

    SetPhaseDuty(phase, 500);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetPhaseDuty(phase, 600);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetPhaseDuty(phase, 700);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetPhaseDuty(phase, 800);
    Ms_Delay(PHASE_HOLD_DELAY_MS);

    SetPhaseDuty(phase, 700);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetPhaseDuty(phase, 600);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetPhaseDuty(phase, 500);
    Ms_Delay(RAMP_STEP_DELAY_MS);
    SetFrictionDuty(0, 0);
    Ms_Delay(RAMP_STEP_DELAY_MS);
}

void main(void)
{
    Board_Init();

    GPIO_Init(DIAG_LED_PORT,
              (GPIO_Pin_enum)(DIAG_LED_LEFT | DIAG_LED_RIGHT | DIAG_LED_BOTH),
              GPIO_OUT_PP);
    ShowPhase(0);

    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    Ms_Delay(1000);

    /* 完全采用官方示例的初始化频率组合，排除 0Hz 和混合时基干扰。 */
    ExpansionBoradControl(Init_Order,
                          50, 50, 50, 50,
                          10000, 10000, 10000, 10000);
    SetFrictionDuty(0, 0);
    Ms_Delay(2000);

    RunFrictionPhase(1); /* P64 */
    RunFrictionPhase(2); /* P66 */
    RunFrictionPhase(3); /* P64 + P66 */

    SetFrictionDuty(0, 0);
    ShowPhase(4);
    while (1)
    {
        /* 测试结束后保持所有动力输出为 0。 */
        Ms_Delay(1000);
    }
}

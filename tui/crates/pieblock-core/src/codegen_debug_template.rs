// 调试测试代码（由 PIE-Block Flutter 配置器自动生成）
#include "main.h"

/* 提示音方案（详见 docs/design/调试模式提示音方案.md）：
   步序用一条上行音型 C6-E6-G6-C7-E7 的前 N 个音表示第 N 项
   （个数即序号，不单独播一遍完整音型做前奏，也没有结束区的回落乐句）。
   音区（八度）负责进位：项 1~5 低八度，项 6 起高八度。
   整段测试序列放在 while (1) 里循环执行：跑完最后一项自动回到第 1 项，
   没有「全部完成」的收尾旋律。 */
uint8_t Channal = 36;
#define BUZZER_CH PWMA_CH4N_P33
#define BUZZER_DUTY_ON 5000
/* 静音占位频率：占空比为 0，频率取值不影响是否有声 */
#define BUZZER_IDLE_FREQ 500
/* 音高：十二平均律，A4 = 440Hz */
#define CUE_C5 523
#define CUE_E5 659
#define CUE_G5 784
#define CUE_C6 1047
#define CUE_E6 1319
#define CUE_G6 1568
#define CUE_C7 2093
#define CUE_E7 2637
/* 上行音型：C6-E6-G6-C7-E7。步序用它的前 N 个音表示第 N 项（个数即序号），
   音型本身不单独播放。 */
#define CUE_MOTIF_LEN 5
/* 步序码：八度音区进位（项 1~5 低八度，项 6 起高八度） */
#define CUE_ZONE_SPAN 5
#define CUE_UNIT_MS 220
#define CUE_GAP_MS 140
/* 分区停顿：步序音与随后的测试动作之间的静默，
   必须明显长于 CUE_GAP_MS，否则动作噪音会盖掉步序音。 */
#define CUE_SECTION_GAP_MS 300
/* 项间与循环边界的静默：跑完最后一项后同样等这么久再回到第 1 项。 */
#define TEST_GAP_MS 1000
#define FRICTION_STEP_MS 1500
#define FRICTION_START_DUTY 500
#define FRICTION_STEP_DUTY 1
#define FRICTION_RAMP_CYCLE_MS 20
#define FRICTION_ACTIVATE_MS 1000
#define EXPANSION_FRAME_GAP_MS 5
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Dir_Change_Order 0xDD

static uint8_t control_frame_pack[21];

static void Uart1TxQuery(uint8_t dat)
{
    uint8_t uart1InterruptEnabled = ES;

    ES = 0;
    TI = 0;
    SBUF = dat;
    while (!TI) ;
    TI = 0;
    ES = uart1InterruptEnabled;
}

static void Beep(uint16_t frequency, uint16_t duration)
{
    PWM_SET_Frequency(BUZZER_CH, frequency, BUZZER_DUTY_ON);
    Ms_Delay(duration);
    PWM_SET_Frequency(BUZZER_CH, frequency, 0);
}

/* 上行音型第 index 个音（index 从 0 开始），high 为真时整体升八度。
   用 switch 而不是数组变址：SDCC 对 "数组 + 变址" 的写法有已知取错字节的
   问题（见 ExpansionBoradControl 里的注释），能避开就避开。 */
static uint16_t MotifNote(uint8_t index, uint8_t high)
{
    uint16_t octave = high ? 2 : 1;

    switch (index)
    {
    case 0: return (uint16_t)(CUE_C6 * octave);
    case 1: return (uint16_t)(CUE_E6 * octave);
    case 2: return (uint16_t)(CUE_G6 * octave);
    case 3: return (uint16_t)(CUE_C7 * octave);
    default: return (uint16_t)(CUE_E7 * octave);
    }
}

/* 步序提示：用上行音型的前 count 个音表示第 count 项——**个数即序号**，
   所以不需要先播一遍完整音型做前奏，也没有结束区的回落乐句。
   音区（八度）负责进位：项 1~5 用低八度那组，项 6 起换高八度那组。 */
static void StepCue(uint8_t step)
{
    uint8_t zone;
    uint8_t count;
    uint8_t i;

    zone = (uint8_t)((step - 1) / CUE_ZONE_SPAN);
    count = (uint8_t)((step - 1) % CUE_ZONE_SPAN + 1);
    for (i = 0; i < count; i++)
    {
        Beep(MotifNote(i, zone), CUE_UNIT_MS);
        if (i + 1 < count)
            Ms_Delay(CUE_GAP_MS);
    }
}

static void ExpansionBoradControl(uint8_t command,
    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,
    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)
{
    uint8_t i;
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[2] = command;
    /* 逐字展开落帧，与《RM电控指南》的参考实现一致：SDCC 对
       "values[] 数组 + 3+i*2 变址" 的写法会取错字节（低字节位置被写成高字节，
       即 10000 发成 0x2727、500 发成 0x0101），这里直接从形参取高/低字节。 */
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
    for (i = 0; i < 21; i++) {
        Uart1TxQuery(control_frame_pack[i]);
    }
}

static uint16_t frictionDuty = 0;

/* 只改当前测试那个脚的占空比，其余脚维持 0。按脚展开写，避免 SDCC 在
   "values[] + 变址" 上取错字节。 */
static void FrictionSendDuty(uint8_t slot, uint16_t duty)
{
    switch (slot) {
    case 0: ExpansionBoradControl(Duty_Change_Order, duty, 0, 0, 0, 0, 0, 0, 0); break;
    case 1: ExpansionBoradControl(Duty_Change_Order, 0, duty, 0, 0, 0, 0, 0, 0); break;
    case 2: ExpansionBoradControl(Duty_Change_Order, 0, 0, duty, 0, 0, 0, 0, 0); break;
    case 3: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, duty, 0, 0, 0, 0); break;
    case 4: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, duty, 0, 0, 0); break;
    case 5: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, duty, 0, 0); break;
    case 6: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, duty, 0); break;
    default: ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, duty); break;
    }
}

/* 摩擦轮激活：给 500 启动占空比并保持 FRICTION_ACTIVATE_MS 让电调完成激活；
   这段激活时间不发蜂鸣。 */
static void FrictionActivate(uint8_t slot)
{
    frictionDuty = FRICTION_START_DUTY;
    FrictionSendDuty(slot, frictionDuty);
    PWM_SET_Frequency(BUZZER_CH, BUZZER_IDLE_FREQ, 0);
    Ms_Delay(FRICTION_ACTIVATE_MS);
}

/* 摩擦轮斜坡控制与步兵项目同律：静止先跳到启动占空比，其余每周期
   ±FRICTION_STEP_DUTY 渐变；目标为 0 且已降到启动占空比及以下直接停机。
   渐变期间蜂鸣频率等于当前占空比，启动爬升即为上行扫频。 */
static void FrictionRampTo(uint8_t slot, uint16_t target)
{
    while (frictionDuty != target) {
        if (target >= FRICTION_START_DUTY && frictionDuty < FRICTION_START_DUTY)
            frictionDuty = FRICTION_START_DUTY;
        else if (frictionDuty < target)
            frictionDuty += FRICTION_STEP_DUTY;
        else if (target == 0 && frictionDuty <= FRICTION_START_DUTY)
            frictionDuty = 0;
        else
            frictionDuty -= FRICTION_STEP_DUTY;
        FrictionSendDuty(slot, frictionDuty);
        if (frictionDuty)
            PWM_SET_Frequency(BUZZER_CH, frictionDuty, 5000);
        else
            PWM_SET_Frequency(BUZZER_CH, BUZZER_IDLE_FREQ, 0);
        Ms_Delay(FRICTION_RAMP_CYCLE_MS);
    }
}

void main(void)
{
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    PWM_Init(BUZZER_CH, BUZZER_IDLE_FREQ, 0);

    /* 整段测试序列循环执行：跑完最后一项自动回到第 1 项。 */
    while (1)
    {
        /* 每轮开头先把两组 PWM 复位到 main 起始的 50Hz。逐项那条 Init 是
           生成期按「上一项之后」的静态状态决定要不要发的，只有每轮都从
           同一个状态起步，这条静态判断在第二轮及以后才继续成立。 */
        ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 50, 50, 50, 50);
        Ms_Delay(20);

__LOOP_BODY__

        /* 一轮结束：八路输出全部归零，随后回到第 1 项。 */
        ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
    }
}

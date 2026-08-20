// 步兵机器人操作代码（由 Pie-Block 配置生成器自动生成）
#include "main.h"
#include "MATH.H"
// ========================= 参数区 =========================
uint8_t Channal = 36;                          // NRF24L01 通信通道（0-125），与遥控器一致
uint16_t maxSpeed = 4000;
uint16_t ultraSpeed = 8000;
uint16_t deadBandOfLeft = 10;                   // 左摇杆中心死区
uint16_t deadBandOfRight = 10;                  // 右摇杆中心死区
// 舵机占空比：250=-90°，750=中位(0°)，1250=+90°，总行程 180°
#define SERVO_DUTY_MIN     250
#define SERVO_DUTY_MID     750
#define SERVO_DUTY_MAX     1250
// 每度对应的占空比增量（1000 duty / 180°）
#define SERVO_DUTY_PER_DEG 5.555556f
uint16_t midDutyOfServo[2] = {750, 750};        // 云台水平/垂直舵机中值（归中角 +0° / +0°）
// 摇杆可摆动幅度 ±60°（相对归中位置）
uint16_t maxChangeDutyOfServo[2] = {333, 333};
uint16_t singleChangeDutyOfBooster = 100;       // 按下按键单次占空比改变量
uint16_t maxDutyOfBooster = 1100;               // 摩擦轮最大占空比（指南上限，不得提高）
uint16_t minDutyOfBooster = 500;                // 摩擦轮最低有效占空比
uint16_t boosterDutyOfFeed = 6000;             // 拨弹电机单发转动占空比
uint16_t boosterFeedDelayMs = 100;              // 拨弹电机单发转动时长(ms)
// 摇杆推到底时云台每周期转过 2.0°
float changeRateOfServo[2] = {0.005428, 0.005428};

#define LIMIT_VALUE(x, min, max) \
    do                           \
    {                            \
        if ((x) < (min))         \
            (x) = (min);         \
        else if ((x) > (max))    \
            (x) = (max);         \
    } while (0)
/*帧头帧尾，内部调用，无需关心*/
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
/*命令码*/
#define Init_Order 0xAA        // 初始化模式
#define Duty_Change_Order 0xBB // 修改占空比
#define Freq_Change_Order 0xCC // 修改频率
#define Dir_Change_Order 0xDD  // 修改方向 1为正 0为负 设置一次即可
#define Zero_Order 0xEE        // 0命令
/*内部调用变量，无需关心，请勿定义同名变量*/
uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;
// 自定义变量
float floatDutyOfServo[2]; // 云台舵机
uint16_t dutyOfServo[2];
int dutyOfMotor[5]; // 底盘电机、供弹电机、云台电机（如有）
uint16_t dutyOfBooster = 0, expectDutyOfBooster = 0;
uint16_t levelDutyOfBooster = 1100; // 摩擦轮目标转速档位（B/C 键微调）
uint8_t valueOfKey[3][4];
uint8_t valueOfEKey;
uint8_t triggerKeyValue, lastTriggerKeyValue, boosterKeyValue, lastBoosterKeyValue;
uint8_t lastBoosterUpKeyValue = 0, lastBoosterDownKeyValue = 0;
uint8_t statusOfBooster = 0;
uint8_t i, j;
int valueOfRoker[2][2] // 左摇杆水平、竖直；右摇杆水平、竖直
    ,
    baseSpeed, turnSpeed;
static const uint8_t keyOffsets[3][4] = {
    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},
    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},
    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个
};

void All_Init();
void ReadControllerInputs();
void CalculateMotorControls();
void CalculateGimbalControls();
void CalculateBoosterControl();
uint8_t Get_Dir(int rawdata);
void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster);
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77);

static void remoteControlInitWithTimeout(void)
{
    uint8_t retry;

    for (retry = 0; retry < 20; retry++)
    {
        if (NRF24L01_Init())
        {
            Ms_Delay(200);
            return;
        }
        Ms_Delay(10);
    }
}

// ==================== 初始化诊断：3 颗 LED + 蜂鸣器 ====================
// 3 颗 LED（低电平点亮）+ 蜂鸣器（PWM 驱动），把初始化拆成多步，
// 每步用 LED 编码 + 蜂鸣器音调双重定位：
//   - 进入某步前：LED 显示该步编码（3 bit 二进制，P35=bit0 P36=bit1 P37=bit2）
//   - 该步成功后：蜂鸣器响一声推进确认音（音调随步骤递增）
//   - 若某步阻塞：LED 停在编码、听不到后续确认音 -> 对照编码表定位
#define LED_PORT GPIO_P3
#define LED1_PIN GPIO_Pin_5   // 编码 bit0
#define LED2_PIN GPIO_Pin_6   // 编码 bit1
#define LED3_PIN GPIO_Pin_7   // 编码 bit2
#define BUZZER_CH PWMB_CH3_P33  // 蜂鸣器（PWM 驱动）

// LED 显示步骤编码 0~7（低电平点亮：0=亮 1=灭）
static void LedShow(uint8_t show)
{
    GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);
}

// 蜂鸣器响一声（PWM 驱动，freq 音调 / ms 时长）
static void Beep(uint16_t freq, uint16_t ms)
{
    PWM_SET_Frequency(BUZZER_CH, freq, 5000);
    Ms_Delay(ms);
    PWM_SET_Frequency(BUZZER_CH, freq, 0);
}

// 进入某步：先显示编码（若该步阻塞，LED 就停在这里）
static void StepBegin(uint8_t step)
{
    LedShow(step & 0x07);
}

// 某步初始化成功：蜂鸣器推进确认音（音调随步骤递增，可听声定位）
static void StepDone(uint8_t step)
{
    Beep(500 + (uint16_t)(step % 8) * 60, 60);
}

// UART1 查询发送一字节：不依赖 UART1 TX 中断（避免 UART_PutChar 的
// UART_BUSY 死锁——TX 中断被 NRF P2.6 高优先级中断抢占时 BUSY 永远清不掉）。
// 发送期间临时关串口中断，轮询硬件 TI 标志。要求 UART1 已 UART_Init 初始化。
static void Uart1TxQuery(uint8_t dat)
{
    ES = 0;          // 关 UART1 中断，避免中断抢先清 TI 导致死锁
    SBUF = dat;      // 启动发送
    while (!TI)      // 等硬件发送完成（TI 与中断无关，必定置位）
        ;
    TI = 0;          // 清发送完成标志
    ES = 1;          // 恢复 UART1 中断
}

void main()
{
    All_Init();
    floatDutyOfServo[0] = midDutyOfServo[0];
    floatDutyOfServo[1] = midDutyOfServo[1];
    while (1)
    {
        nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）
        // 测试手柄连接状态
        if (RcKeyValueRead(KEY_OFFSET_UP))
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);
        else
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);

        ReadControllerInputs();    // 统一读取输入
        CalculateMotorControls();  // 计算电机控制
        CalculateGimbalControls(); // 计算云台控制
        CalculateBoosterControl(); // 计算摩擦轮控制
        LIMIT_VALUE(dutyOfMotor[0], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[1], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[2], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[3], -10000, 10000);
        LIMIT_VALUE(dutyOfMotor[4], 0, 10000);
        // Yaw 限幅 417~1083（归中 +0° ±60°，已收敛到舵机行程内）
        LIMIT_VALUE(floatDutyOfServo[0], 417, 1083);
        // Pitch 限幅 417~1083（归中 +0° ±60°，已收敛到舵机行程内）
        LIMIT_VALUE(floatDutyOfServo[1], 417, 1083);
        // 扳机键单发拨弹：上升沿触发，拨弹电机转动 boosterFeedDelayMs 后停转，期间阻塞主线程
        if (triggerKeyValue && !lastTriggerKeyValue)
        {
            dutyOfMotor[4] = boosterDutyOfFeed;
            // 注意：此处保持 dutyOfBooster 不变，不能跳变到目标值，
            // 否则会违反摩擦轮占空比渐变要求
            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
            Ms_Delay(boosterFeedDelayMs);
            dutyOfMotor[4] = 0;
            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
        }
        lastTriggerKeyValue = triggerKeyValue;

        // 摩擦轮占空比平滑变化
        // 主循环周期 10ms，每周期变化 1 => 每秒 100 占空比，
        // 符合《RM电控指南》「每秒增加/减少 100 占空比」的硬性要求，不得提高步长
        // 从静止启动时先跳到 500（指南：启停不考虑 0~5% 区间）
        if (expectDutyOfBooster >= 500 && dutyOfBooster < 500)
            dutyOfBooster = 500;
        else if (dutyOfBooster < expectDutyOfBooster)
            dutyOfBooster++;
        else if (dutyOfBooster > expectDutyOfBooster)
        {
            // 降到 500 以下时直接停机，避免在低占空比区间长时间堵转
            if (dutyOfBooster <= 500 && expectDutyOfBooster == 0)
                dutyOfBooster = 0;
            else
                dutyOfBooster--;
        }

        // 发送控制函数
        Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);
        Ms_Delay(10);
    }
}

uint8_t Get_Dir(int rawdata)
{
    if (rawdata >= 0)
        return 1;
    else
        return 0;
}

void All_Init()
{
    // 初始化诊断分步：卡在哪步，LED 就停在对应编码（P37 P36 P35 二进制）
    //   000 上电   001 Board_Init   010 UART1   011 LED 自检
    //   100 NRF遥控 101 拓展板 Init 110 PWM/舵机 111 完成
    StepBegin(0);
    Board_Init();
    StepDone(0);
    StepBegin(1);
    // 串口必须最先初始化：UART1 是扩展板控制的唯一通道。
    // 放在外设之后的话，一旦某个外设没接好卡住初始化，
    // 扩展板控制就彻底失效了。
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    StepDone(1);
    StepBegin(2);
    // 诊断 LED（P35/P36/P37）推挽输出，全亮自检后熄灭
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
    LedShow(7);
    Ms_Delay(200);
    LedShow(0);
    // 蜂鸣器通道必须 PWM_Init（使能输出+启动定时器），否则 Beep 无声
    PWM_Init(BUZZER_CH, 500, 0);
    StepDone(2);
    StepBegin(3);
    // NRF 遥控器初始化：全程关中断 + 初始化后关 P2.6 EXTI
    // （P2.6 高优先级中断在 ISR 里做 SPI/reentrant，遥控器开着会卡死；
    //  接收改为主循环轮询 nrf_handler()，见主循环开头）
    EA = 0;
    remoteControlInitWithTimeout();
    P2INTE &= ~GPIO_Pin_6; // 关 P2.6 EXTI：接收改主循环轮询
    EA = 1;
    StepDone(3);
    StepBegin(4);
    ExpansionBoradControl(Init_Order,
                          10000, 0,
                          50, 50,
                          10000, 10000,
                          10000, 10000); // p60,p62,p64,p66,p74,p75,p76,p77
    // 摩擦轮初始化后必须留 >=1000ms 硬件反应时间（见《RM电控指南》），不得缩短
    Ms_Delay(1000);
    StepDone(4);
    StepBegin(5);
    PWM_Init(PWMB_CH1_P74, 50, midDutyOfServo[0]); // 云台水平舵机
    PWM_Init(PWMB_CH4_P03, 50, midDutyOfServo[1]); // 云台垂直舵机
    StepDone(5);
    // 初始化完成提示音：P33 蜂鸣器演奏上行琶音
    Beep(523, 120);
    Beep(659, 120);
    Beep(784, 120);
    Beep(1047, 240);
}

void ReadControllerInputs()
{
    // 摇杆读数读取
    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
    // 死区过滤
    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)
        valueOfRoker[0][0] = 0;
    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)
        valueOfRoker[0][1] = 0;
    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)
        valueOfRoker[1][0] = 0;
    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)
        valueOfRoker[1][1] = 0;

    for (i = 0; i < 3; i++)
    {
        for (j = 0; j < 4; j++)
        {
            if (i == 2 && j >= 2)
                break; // 第三行只有2个按键
            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);
        }
    }
    // 读取扳机键和摩擦轮开关键
    triggerKeyValue = RcKeyValueRead(KEY_OFFSET_1);
    boosterKeyValue = RcKeyValueRead(KEY_OFFSET_A);
}

void CalculateMotorControls()
{

    // 冲刺模式：按下左摇杆时使用冲刺速度
    if (valueOfKey[2][0])
    {
        baseSpeed = (int)((float)valueOfRoker[0][1] * ultraSpeed / 2047);
        turnSpeed = (int)((float)valueOfRoker[0][0] * ultraSpeed / 2047);
    }
    else
    {
        baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);
        turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);
    }

    // 方向键设为移动
    if (valueOfKey[0][0] == 1)
        baseSpeed = maxSpeed;
    if (valueOfKey[0][1] == 1)
        baseSpeed = -maxSpeed;
    if (valueOfKey[0][2] == 1)
        turnSpeed = -maxSpeed;
    if (valueOfKey[0][3] == 1)
        turnSpeed = maxSpeed;
    dutyOfMotor[0] = -baseSpeed - turnSpeed;
    dutyOfMotor[1] = -baseSpeed - turnSpeed;
    dutyOfMotor[2] = baseSpeed - turnSpeed;
    dutyOfMotor[3] = baseSpeed - turnSpeed;

    // 供弹电机控制值计算
    if (valueOfKey[1][3])
        dutyOfMotor[4] = 0;
}

void CalculateBoosterControl()
{
    // B/C 键上升沿微调摩擦轮目标转速档位（不是直接改 expectDutyOfBooster，
    // 否则会被下面的开关逻辑覆盖）。档位限制在 500~1100，上限由指南规定
    if (valueOfKey[1][1] && !lastBoosterUpKeyValue)
    {
        if (levelDutyOfBooster + singleChangeDutyOfBooster <= maxDutyOfBooster)
            levelDutyOfBooster += singleChangeDutyOfBooster;
        else
            levelDutyOfBooster = maxDutyOfBooster;
    }
    if (valueOfKey[1][2] && !lastBoosterDownKeyValue)
    {
        if (levelDutyOfBooster >= minDutyOfBooster + singleChangeDutyOfBooster)
            levelDutyOfBooster -= singleChangeDutyOfBooster;
        else
            levelDutyOfBooster = minDutyOfBooster;
    }
    lastBoosterUpKeyValue = valueOfKey[1][1];
    lastBoosterDownKeyValue = valueOfKey[1][2];

    // 摩擦轮开关由 A 上升沿翻转
    if (boosterKeyValue && !lastBoosterKeyValue)
    {                                       // 检测上升沿
        statusOfBooster = !statusOfBooster; // 翻转状态
    }
    lastBoosterKeyValue = boosterKeyValue;

    if (statusOfBooster)
        expectDutyOfBooster = levelDutyOfBooster;
    else
        expectDutyOfBooster = 0;
}

void CalculateGimbalControls()
{
    // 云台舵机控制值计算
    floatDutyOfServo[0] += valueOfRoker[1][0] * changeRateOfServo[0];
    floatDutyOfServo[1] += valueOfRoker[1][1] * changeRateOfServo[1];
    dutyOfServo[0] = (uint16_t)floatDutyOfServo[0];
    dutyOfServo[1] = (uint16_t)floatDutyOfServo[1];
}

void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster)
{
    ExpansionBoradControl(Dir_Change_Order,
                          1, 1,
                          0, 0,
                          Get_Dir(dutyOfMotor[0]), Get_Dir(dutyOfMotor[1]),
                          Get_Dir(dutyOfMotor[2]), Get_Dir(dutyOfMotor[3]));
    Ms_Delay(5);
    ExpansionBoradControl(Duty_Change_Order, dutyOfMotor[4], 0,
                          dutyOfBooster, dutyOfBooster,
                          (uint16_t)abs(dutyOfMotor[0]), (uint16_t)abs(dutyOfMotor[1]),
                          (uint16_t)abs(dutyOfMotor[2]), (uint16_t)abs(dutyOfMotor[3]));
    Ms_Delay(5);
    PWM_SET_Frequency(PWMB_CH1_P74, 50, dutyOfServo[0]);
    PWM_SET_Frequency(PWMB_CH4_P03, 50, dutyOfServo[1]);
}

/// @brief 板间通信函数，用于主控给拓展版发送
/// @param control_cmd
/// @param data_p60 供弹电机
/// @param data_p62 空
/// @param data_p64 摩擦轮L
/// @param data_p66 摩擦轮R
/// @param data_p74 左前电机
/// @param data_p75 左后电机
/// @param data_p76 右前电机
/// @param data_p77 右后电机
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77)
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
        Uart1TxQuery(control_frame_pack[i]); // 查询发送，不依赖 TX 中断
}

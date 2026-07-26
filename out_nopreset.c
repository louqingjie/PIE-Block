// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）
#include "main.h"
#include "MATH.H"
// ========================= 参数区 =========================
// 机械臂构型：3轴（底座旋转+2连杆）
#define L1   100.00f   // 大臂长度(mm)
#define L2   80.00f   // 小臂长度(mm)
#define JOINT_COUNT 3
// 肘部弯曲方向（+1 / -1），与关节初始角符号一致
#define ELBOW_SIGN  1.0f
// 逆解可达性判定的最小半径，避免除零
#define IK_EPS  0.001f
// 舵机占空比参数（50Hz）
// 关节角以舵机中位为 0°，行程 ±90°（对应物理 0~180°）
#define SERVO_MID_DUTY  750   // 0°
#define SERVO_MIN_DUTY  500   // -90°
#define SERVO_MAX_DUTY  1000  // +90°
#define SERVO_DUTY_PER_DEG  2.7778f
// 摇杆推到满偏时末端每周期位移(mm)
#define JOY_SCALE  5.00f
// 按键长按时末端每周期位移(mm)
#define KEYMOVE_SPEED  2.00f
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
uint8_t Channal = 36;                          // NRF24L01 通信通道（0-125），与遥控器一致
// 自定义变量
uint16_t dutyOfServo[3];       // 各关节舵机占空比
float    jointAngle[3];        // 各关节角度(度)
float    targetX, targetY, targetZ;
uint8_t  ik_reachable;          // 逆解算可达性标志(1=可达,0=越界已钳位)
uint8_t  presetHit;             // 本周期是否命中预设点位
int16_t  valueOfRoker[2][2];    // 左摇杆水平、竖直；右摇杆水平、竖直
uint16_t deadBandOfLeft = 10;
uint16_t deadBandOfRight = 10;
uint8_t  i;
// 各关节初始角度(度)，以舵机中位为 0°
const float jointHome[3] = {30.00f, 30.00f, 30.00f};
// 各关节限位(度) [min, max]，以舵机中位为 0°，可表达范围 ±90°
const float jointMin[3] = {-90.00f, -90.00f, -90.00f};
const float jointMax[3] = {90.00f, 90.00f, 90.00f};
// 各关节方向(1=正向, 0=反向)，仅在 angle_to_duty 中生效
const uint8_t jointDir[3] = {1, 0, 1};
// 预设点位数量
#define PRESET_COUNT 0
// 未配置预设点位，故不生成 presetKey / presetPos 数组

void All_Init();
void ReadControllerInputs();
void CalculateIK(uint8_t hit);
void ApplyServoControl();
uint16_t angle_to_duty(int joint, float angle);
void ik_solve(float x, float y, float z);
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77);

void main()
{
    All_Init();
    // 初始化各关节到初始角度
    for (i = 0; i < JOINT_COUNT; i++)
        jointAngle[i] = jointHome[i];
    // 增量模式起点：初始姿态对应的末端位置（GUI 端正运动学预计算）
    targetX = 109.64f; targetY = 63.30f; targetZ = 119.28f;
    ik_reachable = 1;
    while (1)
    {
        // 测试手柄连接状态
        if (RcKeyValueRead(KEY_OFFSET_UP))
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);
        else
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);
        ReadControllerInputs();
        presetHit = 0;                 // 未配置预设点位
        CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算
        ApplyServoControl();           // 应用舵机控制
        Ms_Delay(5);                   // 与舵机发送延时合计 10ms/周期
    }
}

/// @brief 关节角度(度) -> 舵机占空比
/// @param joint 关节索引(0..JOINT_COUNT-1)
/// @param angle 角度(度)
/// @return 舵机占空比(SERVO_MIN_DUTY~SERVO_MAX_DUTY)
/// @note 角度以舵机中位为 0°，行程 ±90°：-90°=500, 0°=750, +90°=1000。
///       反向关节沿中位镜像；舵机方向只由占空比决定，
///       故不再向扩展板发 Dir_Change_Order。
uint16_t angle_to_duty(int joint, float angle)
{
    int duty;
    // 限位夹紧
    if (angle < jointMin[joint])
        angle = jointMin[joint];
    if (angle > jointMax[joint])
        angle = jointMax[joint];
    // 角度 -> 占空比（0° 即中位 750），反向关节沿中位镜像
    if (jointDir[joint])
        duty = (int)(SERVO_MID_DUTY + angle * SERVO_DUTY_PER_DEG);
    else
        duty = (int)(SERVO_MID_DUTY - angle * SERVO_DUTY_PER_DEG);
    if (duty < SERVO_MIN_DUTY)
        duty = SERVO_MIN_DUTY;
    if (duty > SERVO_MAX_DUTY)
        duty = SERVO_MAX_DUTY;
    return (uint16_t)duty;
}

/// @brief 逆解算：末端位置 -> 各关节角度
/// @param x 末端X(mm)
/// @param y 末端Y(mm)
/// @param z 末端Z(mm)
/// @note 结果写入 jointAngle[]，越界时钳到边界并设 ik_reachable=0
void ik_solve(float x, float y, float z)
{
    float r, c2, t1, t2, t0, rz, scale;
    ik_reachable = 1;
    // === 3 轴逆解（底座旋转 + 2连杆平面）===
    t0 = atan2(y, x);
    r = sqrt(x * x + y * y);
    rz = sqrt(r * r + z * z);
    // (r, z) 平面可达性；rz 过小时无方向可依，直接退到内边界正上方
    if (rz < IK_EPS)
    {
        ik_reachable = 0;
        r = fabs(L1 - L2);
        z = 0.0f;
        if (r < IK_EPS)
            r = L1 + L2;
    }
    else if (rz < fabs(L1 - L2))
    {
        ik_reachable = 0;
        scale = fabs(L1 - L2) / rz;
        r *= scale; z *= scale;
    }
    else if (rz > (L1 + L2))
    {
        ik_reachable = 0;
        scale = (L1 + L2) / rz;
        r *= scale; z *= scale;
    }
    c2 = (r * r + z * z - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);
    if (c2 > 1.0f) c2 = 1.0f;
    if (c2 < -1.0f) c2 = -1.0f;
    t2 = ELBOW_SIGN * acos(c2);
    t1 = atan2(z, r) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));
    jointAngle[0] = t0 * 180.0f / 3.14159265f;
    jointAngle[1] = t1 * 180.0f / 3.14159265f;
    jointAngle[2] = t2 * 180.0f / 3.14159265f;
}

/// @brief 读取摇杆并做死区过滤（按键在使用处直接 RcKeyValueRead 读取）
void ReadControllerInputs()
{
    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);
    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);
    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);
    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);
    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)
        valueOfRoker[0][0] = 0;
    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)
        valueOfRoker[0][1] = 0;
    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)
        valueOfRoker[1][0] = 0;
    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)
        valueOfRoker[1][1] = 0;
}

/// @brief 摇杆/按键输入末端位置增量 -> 逆解算
/// @param hit 1=本周期已由预设点位设定目标，跳过增量累加
/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，
///       松开后末端保持当前位置不动。
///       仅当上次目标可达时才回退，避免不可达的预设点位把目标永久卡死。
void CalculateIK(uint8_t hit)
{
    float lastX, lastY, lastZ;
    uint8_t lastReachable;
    // 备份上次目标，越界时回退（防止 target 无限增长导致松手后回不来）
    lastX = targetX; lastY = targetY; lastZ = targetZ;
    lastReachable = ik_reachable;
    if (!hit)
    {
        // 摇杆增量：摇杆值 -2047~2047 归一化后乘 JOY_SCALE 作为每周期位移
        targetX += (float)valueOfRoker[1][0] * JOY_SCALE / 2047.0f;
        targetY += (float)valueOfRoker[1][1] * JOY_SCALE / 2047.0f;
        targetZ += (float)valueOfRoker[1][0] * JOY_SCALE / 2047.0f;
        // 按键增量：长按时每周期移动 KEYMOVE_SPEED mm / KEYMOVE_PHI_SPEED 度
        if (RcKeyValueRead(KEY_OFFSET_UP))
            targetX += KEYMOVE_SPEED; // 末端X 正向（按键 ↑）
        if (RcKeyValueRead(KEY_OFFSET_DOWN))
            targetX -= KEYMOVE_SPEED; // 末端X 负向（按键 ↓）
        if (RcKeyValueRead(KEY_OFFSET_LEFT))
            targetY += KEYMOVE_SPEED; // 末端Y 正向（按键 ←）
        if (RcKeyValueRead(KEY_OFFSET_RIGHT))
            targetY -= KEYMOVE_SPEED; // 末端Y 负向（按键 ->）
        if (RcKeyValueRead(KEY_OFFSET_B))
            targetZ += KEYMOVE_SPEED; // 末端Z 正向（按键 B）
        if (RcKeyValueRead(KEY_OFFSET_C))
            targetZ -= KEYMOVE_SPEED; // 末端Z 负向（按键 C）
    }
    ik_solve(targetX, targetY, targetZ);
    // 越界则回退本周期增量，末端停在上一个可达位置；
    // 若上次目标本身就不可达（如预设点位超出量程），保留钳位结果以便摇杆能把末端拉回来
    if (!ik_reachable && !hit && lastReachable)
    {
        targetX = lastX; targetY = lastY; targetZ = lastZ;
        ik_solve(targetX, targetY, targetZ);
    }
}

/// @brief 应用舵机控制：关节角度 -> 占空比 -> 发送
void ApplyServoControl()
{
    for (i = 0; i < JOINT_COUNT; i++)
        dutyOfServo[i] = angle_to_duty(i, jointAngle[i]);
    // 扩展板舵机控制（频率 50Hz），未占用槽位传 0 表示维持原状
    ExpansionBoradControl(Duty_Change_Order,
                          0, 0,
                          0, 0,
                          dutyOfServo[0], dutyOfServo[1],
                          dutyOfServo[2], 0);
    Ms_Delay(5);
}

void All_Init()
{
    Board_Init();
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);
    remote_control_init();
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    // 扩展板舵机初始化（频率 50Hz），未占用槽位传 0 表示维持原状
    ExpansionBoradControl(Init_Order,
                          0, 0,
                          0, 0,
                          50, 50,
                          50, 0);
    Ms_Delay(20);
    // 舵机转向已在 angle_to_duty 中以占空比镜像实现，无需 Dir_Change_Order
    // 上电先把各关节推到初始角度
    ExpansionBoradControl(Duty_Change_Order,
                          0, 0,
                          0, 0,
                          angle_to_duty(0, jointHome[0]), angle_to_duty(1, jointHome[1]),
                          angle_to_duty(2, jointHome[2]), 0);
    Ms_Delay(20);
}

/// @brief 板间通信函数，用于主控给拓展版发送
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
        UART_PutChar(UART_1, control_frame_pack[i]);
}

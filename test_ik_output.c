// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）
#include "main.h"
#include "MATH.H"
// ========================= 参数区 =========================
// 机械臂构型：4轴（3轴+腕部俯仰）
#define L1   100.00f   // 大臂长度(mm)
#define L2   80.00f   // 小臂长度(mm)
#define L3   30.00f   // 腕部连杆长度(mm)
#define JOINT_COUNT 4
// 肘部弯曲方向（+1 / -1），与关节初始角符号一致
#define ELBOW_SIGN  1.0f
// 逆解可达性判定的最小半径，避免除零
#define IK_EPS  0.001f
// 舵机占空比参数（50Hz）
// 关节角以舵机中位为 0°，行程 ±90°（对应物理 0~180°）
#define SERVO_MID_DUTY  750   // 0°
#define SERVO_MIN_DUTY  250   // -90°
#define SERVO_MAX_DUTY  1250  // +90°
#define SERVO_DUTY_PER_DEG  5.5556f
// 摇杆推到满偏时末端每周期位移(mm)
#define JOY_SCALE  5.00f
// 按键长按时末端每周期位移(mm)
#define KEYMOVE_SPEED  2.00f
// 按键长按时末端姿态角每周期变化(度)
#define KEYMOVE_PHI_SPEED  2.00f
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
uint16_t dutyOfServo[4];       // 各关节舵机占空比
float    jointAngle[4];        // 各关节角度(度)
float    targetX, targetY, targetZ, targetPhi;
uint8_t  ik_reachable;          // 逆解算可达性标志(1=可达,0=越界已钳位)
uint8_t  presetHit;             // 本周期是否命中预设点位
int16_t  valueOfRoker[2][2];    // 左摇杆水平、竖直；右摇杆水平、竖直
uint16_t deadBandOfLeft = 10;
uint16_t deadBandOfRight = 10;
uint8_t  i;
// 各关节安装中位朝向(度，运动学角)：舵机处于中位时该关节的实际朝向。
// 舵机盘装歪时填这里，逆解算不受影响，只在 angle_to_duty 里换算掉。
const float jointOffset[4] = {0.00f, 0.00f, 0.00f, 0.00f};
// 各关节初始角度(度，运动学角)
const float jointHome[4] = {45.00f, 45.00f, 45.00f, 45.00f};
// 各关节限位(度，运动学角) [min, max]，可表达范围 = 中位朝向 ±90°
const float jointMin[4] = {-90.00f, -90.00f, -90.00f, -90.00f};
const float jointMax[4] = {90.00f, 90.00f, 90.00f, 90.00f};
// 各关节方向(1=正向, 0=反向)，仅在 angle_to_duty 中生效
const uint8_t jointDir[4] = {1, 1, 1, 1};
// 预设点位数量
#define PRESET_COUNT 1
// 预设点位：按键 KEY_OFFSET
const uint8_t presetKey[PRESET_COUNT] = {KEY_OFFSET_A};
// 预设点位末端坐标 {x, y, z, phi}
const float presetPos[PRESET_COUNT][4] = {
    {100.00f, 80.00f, 50.00f, 90.00f}  // P1 关节角度: [38.7, -29.2, 88.6, 30.7]
};

void All_Init();
void ReadControllerInputs();
void CalculateIK(uint8_t hit);
void ApplyServoControl();
uint8_t CheckPresetKeys();
uint16_t angle_to_duty(int joint, float angle);
void ik_solve(float x, float y, float z, float phi);
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
    targetX = 35.00f; targetY = 35.00f; targetZ = 171.92f; targetPhi = 135.00f;
    ik_reachable = 1;
    while (1)
    {
        // 测试手柄连接状态
        if (RcKeyValueRead(KEY_OFFSET_UP))
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);
        else
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);
        ReadControllerInputs();
        presetHit = CheckPresetKeys(); // 预设点位按键检测
        CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算
        ApplyServoControl();           // 应用舵机控制
        Ms_Delay(5);                   // 与舵机发送延时合计 10ms/周期
    }
}

/// @brief 关节角度(运动学角，度) -> 舵机占空比
/// @param joint 关节索引(0..JOINT_COUNT-1)
/// @param angle 运动学角(度)，即连杆的实际朝向
/// @return 舵机占空比(SERVO_MIN_DUTY~SERVO_MAX_DUTY)
/// @note 两个角度空间：运动学角是连杆朝向（逆解算的输出），
///       舵机指令角 = 运动学角 - jointOffset[joint]，行程 ±90°：
///       -90°=250, 0°=750, +90°=1250。
///       反向关节沿中位镜像；舵机方向只由占空比决定，
///       故不再向扩展板发 Dir_Change_Order。
uint16_t angle_to_duty(int joint, float angle)
{
    int duty;
    float servo;
    // 限位夹紧（限位也是运动学角）
    if (angle < jointMin[joint])
        angle = jointMin[joint];
    if (angle > jointMax[joint])
        angle = jointMax[joint];
    // 运动学角 -> 舵机指令角：扣掉安装中位朝向
    servo = angle - jointOffset[joint];
    // 舵机指令角 -> 占空比（0° 即中位 750），反向关节沿中位镜像
    if (jointDir[joint])
        duty = (int)(SERVO_MID_DUTY + servo * SERVO_DUTY_PER_DEG);
    else
        duty = (int)(SERVO_MID_DUTY - servo * SERVO_DUTY_PER_DEG);
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
/// @param phi 末端姿态角(度)
/// @note 结果写入 jointAngle[]，越界时钳到边界并设 ik_reachable=0
void ik_solve(float x, float y, float z, float phi)
{
    float r, c2, t1, t2, t0, t3, rz, scale, phi_rad;
    ik_reachable = 1;
    // === 4 轴逆解（底座 + 2连杆 + 腕部俯仰）===
    t0 = atan2(y, x);
    r = sqrt(x * x + y * y);
    // 腕心 = 末端沿姿态角 φ 回退 L3，逆解针对腕心而非末端
    phi_rad = phi * 3.14159265f / 180.0f;
    r = r - L3 * cos(phi_rad);
    z = z - L3 * sin(phi_rad);
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
    // 腕部：补足剩余角度以保持末端姿态角 φ
    t3 = phi_rad - (t1 + t2);
    jointAngle[3] = t3 * 180.0f / 3.14159265f;
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

/// @brief 预设点位按键检测：按下时把末端目标设为该点位坐标
/// @return 1=命中预设点位（本周期跳过摇杆/按键增量），0=未命中
uint8_t CheckPresetKeys()
{
    for (i = 0; i < PRESET_COUNT; i++)
    {
        if (RcKeyValueRead(presetKey[i]))
        {
            targetX = presetPos[i][0];
            targetY = presetPos[i][1];
            targetZ = presetPos[i][2];
            targetPhi = presetPos[i][3];
            return 1;
        }
    }
    return 0;
}

/// @brief 摇杆/按键输入末端位置增量 -> 逆解算
/// @param hit 1=本周期已由预设点位设定目标，跳过增量累加
/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，
///       松开后末端保持当前位置不动。
///       仅当上次目标可达时才回退，避免不可达的预设点位把目标永久卡死。
void CalculateIK(uint8_t hit)
{
    float lastX, lastY, lastZ, lastPhi;
    uint8_t lastReachable;
    // 备份上次目标，越界时回退（防止 target 无限增长导致松手后回不来）
    lastX = targetX; lastY = targetY; lastZ = targetZ; lastPhi = targetPhi;
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
        if (RcKeyValueRead(KEY_OFFSET_D))
            targetPhi += KEYMOVE_PHI_SPEED; // 末端姿态角φ 正向（按键 D）
        if (RcKeyValueRead(KEY_OFFSET_1))
            targetPhi -= KEYMOVE_PHI_SPEED; // 末端姿态角φ 负向（按键 R）
    }
    ik_solve(targetX, targetY, targetZ, targetPhi);
    // 越界则回退本周期增量，末端停在上一个可达位置；
    // 若上次目标本身就不可达（如预设点位超出量程），保留钳位结果以便摇杆能把末端拉回来
    if (!ik_reachable && !hit && lastReachable)
    {
        targetX = lastX; targetY = lastY; targetZ = lastZ; targetPhi = lastPhi;
        ik_solve(targetX, targetY, targetZ, targetPhi);
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
    // 主控板舵机控制（PWM）
    PWM_SET_Frequency(PWMB_CH4_P03, 50, dutyOfServo[3]);
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
    // 主控板舵机 PWM 初始化，初始占空比 = 初始角度对应值
    PWM_Init(PWMB_CH4_P03, 50, angle_to_duty(3, jointHome[3]));
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

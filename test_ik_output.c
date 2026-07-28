// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）
#include "main.h"
#include "MATH.H"
// ========================= 参数区 =========================
// 关节数：4。各关节的转轴与连杆长度见下方 jointAxis / jointLen 两张表。
// 逆解算是通用的雅可比法，不假定任何特定构型。
#define JOINT_COUNT 4
// 逆解算除零保护阈值
#define IK_EPS  0.001f
// 弧度与度的换算
#define DEG_TO_RAD  0.0174532925f
#define RAD_TO_DEG  57.29577951f
// 逆解单步最大转动量(度)：防大误差时末端猛冲，也避免线性近似失效
#define IK_MAX_STEP_DEG  4.0f
// 姿态误差权重(mm/rad)，取连杆总长：
// 让 1 弧度的俯仰角误差与一个臂长的位置误差等重，两者才能相加
#define PHI_WEIGHT  210.00f
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
// 按键长按时末端俯仰角每周期变化(度)
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
uint8_t  ik_reachable;          // 逆解算可达性标志(1=本步在靠近目标,0=已贴到极限)
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
// 各关节转轴（关节局部坐标系，连杆沿局部 +X 伸出）：
//   Yaw=(0,0,1) 左右摆 / Pitch=(0,-1,0) 上下俯仰 / Roll=(1,0,0) 绕自身轴自转
const float jointAxis[4][3] = {
    {0.0f, 0.0f, 1.0f},   // 关节1 Yaw
    {0.0f, -1.0f, 0.0f},   // 关节2 Pitch
    {0.0f, -1.0f, 0.0f},   // 关节3 Pitch
    {0.0f, -1.0f, 0.0f}   // 关节4 Pitch
};
// 各关节之后的连杆长度(mm)。最后一个是末端到夹爪的距离。
const float jointLen[4] = {0.00f, 100.00f, 80.00f, 30.00f};
// 逆解算中间结果。放 xdata 而非栈上：C251 单函数局部变量段上限 128 字节，
// 这几个数组加起来远超上限，声明成局部变量会报 segment too big。
static float xdata ikBasis[3][3], ikRot[3][3], ikTmp[3][3];
static float xdata ikPts[5][3];      // 各关节位置 + 末端位置
static float xdata ikAxes[4][3];     // 各关节转轴的世界方向
static float xdata ikCols[4][3];     // 雅可比各列 a_i x (tip - o_i)
static float xdata ikJte[4];         // J^T e
static float xdata ikLa[3], ikLv[3], ikWv[3], ikEv[3];
// 预设点位数量
#define PRESET_COUNT 1
// 预设点位：按键 KEY_OFFSET
const uint8_t presetKey[PRESET_COUNT] = {KEY_OFFSET_A};
// 预设点位末端坐标 {x, y, z, phi}
const float presetPos[PRESET_COUNT][4] = {
    {100.00f, 80.00f, 50.00f, 90.00f}  // P1 关节角度: [38.7, -29.1, 88.3, 31.4] 误差 0.0mm
};

void All_Init();
void ReadControllerInputs();
void CalculateIK(uint8_t hit);
void ApplyServoControl();
uint8_t CheckPresetKeys();
uint16_t angle_to_duty(int joint, float angle);
void mat_vec(float m[3][3], float v[3], float out[3]);
void axis_rot(float a[3], float ang, float m[3][3]);
void mat_mul(float x[3][3], float y[3][3], float out[3][3]);
void ik_fk();
void ik_solve(float x, float y, float z, float phi);
uint8_t ik_target_too_far(float x, float y, float z);
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,
                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,
                           uint16_t data_p77);

// ========================= ISP 自烧录监听 =========================
// 串口收到 "@STCISP#" 命令时触发软复位进入 ISP 模式
static const char isp_cmd[] = {'@','S','T','C','I','S','P','#'};
static uint8_t isp_match_idx = 0;
static uint8_t isp_rx_buf[8];
void CheckISPCommand(void);
void CheckISPCommand(void)
{
    uint8_t ch;
    while (uart1_rx_head != uart1_rx_tail)
    {
        ch = uart1_rx_buff[uart1_rx_tail];
        uart1_rx_tail = (uart1_rx_tail + 1) % UART1_RX_BUFFER_SIZE;
        isp_rx_buf[isp_match_idx] = ch;
        if (isp_rx_buf[isp_match_idx] == isp_cmd[isp_match_idx])
        {
            isp_match_idx++;
            if (isp_match_idx >= 8)
            {
                // 收到完整 @STCISP#，触发软复位进入 ISP
                IAP_CONTR = 0x60; // SWBS=1, SWRST=1
            }
        }
        else
        {
            // 不匹配，重置（但当前字符可能是新序列的起始）
            isp_match_idx = 0;
            if (ch == '@')
                isp_match_idx = 1;
        }
    }
}

void main()
{
    All_Init();
    // 初始化各关节到初始角度
    for (i = 0; i < JOINT_COUNT; i++)
        jointAngle[i] = jointHome[i];
    // 增量模式起点：初始姿态对应的末端位置（GUI 端正运动学预计算）
    targetX = 35.00f; targetY = 35.00f; targetZ = 171.92f; targetPhi = 45.00f;
    ik_reachable = 1;
    while (1)
    {
        CheckISPCommand(); // 检测 ISP 烧录命令
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

/// @brief 矩阵乘向量 out = m * v
void mat_vec(float m[3][3], float v[3], float out[3])
{
    out[0] = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2];
    out[1] = m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2];
    out[2] = m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2];
}

/// @brief 绕任意单位轴 a 转 ang 弧度的旋转矩阵（罗德里格斯公式）
/// @note 转轴是 Pitch/Roll/Yaw 只影响传进来的 a，公式本身通用
void axis_rot(float a[3], float ang, float m[3][3])
{
    float c, s, t;
    c = cos(ang);
    s = sin(ang);
    t = 1.0f - c;
    m[0][0] = t * a[0] * a[0] + c;
    m[0][1] = t * a[0] * a[1] - s * a[2];
    m[0][2] = t * a[0] * a[2] + s * a[1];
    m[1][0] = t * a[0] * a[1] + s * a[2];
    m[1][1] = t * a[1] * a[1] + c;
    m[1][2] = t * a[1] * a[2] - s * a[0];
    m[2][0] = t * a[0] * a[2] - s * a[1];
    m[2][1] = t * a[1] * a[2] + s * a[0];
    m[2][2] = t * a[2] * a[2] + c;
}

/// @brief 矩阵乘矩阵 out = x * y
void mat_mul(float x[3][3], float y[3][3], float out[3][3])
{
    uint8_t r, c;
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            out[r][c] = x[r][0] * y[0][c] + x[r][1] * y[1][c] + x[r][2] * y[2][c];
}

/// @brief 按当前 jointAngle[] 算正运动学链
/// @note 结果写入：ikPts[]=各关节位置+末端，ikAxes[]=各关节世界转轴，
///       ikBasis=末端姿态（第一列即末端朝向）
void ik_fk()
{
    uint8_t k, r, c;
    float ang;
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            ikBasis[r][c] = (r == c) ? 1.0f : 0.0f;
    ikPts[0][0] = 0.0f; ikPts[0][1] = 0.0f; ikPts[0][2] = 0.0f;
    for (k = 0; k < JOINT_COUNT; k++)
    {
        ikLa[0] = jointAxis[k][0];
        ikLa[1] = jointAxis[k][1];
        ikLa[2] = jointAxis[k][2];
        // 关节 k 的世界转轴由它之前的姿态决定
        // （绕自身轴转不改变该轴方向，故用旋转前的 basis）
        mat_vec(ikBasis, ikLa, ikWv);
        ikAxes[k][0] = ikWv[0]; ikAxes[k][1] = ikWv[1]; ikAxes[k][2] = ikWv[2];
        ang = jointAngle[k] * DEG_TO_RAD;
        axis_rot(ikLa, ang, ikRot);
        mat_mul(ikBasis, ikRot, ikTmp);
        for (r = 0; r < 3; r++)
            for (c = 0; c < 3; c++)
                ikBasis[r][c] = ikTmp[r][c];
        // 沿旋转后的局部 +X 伸出该关节之后的连杆
        ikLv[0] = jointLen[k]; ikLv[1] = 0.0f; ikLv[2] = 0.0f;
        mat_vec(ikBasis, ikLv, ikWv);
        ikPts[k + 1][0] = ikPts[k][0] + ikWv[0];
        ikPts[k + 1][1] = ikPts[k][1] + ikWv[1];
        ikPts[k + 1][2] = ikPts[k][2] + ikWv[2];
    }
}

/// @brief 逆解算：末端目标 -> 各关节角度（雅可比转置增量法）
/// @param x 末端X(mm)
/// @param y 末端Y(mm)
/// @param z 末端Z(mm)
/// @param phi 末端俯仰角(度)，末端朝向的仰角
/// @note 每次调用只走一步，靠 10ms 主循环连续收敛。
///       结果写入 jointAngle[]，已按 jointMin/jointMax 钳位。
///       ik_reachable=0 表示这一步没能靠近目标（已贴到可达域边界）。
void ik_solve(float x, float y, float z, float phi)
{
    uint8_t k;
    float alpha, num, den, step, maxStep, errBefore, errAfter;
    float az, denom, phiErr, gk, gDot;
    // === 正运动学：得到各关节位置、世界转轴、末端姿态 ===
    ik_fk();
    // === 位置误差 ===
    ikEv[0] = x - ikPts[JOINT_COUNT][0];
    ikEv[1] = y - ikPts[JOINT_COUNT][1];
    ikEv[2] = z - ikPts[JOINT_COUNT][2];
    // === 末端俯仰角误差 ===
    // phi = asin(a_z)，a = 末端朝向（tip_basis 的局部 +X）
    az = ikBasis[2][0];
    if (az > 1.0f) az = 1.0f;
    if (az < -1.0f) az = -1.0f;
    denom = 1.0f - az * az;
    phiErr = 0.0f;
    // 末端竖直时 asin 导数发散、phi 也不再区分朝向，本周期只管位置
    if (denom > 0.000100f)
    {
        denom = sqrt(denom);
        phiErr = (phi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;
    }
    else
        denom = 0.0f;   // 0 表示本周期不参与姿态解算
    // === 雅可比各列与 J^T e ===
    gDot = 0.0f;
    for (k = 0; k < JOINT_COUNT; k++)
    {
        ikLv[0] = ikPts[JOINT_COUNT][0] - ikPts[k][0];
        ikLv[1] = ikPts[JOINT_COUNT][1] - ikPts[k][1];
        ikLv[2] = ikPts[JOINT_COUNT][2] - ikPts[k][2];
        ikCols[k][0] = ikAxes[k][1] * ikLv[2] - ikAxes[k][2] * ikLv[1];
        ikCols[k][1] = ikAxes[k][2] * ikLv[0] - ikAxes[k][0] * ikLv[2];
        ikCols[k][2] = ikAxes[k][0] * ikLv[1] - ikAxes[k][1] * ikLv[0];
        ikJte[k] = ikCols[k][0] * ikEv[0] + ikCols[k][1] * ikEv[1]
                 + ikCols[k][2] * ikEv[2];
        if (denom > 0.0f)
        {
            // phi 梯度 g_k = (a_k x approach)_z / sqrt(1 - a_z^2)
            gk = (ikAxes[k][0] * ikBasis[1][0]
                - ikAxes[k][1] * ikBasis[0][0]) / denom;
            // 两项量纲统一到 mm：g 是 rad/rad，乘权重后与位置项可加
            ikJte[k] += gk * PHI_WEIGHT * (phiErr * PHI_WEIGHT);
            gDot += gk * PHI_WEIGHT * ikJte[k];
        }
    }
    // === 步长 alpha（最速下降的精确解）===
    // alpha = |J^T e|^2 / |J J^T e|^2。分子是**关节空间**的模长，
    // 用任务空间的 |e|^2 会小好几个数量级，末端几乎不动。
    num = 0.0f;
    ikWv[0] = 0.0f; ikWv[1] = 0.0f; ikWv[2] = 0.0f;
    for (k = 0; k < JOINT_COUNT; k++)
    {
        num += ikJte[k] * ikJte[k];
        ikWv[0] += ikCols[k][0] * ikJte[k];
        ikWv[1] += ikCols[k][1] * ikJte[k];
        ikWv[2] += ikCols[k][2] * ikJte[k];
    }
    den = ikWv[0] * ikWv[0] + ikWv[1] * ikWv[1] + ikWv[2] * ikWv[2];
    den += gDot * gDot;
    alpha = 0.0f;
    if (den > IK_EPS)
        alpha = num / den;
    // 单步限幅：防止大误差时末端猛冲，也避免线性近似在大角度下失效
    maxStep = 0.0f;
    for (k = 0; k < JOINT_COUNT; k++)
    {
        step = alpha * ikJte[k] * RAD_TO_DEG;
        if (step < 0.0f) step = -step;
        if (step > maxStep) maxStep = step;
    }
    if (maxStep > IK_MAX_STEP_DEG)
        alpha *= IK_MAX_STEP_DEG / maxStep;
    // === 走一步并按限位钳位 ===
    errBefore = ikEv[0] * ikEv[0] + ikEv[1] * ikEv[1] + ikEv[2] * ikEv[2];
    errBefore += (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);
    for (k = 0; k < JOINT_COUNT; k++)
    {
        jointAngle[k] += alpha * ikJte[k] * RAD_TO_DEG;
        if (jointAngle[k] < jointMin[k]) jointAngle[k] = jointMin[k];
        if (jointAngle[k] > jointMax[k]) jointAngle[k] = jointMax[k];
    }
    // === 可达性：这一步有没有真的靠近目标 ===
    // 姿态误差要一起算进总误差，否则纯粹在调 phi 的步会被误判成停滞
    ik_fk();
    ikEv[0] = x - ikPts[JOINT_COUNT][0];
    ikEv[1] = y - ikPts[JOINT_COUNT][1];
    ikEv[2] = z - ikPts[JOINT_COUNT][2];
    errAfter = ikEv[0] * ikEv[0] + ikEv[1] * ikEv[1] + ikEv[2] * ikEv[2];
    az = ikBasis[2][0];
    if (az > 1.0f) az = 1.0f;
    if (az < -1.0f) az = -1.0f;
    phiErr = (phi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;
    errAfter += (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);
    ik_reachable = (errAfter < errBefore) ? 1 : 0;
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

/// @brief 目标点是否超出臂展（连杆总长）
/// @note 只拦「明显够不着」，留 2% 余量避免边界处反复抖动
uint8_t ik_target_too_far(float x, float y, float z)
{
    float d2;
    d2 = x * x + y * y + z * z;
    // 与 (臂展 * 0.98)^2 比，省一次开方
    return (d2 > 42353.64f) ? 1 : 0;
}

/// @brief 摇杆/按键输入末端位置增量 -> 逆解算
/// @param hit 1=本周期已由预设点位设定目标，跳过增量累加
/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，
///       松开后末端保持当前位置不动。
///       逆解是雅可比增量法，每周期走一步，连续多个周期逼近目标。
void CalculateIK(uint8_t hit)
{
    float lastX, lastY, lastZ, lastPhi;
    // 备份上次目标：目标跑到臂展外时要把这一步的增量撤掉，
    // 否则长推摇杆会让 target 一直飘远，松手后末端要等很久才追回来
    lastX = targetX; lastY = targetY; lastZ = targetZ; lastPhi = targetPhi;
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
            targetPhi += KEYMOVE_PHI_SPEED; // 末端俯仰角 正向（按键 D）
        if (RcKeyValueRead(KEY_OFFSET_1))
            targetPhi -= KEYMOVE_PHI_SPEED; // 末端俯仰角 负向（按键 R）
    }
    ik_solve(targetX, targetY, targetZ, targetPhi);
    // 目标是否落在可达范围内：拿末端到底座的距离与连杆总长比。
    // 注意不能用 ik_reachable 判断——雅可比法下它表示
    // 「这一步有没有靠近目标」，正常收敛途中也会因步长限幅而为 0。
    if (!hit && ik_target_too_far(targetX, targetY, targetZ))
    {
        // 撤回本周期增量，target 停在上一个够得着的位置
        targetX = lastX; targetY = lastY; targetZ = lastZ; targetPhi = lastPhi;
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

/* STC32G 机械臂逆解性能实测 */
/* 计时：TIM0 1T 自由运行 16 位定时器，每系统时钟 +1，中断累加溢出。 */
/*       FOSC=33177600，微秒 = 周期数 / 33.1776 */
/* 输出：UART1 (P30/P31) 230400 8N1，上电即跑，无需遥控器 */
#include "main.h"
#include "MATH.H"

uint8_t Channal = 36; /* nrf24l01.c 通过 extern 引用 */
unsigned long txt;

#define MAX_J 6   /* 最大关节数 */
#define REPEAT 20 /* 每种关节数重复次数，取平均抵消抖动 */

/* ==================== 计时 ==================== */
volatile uint16_t t0_ovf = 0;

void Timer0_FreeRun_Init(void)
{
    TMOD &= 0xF0; /* T0 模式 0：16 位自动重载 */
    AUXR |= 0x80; /* T0 为 1T 模式 */
    TL0 = 0;
    TH0 = 0;
    ET0 = 1;
    TR0 = 1;
    EA = 1;
}

void TM0_Isr(void) interrupt 1
{
    t0_ovf++;
}

/* 读 32 位计数。读时可能溢出，故比对前后 ovf，不一致就重读 */
uint32_t tick_now(void)
{
    uint8_t hi, lo;
    uint16_t ovf1, ovf2;
    do
    {
        ovf1 = t0_ovf;
        lo = TL0;
        hi = TH0;
        ovf2 = t0_ovf;
    } while (ovf1 != ovf2);
    return ((uint32_t)ovf1 << 16) | ((uint32_t)hi << 8) | (uint32_t)lo;
}

/* ==================== 串口输出 ==================== */
void put_str(char *s)
{
    while (*s)
        UART_PutChar(UART_1, (uint8_t)(*s++));
}

void put_u32(uint32_t v)
{
    char buf[11];
    int8_t i = 0;
    if (v == 0)
    {
        UART_PutChar(UART_1, 48);
        return;
    }
    while (v > 0 && i < 10)
    {
        buf[i++] = (char)(48 + (uint8_t)(v % 10));
        v /= 10;
    }
    while (i > 0)
        UART_PutChar(UART_1, (uint8_t)buf[--i]);
}

/* 输出 x.yy，传入值已放大 100 倍 */
void put_fixed2(uint32_t v100)
{
    put_u32(v100 / 100);
    UART_PutChar(UART_1, 46);
    UART_PutChar(UART_1, (uint8_t)(48 + (uint8_t)((v100 / 10) % 10)));
    UART_PutChar(UART_1, (uint8_t)(48 + (uint8_t)(v100 % 10)));
}

/* ==================== 机械臂配置 ====================
   转轴：Yaw=(0,0,1) Pitch=(0,-1,0) Roll=(1,0,0)
   典型 6 轴构形：Yaw + Pitch + Pitch + Roll + Pitch + Roll */
const float jointAxis[MAX_J][3] = {
    {0.0f, 0.0f, 1.0f},
    {0.0f, -1.0f, 0.0f},
    {0.0f, -1.0f, 0.0f},
    {1.0f, 0.0f, 0.0f},
    {0.0f, -1.0f, 0.0f},
    {1.0f, 0.0f, 0.0f}};
const float jointLen[MAX_J] = {0.0f, 120.0f, 90.0f, 0.0f, 40.0f, 25.0f};
const float jointMin[MAX_J] = {-90.0f, -90.0f, -90.0f, -90.0f, -90.0f, -90.0f};
const float jointMax[MAX_J] = {90.0f, 90.0f, 90.0f, 90.0f, 90.0f, 90.0f};

float jointAngle[MAX_J];
uint8_t ik_reachable;

/* 姿态误差权重(mm/rad) = 连杆总长 0+120+90+0+40+25 = 275。
   生成器按实际构形算，这里取 6 关节的值固定不变：
   计时只关心指令条数，权重的具体数值不影响耗时。
   （收敛性测试用 4 关节时权重偏大，但仍能看出误差趋势） */
#define PHI_WEIGHT 275.00f
/* 单步最大转动量(度)，与生成器的 IK_MAX_STEP_DEG 一致 */
#define IK_MAX_STEP_DEG 4.0f
#define IK_EPS 0.001f
#define DEG_TO_RAD 0.0174532925f
#define RAD_TO_DEG 57.29577951f
/* phi = asin(a_z) 在末端竖直时退化 */
#define PITCH_DEGEN_EPS 0.0001f

/* FK 链中间结果必须放 xdata：C251 单函数局部变量段上限 128 字节，
   放栈上会报 segment too big */
static float xdata basis[3][3], rot[3][3], mtmp[3][3];
static float xdata pts[MAX_J + 1][3];
static float xdata axes[MAX_J][3];
static float xdata la[3], lv[3], wv[3];
static float xdata ev[3], jcol[3];
static float xdata cols[MAX_J][3];
static float xdata jte[MAX_J];
/* 当前测试的关节数。生成的代码里是 JOINT_COUNT 宏，这里要能逐个关节数扫，
   故用全局变量替代，其余代码与生成版逐行一致 */
uint8_t njoints;

/* ==================== 运动学 ==================== */
void mat_vec(float m[3][3], float v[3], float out[3])
{
    out[0] = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2];
    out[1] = m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2];
    out[2] = m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2];
}

/* 绕任意轴 a 转 ang 弧度（罗德里格斯公式）*/
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

void mat_mul(float x[3][3], float y[3][3], float out[3][3])
{
    uint8_t r, c;
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            out[r][c] = x[r][0] * y[0][c] + x[r][1] * y[1][c] + x[r][2] * y[2][c];
}

/* 正运动学链。结果写入 pts[]（各关节位置+末端）、axes[]（世界转轴）、
   basis（末端姿态，第一列即末端朝向）。
   与生成的 ik_fk() 逐行一致，只是 JOINT_COUNT 换成 njoints。 */
void ik_fk(void)
{
    uint8_t k, r, c;
    float ang;
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            basis[r][c] = (r == c) ? 1.0f : 0.0f;
    pts[0][0] = 0.0f;
    pts[0][1] = 0.0f;
    pts[0][2] = 0.0f;
    for (k = 0; k < njoints; k++)
    {
        la[0] = jointAxis[k][0];
        la[1] = jointAxis[k][1];
        la[2] = jointAxis[k][2];
        mat_vec(basis, la, wv);
        axes[k][0] = wv[0];
        axes[k][1] = wv[1];
        axes[k][2] = wv[2];
        ang = jointAngle[k] * DEG_TO_RAD;
        axis_rot(la, ang, rot);
        mat_mul(basis, rot, mtmp);
        for (r = 0; r < 3; r++)
            for (c = 0; c < 3; c++)
                basis[r][c] = mtmp[r][c];
        lv[0] = jointLen[k];
        lv[1] = 0.0f;
        lv[2] = 0.0f;
        mat_vec(basis, lv, wv);
        pts[k + 1][0] = pts[k][0] + wv[0];
        pts[k + 1][1] = pts[k][1] + wv[1];
        pts[k + 1][2] = pts[k][2] + wv[2];
    }
}

/* 雅可比转置增量 IK：一个周期走一步。
   与生成的 ik_solve() 逐行一致（含 phi 一行、自适应 alpha、步长限幅、
   走完后重算 FK 判断误差是否下降）。 */
void ik_solve(float tx, float ty, float tz, float tphi)
{
    uint8_t k;
    float alpha, num, den, step, maxStep, errBefore, errAfter;
    float az, denom, phiErr, gk, gDot;
    ik_fk();
    ev[0] = tx - pts[njoints][0];
    ev[1] = ty - pts[njoints][1];
    ev[2] = tz - pts[njoints][2];
    /* --- 末端俯仰角误差：phi = asin(a_z)，a = basis 第一列 --- */
    az = basis[2][0];
    if (az > 1.0f)
        az = 1.0f;
    if (az < -1.0f)
        az = -1.0f;
    denom = 1.0f - az * az;
    phiErr = 0.0f;
    if (denom > PITCH_DEGEN_EPS)
    {
        denom = sqrt(denom);
        phiErr = (tphi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;
    }
    else
        denom = 0.0f;
    /* --- 雅可比各列与 J^T e --- */
    gDot = 0.0f;
    for (k = 0; k < njoints; k++)
    {
        lv[0] = pts[njoints][0] - pts[k][0];
        lv[1] = pts[njoints][1] - pts[k][1];
        lv[2] = pts[njoints][2] - pts[k][2];
        cols[k][0] = axes[k][1] * lv[2] - axes[k][2] * lv[1];
        cols[k][1] = axes[k][2] * lv[0] - axes[k][0] * lv[2];
        cols[k][2] = axes[k][0] * lv[1] - axes[k][1] * lv[0];
        jte[k] = cols[k][0] * ev[0] + cols[k][1] * ev[1] + cols[k][2] * ev[2];
        if (denom > 0.0f)
        {
            gk = (axes[k][0] * basis[1][0] - axes[k][1] * basis[0][0]) / denom;
            jte[k] += gk * PHI_WEIGHT * (phiErr * PHI_WEIGHT);
            gDot += gk * PHI_WEIGHT * jte[k];
        }
    }
    /* --- alpha = |J^T e|^2 / |J J^T e|^2（最速下降精确步长）--- */
    num = 0.0f;
    wv[0] = 0.0f;
    wv[1] = 0.0f;
    wv[2] = 0.0f;
    for (k = 0; k < njoints; k++)
    {
        num += jte[k] * jte[k];
        wv[0] += cols[k][0] * jte[k];
        wv[1] += cols[k][1] * jte[k];
        wv[2] += cols[k][2] * jte[k];
    }
    den = wv[0] * wv[0] + wv[1] * wv[1] + wv[2] * wv[2] + gDot * gDot;
    alpha = 0.0f;
    if (den > IK_EPS)
        alpha = num / den;
    /* --- 单步限幅 --- */
    maxStep = 0.0f;
    for (k = 0; k < njoints; k++)
    {
        step = alpha * jte[k] * RAD_TO_DEG;
        if (step < 0.0f)
            step = -step;
        if (step > maxStep)
            maxStep = step;
    }
    if (maxStep > IK_MAX_STEP_DEG)
        alpha *= IK_MAX_STEP_DEG / maxStep;
    /* --- 走一步并钳位 --- */
    errBefore = ev[0] * ev[0] + ev[1] * ev[1] + ev[2] * ev[2] + (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);
    for (k = 0; k < njoints; k++)
    {
        jointAngle[k] += alpha * jte[k] * RAD_TO_DEG;
        if (jointAngle[k] < jointMin[k])
            jointAngle[k] = jointMin[k];
        if (jointAngle[k] > jointMax[k])
            jointAngle[k] = jointMax[k];
    }
    /* --- 可达性：这一步有没有真的靠近目标 --- */
    ik_fk();
    ev[0] = tx - pts[njoints][0];
    ev[1] = ty - pts[njoints][1];
    ev[2] = tz - pts[njoints][2];
    errAfter = ev[0] * ev[0] + ev[1] * ev[1] + ev[2] * ev[2];
    az = basis[2][0];
    if (az > 1.0f)
        az = 1.0f;
    if (az < -1.0f)
        az = -1.0f;
    phiErr = (tphi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;
    errAfter += (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);
    ik_reachable = (errAfter < errBefore) ? 1 : 0;
}

/* ==================== 基准测试 ==================== */
/* 测 nj 个关节的单次 ik_solve 耗时。
   withPhi=0 时把目标俯仰角设成当前实际值，phiErr≈0 —— 注意这样只省掉
   梯度项的乘加，asin/sqrt 仍会执行，故它不是「纯位置版」的真实耗时，
   仅用于看梯度项本身的开销。真正的纯位置对照见 bench_pos_only。 */
void bench_joints(uint8_t nj)
{
    uint32_t t0, t1, total, cycles, us100;
    uint16_t n;
    njoints = nj;
    for (n = 0; n < MAX_J; n++)
        jointAngle[n] = 10.0f; /* 复位，保证每次起点一致 */
    total = 0;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        ik_solve(150.0f, 30.0f, 60.0f, -30.0f);
        t1 = tick_now();
        total += (t1 - t0);
    }
    cycles = total / REPEAT;
    /* 微秒*100 = 周期*100/33.1776 ≈ 周期*100/332*100，先除后乘防溢出 */
    us100 = (cycles * 100UL) / 332UL;
    put_str("JOINTS=");
    put_u32(nj);
    put_str(" CYCLES=");
    put_u32(cycles);
    put_str(" US=");
    put_fixed2(us100);
    put_str("\r\n");
}

/* 单次 ik_fk 耗时：IK 的主要成本在 FK 链（每关节 1 次 sin+cos + 两次矩阵乘），
   分离出来才能判断优化空间在哪 */
void bench_fk(uint8_t nj)
{
    uint32_t t0, t1, total, cycles, us100;
    uint16_t n;
    njoints = nj;
    for (n = 0; n < MAX_J; n++)
        jointAngle[n] = 10.0f;
    total = 0;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        ik_fk();
        t1 = tick_now();
        total += (t1 - t0);
    }
    cycles = total / REPEAT;
    us100 = (cycles * 100UL) / 332UL;
    put_str("FK J=");
    put_u32(nj);
    put_str(" CYCLES=");
    put_u32(cycles);
    put_str(" US=");
    put_fixed2(us100);
    put_str("\r\n");
}

/* 收敛性验证：真机上连续走 N 步，看位置误差与俯仰角是否真的收敛。
   这比计时更重要——float 精度、asin 实现差异都可能让 PC 上收敛的算法在
   8051 上原地打转。误差按 mm 打印（放大 100 倍取两位小数）。 */
void bench_converge(uint8_t nj)
{
    uint16_t n;
    float ex, ey, ez, err, az, phi;
    njoints = nj;
    for (n = 0; n < MAX_J; n++)
        jointAngle[n] = 10.0f;
    put_str("CONV J=");
    put_u32(nj);
    put_str("\r\n");
    for (n = 0; n < 60; n++)
    {
        ik_solve(150.0f, 30.0f, 60.0f, -30.0f);
        /* 第 1/5/10/20/40/60 步打印，避免刷屏 */
        if (n == 0 || n == 4 || n == 9 || n == 19 || n == 39 || n == 59)
        {
            ik_fk();
            ex = 150.0f - pts[njoints][0];
            ey = 30.0f - pts[njoints][1];
            ez = 60.0f - pts[njoints][2];
            err = sqrt(ex * ex + ey * ey + ez * ez);
            az = basis[2][0];
            if (az > 1.0f)
                az = 1.0f;
            if (az < -1.0f)
                az = -1.0f;
            phi = asin(az) * RAD_TO_DEG;
            put_str("  step=");
            put_u32((uint32_t)(n + 1));
            put_str(" err=");
            put_fixed2((uint32_t)(err * 100.0f));
            put_str("mm phi=");
            /* phi 是负值，单独处理符号 */
            if (phi < 0.0f)
            {
                UART_PutChar(UART_1, 45);
                phi = -phi;
            }
            put_fixed2((uint32_t)(phi * 100.0f));
            put_str("deg reach=");
            put_u32(ik_reachable);
            put_str("\r\n");
        }
    }
}

/* tick_now 自身开销，读数要扣掉 */
void bench_overhead(void)
{
    uint32_t t0, t1, total;
    uint16_t n;
    total = 0;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        t1 = tick_now();
        total += (t1 - t0);
    }
    put_str("OVERHEAD_CYCLES=");
    put_u32(total / REPEAT);
    put_str("\r\n");
}

/* 单次 sin+cos，验证「三角函数是主要开销」这个判断 */
void bench_trig(void)
{
    uint32_t t0, t1, total;
    uint16_t n;
    float a, r;
    total = 0;
    a = 0.5f;
    r = 0.0f;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        r = sin(a) + cos(a);
        t1 = tick_now();
        total += (t1 - t0);
    }
    if (r > 1000.0f)
        put_str(""); /* 防止被优化掉 */
    put_str("SINCOS_CYCLES=");
    put_u32(total / REPEAT);
    put_str("\r\n");
}

/* 单次浮点乘 */
void bench_fmul(void)
{
    uint32_t t0, t1, total;
    uint16_t n;
    float a, b, r;
    total = 0;
    a = 1.2345f;
    b = 6.789f;
    r = 0.0f;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        r = a * b;
        t1 = tick_now();
        total += (t1 - t0);
    }
    if (r > 1e30f)
        put_str("");
    put_str("FMUL_CYCLES=");
    put_u32(total / REPEAT);
    put_str("\r\n");
}

// ========================= ISP 自烧录监听 =========================
// 按照 STC32G 技术手册官方示例：在 UART1 ISR 中直接匹配 @STCISP#
char code STCISPCMD[] = "@STCISP#"; // 自定义下载命令
uint8_t isp_cmd_index = 0;           // 命令匹配索引

void main(void)
{
    uint8_t nj;
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    Timer0_FreeRun_Init();
    Ms_Delay(200);

    put_str("\r\n=== STC32G IK BENCH ===\r\n");
    put_str("FOSC=33177600 REPEAT=");
    put_u32(REPEAT);
    put_str("\r\n");

    bench_overhead();
    bench_fmul();
    bench_trig();
    put_str("---\r\n");

    /* FK 链单独计时：IK 的主要成本在这里 */
    for (nj = 2; nj <= MAX_J; nj++)
        bench_fk(nj);
    put_str("---\r\n");

    for (nj = 2; nj <= MAX_J; nj++)
        bench_joints(nj);
    put_str("---\r\n");

    /* 收敛性：只测 4 和 6 关节，够看出趋势 */
    bench_converge(4);
    bench_converge(6);

    put_str("=== DONE ===\r\n");

    /* 循环输出全部项目：接串口的时机不确定，上电段容易错过，
       所以 FK 计时与收敛性也放进循环 */
    while (1)
    {
        Ms_Delay(3000);
        put_str("--- repeat ---\r\n");
        for (nj = 2; nj <= MAX_J; nj++)
            bench_fk(nj);
        for (nj = 2; nj <= MAX_J; nj++)
            bench_joints(nj);
        bench_converge(4);
        bench_converge(6);
    }
}

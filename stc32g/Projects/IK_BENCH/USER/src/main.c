/* STC32G 机械臂逆解性能实测 */
/* 计时：TIM0 1T 自由运行 16 位定时器，每系统时钟 +1，中断累加溢出。 */
/*       FOSC=33177600，微秒 = 周期数 / 33.1776 */
/* 输出：UART1 (P30/P31) 115200 8N1，上电即跑，无需遥控器 */
#include "main.h"
#include "MATH.H"

uint8_t Channal = 36;   /* nrf24l01.c 通过 extern 引用 */
unsigned long txt;

#define MAX_J  6    /* 最大关节数 */
#define REPEAT 20   /* 每种关节数重复次数，取平均抵消抖动 */

/* ==================== 计时 ==================== */
volatile uint16_t t0_ovf = 0;

void Timer0_FreeRun_Init(void)
{
    TMOD &= 0xF0;   /* T0 模式 0：16 位自动重载 */
    AUXR |= 0x80;   /* T0 为 1T 模式 */
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
    do {
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
    {1.0f, 0.0f, 0.0f}
};
const float jointLen[MAX_J] = {0.0f, 120.0f, 90.0f, 0.0f, 40.0f, 25.0f};
const float jointMin[MAX_J] = {-90.0f, -90.0f, -90.0f, -90.0f, -90.0f, -90.0f};
const float jointMax[MAX_J] = {90.0f, 90.0f, 90.0f, 90.0f, 90.0f, 90.0f};

float jointAngle[MAX_J];
uint8_t ik_reachable;

/* FK 链中间结果必须放 xdata：C251 单函数局部变量段上限 128 字节，
   放栈上会报 segment too big */
static float xdata basis[3][3], rot[3][3], mtmp[3][3];
static float xdata pts[MAX_J + 1][3];
static float xdata axes[MAX_J][3];
static float xdata la[3], lv[3], wv[3];
static float xdata ev[3], jcol[3];

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

/* 雅可比转置增量 IK：一个周期走一步。nj = 实际关节数 */
void ik_solve(uint8_t nj, float tx, float ty, float tz)
{
    float dtheta, alpha;
    uint8_t k, r, c;
    /* --- FK 链 --- */
    for (r = 0; r < 3; r++)
        for (c = 0; c < 3; c++)
            basis[r][c] = (r == c) ? 1.0f : 0.0f;
    pts[0][0] = 0.0f; pts[0][1] = 0.0f; pts[0][2] = 0.0f;
    for (k = 0; k < nj; k++)
    {
        la[0] = jointAxis[k][0];
        la[1] = jointAxis[k][1];
        la[2] = jointAxis[k][2];
        mat_vec(basis, la, wv);
        axes[k][0] = wv[0]; axes[k][1] = wv[1]; axes[k][2] = wv[2];
        axis_rot(la, jointAngle[k] * 0.0174532925f, rot);
        mat_mul(basis, rot, mtmp);
        for (r = 0; r < 3; r++)
            for (c = 0; c < 3; c++)
                basis[r][c] = mtmp[r][c];
        lv[0] = jointLen[k]; lv[1] = 0.0f; lv[2] = 0.0f;
        mat_vec(basis, lv, wv);
        pts[k + 1][0] = pts[k][0] + wv[0];
        pts[k + 1][1] = pts[k][1] + wv[1];
        pts[k + 1][2] = pts[k][2] + wv[2];
    }
    /* --- 误差 --- */
    ev[0] = tx - pts[nj][0];
    ev[1] = ty - pts[nj][1];
    ev[2] = tz - pts[nj][2];
    /* --- dtheta = alpha * J^T e，J 第 k 列 = axes[k] x (tip - pts[k]) --- */
    alpha = 0.00002f;
    for (k = 0; k < nj; k++)
    {
        lv[0] = pts[nj][0] - pts[k][0];
        lv[1] = pts[nj][1] - pts[k][1];
        lv[2] = pts[nj][2] - pts[k][2];
        jcol[0] = axes[k][1] * lv[2] - axes[k][2] * lv[1];
        jcol[1] = axes[k][2] * lv[0] - axes[k][0] * lv[2];
        jcol[2] = axes[k][0] * lv[1] - axes[k][1] * lv[0];
        dtheta = (jcol[0] * ev[0] + jcol[1] * ev[1] + jcol[2] * ev[2]) * alpha;
        jointAngle[k] += dtheta * 57.29577951f;
        if (jointAngle[k] < jointMin[k]) jointAngle[k] = jointMin[k];
        if (jointAngle[k] > jointMax[k]) jointAngle[k] = jointMax[k];
    }
    ik_reachable = 1;
}

/* ==================== 基准测试 ==================== */
/* 测 nj 个关节的单次 ik_solve 耗时 */
void bench_joints(uint8_t nj)
{
    uint32_t t0, t1, total, cycles, us100;
    uint16_t n;
    for (n = 0; n < MAX_J; n++)
        jointAngle[n] = 10.0f;   /* 复位，保证每次起点一致 */
    total = 0;
    for (n = 0; n < REPEAT; n++)
    {
        t0 = tick_now();
        ik_solve(nj, 150.0f, 30.0f, 60.0f);
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
    if (r > 1000.0f) put_str("");   /* 防止被优化掉 */
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
    if (r > 1e30f) put_str("");
    put_str("FMUL_CYCLES=");
    put_u32(total / REPEAT);
    put_str("\r\n");
}

void main(void)
{
    uint8_t nj;
    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 115200, TIM1);
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

    for (nj = 2; nj <= MAX_J; nj++)
        bench_joints(nj);

    put_str("=== DONE ===\r\n");

    /* 循环输出，随时接串口都能看到结果 */
    while (1)
    {
        Ms_Delay(3000);
        put_str("--- repeat ---\r\n");
        for (nj = 2; nj <= MAX_J; nj++)
            bench_joints(nj);
    }
}


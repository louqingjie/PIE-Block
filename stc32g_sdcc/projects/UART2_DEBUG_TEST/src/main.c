/*
 * UART2 调试链路临时测试固件。
 *
 * 接线（和 USB-CDC 桥配合）：
 *   本板 P1.1 (UART2 TX) -> 桥 P1.0 (UART2 RX)
 *   本板 P1.0 (UART2 RX) <- 桥 P1.1 (UART2 TX)
 *   GND 共地
 *
 * 行为：
 *   - 每 1 秒发送 "UART2 OK <counter>\r\n"；
 *   - 收到 PC 经桥下发的字节，回显 "[RX] <byte>\r\n"。
 *
 * 只初始化系统时钟和 UART2，不初始化电机、NRF、拓展板，测试时机器人不会动作。
 */

#include "main.h"

static const char __code MSG_BOOT[] = "\r\n[UART2 TEST] P1.0=RX P1.1=TX 115200 8N1\r\n";
static const char __code MSG_OK[] = "UART2 OK ";
static const char __code MSG_RX[] = "[RX] ";
static const char __code MSG_CRLF[] = "\r\n";

static void Uart2Init(void)
{
    P_SW2 &= ~0x01; /* UART2 -> P1.0/P1.1 */
    P1M0 &= ~0x03;
    P1M1 &= ~0x03; /* P1.0/P1.1 准双向 */
    S2CON = 0x50;  /* 模式 1，8 位 UART，允许接收 */
    T2L = (uint8_t)BR(115200);
    T2H = BR(115200) >> 8;
    AUXR |= 0x14; /* T2x12 = 1, T2R = 1；AUXR 不是可位寻址 SFR */
}

static void Uart2SendByte(uint8_t dat)
{
    S2BUF = dat;
    while (!(S2CON & 0x02))
    {
    }
    S2CON &= ~0x02;
}

static void Uart2SendStr(const char __code *s)
{
    while (*s)
        Uart2SendByte((uint8_t)*s++);
}

static void Uart2SendUint(uint16_t value)
{
    uint8_t buf[5];
    uint8_t n = 0;

    if (value == 0)
    {
        Uart2SendByte('0');
        return;
    }
    while (value)
    {
        buf[n++] = (uint8_t)('0' + (value % 10));
        value /= 10;
    }
    while (n)
        Uart2SendByte(buf[--n]);
}

static uint8_t Uart2PollByte(uint8_t *dat)
{
    if (S2CON & 0x01)
    {
        S2CON &= ~0x01;
        *dat = S2BUF;
        return 1;
    }
    return 0;
}

void main(void)
{
    uint16_t count = 0;
    uint16_t tick = 0;
    uint8_t c;

    Register_Set();
    Uart2Init();
    Uart2SendStr(MSG_BOOT);

    while (1)
    {
        if (Uart2PollByte(&c))
        {
            Uart2SendStr(MSG_RX);
            Uart2SendByte(c);
            Uart2SendStr(MSG_CRLF);
        }

        if (++tick >= 1000)
        {
            tick = 0;
            Uart2SendStr(MSG_OK);
            Uart2SendUint(count++);
            Uart2SendStr(MSG_CRLF);
        }

        Ms_Delay(1);
    }
}


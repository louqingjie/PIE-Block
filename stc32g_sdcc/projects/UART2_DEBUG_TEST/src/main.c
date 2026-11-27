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

/* UART3 P0.0/P0.1 独立调试口：只发送，115200 8N1，轮询。 */
static void DebugUartInit(void)
{
    P_SW2 &= ~(0x01 << 1); /* UART3 -> P0.0/P0.1 */
    P0M1 &= ~0x03;
    P0M0 &= ~0x01;
    P0M0 |= 0x02; /* P0.1 TX 推挽；P0.0 保持准双向输入 */
    S3CON = 0x50;
    T3L = (uint8_t)BR(115200);
    T3H = (uint8_t)(BR(115200) >> 8);
    T4T3M |= 0x0a; /* T3x12 = 1, T3R = 1 */
    S3CON &= ~0x02;
}

static void DebugUartPutChar(uint8_t c)
{
    S3CON &= ~0x02;
    S3BUF = c;
    while (!(S3CON & 0x02))
    {
    }
    S3CON &= ~0x02;
}

/* 让 printf() 输出到 UART3，而不是 UART2。 */
int putchar(int c)
{
    DebugUartPutChar((uint8_t)c);
    return c;
}

/*
 * UART2 接收中断 + 环形缓冲。115200 下连续字节间隔只有约 87us，
 * 主循环轮询会覆盖 S2BUF，必须由中断及时搬走。
 */
#define UART2_RX_SIZE 64
static volatile uint8_t RxBuffer[UART2_RX_SIZE];
static volatile uint8_t RxHead = 0;
static volatile uint8_t RxTail = 0;
static volatile uint16_t Uart2IrqCount = 0;
static volatile uint16_t Uart2DropCount = 0;

void Uart2Isr(void) __interrupt (UART2_VECTOR)
{
    uint8_t dat;
    uint8_t next;

    Uart2IrqCount++;

    if (S2CON & 0x01) /* S2RI */
    {
        dat = S2BUF;
        S2CON &= ~0x01;
        next = (uint8_t)(RxHead + 1);
        if (next >= UART2_RX_SIZE)
            next = 0;
        if (next != RxTail)
        {
            RxBuffer[RxHead] = dat;
            RxHead = next;
        }
        else
        {
            Uart2DropCount++;
        }
    }

    if (S2CON & 0x02) /* S2TI：本工程 TX 仍用查询，清掉即可 */
        S2CON &= ~0x02;
}

static void Uart2Init(void)
{
    P_SW2 &= ~0x01; /* UART2 -> P1.0/P1.1 */
    P1M0 &= ~0x03;
    P1M1 &= ~0x03; /* P1.0/P1.1 准双向 */
    S2CON = 0x50;  /* 模式 1，8 位 UART，允许接收 */
    T2L = (uint8_t)BR(115200);
    T2H = BR(115200) >> 8;
    AUXR |= 0x14;  /* T2x12 = 1, T2R = 1；AUXR 不是可位寻址 SFR */
    IE2 = 0x01;    /* ES2：使能 UART2 中断；本工程没有 USB，不涉及 EUSB */
    EA = 1;
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

void main(void)
{
    uint16_t count = 0;
    uint16_t tick = 0;
    uint8_t c;

    Register_Set();
    DebugUartInit();
    printf("\r\n[BOOT] UART2 test; UART3 debug P0.1 115200\r\n");

    /* P3.5 心跳：低电平点亮，每秒翻转一次。 */
    P3M0 |= 0x20;
    P3M1 &= ~0x20;
    P35 = 0;

    Uart2Init();
    printf("[INIT] S2CON=%02X IE2=%02X EA=%u\r\n",
           (unsigned int)S2CON, (unsigned int)IE2, (unsigned int)(EA ? 1 : 0));

    Uart2SendStr(MSG_BOOT);

    while (1)
    {
        while (RxTail != RxHead)
        {
            c = RxBuffer[RxTail];
            RxTail = (uint8_t)(RxTail + 1);
            if (RxTail >= UART2_RX_SIZE)
                RxTail = 0;

            Uart2SendStr(MSG_RX);
            Uart2SendByte(c);
            Uart2SendStr(MSG_CRLF);
        }

        if (++tick >= 1000)
        {
            tick = 0;
            P35 = !P35;

            Uart2SendStr(MSG_OK);
            Uart2SendUint(count++);
            Uart2SendStr(MSG_CRLF);

            printf("[DBG] u2irq=%u drop=%u head=%u tail=%u s2con=%02X ie2=%02X ea=%u\r\n",
                   (unsigned int)Uart2IrqCount,
                   (unsigned int)Uart2DropCount,
                   (unsigned int)RxHead,
                   (unsigned int)RxTail,
                   (unsigned int)S2CON,
                   (unsigned int)IE2,
                   (unsigned int)(EA ? 1 : 0));
        }

        Ms_Delay(1);
    }
}


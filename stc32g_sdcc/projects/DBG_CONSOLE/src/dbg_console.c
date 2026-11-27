/*
 * 车体串口调试台实现。
 *
 * 组成：
 *   - UART2 P1.0/P1.1 收发环形缓冲（发送由 ISR 续发，不阻塞主循环）
 *   - Timer3 1 ms 节拍（loop/age/周期输出）
 *   - 周期快照、FIFO_FULL / LOOP_STALL / LINK_LOST / RESET 事件
 *   - ? s r d l b m v 命令
 *   - PCON/WDT_CONTR/RSTFLAG 复位原因 + EEPROM 启动次数
 *
 * 注意：调试输出绝不使用 printf —— SDCC 默认 putchar 会写 UART1，
 * 与扩展板 230400 帧互相打断。
 */
#include "main.h"

#define EE_BASE 0x000000UL

static volatile uint32_t dbg_ms;

static volatile uint8_t tx_ring[DBG_TX_RING_SIZE];
static volatile uint16_t tx_head;
static volatile uint16_t tx_tail;
static volatile uint8_t tx_active;

static volatile uint8_t rx_ring[DBG_RX_RING_SIZE];
static volatile uint8_t rx_head;
static volatile uint8_t rx_tail;

static uint32_t dbg_dropped;
static uint32_t last_rx_ms;
static uint8_t has_rx;
static uint32_t last_print_ms;
static uint16_t print_interval_ms = (uint16_t)(1000 / DBG_DEFAULT_HZ);
static uint16_t last_loop;
static uint16_t last_exp;
static uint16_t loop_max;
static uint8_t link_lost;
static uint8_t rst_code;

static uint16_t boot_count;
static const char __code *dbg_fw;
static const char __code *dbg_build;

static uint8_t line_buf[DBG_LINE_SIZE];
static uint16_t line_len;
static uint8_t line_overflow;

static void PrintSnapshot(void);
static void PrintBurstLine(void);
static void PrintHelp(void);
static void DumpRegs(void);
static void PrintVersion(void);
static void HandleCommand(uint8_t *cmd);

/* ------------------------------------------------------------------------- */
/* 行缓冲与发送队列                                                          */
/* ------------------------------------------------------------------------- */

static void LineReset(void)
{
    line_len = 0;
    line_overflow = 0;
}

static void LineChar(char c)
{
    if (line_len < (uint16_t)(DBG_LINE_SIZE - 2))
        line_buf[line_len++] = (uint8_t)c;
    else
        line_overflow = 1;
}

static void LineStr(const char __code *s)
{
    while (*s)
        LineChar(*s++);
}

static void LineU32(uint32_t v)
{
    uint8_t tmp[10];
    uint8_t n = 0;

    if (v == 0)
    {
        LineChar('0');
        return;
    }
    do
    {
        tmp[n++] = (uint8_t)('0' + (v % 10));
        v /= 10;
    } while (v);
    while (n)
        LineChar((char)tmp[--n]);
}

static void LineU16(uint16_t v)
{
    LineU32((uint32_t)v);
}

/* 用算术转换，避免 SDCC 对「常量数组 + 变址」取字节的已知问题。 */
static void LineHexDigit(uint8_t v)
{
    v &= 0x0F;
    if (v < 10)
        LineChar((char)('0' + v));
    else
        LineChar((char)('A' + v - 10));
}

static void LineHex8(uint8_t v)
{
    LineChar('0');
    LineChar('x');
    LineHexDigit((uint8_t)(v >> 4));
    LineHexDigit(v);
}

static uint16_t TxFree(void)
{
    uint16_t head = tx_head;
    uint16_t tail = tx_tail;
    uint16_t used;

    if (head >= tail)
        used = (uint16_t)(head - tail);
    else
        used = (uint16_t)(DBG_TX_RING_SIZE - tail + head);
    return (uint16_t)(DBG_TX_RING_SIZE - 1 - used);
}

static void TxEnqueue(const uint8_t *buf, uint16_t len)
{
    uint16_t i;
    uint8_t ea;

    if (TxFree() < len)
    {
        dbg_dropped++;
        return;
    }

    ea = EA;
    EA = 0;
    for (i = 0; i < len; i++)
    {
        tx_ring[tx_head] = buf[i];
        tx_head++;
        if (tx_head >= DBG_TX_RING_SIZE)
            tx_head = 0;
    }
    if (!tx_active)
    {
        tx_active = 1;
        S2BUF = tx_ring[tx_tail];
        tx_tail++;
        if (tx_tail >= DBG_TX_RING_SIZE)
            tx_tail = 0;
    }
    EA = ea;
}

static void LineEnd(void)
{
    if (line_overflow)
    {
        /* 单行超长：整行丢弃，避免输出半行无法解析。 */
        dbg_dropped++;
        LineReset();
        return;
    }
    LineChar('\r');
    LineChar('\n');
    TxEnqueue(line_buf, line_len);
    LineReset();
}

static void PrintAck(const char __code *msg)
{
    LineReset();
    LineStr("# ");
    LineStr(msg);
    LineEnd();
}

/* ------------------------------------------------------------------------- */
/* 时间与收包时间                                                            */
/* ------------------------------------------------------------------------- */

uint32_t Dbg_Millis(void)
{
    uint32_t v;
    uint8_t ea = EA;

    EA = 0;
    v = dbg_ms;
    EA = ea;
    return v;
}

void Dbg_TickIsr(void)
{
    dbg_ms++;
}

void Dbg_NoteRx(void)
{
    has_rx = 1;
    last_rx_ms = Dbg_Millis();
}

uint32_t Dbg_AgeMs(void)
{
    uint32_t now = Dbg_Millis();
    uint8_t have;
    uint32_t last;
    uint8_t ea = EA;

    EA = 0;
    have = has_rx;
    last = last_rx_ms;
    EA = ea;

    if (!have)
        return now;
    return now - last;
}

/* ------------------------------------------------------------------------- */
/* 复位原因与 EEPROM 启动次数                                                */
/* ------------------------------------------------------------------------- */

static void IapEnable(void)
{
    P_SW2 |= 0x80;
    IAP_TPS = (uint8_t)(FOSC / 1000000UL);
    IAP_CONTR = 0x80; /* IAPEN=1；不使用 SWBS/SWRST */
}

static void IapDisable(void)
{
    IAP_CONTR = 0;
    IAP_CMD = 0;
    IAP_TRIG = 0;
    IAP_ADDRH = 0xFF;
    IAP_ADDRL = 0xFF;
}

static void IapAddr(uint32_t addr)
{
    IAP_ADDRE = (uint8_t)(addr >> 16);
    IAP_ADDRH = (uint8_t)(addr >> 8);
    IAP_ADDRL = (uint8_t)addr;
}

static void IapTrigger(void)
{
    uint8_t ea = EA;

    EA = 0;
    IAP_TRIG = 0x5A;
    IAP_TRIG = 0xA5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
    EA = ea;
}

static void EeRead(uint32_t addr, uint8_t *buf, uint8_t n)
{
    uint8_t i;

    IapEnable();
    IAP_CMD = 1;
    for (i = 0; i < n; i++)
    {
        IapAddr(addr + i);
        IapTrigger();
        buf[i] = IAP_DATA;
    }
    IapDisable();
}

static void EeWrite(uint32_t addr, uint8_t *buf, uint8_t n)
{
    uint8_t i;

    IapEnable();
    IAP_CMD = 2;
    for (i = 0; i < n; i++)
    {
        IapAddr(addr + i);
        IAP_DATA = buf[i];
        IapTrigger();
    }
    IapDisable();
}

static void EeErase(uint32_t addr)
{
    IapEnable();
    IAP_CMD = 3;
    IapAddr(addr);
    IapTrigger();
    IapDisable();
}

/* 读改写 EEPROM 首扇区 4 字节：'P','B',boot_lo,boot_hi。 */
static void LoadBoot(void)
{
    uint8_t buf[4];
    uint16_t v;

    EeRead(EE_BASE, buf, 4);
    if (buf[0] != 'P' || buf[1] != 'B')
    {
        boot_count = 1;
    }
    else
    {
        v = (uint16_t)buf[2] | ((uint16_t)buf[3] << 8);
        boot_count = (v == 0xFFFF) ? 0xFFFF : (uint16_t)(v + 1);
    }

    buf[0] = 'P';
    buf[1] = 'B';
    buf[2] = (uint8_t)(boot_count & 0xFF);
    buf[3] = (uint8_t)(boot_count >> 8);

    /* 用户 EEPROM 未在 STC-ISP 中分配时，擦写无效，boot 每次退化为 1。 */
    EeErase(EE_BASE);
    EeWrite(EE_BASE, buf, 4);
}

/*
 * 复位原因：
 *   PCON.POF(bit4) 上电；WDT_CONTR.WDT_FLAG(bit7) 看门狗；
 *   RSTFLAG bit2 软件复位、bit3 外部引脚复位。
 * 头文件里的 POF/WDT_FLAG/IAPEN sbit 地址不可用，这里全部用字节掩码。
 */
static void DetectReset(void)
{
    uint8_t pcon = PCON;
    uint8_t wdt = WDT_CONTR;
    uint8_t rf = RSTFLAG;

    if (pcon & 0x10)
    {
        rst_code = 0;
        PCON = (uint8_t)(pcon & (uint8_t)~0x10);
    }
    else if (wdt & 0x80)
    {
        rst_code = 1;
        WDT_CONTR = (uint8_t)(wdt & (uint8_t)~0x80);
    }
    else if (rf & 0x04)
    {
        rst_code = 2;
    }
    else if (rf & 0x08)
    {
        rst_code = 3;
    }
    else
    {
        rst_code = 0;
    }
}

static const char __code *RstText(void)
{
    switch (rst_code)
    {
    case 1:
        return "WDG";
    case 2:
        return "SW";
    case 3:
        return "PIN";
    default:
        return "POR";
    }
}

/* ------------------------------------------------------------------------- */
/* UART2                                                                     */
/* ------------------------------------------------------------------------- */

static void Uart2Init(void)
{
    P_SW2 &= (uint8_t)~0x01; /* UART2 -> P1.0/P1.1 */
    P1M1 &= (uint8_t)~0x03;
    P1M0 &= (uint8_t)~0x01; /* P1.0 准双向输入 */
    P1M0 |= 0x02;           /* P1.1 推挽输出 */

    /*
     * 不使用 UART_Init(UART_2,...)：共享驱动只设置 S2CON.REN，漏掉
     * 模式位 0x40，这里按已验证的 UART2_DEBUG_TEST 写法直接初始化。
     */
    S2CON = 0x50; /* 模式 1，8 位 UART，允许接收 */
    T2L = (uint8_t)DBG_BR(DBG_BAUD);
    T2H = (uint8_t)(DBG_BR(DBG_BAUD) >> 8);
    AUXR |= 0x14; /* T2x12=1, T2R=1 */
    IE2 |= 0x01;  /* ES2 */
}

void Dbg_UartIsr(void)
{
    uint8_t dat;
    uint8_t next;

    if (S2CON & 0x01) /* S2RI */
    {
        dat = S2BUF;
        S2CON &= (uint8_t)~0x01;
        next = (uint8_t)(rx_head + 1);
        if (next >= DBG_RX_RING_SIZE)
            next = 0;
        if (next != rx_tail)
        {
            rx_ring[rx_head] = dat;
            rx_head = next;
        }
    }

    if (S2CON & 0x02) /* S2TI */
    {
        S2CON &= (uint8_t)~0x02;
        if (tx_head != tx_tail)
        {
            S2BUF = tx_ring[tx_tail];
            tx_tail++;
            if (tx_tail >= DBG_TX_RING_SIZE)
                tx_tail = 0;
        }
        else
        {
            tx_active = 0;
        }
    }
}

/* ------------------------------------------------------------------------- */
/* 快照、事件                                                                */
/* ------------------------------------------------------------------------- */

static void PrintBanner(void)
{
    LineReset();
    LineStr("# P" "IE-Block DBG v1 fw=");
    LineStr(dbg_fw);
    LineStr(" build=");
    LineStr(dbg_build);
    LineStr(" board=STC32G12K128 ch=");
    LineU32(NRF_CHANNEL);
    LineStr(" rate=250k retr=");
    LineHex8(NRF_SETUP_RETR_V);
    LineEnd();
}

static void PrintResetEvent(void)
{
    LineReset();
    LineStr("ev=RESET rst=");
    LineStr(RstText());
    LineStr(" boot=");
    LineU16(boot_count);
    LineEnd();
}

static void PrintFifoFull(void)
{
    NrfStats s;

    Nrf_GetStats(&s);
    LineReset();
    LineStr("ev=FIFO_FULL t=");
    LineU32(Dbg_Millis());
    LineStr(" loop=");
    LineU16(last_loop);
    LineStr(" fifo=");
    LineHex8(s.fifo);
    LineStr(" drain=");
    LineU16(s.drain);
    LineStr(" age=");
    LineU32(Dbg_AgeMs());
    LineStr(" maxrt=");
    LineU32(s.maxrt);
    LineEnd();
}

void Dbg_AfterNrfHandler(void)
{
    uint8_t events = Nrf_TakeEvents();

    if (events & NRF_EVT_FIFO_FULL)
        PrintFifoFull();
}

static void PrintSnapshot(void)
{
    NrfStats s;
    uint32_t now;
    uint32_t age;

    Nrf_GetStats(&s);
    now = Dbg_Millis();
    age = Dbg_AgeMs();

    LineReset();
    LineStr("t=");
    LineU32(now);
    LineStr(" loop=");
    LineU16(last_loop);
    LineStr(" loop_max=");
    LineU16(loop_max);
    LineStr(" exp_ms=");
    LineU16(last_exp);
    LineStr(" mode=");
    if (s.mode == NRF_MODE_TX)
        LineStr("TX");
    else
        LineStr("RX");
    LineStr(" st=");
    LineHex8(s.st);
    LineStr(" fifo=");
    LineHex8(s.fifo);
    LineStr(" drain=");
    LineU16(s.drain);
    LineStr(" drain_max=");
    LineU16(s.drain_max);
    LineStr(" rx=");
    LineU32(s.rx);
    LineStr(" rx_dr=");
    LineU32(s.rx_dr);
    LineStr(" tx=");
    LineU32(s.tx);
    LineStr(" tx_ds=");
    LineU32(s.tx_ds);
    LineStr(" maxrt=");
    LineU32(s.maxrt);
    LineStr(" age=");
    LineU32(age);
    LineStr(" ch=");
    LineU16(s.ch);
    LineStr(" rf=");
    LineHex8(s.rf);
    LineStr(" retr=");
    LineHex8(s.retr);
    LineStr(" rst=");
    LineStr(RstText());
    LineStr(" boot=");
    LineU16(boot_count);
    LineStr(" dbg_dropped=");
    LineU32(dbg_dropped);
    LineEnd();
}

static void PrintBurstLine(void)
{
    NrfStats s;

    Nrf_GetStats(&s);
    LineReset();
    LineStr("b=1 t=");
    LineU32(Dbg_Millis());
    LineStr(" fifo=");
    LineHex8(s.fifo);
    LineStr(" drain=");
    LineU16(s.drain);
    LineStr(" rx=");
    LineU32(s.rx);
    LineStr(" rx_dr=");
    LineU32(s.rx_dr);
    LineStr(" age=");
    LineU32(Dbg_AgeMs());
    LineEnd();
}

void Dbg_EndLoop(uint16_t loop_ms, uint16_t exp_ms)
{
    uint32_t now;
    uint32_t age;

    last_loop = loop_ms;
    last_exp = exp_ms;
    if (loop_ms > loop_max)
        loop_max = loop_ms;

    now = Dbg_Millis();
    age = Dbg_AgeMs();

    if (loop_ms > 100)
    {
        LineReset();
        LineStr("ev=LOOP_STALL t=");
        LineU32(now);
        LineStr(" loop=");
        LineU16(loop_ms);
        LineStr(" exp_ms=");
        LineU16(exp_ms);
        LineEnd();
    }

    if (age > DBG_LINK_TIMEOUT_MS)
    {
        if (!link_lost)
        {
            link_lost = 1;
            LineReset();
            LineStr("ev=LINK_LOST t=");
            LineU32(now);
            LineStr(" age=");
            LineU32(age);
            LineEnd();
        }
    }
    else
    {
        link_lost = 0;
    }

    if ((uint32_t)(now - last_print_ms) >= (uint32_t)print_interval_ms)
    {
        last_print_ms = now;
        PrintSnapshot();
    }
}

/* ------------------------------------------------------------------------- */
/* 命令                                                                      */
/* ------------------------------------------------------------------------- */

static uint16_t ParseNumber(uint8_t *s)
{
    uint16_t v = 0;

    while (*s == ' ')
        s++;
    while (*s >= '0' && *s <= '9')
    {
        v = (uint16_t)(v * 10 + (uint16_t)(*s - '0'));
        s++;
    }
    return v;
}

static void PrintRate(uint16_t hz)
{
    LineReset();
    LineStr("# rate=");
    LineU16(hz);
    LineStr("Hz interval=");
    LineU16(print_interval_ms);
    LineStr("ms");
    LineEnd();
}

static void Burst(uint16_t n)
{
    uint16_t i;

    if (n < 1)
        n = 1;
    if (n > 200)
        n = 200;

    PrintAck("b burst start; control/telemetry paused");
    for (i = 0; i < n; i++)
    {
        Nrf_Handler();
        Dbg_AfterNrfHandler();
        PrintBurstLine();
        Ms_Delay(1);
    }

    LineReset();
    LineStr("# b done dbg_dropped=");
    LineU32(dbg_dropped);
    LineEnd();
}

static void ForceMode(uint8_t *cmd)
{
    uint8_t *p = cmd + 1;

    while (*p == ' ')
        p++;
    if ((p[0] == 'r' || p[0] == 'R') && (p[1] == 'x' || p[1] == 'X'))
    {
        Nrf_ForceRx();
        PrintAck("mode=RX");
    }
    else if ((p[0] == 't' || p[0] == 'T') && (p[1] == 'x' || p[1] == 'X'))
    {
        Nrf_ForceTx();
        PrintAck("mode=TX");
    }
    else
    {
        PrintAck("usage: m rx | m tx");
    }
}

static void DumpRegs(void)
{
    uint8_t addr[5];
    uint8_t i;

    LineReset();
    LineStr("# CONFIG=");
    LineHex8(Nrf_ReadReg(NRF_REG_CONFIG));
    LineStr(" EN_AA=");
    LineHex8(Nrf_ReadReg(NRF_REG_EN_AA));
    LineStr(" EN_RXADDR=");
    LineHex8(Nrf_ReadReg(NRF_REG_EN_RXADDR));
    LineStr(" SETUP_AW=");
    LineHex8(Nrf_ReadReg(NRF_REG_SETUP_AW));
    LineEnd();

    LineReset();
    LineStr("# SETUP_RETR=");
    LineHex8(Nrf_ReadReg(NRF_REG_SETUP_RETR));
    LineStr(" RF_CH=");
    LineHex8(Nrf_ReadReg(NRF_REG_RF_CH));
    LineStr(" RF_SETUP=");
    LineHex8(Nrf_ReadReg(NRF_REG_RF_SETUP));
    LineStr(" RX_PW_P0=");
    LineHex8(Nrf_ReadReg(NRF_REG_RX_PW_P0));
    LineEnd();

    Nrf_ReadBuf(NRF_REG_RX_ADDR_P0, addr, 5);
    LineReset();
    LineStr("# RX_ADDR_P0=");
    for (i = 0; i < 5; i++)
    {
        if (i)
            LineChar(' ');
        LineHex8(addr[i]);
    }
    LineEnd();

    Nrf_ReadBuf(NRF_REG_TX_ADDR, addr, 5);
    LineReset();
    LineStr("# TX_ADDR=");
    for (i = 0; i < 5; i++)
    {
        if (i)
            LineChar(' ');
        LineHex8(addr[i]);
    }
    LineEnd();

    LineReset();
    LineStr("# FIFO_STATUS=");
    LineHex8(Nrf_ReadReg(NRF_REG_FIFO_STATUS));
    LineStr(" STATUS=");
    LineHex8(Nrf_ReadReg(NRF_REG_STATUS));
    LineStr(" OBSERVE_TX=");
    LineHex8(Nrf_ReadReg(NRF_REG_OBSERVE_TX));
    LineStr(" RPD=");
    LineHex8(Nrf_ReadReg(NRF_REG_RPD));
    LineEnd();
}

static void PrintVersion(void)
{
    NrfStats s;

    Nrf_GetStats(&s);

    LineReset();
    LineStr("# P" "IE-Block DBG v1 fw=");
    LineStr(dbg_fw);
    LineStr(" build=");
    LineStr(dbg_build);
    LineStr(" ch=");
    LineU16(s.ch);
    LineStr(" rf=");
    LineHex8(s.rf);
    LineStr(" retr=");
    LineHex8(s.retr);
    LineEnd();

    LineReset();
    LineStr("# UART2 P1.0=RX P1.1=TX ");
    LineU32(DBG_BAUD);
    LineStr(" 8N1 3.3V TTL GND");
    LineEnd();
}

static void PrintHelp(void)
{
    PrintAck("P" "IE-Block DBG v1 help");
    PrintAck("UART2 P1.0=RX P1.1=TX 115200 8N1, 3.3V TTL, common GND");
    PrintAck("? help | s snapshot | r clear counters | d nrf regs");
    PrintAck("l <hz> 1-20 | b <n> 1ms burst (control paused, n<=200)");
    PrintAck("m rx | m tx | v version");
    PrintAck("b at 115200 drops lines (dbg_dropped); 921600 recommended");
    PrintAck("STC-ISP: set user EEPROM >=1 sector for boot counter");
}

static void HandleCommand(uint8_t *cmd)
{
    uint16_t arg;

    switch (cmd[0])
    {
    case '?':
        PrintHelp();
        break;
    case 's':
        PrintSnapshot();
        break;
    case 'r':
        Nrf_ResetCounters();
        loop_max = 0;
        dbg_dropped = 0;
        PrintAck("counters cleared");
        break;
    case 'd':
        DumpRegs();
        break;
    case 'v':
        PrintVersion();
        break;
    case 'l':
        arg = ParseNumber(cmd + 1);
        if (arg < 1)
            arg = 1;
        if (arg > 20)
            arg = 20;
        print_interval_ms = (uint16_t)(1000 / arg);
        PrintRate(arg);
        break;
    case 'b':
        Burst(ParseNumber(cmd + 1));
        break;
    case 'm':
        ForceMode(cmd);
        break;
    default:
        PrintAck("unknown command, send ? for help");
        break;
    }
}

void Dbg_PollCommands(void)
{
    static uint8_t cmd[32];
    static uint8_t cmd_len;
    static uint8_t discard;
    uint8_t c;

    while (rx_tail != rx_head)
    {
        c = rx_ring[rx_tail];
        rx_tail++;
        if (rx_tail >= DBG_RX_RING_SIZE)
            rx_tail = 0;

        if (c == '\r' || c == '\n')
        {
            if (discard)
            {
                discard = 0;
                cmd_len = 0;
            }
            else if (cmd_len)
            {
                cmd[cmd_len] = 0;
                HandleCommand(cmd);
                cmd_len = 0;
            }
            continue;
        }

        if (discard)
            continue;
        if (cmd_len < (uint8_t)(sizeof(cmd) - 1))
            cmd[cmd_len++] = c;
        else
        {
            discard = 1;
            cmd_len = 0;
        }
    }
}

/* ------------------------------------------------------------------------- */
/* 初始化                                                                    */
/* ------------------------------------------------------------------------- */

void Dbg_Init(const char __code *fw, const char __code *build)
{
    dbg_fw = fw;
    dbg_build = build;

    DetectReset();
    LoadBoot();
    Uart2Init();

    dbg_ms = 0;
    last_rx_ms = 0;
    has_rx = 0;
    last_print_ms = 0;
    link_lost = 0;
    loop_max = 0;

    PIT_Timer_Ms(TIM3, 1);

    PrintBanner();
    PrintResetEvent();
}

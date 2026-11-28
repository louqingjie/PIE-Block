/*
 * 车体串口调试台实现（v2 诊断版）。
 *
 * 组成：
 *   - UART2 P1.0/P1.1 收发环形缓冲（发送由 ISR 续发，不阻塞主循环）
 *   - Timer3 1 ms 节拍（loop/age/周期输出）
 *   - 周期快照、FIFO_FULL / TX_STUCK / LOOP_STALL / LINK_LOST / RESET 事件
 *   - ? s r d l b m v e z p w 命令
 *   - 复位原因按手册 9.1.4 解码（LVD/WDG/SW/ROMOVF/PIN）+ 原始 RSTFLAG/WDT_CONTR
 *   - 复位之间的启动序号：用不参与 SDCC 启动清零的绝对 XDATA 保存，不依赖 EEPROM
 *
 * 注意：调试输出绝不使用 printf —— SDCC 默认 putchar 会写 UART1，
 * 与扩展板 230400 帧互相打断。
 */
#include "main.h"

/*
 * 复位之间保留的启动序号（不依赖 EEPROM）。
 *
 * SDCC 的 crtxclear 只清 XSEG 区（本工程 0x010000..0x01074B），XABS 不会被
 * 启动代码清零；STC32G 的 XRAM 在除上电以外的复位后内容保留，因此这块
 * “绝对 XDATA 小尾巴”可以数清同一上电周期内复位了几次：
 *   - 冷上电：magic 不匹配 → seq=1；
 *   - 之后每次复位：magic 匹配 → seq++。
 * 地址 0x011FF0 在 --xram-size 0x2000（0x010000..0x011FFF）范围内、远离
 * XSEG 区，也不与 MCS-251 的 EDATA 栈（0x000000 起）冲突。
 */
#define DBG_BOOT_MAGIC 0x5AU
static volatile __xdata __at (0x011FF0) uint16_t boot_seq_ram;
static volatile __xdata __at (0x011FF2) uint8_t boot_magic_ram;

/*
 * 跑飞面包屑：同一条 XRAM 尾巴内记录“最后执行到的主循环阶段”。
 * 复位后由启动代码打印 # LAST stage=.. t=..，定位 ROMOVF 发生的位置。
 *   stage 0      = 尚未进入主循环
 *   10..19       = 主循环各步骤（见 main.c 的 Dbg_Mark 调用）
 *   30..39       = Dbg_EndLoop / PrintSnapshot 内部
 *   50..59       = nRF 中断处理/发送内部
 *   60..69       = UART2 发送内部
 */
static volatile __xdata __at (0x011FF3) uint8_t mark_stage;
static volatile __xdata __at (0x011FF4) uint32_t mark_ms;
static volatile __xdata __at (0x011FF8) uint16_t mark_sp_max;

static uint8_t last_stage;
static uint32_t last_ms;
static uint16_t last_sp_max;


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

/* 复位原因原始值（DetectReset 一次性采样，命令 e 可重复打印）。 */
static uint8_t rst_raw;
static uint8_t rst_pcon;
static uint8_t rst_wdt;
static uint8_t rst_rstcfg;

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
static void PrintResetEvent(void);
static void PrintLastMark(void);
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
/* 复位原因与启动序号                                                        */
/* ------------------------------------------------------------------------- */

/*
 * 启动序号：XRAM 不参与 SDCC 启动清零的绝对地址区，复位后内容保留，
 * 用 magic 判断是「同一上电周期内的第几次复位」还是「冷上电首启」。
 * 仅用于诊断，不做持久化；启动路径不再访问 IAP/EEPROM——旧实现读写的
 * 0x000000 并不是这颗芯片的用户 EEPROM 地址（用户 EEPROM 在 flash 顶部，
 * 地址取决于 STC-ISP 分配），写入还可能破坏程序区。
 */
static void LoadBoot(void)
{
    if (boot_magic_ram == DBG_BOOT_MAGIC && boot_seq_ram != 0xFFFFU)
    {
        boot_seq_ram++;
        /* 上一轮留下的面包屑就是这次复位前的最后现场 */
        last_stage = mark_stage;
        last_ms = mark_ms;
        last_sp_max = mark_sp_max;
    }
    else
    {
        boot_seq_ram = 1;
        last_stage = 0;
        last_ms = 0;
        last_sp_max = 0;
    }

    boot_magic_ram = DBG_BOOT_MAGIC;
    boot_count = boot_seq_ram;

    mark_stage = 0;
    mark_ms = 0;
    mark_sp_max = 0;
}

/*
 * 面包屑写入点：只写几个 XRAM 字节，开销可忽略。
 * 同时记录观测到的最大 SP（栈深），用于判断是否栈溢出。
 */
void Dbg_Mark(uint8_t stage)
{
    uint16_t sp = (uint16_t)(((uint16_t)SPH << 8) | (uint16_t)SP);

    mark_stage = stage;
    mark_ms = dbg_ms;
    if (sp > mark_sp_max)
        mark_sp_max = sp;
}

/*
 * RSTFLAG（扩展 SFR 0x7EFE99，手册 9.1.4）：
 *   B4 LVDRSTF 低压复位、B3 WDTRSTF 看门狗复位、B2 SWRSTF 软件复位、
 *   B1 ROMOVF  代码区溢出（跑飞/中断向量缺失）、B0 EXRSTF 复位脚。
 * 读 1 有效；写 1 清除（写 0 无效）。上电默认 LVD+SW 置位（0x14）。
 * SWRSTF 不清：STC-ISP 的「软复位进系统区」判断依赖它。
 *
 * PCON.POF 只在本次是上电复位时为 1，用来把「上电默认 0x14」与
 * 「真正的低压复位」区分开。
 */
#define RST_LVD 0x10U
#define RST_WDT 0x08U
#define RST_SW 0x04U
#define RST_ROV 0x02U
#define RST_PIN 0x01U
#define RST_CLEAR_MASK (RST_LVD | RST_WDT | RST_ROV | RST_PIN)
#define PCON_POF_MASK 0x10U

static void DetectReset(void)
{
    uint8_t pcon = PCON;
    uint8_t wdt = WDT_CONTR;
    uint8_t rstcfg = RSTCFG;
    uint8_t rf;
    uint8_t ea = EA;

    /* RSTFLAG 在扩展 SFR 区，访问前必须 EAXFR=1。 */
    EA = 0;
    P_SW2 |= 0x80;
    rf = RSTFLAG;
    RSTFLAG = RST_CLEAR_MASK; /* 写 1 清零，留 SWRSTF 给 ISP */
    EA = ea;

    rst_raw = rf;
    rst_pcon = pcon;
    rst_wdt = wdt;
    rst_rstcfg = rstcfg;

    if (pcon & PCON_POF_MASK)
        PCON = (uint8_t)(pcon & (uint8_t)~PCON_POF_MASK);
}

static const char __code *RstText(void)
{
    if (rst_raw & RST_WDT)
        return "WDG";
    if (rst_raw & RST_ROV)
        return "ROV";
    if (rst_raw & RST_PIN)
        return "PIN";
    if (rst_raw & RST_LVD)
        return (rst_pcon & PCON_POF_MASK) ? "POR" : "LVD";
    if (rst_raw & RST_SW)
        return "SW";
    return "POR";
}

static void LineRstFlags(uint8_t raw)
{
    uint8_t first = 1;

    if (raw & RST_LVD)
    {
        LineStr("LVD");
        first = 0;
    }
    if (raw & RST_WDT)
    {
        if (!first)
            LineChar('+');
        LineStr("WDG");
        first = 0;
    }
    if (raw & RST_ROV)
    {
        if (!first)
            LineChar('+');
        LineStr("ROV");
        first = 0;
    }
    if (raw & RST_PIN)
    {
        if (!first)
            LineChar('+');
        LineStr("PIN");
        first = 0;
    }
    if (raw & RST_SW)
    {
        if (!first)
            LineChar('+');
        LineStr("SW");
        first = 0;
    }
    if (first)
        LineStr("none");
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
/* 启动自检与复位信息                                                        */
/* ------------------------------------------------------------------------- */

static void PrintBanner(void)
{
    LineReset();
    LineStr("# P" "IE-Block DBG v2diag fw=");
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
    LineStr(" raw=");
    LineHex8(rst_raw);
    LineStr(" flags=");
    LineRstFlags(rst_raw);
    LineStr(" pcon=");
    LineHex8(rst_pcon);
    LineStr(" wdt=");
    LineHex8(rst_wdt);
    LineStr(" rstcfg=");
    LineHex8(rst_rstcfg);
    LineEnd();
}

void Dbg_PrintResetInfo(void)
{
    PrintResetEvent();
    PrintLastMark();
}

/* 上一次复位前最后执行到的阶段（上电首启时 last_stage=0，不打印）。 */
static void PrintLastMark(void)
{
    if (last_stage == 0 && last_ms == 0)
        return;

    LineReset();
    LineStr("# LAST stage=");
    LineU16(last_stage);
    LineStr(" t=");
    LineU32(last_ms);
    LineStr(" spmax=");
    LineU16(last_sp_max);
    LineEnd();
}

/* Nrf_Init() 之后调用：每次启动都打印一次 nRF 状态，用于确认模块是否真的通了。 */
void Dbg_BootNrfReport(void)
{
    uint8_t addr[5];
    uint8_t i;

    LineReset();
    LineStr("# NRF init=");
    LineU16(Nrf_InitOk());
    LineStr(" config=");
    LineHex8(Nrf_ReadReg(NRF_REG_CONFIG));
    LineStr(" enaa=");
    LineHex8(Nrf_ReadReg(NRF_REG_EN_AA));
    LineStr(" enrx=");
    LineHex8(Nrf_ReadReg(NRF_REG_EN_RXADDR));
    LineStr(" rxq=");
    LineHex8(Nrf_ReadReg(NRF_REG_RX_PW_P0));
    LineStr(" fifo=");
    LineHex8(Nrf_ReadReg(NRF_REG_FIFO_STATUS));
    LineStr(" st=");
    LineHex8(Nrf_ReadReg(NRF_REG_STATUS));
    LineEnd();

    LineReset();
    LineStr("# NRF ch=");
    LineHex8(Nrf_ReadReg(NRF_REG_RF_CH));
    LineStr(" rf=");
    LineHex8(Nrf_ReadReg(NRF_REG_RF_SETUP));
    LineStr(" retr=");
    LineHex8(Nrf_ReadReg(NRF_REG_SETUP_RETR));
    Nrf_ReadBuf(NRF_REG_TX_ADDR, addr, 5);
    LineStr(" txadr=");
    for (i = 0; i < 5; i++)
    {
        if (i)
            LineChar(' ');
        LineHex8(addr[i]);
    }
    LineEnd();
}

/* All_Init() 末尾调用：看到这行才说明初始化完整跑完、准备进主循环。 */
void Dbg_InitDone(void)
{
    LineReset();
    LineStr("# init done t=");
    LineU32(Dbg_Millis());
    LineStr(" nrf=");
    LineU16(Nrf_InitOk());
    LineEnd();
}

/* ------------------------------------------------------------------------- */
/* 快照、事件                                                                */
/* ------------------------------------------------------------------------- */

static void PrintFifoFull(void)
{
    static NrfStats s;

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

static void PrintTxStuck(void)
{
    static NrfStats s;

    Nrf_GetStats(&s);
    LineReset();
    LineStr("ev=TX_STUCK t=");
    LineU32(Dbg_Millis());
    LineStr(" st=");
    LineHex8(s.st);
    LineStr(" fifo=");
    LineHex8(s.fifo);
    LineStr(" txto=");
    LineU32(s.tx_to);
    LineStr(" stuck=");
    LineU32(s.tx_stuck);
    LineStr(" age=");
    LineU32(Dbg_AgeMs());
    LineEnd();
}

void Dbg_AfterNrfHandler(void)
{
    uint8_t events = Nrf_TakeEvents();

    if (events & NRF_EVT_FIFO_FULL)
        PrintFifoFull();
    if (events & NRF_EVT_TX_STUCK)
        PrintTxStuck();
}

static void PrintSnapshot(void)
{
    static NrfStats s;
    uint32_t now;
    uint32_t age;

    Dbg_Mark(40);
    Nrf_GetStats(&s);
    now = Dbg_Millis();
    age = Dbg_AgeMs();
    Dbg_Mark(41);

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
    Dbg_Mark(42);
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
    LineStr(" txto=");
    LineU32(s.tx_to);
    LineStr(" stuck=");
    LineU32(s.tx_stuck);
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
    LineStr(" wdt=");
    LineHex8(WDT_CONTR);
    LineStr(" dbg_dropped=");
    LineU32(dbg_dropped);
    Dbg_Mark(43);
    LineEnd();
    Dbg_Mark(44);
}

static void PrintBurstLine(void)
{
    static NrfStats s;

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

    Dbg_Mark(30);

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
        Dbg_Mark(31);
        PrintSnapshot();
        Dbg_Mark(32);
    }
    Dbg_Mark(33);
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
    static NrfStats s;

    Nrf_GetStats(&s);

    LineReset();
    LineStr("# P" "IE-Block DBG v2diag fw=");
    LineStr(dbg_fw);
    LineStr(" build=");
    LineStr(dbg_build);
    LineStr(" ch=");
    LineU16(s.ch);
    LineStr(" rf=");
    LineHex8(s.rf);
    LineStr(" retr=");
    LineHex8(s.retr);
    LineStr(" link=");
    LineU16(s.link);
    LineStr(" txto=");
    LineU32(s.tx_to);
    LineStr(" stuck=");
    LineU32(s.tx_stuck);
    LineEnd();

    LineReset();
    LineStr("# UART2 P1.0=RX P1.1=TX ");
    LineU32(DBG_BAUD);
    LineStr(" 8N1 3.3V TTL GND");
    LineEnd();
}

static void PrintHelp(void)
{
    PrintAck("P" "IE-Block DBG v2diag help");
    PrintAck("UART2 P1.0=RX P1.1=TX 115200 8N1, 3.3V TTL, common GND");
    PrintAck("? help | s snapshot | r clear counters | d nrf regs");
    PrintAck("e reset info | v version | l <hz> 1-20 | m rx | m tx");
    PrintAck("z buzzer off | p beep 1kHz 200ms");
    PrintAck("w show wdt/rstflag | w0 disable wdt | wf feed wdt(ps=7)");
    PrintAck("b <n> 1ms burst (control paused, n<=200; 115200 drops lines)");
}

/*
 * 看门狗/复位标志查看命令。
 *
 * WDT_CONTR（0xC1H，手册 9.3）：B7 WDT_FLAG、B5 EN_WDT、B4 CLR_WDT、
 * B3 IDL_WDT、B2:0 WDT_PS。EN_WDT=1 表示看门狗正在计数；若没喂狗，
 * 硬件会在超时后复位（日志表现为 ev=RESET flags=WDG）。
 */
static void WdtCommand(uint8_t *cmd)
{
    uint8_t *p = cmd + 1;
    uint8_t raw;
    uint8_t ea = EA;

    while (*p == ' ')
        p++;

    if (p[0] == '0')
    {
        EA = 0;
        P_SW2 |= 0x80;
        WDT_CONTR = 0x00; /* EN_WDT=0：关闭看门狗 */
        EA = ea;
        PrintAck("wdt disabled (WDT_CONTR=0)");
        return;
    }

    if (p[0] == 'f' || p[0] == 'F')
    {
        EA = 0;
        P_SW2 |= 0x80;
        WDT_CONTR = 0x37; /* EN_WDT=1 + CLR_WDT=1 + WDT_PS=111（约 4.5 s） */
        EA = ea;
        PrintAck("wdt fed, ps=7 (~4.5s)");
        return;
    }

    raw = WDT_CONTR;
    LineReset();
    LineStr("# wdt_contr=");
    LineHex8(raw);
    LineStr(" en_wdt=");
    LineU16((raw & 0x20U) ? 1 : 0);
    LineStr(" ps=");
    LineU16((uint16_t)(raw & 0x07U));
    EA = 0;
    P_SW2 |= 0x80;
    LineStr(" rstflag=");
    LineHex8(RSTFLAG);
    EA = ea;
    LineStr(" boot=");
    LineU16(boot_count);
    LineStr(" rstcfg=");
    LineHex8(RSTCFG);
    LineEnd();
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
    case 'e':
        Dbg_PrintResetInfo();
        break;
    case 'z':
        Buzzer_Silence();
        PrintAck("buzzer silenced");
        break;
    case 'p':
        Buzzer_Beep(1000, 200);
        PrintAck("beep 1000Hz 200ms");
        break;
    case 'w':
        WdtCommand(cmd);
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
    PrintLastMark();
}

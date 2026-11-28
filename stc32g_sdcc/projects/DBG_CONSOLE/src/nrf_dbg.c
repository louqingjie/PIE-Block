/*
 * 本工程私有的 nRF24L01+ 驱动副本（带调试统计）。
 *
 * 与 stc32g_sdcc/libraries/boards/src/nrf24l01.c 的射频配置、控制包解包
 * 与 22 字节遥测帧完全一致；额外提供调试台所需的寄存器快照和计数。
 */
#include "main.h"

/* SPI 命令 */
#define NRF_READ_REG 0x00
#define NRF_WRITE_REG 0x20
#define RD_RX_PLOAD 0x61
#define WR_TX_PLOAD 0xA0
#define FLUSH_TX 0xE1
#define FLUSH_RX 0xE2
#define NRF_NOP 0xFF

/* 状态位 */
#define NRF_RX_DR 0x40
#define NRF_TX_DS 0x20
#define NRF_MAX_RT 0x10
/* FIFO_STATUS 位（nRF24L01+ 规格书 v1.0 p.61）：
 * bit0 RX_EMPTY、bit1 RX_FULL；旧实现误写成 bit6/bit4，导致 drain 与
 * FIFO_FULL 事件长期失真。 */
#define NRF_RX_FULL 0x02
#define NRF_RX_EMPTY 0x01

/* 引脚：CE=P3.4，CSN=P2.2，IRQ=P2.6，SPI2: SCK=P2.5/MOSI=P2.3/MISO=P2.4 */
#define NRF_CE_PORT GPIO_P3
#define NRF_CE_PIN GPIO_Pin_4
#define NRF_CSN_PORT GPIO_P2
#define NRF_CSN_PIN GPIO_Pin_2
#define NRF_MISO_PORT GPIO_P2
#define NRF_MISO_PIN GPIO_Pin_4
#define NRF_IRQ_PORT GPIO_P2
#define NRF_IRQ_PIN GPIO_Pin_6

/*
 * CE/CSN 直接用位寻址 SFR 写，不再走 GPIO_Write_Bit()。
 * 后者是 switch + 跳表（movc 取目标地址 → ejmp @dr28），而 SDCC mcs251 的
 * __interrupt 序言不保存 DPXL；这里属于主循环最高频路径，改成单指令位写
 * 后既快，也不依赖 24 位跳表取址。
 */
#define NRF_CE_LOW() (P34 = 0)
#define NRF_CE_HIGH() (P34 = 1)
#define NRF_CSN_LOW() (P22 = 0)
#define NRF_CSN_HIGH() (P22 = 1)

static uint8_t nrf_addr[5] = {'R', 'C', 'T', 'L', NRF_CHANNEL};
static uint8_t nrf_rx_buff[NRF_RX_PAYLOAD];
static uint8_t nrf_tx_buff[NRF_TX_PAYLOAD + 2];
static int16_t nrf_rocker[4];

static NrfMode nrf_mode = NRF_MODE_INIT;
static uint8_t nrf_force_tx = 0;
static uint8_t nrf_events = 0;
static uint8_t nrf_link_ok = 0;
static uint8_t tx_stall_rounds = 0;

static uint32_t stat_rx = 0;
static uint32_t stat_rx_dr = 0;
static uint32_t stat_tx = 0;
static uint32_t stat_tx_ds = 0;
static uint32_t stat_maxrt = 0;
static uint32_t stat_tx_to = 0;
static uint32_t stat_tx_stuck = 0;
static uint16_t stat_drain_max = 0;
static uint8_t stat_drain = 0;
static uint8_t stat_st = 0;
static uint8_t stat_fifo = 0;
static uint8_t stat_ch = NRF_CHANNEL;
static uint8_t stat_rf = NRF_RF_SETUP_V;
static uint8_t stat_retr = NRF_SETUP_RETR_V;

static uint8_t nrf_readreg(uint8_t reg)
{
    uint8_t value;
    NRF_CSN_LOW();
    SPI_ReadWriteByte(reg);
    value = SPI_ReadWriteByte(NRF_NOP);
    NRF_CSN_HIGH();
    return value;
}

static void nrf_writereg(uint8_t reg, uint8_t dat)
{
    NRF_CSN_LOW();
    SPI_ReadWriteByte(reg);
    SPI_ReadWriteByte(dat);
    NRF_CSN_HIGH();
}

static void nrf_writebuf(uint8_t reg, uint8_t *buf, uint8_t len)
{
    NRF_CSN_LOW();
    SPI_ReadWriteByte(reg);
    while (len--)
        SPI_ReadWriteByte(*buf++);
    NRF_CSN_HIGH();
}

static void nrf_readbuf(uint8_t reg, uint8_t *buf, uint8_t len)
{
    NRF_CSN_LOW();
    SPI_ReadWriteByte(reg);
    while (len--)
        *buf++ = SPI_ReadWriteByte(NRF_NOP);
    NRF_CSN_HIGH();
}

/* 写/读 TX_ADDR 校验模块是否在线；失败也允许继续运行。 */
static uint8_t nrf_link_check(void)
{
    uint8_t buff[5] = {0x06, 0x06, 0x06, 0x06, 0x06};
    uint8_t i;

    NRF_CE_LOW();
    nrf_writebuf(NRF_WRITE_REG + NRF_REG_TX_ADDR, buff, 5);
    nrf_readbuf(NRF_REG_TX_ADDR, buff, 5);
    NRF_CE_HIGH();

    for (i = 0; i < 5; i++)
    {
        if (buff[i] != 0x06)
            return 0;
    }
    return 1;
}

/* 切回 RX：只改 CONFIG，不清 RX FIFO，避免丢掉 TX 期间已入队的控制包。 */
static void nrf_enter_rx(void)
{
    NRF_CE_LOW();
    nrf_writereg(NRF_WRITE_REG + NRF_REG_CONFIG, 0x0F);
    nrf_writereg(FLUSH_TX, NRF_NOP); /* 丢弃强制 TX/异常路径残留的发送包 */
    NRF_CE_HIGH();
    nrf_mode = NRF_MODE_RX;
}

/* 写入完整射频配置并进入 RX；模块晚上电时可在重试中重复调用。 */
static void nrf_apply_config(void)
{
    NRF_CE_LOW();
    nrf_writereg(NRF_WRITE_REG + NRF_REG_SETUP_AW, 3); /* 5 字节地址 */
    nrf_writereg(NRF_WRITE_REG + NRF_REG_RF_CH, NRF_CHANNEL);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_RF_SETUP, NRF_RF_SETUP_V);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_EN_AA, 0x01);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_EN_RXADDR, 0x01);

    nrf_writebuf(NRF_WRITE_REG + NRF_REG_RX_ADDR_P0, nrf_addr, 5);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_RX_PW_P0, NRF_RX_PAYLOAD);
    nrf_writereg(FLUSH_RX, NRF_NOP);

    nrf_writebuf(NRF_WRITE_REG + NRF_REG_TX_ADDR, nrf_addr, 5);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_SETUP_RETR, NRF_SETUP_RETR_V);
    nrf_writereg(FLUSH_TX, NRF_NOP);

    /* 清掉上电/上次运行残留的状态位，避免第一包遥测被旧标志干扰。 */
    nrf_writereg(NRF_WRITE_REG + NRF_REG_STATUS, 0xFF);

    nrf_enter_rx();
}

static void nrf_enter_tx(void)
{
    NRF_CE_LOW();
    nrf_writebuf(NRF_WRITE_REG + NRF_REG_TX_ADDR, nrf_addr, 5);
    /* 管道 0 地址同时用于接收 ACK。 */
    nrf_writebuf(NRF_WRITE_REG + NRF_REG_RX_ADDR_P0, nrf_addr, 5);
    nrf_writereg(NRF_WRITE_REG + NRF_REG_CONFIG, 0x0E);
    NRF_CE_HIGH();
    nrf_mode = NRF_MODE_TX;
    Ms_Delay(1);
}

static void nrf_send_payload(uint8_t *payload, uint8_t len)
{
    uint8_t i;
    uint8_t crc = 0;
    uint8_t *p;

    nrf_tx_buff[0] = (uint8_t)(len + 1);
    memcpy(nrf_tx_buff + 1, payload, len);

    p = payload;
    for (i = 0; i < len; i++)
        crc += *p++;
    nrf_tx_buff[len + 1] = crc;

    if (nrf_mode != NRF_MODE_TX)
        nrf_enter_tx();

    Dbg_Mark(60);
    NRF_CE_LOW();
    nrf_writebuf(WR_TX_PLOAD, nrf_tx_buff, (uint8_t)(len + 2));
    NRF_CE_HIGH();
    Dbg_Mark(61);
}

/*
 * 有界等待遥测发送结果（TX_DS 或 MAX_RT），无论成功/超时都立即切回 RX。
 *
 * 旧实现固定 Ms_Delay(3) 后调用 handler：250 kbps、ARC=5 时重发跑满要 4 ms
 * 以上，3 ms 内看不到标志，nrf_mode 就一直停在 TX；主循环随后再也收不到
 * 控制包（日志表现：mode=TX、tx_ds=0、maxrt=0、age 单调增长）。
 */
static uint8_t nrf_wait_tx_done(uint8_t timeout_ms)
{
    uint8_t i;
    uint8_t state;

    for (i = 0; i < timeout_ms; i++)
    {
        state = nrf_readreg(NRF_REG_STATUS);
        if (state & (NRF_TX_DS | NRF_MAX_RT))
        {
            nrf_writereg(NRF_WRITE_REG + NRF_REG_STATUS, state);
            if (state & NRF_TX_DS)
                stat_tx_ds++;
            if (state & NRF_MAX_RT)
            {
                stat_maxrt++;
                nrf_writereg(FLUSH_TX, NRF_NOP);
            }
            Dbg_Mark(54);
            nrf_enter_rx();
            return 1;
        }
        Ms_Delay(1);
    }

    /* 超时：清 TX FIFO，强制回 RX；计数供日志判断下行链路质量。 */
    stat_tx_to++;
    Dbg_Mark(55);
    nrf_writereg(FLUSH_TX, NRF_NOP);
    nrf_enter_rx();
    return 0;
}

/* 控制包协议：帧头 11、10 字节数据、1 字节累加校验，共 12 字节。 */
static uint8_t nrf_unpack(const uint8_t *data)
{
    uint8_t i;
    uint8_t check = 0;

    if (data[0] != 11)
        return 0;
    for (i = 1; i < 11; i++)
        check += data[i];
    if (check != data[11])
        return 0;

    nrf_rocker[0] = (int16_t)((uint16_t)data[1] | ((uint16_t)data[2] << 8));
    nrf_rocker[1] = (int16_t)((uint16_t)data[3] | ((uint16_t)data[4] << 8));
    nrf_rocker[2] = (int16_t)((uint16_t)data[5] | ((uint16_t)data[6] << 8));
    nrf_rocker[3] = (int16_t)((uint16_t)data[7] | ((uint16_t)data[8] << 8));

    stat_rx++;
    Dbg_NoteRx();
    return 1;
}

void Nrf_Init(void)
{
    uint8_t retry;

    nrf_mode = NRF_MODE_INIT;

    GPIO_Init(NRF_CE_PORT, NRF_CE_PIN, GPIO_OUT_PP);
    GPIO_Init(NRF_CSN_PORT, NRF_CSN_PIN, GPIO_OUT_PP);
    GPIO_Init(NRF_MISO_PORT, NRF_MISO_PIN, GPIO_HighZ);
    GPIO_PinPullConfig(NRF_MISO_PORT, NRF_MISO_PIN, GPIO_NO_PULL);
    GPIO_Init(NRF_IRQ_PORT, NRF_IRQ_PIN, GPIO_HighZ);

    SPI_Init(SPI_2, 0, SPI_MSB, SPI_CPOL_Low, SPI_CPHA_1Edge,
             SPI_Speed_4, SPI_Mode_Master, 1);

    nrf_addr[4] = NRF_CHANNEL;
    nrf_apply_config();

    nrf_link_ok = 0;
    for (retry = 0; retry < 20; retry++)
    {
        if (nrf_link_check())
        {
            nrf_link_ok = 1;
            Ms_Delay(200); /* 与生成工程 remoteControlInitWithTimeout 一致 */
            break;
        }
        /* 模块可能晚上电：重新落配置后再检查。 */
        nrf_apply_config();
        Ms_Delay(10);
    }

    /* 链路检查会临时改写 TX_ADDR；这里恢复为通信地址，
       nrf_enter_tx() 每次发送前也会重写，不影响遥测。 */
    NRF_CE_LOW();
    nrf_writebuf(NRF_WRITE_REG + NRF_REG_TX_ADDR, nrf_addr, 5);
    NRF_CE_HIGH();

    stat_ch = nrf_readreg(NRF_REG_RF_CH);
    stat_rf = nrf_readreg(NRF_REG_RF_SETUP);
    stat_retr = nrf_readreg(NRF_REG_SETUP_RETR);
}

/*
 * 轮询：一次把 RX FIFO 读空（最多 3 包），并统计 STATUS 事件。
 * STATUS.RX_DR 是单标志，一次可能覆盖多包，因此 rx 可能大于 rx_dr；
 * 这不是计数器撕裂，而是 3 级 FIFO 的正常表现。
 */
void Nrf_Handler(void)
{
    uint8_t state;
    uint8_t fifo;
    uint8_t round;
    uint8_t drained = 0;

    Dbg_Mark(50);
    state = nrf_readreg(NRF_REG_STATUS);
    fifo = nrf_readreg(NRF_REG_FIFO_STATUS);
    Dbg_Mark(51);

    stat_st = state;
    stat_fifo = fifo;

    /* SPI 未响应时两个寄存器都会读成 0xFF，直接跳过，避免计数器乱跳。 */
    if (state == 0xFF && fifo == 0xFF)
    {
        stat_drain = 0;
        return;
    }

    /* 回写 STATUS 清掉本次观察到的 RX_DR/TX_DS/MAX_RT。 */
    nrf_writereg(NRF_WRITE_REG + NRF_REG_STATUS, state);

    if (state & NRF_RX_DR)
        stat_rx_dr++;

    if (!(fifo & NRF_RX_EMPTY))
    {
        for (round = 0; round < 3; round++)
        {
            NRF_CE_LOW();
            nrf_readbuf(RD_RX_PLOAD, nrf_rx_buff, NRF_RX_PAYLOAD);
            NRF_CE_HIGH();
            drained++;
            (void)nrf_unpack(nrf_rx_buff);
            if (nrf_readreg(NRF_REG_FIFO_STATUS) & NRF_RX_EMPTY)
                break;
        }
    }
    Dbg_Mark(52);

    stat_drain = drained;
    if (drained > stat_drain_max)
        stat_drain_max = drained;
    if (drained == 3 || (fifo & NRF_RX_FULL))
        nrf_events |= NRF_EVT_FIFO_FULL;
    Dbg_Mark(53);

    if (state & NRF_TX_DS)
    {
        stat_tx_ds++;
        nrf_writereg(FLUSH_TX, NRF_NOP);
        if (!nrf_force_tx && nrf_mode != NRF_MODE_RX)
            nrf_enter_rx();
    }

    if (state & NRF_MAX_RT)
    {
        stat_maxrt++;
        nrf_writereg(FLUSH_TX, NRF_NOP);
        if (!nrf_force_tx && nrf_mode != NRF_MODE_RX)
            nrf_enter_rx();
    }

    /*
     * 兜底：只要还停在 TX，连续 3 次 handler 都没等到 TX_DS/MAX_RT，
     * 就强制清 TX FIFO 回 RX（正常路径在 nrf_wait_tx_done 里已经回 RX，
     * 这里只防“射频模块不响应/被强制 TX”等异常，避免永久聋掉）。
     */
    if (nrf_mode == NRF_MODE_TX && !nrf_force_tx)
    {
        if (++tx_stall_rounds >= 3)
        {
            tx_stall_rounds = 0;
            stat_tx_stuck++;
            nrf_writereg(FLUSH_TX, NRF_NOP);
            nrf_enter_rx();
            nrf_events |= NRF_EVT_TX_STUCK;
        }
    }
    else
    {
        tx_stall_rounds = 0;
    }
}

/*
 * 十路 IO 状态回传：10 个 int16 小端值，5 次分频（首次立即发送）。
 * 与共享驱动 RemoteStatusSend 的帧格式一致，额外累计 tx 计数。
 */
void Nrf_SendTelemetry(int v0, int v1, int v2, int v3, int v4,
                       int v5, int v6, int v7, int v8, int v9)
{
    static uint8_t divider = 4;
    static uint8_t payload[NRF_TX_PAYLOAD];

    if (++divider < 5)
        return;
    divider = 0;

    /* 逐字节落帧：SDCC 对「数组 + 变址循环」取字节有误。 */
    payload[0] = (uint8_t)((uint16_t)v0 & 0xFF);
    payload[1] = (uint8_t)(((uint16_t)v0 >> 8) & 0xFF);
    payload[2] = (uint8_t)((uint16_t)v1 & 0xFF);
    payload[3] = (uint8_t)(((uint16_t)v1 >> 8) & 0xFF);
    payload[4] = (uint8_t)((uint16_t)v2 & 0xFF);
    payload[5] = (uint8_t)(((uint16_t)v2 >> 8) & 0xFF);
    payload[6] = (uint8_t)((uint16_t)v3 & 0xFF);
    payload[7] = (uint8_t)(((uint16_t)v3 >> 8) & 0xFF);
    payload[8] = (uint8_t)((uint16_t)v4 & 0xFF);
    payload[9] = (uint8_t)(((uint16_t)v4 >> 8) & 0xFF);
    payload[10] = (uint8_t)((uint16_t)v5 & 0xFF);
    payload[11] = (uint8_t)(((uint16_t)v5 >> 8) & 0xFF);
    payload[12] = (uint8_t)((uint16_t)v6 & 0xFF);
    payload[13] = (uint8_t)(((uint16_t)v6 >> 8) & 0xFF);
    payload[14] = (uint8_t)((uint16_t)v7 & 0xFF);
    payload[15] = (uint8_t)(((uint16_t)v7 >> 8) & 0xFF);
    payload[16] = (uint8_t)((uint16_t)v8 & 0xFF);
    payload[17] = (uint8_t)(((uint16_t)v8 >> 8) & 0xFF);
    payload[18] = (uint8_t)((uint16_t)v9 & 0xFF);
    payload[19] = (uint8_t)(((uint16_t)v9 >> 8) & 0xFF);

    nrf_send_payload(payload, NRF_TX_PAYLOAD);
    stat_tx++;

    /* 有界等待 TX_DS/MAX_RT（最多 NRF_TX_WAIT_MS），然后无论结果都回 RX；
       收包统计在随后的 handler 里完成。 */
    (void)nrf_wait_tx_done(NRF_TX_WAIT_MS);
    Nrf_Handler();
}

void Nrf_ForceRx(void)
{
    nrf_force_tx = 0;
    nrf_enter_rx();
}

void Nrf_ForceTx(void)
{
    nrf_force_tx = 1;
    nrf_enter_tx();
}

void Nrf_GetStats(NrfStats *out)
{
    out->rx = stat_rx;
    out->rx_dr = stat_rx_dr;
    out->tx = stat_tx;
    out->tx_ds = stat_tx_ds;
    out->maxrt = stat_maxrt;
    out->tx_to = stat_tx_to;
    out->tx_stuck = stat_tx_stuck;
    out->drain_max = stat_drain_max;
    out->drain = stat_drain;
    out->st = stat_st;
    out->fifo = stat_fifo;
    out->mode = (uint8_t)nrf_mode;
    out->ch = stat_ch;
    out->rf = stat_rf;
    out->retr = stat_retr;
    out->link = nrf_link_ok;
}

void Nrf_ResetCounters(void)
{
    stat_rx = 0;
    stat_rx_dr = 0;
    stat_tx = 0;
    stat_tx_ds = 0;
    stat_maxrt = 0;
    stat_tx_to = 0;
    stat_tx_stuck = 0;
    stat_drain_max = 0;
    stat_drain = 0;
    nrf_events = 0;
}

uint8_t Nrf_InitOk(void)
{
    return nrf_link_ok;
}

uint8_t Nrf_TakeEvents(void)
{
    uint8_t events = nrf_events;
    nrf_events = 0;
    return events;
}

int16_t Nrf_Rocker(uint8_t index)
{
    if (index > 3)
        return 0;
    return nrf_rocker[index];
}

uint8_t Nrf_ReadReg(uint8_t reg)
{
    return nrf_readreg(reg);
}

void Nrf_ReadBuf(uint8_t reg, uint8_t *buf, uint8_t len)
{
    nrf_readbuf(reg, buf, len);
}

/*
 * 同步 TX 探针（命令 t）：一次性把“能不能发出去”测清楚。
 * 与主循环的发送路径完全同序：CE 低 → 写 FIFO → CE 高，只是等待时间拉长到
 * 20 ms 并分三个时刻回读 STATUS，避免 8 ms 窗口把 MAX_RT 截断。
 */
void Nrf_TxProbe(NrfTxProbe *out)
{
    uint8_t i;

    out->cfg_enter = 0;
    out->fifo_write = 0;
    out->st_imm = 0;
    out->st_2ms = 0;
    out->st_20ms = 0;
    out->st_50ms = 0;
    out->fifo_after = 0;
    out->observe = 0;
    out->mode_after = 0;
    out->ce_fifo_before = 0;
    out->ce_p3_low = 0;
    out->ce_fifo_low = 0;
    out->ce_p3_high = 0;
    out->ce_fifo_high = 0;
    out->spi_check = 0;

    /* --- 第一步：CE 有效性测试（RX 模式）--- */
    nrf_enter_rx();
    nrf_writereg(NRF_WRITE_REG + NRF_REG_STATUS, 0x70);
    nrf_writereg(FLUSH_RX, NRF_NOP);
    out->ce_fifo_before = nrf_readreg(NRF_REG_FIFO_STATUS);

    NRF_CE_LOW();
    Ms_Delay(60);
    out->ce_p3_low = P3;
    out->ce_fifo_low = nrf_readreg(NRF_REG_FIFO_STATUS);

    NRF_CE_HIGH();
    Ms_Delay(60);
    out->ce_p3_high = P3;
    out->ce_fifo_high = nrf_readreg(NRF_REG_FIFO_STATUS);

    /* --- 第二步：TX 探针 --- */
    nrf_enter_tx();
    out->cfg_enter = nrf_readreg(NRF_REG_CONFIG);

    nrf_tx_buff[0] = (uint8_t)(NRF_TX_PAYLOAD + 1);
    for (i = 0; i < NRF_TX_PAYLOAD; i++)
        nrf_tx_buff[i + 1] = (uint8_t)(0xA0 + i);
    nrf_tx_buff[NRF_TX_PAYLOAD + 1] = 0x5A;

    NRF_CE_LOW();
    nrf_writebuf(WR_TX_PLOAD, nrf_tx_buff, (uint8_t)(NRF_TX_PAYLOAD + 2));
    out->fifo_write = nrf_readreg(NRF_REG_FIFO_STATUS);
    NRF_CE_HIGH();

    out->st_imm = nrf_readreg(NRF_REG_STATUS);
    Ms_Delay(2);
    out->st_2ms = nrf_readreg(NRF_REG_STATUS);
    Ms_Delay(18);
    out->st_20ms = nrf_readreg(NRF_REG_STATUS);
    Ms_Delay(30);
    out->st_50ms = nrf_readreg(NRF_REG_STATUS);
    out->fifo_after = nrf_readreg(NRF_REG_FIFO_STATUS);
    out->observe = nrf_readreg(NRF_REG_OBSERVE_TX);

    nrf_writereg(NRF_WRITE_REG + NRF_REG_STATUS, 0x70);
    nrf_writereg(FLUSH_TX, NRF_NOP);
    nrf_enter_rx();
    out->mode_after = (uint8_t)nrf_mode;
    out->spi_check = nrf_readreg(NRF_REG_RF_CH);
}

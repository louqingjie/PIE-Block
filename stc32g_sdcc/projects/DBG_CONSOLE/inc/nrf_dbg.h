/*
 * 本工程私有的 nRF24L01+ 驱动副本（带调试统计）。
 *
 * 与共享库 nrf24l01.c 的射频配置、控制包解包与 22 字节遥测帧完全一致；
 * 额外提供调试台所需的寄存器快照和计数。
 *
 * 诊断版（v2）修正：
 *   - 遥测发送改为“有界等待 TX_DS/MAX_RT 后立刻回 RX”，不再固定 3 ms；
 *     旧实现在重发未结束时看不到标志，主循环会一直停在 TX，车体随后
 *     收不到任何控制包（日志表现为 mode=TX、tx_ds=0、age 一路增长）。
 *   - 增加 TX 卡死兜底：连续 3 次 handler 仍停在 TX 就强制 FLUSH_TX + 回 RX，
 *     并置 TX_STUCK 事件。
 *   - 记录初始化链路检查结果，供启动自检打印。
 *
 * 有意差异：切回 RX 时不再 FLUSH_RX（只在初始化清一次），避免丢掉 TX
 * 期间已经进入 RX FIFO 的控制包，保证 drain/rx 观测不被驱动自身清除。
 */
#ifndef __NRF_DBG_H
#define __NRF_DBG_H

#include <stdint.h>

#define NRF_CHANNEL 29
#define NRF_RF_SETUP_V 0x27
#define NRF_SETUP_RETR_V 0x15
#define NRF_RX_PAYLOAD 12
#define NRF_TX_PAYLOAD 20

/* 遥测发送等待 TX_DS/MAX_RT 的上限（250 kbps + 5 次重发约 4 ms，留余量）。 */
#define NRF_TX_WAIT_MS 8

/* 事件位：nRF RX FIFO 满（读之前 RX_FULL 或一次读出 3 包）。 */
#define NRF_EVT_FIFO_FULL 0x01
/* 事件位：射频还停在 TX 被兜底强制拉回 RX。 */
#define NRF_EVT_TX_STUCK 0x02

/* 寄存器地址（供 d 命令打印）。 */
#define NRF_REG_CONFIG 0x00
#define NRF_REG_EN_AA 0x01
#define NRF_REG_EN_RXADDR 0x02
#define NRF_REG_SETUP_AW 0x03
#define NRF_REG_SETUP_RETR 0x04
#define NRF_REG_RF_CH 0x05
#define NRF_REG_RF_SETUP 0x06
#define NRF_REG_STATUS 0x07
#define NRF_REG_OBSERVE_TX 0x08
#define NRF_REG_RPD 0x09
#define NRF_REG_RX_ADDR_P0 0x0A
#define NRF_REG_TX_ADDR 0x10
#define NRF_REG_RX_PW_P0 0x11
#define NRF_REG_FIFO_STATUS 0x17

typedef enum
{
    NRF_MODE_INIT = 0,
    NRF_MODE_RX,
    NRF_MODE_TX,
} NrfMode;

typedef struct
{
    uint32_t rx;      /* 已读出的有效控制包总数 */
    uint32_t rx_dr;   /* 观察到 STATUS.RX_DR 的次数 */
    uint32_t tx;      /* 遥测发送尝试次数 */
    uint32_t tx_ds;   /* 遥测被 ACK 的次数 */
    uint32_t maxrt;   /* 遥测重发耗尽次数 */
    uint32_t tx_to;   /* 遥测等待 TX_DS/MAX_RT 超时次数（超时也会强制回 RX） */
    uint32_t tx_stuck;/* TX 卡死兜底触发次数 */
    uint16_t drain_max;
    uint8_t drain;    /* 最近一次 handler 从 RX FIFO 读出的包数 0..3 */
    uint8_t st;       /* STATUS 快照 */
    uint8_t fifo;     /* FIFO_STATUS 快照 */
    uint8_t mode;     /* NrfMode */
    uint8_t ch;       /* RF_CH */
    uint8_t rf;       /* RF_SETUP */
    uint8_t retr;     /* SETUP_RETR */
    uint8_t link;     /* Nrf_Init 链路检查结果：1=通过 */
} NrfStats;

void Nrf_Init(void);
void Nrf_Handler(void);
void Nrf_SendTelemetry(int v0, int v1, int v2, int v3, int v4,
                       int v5, int v6, int v7, int v8, int v9);
void Nrf_ForceRx(void);
void Nrf_ForceTx(void);
void Nrf_GetStats(NrfStats *out);
void Nrf_ResetCounters(void);
uint8_t Nrf_TakeEvents(void);
uint8_t Nrf_InitOk(void);
int16_t Nrf_Rocker(uint8_t index);
uint8_t Nrf_ReadReg(uint8_t reg);
void Nrf_ReadBuf(uint8_t reg, uint8_t *buf, uint8_t len);

#endif /* __NRF_DBG_H */

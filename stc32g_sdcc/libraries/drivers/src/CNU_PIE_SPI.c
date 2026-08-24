/*
 * COPYRIGHT NOTICE
 * Copyright (c) 2023, CNU_W.PIE. All rights reserved.
 * The copyright notice of the original library must be preserved when
 * modifying this file.
 *
 * @file CNU_PIE_SPI.c
 * @brief SPI driver
 */
#include "CNU_PIE_SPI.h"
#include "CNU_PIE_GPIO.h"

uint8_t SPI_RxTimerOut;
uint8_t SPI_BUF_type SPI_RxBuffer[SPI_BUF_LENTH];
__bit B_SPI_Busy;

void SPI_Init(SPI_ENUM SPI_CHN, uint8_t SS_CFG, uint8_t FirstBit,
              uint8_t cpol, uint8_t cpha, uint8_t Clock_Div,
              uint8_t SPI_Mode, uint8_t SPI_EN)
{
    uint8_t control;

    /*
     * P_SW1/SPCTL 不是传统 8051 可位寻址 SFR。Keil C251 能为
     * SPCTL^n 生成扩展位指令，但 SDCC 的普通 __sbit 会误落到 PSW
     * 0xD0~0xD7，甚至切换寄存器组。这里必须整字节访问。
     */
    P_SW1 = (uint8_t)((P_SW1 & (uint8_t)~0x0C) |
                      (((uint8_t)SPI_CHN & 0x03U) << 2));
    control = (uint8_t)(Clock_Div & 0x03U);
    if (!SS_CFG) control |= 0x80U;
    if (SPI_EN) control |= 0x40U;
    if (FirstBit) control |= 0x20U;
    if (SPI_Mode) control |= 0x10U;
    if (cpol) control |= 0x08U;
    if (cpha) control |= 0x04U;
    SPCTL = control;
    SPI_RxTimerOut = 0;
    B_SPI_Busy = 0;
}

void SPI_SetMode(uint8_t SPI_Mode)
{
    if (SPI_Mode == SPI_Mode_Slave)
    {
        SPCTL &= (uint8_t)~0x90U;
    }
    else
    {
        SPCTL |= 0x90U;
    }
}

void SPI_WriteByte(uint8_t dat)
{
    if (IE2 & 0x02U)
    {
        B_SPI_Busy = 1;
        SPDAT = dat;
        while (B_SPI_Busy)
            ;
    }
    else
    {
        uint8_t ignored;
        SPI_ReadWriteByte_Timeout(dat, SPI_TRANSFER_TIMEOUT, &ignored);
    }
}

uint8_t SPI_ReadByte(void)
{
    uint8_t value = 0xFF;
    SPI_ReadWriteByte_Timeout(0xFF, SPI_TRANSFER_TIMEOUT, &value);
    return value;
}

/*
 * 有限等待的全双工 SPI 传输。
 * 返回 1 表示 SPSTAT 完成位在期限内出现，返回 0 表示外设未响应。
 * RxData 可以为 NULL；失败时若提供了 RxData，则返回 0xFF。
 */
uint8_t SPI_ReadWriteByte_Timeout(uint8_t TxData, uint16_t timeout, uint8_t *RxData)
{
    SPDAT = TxData;
    while (!(SPSTAT & 0x80))
    {
        if (timeout == 0)
        {
            if (RxData != 0)
                *RxData = 0xFF;
            return 0;
        }
        timeout--;
    }
    SPSTAT = 0xC0;
    if (RxData != 0)
        *RxData = SPDAT;
    return 1;
}

uint8_t SPI_ReadWriteByte(uint8_t TxData)
{
    uint8_t RxData = 0xFF;
    /* 保留原 API；未接外设时返回 0xFF 而不是死循环。 */
    SPI_ReadWriteByte_Timeout(TxData, SPI_TRANSFER_TIMEOUT, &RxData);
    return RxData;
}

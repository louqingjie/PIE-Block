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
    switch (SPI_CHN)
    {
    case SPI_1: P_SW1 |= (0x00 << 2); break;
    case SPI_2: P_SW1 |= (0x01 << 2); break;
    case SPI_3: P_SW1 |= (0x02 << 2); break;
    case SPI_4: P_SW1 |= (0x03 << 2); break;
    }
    if (SS_CFG)
        SSIG = 0;
    else
        SSIG = 1;
    SPEN = SPI_EN;
    DORD = FirstBit;
    MSTR = SPI_Mode;
    CPOL = cpol;
    CPHA = cpha;
    SPCTL = (SPCTL & ~0x03) | Clock_Div;
    SPI_RxTimerOut = 0;
    B_SPI_Busy = 0;
}

void SPI_SetMode(uint8_t SPI_Mode)
{
    if (SPI_Mode == SPI_Mode_Slave)
    {
        MSTR = 0;
        SSIG = 0;
    }
    else
    {
        MSTR = 1;
        SSIG = 1;
    }
}

void SPI_WriteByte(uint8_t dat)
{
    if (ESPI)
    {
        B_SPI_Busy = 1;
        SPDAT = dat;
        while (B_SPI_Busy)
            ;
    }
    else
    {
        SPDAT = dat;
        while (SPIF == 0)
            ;
        SPIF = 1;
        WCOL = 1;
    }
}

uint8_t SPI_ReadByte(void)
{
    SPDAT = 0xFF;
    while (SPIF == 0)
        ;
    SPIF = 1;
    WCOL = 1;
    return SPDAT;
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

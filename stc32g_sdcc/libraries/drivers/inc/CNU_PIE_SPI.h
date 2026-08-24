/*********************************************************************************************************************
 *     COPYRIGHT NOTICE
 *     Copyright (c) 2023,CNU_W.PIE
 *     All rights reserved.
 *
 *     ��ע�������⣬�����������ݰ�Ȩ�������ָ������У�δ������������������ҵ��;��
 *     �޸�����ʱ���뱣��PP�İ�Ȩ������
 *     Except where indicated, the copyright of all the contents below is owned by PP 
 *     and can not be used for commercial purposes without permission. 
 *     The copyright notice of PP must be preserved when modifying the content.
 *
 * @file       CNU_PIE_SPI.h
 * @brief      SPI
 * @author     ����
 * @version    v1.0
 * @note       NULL
 * @date       2023-07-26
 ********************************************************************************************************************/
#ifndef __CNU_PIE_SPI_H_
#define __CNU_PIE_SPI_H_

#include "STC32Gxx.h"
#include "common.h"

#define	SPI_BUF_LENTH	64
#define	SPI_BUF_type	__xdata

// SPI chip-select and data pins are configured by CNU_PIE_SPI.c.

#define	SPI_Mode_Master		1
#define	SPI_Mode_Slave		0
#define	SPI_CPOL_High		1
#define	SPI_CPOL_Low		0
#define	SPI_CPHA_1Edge		0
#define	SPI_CPHA_2Edge		1
#define	SPI_Speed_4			0
#define	SPI_Speed_8			1
#define	SPI_Speed_16		2
#define	SPI_Speed_32		3
#define	SPI_Speed_2			3
#define	SPI_MSB				0
#define	SPI_LSB				1

typedef enum
{
	SPI_1 = 0x00,
	SPI_2,
	SPI_3,
	SPI_4,
}SPI_ENUM;

void SPI_Init(SPI_ENUM SPI_CHN , uint8_t SS_CFG , uint8_t FirstBit , uint8_t cpol , uint8_t cpha , uint8_t Clock_Div , uint8_t SPI_Mode , uint8_t SPI_EN);
void SPI_SetMode(uint8_t SPI_Mode);
void SPI_WriteByte(uint8_t dat);
uint8_t SPI_ReadByte(void);
uint8_t SPI_ReadWriteByte(uint8_t TxData);
#endif

/*********************************************************************************************************************
 * @file       iap_proto.c
 * @brief      pie-block 自升级串口协议 - CRC 实现
 *
 * 与 PC 侧 pie_block_iap.py 的 crc16() 必须逐位一致。
 ********************************************************************************************************************/

#include "iap_proto.h"

uint16_t iap_crc16_update(uint16_t crc, uint8_t *buf, uint16_t len)
{
	uint16_t i;
	uint8_t j;

	for (i = 0; i < len; i++)
	{
		crc ^= (uint16_t)buf[i];
		for (j = 0; j < 8; j++)
		{
			if (crc & 0x0001)
				crc = (uint16_t)((crc >> 1) ^ 0xA001);
			else
				crc = (uint16_t)(crc >> 1);
		}
	}
	return crc;
}

uint16_t iap_crc16(uint8_t *buf, uint16_t len)
{
	return iap_crc16_update(0xFFFF, buf, len);
}

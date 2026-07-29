/*********************************************************************************************************************
 * @file       iap_proto.h
 * @brief      pie-block 自升级串口协议 - 芯片侧定义
 *
 * 与 PC 侧 `stc32g/toolchain/stcflash/pie_block_iap.py` 必须逐字节一致。
 * 改动任何常量或 CRC 实现时，两侧同步改，并跑 pie_block_iap.py --selftest
 * 以及 scripts/test_iap_proto.gd 的交叉验证。
 ********************************************************************************************************************/

#ifndef __IAP_PROTO_H_
#define __IAP_PROTO_H_

#include "common.h"

/* ---------------------------------------------------------------- 帧格式

   AA 55 | ver | cmd | addr(3, 小端) | len(2, 小端) | payload... | crc16(2, 小端)

   crc16 覆盖 ver..payload 末字节，不含 AA 55 帧头。
   addr/len 用小端是为了 8051 侧能直接按字节取，不做移位。
*/

#define IAP_MAGIC0 0xAA
#define IAP_MAGIC1 0x55
#define IAP_PROTO_VER 0x01

/* 帧头(2) + ver(1) + cmd(1) + addr(3) + len(2) = 9，再加 crc(2) = 11 */
#define IAP_FRAME_OVERHEAD 11
#define IAP_HEADER_LEN 9

#define IAP_CMD_PING 0x01
#define IAP_CMD_ERASE 0x02
#define IAP_CMD_WRITE 0x03
#define IAP_CMD_VERIFY 0x04
#define IAP_CMD_RUN 0x05

#define IAP_RESP_ACK 0x80
#define IAP_RESP_NAK 0x81

/* 单帧 payload 上限。收帧缓冲区按这个尺寸开。 */
#define IAP_MAX_PAYLOAD 256

/* ---------------------------------------------------------------- 内存布局

   物理 0xFE0000 起是 IAP 可擦区，对应 IAP 线性地址 0。
   物理 0xFF0000 起是代码区，bootloader 常驻此处，IAP 地址 0x010000。

   注：上述映射关系由 Phase 0 探针实测确认后才可依赖。
*/

/* App 区在 IAP 线性地址空间的起点 */
#define IAP_APP_BASE 0x000000UL
/* App 区大小，与 stcgal 的 program_eeprom_split 上限一致（65024 = 127 扇区） */
#define IAP_APP_SIZE 0xFE00UL
/* 代码区在 IAP 线性地址空间的起点。bootloader 必须拒绝 >= 此值的地址。 */
#define IAP_CODE_BASE 0x010000UL

#define IAP_SECTOR_SIZE 512U

/* ---------------------------------------------------------------- API */

/* CRC-16/MODBUS。与 Python 侧 crc16() 同算法。
   逐位实现，不用查表：256 字节的表在 bootloader 里比这段循环更贵。
   参数名必须避开 data：它是 C251 的存储类关键字（同 idata/xdata/code），
   用作参数名会报 error C25 syntax error。 */
uint16_t iap_crc16(uint8_t *buf, uint16_t len);

/* 增量式 CRC，供分块校验整个 App 区时使用（一次读不完 64K）。
   初值必须传 0xFFFF。 */
uint16_t iap_crc16_update(uint16_t crc, uint8_t *buf, uint16_t len);

#endif

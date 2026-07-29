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
 *
 * 布局照 STC 官方《利用STC的IAP单片机开发自己的ISP程序-STC32G12K128系列》
 * 第 2 页的 flash 规划，不要自创。
 *
 * 前提：ISP 下载 bootloader 时必须把 EEPROM 设成 128K，且【设完要重新上电
 * 才生效】（官方文档标注"很重要，容易被忽略"）。否则 IAP 全部 CMD_FAIL。
 *
 * IAP 地址 = 物理地址 & 0x1FFFF（IAP_ADDRE 只取 bit16，寻址空间 17 位）：
 *
 *   物理 0xFE0000-0xFEFFFF = IAP 0x00000-0x0FFFF  低 64K，用户可任意使用
 *   物理 0xFF0000-0xFF0FFF = IAP 0x10000-0x10FFF  Bootloader 4K（拒绝写）
 *   物理 0xFF1000-0xFFFFFF = IAP 0x11000-0x1FFFF  App 代码区 60K
 *
 * 实测确认（IAP_PROBE 探针）：
 *   - 128K 模式下 IAP 能读写代码区
 *   - 代码仍能从 0xFF0000 正常执行
 *   - 0xFE0000 区【不能取指执行】，调用后芯片复位。所以 App 不放那里，
 *     而是放在同一代码区的偏移处 0xFF1000。
 *
 * App 跑在 0xFF1000 需要三件事配合（缺一不可）：
 *   1. bootloader 的 isr.asm 中断蹦床，把 0x0003/0x000B/... 转发到 +0x1000
 *   2. App 的 C251 编译器选项 INTVECTOR(0x1000)
 *   3. 上位机把 hex 里 0xFF0000-0xFF0002 的复位跳转搬到 0xFF1000-0xFF1002
 */

/* Bootloader 占用范围（IAP 地址），App 与下载协议都必须拒绝写这里 */
#define IAP_BOOT_BASE 0x10000UL
#define IAP_LDR_SIZE 0x1000UL
#define IAP_BOOT_END (IAP_BOOT_BASE + IAP_LDR_SIZE)

/* App 区在 IAP 地址空间的起点与大小 */
#define IAP_APP_BASE (IAP_BOOT_BASE + IAP_LDR_SIZE)
#define IAP_APP_SIZE (0x20000UL - IAP_APP_BASE)

/* 低 64K 块区，用户可任意使用（不可取指，只能存数据） */
#define IAP_EEPROM_BASE 0x000000UL

#define IAP_SECTOR_SIZE 512U

/* DFU 下载标志：放 XRAM 最后 4 字节，软复位不清零。
   App 侧写入 IAP_DFU_TAG 后软复位，bootloader 据此停在下载模式。
   与 bootloader 的 dfu.c / dfu.h 必须一致。 */
#define IAP_DFU_FLAG_ADDR 0x1FFCU
#define IAP_DFU_TAG 0x12abcd34UL

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

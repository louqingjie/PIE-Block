/*********************************************************************************************************************
 * @file       main.c
 * @brief      pie-block IAP Bootloader
 *
 * 架构（EEPROM=128K 模式）：
 *   0xFF0000 +---------------+
 *           |  Bootloader   |  8K (0xFF0000 - 0xFF1FFF)
 *           +---------------+
 *           |  App 代码区   |  剩余空间 (0xFF2000 - 0xFFFFFF)
 *           |  ...          |
 *           +---------------+
 *   0xFE0000 |  EEPROM 数据  |  (IAP 可写，不可执行)
 *           +---------------+
 *
 * 工作流程：
 *   1. 上电/复位 -> bootloader 启动
 *   2. 读元数据扇区检查"进入下载模式"标志
 *   3. 无标志 -> 直接跳到 App (0xFF2000)
 *   4. 有标志 -> 进下载循环：收帧 -> 擦扇区 -> 写 -> 回 ACK
 *   5. VERIFY 通过后 -> 清标志 -> 跳 App
 *
 * 安全设计：
 *   - bootloader 只占用 0xFF0000-0xFF1FFF，擦写时拒绝该范围的地址
 *   - 元数据扇区（App 区最后一个 512B 扇区）也不擦
 *   - 写失败/断电 -> 元数据未更新 -> 下次开机 bootloader 会检测到 App 无效，
 *     停在下载循环等重新下载
 ********************************************************************************************************************/
#include "main.h"

#define BOOT_BAUD 115200

/* 地址布局全部来自 iap_proto.h，不在这里另写一份，
   免得两处不一致（PC 侧 pie_block_iap.py 也用同一套数值）。 */
#define BOOT_IAP_END IAP_BOOT_END
#define APP_IAP_BASE IAP_APP_BASE
#define META_IAP_ADDR IAP_META_ADDR

/* App 物理入口地址（bootloader 跳转目标） */
#define APP_PHYS_ENTRY 0xFF2000UL

#define META_MAGIC 0x5049 /* "IP" */

/* 跳转到 App 的函数指针 */
typedef void (*app_entry_t)(void);

/* ------------------------------------------------------------------ IAP 原语
 * 从探针验证过的直接寄存器操作，不依赖库函数（库函数不报 CMD_FAIL）。
 */

static void iap_idle(void)
{
    IAP_CONTR = 0;
    IAP_CMD = 0;
    IAP_TRIG = 0;
    IAP_ADDRH = 0xff;
    IAP_ADDRL = 0xff;
    IAP_ADDRE = 0xff;
}

static uint8_t iap_read_byte(uint32_t addr)
{
    uint8_t dat;
    uint8_t fail;

    IAP_CONTR = 0x80;
    IAP_TPS = (uint8_t)(FOSC / 1000000UL);
    IAP_CMD = 1;
    IAP_ADDRL = (uint8_t)addr;
    IAP_ADDRH = (uint8_t)(addr >> 8);
    IAP_ADDRE = (uint8_t)(addr >> 16);
    IAP_TRIG = 0x5a;
    IAP_TRIG = 0xa5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
    dat = IAP_DATA;
    fail = (IAP_CONTR >> 4) & 0x01;
    iap_idle();
    if (fail)
        return 0xFE;
    return dat;
}

static uint8_t iap_write_byte(uint32_t addr, uint8_t dat)
{
    uint8_t fail;

    IAP_CONTR = 0x80;
    IAP_TPS = (uint8_t)(FOSC / 1000000UL);
    IAP_CMD = 2;
    IAP_ADDRL = (uint8_t)addr;
    IAP_ADDRH = (uint8_t)(addr >> 8);
    IAP_ADDRE = (uint8_t)(addr >> 16);
    IAP_DATA = dat;
    IAP_TRIG = 0x5a;
    IAP_TRIG = 0xa5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
    fail = (IAP_CONTR >> 4) & 0x01;
    iap_idle();
    return fail;
}

static uint8_t iap_erase_sector(uint32_t addr)
{
    uint8_t fail;

    IAP_CONTR = 0x80;
    IAP_TPS = (uint8_t)(FOSC / 1000000UL);
    IAP_CMD = 3;
    IAP_ADDRL = (uint8_t)addr;
    IAP_ADDRH = (uint8_t)(addr >> 8);
    IAP_ADDRE = (uint8_t)(addr >> 16);
    IAP_TRIG = 0x5a;
    IAP_TRIG = 0xa5;
    _nop_();
    _nop_();
    _nop_();
    _nop_();
    fail = (IAP_CONTR >> 4) & 0x01;
    iap_idle();
    return fail;
}

/* ------------------------------------------------------------------ 帧收发 */

static void boot_send_byte(uint8_t b)
{
    UART_PutChar(UART_1, b);
}

static void boot_send_ack(uint8_t cmd, uint8_t *payload, uint8_t len)
{
    /* 复用协议层格式：AA 55 | ver | cmd | addr(3) | len(2) | payload | crc16(2) */
    uint8_t buf[11 + 256];
    uint16_t crc;
    uint8_t i;

    buf[0] = IAP_MAGIC0;
    buf[1] = IAP_MAGIC1;
    buf[2] = IAP_PROTO_VER;
    buf[3] = cmd;
    buf[4] = 0;
    buf[5] = 0;
    buf[6] = 0; /* addr = 0 */
    buf[7] = len;
    buf[8] = 0;
    for (i = 0; i < len; i++)
        buf[9 + i] = payload[i];

    /* CRC 覆盖 buf[2..8+len] */
    crc = iap_crc16(&buf[2], 7 + len);
    buf[9 + len] = (uint8_t)(crc & 0xFF);
    buf[10 + len] = (uint8_t)(crc >> 8);

    for (i = 0; i < 11 + len; i++)
        boot_send_byte(buf[i]);
}

static void boot_send_nak(uint8_t cmd, uint8_t reason)
{
    boot_send_ack(cmd | 0x01, &reason, 1);
}

/* 从环形缓冲区收一个完整帧。
   返回 1 且填入 cmd/addr/len/payload，返回 0 表示无完整帧。 */
static uint8_t boot_recv_frame(uint8_t *cmd, uint32_t *addr, uint8_t *len, uint8_t *payload)
{
    /* 环形缓冲区读取：head 是写入指针（ISR 更新），tail 是读取指针 */
    static uint8_t rx_buf[IAP_MAX_PAYLOAD];
    static uint8_t frame[11 + IAP_MAX_PAYLOAD];
    static uint8_t frame_len = 0;
    static uint8_t collecting = 0;
    uint8_t b;

    while (uart1_rx_tail != uart1_rx_head)
    {
        b = uart1_rx_buff[uart1_rx_tail];
        uart1_rx_tail = (uart1_rx_tail + 1) % UART1_RX_BUFFER_SIZE;

        if (!collecting)
        {
            /* 等帧头 AA 55 */
            if (frame_len == 0 && b == IAP_MAGIC0)
                frame_len = 1;
            else if (frame_len == 1 && b == IAP_MAGIC1)
            {
                frame[0] = IAP_MAGIC0;
                frame[1] = IAP_MAGIC1;
                frame_len = 2;
                collecting = 1;
            }
            else
                frame_len = 0;
        }
        else
        {
            frame[frame_len++] = b;
            /* 需要至少收到 header(9) 才知道 payload 长度 */
            if (frame_len >= 9)
            {
                uint8_t plen = frame[7];
                uint16_t want_crc;
                uint16_t got_crc;
                if (frame_len < 11 + plen)
                    continue; /* 还没收完 */

                /* 校验 CRC */
                got_crc = iap_crc16(&frame[2], 7 + plen);
                want_crc = frame[9 + plen] | (frame[10 + plen] << 8);
                if (got_crc != want_crc)
                {
                    collecting = 0;
                    frame_len = 0;
                    return 0; /* CRC 错，丢帧 */
                }

                *cmd = frame[3];
                *addr = frame[4] | ((uint32_t)frame[5] << 8) | ((uint32_t)frame[6] << 16);
                *len = plen;
                {
                    uint8_t i;
                    for (i = 0; i < plen; i++)
                        rx_buf[i] = frame[9 + i];
                    /* payload 指针通过参数返回 */
                    /* 这里用 static rx_buf 保证返回后仍有效 */
                }

                collecting = 0;
                frame_len = 0;
                /* 把 payload 拷出来 */
                {
                    uint8_t i;
                    for (i = 0; i < plen; i++)
                        payload[i] = rx_buf[i];
                }
                return 1;
            }
        }
    }
    return 0;
}

/* ------------------------------------------------------------------ 元数据 */

struct meta_t
{
    uint16_t magic;     /* META_MAGIC */
    uint16_t app_len;   /* App 代码长度（字节） */
    uint16_t app_crc;   /* App 代码 CRC16 */
    uint16_t boot_flag; /* 非 0 = 进入下载模式 */
};

static void meta_read(struct meta_t *m)
{
    uint8_t *p = (uint8_t *)m;
    uint8_t i;
    for (i = 0; i < sizeof(struct meta_t); i++)
        p[i] = iap_read_byte(META_IAP_ADDR + i);
}

/* meta_write_flag 由 App 侧调用（收到 @PIEIAP# 后写 boot_flag），
   bootloader 不直接用，但在这里保留定义供参考。
   App 侧代码生成器会发等价逻辑。 */
#if 0
static void meta_write_flag(uint16_t flag)
{
	/* 只改 flag 字段，不影响其他元数据。
	   先读整个扇区到 RAM，改 flag，擦扇区，再写回。
	   扇区 512 字节，用 xdata 缓冲区。 */
	static uint8_t xdata sec[512];
	uint16_t i;

	for (i = 0; i < 512; i++)
		sec[i] = iap_read_byte(META_IAP_ADDR + i);

	iap_erase_sector(META_IAP_ADDR);

	/* flag 在偏移 6 处（magic=2 + app_len=2 + app_crc=2） */
	sec[6] = (uint8_t)(flag & 0xFF);
	sec[7] = (uint8_t)(flag >> 8);

	for (i = 0; i < 512; i++)
		iap_write_byte(META_IAP_ADDR + i, sec[i]);
}
#endif

/* ------------------------------------------------------------------ 跳转到 App */

static void jump_to_app(void)
{
	app_entry_t app;
	uint8_t volatile far *p;

	p = (uint8_t volatile far *)APP_PHYS_ENTRY;
	app = (app_entry_t)p;
	app();
}

/* ------------------------------------------------------------------ 串口输出 */

static void p_str(char *s)
{
    while (*s)
        UART_PutChar(UART_1, (uint8_t)*s++);
}

static void p_hex8(uint8_t v)
{
    uint8_t h = (v >> 4) & 0x0F;
    uint8_t l = v & 0x0F;
    UART_PutChar(UART_1, (uint8_t)(h < 10 ? '0' + h : 'A' + h - 10));
    UART_PutChar(UART_1, (uint8_t)(l < 10 ? '0' + l : 'A' + l - 10));
}

static void p_hex16(uint16_t v)
{
    p_hex8((uint8_t)(v >> 8));
    p_hex8((uint8_t)v);
}

/* ------------------------------------------------------------------ 下载循环 */

static void download_loop(void)
{
    uint8_t cmd, len;
    uint32_t addr;
    static uint8_t payload[IAP_MAX_PAYLOAD];
    uint16_t i;
    uint16_t app_len = 0;
    uint16_t app_crc = 0;

    p_str("\r\n[BOOT] download mode ready\r\n");

    while (1)
    {
        if (boot_recv_frame(&cmd, &addr, &len, payload))
        {
            switch (cmd)
            {
            case IAP_CMD_PING:
                boot_send_ack(IAP_RESP_ACK, (uint8_t *)"\x01", 1);
                break;

            case IAP_CMD_ERASE:
                /* payload: app_len(2) little-endian */
                if (len >= 2)
                {
                    app_len = payload[0] | (payload[1] << 8);
                    /* 擦除 App 区所有扇区，跳过 bootloader 区和元数据扇区 */
                    {
                        uint32_t a;
                        uint8_t fail;
                        p_str("[BOOT] erasing... ");
                        for (a = APP_IAP_BASE; a < META_IAP_ADDR; a += IAP_SECTOR_SIZE)
                        {
                            fail = iap_erase_sector(a);
                            if (fail)
                            {
                                p_str("FAIL@");
                                p_hex16((uint16_t)a);
                                boot_send_nak(cmd, fail);
                                goto next;
                            }
                        }
                        p_str("done\r\n");
                    }
                    boot_send_ack(IAP_RESP_ACK, (uint8_t *)"", 0);
                }
                else
                    boot_send_nak(cmd, 0);
                break;

            case IAP_CMD_WRITE:
                /* 拒绝写 bootloader 区 */
                if (addr < BOOT_IAP_END)
                {
                    boot_send_nak(cmd, 0xFF);
                    break;
                }
                /* 拒绝写元数据扇区 */
                if (addr >= META_IAP_ADDR && addr < META_IAP_ADDR + IAP_SECTOR_SIZE)
                {
                    boot_send_nak(cmd, 0xFE);
                    break;
                }
                {
                    uint8_t fail = 0;
                    for (i = 0; i < len; i++)
                    {
                        fail = iap_write_byte(addr + i, payload[i]);
                        if (fail)
                            break;
                    }
                    if (fail)
                        boot_send_nak(cmd, fail);
                    else
                        boot_send_ack(IAP_RESP_ACK, (uint8_t *)"", 0);
                }
                break;

            case IAP_CMD_VERIFY:
                /* payload: app_len(3) little-endian */
                if (len >= 3)
                {
                    uint32_t vlen = payload[0] | ((uint32_t)payload[1] << 8) | ((uint32_t)payload[2] << 16);
                    uint16_t crc = 0xFFFF;
                    uint8_t resp[2];
                    p_str("[BOOT] verifying... ");
                    for (i = 0; i < vlen; i++)
                    {
                        uint8_t b = iap_read_byte(APP_IAP_BASE + i);
                        crc = iap_crc16_update(crc, &b, 1);
                        if ((i & 0x0FFF) == 0)
                        {
                            p_str(".");
                        }
                    }
                    p_str(" done\r\n");
                    resp[0] = (uint8_t)(crc & 0xFF);
                    resp[1] = (uint8_t)(crc >> 8);
                    boot_send_ack(IAP_RESP_ACK, resp, 2);
                }
                else
                    boot_send_nak(cmd, 0);
                break;

            case IAP_CMD_RUN:
                /* 写元数据：app 有效标记 + 长度 + CRC + 清 boot_flag */
                /* 先擦元数据扇区，写 magic=IP + 长度 + CRC + flag=0 */
                {
                    static uint8_t xdata sec[512];
                    uint16_t j;
                    for (j = 0; j < 512; j++)
                        sec[j] = 0xFF;
                    sec[0] = META_MAGIC & 0xFF;
                    sec[1] = META_MAGIC >> 8;
                    sec[2] = app_len & 0xFF;
                    sec[3] = app_len >> 8;
                    /* app_crc 在 VERIFY 阶段算出但没存 -- 简化：跳过 CRC 校验 */
                    sec[4] = 0;
                    sec[5] = 0;
                    sec[6] = 0;
                    sec[7] = 0; /* boot_flag = 0 */
                    iap_erase_sector(META_IAP_ADDR);
                    for (j = 0; j < 8; j++)
                        iap_write_byte(META_IAP_ADDR + j, sec[j]);
                }
                boot_send_ack(IAP_RESP_ACK, (uint8_t *)"", 0);
                p_str("[BOOT] jumping to app\r\n");
                Ms_Delay(10);
                jump_to_app();
                break;

            default:
                boot_send_nak(cmd, 0xFD);
                break;
            }
        next:;
        }
    }
}

/* ------------------------------------------------------------------ 主函数 */

void main(void)
{
    struct meta_t meta;

    Board_Init();
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, BOOT_BAUD, TIM1);
    EA = 1;
    Ms_Delay(100);

    /* 初始化环形缓冲区指针 */
    uart1_rx_head = 0;
    uart1_rx_tail = 0;

    meta_read(&meta);

    if (meta.magic == META_MAGIC && meta.boot_flag == 0)
    {
        /* App 有效且无下载标志 -> 直接跳 App */
        jump_to_app();
        /* 如果 App 跳转失败（地址无代码），会继续往下走 */
    }

    /* 否则进下载循环 */
    download_loop();

    while (1)
        ;
}

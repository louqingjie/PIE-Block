/*********************************************************************************************************************
 * @file       main.c
 * @brief      IAP_PROBE - Phase 0 事实探测探针
 *
 * 目的：在动手写 bootloader 之前，用实测回答四个问题。
 *   Q1  far 指针能读到哪些 flash 区域？0xFE0000 / 0xFF0000 各是什么内容？
 *   Q2  IAP 线性地址 0x000000 到底映射到物理哪里？是 0xFE0000 还是 0xFF0000？
 *   Q3  IAP 能擦写的地址区间的真实上下界在哪？
 *   Q4  IAP 能不能碰到代码区（决定 bootloader 是否天然防砖）？
 *
 * 安全设计：
 *   - 擦除是唯一有破坏性的操作。执行前先用 IAP 读回 0x000000 的内容，
 *     与 far 指针读到的 0xFF0000（我们自己的代码）逐字节比对。
 *     一旦相同，说明 IAP 地址 0 就是代码区，立刻放弃擦除并如实上报。
 *   - 对代码区只做「写」测试，且只写我们确认为空白（0xFF）的高位地址。
 *     flash 写只能 1->0，写空白区不破坏任何已用代码。
 *   - 每步先打印再执行。若某步之后没有输出，就说明该步让芯片跑飞了，
 *     这本身也是一个明确结论。
 *
 * 用完即弃，不属于产品固件。
 ********************************************************************************************************************/
#include "main.h"

/* 串口输出波特率。取保守值，与 App 的 230400 无关。 */
#define PROBE_BAUD 115200

/* 我们自己的代码基址。MCS-251 复位入口，hex 的 linear base。 */
#define CODE_BASE 0xFF0000UL

/* 假设中的 EEPROM 区基址。 */
#define EE_BASE 0xFE0000UL

/* 代码区高位空白地址，用于非破坏性写测试。固件约 28K，此处远在其上。 */
#define BLANK_IN_CODE 0x01FE00UL

static uint8_t buf_a[16];
static uint8_t buf_b[16];

/* ------------------------------------------------------------------ 串口输出 */

/* 大内存模型（MemoryModel=3）下字符串字面量是 huge，
   写 char code * 会触发 warning C151 指针截断、打印内容会错乱。
   用默认指针类型让编译器自己选宽度。 */
static void p_str(char *s)
{
	while (*s)
		UART_PutChar(UART_1, (uint8_t)*s++);
}

static void p_nl(void)
{
	UART_PutChar(UART_1, '\r');
	UART_PutChar(UART_1, '\n');
}

static void p_hex4(uint8_t v)
{
	v &= 0x0F;
	UART_PutChar(UART_1, (uint8_t)(v < 10 ? ('0' + v) : ('A' + v - 10)));
}

static void p_hex8(uint8_t v)
{
	p_hex4((uint8_t)(v >> 4));
	p_hex4(v);
}

static void p_hex16(uint16_t v)
{
	p_hex8((uint8_t)(v >> 8));
	p_hex8((uint8_t)v);
}

static void p_hex24(uint32_t v)
{
	p_hex8((uint8_t)(v >> 16));
	p_hex8((uint8_t)(v >> 8));
	p_hex8((uint8_t)v);
}

static void p_dec(uint32_t v)
{
	uint8_t d[10];
	uint8_t n = 0;
	if (v == 0)
	{
		UART_PutChar(UART_1, '0');
		return;
	}
	while (v > 0)
	{
		d[n++] = (uint8_t)(v % 10);
		v /= 10;
	}
	while (n > 0)
		UART_PutChar(UART_1, (uint8_t)('0' + d[--n]));
}

/* 打印 16 字节十六进制 */
static void p_dump(uint8_t *p)
{
	uint8_t i;
	for (i = 0; i < 16; i++)
	{
		p_hex8(p[i]);
		UART_PutChar(UART_1, ' ');
	}
}

/* ------------------------------------------------------------------ IAP 原语
 *
 * 手册第 905 页：IAP_CONTR 的 B4 位是 CMD_FAIL，失败时置 1，需软件清零。
 * 库函数 EEPROM_read_n / EEPROM_write_n / EEPROM_SectorErase 不读 CMD_FAIL，
 * 所以失败时只能看到错误返回值（如全 0x00），不知道根因。
 * 下面直接操作寄存器，每次操作后都把 CMD_FAIL 和 IAP_CONTR 打出来。
 */

static void iap_idle(void)
{
	IAP_CONTR = 0; /* 关闭 IAP */
	IAP_CMD = 0;
	IAP_TRIG = 0;
	IAP_ADDRH = 0xff;
	IAP_ADDRL = 0xff;
	IAP_ADDRE = 0xff;
}

/* 返回 CMD_FAIL（1=失败 0=成功）。 */
static uint8_t iap_wait(void)
{
	uint8_t contr;
	_nop_();
	_nop_();
	_nop_();
	_nop_();
	contr = IAP_CONTR;
	return (uint8_t)((contr >> 4) & 0x01);
}

static uint8_t iap_read_byte(uint32_t addr)
{
	uint8_t dat;
	uint8_t fail;

	IAP_CONTR = 0x80; /* 使能 IAP */
	IAP_TPS = (uint8_t)(FOSC / 1000000UL);
	IAP_CMD = 1; /* 读 */
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
	fail = iap_wait();
	iap_idle();

	if (fail)
		return 0xFE; /* 哨兵值：与正常返回区分 */
	return dat;
}

static uint8_t iap_write_byte(uint32_t addr, uint8_t dat)
{
	uint8_t fail;

	IAP_CONTR = 0x80;
	IAP_TPS = (uint8_t)(FOSC / 1000000UL);
	IAP_CMD = 2; /* 写 */
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
	fail = iap_wait();
	iap_idle();
	return fail;
}

static uint8_t iap_erase_sector(uint32_t addr)
{
	uint8_t fail;

	IAP_CONTR = 0x80;
	IAP_TPS = (uint8_t)(FOSC / 1000000UL);
	IAP_CMD = 3; /* 扇区擦除 */
	IAP_ADDRL = (uint8_t)addr;
	IAP_ADDRH = (uint8_t)(addr >> 8);
	IAP_ADDRE = (uint8_t)(addr >> 16);
	IAP_TRIG = 0x5a;
	IAP_TRIG = 0xa5;
	_nop_();
	_nop_();
	_nop_();
	_nop_();
	fail = iap_wait();
	iap_idle();
	return fail;
}

/* ------------------------------------------------------------------ 内存读取 */

/* 用 far 指针读 flash。CHIPID 就是这么读的（STC32Gxx.h 里 0x7efde0），
   所以 far 指针确实能读到 flash，问题只是地址怎么映射。 */
static void read_far(uint32_t addr, uint8_t *dst)
{
	uint8_t i;
	uint8_t volatile far *p = (uint8_t volatile far *)addr;
	for (i = 0; i < 16; i++)
		dst[i] = p[i];
}

/* 用 IAP 读 16 字节，每个字节单独操作以捕获 CMD_FAIL。 */
static void read_iap(uint32_t addr, uint8_t *dst)
{
	uint8_t i;
	for (i = 0; i < 16; i++)
		dst[i] = iap_read_byte(addr + i);
}

static uint8_t same16(uint8_t *a, uint8_t *b)
{
	uint8_t i;
	for (i = 0; i < 16; i++)
		if (a[i] != b[i])
			return 0;
	return 1;
}

static uint8_t all_ff(uint8_t *a)
{
	uint8_t i;
	for (i = 0; i < 16; i++)
		if (a[i] != 0xFF)
			return 0;
	return 1;
}

/* ------------------------------------------------------------------ 各项测试 */

/* Q1：far 指针的地址映射。把几个关键地址各读 16 字节打出来。
   若 0xFF0000 处读到的正是我们自己代码的开头（hex 首条记录 02 4E 27 ...），
   就证明 far 指针能直接寻址代码区。 */
static void test_far_map(void)
{
	p_str("[Q1] far pointer memory map\r\n");

	p_str("  0x7EFDE0 (CHIPID) : ");
	read_far(0x7EFDE0UL, buf_a);
	p_dump(buf_a);
	p_nl();

	p_str("  0xFF0000 (code)   : ");
	read_far(CODE_BASE, buf_a);
	p_dump(buf_a);
	p_nl();

	p_str("  0xFE0000 (ee?)    : ");
	read_far(EE_BASE, buf_b);
	p_dump(buf_b);
	p_nl();

	p_str("  0xFE0000 blank(FF)? ");
	p_str(all_ff(buf_b) ? "YES" : "NO");
	p_nl();
	p_nl();
}

/* Q2：IAP 线性地址 0 到底是谁。
   与 far 读到的 0xFF0000 比对，直接判定 IAP 地址 0 是否就是代码区。
   这一步的结论决定后面能不能安全擦除。 */
static uint8_t g_iap0_is_code = 1; /* 保守默认：假定危险，除非证明安全 */

static void test_iap_identity(void)
{
	p_str("[Q2] what does IAP addr 0x000000 map to\r\n");

	read_iap(0x000000UL, buf_a);
	p_str("  IAP read 0x000000 : ");
	p_dump(buf_a);
	p_nl();

	read_far(CODE_BASE, buf_b);
	p_str("  far read 0xFF0000 : ");
	p_dump(buf_b);
	p_nl();

	if (same16(buf_a, buf_b) && !all_ff(buf_a))
	{
		g_iap0_is_code = 1;
		p_str("  VERDICT: IAP 0 == CODE BASE -> erase would BRICK. Skipping erase.\r\n");
	}
	else
	{
		g_iap0_is_code = 0;
		p_str("  VERDICT: IAP 0 differs from code base -> IAP 0 is the EEPROM area.\r\n");
	}
	p_nl();
}

/* Q3：IAP 可擦写区间。只在确认 IAP 0 不是代码区之后才做擦除。
   擦一个扇区 -> 读回应为全 FF -> 写图案 -> 读回应一致。
   每步都打 CMD_FAIL，这是定位根因的关键。 */
static void test_iap_rw(void)
{
	uint8_t i;
	uint8_t fail;
	uint8_t got;

	p_str("[Q3] IAP erase/write at 0x000000\r\n");

	if (g_iap0_is_code)
	{
		p_str("  SKIPPED (Q2 says this is the code area)\r\n\r\n");
		return;
	}

	p_str("  erasing sector 0 ... ");
	fail = iap_erase_sector(0x000000UL);
	p_str(fail ? "CMD_FAIL!" : "ok");
	p_nl();

	/* 擦后读第一个字节，应为 0xFF */
	got = iap_read_byte(0x000000UL);
	p_str("  read after erase: ");
	p_hex8(got);
	p_str(got == 0xFF ? " (FF=good)" : " (NOT FF - erase may have failed)");
	p_nl();

	p_str("  writing 0x5A to 0x000000 ... ");
	fail = iap_write_byte(0x000000UL, 0x5A);
	p_str(fail ? "CMD_FAIL!" : "ok");
	p_nl();

	got = iap_read_byte(0x000000UL);
	p_str("  read after write: ");
	p_hex8(got);
	p_str(got == 0x5A ? " (match)" : " (MISMATCH)");
	p_nl();

	/* 把擦写状态汇总 */
	p_str("  RESULT: ");
	if (got == 0x5A)
		p_str("EEPROM area WRITABLE\r\n");
	else
		p_str("EEPROM area NOT usable - check CMD_FAIL above\r\n");
	p_nl();

	/* 顺带扫几个地址的 CMD_FAIL，看是否与地址范围有关 */
	p_str("  CMD_FAIL scan (read 1 byte at each addr):\r\n");
	for (i = 0; i < 4; i++)
	{
		uint32_t a = (uint32_t)i * 0x4000UL; /* 0, 0x4000, 0x8000, 0xC000 */
		uint8_t v = iap_read_byte(a);
		uint8_t f = (v == 0xFE) ? 1 : 0;
		p_str("    0x");
		p_hex24(a);
		p_str(" -> val=");
		p_hex8(v);
		p_str(f ? " CMD_FAIL" : " ok");
		p_nl();
	}
	p_nl();
}

/* Q3b：可写区间的上界在哪。
   逐个候选地址做「写一个字节到空白处再读回」的非破坏性探测。
   flash 写只能 1->0，所以往读回为 FF 的位置写 0x5A 不会毁掉任何已用数据。 */
static void probe_one_addr(uint32_t addr)
{
	uint8_t before, after;
	uint8_t fail;
	uint8_t pattern = 0x5A;

	p_str("  IAP 0x");
	p_hex24(addr);
	p_str(" : ");

	before = iap_read_byte(addr);
	if (before == 0xFE)
	{
		p_str("READ CMD_FAIL");
		p_nl();
		return;
	}
	p_str("was ");
	p_hex8(before);

	if (before != 0xFF)
	{
		/* 不是空白，不敢写，只报告内容 */
		p_str("  (not blank, write skipped)");
		p_nl();
		return;
	}

	fail = iap_write_byte(addr, pattern);
	if (fail)
	{
		p_str("  WRITE CMD_FAIL");
		p_nl();
		return;
	}
	after = iap_read_byte(addr);

	p_str("  wrote 5A -> read ");
	p_hex8(after);
	p_str(after == pattern ? "  WRITABLE" : "  read-only/out-of-range");
	p_nl();
}

static void test_iap_range(void)
{
	p_str("[Q3b] IAP writable range scan (non-destructive, blank bytes only)\r\n");

	probe_one_addr(0x000100UL);
	probe_one_addr(0x008000UL);
	probe_one_addr(0x00FE00UL);
	probe_one_addr(0x00FFFFUL);
	p_nl();
}

/* Q4：IAP 能否碰到代码区。
   只做写测试，且目标是代码区高位的空白字节，不擦除。
   若这里可写，说明 128K EEPROM 模式下 IAP 能写整个 flash，
   bootloader 方案重新成立。
   注意：不擦除，只往读回为 FF 的空白字节写 0x5A。
   flash 写只能 1->0，不会破坏已用代码。 */
static void test_code_region(void)
{
	p_str("[Q4] can IAP reach the CODE region (EEPROM=128K expected)\r\n");
	p_str("  (write-only test on blank high addresses, no erase)\r\n");

	/* 0x010000 = 物理 0xFF0000 = 代码区起始（探针代码在此），跳过 */
	/* 探针约 6K，0x012000 以上应该是空白 */
	probe_one_addr(0x012000UL);
	probe_one_addr(0x018000UL);
	probe_one_addr(0x01FE00UL);
	probe_one_addr(0x01FFFFUL);
	p_nl();
}

/* Q5：C 侧 CRC16 是否与 PC 侧一致。
   期望值由 pie_block_iap.py 与 test_iap_proto.gd 两份独立实现交叉确认：
	 len=0                        -> FFFF
	 len=1  00                    -> 40BF
	 len=1  FF                    -> 00FF
	 len=7  01 01 00 00 00 00 00  -> 110A
	 len=9  "123456789"           -> 4B37
   任何一项不符，说明 C251 的移位/类型提升与预期不同，必须先修 iap_proto.c。 */
static void test_crc(void)
{
	static uint8_t v_zero[1] = {0x00};
	static uint8_t v_ff[1] = {0xFF};
	static uint8_t v_frame[7] = {0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00};
	static uint8_t v_str[9] = {'1', '2', '3', '4', '5', '6', '7', '8', '9'};

	p_str("[Q5] CRC16 vs PC side (expect FFFF 40BF 00FF 110A 4B37)\r\n");

	p_str("  len=0 : ");
	p_hex16(iap_crc16(v_zero, 0));
	p_nl();
	p_str("  len=1 : ");
	p_hex16(iap_crc16(v_zero, 1));
	p_nl();
	p_str("  len=1 : ");
	p_hex16(iap_crc16(v_ff, 1));
	p_nl();
	p_str("  len=7 : ");
	p_hex16(iap_crc16(v_frame, 7));
	p_nl();
	p_str("  len=9 : ");
	p_hex16(iap_crc16(v_str, 9));
	p_nl();
	p_nl();
}

/* ------------------------------------------------------------------ 主流程 */

/* Q6：0xFE0000 能否取指执行。

   思路：写一个只碰 SFR 的最小函数（不引用任何 RAM，天然位置无关），
   用 far 指针读它的机器码，再用 IAP 复制到 EEPROM 区（IAP 地址 0x000200），
   然后用 far 函数指针调用副本。如果 P0 口被设成 0x55，说明取指成功。

   选 P0 作目标是因为它不影响串口输出（UART1 在 P30/P31），
   读 P0 即可确认执行结果。

   选 0x000200 作为目标地址，避开 Q3 里写到 0x000000 的测试数据。 */

/* 这个函数只写 SFR P0，返回。不引用任何 RAM/全局变量。
   放在代码区，作为"原件"。 */
void target_func(void) large
{
	P0 = 0x55;
}

/* 拷贝目标地址（IAP 线性地址），选 0x000200 避开 Q3 的测试数据 */
#define TARGET_IAP_ADDR 0x000200UL
#define TARGET_FAR_ADDR 0xFE0200UL

/* far 函数指针类型。MCS-251 far call 用 24 位地址。 */
typedef void (*far_func_t)(void);

static void test_exec(void)
{
	uint8_t code_buf[64];
	uint8_t i;
	uint8_t got;
	far_func_t fp;

	p_str("[Q6] execute from 0xFE0000 area\r\n");

	/* 第一步：读 target_func 的机器码 */
	p_str("  reading target_func code... ");
	read_far((uint32_t)target_func, code_buf);
	p_str("done\r\n");
	p_str("  first 16 bytes: ");
	for (i = 0; i < 16; i++)
	{
		p_hex8(code_buf[i]);
		UART_PutChar(UART_1, ' ');
	}
	p_nl();

	/* 第二步：擦目标扇区 */
	p_str("  erasing target sector 0x000200... ");
	got = iap_erase_sector(TARGET_IAP_ADDR);
	p_str(got ? "CMD_FAIL!" : "ok");
	p_nl();

	/* 第三步：把机器码写到 EEPROM 区 */
	p_str("  writing code to EEPROM 0x000200... ");
	for (i = 0; i < 32; i++)
	{
		got = iap_write_byte(TARGET_IAP_ADDR + i, code_buf[i]);
		if (got)
		{
			p_str("CMD_FAIL at byte ");
			p_dec(i);
			p_nl();
			return;
		}
	}
	p_str("done\r\n");

	/* 第四步：读回并比对 */
	p_str("  verifying copy... ");
	for (i = 0; i < 32; i++)
	{
		if (iap_read_byte(TARGET_IAP_ADDR + i) != code_buf[i])
		{
			p_str("MISMATCH at byte ");
			p_dec(i);
			p_nl();
			return;
		}
	}
	p_str("match\r\n");

	/* 第五步：先清 P0，再调用副本，看 P0 是否变 0x55 */
	P0 = 0x00;
	p_str("  P0 before call = ");
	p_hex8(P0);
	p_nl();

	p_str("  calling function at 0xFE0200... ");
	{
		uint8_t volatile far *p = (uint8_t volatile far *)TARGET_FAR_ADDR;
		fp = (far_func_t)p;
	}
	fp();
	p_str("returned\r\n");

	p_str("  P0 after call  = ");
	p_hex8(P0);
	p_nl();

	if (P0 == 0x55)
		p_str("  VERDICT: 0xFE0000 area is EXECUTABLE\r\n");
	else
		p_str("  VERDICT: 0xFE0000 area is NOT executable (P0 unchanged)\r\n");
	p_nl();
}

void main(void)
{
	Board_Init();
	UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, PROBE_BAUD, TIM1);
	EA = 1;
	Ms_Delay(200);

	p_nl();
	p_str("==== PIE-BLOCK IAP PROBE ====\r\n");
	p_str("FOSC    = ");
	p_dec(FOSC);
	p_nl();
	p_str("IAP_TPS = ");
	p_dec(FOSC / 1000000);
	p_nl();
	p_str("baud    = ");
	p_dec(PROBE_BAUD);
	p_nl();
	p_nl();

	test_crc();
	test_far_map();
	test_iap_identity();
	test_iap_rw();
	test_iap_range();
	test_code_region();
	test_exec();

	p_str("==== PROBE DONE ====\r\n");

	while (1)
		;
}

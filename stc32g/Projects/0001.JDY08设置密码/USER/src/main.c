/* ============================================================
 * JDY-08 蓝牙串口模块 —— 修改配对密码工具（一次性使用）
 * ------------------------------------------------------------
 * 硬件接线（主控板 STC32G12K128）：
 *   JDY-08  TX  -> 主控板 P43（UART1 RXD）
 *   JDY-08  RX  -> 主控板 P44（UART1 TXD）
 *   JDY-08  VCC -> 3.3V（模块供电，注意别接 5V）
 *   JDY-08  GND -> GND
 *
 * 工作原理：
 *   程序自动挨个波特率（9600/115200/19200/38400/57600/230400/1200/2400/4800）
 *   发 AT+VER 探测，找到能应答的波特率后依次发
 *          AT+ISCEN1      （打开密码认证，默认关闭，必须先开）
 *          AT+PASS0000    （设 4 位密码 0000，应回 OK）
 *          AT+PASS000000  （若 4 位被拒，回退 6 位）
 *          AT+RST/AT+RESET（复位让设置生效）
 *   要点（官方 V2.1 手册）：JDY-08 没有裸 AT 指令（发 AT 回 +ERR2）；
 *   密码只能 4 位；指令不要加 \r\n 结尾；默认波特率 115200。
 *
 * 状态指示（板上 P3.4 蓝色 LED）：
 *   亮            -> 正在扫描/发送
 *   灭（常灭）     -> 成功，密码 = 0000（4 位）
 *   慢闪 2 下      -> 成功，但固件只认 6 位，密码 = 000000
 *   快闪 3 下      -> 波特率对，但改密码指令被拒（固件特殊）
 *   快闪 5 下      -> 所有波特率都探不到应答。检查接线 TX/RX 交叉、
 *                    供电、手机是否连着蓝牙
 *
 * 注意事项：
 *   - 上电前不要用手机连这个蓝牙，否则 AT 不生效。
 *   - 若模块被手机连着，先断开/关手机蓝牙再试。
 * ============================================================ */
#include "main.h"

uint8_t Channal = 36; /* nrf24l01.c 依赖此符号，本工具不用遥控，但工程里有该文件，必须定义 */

/* ==================== JDY-08 参数 ====================
 * JDY-08(CC2541) 官方 V2.1 手册要点（已核对原版 PDF）：
 *   - 指令都是 AT+XXX 形式，没有裸 AT 测试指令！发 AT 会回 +ERR2
 *   - 密码只能 4 位：AT+PASSxxxx；必须先 AT+ISCEN1 打开密码认证（默认关）
 *   - 查询密码 AT+PASS 回 PSS: xxxx；复位 AT+RST；版本 AT+VER
 *   - 默认波特率 115200；不要加 \r\n 结尾（部分固件把换行算进参数拒收） */
static unsigned long code BAUD_TABLE[] = {9600, 115200, 19200, 38400, 57600, 230400, 1200, 2400, 4800};
#define BAUD_COUNT 9
static char code CMD_VER[] = "AT+VER";              /* 探测用：读版本（只读安全） */
static char code CMD_ISCEN1[] = "AT+ISCEN1";        /* 打开密码认证（默认关闭，必须先开） */
static char code CMD_SET_PASS[] = "AT+PASS0000";    /* 4 位密码 0000（V2.1 手册：只能 4 位） */
static char code CMD_SET_PASS6[] = "AT+PASS000000"; /* 6 位密码回退（V3.x 固件用） */
static char code CMD_RST[] = "AT+RST";              /* JDY-08 原生复位指令 */
static char code CMD_RESET[] = "AT+RESET";          /* HM-10 clone 固件的复位指令 */

/* ==================== IAP 自升级下载触发（保留，勿删）====================
 * 收到 "@PIEIAP#" 命令字后置 DFU 标志并软复位到 bootloader，
 * 这样以后仍可通过 USB/蓝牙串口无线升级固件。 */
char code STCISPCMD[] = "@PIEIAP#";  /* 下载触发命令字 */
uint8_t isp_cmd_index = 0;           /* 命令匹配索引（ISR 更新） */
volatile uint8_t iapDownloadReq = 0; /* 1 = 请求进入下载模式 */

/* DFU 标志：放 XRAM 最后 4 字节，软复位不清零，bootloader 复位后据此
 * 停在下载模式而不跳 App。不动 flash，无擦写磨损。 */
#define DFU_TAG 0x12abcd34
long xdata DfuFlag _at_ 0x1ffc;

/* isr.c 通过 extern 引用本函数（收到 "@PIEIAP#" 命令字时由 ISR 直接调用），
 * 所以这里不能是 static。 */
void iapEnterDownload(void)
{
    EA = 0;            /* 关中断，避免复位序列被打断 */
    DfuFlag = DFU_TAG; /* 告诉 bootloader 停在下载模式 */
    IAP_CONTR = 0x20;  /* SWRST=1, SWBS=0 -> 复位到 bootloader */
    while (1)
        ; /* 等复位生效 */
}

/* ==================== UART1 收发工具 ==================== */

/* 发送一串 code 段字符串 */
static void Uart1SendStr(char code *s)
{
    while (*s)
        UART_PutChar(UART_1, (uint8_t)*s++);
}

/* 从 UART1 接收环形缓冲区读一个字节（ISR 负责往里存） */
static uint8_t Uart1ReadByte(void)
{
    uint8_t b;
    if (uart1_rx_head == uart1_rx_tail)
        return 0;
    b = uart1_rx_buff[uart1_rx_tail];
    uart1_rx_tail = (uint8_t)((uart1_rx_tail + 1) % UART1_RX_BUFFER_SIZE);
    return b;
}

/* 清空 UART1 接收缓冲 */
static void Uart1RxClear(void)
{
    uart1_rx_head = 0;
    uart1_rx_tail = 0;
}

/* 在 timeout_ms 内等待串口响应中出现 "OK"，匹配到返回 1 */
static uint8_t Uart1WaitOK(uint16_t timeout_ms)
{
    uint16_t t = 0;
    uint8_t st = 0; /* 0=等 'O'；1=已收到 'O'，等 'K' */
    uint8_t c;
    while (t < timeout_ms)
    {
        while (uart1_rx_head != uart1_rx_tail)
        {
            c = Uart1ReadByte();
            if (st == 0)
            {
                if (c == 'O')
                    st = 1;
            }
            else
            {
                if (c == 'K')
                    return 1;
                if (c != 'O')
                    st = 0;
            }
        }
        Ms_Delay(1);
        t++;
    }
    return 0;
}

/* 探测波特率用：在 timeout 内收到一段 "可打印 ASCII" 应答（≥2 个连续可打印字符
 * 或 1 个可打印字符后跟换行）即认为模块在线、波特率已对上。
 * 适用于 JDY-08：它应答可能是 OK / +OK / +ERR2 / JDY-08-V2.1 等，都含可打印字符。 */
static uint8_t Uart1ProbeWait(uint16_t timeout_ms)
{
    uint16_t t = 0;
    uint8_t got = 0;
    uint8_t c;
    while (t < timeout_ms)
    {
        while (uart1_rx_head != uart1_rx_tail)
        {
            c = Uart1ReadByte();
            if (c >= 0x20 && c <= 0x7E)
            {
                got++;
                if (got >= 2)
                    return 1;
            }
            else if (c == 0x0D || c == 0x0A)
            {
                if (got >= 1)
                    return 1;
            }
            else
            {
                got = 0; /* 乱码：重新累计 */
            }
        }
        Ms_Delay(1);
        t++;
    }
    return 0;
}

/* ==================== 状态 LED（板上 P3.4，0=亮 1=灭）====================
 * 注意：不能用 main.h 里的 LED_ON/LED_OFF 宏，那两行历史遗留带多余反引号，
 * 展开会语法错误。这里用独立宏名避免冲突。 */
#define LED_LIT 0  /* 亮 */
#define LED_DARK 1 /* 灭 */

static void LedSet(uint8_t v)
{
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, v);
}

/* ==================== 主函数 ==================== */
void main(void)
{
    uint8_t i;       /* 波特率表下标 */
    uint8_t b;       /* 重试/闪灯计数 */
    uint8_t found;   /* 是否找到能对话的波特率 */
    uint8_t isc_ok;  /* AT+ISCEN1 是否成功 */
    uint8_t set_ok;  /* 4 位密码 AT+PASS0000 是否成功 */
    uint8_t set6_ok; /* 6 位密码 AT+PASS000000 是否成功 */

    Board_Init();

    /* 板上 P3.4 LED 配置为准双向输出 */
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    LedSet(LED_DARK);

    /* 上电等模块启动完成 */
    Ms_Delay(500);

    while (1)
    {
        if (iapDownloadReq)
            iapEnterDownload();

        LedSet(LED_LIT); /* 亮 = 工作中 */
        found = 0;

        /* 1) 波特率扫描：发 AT+VER（只读），收到可打印 ASCII 应答即波特率对上。
         *    JDY-08 没有裸 AT 测试指令（会回 +ERR2），所以不能用 AT 当探测。 */
        for (i = 0; i < BAUD_COUNT; i++)
        {
            UART_Init(UART_1, UART1_RX_P43, UART1_TX_P44, BAUD_TABLE[i], TIM1);
            Uart1RxClear();
            Uart1SendStr(CMD_VER);
            if (Uart1ProbeWait(400))
            {
                found = 1;
                break;
            }
        }

        if (found)
        {
            Ms_Delay(200); /* 等模块安静 */

            /* 2) 打开密码认证（官方手册：密码仅在 AT+ISCEN1 后才生效） */
            isc_ok = 0;
            for (b = 0; b < 2 && !isc_ok; b++)
            {
                Uart1RxClear();
                Uart1SendStr(CMD_ISCEN1);
                isc_ok = Uart1WaitOK(400);
            }

            /* 3a) 设 4 位密码 0000（V2.1 手册：密码只能 4 位） */
            set_ok = 0;
            for (b = 0; b < 2 && !set_ok; b++)
            {
                Uart1RxClear();
                Uart1SendStr(CMD_SET_PASS);
                set_ok = Uart1WaitOK(400);
            }

            /* 3b) 4 位被拒，回退试 6 位（V3.x 固件可能要求 6 位） */
            set6_ok = 0;
            if (!set_ok)
            {
                for (b = 0; b < 2 && !set6_ok; b++)
                {
                    Uart1RxClear();
                    Uart1SendStr(CMD_SET_PASS6);
                    set6_ok = Uart1WaitOK(400);
                }
            }

            if (set_ok)
            {
                /* 成功：密码 = 0000（4 位）。复位使生效，LED 常灭 */
                Uart1SendStr(CMD_RST);
                Uart1SendStr(CMD_RESET);
                Ms_Delay(500);
                LedSet(LED_DARK);
                Ms_Delay(3000); /* 保持灭 3 秒，随后重试一轮（幂等，无副作用） */
            }
            else if (set6_ok)
            {
                /* 成功但只能 6 位：密码 = 000000。慢闪 2 下提示 */
                Uart1SendStr(CMD_RST);
                Uart1SendStr(CMD_RESET);
                Ms_Delay(500);
                for (b = 0; b < 2; b++)
                {
                    LedSet(LED_LIT);
                    Ms_Delay(300);
                    LedSet(LED_DARK);
                    Ms_Delay(300);
                }
                Ms_Delay(1000);
            }
            else
            {
                /* 波特率对但改密码被拒：快闪 3 下 */
                for (b = 0; b < 3; b++)
                {
                    LedSet(LED_LIT);
                    Ms_Delay(100);
                    LedSet(LED_DARK);
                    Ms_Delay(100);
                }
                Ms_Delay(800);
            }
        }
        else
        {
            /* 所有波特率都探不到：快闪 5 下 */
            for (b = 0; b < 5; b++)
            {
                LedSet(LED_LIT);
                Ms_Delay(100);
                LedSet(LED_DARK);
                Ms_Delay(100);
            }
            Ms_Delay(800);
        }
    }
}

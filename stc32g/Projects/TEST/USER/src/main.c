#include "main.h"

/* ===== 全局变量（自动生成）===== */
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Freq_Change_Order 0xCC
#define Dir_Change_Order 0xDD
#define Zero_Order 0xEE
uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;
uint8_t Channal = 15;
/* UART1 查询发送一字节：不依赖 UART1 TX 中断（避免 UART_PutChar 的
 * UART_BUSY 死锁——TX 中断被 NRF 的 P2.6 高优先级中断抢占时，BUSY 永远
 * 清不掉，发送会永久卡死）。发送期间临时关串口中断，轮询硬件 TI 标志。
 * 要求 UART1 已用 UART_Init 初始化（TR1 已启动，TI 必会置位）。 */
static void Uart1TxQuery(uint8_t dat)
{
    ES = 0;     /* 关 UART1 中断，避免中断抢先清 TI 导致死锁 */
    SBUF = dat; /* 启动发送 */
    while (!TI) /* 等硬件发送完成 */
        ;
    TI = 0; /* 清发送完成标志 */
    ES = 1; /* 恢复 UART1 中断 */
}

void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64, uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76, uint16_t data_p77)
{
    uint8_t i = 0;
    uint8_t control_frame_pack[21] = {0};
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    control_frame_pack[2] = control_cmd;
    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);
    for (i = 0; i < 21; i++)
        Uart1TxQuery(control_frame_pack[i]);
}
int pie_abs(int x)
{
    return (x < 0) ? -x : x;
}
int _base_spd, _turn_spd, _wheel[4];
uint8_t _rm_shoot_last_key = 0;

/* 不会永久阻塞启动流程的 NRF24L01 初始化函数。
 * 库里的 remote_control_init() 使用无限循环，模块未接或故障时整个 App
 * 永远无法进入主循环。这里有限重试，失败后让其余功能继续启动。
 * 注意：NRF 的 IRQ 中断（P2.6）会在 ISR 里做 SPI 读写（nrf_readbuf 是
 * reentrant），若在初始化期间抢先执行，会破坏 nrf_link_check 的 SPI 校验，
 * 导致 NRF24L01_Init 一直返回 0 而卡死。所以调用本函数前必须先 EA=0
 * 关全局中断，初始化完成后再 EA=1。Ms_Delay 是纯软件延时，关中断不受影响。 */
static void remoteControlInitWithTimeout(void)
{
    uint8_t retry;

    for (retry = 0; retry < 20; retry++)
    {
        if (NRF24L01_Init())
        {
            Ms_Delay(200);
            return;
        }
        Ms_Delay(10);
    }
}

/* ==================== 初始化诊断：3 颗 LED + 蜂鸣器 ====================
 * 3 颗 LED（P35/P36/P37，低电平点亮）+ 蜂鸣器（P33，PWM 驱动），把初始化
 * 拆成多步，每步用 LED 编码 + 蜂鸣器音调双重定位：
 *   - 进入某步前：LED 显示该步编码（3 bit 二进制，P35=bit0 P36=bit1 P37=bit2）
 *   - 该步初始化成功后：蜂鸣器响一声推进确认音（音调随步骤递增）
 *   - 若某步阻塞：LED 停在编码、且听不到后续确认音 -> 对照编码表即可定位
 * P34 保留给 NRF 遥控器 CE，不作为 LED。 */
#define LED_PORT GPIO_P3
#define LED1_PIN GPIO_Pin_5    /* P35 = 编码 bit0 */
#define LED2_PIN GPIO_Pin_6    /* P36 = 编码 bit1 */
#define LED3_PIN GPIO_Pin_7    /* P37 = 编码 bit2 */
#define BUZZER_CH PWMB_CH3_P33 /* 蜂鸣器 P33 */

/* LED 显示步骤编码 0~7（低电平点亮：0=亮 1=灭）
 * 注意：参数不能叫 code —— code 是 C251 保留字（存储类型限定符） */
static void LedShow(uint8_t show)
{
    GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);
    GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);
}

/* 蜂鸣器响一声（PWM 驱动，freq 音调 / ms 时长） */
static void Beep(uint16_t freq, uint16_t ms)
{
    PWM_SET_Frequency(BUZZER_CH, freq, 500);
    Ms_Delay(ms);
    PWM_SET_Frequency(BUZZER_CH, freq, 0);
}

/* 进入某步：先显示编码（若该步阻塞，LED 就停在这里） */
static void StepBegin(uint8_t step)
{
    LedShow(step & 0x07);
}

/* 某步初始化成功：蜂鸣器推进确认音（音调随步骤递增，可听声定位） */
static void StepDone(uint8_t step)
{
    Beep(500 + (uint16_t)(step % 8) * 60, 60);
}

/* ===== 主函数 ===== */
void main(void)
{
    /* ===== 初始化诊断：每步 LED 编码 + 蜂鸣器音调，卡在哪步 LED 就停在哪 =====
     * 编码表（P37 P36 P35 二进制）：
     *   000 上电起点      001 Board_Init
     *   010 LED GPIO 自检 011 蜂鸣器 PWM
     *   100 蜂鸣器自检    101 NRF 遥控器初始化（已知易阻塞）
     *   110 UART1+拓展板  111 全部完成 */
    StepBegin(0);
    Board_Init();
    StepDone(0);

    StepBegin(1);
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);
    LedShow(7); /* LED 全亮自检 */
    Ms_Delay(200);
    LedShow(0); /* 全灭 */
    StepDone(1);

    StepBegin(2);
    PWM_Init(BUZZER_CH, 1000, 0); /* 蜂鸣器 P33（占空比 0 不响） */
    StepDone(2);

    StepBegin(3);
    Beep(700, 120); /* 蜂鸣器自检 */
    StepDone(3);

    StepBegin(4);
    /* NRF 遥控器初始化：全程关中断，避免 P2.6 高优先级中断在 ISR 里做 SPI 死锁 */
    EA = 0;
    remoteControlInitWithTimeout();
    /* 关掉 P2.6 外部中断：遥控器接收改为主循环轮询 nrf_handler()，
     * 彻底避免 ISR 里 SPI/reentrant 死锁（实测遥控器开着会导致初始化卡死） */
    P2INTE &= ~GPIO_Pin_6;
    EA = 1;
    StepDone(4);

    StepBegin(5);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    ExpansionBoradControl(Init_Order, 10000, 10000, 50, 50, 10000, 10000, 10000, 10000);
    Ms_Delay(20);
    StepDone(5);

    /* ===== 初始化全部通过 ===== */
    StepBegin(6);
    LedShow(7);     /* 全亮 = 初始化完成 */
    Beep(523, 120); /* 完成琶音 */
    Beep(659, 120);
    Beep(784, 120);
    Beep(1047, 240);

    /* ===== 主循环：底盘四轮差速控制 ===== */
    while (1)
    {
        nrf_handler(); /* 轮询 NRF 接收（P2.6 中断已关，改主循环轮询） */

        _base_spd = (int)((float)RcRockerValueRead(ROCKER_LEFT_VERTICAL) * (4000) / 2047);
        _turn_spd = -(int)((float)RcRockerValueRead(ROCKER_LEFT_HORIZONTAL) * (4000) / 2047);
        _wheel[0] = -_base_spd - _turn_spd;
        _wheel[1] = -_base_spd - _turn_spd;
        _wheel[2] = _base_spd - _turn_spd;
        _wheel[3] = _base_spd - _turn_spd;
        ExpansionBoradControl(Dir_Change_Order, 1, 1, 1, 1, (_wheel[0] >= 0), (_wheel[1] >= 0), (_wheel[2] >= 0), (_wheel[3] >= 0));
        Ms_Delay(5);
        ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, (uint16_t)pie_abs(_wheel[0]), (uint16_t)pie_abs(_wheel[1]), (uint16_t)pie_abs(_wheel[2]), (uint16_t)pie_abs(_wheel[3]));
        Ms_Delay(5);
        if (RcKeyValueRead(KEY_OFFSET_1) && !_rm_shoot_last_key)
        {
            ExpansionBoradControl(Duty_Change_Order, ((3000) < 0 ? 0 : ((3000) > 10000 ? 10000 : (3000))), 0, 0, 0, 0, 0, 0, 0);
            Ms_Delay(100);
            ExpansionBoradControl(Duty_Change_Order, 0, 0, 0, 0, 0, 0, 0, 0);
        }
        _rm_shoot_last_key = RcKeyValueRead(KEY_OFFSET_1);
    }
}

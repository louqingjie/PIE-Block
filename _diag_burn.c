/* ============================================================
 * 烧录模式按键诊断固件（临时排查用）
 * ------------------------------------------------------------
 * 作用：
 *   1) 主循环每 500ms 翻转一次板上 LED（P3.4）—— LED 在闪 = 固件活着、主循环在跑
 *   2) 上电采样 P06/P07/P42 空闲电平，任一按键电平变化 -> 蜂鸣器响 200ms
 *      —— 按下某个键有声音 = 那个引脚实际接了按键且按下有电平变化
 *   3) 上电后蜂鸣器响 3 声（700/1000/1400Hz）—— 证明初始化完成、即将进主循环
 * ============================================================ */
#include "main.h"
#include "MATH.H"

uint8_t Channal = 36; /* nrf24l01.c 依赖此符号，必须定义 */

/* isr.c 固定引用这些符号（正常由生成器 _gen_isp_monitor 提供），诊断固件必须定义 */
char code STCISPCMD[] = "@PIEIAP#";  /* 下载触发命令字 */
uint8_t isp_cmd_index = 0;           /* 命令匹配索引（ISR 更新） */
volatile uint8_t iapDownloadReq = 0; /* 下载请求标志 */
#define DFU_TAG 0x12abcd34
long xdata DfuFlag _at_ 0x1ffc; /* 软复位不清零的 DFU 标志 */
void iapEnterDownload(void)
{
    EA = 0;
    DfuFlag = DFU_TAG;
    IAP_CONTR = 0x20; /* 软复位到 bootloader */
    while (1)
        ;
}

void main(void)
{
    uint8_t idle06, idle07, idle42;
    uint8_t ledState = 0;
    unsigned int tick = 0;
    unsigned int i;

    Board_Init();
    /* 按键高阻输入（不配内部上下拉，由外部电路决定电平） */
    GPIO_Init(GPIO_P0, (GPIO_Pin_enum)(GPIO_Pin_6 | GPIO_Pin_7), GPIO_HighZ);
    GPIO_Init(GPIO_P4, GPIO_Pin_2, GPIO_HighZ);
    /* 板上 LED：P3.4 推挽输出 */
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    /* 蜂鸣器 P33（PWM） */
    PWM_Init(PWMB_CH3_P33, 1000, 0);

    /* 上电采样空闲电平 */
    idle06 = GPIO_Read_Bit(GPIO_P0, GPIO_Pin_6);
    idle07 = GPIO_Read_Bit(GPIO_P0, GPIO_Pin_7);
    idle42 = GPIO_Read_Bit(GPIO_P4, GPIO_Pin_2);

    /* 初始化完成：蜂鸣器 3 声提示，随后进主循环 */
    PWM_SET_Frequency(PWMB_CH3_P33, 700, 500);
    Ms_Delay(150);
    PWM_SET_Frequency(PWMB_CH3_P33, 1000, 500);
    Ms_Delay(150);
    PWM_SET_Frequency(PWMB_CH3_P33, 1400, 500);
    Ms_Delay(250);
    PWM_SET_Frequency(PWMB_CH3_P33, 1000, 0);

    for (;;)
    {
        /* LED 每 500ms 翻转一次：在闪 = 主循环在跑 */
        if (++tick >= 50)
        {
            tick = 0;
            ledState ^= 1;
            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, ledState);
        }

        /* 任一按键电平变化 -> 蜂鸣器响 200ms */
        if (GPIO_Read_Bit(GPIO_P0, GPIO_Pin_6) != idle06 || GPIO_Read_Bit(GPIO_P0, GPIO_Pin_7) != idle07 || GPIO_Read_Bit(GPIO_P4, GPIO_Pin_2) != idle42)
        {
            PWM_SET_Frequency(PWMB_CH3_P33, 1000, 500);
            Ms_Delay(200);
            PWM_SET_Frequency(PWMB_CH3_P33, 1000, 0);
            /* 响完丢弃一次抖动：清空计数，避免连响 */
            for (i = 0; i < 5; i++)
                Ms_Delay(10);
        }

        Ms_Delay(10);
    }
}

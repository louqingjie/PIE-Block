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

static void Uart1SendFrameQuery(const uint8_t *frame, uint8_t length)
{
    uint8_t i;
    uint8_t globalInterruptEnabled = EA;
    uint8_t uart1InterruptEnabled = ES;

    EA = 0;
    ES = 0;
    for (i = 0; i < length; i++)
    {
        TI = 0;
        SBUF = frame[i];
        while (!TI)
            ;
    }
    TI = 0;
    ES = uart1InterruptEnabled;
    EA = globalInterruptEnabled;
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
    Uart1SendFrameQuery(control_frame_pack, 21);
}
int pie_abs(int x)
{
    return (x < 0) ? -x : x;
}
int _base_spd, _turn_spd, _wheel[4];
uint8_t _rm_shoot_last_key = 0;

/* 遥控器通道号，0~125（nrf24l01.c 通过 extern 引用） */
uint8_t Channal = 36;

/* ===== 主函数 ===== */
void main(void)
{
    Board_Init();

    /* ===== 初始化区 ===== */
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);
    remote_control_init();
    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);
    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);
    ExpansionBoradControl(Init_Order, 10000, 10000, 50, 50, 10000, 10000, 10000, 10000);
    Ms_Delay(20);

    /* ===== 主循环 ===== */
    while (1)
    {
        _base_spd = (int)(((int32_t)RcRockerValueRead(ROCKER_LEFT_VERTICAL) * 4000L) / 2047L);
        _turn_spd = -(int)(((int32_t)RcRockerValueRead(ROCKER_LEFT_HORIZONTAL) * 4000L) / 2047L);
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

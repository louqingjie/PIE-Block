#include "main.h"

#define PWM_TEST_CHANNEL PWMA_CH1P_P60

#define LED_PORT GPIO_P3
#define LED_P35  GPIO_Pin_5
#define LED_P36  GPIO_Pin_6
#define LED_P37  GPIO_Pin_7

static void Led_Set(uint8_t p35, uint8_t p36, uint8_t p37)
{
    /* 板载LED低电平点亮。 */
    GPIO_Write_Bit(LED_PORT, LED_P35, p35 ? GPIO_LOW : GPIO_HIGH);
    GPIO_Write_Bit(LED_PORT, LED_P36, p36 ? GPIO_LOW : GPIO_HIGH);
    GPIO_Write_Bit(LED_PORT, LED_P37, p37 ? GPIO_LOW : GPIO_HIGH);
}

void main(void)
{
    Board_Init();
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED_P35 | LED_P36 | LED_P37), GPIO_OUT_PP);
    Led_Set(0, 0, 0);

    /* P60：1 kHz、50%占空比，先验证PWM初始化和输出使能。 */
    PWM_Init(PWM_TEST_CHANNEL, 1000, 5000);

    while (1)
    {
        /* 1 kHz，25%占空比。LED编码：001。 */
        Led_Set(1, 0, 0);
        PWM_SET_Duty(PWM_TEST_CHANNEL, 2500);
        Ms_Delay(1000);

        /* 1 kHz，50%占空比。LED编码：010。 */
        Led_Set(0, 1, 0);
        PWM_SET_Duty(PWM_TEST_CHANNEL, 5000);
        Ms_Delay(1000);

        /* 1 kHz，75%占空比。LED编码：011。 */
        Led_Set(1, 1, 0);
        PWM_SET_Duty(PWM_TEST_CHANNEL, 7500);
        Ms_Delay(1000);

        /* 2 kHz，50%占空比，验证运行中改频率。LED编码：100。 */
        Led_Set(0, 0, 1);
        PWM_SET_Frequency(PWM_TEST_CHANNEL, 2000, 5000);
        Ms_Delay(1000);

        /* 关闭输出一秒，再回到1 kHz，便于听感和示波器确认。 */
        Led_Set(0, 0, 0);
        PWM_SET_Duty(PWM_TEST_CHANNEL, 0);
        Ms_Delay(1000);
        PWM_SET_Frequency(PWM_TEST_CHANNEL, 1000, 5000);
    }
}

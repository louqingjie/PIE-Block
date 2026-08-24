#include "main.h"

#define PWM5_TEST_CHANNEL PWMB_CH1_P74
#define PWM6_TEST_CHANNEL PWMB_CH2_P75
#define PWM7_TEST_CHANNEL PWMB_CH3_P76
#define PWM8_TEST_CHANNEL PWMB_CH4_P77

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

static void Set_All_Duty(uint32_t pwm5, uint32_t pwm6, uint32_t pwm7, uint32_t pwm8)
{
    PWM_SET_Duty(PWM5_TEST_CHANNEL, pwm5);
    PWM_SET_Duty(PWM6_TEST_CHANNEL, pwm6);
    PWM_SET_Duty(PWM7_TEST_CHANNEL, pwm7);
    PWM_SET_Duty(PWM8_TEST_CHANNEL, pwm8);
}

void main(void)
{
    Board_Init();
    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED_P35 | LED_P36 | LED_P37), GPIO_OUT_PP);
    Led_Set(0, 0, 0);

    /* PWMB：P74/P75/P76/P77 分别测试 PWM5/PWM6/PWM7/PWM8。 */
    PWM_Init(PWM5_TEST_CHANNEL, 1000, 2500);
    PWM_Init(PWM6_TEST_CHANNEL, 1000, 5000);
    PWM_Init(PWM7_TEST_CHANNEL, 1000, 7500);
    PWM_Init(PWM8_TEST_CHANNEL, 1000, 2500);

    while (1)
    {
        /* P74/P75/P76/P77 = 25%/50%/75%/25%。 */
        Led_Set(1, 0, 0);
        Set_All_Duty(2500, 5000, 7500, 2500);
        Ms_Delay(1000);

        /* P74/P75/P76/P77 = 75%/50%/25%/75%。 */
        Led_Set(0, 1, 0);
        Set_All_Duty(7500, 5000, 2500, 7500);
        Ms_Delay(1000);

        /* P74/P75/P76/P77 = 50%/25%/50%/25%。 */
        Led_Set(1, 1, 0);
        Set_All_Duty(5000, 2500, 5000, 2500);
        Ms_Delay(1000);

        /* 四路占空比归零，验证 PWMB 四个比较通道均可更新。 */
        Led_Set(0, 0, 1);
        Set_All_Duty(0, 0, 0, 0);
        Ms_Delay(1000);
    }
}

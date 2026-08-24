#include "main.h"

#define LED_PORT GPIO_P3
#define LED_P35  GPIO_Pin_5
#define LED_P36  GPIO_Pin_6
#define LED_P37  GPIO_Pin_7
#define TIMER_MARKER_PIN GPIO_Pin_4

void main(void)
{
    Board_Init();

    GPIO_Init(LED_PORT,
              (GPIO_Pin_enum)(LED_P35 | LED_P36 | LED_P37),
              GPIO_OUT_PP);
    GPIO_Init(LED_PORT, TIMER_MARKER_PIN, GPIO_OUT_PP);

    /* 板载 LED 低电平点亮；P34 作为每次定时器中断的示波器标记脚。 */
    P35 = 1;
    P36 = 1;
    P37 = 1;
    P34 = 0;

    /* Timer0：1 ms 一次中断。 */
    PIT_Timer_Ms(TIM0, 1);

    while (1)
    {
        /* 所有动作由 Timer0 ISR 完成，主循环保持运行即可。 */
    }
}

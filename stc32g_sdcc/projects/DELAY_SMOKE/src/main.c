#include "main.h"

/* P34 高电平和低电平都应持续 1000 ms，便于示波器直接测量 Ms_Delay。 */
void main(void)
{
    Board_Init();
    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);
    P34 = 0;

    while (1)
    {
        P34 = 1;
        Ms_Delay(1000);
        P34 = 0;
        Ms_Delay(1000);
    }
}

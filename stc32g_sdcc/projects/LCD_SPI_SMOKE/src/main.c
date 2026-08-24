#include "main.h"

/* P35：低电平点亮的运行心跳；P36：低电平点亮的 LCD 初始化完成指示。 */
#define HEARTBEAT_PORT GPIO_P3
#define HEARTBEAT_PIN  GPIO_Pin_5
#define READY_PORT     GPIO_P3
#define READY_PIN      GPIO_Pin_6

static void Led_Init(void)
{
    GPIO_Init(HEARTBEAT_PORT, HEARTBEAT_PIN, GPIO_OUT_PP);
    GPIO_Init(READY_PORT, READY_PIN, GPIO_OUT_PP);
    GPIO_Write_Bit(HEARTBEAT_PORT, HEARTBEAT_PIN, GPIO_HIGH);
    GPIO_Write_Bit(READY_PORT, READY_PIN, GPIO_HIGH);
}

void main(void)
{
    Board_Init();
    Led_Init();

    /* LCD.c 通过 GPIO 手动输出 CLK/DATA，因此本程序验证的是软件 SPI。 */
    LCD_Init();
    LCD_P6x8Str(0, 0, "LCD SPI OK");
    LCD_P6x8Str(0, 2, "RUN");
    GPIO_Write_Bit(READY_PORT, READY_PIN, GPIO_LOW);

    while (1)
    {
        GPIO_Toggle_Bit(HEARTBEAT_PORT, HEARTBEAT_PIN);
        Ms_Delay(250);
    }
}

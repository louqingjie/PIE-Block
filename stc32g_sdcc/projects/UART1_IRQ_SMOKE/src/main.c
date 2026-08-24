#include "main.h"

#define LED_PORT GPIO_P3
#define RX_MARKER_PIN GPIO_Pin_4
#define RX_LED_PIN GPIO_Pin_5
#define TX_LED_PIN GPIO_Pin_6
#define STATUS_LED_PIN GPIO_Pin_7

volatile uint8_t uart1_rx_pending;
volatile uint8_t uart1_rx_data;
volatile uint8_t uart1_tx_busy;

static void UART1_SendByte(uint8_t data)
{
    while (uart1_tx_busy)
    {
    }
    uart1_tx_busy = 1;
    SBUF = data;
    while (uart1_tx_busy)
    {
    }
}

void main(void)
{
    uint8_t data;

    Board_Init();

    GPIO_Init(LED_PORT,
              (GPIO_Pin_enum)(RX_MARKER_PIN | RX_LED_PIN | TX_LED_PIN | STATUS_LED_PIN),
              GPIO_OUT_PP);
    GPIO_Init(GPIO_P4, GPIO_Pin_3, GPIO_HighZ);
    GPIO_Init(GPIO_P4, GPIO_Pin_4, GPIO_OUT_PP);

    /* 板载 LED 低电平点亮；P34 标记 UART1 ISR，P43/P44 为 RX/TX。 */
    P34 = 0;
    P35 = 1;
    P36 = 1;
    P37 = 1;

    /* 显式初始化测试状态，避免测试依赖外部 RAM 上电值。 */
    uart1_rx_pending = 0;
    uart1_rx_data = 0;
    uart1_tx_busy = 0;

    /* UART1：P43=RX、P44=TX，8N1，115200 baud；使用手册示例的 Timer2。 */
    UART_Init(UART_1, UART1_RX_P43, UART1_TX_P44, 115200, TIM2);
    UART1_SendByte('U');
    UART1_SendByte('A');
    UART1_SendByte('R');
    UART1_SendByte('T');
    UART1_SendByte('1');
    UART1_SendByte('_');
    UART1_SendByte('R');
    UART1_SendByte('E');
    UART1_SendByte('A');
    UART1_SendByte('D');
    UART1_SendByte('Y');
    UART1_SendByte('\r');
    UART1_SendByte('\n');

    while (1)
    {
        if (uart1_rx_pending)
        {
            /* 主循环取走 ISR 保存的字节，再交给发送端回显。 */
            EA = 0;
            data = uart1_rx_data;
            uart1_rx_pending = 0;
            EA = 1;

            while (uart1_tx_busy)
            {
            }
            uart1_tx_busy = 1;
            SBUF = data;
        }
    }
}

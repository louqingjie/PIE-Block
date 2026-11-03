/* PIE-Block 生成代码运行时验证桩头文件。
 *
 * 只覆盖步兵/工程生成代码引用到的板级符号；函数实现由 verify_runtime 生成的
 * harness.c 提供（虚拟时钟 + 脚本化遥控输入 + 串口/扩展板帧捕获）。
 * 该目录仅用于 `dart run tool/verify_runtime.dart`，不参与任何正式构建。
 */
#ifndef PB_RUNTIME_STUB_MAIN_H
#define PB_RUNTIME_STUB_MAIN_H

#include <stdint.h>
#include <stdlib.h>

typedef unsigned int GPIO_Pin_enum;
typedef unsigned char GPIO_Port_enum;
#define GPIO_P3 ((GPIO_Port_enum)3)
#define GPIO_Pin_5 0x0020u
#define GPIO_Pin_6 0x0040u
#define GPIO_Pin_7 0x0080u
#define GPIO_OUT_PP 0

extern volatile unsigned char EA, P2INTE;

#define UART_1 1
#define UART1_RX_P30 0
#define UART1_TX_P31 1
#define TIM1 1

#define PWMA_CH4N_P33 101
#define PWMB_CH4_P03 201
#define PWMB_CH1_P74 202
#define PWMB_CH3_P33 203

enum {
    KEY_OFFSET_1 = 1, /* E */
    KEY_OFFSET_UP,
    KEY_OFFSET_DOWN,
    KEY_OFFSET_LEFT,
    KEY_OFFSET_RIGHT,
    KEY_OFFSET_A,
    KEY_OFFSET_B,
    KEY_OFFSET_C,
    KEY_OFFSET_D,
    KEY_OFFSET_Rocker11, /* LC */
    KEY_OFFSET_Rocker21, /* RC */
};

enum {
    ROCKER_LEFT_HORIZONTAL = 0,
    ROCKER_LEFT_VERTICAL,
    ROCKER_RIGHT_HORIZONTAL,
    ROCKER_RIGHT_VERTICAL,
};

/* 由 harness.c 提供的实现。 */
void Ms_Delay(uint32_t ms);
uint8_t NRF24L01_Init(void);
void Board_Init(void);
void UART_Init(int id, int rx, int tx, int baud, int tim);
void GPIO_Init(GPIO_Port_enum port, GPIO_Pin_enum pins, int mode);
void GPIO_Write_Bit(GPIO_Port_enum port, GPIO_Pin_enum pin, int value);
void PWM_Init(int channel, int frequency, int duty);
void PWM_SET_Frequency(int channel, int frequency, int duty);
uint8_t RcKeyValueRead(int key);
int RcRockerValueRead(int rocker);
void nrf_handler(void);

/* 生成代码的 main 由 -Dmain=robot_main 改名后调用。 */
void robot_main(void);

#endif

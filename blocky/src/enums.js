/* 与 CNU_PIE_GPIO.h / CNU_PIE_UART.h 等枚举一一对应
 * 格式: [下拉显示名, 生成的 C 标识符] */

// GPIO 端口 (GPIO_Port_enum)
export const PORT_OPTIONS = [
  ['P0', 'GPIO_P0'], ['P1', 'GPIO_P1'], ['P2', 'GPIO_P2'], ['P3', 'GPIO_P3'],
  ['P4', 'GPIO_P4'], ['P5', 'GPIO_P5'], ['P6', 'GPIO_P6'], ['P7', 'GPIO_P7'],
];

// GPIO 引脚 (GPIO_Pin_enum)
export const PIN_OPTIONS = [
  ['0', 'GPIO_Pin_0'], ['1', 'GPIO_Pin_1'], ['2', 'GPIO_Pin_2'], ['3', 'GPIO_Pin_3'],
  ['4', 'GPIO_Pin_4'], ['5', 'GPIO_Pin_5'], ['6', 'GPIO_Pin_6'], ['7', 'GPIO_Pin_7'],
  ['低4位', 'GPIO_Pin_LOW'], ['高4位', 'GPIO_Pin_HIGH'], ['全部', 'GPIO_Pin_All'],
];

// GPIO 工作模式 (GPIO_Mode_enum)
export const MODE_OPTIONS = [
  ['准双向口', 'GPIO_PullUp'],
  ['高阻输入', 'GPIO_HighZ'],
  ['开漏输出', 'GPIO_OUT_OD'],
  ['推挽输出', 'GPIO_OUT_PP'],
];

// 输出电平
export const LEVEL_OPTIONS = [
  ['高电平', '1'],
  ['低电平', '0'],
];

// 串口号 (UARTN_Enum)
export const UART_OPTIONS = [
  ['串口1', 'UART_1'], ['串口2', 'UART_2'],
  ['串口3', 'UART_3'], ['串口4', 'UART_4'],
];

// ===== PWM (PWM_CHN_PIN_enum) =====
export const PWM_PIN_OPTIONS = [
  ['PWMA CH1+ P1.0', 'PWMA_CH1P_P10'], ['PWMA CH1- P1.1', 'PWMA_CH1N_P11'],
  ['PWMA CH1+ P2.0', 'PWMA_CH1P_P20'], ['PWMA CH1- P2.1', 'PWMA_CH1N_P21'],
  ['PWMA CH1+ P6.0', 'PWMA_CH1P_P60'], ['PWMA CH1- P6.1', 'PWMA_CH1N_P61'],
  ['PWMA CH2+ P1.2', 'PWMA_CH2P_P12'], ['PWMA CH2- P1.3', 'PWMA_CH2N_P13'],
  ['PWMA CH2+ P2.2', 'PWMA_CH2P_P22'], ['PWMA CH2- P2.3', 'PWMA_CH2N_P23'],
  ['PWMA CH2+ P6.2', 'PWMA_CH2P_P62'], ['PWMA CH2- P6.3', 'PWMA_CH2N_P63'],
  ['PWMA CH3+ P1.4', 'PWMA_CH3P_P14'], ['PWMA CH3- P1.5', 'PWMA_CH3N_P15'],
  ['PWMA CH3+ P2.4', 'PWMA_CH3P_P24'], ['PWMA CH3- P2.5', 'PWMA_CH3N_P25'],
  ['PWMA CH3+ P6.4', 'PWMA_CH3P_P64'], ['PWMA CH3- P6.5', 'PWMA_CH3N_P65'],
  ['PWMA CH4+ P1.6', 'PWMA_CH4P_P16'], ['PWMA CH4- P1.7', 'PWMA_CH4N_P17'],
  ['PWMA CH4+ P2.6', 'PWMA_CH4P_P26'], ['PWMA CH4- P2.7', 'PWMA_CH4N_P27'],
  ['PWMA CH4+ P6.6', 'PWMA_CH4P_P66'], ['PWMA CH4- P6.7', 'PWMA_CH4N_P67'],
  ['PWMA CH4+ P3.4', 'PWMA_CH4P_P34'], ['PWMA CH4- P3.3', 'PWMA_CH4N_P33'],
  ['PWMB CH1 P2.0', 'PWMB_CH1_P20'], ['PWMB CH1 P1.7', 'PWMB_CH1_P17'],
  ['PWMB CH1 P0.0', 'PWMB_CH1_P00'], ['PWMB CH1 P7.4', 'PWMB_CH1_P74'],
  ['PWMB CH2 P2.1', 'PWMB_CH2_P21'], ['PWMB CH2 P5.4', 'PWMB_CH2_P54'],
  ['PWMB CH2 P0.1', 'PWMB_CH2_P01'], ['PWMB CH2 P7.5', 'PWMB_CH2_P75'],
  ['PWMB CH3 P2.2', 'PWMB_CH3_P22'], ['PWMB CH3 P3.3', 'PWMB_CH3_P33'],
  ['PWMB CH3 P0.2', 'PWMB_CH3_P02'], ['PWMB CH3 P7.6', 'PWMB_CH3_P76'],
  ['PWMB CH4 P2.3', 'PWMB_CH4_P23'], ['PWMB CH4 P3.4', 'PWMB_CH4_P34'],
  ['PWMB CH4 P0.3', 'PWMB_CH4_P03'], ['PWMB CH4 P7.7', 'PWMB_CH4_P77'],
];

// ===== ADC (ADC_PIN_ENUM / ADC_SPEED_ENUM) =====
export const ADC_PIN_OPTIONS = [
  ['P1.0', 'ADC_P10'], ['P1.1', 'ADC_P11'], ['P1.2', 'ADC_P12'], ['P1.3', 'ADC_P13'],
  ['P1.4', 'ADC_P14'], ['P1.5', 'ADC_P15'], ['P1.6', 'ADC_P16'], ['P1.7', 'ADC_P17'],
  ['P0.0', 'ADC_P00'], ['P0.1', 'ADC_P01'], ['P0.2', 'ADC_P02'], ['P0.3', 'ADC_P03'],
  ['P0.4', 'ADC_P04'], ['P0.5', 'ADC_P05'], ['P0.6', 'ADC_P06'],
  ['内部1.19V', 'ADC_POWR'],
];
export const ADC_SPEED_OPTIONS = [
  ['SYSclk/2/1', 'ADC_SPEED_2X1T'], ['SYSclk/2/2', 'ADC_SPEED_2X2T'],
  ['SYSclk/2/4', 'ADC_SPEED_2X4T'], ['SYSclk/2/8', 'ADC_SPEED_2X8T'],
  ['SYSclk/2/16', 'ADC_SPEED_2X16T'],
];
export const ADC_PRECISION_OPTIONS = [
  ['12位', '0'], ['11位', '1'], ['10位', '2'], ['9位', '3'], ['8位', '4'],
];

// ===== TIMER (TIMER_COUNT_PIN_Enum / TIMER_CHN_Enum) =====
export const TIMER_COUNT_PIN_OPTIONS = [
  ['T0 P3.4', 'TIMER0_P34'], ['T1 P3.5', 'TIMER1_P35'],
  ['T2 P1.2', 'TIMER2_P12'], ['T3 P0.4', 'TIMER3_P04'], ['T4 P0.6', 'TIMER4_P06'],
];
export const TIMER_CHN_OPTIONS = [
  ['TIM0', 'TIM0'], ['TIM1', 'TIM1'], ['TIM2', 'TIM2'], ['TIM3', 'TIM3'], ['TIM4', 'TIM4'],
];

// ===== I2C / SPI =====
export const I2C_OPTIONS = [
  ['I2C1', 'IIC_1'], ['I2C2', 'IIC_2'], ['I2C3', 'IIC_3'], ['I2C4', 'IIC_4'],
];
export const SPI_OPTIONS = [
  ['SPI1', 'SPI_1'], ['SPI2', 'SPI_2'], ['SPI3', 'SPI_3'], ['SPI4', 'SPI_4'],
];
export const SPI_MODE_OPTIONS = [['主机', '1'], ['从机', '0']];
export const SPI_CPOL_OPTIONS = [['高电平', '1'], ['低电平', '0']];
export const SPI_CPHA_OPTIONS = [['第1边沿', '0'], ['第2边沿', '1']];
export const SPI_SPEED_OPTIONS = [
  ['4分频', '0'], ['8分频', '1'], ['16分频', '2'], ['32分频', '3'],
];
export const SPI_BITORDER_OPTIONS = [['MSB先发', '0'], ['LSB先发', '1']];

// ===== EXTI (EXTI_MODE_Enum / EXTI_PRIORITY_Enum) =====
export const EXTI_MODE_OPTIONS = [
  ['下降沿', 'FALLING_EDGE'], ['上升沿', 'RISING_EDGE'],
  ['低电平', 'LOW_LEVEL'], ['高电平', 'HIGH_LEVEL'],
];
export const EXTI_PRIORITY_OPTIONS = [
  ['最高', 'Highest_priority'], ['第二', 'Second_priority'],
  ['第三', 'Third_priority'], ['最低', 'Lowest_priority'],
];

// ===== 看门狗 =====
export const WDT_ENABLE_OPTIONS = [['使能', '1'], ['关闭', '0']];
export const WDT_IDLE_OPTIONS = [['IDLE停止', '0'], ['IDLE运行', '1']];
export const WDT_SCALE_OPTIONS = [
  ['2分频', 'WDT_SCALE_2'], ['4分频', 'WDT_SCALE_4'], ['8分频', 'WDT_SCALE_8'],
  ['16分频', 'WDT_SCALE_16'], ['32分频', 'WDT_SCALE_32'], ['64分频', 'WDT_SCALE_64'],
  ['128分频', 'WDT_SCALE_128'], ['256分频', 'WDT_SCALE_256'],
];

// ===== 遥控 (KEY_OFFSET_t / ROCKER_OFFSET_t) =====
export const KEY_OPTIONS = [
  ['唤醒键', 'KEY_OFFSET_WKUP'], ['扳机键', 'KEY_OFFSET_1'],
  ['上', 'KEY_OFFSET_UP'], ['下', 'KEY_OFFSET_DOWN'],
  ['左', 'KEY_OFFSET_LEFT'], ['右', 'KEY_OFFSET_RIGHT'],
  ['A', 'KEY_OFFSET_A'], ['B', 'KEY_OFFSET_B'], ['C', 'KEY_OFFSET_C'], ['D', 'KEY_OFFSET_D'],
  ['摇杆1按键', 'KEY_OFFSET_Rocker11'], ['摇杆2按键', 'KEY_OFFSET_Rocker21'],
  ['遥控断连', 'KEY_RCDISCONNECTED'],
];
export const ROCKER_OPTIONS = [
  ['左摇杆垂直', 'ROCKER_LEFT_VERTICAL'], ['左摇杆水平', 'ROCKER_LEFT_HORIZONTAL'],
  ['右摇杆垂直', 'ROCKER_RIGHT_VERTICAL'], ['右摇杆水平', 'ROCKER_RIGHT_HORIZONTAL'],
];

// ===== MCP23017 端口 =====
export const MCP_PORT_OPTIONS = [['端口A', 'portA'], ['端口B', 'portB']];

// ===== RM 机械拓展板端口 (值为 ExpansionBoradControl 参数位置索引) =====
export const EXPANSION_PORT_OPTIONS = [
  ['P60', '0'], ['P62', '1'], ['P64', '2'], ['P66', '3'],
  ['P74', '4'], ['P75', '5'], ['P76', '6'], ['P77', '7'],
];

// 拓展板端口频率（决定该端口是电机还是舵机/摩擦轮）
export const EXPANSION_FREQ_OPTIONS = [
  ['电机 (10000Hz)', '10000'],
  ['舵机/摩擦轮 (50Hz)', '50'],
  ['不使用', '0'],
];

// 机器人类型
export const ROBOT_TYPE_OPTIONS = [
  ['步兵（预设）', 'infantry'],
  ['工程（预设）', 'engineer'],
  ['自定义', 'custom'],
];

// 方向
export const DIR_OPTIONS = [['正转', '1'], ['反转', '0']];

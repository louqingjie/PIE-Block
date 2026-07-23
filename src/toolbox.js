export const toolbox = {
    kind: 'categoryToolbox',
    contents: [
        {
            kind: 'category', name: '引脚 GPIO', colour: '#78c850',
            contents: [
                { kind: 'block', type: 'stc_gpio_init' },
                { kind: 'block', type: 'stc_gpio_write' },
                { kind: 'block', type: 'stc_gpio_toggle' },
                { kind: 'block', type: 'stc_gpio_read' },
            ],
        },
        {
            kind: 'category', name: '延时', colour: '#d4a017',
            contents: [
                { kind: 'block', type: 'stc_delay_ms' },
                { kind: 'block', type: 'stc_delay_us' },
            ],
        },
        {
            kind: 'category', name: '遥控器', colour: '#ab47bc',
            contents: [
                { kind: 'block', type: 'stc_rc_init' },
                { kind: 'block', type: 'stc_rc_key_read' },
                { kind: 'block', type: 'stc_rc_rocker_read' },
            ],
        },
        {
            kind: 'category', name: 'RoboMaster', colour: '#e91e63',
            contents: [
                { kind: 'block', type: 'rm_robot_init' },
                { kind: 'block', type: 'rm_expansion_set_duty' },
                { kind: 'block', type: 'rm_expansion_set_dir' },
                { kind: 'block', type: 'rm_chassis_drive' },
                { kind: 'block', type: 'rm_chassis_stop' },
                { kind: 'block', type: 'rm_servo_init' },
                { kind: 'block', type: 'rm_servo_set' },
                { kind: 'block', type: 'rm_booster_set' },
                { kind: 'block', type: 'rm_limit_value' },
                { kind: 'block', type: 'rm_abs' },
                { kind: 'block', type: 'rm_angle_to_duty' },
            ],
        },
        {
            kind: 'category', name: '逻辑', colour: '#5b80a5',
            contents: [
                { kind: 'block', type: 'controls_if' },
                { kind: 'block', type: 'logic_compare' },
                { kind: 'block', type: 'logic_operation' },
                { kind: 'block', type: 'logic_negate' },
                { kind: 'block', type: 'logic_boolean' },
            ],
        },
        {
            kind: 'category', name: '循环', colour: '#5ba55b',
            contents: [{ kind: 'block', type: 'controls_whileUntil' }],
        },
        {
            kind: 'category', name: '数学', colour: '#9c27b0',
            contents: [
                { kind: 'block', type: 'math_number' },
                { kind: 'block', type: 'math_arithmetic' },
            ],
        },
        { kind: 'category', name: '变量', custom: 'VARIABLE', colour: '#a55b80' },
        {
            kind: 'category', name: '高级', colour: '#607d8b',
            contents: [
                {
                    kind: 'category', name: '串口 UART', colour: '#2db5d4',
                    contents: [{ kind: 'block', type: 'stc_uart_print' }],
                },
                {
                    kind: 'category', name: 'PWM 输出', colour: '#d4a017',
                    contents: [
                        { kind: 'block', type: 'stc_pwm_init' },
                        { kind: 'block', type: 'stc_pwm_set_duty' },
                        { kind: 'block', type: 'stc_pwm_set_freq' },
                    ],
                },
                {
                    kind: 'category', name: 'ADC 采集', colour: '#2db5d4',
                    contents: [
                        { kind: 'block', type: 'stc_adc_init' },
                        { kind: 'block', type: 'stc_adc_read' },
                        { kind: 'block', type: 'stc_adc_average' },
                    ],
                },
                {
                    kind: 'category', name: '定时器', colour: '#9c27b0',
                    contents: [
                        { kind: 'block', type: 'stc_timer_count_init' },
                        { kind: 'block', type: 'stc_timer_count_read' },
                        { kind: 'block', type: 'stc_timer_count_clear' },
                        { kind: 'block', type: 'stc_pit_timer_ms' },
                        { kind: 'block', type: 'stc_pit_timer_clear' },
                    ],
                },
                {
                    kind: 'category', name: '外部中断', colour: '#e91e63',
                    contents: [
                        { kind: 'block', type: 'stc_exti_init' },
                        { kind: 'block', type: 'stc_exti_open' },
                        { kind: 'block', type: 'stc_exti_set_priority' },
                        { kind: 'block', type: 'stc_exti_flag_read' },
                        { kind: 'block', type: 'stc_exti_flag_clear' },
                    ],
                },
                {
                    kind: 'category', name: 'I2C 总线', colour: '#009688',
                    contents: [
                        { kind: 'block', type: 'stc_i2c_init_master' },
                        { kind: 'block', type: 'stc_i2c_change_pin' },
                        { kind: 'block', type: 'stc_i2c_write_reg' },
                        { kind: 'block', type: 'stc_i2c_read_reg' },
                    ],
                },
                {
                    kind: 'category', name: 'SPI 总线', colour: '#03a9f4',
                    contents: [
                        { kind: 'block', type: 'stc_spi_init' },
                        { kind: 'block', type: 'stc_spi_readwrite' },
                    ],
                },
                {
                    kind: 'category', name: 'EEPROM', colour: '#8bc34a',
                    contents: [
                        { kind: 'block', type: 'stc_eeprom_erase' },
                        { kind: 'block', type: 'stc_eeprom_write_byte' },
                        { kind: 'block', type: 'stc_eeprom_read_byte' },
                    ],
                },
                {
                    kind: 'category', name: '看门狗', colour: '#ff5722',
                    contents: [
                        { kind: 'block', type: 'stc_wdog_init' },
                        { kind: 'block', type: 'stc_wdog_clear' },
                    ],
                },
                {
                    kind: 'category', name: '编码器', colour: '#e040fb',
                    contents: [
                        { kind: 'block', type: 'stc_encoder_init' },
                        { kind: 'block', type: 'stc_encoder_read' },
                        { kind: 'block', type: 'stc_encoder_clear' },
                    ],
                },
                {
                    kind: 'category', name: 'BMI088 IMU', colour: '#3f51b5',
                    contents: [
                        { kind: 'block', type: 'stc_bmi088_init' },
                        { kind: 'block', type: 'stc_bmi088_temp' },
                        { kind: 'block', type: 'stc_bmi088_time' },
                    ],
                },
                {
                    kind: 'category', name: '无线通信（已废弃）', colour: '#9e9e9e',
                    contents: [
                        { kind: 'block', type: 'stc_wireless_init' },
                        { kind: 'block', type: 'stc_wireless_link_check' },
                        { kind: 'block', type: 'stc_wireless_handler' },
                    ],
                },
                {
                    kind: 'category', name: 'OLED 屏（已废弃）', colour: '#9e9e9e',
                    contents: [
                        { kind: 'block', type: 'stc_oled_init' },
                        { kind: 'block', type: 'stc_oled_cls' },
                        { kind: 'block', type: 'stc_oled_big_str' },
                        { kind: 'block', type: 'stc_oled_small_str' },
                        { kind: 'block', type: 'stc_oled_float' },
                        { kind: 'block', type: 'stc_oled_onoff' },
                    ],
                },
                {
                    kind: 'category', name: 'LCD 屏（引脚冲突）', colour: '#ff5722',
                    contents: [
                        { kind: 'block', type: 'stc_lcd_init' },
                        { kind: 'block', type: 'stc_lcd_cls' },
                        { kind: 'block', type: 'stc_lcd_str' },
                        { kind: 'block', type: 'stc_lcd_big_str' },
                        { kind: 'block', type: 'stc_lcd_uint' },
                        { kind: 'block', type: 'stc_lcd_float' },
                    ],
                },
            ],
        },
    ],
};

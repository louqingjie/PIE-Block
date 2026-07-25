import { javascriptGenerator } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_pwm_init'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const freq = block.getFieldValue('FREQ');
    const duty = block.getFieldValue('DUTY');
    return `PWM_Init(${pin}, ${freq}, ${duty});\n`;
};

javascriptGenerator.forBlock['stc_pwm_set_duty'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const duty = block.getFieldValue('DUTY');
    return `PWM_SET_Duty(${pin}, ${duty});\n`;
};

javascriptGenerator.forBlock['stc_pwm_set_freq'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const freq = block.getFieldValue('FREQ');
    const duty = block.getFieldValue('DUTY');
    return `PWM_SET_Frequency(${pin}, ${freq}, ${duty});\n`;
};

import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_adc_init'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const speed = block.getFieldValue('SPEED');
    return `ADC_Init(${pin}, ${speed});\n`;
};

javascriptGenerator.forBlock['stc_adc_read'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const precision = block.getFieldValue('PRECISION');
    return [`ADC_Read_Once(${pin}, ${precision})`, Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_adc_average'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const precision = block.getFieldValue('PRECISION');
    const n = block.getFieldValue('N');
    return [`ADC_Average(${pin}, ${precision}, ${n})`, Order.FUNCTION_CALL];
};

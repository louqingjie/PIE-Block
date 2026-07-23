import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_timer_count_init'] = (block) => {
    const pin = block.getFieldValue('PIN');
    return `Timer_Count_Init(${pin});\n`;
};

javascriptGenerator.forBlock['stc_timer_count_read'] = (block) => {
    const pin = block.getFieldValue('PIN');
    return [`Timer_Count_Read(${pin})`, Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_timer_count_clear'] = (block) => {
    const pin = block.getFieldValue('PIN');
    return `Timer_Count_Clear(${pin});\n`;
};

javascriptGenerator.forBlock['stc_pit_timer_ms'] = (block) => {
    const chn = block.getFieldValue('CHN');
    const time = block.getFieldValue('TIME');
    return `PIT_Timer_Ms(${chn}, ${time});\n`;
};

javascriptGenerator.forBlock['stc_pit_timer_clear'] = (block) => {
    const chn = block.getFieldValue('CHN');
    return `PIT_Timer_Clear(${chn});\n`;
};

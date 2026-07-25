import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_exti_init'] = (block) => {
    const port = block.getFieldValue('PORT');
    const pin = block.getFieldValue('PIN');
    const mode = block.getFieldValue('MODE');
    return `GPIO_EXTI_Init(${port}, ${pin}, ${mode});\n`;
};

javascriptGenerator.forBlock['stc_exti_open'] = (block) => {
    const port = block.getFieldValue('PORT');
    const pin = block.getFieldValue('PIN');
    return `GPIO_EXTI_Open(${port}, ${pin});\n`;
};

javascriptGenerator.forBlock['stc_exti_set_priority'] = (block) => {
    const port = block.getFieldValue('PORT');
    const priority = block.getFieldValue('PRIORITY');
    return `GPIO_EXTI_Set_Priority(${port}, ${priority});\n`;
};

javascriptGenerator.forBlock['stc_exti_flag_read'] = (block) => {
    const port = block.getFieldValue('PORT');
    return [`GPIO_EXTI_Flag_Read(${port})`, Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_exti_flag_clear'] = (block) => {
    const port = block.getFieldValue('PORT');
    return `GPIO_EXTI_Flag_Clear(${port});\n`;
};

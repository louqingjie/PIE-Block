import { javascriptGenerator } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_uart_print'] = (block) => {
    const uart = block.getFieldValue('UART');
    const text = block.getFieldValue('TEXT')
        .replace(/\\/g, '\\\\')
        .replace(/"/g, '\\"');
    return `UART_PutStr(${uart}, "${text}");\n`;
};

import { javascriptGenerator } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_delay_ms'] = (block) => {
    return `Ms_Delay(${block.getFieldValue('TIME')});\n`;
};

javascriptGenerator.forBlock['stc_delay_us'] = (block) => {
    return `Us_Delay(${block.getFieldValue('TIME')});\n`;
};

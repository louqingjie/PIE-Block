import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_lcd_init'] = () => 'LCD_Init();\n';
javascriptGenerator.forBlock['stc_lcd_cls'] = () => 'LCD_CLS();\n';

javascriptGenerator.forBlock['stc_lcd_str'] = (block) => {
    const text = esc(block.getFieldValue('TEXT'));
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    return `LCD_P6x8Str(${x}, ${y}, "${text}");\n`;
};

javascriptGenerator.forBlock['stc_lcd_big_str'] = (block) => {
    const text = esc(block.getFieldValue('TEXT'));
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    return `LCD_P8x16Str(${x}, ${y}, "${text}");\n`;
};

javascriptGenerator.forBlock['stc_lcd_uint'] = (block, gen) => {
    const num = gen.valueToCode(block, 'NUM', Order.NONE) || '0';
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    return `LCD_PrintU16(${x}, ${y}, ${num});\n`;
};

javascriptGenerator.forBlock['stc_lcd_float'] = (block, gen) => {
    const num = gen.valueToCode(block, 'NUM', Order.NONE) || '0';
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    const n = block.getFieldValue('N');
    return `LCD_PrintFloat(${x}, ${y}, ${num}, ${n});\n`;
};

function esc(s) {
    return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

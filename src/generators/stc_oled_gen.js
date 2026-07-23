import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_oled_init'] = () => 'oled_init();\n';
javascriptGenerator.forBlock['stc_oled_cls'] = () => 'oled_cls();\n';

javascriptGenerator.forBlock['stc_oled_big_str'] = (block) => {
    const text = esc(block.getFieldValue('TEXT'));
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    return `oled_p8x16_str(${x}, ${y}, "${text}");\n`;
};

javascriptGenerator.forBlock['stc_oled_small_str'] = (block) => {
    const text = esc(block.getFieldValue('TEXT'));
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    return `oled_p6x8_str(${x}, ${y}, "${text}");\n`;
};

javascriptGenerator.forBlock['stc_oled_float'] = (block, gen) => {
    const num = gen.valueToCode(block, 'NUM', Order.NONE) || '0';
    const y = block.getFieldValue('Y');
    const x = block.getFieldValue('X');
    const n = block.getFieldValue('N');
    return `oled_show_float(${x}, ${y}, ${num}, ${n});\n`;
};

javascriptGenerator.forBlock['stc_oled_onoff'] = (block) => {
    return block.getFieldValue('STATE') === 'on' ? 'oled_on();\n' : 'oled_off();\n';
};

function esc(s) {
    return s.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

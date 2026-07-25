import * as Blockly from 'blockly';

Blockly.Blocks['stc_oled_init'] = {
    init() {
        this.appendDummyInput().appendField('初始化 OLED 屏');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('初始化 OLED 显示屏 oled_init()');
    },
};

Blockly.Blocks['stc_oled_cls'] = {
    init() {
        this.appendDummyInput().appendField('OLED 清屏');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('清空 OLED 屏幕 oled_cls()');
    },
};

Blockly.Blocks['stc_oled_big_str'] = {
    init() {
        this.appendDummyInput()
            .appendField('OLED 大字 显示')
            .appendField(new Blockly.FieldTextInput('Hello'), 'TEXT')
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('OLED 8x16 大字体显示字符串 oled_p8x16_str()');
    },
};

Blockly.Blocks['stc_oled_small_str'] = {
    init() {
        this.appendDummyInput()
            .appendField('OLED 小字 显示')
            .appendField(new Blockly.FieldTextInput('Hello'), 'TEXT')
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('OLED 6x8 小字体显示字符串 oled_p6x8_str()');
    },
};

Blockly.Blocks['stc_oled_float'] = {
    init() {
        this.appendValueInput('NUM').setCheck(null).appendField('OLED 显示数值');
        this.appendDummyInput()
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X')
            .appendField('小数位')
            .appendField(new Blockly.FieldNumber(2, 0, 6), 'N');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('OLED 显示浮点数 oled_show_float()');
    },
};

Blockly.Blocks['stc_oled_onoff'] = {
    init() {
        this.appendDummyInput()
            .appendField('OLED')
            .appendField(new Blockly.FieldDropdown([['点亮', 'on'], ['熄灭', 'off']]), 'STATE');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(80);
        this.setTooltip('OLED 点亮/熄灭 oled_on()/oled_off()');
    },
};

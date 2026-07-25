import * as Blockly from 'blockly';

Blockly.Blocks['stc_lcd_init'] = {
    init() {
        this.appendDummyInput().appendField('初始化 LCD 屏');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('初始化 LCD 显示屏 LCD_Init()');
    },
};

Blockly.Blocks['stc_lcd_cls'] = {
    init() {
        this.appendDummyInput().appendField('LCD 清屏');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('清空 LCD 屏幕 LCD_CLS()');
    },
};

Blockly.Blocks['stc_lcd_str'] = {
    init() {
        this.appendDummyInput()
            .appendField('LCD 显示')
            .appendField(new Blockly.FieldTextInput('Hello'), 'TEXT')
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('LCD 6x8 字体显示字符串 LCD_P6x8Str()');
    },
};

Blockly.Blocks['stc_lcd_big_str'] = {
    init() {
        this.appendDummyInput()
            .appendField('LCD 大字显示')
            .appendField(new Blockly.FieldTextInput('Hello'), 'TEXT')
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('LCD 8x16 字体显示字符串 LCD_P8x16Str()');
    },
};

Blockly.Blocks['stc_lcd_uint'] = {
    init() {
        this.appendValueInput('NUM').setCheck(null).appendField('LCD 显示整数');
        this.appendDummyInput()
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('LCD 显示无符号整数 LCD_PrintU16()');
    },
};

Blockly.Blocks['stc_lcd_float'] = {
    init() {
        this.appendValueInput('NUM').setCheck(null).appendField('LCD 显示数值');
        this.appendDummyInput()
            .appendField('行')
            .appendField(new Blockly.FieldNumber(0, 0, 7), 'Y')
            .appendField('列')
            .appendField(new Blockly.FieldNumber(0, 0, 127), 'X')
            .appendField('小数位')
            .appendField(new Blockly.FieldNumber(2, 0, 6), 'N');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(70);
        this.setTooltip('LCD 显示浮点数 LCD_PrintFloat()');
    },
};

import * as Blockly from 'blockly';
import { PORT_OPTIONS, PIN_OPTIONS, MODE_OPTIONS, LEVEL_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_gpio_init'] = {
    init() {
        this.appendDummyInput()
            .appendField('设置引脚')
            .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
            .appendField('.')
            .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN')
            .appendField('为')
            .appendField(new Blockly.FieldDropdown(MODE_OPTIONS), 'MODE');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(120);
        this.setTooltip('初始化 GPIO 引脚工作模式 GPIO_Init()');
    },
};

Blockly.Blocks['stc_gpio_write'] = {
    init() {
        this.appendDummyInput()
            .appendField('引脚')
            .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
            .appendField('.')
            .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN')
            .appendField('输出')
            .appendField(new Blockly.FieldDropdown(LEVEL_OPTIONS), 'LEVEL');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(120);
        this.setTooltip('设置引脚输出电平 GPIO_Write_Bit()');
    },
};

Blockly.Blocks['stc_gpio_toggle'] = {
    init() {
        this.appendDummyInput()
            .appendField('翻转引脚')
            .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
            .appendField('.')
            .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(120);
        this.setTooltip('翻转引脚电平 GPIO_Toggle_Bit()');
    },
};

Blockly.Blocks['stc_gpio_read'] = {
    init() {
        this.appendDummyInput()
            .appendField('读取引脚')
            .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
            .appendField('.')
            .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN');
        this.setOutput(true, null);
        this.setColour(120);
        this.setTooltip('读取引脚电平（返回 0/1）GPIO_Read_Bit()');
    },
};

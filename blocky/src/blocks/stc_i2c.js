import * as Blockly from 'blockly';
import { I2C_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_i2c_init_master'] = {
    init() {
        this.appendDummyInput()
            .appendField('初始化 I2C 主机')
            .appendField(new Blockly.FieldDropdown(I2C_OPTIONS), 'I2C')
            .appendField('速率')
            .appendField(new Blockly.FieldNumber(100000, 1, 1000000), 'RATE')
            .appendField('Hz');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(160);
        this.setTooltip('初始化 I2C 为主机模式 I2C_Init_Master()');
    },
};

Blockly.Blocks['stc_i2c_change_pin'] = {
    init() {
        this.appendDummyInput()
            .appendField('切换 I2C 引脚')
            .appendField(new Blockly.FieldDropdown(I2C_OPTIONS), 'I2C');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(160);
        this.setTooltip('切换 I2C 通道引脚 I2C_Change_Pin()');
    },
};

Blockly.Blocks['stc_i2c_write_reg'] = {
    init() {
        this.appendDummyInput()
            .appendField('I2C 写寄存器 设备地址')
            .appendField(new Blockly.FieldTextInput('0x42'), 'ADDR')
            .appendField('寄存器')
            .appendField(new Blockly.FieldTextInput('0x00'), 'REG');
        this.appendValueInput('VALUE')
            .setCheck(null)
            .appendField('数据');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(160);
        this.setTooltip('向 I2C 设备寄存器写入单字节 I2C_WriteNbyte()');
    },
};

Blockly.Blocks['stc_i2c_read_reg'] = {
    init() {
        this.appendDummyInput()
            .appendField('I2C 读寄存器 设备地址')
            .appendField(new Blockly.FieldTextInput('0x42'), 'ADDR')
            .appendField('寄存器')
            .appendField(new Blockly.FieldTextInput('0x00'), 'REG');
        this.setOutput(true, null);
        this.setColour(160);
        this.setTooltip('从 I2C 设备寄存器读取单字节 I2C_ReadNbyte()');
    },
};

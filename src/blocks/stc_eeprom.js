import * as Blockly from 'blockly';

Blockly.Blocks['stc_eeprom_erase'] = {
    init() {
        this.appendDummyInput()
            .appendField('擦除 EEPROM 扇区 起始地址')
            .appendField(new Blockly.FieldTextInput('0x0000'), 'ADDR');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(100);
        this.setTooltip('擦除 EEPROM 指定扇区 EEPROM_SectorErase()');
    },
};

Blockly.Blocks['stc_eeprom_write_byte'] = {
    init() {
        this.appendDummyInput()
            .appendField('EEPROM 写字节 地址')
            .appendField(new Blockly.FieldTextInput('0x0000'), 'ADDR')
            .appendField('数据');
        this.appendValueInput('VALUE').setCheck(null);
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(100);
        this.setTooltip('向 EEPROM 写入单字节 EEPROM_write_n()');
    },
};

Blockly.Blocks['stc_eeprom_read_byte'] = {
    init() {
        this.appendDummyInput()
            .appendField('EEPROM 读字节 地址')
            .appendField(new Blockly.FieldTextInput('0x0000'), 'ADDR');
        this.setOutput(true, null);
        this.setColour(100);
        this.setTooltip('从 EEPROM 读取单字节 EEPROM_read_n()');
    },
};

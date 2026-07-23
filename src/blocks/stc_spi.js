import * as Blockly from 'blockly';
import {
    SPI_OPTIONS, SPI_MODE_OPTIONS, SPI_CPOL_OPTIONS,
    SPI_CPHA_OPTIONS, SPI_SPEED_OPTIONS, SPI_BITORDER_OPTIONS,
} from '../enums.js';

Blockly.Blocks['stc_spi_init'] = {
    init() {
        this.appendDummyInput()
            .appendField('初始化 SPI')
            .appendField(new Blockly.FieldDropdown(SPI_OPTIONS), 'SPI')
            .appendField('模式')
            .appendField(new Blockly.FieldDropdown(SPI_MODE_OPTIONS), 'MODE')
            .appendField('CPOL')
            .appendField(new Blockly.FieldDropdown(SPI_CPOL_OPTIONS), 'CPOL')
            .appendField('CPHA')
            .appendField(new Blockly.FieldDropdown(SPI_CPHA_OPTIONS), 'CPHA')
            .appendField('速率')
            .appendField(new Blockly.FieldDropdown(SPI_SPEED_OPTIONS), 'SPEED')
            .appendField('位序')
            .appendField(new Blockly.FieldDropdown(SPI_BITORDER_OPTIONS), 'BITORDER');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(190);
        this.setTooltip('初始化 SPI 通道 SPI_Init()');
    },
};

Blockly.Blocks['stc_spi_readwrite'] = {
    init() {
        this.appendValueInput('DATA')
            .setCheck(null)
            .appendField('SPI 收发字节');
        this.setOutput(true, null);
        this.setColour(190);
        this.setTooltip('SPI 收发单字节 SPI_ReadWriteByte()，返回接收到的字节');
    },
};

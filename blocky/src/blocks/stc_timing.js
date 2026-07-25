import * as Blockly from 'blockly';

Blockly.Blocks['stc_delay_ms'] = {
    init() {
        this.appendDummyInput()
            .appendField('延时')
            .appendField(new Blockly.FieldNumber(500, 0, 65535), 'TIME')
            .appendField('毫秒');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(60);
        this.setTooltip('阻塞毫秒延时 Ms_Delay()');
    },
};

Blockly.Blocks['stc_delay_us'] = {
    init() {
        this.appendDummyInput()
            .appendField('延时')
            .appendField(new Blockly.FieldNumber(100, 0, 4294967295), 'TIME')
            .appendField('微秒');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(60);
        this.setTooltip('阻塞微秒延时 Us_Delay()');
    },
};

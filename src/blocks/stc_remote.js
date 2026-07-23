import * as Blockly from 'blockly';
import { KEY_OPTIONS, ROCKER_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_rc_init'] = {
    init() {
        this.appendDummyInput().appendField('初始化遥控接收');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(260);
        this.setTooltip('初始化遥控器数据接收 remote_control_init()');
    },
};

Blockly.Blocks['stc_rc_key_read'] = {
    init() {
        this.appendDummyInput()
            .appendField('遥控按键')
            .appendField(new Blockly.FieldDropdown(KEY_OPTIONS), 'KEY');
        this.setOutput(true, null);
        this.setColour(260);
        this.setTooltip('读取遥控按键状态 RcKeyValueRead()，按下返回 1 松开返回 0');
    },
};

Blockly.Blocks['stc_rc_rocker_read'] = {
    init() {
        this.appendDummyInput()
            .appendField('遥控摇杆')
            .appendField(new Blockly.FieldDropdown(ROCKER_OPTIONS), 'ROCKER');
        this.setOutput(true, null);
        this.setColour(260);
        this.setTooltip('读取遥控摇杆 ADC 值 RcRockerValueRead()');
    },
};

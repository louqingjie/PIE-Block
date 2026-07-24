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

// 遥控按键下降沿：轮询检测「按下→松开」，不使用中断
// 需放在主循环中反复判断；同一循环内对同一按键只应调用一次
Blockly.Blocks['stc_rc_key_falling'] = {
    init() {
        this.appendDummyInput()
            .appendField('遥控按键')
            .appendField(new Blockly.FieldDropdown(KEY_OPTIONS), 'KEY')
            .appendField('下降沿');
        this.setOutput(true, null);
        this.setColour(260);
        this.setTooltip(
            '轮询检测遥控按键下降沿（按下→松开返回 1，否则 0）。'
            + '不使用中断；需在主循环中反复调用。同一循环内同一按键请只判断一次。'
        );
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

// 摇杆值 -> 速度映射：speed = rocker * maxSpeed / 2047
Blockly.Blocks['stc_rc_rocker_to_speed'] = {
    init() {
        this.appendValueInput('ROCKER').setCheck(null).appendField('摇杆值');
        this.appendValueInput('MAX_SPEED').setCheck(null).appendField('映射速度 最大');
        this.setOutput(true, null);
        this.setColour(260);
        this.setInputsInline(true);
        this.setTooltip('将摇杆 ADC 值映射为速度：(int)((float)摇杆 * 最大速度 / 2047)，摇杆范围约 -2047~2047');
    },
};

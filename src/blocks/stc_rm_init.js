import * as Blockly from 'blockly';
import {
    ROBOT_TYPE_OPTIONS, EXPANSION_PORT_OPTIONS, EXPANSION_FREQ_OPTIONS, DIR_OPTIONS,
} from '../enums.js';

// 机器人整体初始化：端口可配置
Blockly.Blocks['rm_robot_init'] = {
    init() {
        this.appendDummyInput()
            .appendField('初始化机器人')
            .appendField(new Blockly.FieldDropdown(ROBOT_TYPE_OPTIONS, (newValue) => {
                this.updateShape_(newValue);
            }), 'TYPE');
        this.appendDummyInput('PORTS')
            .appendField('P60:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F0')
            .appendField(' P62:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F1')
            .appendField(' P64:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F2')
            .appendField(' P66:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F3')
            .appendField(' P74:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F4')
            .appendField(' P75:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F5')
            .appendField(' P76:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F6')
            .appendField(' P77:').appendField(new Blockly.FieldDropdown(EXPANSION_FREQ_OPTIONS), 'F7');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('初始化机器人系统：Board_Init + 遥控 + 串口 + 拓展板端口配置');
        this.updateShape_('infantry');
    },
    updateShape_(type) {
        // 预设端口频率配置
        const presets = {
            infantry: ['10000', '0', '50', '50', '10000', '10000', '10000', '10000'],
            engineer: ['50', '50', '0', '0', '10000', '10000', '10000', '10000'],
            custom: null,
        };
        const freqs = presets[type];
        if (freqs) {
            for (let i = 0; i < 8; i++) {
                this.setFieldValue(freqs[i], 'F' + i);
            }
        }
    },
};

// 设置拓展板端口占空比（端口可选）
Blockly.Blocks['rm_expansion_set_duty'] = {
    init() {
        this.appendDummyInput()
            .appendField('设置端口')
            .appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'PORT')
            .appendField('占空比');
        this.appendValueInput('DUTY').setCheck(null).appendField('值');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('设置机械拓展板指定端口的占空比，其余端口填0停止');
    },
};

// 设置拓展板端口方向
Blockly.Blocks['rm_expansion_set_dir'] = {
    init() {
        this.appendDummyInput()
            .appendField('设置端口')
            .appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'PORT')
            .appendField('方向')
            .appendField(new Blockly.FieldDropdown(DIR_OPTIONS), 'DIR');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('设置机械拓展板指定端口的电机正反转方向');
    },
};

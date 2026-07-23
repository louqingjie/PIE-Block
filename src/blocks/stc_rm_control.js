import * as Blockly from 'blockly';
import { EXPANSION_PORT_OPTIONS, PWM_PIN_OPTIONS, KEY_OPTIONS } from '../enums.js';

// 底盘行驶：四轮端口可选，自动封装差速运算
Blockly.Blocks['rm_chassis_drive'] = {
    init() {
        this.appendDummyInput()
            .appendField('底盘行驶')
            .appendField(' 左前轮').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LF')
            .appendField(' 左后轮').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LB');
        this.appendDummyInput()
            .appendField(' 右前轮').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RF')
            .appendField(' 右后轮').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RB');
        this.appendValueInput('BASE').setCheck(null).appendField('基础速度');
        this.appendValueInput('TURN').setCheck(null).appendField('转向速度');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('底盘差速控制：自动计算四轮速度并发送方向+占空比指令');
    },
};

// 底盘控制（一键模块）：左摇杆映射速度 + 四轮差速
// 参数：四轮 IO、最大速度
Blockly.Blocks['rm_chassis_control'] = {
    init() {
        this.appendDummyInput()
            .appendField('底盘单左摇杆控制')
            .appendField(' 左前').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LF')
            .appendField(' 左后').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LB');
        this.appendDummyInput()
            .appendField(' 右前').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RF')
            .appendField(' 右后').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RB');
        this.appendValueInput('MAX_SPEED').setCheck(null).appendField('最大速度');
        // 步兵默认端口：左前P74 左后P75 右前P76 右后P77
        this.setFieldValue('4', 'LF');
        this.setFieldValue('5', 'LB');
        this.setFieldValue('6', 'RF');
        this.setFieldValue('7', 'RB');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip(
            '一键底盘控制：读取左摇杆（垂直=前进/后退，水平=转向），'
            + '按 摇杆*最大速度/2047 映射后差速驱动四轮。'
            + '默认端口步兵：P74/P75/P76/P77'
        );
    },
};

// 底盘停止
Blockly.Blocks['rm_chassis_stop'] = {
    init() {
        this.appendDummyInput()
            .appendField('底盘停止')
            .appendField(' 左前').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LF')
            .appendField(' 左后').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'LB')
            .appendField(' 右前').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RF')
            .appendField(' 右后').appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'RB');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('底盘四轮全部停止');
    },
};

// 初始化舵机（PWM引脚可选）
Blockly.Blocks['rm_servo_init'] = {
    init() {
        this.appendDummyInput()
            .appendField('初始化舵机')
            .appendField(new Blockly.FieldDropdown(PWM_PIN_OPTIONS), 'PIN')
            .appendField('中值')
            .appendField(new Blockly.FieldNumber(750, 250, 1250), 'DUTY');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('初始化舵机到指定中值位置 PWM_init(引脚, 50, duty)');
    },
};

// 设置舵机角度（PWM引脚可选）
Blockly.Blocks['rm_servo_set'] = {
    init() {
        this.appendDummyInput()
            .appendField('设置舵机')
            .appendField(new Blockly.FieldDropdown(PWM_PIN_OPTIONS), 'PIN')
            .appendField('占空比');
        this.appendValueInput('DUTY').setCheck(null);
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('设置舵机角度 PWM_SET_Frequency(引脚, 50, duty)，范围250~1250');
    },
};

// 设置摩擦轮占空比（两端口可选）
Blockly.Blocks['rm_booster_set'] = {
    init() {
        this.appendDummyInput()
            .appendField('摩擦轮 端口L')
            .appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'PORTL')
            .appendField(' 端口R')
            .appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'PORTR')
            .appendField('占空比');
        this.appendValueInput('DUTY').setCheck(null);
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip('设置摩擦轮占空比。警告：上限1100，必须渐变启动，否则损坏电机');
    },
};

// 射击（单点拨弹）：触发按键上升沿 → 拨弹电机以指定速度运行「单点时长」后停止
Blockly.Blocks['rm_shoot'] = {
    init() {
        this.appendDummyInput()
            .appendField('射击')
            .appendField(' 拨弹电机')
            .appendField(new Blockly.FieldDropdown(EXPANSION_PORT_OPTIONS), 'PORT')
            .appendField(' 触发按键')
            .appendField(new Blockly.FieldDropdown(KEY_OPTIONS), 'KEY');
        this.appendValueInput('SPEED').setCheck(null).appendField('拨弹速度');
        this.appendValueInput('DURATION').setCheck(null).appendField('单点时长(ms)');
        // 步兵默认：拨弹 P60、扳机键
        this.setFieldValue('0', 'PORT');
        this.setFieldValue('KEY_OFFSET_1', 'KEY');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(350);
        this.setTooltip(
            '单点射击：检测触发按键上升沿，拨弹电机以指定速度(0~10000)运行「单点时长」毫秒后停止。'
            + '默认拨弹口 P60、扳机键。注意：阻塞延时期间不会执行其它控制。'
        );
    },
};

// 数值限幅（值积木）
Blockly.Blocks['rm_limit_value'] = {
    init() {
        this.appendValueInput('VAL').setCheck(null).appendField('限幅');
        this.appendDummyInput()
            .appendField('最小').appendField(new Blockly.FieldNumber(-10000, -65535, 65535), 'MIN')
            .appendField('最大').appendField(new Blockly.FieldNumber(10000, -65535, 65535), 'MAX');
        this.setOutput(true, null);
        this.setColour(350);
        this.setTooltip('将数值限制在 [最小, 最大] 范围内');
    },
};

// 取绝对值（值积木）
Blockly.Blocks['rm_abs'] = {
    init() {
        this.appendValueInput('VAL').setCheck(null).appendField('绝对值');
        this.setOutput(true, null);
        this.setColour(350);
        this.setTooltip('取绝对值（整数，生成 pie_abs）');
    },
};

// 角度转占空比（值积木）：输入角度和中值，输出限幅后的占空比
Blockly.Blocks['rm_angle_to_duty'] = {
    init() {
        this.appendValueInput('ANGLE').setCheck(null).appendField('角度');
        this.appendDummyInput()
            .appendField('° 中值')
            .appendField(new Blockly.FieldNumber(750, 250, 1250), 'MID');
        this.setOutput(true, null);
        this.setColour(350);
        this.setTooltip('将角度(-90~90°)转换为舵机占空比：占空比 = 中值 + 角度×5.56，结果限幅250~1250');
    },
};

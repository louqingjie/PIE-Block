import * as Blockly from 'blockly';

Blockly.Blocks['stc_bmi088_init'] = {
    init() {
        this.appendDummyInput().appendField('初始化 BMI088 IMU');
        this.setOutput(true, null);
        this.setColour(220);
        this.setTooltip('初始化 BMI088 六轴惯性测量单元 BMI088_init()，返回错误码（0 为正常）');
    },
};

Blockly.Blocks['stc_bmi088_temp'] = {
    init() {
        this.appendDummyInput().appendField('读取 BMI088 温度');
        this.setOutput(true, null);
        this.setColour(220);
        this.setTooltip('读取 BMI088 芯片温度 get_BMI088_temperate()');
    },
};

Blockly.Blocks['stc_bmi088_time'] = {
    init() {
        this.appendDummyInput().appendField('读取 BMI088 传感器时间');
        this.setOutput(true, null);
        this.setColour(220);
        this.setTooltip('读取 BMI088 传感器时间戳 get_BMI088_sensor_time()');
    },
};

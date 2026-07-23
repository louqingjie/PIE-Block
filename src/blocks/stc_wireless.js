import * as Blockly from 'blockly';

Blockly.Blocks['stc_wireless_init'] = {
    init() {
        this.appendDummyInput().appendField('初始化无线模块');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(240);
        this.setTooltip('初始化 Ci24R1/NRF24L01 无线模块 Ci24R1_Init()');
    },
};

Blockly.Blocks['stc_wireless_link_check'] = {
    init() {
        this.appendDummyInput().appendField('检测无线连接');
        this.setOutput(true, null);
        this.setColour(240);
        this.setTooltip('检测无线模块与单片机是否通信正常 nrf_link_check()');
    },
};

Blockly.Blocks['stc_wireless_handler'] = {
    init() {
        this.appendDummyInput().appendField('处理无线数据');
        this.setPreviousStatement(true, null);
        this.setNextStatement(true, null);
        this.setColour(240);
        this.setTooltip('处理无线数据收发 nrf_handler()');
    },
};

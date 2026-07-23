import * as Blockly from 'blockly';

Blockly.Blocks['stc_encoder_init'] = {
  init() {
    this.appendDummyInput().appendField('初始化编码器');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(300);
    this.setTooltip('初始化旋转编码器 Encoder_Init()');
  },
};

Blockly.Blocks['stc_encoder_read'] = {
  init() {
    this.appendDummyInput().appendField('读取编码器计数');
    this.setOutput(true, null);
    this.setColour(300);
    this.setTooltip('读取编码器累计计数值 Encoder_Count_Read()');
  },
};

Blockly.Blocks['stc_encoder_clear'] = {
  init() {
    this.appendDummyInput().appendField('清零编码器计数');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(300);
    this.setTooltip('清零编码器计数值 Encoder_Clear()');
  },
};

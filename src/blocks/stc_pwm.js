import * as Blockly from 'blockly';
import { PWM_PIN_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_pwm_init'] = {
  init() {
    this.appendDummyInput()
      .appendField('初始化 PWM')
      .appendField(new Blockly.FieldDropdown(PWM_PIN_OPTIONS), 'PIN')
      .appendField('频率')
      .appendField(new Blockly.FieldNumber(1000, 1, 1000000), 'FREQ')
      .appendField('Hz 占空比')
      .appendField(new Blockly.FieldNumber(0, 0, 10000), 'DUTY');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(30);
    this.setTooltip('初始化 PWM 通道引脚、频率与占空比 PWM_Init()');
  },
};

Blockly.Blocks['stc_pwm_set_duty'] = {
  init() {
    this.appendDummyInput()
      .appendField('设置 PWM 占空比')
      .appendField(new Blockly.FieldDropdown(PWM_PIN_OPTIONS), 'PIN')
      .appendField('占空比')
      .appendField(new Blockly.FieldNumber(0, 0, 10000), 'DUTY');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(30);
    this.setTooltip('修改 PWM 占空比 PWM_SET_Duty()');
  },
};

Blockly.Blocks['stc_pwm_set_freq'] = {
  init() {
    this.appendDummyInput()
      .appendField('设置 PWM 频率')
      .appendField(new Blockly.FieldDropdown(PWM_PIN_OPTIONS), 'PIN')
      .appendField('频率')
      .appendField(new Blockly.FieldNumber(1000, 1, 1000000), 'FREQ')
      .appendField('Hz 占空比')
      .appendField(new Blockly.FieldNumber(0, 0, 10000), 'DUTY');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(30);
    this.setTooltip('修改 PWM 频率与占空比 PWM_SET_Frequency()');
  },
};

import * as Blockly from 'blockly';
import {
  PORT_OPTIONS, PIN_OPTIONS,
  EXTI_MODE_OPTIONS, EXTI_PRIORITY_OPTIONS,
} from '../enums.js';

Blockly.Blocks['stc_exti_init'] = {
  init() {
    this.appendDummyInput()
      .appendField('初始化外部中断')
      .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
      .appendField('.')
      .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN')
      .appendField('触发')
      .appendField(new Blockly.FieldDropdown(EXTI_MODE_OPTIONS), 'MODE');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(340);
    this.setTooltip('初始化 GPIO 外部中断 GPIO_EXTI_Init()');
  },
};

Blockly.Blocks['stc_exti_open'] = {
  init() {
    this.appendDummyInput()
      .appendField('使能外部中断')
      .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
      .appendField('.')
      .appendField(new Blockly.FieldDropdown(PIN_OPTIONS), 'PIN');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(340);
    this.setTooltip('使能端口外部中断 GPIO_EXTI_Open()');
  },
};

Blockly.Blocks['stc_exti_set_priority'] = {
  init() {
    this.appendDummyInput()
      .appendField('设置外部中断优先级')
      .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT')
      .appendField('优先级')
      .appendField(new Blockly.FieldDropdown(EXTI_PRIORITY_OPTIONS), 'PRIORITY');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(340);
    this.setTooltip('设置端口外部中断优先级 GPIO_EXTI_Set_Priority()');
  },
};

Blockly.Blocks['stc_exti_flag_read'] = {
  init() {
    this.appendDummyInput()
      .appendField('读取中断标志')
      .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT');
    this.setOutput(true, null);
    this.setColour(340);
    this.setTooltip('读取端口外部中断标志 GPIO_EXTI_Flag_Read()');
  },
};

Blockly.Blocks['stc_exti_flag_clear'] = {
  init() {
    this.appendDummyInput()
      .appendField('清除中断标志')
      .appendField(new Blockly.FieldDropdown(PORT_OPTIONS), 'PORT');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(340);
    this.setTooltip('清除端口外部中断标志 GPIO_EXTI_Flag_Clear()');
  },
};

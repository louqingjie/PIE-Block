import * as Blockly from 'blockly';
import { TIMER_COUNT_PIN_OPTIONS, TIMER_CHN_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_timer_count_init'] = {
  init() {
    this.appendDummyInput()
      .appendField('初始化计数器')
      .appendField(new Blockly.FieldDropdown(TIMER_COUNT_PIN_OPTIONS), 'PIN');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(280);
    this.setTooltip('初始化定时器为外部脉冲计数模式 Timer_Count_Init()');
  },
};

Blockly.Blocks['stc_timer_count_read'] = {
  init() {
    this.appendDummyInput()
      .appendField('读取计数器')
      .appendField(new Blockly.FieldDropdown(TIMER_COUNT_PIN_OPTIONS), 'PIN');
    this.setOutput(true, null);
    this.setColour(280);
    this.setTooltip('读取定时器计数值 Timer_Count_Read()');
  },
};

Blockly.Blocks['stc_timer_count_clear'] = {
  init() {
    this.appendDummyInput()
      .appendField('清零计数器')
      .appendField(new Blockly.FieldDropdown(TIMER_COUNT_PIN_OPTIONS), 'PIN');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(280);
    this.setTooltip('清零定时器计数值 Timer_Count_Clear()');
  },
};

Blockly.Blocks['stc_pit_timer_ms'] = {
  init() {
    this.appendDummyInput()
      .appendField('周期定时')
      .appendField(new Blockly.FieldDropdown(TIMER_CHN_OPTIONS), 'CHN')
      .appendField('定时')
      .appendField(new Blockly.FieldNumber(10, 1, 65535), 'TIME')
      .appendField('ms');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(280);
    this.setTooltip('设置周期定时中断时间 PIT_Timer_Ms()');
  },
};

Blockly.Blocks['stc_pit_timer_clear'] = {
  init() {
    this.appendDummyInput()
      .appendField('清除定时标志')
      .appendField(new Blockly.FieldDropdown(TIMER_CHN_OPTIONS), 'CHN');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(280);
    this.setTooltip('清除周期定时中断标志 PIT_Timer_Clear()');
  },
};

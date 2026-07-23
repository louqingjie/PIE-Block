import * as Blockly from 'blockly';
import { ADC_PIN_OPTIONS, ADC_SPEED_OPTIONS, ADC_PRECISION_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_adc_init'] = {
  init() {
    this.appendDummyInput()
      .appendField('初始化 ADC 引脚')
      .appendField(new Blockly.FieldDropdown(ADC_PIN_OPTIONS), 'PIN')
      .appendField('速度')
      .appendField(new Blockly.FieldDropdown(ADC_SPEED_OPTIONS), 'SPEED');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(200);
    this.setTooltip('初始化 ADC 采集引脚与转换速度 ADC_Init()');
  },
};

Blockly.Blocks['stc_adc_read'] = {
  init() {
    this.appendDummyInput()
      .appendField('读取 ADC')
      .appendField(new Blockly.FieldDropdown(ADC_PIN_OPTIONS), 'PIN')
      .appendField('精度')
      .appendField(new Blockly.FieldDropdown(ADC_PRECISION_OPTIONS), 'PRECISION');
    this.setOutput(true, null);
    this.setColour(200);
    this.setTooltip('读取 ADC 单次转换值 ADC_Read_Once()');
  },
};

Blockly.Blocks['stc_adc_average'] = {
  init() {
    this.appendDummyInput()
      .appendField('读取 ADC 均值')
      .appendField(new Blockly.FieldDropdown(ADC_PIN_OPTIONS), 'PIN')
      .appendField('精度')
      .appendField(new Blockly.FieldDropdown(ADC_PRECISION_OPTIONS), 'PRECISION')
      .appendField('采样次数')
      .appendField(new Blockly.FieldNumber(10, 1, 255), 'N');
    this.setOutput(true, null);
    this.setColour(200);
    this.setTooltip('读取 ADC 多次平均转换值 ADC_Average()');
  },
};

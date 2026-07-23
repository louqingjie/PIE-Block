import * as Blockly from 'blockly';
import { WDT_ENABLE_OPTIONS, WDT_IDLE_OPTIONS, WDT_SCALE_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_wdog_init'] = {
  init() {
    this.appendDummyInput()
      .appendField('初始化看门狗')
      .appendField(new Blockly.FieldDropdown(WDT_ENABLE_OPTIONS), 'ENABLE')
      .appendField('IDLE')
      .appendField(new Blockly.FieldDropdown(WDT_IDLE_OPTIONS), 'IDLE')
      .appendField('分频')
      .appendField(new Blockly.FieldDropdown(WDT_SCALE_OPTIONS), 'SCALE');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(20);
    this.setTooltip('初始化看门狗定时器 WDog_Inilize()');
  },
};

Blockly.Blocks['stc_wdog_clear'] = {
  init() {
    this.appendDummyInput().appendField('喂狗（复位看门狗）');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(20);
    this.setTooltip('喂狗，复位看门狗计数 WDog_Clear()');
  },
};

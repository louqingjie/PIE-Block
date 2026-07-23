import * as Blockly from 'blockly';
import { UART_OPTIONS } from '../enums.js';

Blockly.Blocks['stc_uart_print'] = {
  init() {
    this.appendDummyInput()
      .appendField(new Blockly.FieldDropdown(UART_OPTIONS), 'UART')
      .appendField('发送文本')
      .appendField(new Blockly.FieldTextInput('Hello STC32G'), 'TEXT');
    this.setPreviousStatement(true, null);
    this.setNextStatement(true, null);
    this.setColour(180);
    this.setTooltip('串口发送字符串 UART_PutStr()');
  },
};

import * as Blockly from 'blockly';

// 初始化区容器：代码生成在 Board_Init() 之后、主循环之前
Blockly.Blocks['stc_setup'] = {
  init() {
    this.appendDummyInput().appendField('▶ 初始化区（运行一次）');
    this.appendStatementInput('STACK').setCheck(null);
    this.setColour(0);
    this.setTooltip('此处积木生成在 Board_Init() 之后、while(1) 之前');
    this.setDeletable(false);
    this.setMovable(false);
  },
};

// 主循环区容器：代码生成在 while(1) 内
Blockly.Blocks['stc_loop'] = {
  init() {
    this.appendDummyInput().appendField('🔁 主循环区（重复执行）');
    this.appendStatementInput('STACK').setCheck(null);
    this.setColour(0);
    this.setTooltip('此处积木生成在 while(1) 循环内');
    this.setDeletable(false);
    this.setMovable(false);
  },
};

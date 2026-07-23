import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_gpio_init'] = (block) => {
  const port = block.getFieldValue('PORT');
  const pin = block.getFieldValue('PIN');
  const mode = block.getFieldValue('MODE');
  return `GPIO_Init(${port}, ${pin}, ${mode});\n`;
};

javascriptGenerator.forBlock['stc_gpio_write'] = (block) => {
  const port = block.getFieldValue('PORT');
  const pin = block.getFieldValue('PIN');
  const level = block.getFieldValue('LEVEL');
  return `GPIO_Write_Bit(${port}, ${pin}, ${level});\n`;
};

javascriptGenerator.forBlock['stc_gpio_toggle'] = (block) => {
  const port = block.getFieldValue('PORT');
  const pin = block.getFieldValue('PIN');
  return `GPIO_Toggle_Bit(${port}, ${pin});\n`;
};

javascriptGenerator.forBlock['stc_gpio_read'] = (block) => {
  const port = block.getFieldValue('PORT');
  const pin = block.getFieldValue('PIN');
  return [`GPIO_Read_Bit(${port}, ${pin})`, Order.FUNCTION_CALL];
};

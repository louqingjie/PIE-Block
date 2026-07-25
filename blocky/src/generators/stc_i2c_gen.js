import { javascriptGenerator, Order } from 'blockly/javascript';

// 注意：Order 必须为 ATOMIC（否则按 NONE 不加括号，逗号会被误作参数分隔）

javascriptGenerator.forBlock['stc_i2c_init_master'] = (block) => {
    const i2c = block.getFieldValue('I2C');
    const rate = block.getFieldValue('RATE');
    // WDTA=0(关闭自动递增), EN=1(使能)
    return `I2C_Init_Master(${i2c}, ${rate}, 0, 1);\n`;
};

javascriptGenerator.forBlock['stc_i2c_change_pin'] = (block) => {
    const i2c = block.getFieldValue('I2C');
    return `I2C_Change_Pin(${i2c});\n`;
};

// 单字节写入：用块作用域临时变量规避指针参数
javascriptGenerator.forBlock['stc_i2c_write_reg'] = (block, gen) => {
    const addr = block.getFieldValue('ADDR');
    const reg = block.getFieldValue('REG');
    const value = gen.valueToCode(block, 'VALUE', Order.NONE) || '0';
    return `{ uint8_t _i2c_buf = ${value}; I2C_WriteNbyte(${addr}, ${reg}, &_i2c_buf, 1); }\n`;
};

// 单字节读取：逗号运算符 + 全局临时缓冲区
javascriptGenerator.forBlock['stc_i2c_read_reg'] = (block, gen) => {
    const addr = block.getFieldValue('ADDR');
    const reg = block.getFieldValue('REG');
    gen.definitions_['i2c_read_buf'] = 'volatile uint8_t _i2c_read_buf;';
    return [`(I2C_ReadNbyte(${addr}, ${reg}, &_i2c_read_buf, 1), _i2c_read_buf)`, Order.ATOMIC];
};

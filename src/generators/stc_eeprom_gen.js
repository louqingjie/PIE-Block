import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_eeprom_erase'] = (block) => {
    const addr = block.getFieldValue('ADDR');
    return `EEPROM_SectorErase(${addr});\n`;
};

// 单字节写入：块作用域临时变量
javascriptGenerator.forBlock['stc_eeprom_write_byte'] = (block, gen) => {
    const addr = block.getFieldValue('ADDR');
    const value = gen.valueToCode(block, 'VALUE', Order.NONE) || '0';
    return `{ uint8_t _eeprom_buf = ${value}; EEPROM_write_n(${addr}, &_eeprom_buf, 1); }\n`;
};

// 单字节读取：逗号运算符 + 全局临时缓冲区
javascriptGenerator.forBlock['stc_eeprom_read_byte'] = (block, gen) => {
    const addr = block.getFieldValue('ADDR');
    gen.definitions_['eeprom_read_buf'] = 'volatile uint8_t _eeprom_read_buf;';
    return [`(EEPROM_read_n(${addr}, &_eeprom_read_buf, 1), _eeprom_read_buf)`, Order.ATOMIC];
};

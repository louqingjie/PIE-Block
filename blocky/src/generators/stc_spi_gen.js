import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_spi_init'] = (block) => {
    const spi = block.getFieldValue('SPI');
    const mode = block.getFieldValue('MODE');
    const cpol = block.getFieldValue('CPOL');
    const cpha = block.getFieldValue('CPHA');
    const speed = block.getFieldValue('SPEED');
    const bitorder = block.getFieldValue('BITORDER');
    // SS_CFG=1(自动片选), SPI_EN=1(使能)
    return `SPI_Init(${spi}, 1, ${bitorder}, ${cpol}, ${cpha}, ${speed}, ${mode}, 1);\n`;
};

javascriptGenerator.forBlock['stc_spi_readwrite'] = (block, gen) => {
    const data = gen.valueToCode(block, 'DATA', Order.NONE) || '0';
    return [`SPI_ReadWriteByte(${data})`, Order.FUNCTION_CALL];
};

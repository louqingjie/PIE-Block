import { javascriptGenerator } from 'blockly/javascript';

// 结构体初始化：用块作用域临时结构体规避指针参数
javascriptGenerator.forBlock['stc_wdog_init'] = (block) => {
    const enable = block.getFieldValue('ENABLE');
    const idle = block.getFieldValue('IDLE');
    const scale = block.getFieldValue('SCALE');
    return `{ WDog_InitTypeDef _wdt = { ${enable}, ${idle}, ${scale} }; WDog_Inilize(&_wdt); }\n`;
};

javascriptGenerator.forBlock['stc_wdog_clear'] = () => {
    return 'WDog_Clear();\n';
};

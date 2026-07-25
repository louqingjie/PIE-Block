import { javascriptGenerator, Order } from 'blockly/javascript';

// 容器：仅返回其内部语句块的代码（不递归 next 堆叠块）
javascriptGenerator.forBlock['stc_setup'] = (block, gen) =>
    gen.statementToCode(block, 'STACK');

javascriptGenerator.forBlock['stc_loop'] = (block, gen) =>
    gen.statementToCode(block, 'STACK');

/* -- C 语言化覆盖（默认 JS 生成器语法不完全兼容 C）-- */

// 布尔：JS 的 true/false -> C 的 1/0
javascriptGenerator.forBlock['logic_boolean'] = (block) => {
    return block.getFieldValue('BOOL') === 'TRUE'
        ? ['1', Order.ATOMIC]
        : ['0', Order.ATOMIC];
};

// 比较：JS 的 === / !== -> C 的 == / !=
javascriptGenerator.forBlock['logic_compare'] = (block, gen) => {
    const map = { EQ: '==', NEQ: '!=', LT: '<', LTE: '<=', GT: '>', GTE: '>=' };
    const operator = map[block.getFieldValue('OP')] || '==';
    const order = (operator === '==' || operator === '!=')
        ? Order.EQUALITY : Order.RELATIONAL;
    const a = gen.valueToCode(block, 'A', order) || '0';
    const b = gen.valueToCode(block, 'B', order) || '0';
    return [`${a} ${operator} ${b}`, order];
};

// 变量：声明为全局 volatile int（自动收集到顶部）
javascriptGenerator.forBlock['variables_set'] = (block, gen) => {
    const name = gen.getVariableName(block.getFieldValue('VAR'));
    const value = gen.valueToCode(block, 'VALUE', Order.ASSIGNMENT) || '0';
    gen.definitions_['var_' + name] = `volatile int ${name} = 0;`;
    return `${name} = ${value};\n`;
};

javascriptGenerator.forBlock['variables_get'] = (block, gen) => {
    const name = gen.getVariableName(block.getFieldValue('VAR'));
    gen.definitions_['var_' + name] = `volatile int ${name} = 0;`;
    return [name, Order.ATOMIC];
};

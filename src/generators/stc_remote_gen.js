import { javascriptGenerator, Order } from 'blockly/javascript';

// 按键边沿检测：轮询对比上次/当前状态，不依赖中断
function ensureRcKeyEdgeHelper(gen) {
    gen.definitions_['rc_key_edge'] =
        '/* 遥控按键边沿检测（轮询，非中断） */\n' +
        'static uint8_t _rc_key_last[16] = {0};\n' +
        'uint8_t RcKeyFallingEdge(KEY_OFFSET_t offset)\n' +
        '{\n' +
        '    uint8_t cur;\n' +
        '    uint8_t edge;\n' +
        '    if ((int)offset < 0 || (int)offset > 15)\n' +
        '        return 0;\n' +
        '    cur = RcKeyValueRead(offset) ? 1 : 0;\n' +
        '    edge = (_rc_key_last[offset] && !cur) ? 1 : 0;\n' +
        '    _rc_key_last[offset] = cur;\n' +
        '    return edge;\n' +
        '}\n';
}

javascriptGenerator.forBlock['stc_rc_init'] = () => 'remote_control_init();\n';

javascriptGenerator.forBlock['stc_rc_key_read'] = (block) => {
    const key = block.getFieldValue('KEY');
    return [`RcKeyValueRead(${key})`, Order.FUNCTION_CALL];
};

// 下降沿：上次为按下(1)、本次为松开(0)
javascriptGenerator.forBlock['stc_rc_key_falling'] = (block, gen) => {
    ensureRcKeyEdgeHelper(gen);
    const key = block.getFieldValue('KEY');
    return [`RcKeyFallingEdge(${key})`, Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_rc_rocker_read'] = (block) => {
    const rocker = block.getFieldValue('ROCKER');
    return [`RcRockerValueRead(${rocker})`, Order.FUNCTION_CALL];
};

// speed = (int)((float)rocker * maxSpeed / 2047)
javascriptGenerator.forBlock['stc_rc_rocker_to_speed'] = (block) => {
    const rocker = javascriptGenerator.valueToCode(block, 'ROCKER', Order.NONE) || '0';
    const maxSpeed = javascriptGenerator.valueToCode(block, 'MAX_SPEED', Order.NONE) || '0';
    return [`(int)((float)(${rocker}) * (${maxSpeed}) / 2047)`, Order.FUNCTION_CALL];
};

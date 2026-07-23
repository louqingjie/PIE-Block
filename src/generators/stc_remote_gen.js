import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_rc_init'] = () => 'remote_control_init();\n';

javascriptGenerator.forBlock['stc_rc_key_read'] = (block) => {
    const key = block.getFieldValue('KEY');
    return [`RcKeyValueRead(${key})`, Order.FUNCTION_CALL];
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

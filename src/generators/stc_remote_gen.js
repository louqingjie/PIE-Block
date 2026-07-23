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

import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_encoder_init'] = () => 'Encoder_Init();\n';

javascriptGenerator.forBlock['stc_encoder_read'] = () => {
    return ['Encoder_Count_Read()', Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_encoder_clear'] = () => 'Encoder_Clear();\n';

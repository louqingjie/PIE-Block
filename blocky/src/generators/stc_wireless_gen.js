import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_wireless_init'] = () => 'Ci24R1_Init();\n';

javascriptGenerator.forBlock['stc_wireless_link_check'] = () => {
    return ['nrf_link_check()', Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_wireless_handler'] = () => 'nrf_handler();\n';

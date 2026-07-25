import { javascriptGenerator, Order } from 'blockly/javascript';

javascriptGenerator.forBlock['stc_bmi088_init'] = () => {
    return ['BMI088_init()', Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_bmi088_temp'] = () => {
    return ['get_BMI088_temperate()', Order.FUNCTION_CALL];
};

javascriptGenerator.forBlock['stc_bmi088_time'] = () => {
    return ['get_BMI088_sensor_time()', Order.FUNCTION_CALL];
};

import { javascriptGenerator, Order } from 'blockly/javascript';

// 确保 ExpansionBoradControl 已定义（从 init 生成器导入逻辑）
import { ensureExpansionBoardDef } from './stc_rm_init_gen.js';

// Keil C251 的库 abs 为 reentrant，未声明会链接失败；用自包含实现避免依赖 MATH.H/STDLIB
function ensurePieAbs(gen) {
    gen.definitions_['pie_abs'] =
        'int pie_abs(int x)\n' +
        '{\n' +
        '    return (x < 0) ? -x : x;\n' +
        '}';
}

// 生成四轮差速方向 + 占空比指令
function genChassisDiffDrive(gen, lf, lb, rf, rb, baseExpr, turnExpr) {
    ensureExpansionBoardDef(gen);
    ensurePieAbs(gen);
    gen.definitions_['rm_chassis_vars'] = 'int _base_spd, _turn_spd, _wheel[4];';

    let code = '';
    code += `_base_spd = ${baseExpr};\n`;
    code += `_turn_spd = ${turnExpr};\n`;
    // 四轮：左前=-base-turn, 左后=-base-turn, 右前=base-turn, 右后=base-turn
    code += '_wheel[0] = -_base_spd - _turn_spd;\n';
    code += '_wheel[1] = -_base_spd - _turn_spd;\n';
    code += '_wheel[2] = _base_spd - _turn_spd;\n';
    code += '_wheel[3] = _base_spd - _turn_spd;\n';

    const dirArgs = ['1', '1', '1', '1', '1', '1', '1', '1'];
    dirArgs[lf] = '(_wheel[0] >= 0)';
    dirArgs[lb] = '(_wheel[1] >= 0)';
    dirArgs[rf] = '(_wheel[2] >= 0)';
    dirArgs[rb] = '(_wheel[3] >= 0)';
    code += `ExpansionBoradControl(Dir_Change_Order, ${dirArgs.join(', ')});\n`;
    code += 'Ms_Delay(5);\n';

    const dutyArgs = ['0', '0', '0', '0', '0', '0', '0', '0'];
    dutyArgs[lf] = '(uint16_t)pie_abs(_wheel[0])';
    dutyArgs[lb] = '(uint16_t)pie_abs(_wheel[1])';
    dutyArgs[rf] = '(uint16_t)pie_abs(_wheel[2])';
    dutyArgs[rb] = '(uint16_t)pie_abs(_wheel[3])';
    code += `ExpansionBoradControl(Duty_Change_Order, ${dutyArgs.join(', ')});\n`;
    code += 'Ms_Delay(5);\n';
    return code;
}

// 底盘行驶：四轮差速控制
javascriptGenerator.forBlock['rm_chassis_drive'] = (block, gen) => {
    const lf = parseInt(block.getFieldValue('LF'));
    const lb = parseInt(block.getFieldValue('LB'));
    const rf = parseInt(block.getFieldValue('RF'));
    const rb = parseInt(block.getFieldValue('RB'));
    const base = gen.valueToCode(block, 'BASE', Order.NONE) || '0';
    const turn = gen.valueToCode(block, 'TURN', Order.NONE) || '0';
    return genChassisDiffDrive(gen, lf, lb, rf, rb, base, turn);
};

// 底盘控制一键模块：左摇杆 -> 速度映射 -> 差速
// base = 左摇杆垂直 * max / 2047
// turn = -(左摇杆水平 * max / 2047)  （与步兵 main.c 一致）
javascriptGenerator.forBlock['rm_chassis_control'] = (block, gen) => {
    const lf = parseInt(block.getFieldValue('LF'));
    const lb = parseInt(block.getFieldValue('LB'));
    const rf = parseInt(block.getFieldValue('RF'));
    const rb = parseInt(block.getFieldValue('RB'));
    const maxSpeed = gen.valueToCode(block, 'MAX_SPEED', Order.NONE) || '4000';
    const base = `(int)((float)RcRockerValueRead(ROCKER_LEFT_VERTICAL) * (${maxSpeed}) / 2047)`;
    const turn = `-(int)((float)RcRockerValueRead(ROCKER_LEFT_HORIZONTAL) * (${maxSpeed}) / 2047)`;
    return genChassisDiffDrive(gen, lf, lb, rf, rb, base, turn);
};

// 底盘停止
javascriptGenerator.forBlock['rm_chassis_stop'] = (block, gen) => {
    ensureExpansionBoardDef(gen);
    const lf = parseInt(block.getFieldValue('LF'));
    const lb = parseInt(block.getFieldValue('LB'));
    const rf = parseInt(block.getFieldValue('RF'));
    const rb = parseInt(block.getFieldValue('RB'));
    const args = ['0', '0', '0', '0', '0', '0', '0', '0'];
    // 先停底盘端口
    const dutyArgs = [...args];
    dutyArgs[lf] = '0';
    dutyArgs[lb] = '0';
    dutyArgs[rf] = '0';
    dutyArgs[rb] = '0';
    return `ExpansionBoradControl(Duty_Change_Order, ${dutyArgs.join(', ')});\nMs_Delay(5);\n`;
};

// 初始化舵机
javascriptGenerator.forBlock['rm_servo_init'] = (block) => {
    const pin = block.getFieldValue('PIN');
    const duty = block.getFieldValue('DUTY');
    return `PWM_Init(${pin}, 50, ${duty});\n`;
};

// 设置舵机角度
javascriptGenerator.forBlock['rm_servo_set'] = (block, gen) => {
    const pin = block.getFieldValue('PIN');
    const duty = gen.valueToCode(block, 'DUTY', Order.NONE) || '750';
    return `PWM_SET_Frequency(${pin}, 50, ${duty});\n`;
};

// 设置摩擦轮占空比
javascriptGenerator.forBlock['rm_booster_set'] = (block, gen) => {
    ensureExpansionBoardDef(gen);
    const portL = parseInt(block.getFieldValue('PORTL'));
    const portR = parseInt(block.getFieldValue('PORTR'));
    const duty = gen.valueToCode(block, 'DUTY', Order.NONE) || '0';
    const args = ['0', '0', '0', '0', '0', '0', '0', '0'];
    args[portL] = duty;
    args[portR] = duty;
    return `ExpansionBoradControl(Duty_Change_Order, ${args.join(', ')});\nMs_Delay(5);\n`;
};

// 射击：按键上升沿 → 拨弹速度运行 duration ms → 停止
javascriptGenerator.forBlock['rm_shoot'] = (block, gen) => {
    ensureExpansionBoardDef(gen);
    const port = parseInt(block.getFieldValue('PORT'));
    const key = block.getFieldValue('KEY');
    const speed = gen.valueToCode(block, 'SPEED', Order.NONE) || '0';
    const duration = gen.valueToCode(block, 'DURATION', Order.NONE) || '100';

    gen.definitions_['rm_shoot_vars'] = 'uint8_t _rm_shoot_last_key = 0;';

    const runArgs = ['0', '0', '0', '0', '0', '0', '0', '0'];
    runArgs[port] = `((${speed}) < 0 ? 0 : ((${speed}) > 10000 ? 10000 : (${speed})))`;
    const stopArgs = ['0', '0', '0', '0', '0', '0', '0', '0'];

    let code = '';
    code += `if (RcKeyValueRead(${key}) && !_rm_shoot_last_key) {\n`;
    code += `  ExpansionBoradControl(Duty_Change_Order, ${runArgs.join(', ')});\n`;
    code += `  Ms_Delay(${duration});\n`;
    code += `  ExpansionBoradControl(Duty_Change_Order, ${stopArgs.join(', ')});\n`;
    code += '}\n';
    code += `_rm_shoot_last_key = RcKeyValueRead(${key});\n`;
    return code;
};

// 数值限幅
javascriptGenerator.forBlock['rm_limit_value'] = (block, gen) => {
    const val = gen.valueToCode(block, 'VAL', Order.NONE) || '0';
    const min = block.getFieldValue('MIN');
    const max = block.getFieldValue('MAX');
    return [`((${val}) < (${min}) ? (${min}) : ((${val}) > (${max}) ? (${max}) : (${val})))`, Order.NONE];
};

// 取绝对值（自包含 pie_abs，不依赖 Keil 库 abs）
javascriptGenerator.forBlock['rm_abs'] = (block, gen) => {
    ensurePieAbs(gen);
    const val = gen.valueToCode(block, 'VAL', Order.NONE) || '0';
    return [`pie_abs(${val})`, Order.FUNCTION_CALL];
};

// 角度转占空比: duty = mid + angle * (500/90), 限幅250~1250
javascriptGenerator.forBlock['rm_angle_to_duty'] = (block, gen) => {
    const angle = gen.valueToCode(block, 'ANGLE', Order.NONE) || '0';
    const mid = block.getFieldValue('MID');
    // 500/90 ≈ 5.5556，±90°对应±500占空比变化
    const expr = `(${mid} + (int)((${angle}) * 5.5556f))`;
    return [`((${expr}) < 250 ? 250 : ((${expr}) > 1250 ? 1250 : (${expr})))`, Order.NONE];
};


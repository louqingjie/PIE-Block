import { javascriptGenerator, Order } from 'blockly/javascript';

// 确保 ExpansionBoradControl 已定义（从 init 生成器导入逻辑）
import { ensureExpansionBoardDef } from './stc_rm_init_gen.js';

// 底盘行驶：四轮差速控制
javascriptGenerator.forBlock['rm_chassis_drive'] = (block, gen) => {
  ensureExpansionBoardDef(gen);
  const lf = parseInt(block.getFieldValue('LF'));
  const lb = parseInt(block.getFieldValue('LB'));
  const rf = parseInt(block.getFieldValue('RF'));
  const rb = parseInt(block.getFieldValue('RB'));
  const base = gen.valueToCode(block, 'BASE', Order.NONE) || '0';
  const turn = gen.valueToCode(block, 'TURN', Order.NONE) || '0';

  // 四轮速度：左前=-base-turn, 左后=-base-turn, 右前=base-turn, 右后=base-turn
  // 使用全局临时变量避免重复计算
  gen.definitions_['rm_chassis_vars'] = 'int _base_spd, _turn_spd, _wheel[4];';

  let code = '';
  code += `_base_spd = ${base};\n`;
  code += `_turn_spd = ${turn};\n`;
  code += '_wheel[0] = -_base_spd - _turn_spd;\n';  // LF
  code += '_wheel[1] = -_base_spd - _turn_spd;\n';  // LB
  code += '_wheel[2] = _base_spd - _turn_spd;\n';   // RF
  code += '_wheel[3] = _base_spd - _turn_spd;\n';   // RB

  // 方向指令
  const dirArgs = ['1', '1', '1', '1', '1', '1', '1', '1'];
  dirArgs[lf] = '(_wheel[0] >= 0)';
  dirArgs[lb] = '(_wheel[1] >= 0)';
  dirArgs[rf] = '(_wheel[2] >= 0)';
  dirArgs[rb] = '(_wheel[3] >= 0)';
  code += `ExpansionBoradControl(Dir_Change_Order, ${dirArgs.join(', ')});\n`;
  code += 'Ms_Delay(5);\n';

  // 占空比指令
  const dutyArgs = ['0', '0', '0', '0', '0', '0', '0', '0'];
  dutyArgs[lf] = '(uint16_t)abs(_wheel[0])';
  dutyArgs[lb] = '(uint16_t)abs(_wheel[1])';
  dutyArgs[rf] = '(uint16_t)abs(_wheel[2])';
  dutyArgs[rb] = '(uint16_t)abs(_wheel[3])';
  code += `ExpansionBoradControl(Duty_Change_Order, ${dutyArgs.join(', ')});\n`;
  code += 'Ms_Delay(5);\n';

  return code;
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

// 数值限幅
javascriptGenerator.forBlock['rm_limit_value'] = (block, gen) => {
  const val = gen.valueToCode(block, 'VAL', Order.NONE) || '0';
  const min = block.getFieldValue('MIN');
  const max = block.getFieldValue('MAX');
  return [`((${val}) < (${min}) ? (${min}) : ((${val}) > (${max}) ? (${max}) : (${val})))`, Order.NONE];
};

// 取绝对值
javascriptGenerator.forBlock['rm_abs'] = (block, gen) => {
  const val = gen.valueToCode(block, 'VAL', Order.NONE) || '0';
  return [`abs(${val})`, Order.FUNCTION_CALL];
};

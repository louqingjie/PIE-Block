import { javascriptGenerator, Order } from 'blockly/javascript';

// 生成 ExpansionBoradControl 的函数定义和宏定义（自动注入到全局区）
export function ensureExpansionBoardDef(gen) {
  gen.definitions_['rm_expansion_def'] = `
#define COMM_HEADER_1 0xAB
#define COMM_HEADER_2 0xBC
#define COMM_END_1 0xCD
#define COMM_END_2 0xDE
#define Init_Order 0xAA
#define Duty_Change_Order 0xBB
#define Freq_Change_Order 0xCC
#define Dir_Change_Order 0xDD
#define Zero_Order 0xEE
uint16_t control_data[8] = {0};
uint16_t motor_dir[8] = {0};
uint8_t control_command = 0x00;
void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64, uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76, uint16_t data_p77)
{
    uint8_t i = 0;
    uint8_t control_frame_pack[21] = {0};
    control_frame_pack[0] = COMM_HEADER_1;
    control_frame_pack[1] = COMM_HEADER_2;
    control_frame_pack[19] = COMM_END_1;
    control_frame_pack[20] = COMM_END_2;
    control_frame_pack[2] = control_cmd;
    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);
    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);
    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);
    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);
    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);
    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);
    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);
    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);
    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);
    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);
    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);
    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);
    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);
    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);
    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);
    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);
    for (i = 0; i < 21; i++)
        UART_PutChar(UART_1, control_frame_pack[i]);
}`;
}

// 机器人初始化
javascriptGenerator.forBlock['rm_robot_init'] = (block, gen) => {
  ensureExpansionBoardDef(gen);
  const freqs = [];
  for (let i = 0; i < 8; i++) {
    freqs.push(block.getFieldValue('F' + i));
  }
  // 频率0表示不使用，用0占位
  const initArgs = freqs.map((f) => (f === '0' ? '0' : f)).join(', ');
  let code = '';
  code += 'Board_Init();\n';
  code += 'GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);\n';
  code += 'GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);\n';
  code += 'remote_control_init();\n';
  code += 'GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);\n';
  code += 'UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);\n';
  code += `ExpansionBoradControl(Init_Order, ${initArgs});\n`;
  code += 'Ms_Delay(20);\n';
  return code;
};

// 设置拓展板端口占空比
javascriptGenerator.forBlock['rm_expansion_set_duty'] = (block, gen) => {
  ensureExpansionBoardDef(gen);
  const portIdx = parseInt(block.getFieldValue('PORT'));
  const duty = gen.valueToCode(block, 'DUTY', Order.NONE) || '0';
  const args = ['0', '0', '0', '0', '0', '0', '0', '0'];
  args[portIdx] = duty;
  return `ExpansionBoradControl(Duty_Change_Order, ${args.join(', ')});\nMs_Delay(5);\n`;
};

// 设置拓展板端口方向
javascriptGenerator.forBlock['rm_expansion_set_dir'] = (block, gen) => {
  ensureExpansionBoardDef(gen);
  const portIdx = parseInt(block.getFieldValue('PORT'));
  const dir = block.getFieldValue('DIR');
  const args = ['1', '1', '1', '1', '1', '1', '1', '1'];
  args[portIdx] = dir;
  return `ExpansionBoradControl(Dir_Change_Order, ${args.join(', ')});\nMs_Delay(5);\n`;
};

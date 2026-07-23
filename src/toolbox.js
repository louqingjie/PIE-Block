export const toolbox = {
  kind: 'categoryToolbox',
  contents: [
    {
      kind: 'category', name: '引脚 GPIO', colour: '#78c850',
      contents: [
        { kind: 'block', type: 'stc_gpio_init' },
        { kind: 'block', type: 'stc_gpio_write' },
        { kind: 'block', type: 'stc_gpio_toggle' },
        { kind: 'block', type: 'stc_gpio_read' },
      ],
    },
    {
      kind: 'category', name: '延时', colour: '#d4a017',
      contents: [
        { kind: 'block', type: 'stc_delay_ms' },
        { kind: 'block', type: 'stc_delay_us' },
      ],
    },
    {
      kind: 'category', name: '串口 UART', colour: '#2db5d4',
      contents: [{ kind: 'block', type: 'stc_uart_print' }],
    },
    {
      kind: 'category', name: '逻辑', colour: '#5b80a5',
      contents: [
        { kind: 'block', type: 'controls_if' },
        { kind: 'block', type: 'logic_compare' },
        { kind: 'block', type: 'logic_operation' },
        { kind: 'block', type: 'logic_negate' },
        { kind: 'block', type: 'logic_boolean' },
      ],
    },
    {
      kind: 'category', name: '循环', colour: '#5ba55b',
      contents: [{ kind: 'block', type: 'controls_whileUntil' }],
    },
    {
      kind: 'category', name: '数学', colour: '#9c27b0',
      contents: [
        { kind: 'block', type: 'math_number' },
        { kind: 'block', type: 'math_arithmetic' },
      ],
    },
    { kind: 'category', name: '变量', custom: 'VARIABLE', colour: '#a55b80' },
  ],
};

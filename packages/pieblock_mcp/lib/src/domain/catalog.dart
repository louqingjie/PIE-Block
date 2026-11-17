/// 字段目录：把 `.pieproj` 里的 JSON 路径翻译成「人话 + 约束 + 所属步骤」。
///
/// 手写而不是反射，原因是 Dart 没有运行时反射，而 `ProjectValidator` 只输出
/// `ValidationIssue`、不提供字段元数据。手写的代价是可能漏字段，所以有两条
/// 守卫（见 `test/catalog_test.dart`）：
///
/// 1. 目录里的每条 JSON 路径必须能在对应项目的 `toJson()` 中命中，防拼错；
/// 2. 校验器实际报出的每个 `fieldPath` 必须能在目录里找到对应字段，暴露缺口。
///
/// 目录只描述「能不能改、叫什么、属于哪一步、大致范围」，**不做值合法性
/// 判定**——那仍然由 `ProjectConfig.fromJson` 与 `ProjectValidator` 负责，
/// 见 `patch.dart` 的往返校验。
library;

/// 字段的值类型。只用于给模型提示与做粗类型检查，不替代真实解析。
enum McpFieldKind { integer, number, boolean, string, text }

/// 目录条目。
class McpFieldSpec {
  const McpFieldSpec({
    required this.pattern,
    required this.label,
    required this.stepId,
    this.kind = McpFieldKind.string,
    this.issuePattern,
    this.allowedValues,
    this.minimum,
    this.maximum,
    this.unit,
    this.writable = true,
    this.note,
  });

  /// JSON 路径模式：`[n]` 表示数组下标，`*` 表示任意一段（数组下标或对象键）。
  ///
  /// 例：`yaw[*].pin`、`pwm.pin_roles.*`、`modes[*].actions[*].mode`。
  final String pattern;

  /// 中文名，直接用于补丁 diff 与 `get_context` 的展示。
  final String label;

  /// 所属向导步骤，取值与 `AppController.stepIds` 一致。
  final String stepId;

  final McpFieldKind kind;

  /// 校验器使用的路径模式。缺省视为与 [pattern] 相同。
  ///
  /// 校验器的路径是「面向界面」的（`gimbal.yaw.0.pin`、`controls.trigger_key`），
  /// 与存档结构（`yaw[0].pin`、`trigger_key`）并不总是一致，必须单独给出。
  final String? issuePattern;

  /// 枚举字段的字面量取值。
  final List<String>? allowedValues;

  final num? minimum;
  final num? maximum;
  final String? unit;

  /// 是否允许 AI 改写。id、派生字段一律只读。
  final bool writable;

  /// 给模型看的一句补充说明（单位换算、联动关系等）。
  final String? note;

  bool get isArrayElement => pattern.contains('[*]');

  Map<String, Object?> toJson() => {
    'path': pattern,
    'label': label,
    'step': stepId,
    'kind': kind.name,
    if (allowedValues != null) 'allowedValues': allowedValues,
    if (minimum != null) 'minimum': minimum,
    if (maximum != null) 'maximum': maximum,
    if (unit != null) 'unit': unit,
    if (!writable) 'writable': false,
    if (note != null) 'note': note,
  };
}

/// 全部已知字段。
abstract final class McpFieldCatalog {
  /// 枚举字面量，供目录与错误提示复用。
  static const directions = ['forward', 'reverse'];
  static const pinRoles = ['motor', 'servo', 'friction', 'jitterMotor', 'unused'];
  static const pwmFrequencies = ['hz50', 'hz10000'];
  static const switchStrategies = ['cycle', 'direct'];
  static const driveTypes = ['servo', 'motor'];
  static const debugDriveTypes = ['motor', 'servo', 'friction'];
  static const arrowBehaviors = ['move', 'sprint', 'other'];
  static const feedModes = ['blockingOpenLoop', 'visualClosedLoop'];
  static const frictionModes = ['brushlessEsc', 'disabled'];
  static const controlModes = [
    'direct',
    'incremental',
    'speed',
    'accelerate',
    'single',
    'continuous',
    'frictionToggle',
    'frictionStep',
    'frictionContinuous',
    'frictionAxis',
  ];
  static const actionInputKinds = ['remote', 'unspecified'];
  static const actionOutputKinds = ['pin', 'integer', 'rational'];
  static const overlapModes = ['highest', 'lowest', 'nearest'];

  /// 遥控器按键字面量。
  static const remoteKeys = [
    'E',
    '↑',
    '↓',
    '←',
    '→',
    'A',
    'B',
    'C',
    'D',
    'LC',
    'RC',
    'LX',
    'LY',
    'RX',
    'RY',
  ];

  static const expansionPins = [
    'P60',
    'P62',
    'P64',
    'P66',
    'P74',
    'P75',
    'P76',
    'P77',
  ];
  static const mainServoPins = ['MP03', 'MP74'];

  static const _wheelPins = [
    'P60 P61',
    'P62 P63',
    'P74 P24',
    'P75 P25',
    'P76 P26',
    'P77 P27',
  ];

  /// 目录里有 `for` 展开与字符串插值，只能是 final 不能是 const。
  static final specs = <McpFieldSpec>[
    // ---- 遥控器与底盘（步兵 / 工程共用）----
    McpFieldSpec(
      pattern: 'remote.channel',
      label: '遥控器通道号',
      stepId: 'remote',
      kind: McpFieldKind.integer,
      minimum: 0,
      maximum: 125,
      note: '必填。0–125 为合法通道。',
    ),
    McpFieldSpec(
      pattern: 'remote.deadzone',
      label: '摇杆死区',
      stepId: 'remote',
      kind: McpFieldKind.integer,
      minimum: 0,
      maximum: 2047,
      note: '建议不超过 500，超过后校验器会给提醒。',
    ),
    McpFieldSpec(
      pattern: 'chassis.enabled',
      label: '启用底盘',
      stepId: 'remote',
      kind: McpFieldKind.boolean,
      note: '步兵项目必须为 true。',
    ),
    for (final wheel in const ['left_front', 'left_rear', 'right_front', 'right_rear'])
      ...[
        McpFieldSpec(
          pattern: 'chassis.$wheel.pin',
          label: '${_wheelLabel(wheel)}轮引脚',
          stepId: 'remote',
          allowedValues: _wheelPins,
          note: '形如 "P74 P24"，两个引脚之间用空格分隔。',
        ),
        McpFieldSpec(
          pattern: 'chassis.$wheel.direction',
          label: '${_wheelLabel(wheel)}轮方向',
          stepId: 'remote',
          allowedValues: directions,
        ),
      ],
    McpFieldSpec(
      pattern: 'chassis.normal_speed',
      label: '普通速度',
      stepId: 'remote',
      kind: McpFieldKind.integer,
      minimum: 0,
      maximum: 10000,
    ),
    McpFieldSpec(
      pattern: 'chassis.sprint_speed',
      label: '冲刺速度',
      stepId: 'remote',
      kind: McpFieldKind.integer,
      minimum: 0,
      maximum: 10000,
      note: '仅在启用冲刺时有意义。',
    ),
    McpFieldSpec(
      pattern: 'chassis.sprint_enabled',
      label: '启用冲刺',
      stepId: 'remote',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'chassis.turn_reversed',
      label: '转向反向',
      stepId: 'remote',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'chassis.turn_sensitivity',
      label: '转向灵敏度',
      stepId: 'remote',
      kind: McpFieldKind.integer,
      unit: '%',
      note: '缺省 100。',
    ),

    // ---- 步兵：拨弹与云台 ----
    McpFieldSpec(
      pattern: 'feeder_pin',
      label: '拨弹电机引脚',
      stepId: 'mechanism',
      issuePattern: 'mechanism.feeder_pin',
      allowedValues: expansionPins,
    ),
    McpFieldSpec(
      pattern: 'feeder_direction',
      label: '拨弹方向',
      stepId: 'mechanism',
      issuePattern: 'mechanism.feeder_direction',
      allowedValues: directions,
    ),
    for (final axis in const ['yaw', 'pitch']) ...[
      McpFieldSpec(
        pattern: axis,
        label: '${_axisLabel(axis)}执行器列表',
        stepId: 'mechanism',
        note: '可整段替换；每个元素形如 '
            '{drive, pin, direction, mid_offset, min_limit, max_limit}。',
      ),
      McpFieldSpec(
        pattern: '$axis[*]',
        label: '${_axisLabel(axis)}执行器',
        stepId: 'mechanism',
        note: '元素形如 {drive, pin, direction, mid_offset, min_limit, max_limit}。',
      ),
      McpFieldSpec(
        pattern: '$axis[*].drive',
        label: '${_axisLabel(axis)}执行器类型',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.drive',
        allowedValues: driveTypes,
      ),
      McpFieldSpec(
        pattern: '$axis[*].pin',
        label: '${_axisLabel(axis)}引脚',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.pin',
        note: '舵机用 MP03/MP74，电机用扩展板引脚。',
      ),
      McpFieldSpec(
        pattern: '$axis[*].direction',
        label: '${_axisLabel(axis)}方向',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.direction',
        allowedValues: directions,
      ),
      McpFieldSpec(
        pattern: '$axis[*].mid_offset',
        label: '${_axisLabel(axis)}中位偏移',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.mid_offset',
        kind: McpFieldKind.integer,
      ),
      McpFieldSpec(
        pattern: '$axis[*].min_limit',
        label: '${_axisLabel(axis)}角度下限',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.min_limit',
        kind: McpFieldKind.integer,
        unit: '°',
      ),
      McpFieldSpec(
        pattern: '$axis[*].max_limit',
        label: '${_axisLabel(axis)}角度上限',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.*.max_limit',
        kind: McpFieldKind.integer,
        unit: '°',
      ),
      McpFieldSpec(
        pattern: '${axis}_sensitivity',
        label: '${_axisLabel(axis)}灵敏度',
        stepId: 'mechanism',
        issuePattern: 'gimbal.$axis.sensitivity',
        kind: McpFieldKind.integer,
        unit: '%',
        note: '缺省 100。',
      ),
    ],

    // ---- 步兵：按键与摩擦轮 ----
    McpFieldSpec(
      pattern: 'arrow_behavior',
      label: '方向键行为',
      stepId: 'controls',
      issuePattern: 'controls.arrow_behavior',
      allowedValues: arrowBehaviors,
    ),
    McpFieldSpec(
      pattern: 'feed_mode',
      label: '拨弹模式',
      stepId: 'controls',
      issuePattern: 'controls.feed_mode',
      allowedValues: feedModes,
    ),
    McpFieldSpec(
      pattern: 'trigger_key',
      label: '扳机键',
      stepId: 'controls',
      issuePattern: 'controls.trigger_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'reverse_feed_key',
      label: '反转拨弹键',
      stepId: 'controls',
      issuePattern: 'controls.reverse_feed_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'trigger_speed',
      label: '扳机转速',
      stepId: 'controls',
      issuePattern: 'controls.trigger_speed',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'trigger_time_ms',
      label: '扳机持续时间',
      stepId: 'controls',
      issuePattern: 'controls.trigger_time_ms',
      kind: McpFieldKind.integer,
      unit: 'ms',
    ),
    McpFieldSpec(
      pattern: 'friction_mode',
      label: '摩擦轮模式',
      stepId: 'controls',
      issuePattern: 'controls.friction_mode',
      allowedValues: frictionModes,
    ),
    McpFieldSpec(
      pattern: 'friction_key',
      label: '摩擦轮启停键',
      stepId: 'controls',
      issuePattern: 'controls.friction_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'friction_up_key',
      label: '摩擦轮升档键',
      stepId: 'controls',
      issuePattern: 'controls.friction_up_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'friction_down_key',
      label: '摩擦轮降档键',
      stepId: 'controls',
      issuePattern: 'controls.friction_down_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'friction_p64_max_duty',
      label: 'P64 满油占空比',
      stepId: 'controls',
      issuePattern: 'controls.friction_p64_max_duty',
      kind: McpFieldKind.integer,
      minimum: 500,
      maximum: 800,
      note: '油门 100% 时输出的占空比；启动值固定 500，低于 650 只给提醒。',
    ),
    McpFieldSpec(
      pattern: 'friction_p66_max_duty',
      label: 'P66 满油占空比',
      stepId: 'controls',
      issuePattern: 'controls.friction_p66_max_duty',
      kind: McpFieldKind.integer,
      minimum: 500,
      maximum: 800,
      note: '与 P64 分开配置，用于补偿两侧机械差异。',
    ),
    McpFieldSpec(
      pattern: 'friction_level_step',
      label: '摩擦轮档位步长',
      stepId: 'controls',
      issuePattern: 'controls.friction_level_step',
      kind: McpFieldKind.integer,
      minimum: 1,
      maximum: 100,
      unit: '%',
    ),
    McpFieldSpec(
      pattern: 'zero_enabled',
      label: '开机归零',
      stepId: 'controls',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'buzzer_disabled',
      label: '关闭蜂鸣器',
      stepId: 'controls',
      kind: McpFieldKind.boolean,
    ),

    // ---- 工程：PWM 与引脚角色 ----
    McpFieldSpec(
      pattern: 'pwm.pwma',
      label: 'PWMA 频率',
      stepId: 'pwm',
      allowedValues: pwmFrequencies,
      note: '使用摩擦轮控制时必须为 hz50。',
    ),
    McpFieldSpec(
      pattern: 'pwm.pwmb',
      label: 'PWMB 频率',
      stepId: 'pwm',
      allowedValues: pwmFrequencies,
      note: '使用摩擦轮控制时必须为 hz50。',
    ),
    McpFieldSpec(
      pattern: 'pwm.buzzer_disabled',
      label: '关闭蜂鸣器',
      stepId: 'pwm',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'pwm.pin_roles.*',
      label: '引脚输出角色',
      stepId: 'pwm',
      allowedValues: pinRoles,
      note: '键是引脚名（P60…MP74），不能新增或删除引脚，只能改角色。',
    ),
    McpFieldSpec(
      pattern: 'pwm.servo_mids.*',
      label: '舵机中位',
      stepId: 'pwm',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'pwm.servo_min_limits.*',
      label: '舵机角度下限',
      stepId: 'pwm',
      kind: McpFieldKind.integer,
      unit: '°',
    ),
    McpFieldSpec(
      pattern: 'pwm.servo_max_limits.*',
      label: '舵机角度上限',
      stepId: 'pwm',
      kind: McpFieldKind.integer,
      unit: '°',
    ),
    McpFieldSpec(
      pattern: 'pwm.friction_max_duties.*',
      label: '摩擦轮满油占空比',
      stepId: 'pwm',
      kind: McpFieldKind.integer,
      minimum: 500,
      maximum: 800,
    ),

    // ---- 工程：模式与动作 ----
    McpFieldSpec(
      pattern: 'mode_count',
      label: '模式数量',
      stepId: 'strategy',
      issuePattern: 'modes.count',
      kind: McpFieldKind.integer,
      minimum: 1,
      maximum: 4,
    ),
    McpFieldSpec(
      pattern: 'switch_strategy',
      label: '切档方式',
      stepId: 'strategy',
      issuePattern: 'modes.switch_strategy',
      allowedValues: switchStrategies,
    ),
    McpFieldSpec(
      pattern: 'mode_switch_key',
      label: '循环切档键',
      stepId: 'strategy',
      issuePattern: 'modes.switch_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'modes',
      label: '模式列表',
      stepId: 'mappings',
      issuePattern: 'modes',
      note: '可整段替换；每个元素形如 {id, preserve_chassis, actions, action_tables}。',
    ),
    McpFieldSpec(
      pattern: 'mode_keys',
      label: '模式直选键列表',
      stepId: 'strategy',
      note: '定长 4 项，按模式序号填按键。',
    ),
    McpFieldSpec(
      pattern: 'modes[*]',
      label: '单个模式',
      stepId: 'mappings',
      issuePattern: 'modes.*',
      note: '元素形如 {id, preserve_chassis, actions, action_tables}。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions',
      label: '动作列表',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions',
      note: '可整段替换；每个元素形如 '
          '{id, input_kind, key, output_kind, pin, variable, expression, mode, parameter}。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*]',
      label: '单个动作',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*]',
      label: '单张动作表',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables',
      label: '动作表列表',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables',
      note: '可整段替换；每个元素形如 {id, key, prev_key, steps, rows, wrap}。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].rows',
      label: '动作表行列表',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.rows',
      note: '行数决定引脚数量，每行 {pin, values}。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].rows[*].values',
      label: '各档目标值',
      stepId: 'mappings',
      note: '长度等于所属动作表的档位数。',
    ),
    McpFieldSpec(
      pattern: 'mode_keys[*]',
      label: '模式直选键',
      stepId: 'strategy',
      issuePattern: 'modes.keys.*',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'modes[*].id',
      label: '模式 id',
      stepId: 'mappings',
      writable: false,
      note: '内部标识，保持原值；删除/新增模式请整段替换 modes 数组。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].preserve_chassis',
      label: '保留底盘输出',
      stepId: 'mappings',
      issuePattern: 'modes.*.preserve_chassis',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].id',
      label: '动作 id',
      stepId: 'mappings',
      writable: false,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].input_kind',
      label: '动作输入来源',
      stepId: 'mappings',
      allowedValues: actionInputKinds,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].key',
      label: '动作输入',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*.key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].output_kind',
      label: '输出目标类型',
      stepId: 'mappings',
      allowedValues: actionOutputKinds,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].pin',
      label: '输出引脚',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*.pin',
      note: '工程项目可用 P60/P62/P64/P66/P74/P75/P76/P77/MP03/MP74。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].variable',
      label: '变量名',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*.variable',
      note: '输出目标为整数/有理数变量时才使用。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].expression',
      label: '表达式',
      stepId: 'mappings',
      note: '受限表达式语法，改动后务必看一次校验结果。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].mode',
      label: '控制方式',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*.mode',
      allowedValues: controlModes,
    ),
    McpFieldSpec(
      pattern: 'modes[*].actions[*].parameter',
      label: '控制参数',
      stepId: 'mappings',
      issuePattern: 'modes.*.actions.*.parameter',
      kind: McpFieldKind.number,
      note: '带符号：正负表示原来「方向」字段的朝向。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].id',
      label: '动作表 id',
      stepId: 'mappings',
      writable: false,
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].key',
      label: '动作表下一档键',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].prev_key',
      label: '动作表上一档键',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.prev_key',
      allowedValues: remoteKeys,
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].steps',
      label: '动作表档位数',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.steps',
      kind: McpFieldKind.integer,
      minimum: 2,
      maximum: 8,
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].wrap',
      label: '越界重复',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.wrap',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].rows[*].pin',
      label: '动作表引脚',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.rows.*.pin',
      note: '只能是工程输出引脚。',
    ),
    McpFieldSpec(
      pattern: 'modes[*].action_tables[*].rows[*].values[*]',
      label: '动作表目标值',
      stepId: 'mappings',
      issuePattern: 'modes.*.action_tables.*.rows.*.values.*',
      kind: McpFieldKind.integer,
      minimum: -10000,
      maximum: 10000,
      note: '舵机是 −90~90 的相对角度，电机是 −10000~10000 的 duty。',
    ),

    // ---- 调试工程 ----
    McpFieldSpec(
      pattern: 'tests',
      label: '调试测试项列表',
      stepId: 'tests',
      issuePattern: 'tests',
      note: '十个固定引脚各一条，不要增删；每个元素形如 '
          '{pin, enabled, drive_type, value, duration_ms}。',
    ),
    McpFieldSpec(
      pattern: 'tests[*].pin',
      label: '调试引脚',
      stepId: 'tests',
      issuePattern: 'tests.*.pin',
      note: '十个固定引脚各一条测试，不支持增删。',
    ),
    McpFieldSpec(
      pattern: 'tests[*].enabled',
      label: '启用测试项',
      stepId: 'tests',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'tests[*].drive_type',
      label: '驱动类型',
      stepId: 'tests',
      issuePattern: 'tests.*.drive_type',
      allowedValues: debugDriveTypes,
    ),
    McpFieldSpec(
      pattern: 'tests[*].value',
      label: '测试目标值',
      stepId: 'tests',
      issuePattern: 'tests.*.value',
      kind: McpFieldKind.integer,
      note: '电机是 duty，舵机是相对角度，摩擦轮是 500–800 的目标占空比。',
    ),
    McpFieldSpec(
      pattern: 'tests[*].duration_ms',
      label: '测试持续时间',
      stepId: 'tests',
      issuePattern: 'tests.*.duration_ms',
      kind: McpFieldKind.integer,
      unit: 'ms',
    ),

    // ---- 音乐工程 ----
    McpFieldSpec(
      pattern: 'notes',
      label: '音符列表',
      stepId: 'music',
      issuePattern: 'music.notes',
      note: '数量很大时优先带下标改单个音符，不要整段替换。',
    ),
    McpFieldSpec(
      pattern: 'notes[*]',
      label: '音符',
      stepId: 'music',
      issuePattern: 'music.notes.*',
      note: '元素形如 {id, pitch, start_tick, duration_ticks}。',
    ),
    McpFieldSpec(
      pattern: 'tempo_events',
      label: '速度事件列表',
      stepId: 'music',
      issuePattern: 'music.tempo_events',
    ),
    McpFieldSpec(
      pattern: 'tempo_events[*]',
      label: '速度事件',
      stepId: 'music',
      issuePattern: 'music.tempo_events.*',
    ),
    McpFieldSpec(
      pattern: 'time_signature_events',
      label: '拍号事件列表',
      stepId: 'music',
      issuePattern: 'music.time_signature_events',
    ),
    McpFieldSpec(
      pattern: 'time_signature_events[*]',
      label: '拍号事件',
      stepId: 'music',
      issuePattern: 'music.time_signature_events.*',
    ),
    McpFieldSpec(
      pattern: 'ticks_per_quarter',
      label: '每拍 tick 数',
      stepId: 'music',
      issuePattern: 'music.ticks_per_quarter',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'source_name',
      label: '来源文件名',
      stepId: 'music',
    ),
    McpFieldSpec(
      pattern: 'track_name',
      label: '音轨名',
      stepId: 'music',
    ),
    McpFieldSpec(
      pattern: 'overlap_mode',
      label: '重叠裁决方式',
      stepId: 'music',
      allowedValues: overlapModes,
    ),
    McpFieldSpec(
      pattern: 'new_note_interrupts',
      label: '新音符打断',
      stepId: 'music',
      kind: McpFieldKind.boolean,
    ),
    McpFieldSpec(
      pattern: 'key_signature_fifths',
      label: '调号',
      stepId: 'music',
      issuePattern: 'music.key_signature_fifths',
      kind: McpFieldKind.integer,
      minimum: -7,
      maximum: 7,
      note: '正数升号、负数降号，0 为 C 大调。',
    ),
    McpFieldSpec(
      pattern: 'notes[*].id',
      label: '音符 id',
      stepId: 'music',
      writable: false,
    ),
    McpFieldSpec(
      pattern: 'notes[*].pitch',
      label: '音高',
      stepId: 'music',
      kind: McpFieldKind.integer,
      minimum: 0,
      maximum: 127,
      note: 'MIDI 音高，60 为中音 C。',
    ),
    McpFieldSpec(
      pattern: 'notes[*].start_tick',
      label: '起始 tick',
      stepId: 'music',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'notes[*].duration_ticks',
      label: '时长 tick',
      stepId: 'music',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'tempo_events[*].tick',
      label: '速度事件位置',
      stepId: 'music',
      issuePattern: 'music.tempo_events.*',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'tempo_events[*].microseconds_per_quarter',
      label: '每拍微秒数',
      stepId: 'music',
      issuePattern: 'music.tempo_events.*',
      kind: McpFieldKind.integer,
      note: 'BPM = 60000000 / 该值。',
    ),
    McpFieldSpec(
      pattern: 'time_signature_events[*].tick',
      label: '拍号事件位置',
      stepId: 'music',
      issuePattern: 'music.time_signature_events.*',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'time_signature_events[*].numerator',
      label: '拍号分子',
      stepId: 'music',
      issuePattern: 'music.time_signature_events.*',
      kind: McpFieldKind.integer,
    ),
    McpFieldSpec(
      pattern: 'time_signature_events[*].denominator',
      label: '拍号分母',
      stepId: 'music',
      issuePattern: 'music.time_signature_events.*',
      kind: McpFieldKind.integer,
    ),
  ];

  static final Map<String, McpFieldSpec> _byPattern = {
    for (final spec in specs) spec.pattern: spec,
  };

  static final Map<String, McpFieldSpec> _byIssuePattern = {
    for (final spec in specs) spec.issuePattern ?? spec.pattern: spec,
  };

  /// 把具体路径归一化：`modes[1]` → `modes[*]`。
  static String normalize(String path) =>
      path.replaceAllMapped(RegExp(r'\[\d+\]'), (_) => '[*]');

  /// 按 JSON 路径查条目；数组元素与引脚键都要能命中。
  static McpFieldSpec? lookup(String path) =>
      _lookup(normalize(path), _byPattern);

  /// 按校验器路径查条目（`ValidationIssue.fieldPath` 用的是另一套命名）。
  static McpFieldSpec? lookupIssue(String issuePath) =>
      _lookup(normalize(issuePath), _byIssuePattern);

  /// 某一步骤下的全部条目，用于 `get_context`。
  static List<McpFieldSpec> forStep(String stepId) =>
      specs.where((spec) => spec.stepId == stepId).toList(growable: false);

  static McpFieldSpec? _lookup(
    String normalized,
    Map<String, McpFieldSpec> index,
  ) {
    final exact = index[normalized];
    if (exact != null) return exact;
    for (final entry in index.entries) {
      if (_matches(entry.key, normalized)) return entry.value;
    }
    return null;
  }

  /// 段数必须相同；`*` 可以匹配任意一段。
  static bool _matches(String pattern, String path) {
    final patternParts = pattern.split('.');
    final pathParts = path.split('.');
    if (patternParts.length != pathParts.length) return false;
    for (var index = 0; index < patternParts.length; index += 1) {
      final expected = patternParts[index];
      if (expected == '*') continue;
      if (expected != pathParts[index]) return false;
    }
    return true;
  }
}

String _wheelLabel(String key) => switch (key) {
  'left_front' => '左前',
  'left_rear' => '左后',
  'right_front' => '右前',
  _ => '右后',
};

String _axisLabel(String axis) => axis == 'yaw' ? '云台偏航' : '云台俯仰';

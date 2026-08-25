import 'models.dart';

typedef _AddIssue = void Function(
  IssueSeverity severity,
  String path,
  String message,
  String step, [
  ValidationIssueKind kind,
]);

abstract final class ProjectValidator {
  static List<ValidationIssue> validate(RobotConfig config) {
    final issues = <ValidationIssue>[];
    void issue(
      IssueSeverity severity,
      String path,
      String message,
      String step, [
      ValidationIssueKind kind = ValidationIssueKind.invalid,
    ]) {
      issues.add(
        ValidationIssue(
          severity: severity,
          fieldPath: path,
          message: message,
          stepId: step,
          kind: kind,
        ),
      );
    }

    _range(
      config.remote.channel,
      0,
      125,
      'remote.channel',
      '遥控器通道号',
      'remote',
      issue,
    );
    _range(
      config.remote.deadzone,
      0,
      2047,
      'remote.deadzone',
      '摇杆死区',
      'remote',
      issue,
    );
    _range(
      config.chassis.normalSpeed,
      0,
      10000,
      'chassis.normal_speed',
      '普通速度',
      'remote',
      issue,
    );
    _range(
      config.chassis.sprintSpeed,
      0,
      10000,
      'chassis.sprint_speed',
      '冲刺速度',
      'remote',
      issue,
      required: config.chassis.sprintEnabled,
    );
    if (config.chassis.normalSpeed != null &&
        config.chassis.sprintSpeed != null &&
        config.chassis.sprintSpeed! < config.chassis.normalSpeed!) {
      issue(
        IssueSeverity.warning,
        'chassis.sprint_speed',
        '冲刺速度低于普通速度，冲刺将无法生效',
        'remote',
      );
    }
    _chassis(config.chassis, issue);
    switch (config) {
      case InfantryConfig value:
        _infantry(value, issue);
      case EngineerConfig value:
        _engineer(value, issue);
    }
    return issues;
  }

  static void _range(
    int? value,
    int min,
    int max,
    String path,
    String label,
    String step,
    _AddIssue issue, {
    bool required = true,
  }) {
    if (value == null) {
      if (required) {
        issue(
          IssueSeverity.error,
          path,
          '$label尚未填写',
          step,
          ValidationIssueKind.required,
        );
      }
    } else if (value < min || value > max) {
      issue(IssueSeverity.error, path, '$label必须在 $min–$max 之间', step);
    }
  }

  static void _choice(
    Object? value,
    String path,
    String label,
    String step,
    _AddIssue issue,
  ) {
    if (value == null || value is String && value.isEmpty) {
      issue(
        IssueSeverity.error,
        path,
        '$label尚未选择',
        step,
        ValidationIssueKind.required,
      );
    }
  }

  static void _chassis(ChassisConfig chassis, _AddIssue issue) {
    final wheels =
        <({String path, String label, WheelConfig value, String side})>[
          (
            path: 'chassis.left_front',
            label: '左前轮',
            value: chassis.leftFront,
            side: 'left',
          ),
          (
            path: 'chassis.left_rear',
            label: '左后轮',
            value: chassis.leftRear,
            side: 'left',
          ),
          (
            path: 'chassis.right_front',
            label: '右前轮',
            value: chassis.rightFront,
            side: 'right',
          ),
          (
            path: 'chassis.right_rear',
            label: '右后轮',
            value: chassis.rightRear,
            side: 'right',
          ),
        ];
    final byPin =
        <
          String,
          List<({String path, String label, String side, Direction? direction})>
        >{};
    for (final wheel in wheels) {
      _choice(
        wheel.value.pin,
        '${wheel.path}.pin',
        '${wheel.label} IO',
        'remote',
        issue,
      );
      _choice(
        wheel.value.direction,
        '${wheel.path}.direction',
        '${wheel.label}方向',
        'remote',
        issue,
      );
      if (wheel.value.pin != null && !chassisPins.contains(wheel.value.pin)) {
        issue(
          IssueSeverity.error,
          '${wheel.path}.pin',
          '${wheel.label}使用了非法 IO',
          'remote',
        );
      }
      final pin = InfantryPinPlanner.normalizePin(wheel.value.pin);
      if (pin.isNotEmpty) {
        byPin.putIfAbsent(pin, () => []).add((
          path: wheel.path,
          label: wheel.label,
          side: wheel.side,
          direction: wheel.value.direction,
        ));
      }
    }
    for (final entries in byPin.values.where((items) => items.length > 1)) {
      final sides = entries.map((entry) => entry.side).toSet();
      if (sides.length == 1) {
        final dirs = entries
            .map((entry) => entry.direction)
            .whereType<Direction>()
            .toSet();
        if (dirs.length > 1) {
          final side = sides.single == 'left' ? '左' : '右';
          for (final entry in entries) {
            issue(
              IssueSeverity.warning,
              '${entry.path}.direction',
              '$side侧两轮共用 IO 但方向不同，实际只有最后写入的方向生效',
              'remote',
            );
          }
        }
      } else {
        final labels = entries.map((entry) => entry.label).join('、');
        for (final entry in entries) {
          issue(
            IssueSeverity.error,
            '${entry.path}.pin',
            '$labels 不能跨侧共用同一 IO',
            'remote',
          );
        }
      }
    }
  }

  static void _infantry(InfantryConfig config, _AddIssue issue) {
    _choice(
      config.feederPin,
      'mechanism.feeder_pin',
      '拨弹电机 IO',
      'mechanism',
      issue,
    );
    _choice(
      config.feederDirection,
      'mechanism.feeder_direction',
      '拨弹电机方向',
      'mechanism',
      issue,
    );
    _axis(config, true, issue);
    _axis(config, false, issue);
    _choice(
      config.arrowBehavior,
      'controls.arrow_behavior',
      '方向键用途',
      'controls',
      issue,
    );
    _choice(config.feedMode, 'controls.feed_mode', '拨弹模式', 'controls', issue);
    _choice(
      config.triggerKey,
      'controls.trigger_key',
      '扳机键',
      'controls',
      issue,
    );
    _range(
      config.triggerSpeed,
      0,
      10000,
      'controls.trigger_speed',
      '拨弹速度',
      'controls',
      issue,
    );
    _digital(config.triggerKey, 'controls.trigger_key', '扳机键', issue);
    if (config.feedMode == FeedMode.blockingOpenLoop) {
      _range(
        config.triggerTimeMs,
        0,
        65535,
        'controls.trigger_time_ms',
        '拨弹时长',
        'controls',
        issue,
      );
      if ((config.triggerTimeMs ?? 0) > 1000) {
        issue(
          IssueSeverity.warning,
          'controls.trigger_time_ms',
          '拨弹时间过长，单发期间底盘和云台会失去响应',
          'controls',
        );
      }
    }
    _choice(
      config.frictionMode,
      'controls.friction_mode',
      '摩擦轮类型',
      'controls',
      issue,
    );
    if (config.frictionMode == FrictionMode.brushlessEsc) {
      final keys = <({String path, String label, String? key})>[
        (path: 'controls.trigger_key', label: '扳机键', key: config.triggerKey),
        (
          path: 'controls.friction_key',
          label: '摩擦轮开关键',
          key: config.frictionKey,
        ),
        (
          path: 'controls.friction_up_key',
          label: '摩擦轮增速键',
          key: config.frictionUpKey,
        ),
        (
          path: 'controls.friction_down_key',
          label: '摩擦轮减速键',
          key: config.frictionDownKey,
        ),
      ];
      for (final entry in keys.skip(1)) {
        _choice(entry.key, entry.path, entry.label, 'controls', issue);
        _digital(entry.key, entry.path, entry.label, issue);
      }
      final byKey = <String, List<({String path, String label})>>{};
      for (final entry in keys) {
        if (entry.key != null) {
          byKey.putIfAbsent(entry.key!, () => []).add((
            path: entry.path,
            label: entry.label,
          ));
        }
      }
      for (final entries in byKey.values.where((items) => items.length > 1)) {
        final labels = entries.map((entry) => entry.label).join('、');
        for (final entry in entries) {
          issue(
            IssueSeverity.error,
            entry.path,
            '$labels 不能使用同一按键',
            'controls',
          );
        }
      }
      _range(
        config.frictionMaxDuty,
        500,
        800,
        'controls.friction_max_duty',
        '摩擦轮最大占空比',
        'controls',
        issue,
      );
      if (config.frictionMaxDuty != null &&
          config.frictionMaxDuty! % 100 != 0) {
        issue(
          IssueSeverity.error,
          'controls.friction_max_duty',
          '摩擦轮最大占空比必须是 500–800 内的整百值',
          'controls',
        );
      }
      _range(
        config.frictionStep,
        1,
        800,
        'controls.friction_step',
        '摩擦轮调速步长',
        'controls',
        issue,
      );
    }
    if (config.arrowBehavior == ArrowBehavior.move ||
        config.arrowBehavior == ArrowBehavior.sprint) {
      const arrows = {'UP', 'DOWN', 'LEFT', 'RIGHT'};
      final entries = <({String path, String label, String? key})>[
        (path: 'controls.trigger_key', label: '扳机键', key: config.triggerKey),
        if (config.frictionMode == FrictionMode.brushlessEsc)
          (
            path: 'controls.friction_key',
            label: '摩擦轮开关键',
            key: config.frictionKey,
          ),
        if (config.frictionMode == FrictionMode.brushlessEsc)
          (
            path: 'controls.friction_up_key',
            label: '摩擦轮增速键',
            key: config.frictionUpKey,
          ),
        if (config.frictionMode == FrictionMode.brushlessEsc)
          (
            path: 'controls.friction_down_key',
            label: '摩擦轮减速键',
            key: config.frictionDownKey,
          ),
      ];
      for (final entry in entries) {
        if (entry.key != null && arrows.contains(entry.key)) {
          issue(
            IssueSeverity.error,
            entry.path,
            '方向键已用于底盘，不能同时作为${entry.label}',
            'controls',
          );
        }
      }
    }
    _infantryPins(config, issue);
  }

  static void _digital(
    String? key,
    String path,
    String label,
    _AddIssue issue,
  ) {
    if (key != null && !digitalRemoteKeys.contains(key)) {
      issue(IssueSeverity.error, path, '$label必须使用数字按键，不能使用摇杆轴', 'controls');
    }
  }

  static void _axis(InfantryConfig config, bool yaw, _AddIssue issue) {
    final name = yaw ? 'Yaw' : 'Pitch';
    final base = yaw ? 'gimbal.yaw' : 'gimbal.pitch';
    final drive = yaw ? config.yawDrive : config.pitchDrive;
    final pin = yaw ? config.yawPin : config.pitchPin;
    final direction = yaw ? config.yawDirection : config.pitchDirection;
    final mid = yaw ? config.yawMidOffset : config.pitchMidOffset;
    _choice(drive, '$base.drive', '$name 驱动类型', 'mechanism', issue);
    _choice(pin, '$base.pin', '$name IO', 'mechanism', issue);
    _choice(direction, '$base.direction', '$name 方向', 'mechanism', issue);
    if (drive == DriveType.servo) {
      _range(
        mid,
        -90,
        90,
        '$base.mid_offset',
        '$name 归中偏移',
        'mechanism',
        issue,
      );
    }
    if (pin != null && drive != null) {
      final valid = drive == DriveType.servo
          ? InfantryPinPlanner.servoPins
          : InfantryPinPlanner.motorPins;
      if (!valid.contains(pin)) {
        issue(IssueSeverity.error, '$base.pin', '$name 不能使用 $pin', 'mechanism');
      }
      if (drive == DriveType.motor && mainServoPins.contains(pin)) {
        issue(
          IssueSeverity.error,
          '$base.pin',
          '$pin 是主控板舵机口，不能驱动电机',
          'mechanism',
        );
      }
    }
  }

  static void _infantryPins(InfantryConfig config, _AddIssue issue) {
    final entries =
        <
          ({String path, String label, String? pin, String group, PinRole role})
        >[
          (
            path: 'chassis.left_front.pin',
            label: '左前轮',
            pin: config.chassis.leftFront.pin,
            group: 'left',
            role: PinRole.motor,
          ),
          (
            path: 'chassis.left_rear.pin',
            label: '左后轮',
            pin: config.chassis.leftRear.pin,
            group: 'left',
            role: PinRole.motor,
          ),
          (
            path: 'chassis.right_front.pin',
            label: '右前轮',
            pin: config.chassis.rightFront.pin,
            group: 'right',
            role: PinRole.motor,
          ),
          (
            path: 'chassis.right_rear.pin',
            label: '右后轮',
            pin: config.chassis.rightRear.pin,
            group: 'right',
            role: PinRole.motor,
          ),
          (
            path: 'mechanism.feeder_pin',
            label: '拨弹电机',
            pin: config.feederPin,
            group: 'feeder',
            role: PinRole.motor,
          ),
          (
            path: 'gimbal.yaw.pin',
            label: 'Yaw 轴',
            pin: config.yawPin,
            group: 'yaw',
            role: config.yawDrive == DriveType.servo
                ? PinRole.servo
                : PinRole.motor,
          ),
          (
            path: 'gimbal.pitch.pin',
            label: 'Pitch 轴',
            pin: config.pitchPin,
            group: 'pitch',
            role: config.pitchDrive == DriveType.servo
                ? PinRole.servo
                : PinRole.motor,
          ),
          if (config.frictionMode == FrictionMode.brushlessEsc)
            for (final pin in InfantryPinPlanner.frictionPins)
              (
                path: 'controls.friction_mode',
                label: '摩擦轮',
                pin: pin,
                group: 'friction',
                role: PinRole.friction,
              ),
        ];
    final byPin = <String, List<({String path, String label, String group})>>{};
    for (final entry in entries) {
      final pin = InfantryPinPlanner.normalizePin(entry.pin);
      if (pin.isEmpty) continue;
      byPin.putIfAbsent(pin, () => []).add((
        path: entry.path,
        label: entry.label,
        group: entry.group,
      ));
      if (entry.role == PinRole.motor &&
          const {'P60', 'P62', 'P64', 'P66'}.contains(pin)) {
        issue(
          IssueSeverity.warning,
          entry.path,
          '${entry.label}位于固定 50Hz 的 PWMA，电机可能一卡一卡',
          entry.path.startsWith('chassis.') ? 'remote' : 'mechanism',
        );
      }
    }
    for (final item in byPin.entries) {
      final refs = item.value;
      if (refs.length < 2) continue;
      final groups = refs.map((entry) => entry.group).toSet();
      if (groups.length == 1 &&
          (groups.single == 'left' || groups.single == 'right')) {
        continue;
      }
      if (refs.every((entry) => entry.path.startsWith('chassis.'))) continue;
      final labels = refs.map((entry) => entry.label).toSet().join('、');
      for (final ref in refs.where((entry) => entry.group != 'friction')) {
        issue(
          IssueSeverity.error,
          ref.path,
          '${item.key} 同时被 $labels 占用',
          ref.path.startsWith('chassis.')
              ? 'remote'
              : ref.path.startsWith('controls.')
              ? 'controls'
              : 'mechanism',
        );
      }
    }
  }

  static void _engineer(EngineerConfig config, _AddIssue issue) {
    _choice(config.pwm.pwma, 'pwm.pwma', 'PWMA 初始化频率', 'pwm', issue);
    _choice(config.pwm.pwmb, 'pwm.pwmb', 'PWMB 初始化频率', 'pwm', issue);
    final chassisUsed =
        [
              config.chassis.leftFront.pin,
              config.chassis.leftRear.pin,
              config.chassis.rightFront.pin,
              config.chassis.rightRear.pin,
            ]
            .map(InfantryPinPlanner.normalizePin)
            .where((pin) => pin.isNotEmpty)
            .toSet();
    for (final pin in expansionPins) {
      final role = config.pwm.pinRoles[pin];
      _choice(role, 'pwm.pin_roles.$pin', '$pin 输出角色', 'pwm', issue);
      if (chassisUsed.contains(pin) && role != null && !_motorRole(role)) {
        issue(
          IssueSeverity.error,
          'pwm.pin_roles.$pin',
          '$pin 已用于底盘，输出角色必须是电机',
          'pwm',
        );
      }
      final frequency = expansionPins.indexOf(pin) < 4
          ? config.pwm.pwma
          : config.pwm.pwmb;
      if (role != null && frequency != null) {
        final expected = role == PinRole.motor
            ? PwmFrequency.hz10000
            : PwmFrequency.hz50;
        if (role != PinRole.unused && frequency != expected) {
          issue(
            IssueSeverity.warning,
            'pwm.pin_roles.$pin',
            '$pin 的输出角色与所在 PWM 组频率不匹配',
            'pwm',
          );
        }
      }
      if (role == PinRole.servo) {
        _range(
          config.pwm.servoMids[pin],
          -90,
          90,
          'pwm.servo_mids.$pin',
          '$pin 舵机中位偏移',
          'pwm',
          issue,
        );
      }
    }
    for (final pin in mainServoPins) {
      _range(
        config.pwm.servoMids[pin],
        -90,
        90,
        'pwm.servo_mids.$pin',
        '$pin 舵机中位偏移',
        'pwm',
        issue,
      );
    }

    _range(config.modeCount, 1, 4, 'modes.count', '模式数量', 'strategy', issue);
    final count = config.modeCount;
    if (count == null || count < 1 || count > 4) return;
    if (config.modes.length < count) {
      issue(IssueSeverity.error, 'modes', '模式配置数量不足', 'mappings');
      return;
    }
    if (!config.modes.first.preserveChassis) {
      issue(
        IssueSeverity.error,
        'modes.0.preserve_chassis',
        '模式 1 必须保留左摇杆底盘控制',
        'mappings',
      );
    }
    final switchEntries = <({String path, String? key})>[];
    if (count > 1) {
      _choice(
        config.switchStrategy,
        'modes.switch_strategy',
        '模式切换策略',
        'strategy',
        issue,
      );
      if (config.switchStrategy == SwitchStrategy.cycle) {
        switchEntries.add((
          path: 'modes.switch_key',
          key: config.modeSwitchKey,
        ));
      } else if (config.switchStrategy == SwitchStrategy.direct) {
        for (var i = 0; i < count; i++) {
          switchEntries.add((path: 'modes.keys.$i', key: config.modeKeys[i]));
        }
      }
    }
    final switchKeys = <String>{};
    for (final entry in switchEntries) {
      _choice(entry.key, entry.path, '模式切换按键', 'strategy', issue);
      if (entry.key != null && !digitalRemoteKeys.contains(entry.key)) {
        issue(IssueSeverity.error, entry.path, '模式切换只能使用数字按键', 'strategy');
      }
      if (entry.key != null && !switchKeys.add(entry.key!)) {
        issue(IssueSeverity.error, entry.path, '模式切换按键不能重复', 'strategy');
      }
    }
    for (var mi = 0; mi < count; mi++) {
      final mode = config.modes[mi];
      final seen = <String, int>{};
      for (var ai = 0; ai < mode.actions.length; ai++) {
        final action = mode.actions[ai];
        final path = 'modes.$mi.actions.$ai';
        _action(config, mode, action, path, switchKeys, issue);
        if (action.key != null) {
          final previous = seen[action.key!];
          if (previous != null) {
            issue(
              IssueSeverity.warning,
              '$path.key',
              '该按键已被本模式第 ${previous + 1} 行使用，两行动作会同时生效',
              'mappings',
            );
          } else {
            seen[action.key!] = ai;
          }
        }
      }
    }
  }

  static void _action(
    EngineerConfig config,
    EngineerModeConfig parent,
    ActionMapping action,
    String path,
    Set<String> switchKeys,
    _AddIssue issue,
  ) {
    _choice(action.key, '$path.key', '动作输入', 'mappings', issue);
    _choice(action.direction, '$path.direction', '动作方向', 'mappings', issue);
    _choice(action.mode, '$path.mode', '控制方式', 'mappings', issue);
    _choice(action.pin, '$path.pin', '动作 IO', 'mappings', issue);
    if (action.key != null && !remoteKeys.contains(action.key)) {
      issue(IssueSeverity.error, '$path.key', '未知遥控器输入', 'mappings');
    }
    if (action.key != null && switchKeys.contains(action.key)) {
      issue(IssueSeverity.error, '$path.key', '动作输入与模式切换按键冲突', 'mappings');
    }
    final isAxis = action.key != null && axisRemoteInputs.contains(action.key);
    if (parent.preserveChassis && (action.key == 'LX' || action.key == 'LY')) {
      issue(
        IssueSeverity.error,
        '$path.key',
        '当前模式保留底盘控制，LX/LY 不能用于动作',
        'mappings',
      );
    }
    final allPins = [...expansionPins, ...mainServoPins];
    if (action.pin != null && !allPins.contains(action.pin)) {
      issue(IssueSeverity.error, '$path.pin', '动作 IO 无效', 'mappings');
    }
    final chassisUsed = [
      config.chassis.leftFront.pin,
      config.chassis.leftRear.pin,
      config.chassis.rightFront.pin,
      config.chassis.rightRear.pin,
    ].map(InfantryPinPlanner.normalizePin).toSet();
    if (action.pin != null && chassisUsed.contains(action.pin)) {
      issue(
        IssueSeverity.error,
        '$path.pin',
        '${action.pin} 已被底盘电机占用',
        'mappings',
      );
    }
    final role = action.pin == null
        ? null
        : mainServoPins.contains(action.pin)
        ? PinRole.servo
        : config.pwm.pinRoles[action.pin];
    final motor = role != null && _motorRole(role);
    if (role == PinRole.unused) {
      issue(
        IssueSeverity.error,
        '$path.pin',
        '${action.pin} 已标记为未使用，不能作为动作输出',
        'mappings',
      );
    }
    final allowed = role == null
        ? const <ControlMode>[]
        : motor
        ? (isAxis
              ? const [ControlMode.speed, ControlMode.accelerate]
              : const [ControlMode.direct])
        : const [ControlMode.incremental, ControlMode.direct];
    if (action.mode != null && !allowed.contains(action.mode)) {
      issue(
        IssueSeverity.error,
        '$path.mode',
        '控制方式与输入类型或 IO 输出角色不匹配',
        'mappings',
      );
    }
    switch (action.mode) {
      case ControlMode.incremental:
        _range(
          action.parameter,
          0,
          90,
          '$path.parameter',
          '舵机增量',
          'mappings',
          issue,
        );
        if (action.parameter == 0) {
          issue(
            IssueSeverity.warning,
            '$path.parameter',
            '舵机增量为 0，该动作不会产生变化',
            'mappings',
          );
        }
        if ((action.parameter ?? 0) > 30) {
          issue(
            IssueSeverity.warning,
            '$path.parameter',
            '单次增量偏大，建议使用 1–30°',
            'mappings',
          );
        }
      case ControlMode.direct:
        _range(
          action.parameter,
          0,
          motor ? 10000 : 90,
          '$path.parameter',
          motor ? '电机速度' : '舵机角度',
          'mappings',
          issue,
        );
      case ControlMode.speed || ControlMode.accelerate:
        _range(
          action.parameter,
          0,
          10000,
          '$path.parameter',
          '电机控制参数',
          'mappings',
          issue,
        );
      case null:
        _choice(action.parameter, '$path.parameter', '动作参数', 'mappings', issue);
    }
  }

  static bool _motorRole(PinRole role) =>
      role == PinRole.motor ||
      role == PinRole.friction ||
      role == PinRole.jitterMotor;
}

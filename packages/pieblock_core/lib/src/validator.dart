import 'models.dart';

typedef _AddIssue = void Function(
  IssueSeverity severity,
  String path,
  String message,
  String step,
);
typedef _CheckRange = void Function(
  int? value,
  int min,
  int max,
  String path,
  String label,
  String step,
);

abstract final class ProjectValidator {
  static List<ValidationIssue> validate(RobotConfig config) {
    final issues = <ValidationIssue>[];
    void issue(
      IssueSeverity severity,
      String path,
      String message,
      String step,
    ) => issues.add(
      ValidationIssue(
        severity: severity,
        fieldPath: path,
        message: message,
        stepId: step,
      ),
    );
    void range(
      int? value,
      int min,
      int max,
      String path,
      String label,
      String step,
    ) {
      if (value == null) {
        issue(IssueSeverity.error, path, '$label不能为空', step);
      } else if (value < min || value > max) {
        issue(IssueSeverity.error, path, '$label必须在 $min–$max 之间', step);
      }
    }

    range(config.remote.channel, 0, 125, 'remote.channel', '遥控器通道号', 'remote');
    range(config.remote.deadzone, 0, 2047, 'remote.deadzone', '摇杆死区', 'remote');
    range(
      config.chassis.normalSpeed,
      0,
      10000,
      'chassis.normal_speed',
      '普通速度',
      'remote',
    );
    range(
      config.chassis.sprintSpeed,
      0,
      10000,
      'chassis.sprint_speed',
      '冲刺速度',
      'remote',
    );
    if ((config.chassis.sprintSpeed ?? 0) < (config.chassis.normalSpeed ?? 0)) {
      issue(
        IssueSeverity.warning,
        'chassis.sprint_speed',
        '冲刺速度低于普通速度',
        'remote',
      );
    }

    final wheels = <(String, String, String, String, Direction)>[
      (
        'chassis.left_front.pin',
        '左前轮',
        config.chassis.leftFront.pin,
        'left',
        config.chassis.leftFront.direction,
      ),
      (
        'chassis.left_rear.pin',
        '左后轮',
        config.chassis.leftRear.pin,
        'left',
        config.chassis.leftRear.direction,
      ),
      (
        'chassis.right_front.pin',
        '右前轮',
        config.chassis.rightFront.pin,
        'right',
        config.chassis.rightFront.direction,
      ),
      (
        'chassis.right_rear.pin',
        '右后轮',
        config.chassis.rightRear.pin,
        'right',
        config.chassis.rightRear.direction,
      ),
    ];
    final wheelPins = <String, List<(String, String, String, Direction)>>{};
    for (final field in wheels) {
      final pin = InfantryPinPlanner.normalizePin(field.$3);
      wheelPins.putIfAbsent(pin, () => []).add((
        field.$1,
        field.$2,
        field.$4,
        field.$5,
      ));
      if (!chassisPins.contains(field.$3)) {
        issue(IssueSeverity.error, field.$1, '${field.$2}使用了非法 IO', 'remote');
      }
    }
    for (final duplicates in wheelPins.values.where(
      (items) => items.length > 1,
    )) {
      final groups = duplicates.map((item) => item.$3).toSet();
      if (groups.length == 1) {
        final directions = duplicates.map((item) => item.$4).toSet();
        if (directions.length > 1) {
          final side = groups.single == 'left' ? '左' : '右';
          for (final item in duplicates) {
            issue(
              IssueSeverity.warning,
              item.$1,
              '$side侧两轮共用 IO 但方向不同，实际以最后写入的方向为准',
              'remote',
            );
          }
        }
        continue;
      }
      final labels = duplicates.map((item) => item.$2).join('、');
      for (final item in duplicates) {
        issue(IssueSeverity.error, item.$1, '$labels 不能跨侧共用同一 IO', 'remote');
      }
    }

    if (config is InfantryConfig) {
      _validateInfantry(config, issue, range);
    } else if (config is EngineerConfig) {
      _validateEngineer(config, issue, range);
    }
    return issues;
  }

  static void _validateInfantry(
    InfantryConfig config,
    _AddIssue issue,
    _CheckRange range,
  ) {
    range(
      config.yawMidOffset,
      -90,
      90,
      'gimbal.yaw.mid_offset',
      'Yaw 中位偏移',
      'mechanism',
    );
    range(
      config.pitchMidOffset,
      -90,
      90,
      'gimbal.pitch.mid_offset',
      'Pitch 中位偏移',
      'mechanism',
    );
    range(
      config.triggerSpeed,
      0,
      10000,
      'controls.trigger_speed',
      '拨弹速度',
      'controls',
    );
    range(
      config.triggerTimeMs,
      1,
      60000,
      'controls.trigger_time_ms',
      '拨弹时长',
      'controls',
    );
    range(
      config.frictionMaxDuty,
      500,
      800,
      'controls.friction_max_duty',
      '摩擦轮最大占空比',
      'controls',
    );
    range(
      config.frictionStep,
      1,
      300,
      'controls.friction_step',
      '摩擦轮调速步长',
      'controls',
    );

    final assignments = <(String, String, String, PinRole)>[
      (
        'chassis.left_front.pin',
        '左前轮',
        InfantryPinPlanner.normalizePin(config.chassis.leftFront.pin),
        PinRole.motor,
      ),
      (
        'chassis.left_rear.pin',
        '左后轮',
        InfantryPinPlanner.normalizePin(config.chassis.leftRear.pin),
        PinRole.motor,
      ),
      (
        'chassis.right_front.pin',
        '右前轮',
        InfantryPinPlanner.normalizePin(config.chassis.rightFront.pin),
        PinRole.motor,
      ),
      (
        'chassis.right_rear.pin',
        '右后轮',
        InfantryPinPlanner.normalizePin(config.chassis.rightRear.pin),
        PinRole.motor,
      ),
      ('mechanism.feeder_pin', '拨弹电机', config.feederPin, PinRole.motor),
      (
        'gimbal.yaw.pin',
        'Yaw 轴',
        config.yawPin,
        config.yawDrive == DriveType.servo ? PinRole.servo : PinRole.motor,
      ),
      (
        'gimbal.pitch.pin',
        'Pitch 轴',
        config.pitchPin,
        config.pitchDrive == DriveType.servo ? PinRole.servo : PinRole.motor,
      ),
    ];
    final byPin = <String, List<(String, String)>>{};
    for (final assignment in assignments) {
      final validPins = assignment.$4 == PinRole.servo
          ? InfantryPinPlanner.servoPins
          : InfantryPinPlanner.motorPins;
      final step = assignment.$1.startsWith('chassis.')
          ? 'remote'
          : 'mechanism';
      if (!validPins.contains(assignment.$3)) {
        issue(
          IssueSeverity.error,
          assignment.$1,
          '${assignment.$2}不能使用 ${assignment.$3}',
          step,
        );
      }
      byPin.putIfAbsent(assignment.$3, () => <(String, String)>[]).add((
        assignment.$1,
        assignment.$2,
      ));
      if (assignment.$4 == PinRole.motor &&
          const ['P60', 'P62'].contains(assignment.$3)) {
        issue(
          IssueSeverity.warning,
          assignment.$1,
          '${assignment.$2}位于固定 50Hz 的 PWMA，电机运行可能不够平滑',
          step,
        );
      }
    }
    for (final duplicates in byPin.values.where((items) => items.length > 1)) {
      if (duplicates.every((item) => item.$1.startsWith('chassis.'))) {
        continue;
      }
      final labels = duplicates.map((item) => item.$2).join('、');
      for (final item in duplicates) {
        issue(
          IssueSeverity.error,
          item.$1,
          '该 IO 同时被 $labels 占用',
          item.$1.startsWith('chassis.') ? 'remote' : 'mechanism',
        );
      }
    }

    final keys = <(String, String, String)>[
      ('controls.trigger_key', '扳机键', config.triggerKey),
      ('controls.friction_key', '摩擦轮开关键', config.frictionKey),
      ('controls.friction_up_key', '摩擦轮增速键', config.frictionUpKey),
      ('controls.friction_down_key', '摩擦轮减速键', config.frictionDownKey),
    ];
    final byKey = <String, List<(String, String)>>{};
    for (final field in keys) {
      if (!digitalRemoteKeys.contains(field.$3)) {
        issue(
          IssueSeverity.error,
          field.$1,
          '${field.$2}必须使用按键，不能使用摇杆轴',
          'controls',
        );
      }
      byKey.putIfAbsent(field.$3, () => []).add((field.$1, field.$2));
    }
    for (final duplicates in byKey.values.where((items) => items.length > 1)) {
      final labels = duplicates.map((item) => item.$2).join('、');
      for (final item in duplicates) {
        issue(IssueSeverity.error, item.$1, '$labels 不能使用同一按键', 'controls');
      }
    }
  }

  static void _validateEngineer(
    EngineerConfig config,
    _AddIssue issue,
    _CheckRange range,
  ) {
    for (final pin in mainServoPins) {
      if (config.pwm.pinRoles[pin] != PinRole.servo) {
        issue(
          IssueSeverity.error,
          'pwm.pin_roles.$pin',
          '$pin 是主控板舵机口，只能配置为舵机',
          'pwm',
        );
      }
    }
    void checkGroup(List<String> pins, PwmFrequency frequency, String group) {
      for (final pin in pins) {
        final role = config.pwm.pinRoles[pin] ?? PinRole.motor;
        if (role == PinRole.motor && frequency != PwmFrequency.hz10000) {
          issue(
            IssueSeverity.warning,
            'pwm.pin_roles.$pin',
            '$pin 配置为电机，但 $group 当前不是 10000Hz',
            'pwm',
          );
        }
        if ((role == PinRole.servo ||
                role == PinRole.friction ||
                role == PinRole.jitterMotor) &&
            frequency != PwmFrequency.hz50) {
          issue(
            IssueSeverity.warning,
            'pwm.pin_roles.$pin',
            '$pin 的输出角色通常需要 50Hz',
            'pwm',
          );
        }
      }
    }

    checkGroup(expansionPins.take(4).toList(), config.pwm.pwma, 'PWMA');
    checkGroup(expansionPins.skip(4).toList(), config.pwm.pwmb, 'PWMB');
    for (final entry in config.pwm.servoMids.entries) {
      range(
        entry.value,
        -90,
        90,
        'pwm.servo_mids.${entry.key}',
        '${entry.key} 舵机中位偏移',
        'pwm',
      );
    }

    range(config.modeCount, 1, 4, 'modes.count', '模式数量', 'strategy');
    if (config.modes.length < config.modeCount) {
      issue(IssueSeverity.error, 'modes', '模式配置数量不足', 'mappings');
    }
    final switchEntries = config.switchStrategy == SwitchStrategy.cycle
        ? [('modes.switch_key', config.modeSwitchKey)]
        : [
            for (var i = 0; i < config.modeCount; i++)
              ('modes.keys.$i', config.modeKeys[i]),
          ];
    final switchKeys = switchEntries.map((entry) => entry.$2).toSet();
    final bySwitchKey = <String, List<String>>{};
    for (final entry in switchEntries) {
      if (!digitalRemoteKeys.contains(entry.$2)) {
        issue(IssueSeverity.error, entry.$1, '模式切换只能使用按键', 'strategy');
      }
      bySwitchKey.putIfAbsent(entry.$2, () => []).add(entry.$1);
    }
    for (final paths in bySwitchKey.values.where((items) => items.length > 1)) {
      for (final path in paths) {
        issue(IssueSeverity.error, path, '模式切换按键不能重复', 'strategy');
      }
    }
    for (var i = 0; i < config.modes.take(config.modeCount).length; i++) {
      final mode = config.modes[i];
      final seen = <String>{};
      for (var r = 0; r < mode.actions.length; r++) {
        final action = mode.actions[r], path = 'modes.$i.actions.$r';
        if (!remoteKeys.contains(action.key)) {
          issue(IssueSeverity.error, '$path.key', '未知遥控器按键', 'mappings');
        }
        if (!seen.add(action.key)) {
          issue(IssueSeverity.error, '$path.key', '同一模式内按键不能重复', 'mappings');
        }
        if (switchKeys.contains(action.key)) {
          issue(IssueSeverity.error, '$path.key', '动作按键与模式切换键冲突', 'mappings');
        }
        if (![...expansionPins, ...mainServoPins].contains(action.pin)) {
          issue(IssueSeverity.error, '$path.pin', '动作 IO 无效', 'mappings');
        }
        final limit = action.mode == ControlMode.incremental ? 90 : 10000;
        range(
          action.parameter,
          0,
          limit,
          '$path.parameter',
          '动作参数',
          'mappings',
        );
        if (mainServoPins.contains(action.pin) &&
            action.mode != ControlMode.incremental) {
          issue(
            IssueSeverity.error,
            '$path.mode',
            '主控板舵机口只能使用增量控制',
            'mappings',
          );
        }
      }
    }
  }
}

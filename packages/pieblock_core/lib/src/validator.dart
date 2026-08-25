import 'models.dart';

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
      if (value == null)
        issue(IssueSeverity.error, path, '$label不能为空', step);
      else if (value < min || value > max)
        issue(IssueSeverity.error, path, '$label必须在 $min–$max 之间', step);
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
    if ((config.chassis.sprintSpeed ?? 0) < (config.chassis.normalSpeed ?? 0))
      issue(
        IssueSeverity.warning,
        'chassis.sprint_speed',
        '冲刺速度低于普通速度',
        'remote',
      );
    final wheels = [
      config.chassis.leftFront.pin,
      config.chassis.leftRear.pin,
      config.chassis.rightFront.pin,
      config.chassis.rightRear.pin,
    ];
    if (wheels.toSet().length != wheels.length)
      issue(IssueSeverity.error, 'chassis', '四个底盘电机不能重复使用同一 IO', 'remote');

    for (final pin in mainServoPins) {
      if (config.pwm.pinRoles[pin] != PinRole.servo)
        issue(
          IssueSeverity.error,
          'pwm.pin_roles.$pin',
          '$pin 是主控板舵机口，只能配置为舵机',
          'pwm',
        );
    }
    void checkGroup(List<String> pins, PwmFrequency frequency, String group) {
      for (final pin in pins) {
        final role = config.pwm.pinRoles[pin] ?? PinRole.motor;
        if (role == PinRole.motor && frequency != PwmFrequency.hz10000)
          issue(
            IssueSeverity.warning,
            'pwm.pin_roles.$pin',
            '$pin 配置为电机，但 $group 当前不是 10000Hz',
            'pwm',
          );
        if ((role == PinRole.servo ||
                role == PinRole.friction ||
                role == PinRole.jitterMotor) &&
            frequency != PwmFrequency.hz50)
          issue(
            IssueSeverity.warning,
            'pwm.pin_roles.$pin',
            '$pin 的输出角色通常需要 50Hz',
            'pwm',
          );
      }
    }

    checkGroup(expansionPins.take(4).toList(), config.pwm.pwma, 'PWMA');
    checkGroup(expansionPins.skip(4).toList(), config.pwm.pwmb, 'PWMB');
    for (final entry in config.pwm.servoMids.entries)
      range(
        entry.value,
        -90,
        90,
        'pwm.servo_mids.${entry.key}',
        '${entry.key} 舵机中位偏移',
        'pwm',
      );

    if (config is InfantryConfig) {
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
      if (config.yawPin == config.pitchPin)
        issue(
          IssueSeverity.error,
          'gimbal.pitch.pin',
          'Yaw 与 Pitch 不能占用同一 IO',
          'mechanism',
        );
      if ({
            config.triggerKey,
            config.frictionKey,
            config.frictionUpKey,
            config.frictionDownKey,
          }.length <
          4)
        issue(
          IssueSeverity.error,
          'controls',
          '扳机、摩擦轮开关和增减速按键不能重复',
          'controls',
        );
      if (!expansionPins.contains(config.feederPin))
        issue(
          IssueSeverity.error,
          'mechanism.feeder_pin',
          '拨弹电机必须使用扩展板 IO',
          'mechanism',
        );
      if (config.yawDrive == DriveType.servo &&
          !(mainServoPins.contains(config.yawPin) ||
              expansionPins.contains(config.yawPin)))
        issue(
          IssueSeverity.error,
          'gimbal.yaw.pin',
          'Yaw 舵机 IO 无效',
          'mechanism',
        );
    } else if (config is EngineerConfig) {
      range(config.modeCount, 1, 4, 'modes.count', '模式数量', 'strategy');
      if (config.modes.length < config.modeCount)
        issue(IssueSeverity.error, 'modes', '模式配置数量不足', 'mappings');
      final switchKeys = config.switchStrategy == SwitchStrategy.cycle
          ? {config.modeSwitchKey}
          : config.modeKeys.take(config.modeCount).toSet();
      if (switchKeys.length !=
          (config.switchStrategy == SwitchStrategy.cycle
              ? 1
              : config.modeCount))
        issue(IssueSeverity.error, 'modes.keys', '模式切换按键不能重复', 'strategy');
      for (var i = 0; i < config.modes.take(config.modeCount).length; i++) {
        final mode = config.modes[i];
        final seen = <String>{};
        for (var r = 0; r < mode.actions.length; r++) {
          final action = mode.actions[r], path = 'modes.$i.actions.$r';
          if (!remoteKeys.contains(action.key))
            issue(IssueSeverity.error, '$path.key', '未知遥控器按键', 'mappings');
          if (!seen.add(action.key))
            issue(IssueSeverity.error, '$path.key', '同一模式内按键不能重复', 'mappings');
          if (switchKeys.contains(action.key))
            issue(IssueSeverity.error, '$path.key', '动作按键与模式切换键冲突', 'mappings');
          if (![...expansionPins, ...mainServoPins].contains(action.pin))
            issue(IssueSeverity.error, '$path.pin', '动作 IO 无效', 'mappings');
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
              action.mode != ControlMode.incremental)
            issue(
              IssueSeverity.error,
              '$path.mode',
              '主控板舵机口只能使用增量控制',
              'mappings',
            );
        }
      }
    }
    return issues;
  }
}

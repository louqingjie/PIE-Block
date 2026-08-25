enum ProjectKind { infantry, engineer }

enum Direction { forward, reverse }

enum DriveType { servo, motor }

enum PinRole { motor, servo, friction, jitterMotor, unused }

enum PwmFrequency { hz50, hz10000 }

enum SwitchStrategy { cycle, direct }

enum ControlMode { direct, incremental, speed, accelerate }

enum IssueSeverity { error, warning }

const expansionPins = ['P60', 'P62', 'P64', 'P66', 'P74', 'P75', 'P76', 'P77'];
const mainServoPins = ['MP03', 'MP74'];
const chassisPins = [
  'P60 P61',
  'P62 P63',
  'P74 P24',
  'P75 P25',
  'P76 P26',
  'P77 P27',
];
const digitalRemoteKeys = [
  'E',
  'UP',
  'DOWN',
  'LEFT',
  'RIGHT',
  'A',
  'B',
  'C',
  'D',
  'LC',
  'RC',
];
const axisRemoteInputs = ['LX', 'LY', 'RX', 'RY'];
const remoteKeys = [...digitalRemoteKeys, ...axisRemoteInputs];

T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw?.toString()) return value;
  }
  return fallback;
}

class RemoteConfig {
  const RemoteConfig({this.channel = 36, this.deadzone = 10});
  final int? channel;
  final int? deadzone;
  RemoteConfig copyWith({int? channel, int? deadzone}) => RemoteConfig(
    channel: channel ?? this.channel,
    deadzone: deadzone ?? this.deadzone,
  );
  Map<String, Object?> toJson() => {'channel': channel, 'deadzone': deadzone};
  factory RemoteConfig.fromJson(Map<String, Object?> json) => RemoteConfig(
    channel: (json['channel'] as num?)?.toInt(),
    deadzone: (json['deadzone'] as num?)?.toInt(),
  );
}

class WheelConfig {
  const WheelConfig(this.pin, [this.direction = Direction.forward]);
  final String pin;
  final Direction direction;
  WheelConfig copyWith({String? pin, Direction? direction}) =>
      WheelConfig(pin ?? this.pin, direction ?? this.direction);
  Map<String, Object?> toJson() => {'pin': pin, 'direction': direction.name};
  factory WheelConfig.fromJson(Map<String, Object?> json) => WheelConfig(
    json['pin']?.toString() ?? chassisPins.first,
    enumValue(Direction.values, json['direction'], Direction.forward),
  );
}

class ChassisConfig {
  const ChassisConfig({
    required this.leftFront,
    required this.leftRear,
    required this.rightFront,
    required this.rightRear,
    this.normalSpeed = 4000,
    this.sprintSpeed = 8000,
    this.sprintEnabled = false,
  });
  factory ChassisConfig.defaults() => const ChassisConfig(
    leftFront: WheelConfig('P74 P24'),
    leftRear: WheelConfig('P75 P25'),
    rightFront: WheelConfig('P76 P26'),
    rightRear: WheelConfig('P77 P27'),
  );
  final WheelConfig leftFront, leftRear, rightFront, rightRear;
  final int? normalSpeed, sprintSpeed;
  final bool sprintEnabled;
  ChassisConfig copyWith({
    WheelConfig? leftFront,
    WheelConfig? leftRear,
    WheelConfig? rightFront,
    WheelConfig? rightRear,
    int? normalSpeed,
    int? sprintSpeed,
    bool? sprintEnabled,
  }) => ChassisConfig(
    leftFront: leftFront ?? this.leftFront,
    leftRear: leftRear ?? this.leftRear,
    rightFront: rightFront ?? this.rightFront,
    rightRear: rightRear ?? this.rightRear,
    normalSpeed: normalSpeed ?? this.normalSpeed,
    sprintSpeed: sprintSpeed ?? this.sprintSpeed,
    sprintEnabled: sprintEnabled ?? this.sprintEnabled,
  );
  Map<String, Object?> toJson() => {
    'left_front': leftFront.toJson(),
    'left_rear': leftRear.toJson(),
    'right_front': rightFront.toJson(),
    'right_rear': rightRear.toJson(),
    'normal_speed': normalSpeed,
    'sprint_speed': sprintSpeed,
    'sprint_enabled': sprintEnabled,
  };
  factory ChassisConfig.fromJson(Map<String, Object?> j) => ChassisConfig(
    leftFront: WheelConfig.fromJson(
      Map<String, Object?>.from(j['left_front'] as Map? ?? {}),
    ),
    leftRear: WheelConfig.fromJson(
      Map<String, Object?>.from(j['left_rear'] as Map? ?? {}),
    ),
    rightFront: WheelConfig.fromJson(
      Map<String, Object?>.from(j['right_front'] as Map? ?? {}),
    ),
    rightRear: WheelConfig.fromJson(
      Map<String, Object?>.from(j['right_rear'] as Map? ?? {}),
    ),
    normalSpeed: (j['normal_speed'] as num?)?.toInt(),
    sprintSpeed: (j['sprint_speed'] as num?)?.toInt(),
    sprintEnabled: j['sprint_enabled'] as bool? ?? false,
  );
}

class PwmGroupConfig {
  PwmGroupConfig({
    this.pwma = PwmFrequency.hz50,
    this.pwmb = PwmFrequency.hz10000,
    this.buzzerDisabled = false,
    Map<String, PinRole>? pinRoles,
    Map<String, int>? servoMids,
  }) : pinRoles = Map.unmodifiable(
         pinRoles ??
             {
               for (final p in expansionPins) p: PinRole.motor,
               for (final p in mainServoPins) p: PinRole.servo,
             },
       ),
       servoMids = Map.unmodifiable(
         servoMids ??
             {
               for (final p in [...expansionPins, ...mainServoPins]) p: 0,
             },
       );
  final PwmFrequency pwma, pwmb;
  final bool buzzerDisabled;
  final Map<String, PinRole> pinRoles;
  final Map<String, int> servoMids;
  PwmGroupConfig copyWith({
    PwmFrequency? pwma,
    PwmFrequency? pwmb,
    bool? buzzerDisabled,
    Map<String, PinRole>? pinRoles,
    Map<String, int>? servoMids,
  }) => PwmGroupConfig(
    pwma: pwma ?? this.pwma,
    pwmb: pwmb ?? this.pwmb,
    buzzerDisabled: buzzerDisabled ?? this.buzzerDisabled,
    pinRoles: pinRoles ?? this.pinRoles,
    servoMids: servoMids ?? this.servoMids,
  );
  Map<String, Object?> toJson() => {
    'pwma': pwma.name,
    'pwmb': pwmb.name,
    'buzzer_disabled': buzzerDisabled,
    'pin_roles': pinRoles.map((k, v) => MapEntry(k, v.name)),
    'servo_mids': servoMids,
  };
  factory PwmGroupConfig.fromJson(Map<String, Object?> j) {
    final roles = <String, PinRole>{};
    for (final e in Map<String, Object?>.from(
      j['pin_roles'] as Map? ?? {},
    ).entries) {
      roles[e.key] = enumValue(PinRole.values, e.value, PinRole.motor);
    }
    final mids = <String, int>{};
    for (final e in Map<String, Object?>.from(
      j['servo_mids'] as Map? ?? {},
    ).entries) {
      mids[e.key] = (e.value as num?)?.toInt() ?? 0;
    }
    return PwmGroupConfig(
      pwma: enumValue(PwmFrequency.values, j['pwma'], PwmFrequency.hz50),
      pwmb: enumValue(PwmFrequency.values, j['pwmb'], PwmFrequency.hz10000),
      buzzerDisabled: j['buzzer_disabled'] as bool? ?? false,
      pinRoles: roles.isEmpty ? null : roles,
      servoMids: mids.isEmpty ? null : mids,
    );
  }
}

sealed class RobotConfig {
  const RobotConfig({required this.remote, required this.chassis});
  final RemoteConfig remote;
  final ChassisConfig chassis;
  ProjectKind get kind;
  Map<String, Object?> toJson();
}

class InfantryConfig extends RobotConfig {
  InfantryConfig({
    super.remote = const RemoteConfig(),
    ChassisConfig? chassis,
    this.feederPin = 'P60',
    this.feederDirection = Direction.forward,
    this.yawDrive = DriveType.servo,
    this.yawPin = 'MP74',
    this.yawDirection = Direction.forward,
    this.yawMidOffset = 0,
    this.pitchDrive = DriveType.servo,
    this.pitchPin = 'MP03',
    this.pitchDirection = Direction.forward,
    this.pitchMidOffset = 0,
    this.arrowBehavior = 'move',
    this.feedMode = 'closed_loop',
    this.triggerKey = 'E',
    this.triggerSpeed = 6000,
    this.triggerTimeMs = 100,
    this.frictionKey = 'A',
    this.frictionUpKey = 'B',
    this.frictionDownKey = 'C',
    this.frictionMaxDuty = 800,
    this.frictionStep = 100,
    this.zeroEnabled = false,
    this.buzzerDisabled = false,
  }) : super(chassis: chassis ?? ChassisConfig.defaults());
  @override
  ProjectKind get kind => ProjectKind.infantry;
  final String feederPin,
      yawPin,
      pitchPin,
      arrowBehavior,
      feedMode,
      triggerKey,
      frictionKey,
      frictionUpKey,
      frictionDownKey;
  final Direction feederDirection, yawDirection, pitchDirection;
  final DriveType yawDrive, pitchDrive;
  final int? yawMidOffset,
      pitchMidOffset,
      triggerSpeed,
      triggerTimeMs,
      frictionMaxDuty,
      frictionStep;
  final bool zeroEnabled, buzzerDisabled;
  InfantryConfig copyWith({
    RemoteConfig? remote,
    ChassisConfig? chassis,
    String? feederPin,
    Direction? feederDirection,
    DriveType? yawDrive,
    String? yawPin,
    Direction? yawDirection,
    int? yawMidOffset,
    DriveType? pitchDrive,
    String? pitchPin,
    Direction? pitchDirection,
    int? pitchMidOffset,
    String? arrowBehavior,
    String? feedMode,
    String? triggerKey,
    int? triggerSpeed,
    int? triggerTimeMs,
    String? frictionKey,
    String? frictionUpKey,
    String? frictionDownKey,
    int? frictionMaxDuty,
    int? frictionStep,
    bool? zeroEnabled,
    bool? buzzerDisabled,
  }) => InfantryConfig(
    remote: remote ?? this.remote,
    chassis: chassis ?? this.chassis,
    feederPin: feederPin ?? this.feederPin,
    feederDirection: feederDirection ?? this.feederDirection,
    yawDrive: yawDrive ?? this.yawDrive,
    yawPin: yawPin ?? this.yawPin,
    yawDirection: yawDirection ?? this.yawDirection,
    yawMidOffset: yawMidOffset ?? this.yawMidOffset,
    pitchDrive: pitchDrive ?? this.pitchDrive,
    pitchPin: pitchPin ?? this.pitchPin,
    pitchDirection: pitchDirection ?? this.pitchDirection,
    pitchMidOffset: pitchMidOffset ?? this.pitchMidOffset,
    arrowBehavior: arrowBehavior ?? this.arrowBehavior,
    feedMode: feedMode ?? this.feedMode,
    triggerKey: triggerKey ?? this.triggerKey,
    triggerSpeed: triggerSpeed ?? this.triggerSpeed,
    triggerTimeMs: triggerTimeMs ?? this.triggerTimeMs,
    frictionKey: frictionKey ?? this.frictionKey,
    frictionUpKey: frictionUpKey ?? this.frictionUpKey,
    frictionDownKey: frictionDownKey ?? this.frictionDownKey,
    frictionMaxDuty: frictionMaxDuty ?? this.frictionMaxDuty,
    frictionStep: frictionStep ?? this.frictionStep,
    zeroEnabled: zeroEnabled ?? this.zeroEnabled,
    buzzerDisabled: buzzerDisabled ?? this.buzzerDisabled,
  );
  @override
  Map<String, Object?> toJson() => {
    'remote': remote.toJson(),
    'chassis': chassis.toJson(),
    'feeder_pin': feederPin,
    'feeder_direction': feederDirection.name,
    'yaw': {
      'drive': yawDrive.name,
      'pin': yawPin,
      'direction': yawDirection.name,
      'mid_offset': yawMidOffset,
    },
    'pitch': {
      'drive': pitchDrive.name,
      'pin': pitchPin,
      'direction': pitchDirection.name,
      'mid_offset': pitchMidOffset,
    },
    'arrow_behavior': arrowBehavior,
    'feed_mode': feedMode,
    'trigger_key': triggerKey,
    'trigger_speed': triggerSpeed,
    'trigger_time_ms': triggerTimeMs,
    'friction_key': frictionKey,
    'friction_up_key': frictionUpKey,
    'friction_down_key': frictionDownKey,
    'friction_max_duty': frictionMaxDuty,
    'friction_step': frictionStep,
    'zero_enabled': zeroEnabled,
    'buzzer_disabled': buzzerDisabled,
  };
  factory InfantryConfig.fromJson(Map<String, Object?> j) {
    final y = Map<String, Object?>.from(j['yaw'] as Map? ?? {}),
        p = Map<String, Object?>.from(j['pitch'] as Map? ?? {});
    return InfantryConfig(
      remote: RemoteConfig.fromJson(
        Map<String, Object?>.from(j['remote'] as Map? ?? {}),
      ),
      chassis: ChassisConfig.fromJson(
        Map<String, Object?>.from(j['chassis'] as Map? ?? {}),
      ),
      feederPin: j['feeder_pin']?.toString() ?? 'P60',
      feederDirection: enumValue(
        Direction.values,
        j['feeder_direction'],
        Direction.forward,
      ),
      yawDrive: enumValue(DriveType.values, y['drive'], DriveType.servo),
      yawPin: y['pin']?.toString() ?? 'MP74',
      yawDirection: enumValue(
        Direction.values,
        y['direction'],
        Direction.forward,
      ),
      yawMidOffset: (y['mid_offset'] as num?)?.toInt(),
      pitchDrive: enumValue(DriveType.values, p['drive'], DriveType.servo),
      pitchPin: p['pin']?.toString() ?? 'MP03',
      pitchDirection: enumValue(
        Direction.values,
        p['direction'],
        Direction.forward,
      ),
      pitchMidOffset: (p['mid_offset'] as num?)?.toInt(),
      arrowBehavior: j['arrow_behavior']?.toString() ?? 'move',
      feedMode: j['feed_mode']?.toString() ?? 'closed_loop',
      triggerKey: j['trigger_key']?.toString() ?? 'E',
      triggerSpeed: (j['trigger_speed'] as num?)?.toInt(),
      triggerTimeMs: (j['trigger_time_ms'] as num?)?.toInt(),
      frictionKey: j['friction_key']?.toString() ?? 'A',
      frictionUpKey: j['friction_up_key']?.toString() ?? 'B',
      frictionDownKey: j['friction_down_key']?.toString() ?? 'C',
      frictionMaxDuty: (j['friction_max_duty'] as num?)?.toInt(),
      frictionStep: (j['friction_step'] as num?)?.toInt(),
      zeroEnabled: j['zero_enabled'] as bool? ?? false,
      buzzerDisabled: j['buzzer_disabled'] as bool? ?? false,
    );
  }
}

class PinAssignment {
  const PinAssignment({
    required this.pin,
    required this.role,
    required this.ownerFieldPath,
    required this.ownerLabel,
  });

  final String pin;
  final PinRole role;
  final String ownerFieldPath;
  final String ownerLabel;
}

abstract final class InfantryPinPlanner {
  static const pwmaFrequency = PwmFrequency.hz50;
  static const pwmbFrequency = PwmFrequency.hz10000;
  static const frictionPins = ['P64', 'P66'];
  static const motorPins = ['P60', 'P62', 'P74', 'P75', 'P76', 'P77'];
  static const servoPins = ['P60', 'P62', 'MP03', 'MP74'];

  static String normalizePin(String value) => value.split(' ').first;

  static String? _chassisSide(String fieldPath) => switch (fieldPath) {
    'chassis.left_front.pin' || 'chassis.left_rear.pin' => 'left',
    'chassis.right_front.pin' || 'chassis.right_rear.pin' => 'right',
    _ => null,
  };

  static bool _canShare(String firstFieldPath, String secondFieldPath) {
    final firstSide = _chassisSide(firstFieldPath);
    return firstSide != null && firstSide == _chassisSide(secondFieldPath);
  }

  static List<PinAssignment> _references(InfantryConfig config) => [
    PinAssignment(
      pin: normalizePin(config.chassis.leftFront.pin),
      role: PinRole.motor,
      ownerFieldPath: 'chassis.left_front.pin',
      ownerLabel: '左前轮',
    ),
    PinAssignment(
      pin: normalizePin(config.chassis.leftRear.pin),
      role: PinRole.motor,
      ownerFieldPath: 'chassis.left_rear.pin',
      ownerLabel: '左后轮',
    ),
    PinAssignment(
      pin: normalizePin(config.chassis.rightFront.pin),
      role: PinRole.motor,
      ownerFieldPath: 'chassis.right_front.pin',
      ownerLabel: '右前轮',
    ),
    PinAssignment(
      pin: normalizePin(config.chassis.rightRear.pin),
      role: PinRole.motor,
      ownerFieldPath: 'chassis.right_rear.pin',
      ownerLabel: '右后轮',
    ),
    PinAssignment(
      pin: config.feederPin,
      role: PinRole.motor,
      ownerFieldPath: 'mechanism.feeder_pin',
      ownerLabel: '拨弹电机',
    ),
    PinAssignment(
      pin: config.yawPin,
      role: config.yawDrive == DriveType.servo ? PinRole.servo : PinRole.motor,
      ownerFieldPath: 'gimbal.yaw.pin',
      ownerLabel: 'Yaw 轴',
    ),
    PinAssignment(
      pin: config.pitchPin,
      role: config.pitchDrive == DriveType.servo
          ? PinRole.servo
          : PinRole.motor,
      ownerFieldPath: 'gimbal.pitch.pin',
      ownerLabel: 'Pitch 轴',
    ),
    for (final pin in frictionPins)
      PinAssignment(
        pin: pin,
        role: PinRole.friction,
        ownerFieldPath: 'friction.$pin',
        ownerLabel: '摩擦轮（固定）',
      ),
  ];

  static Map<String, PinAssignment> derive(InfantryConfig config) {
    final result = <String, PinAssignment>{};
    for (final assignment in _references(config)) {
      final previous = result[assignment.pin];
      if (previous != null &&
          _canShare(previous.ownerFieldPath, assignment.ownerFieldPath)) {
        result[assignment.pin] = PinAssignment(
          pin: assignment.pin,
          role: assignment.role,
          ownerFieldPath: previous.ownerFieldPath,
          ownerLabel: '${previous.ownerLabel}、${assignment.ownerLabel}',
        );
        continue;
      }
      result[assignment.pin] = assignment;
    }
    return Map.unmodifiable(result);
  }

  static List<String> allowedPins(
    InfantryConfig config,
    String fieldPath, {
    DriveType? driveType,
  }) {
    final candidates = switch (fieldPath) {
      'chassis.left_front.pin' ||
      'chassis.left_rear.pin' ||
      'chassis.right_front.pin' ||
      'chassis.right_rear.pin' => chassisPins,
      'mechanism.feeder_pin' => motorPins,
      'gimbal.yaw.pin' || 'gimbal.pitch.pin' =>
        (driveType ??
                    (fieldPath == 'gimbal.yaw.pin'
                        ? config.yawDrive
                        : config.pitchDrive)) ==
                DriveType.servo
            ? servoPins
            : motorPins,
      _ => const <String>[],
    };
    final current = switch (fieldPath) {
      'chassis.left_front.pin' => config.chassis.leftFront.pin,
      'chassis.left_rear.pin' => config.chassis.leftRear.pin,
      'chassis.right_front.pin' => config.chassis.rightFront.pin,
      'chassis.right_rear.pin' => config.chassis.rightRear.pin,
      'mechanism.feeder_pin' => config.feederPin,
      'gimbal.yaw.pin' => config.yawPin,
      'gimbal.pitch.pin' => config.pitchPin,
      _ => '',
    };
    final occupied = _references(config)
        .where(
          (item) =>
              item.ownerFieldPath != fieldPath &&
              !_canShare(fieldPath, item.ownerFieldPath),
        )
        .map((item) => item.pin)
        .toSet();
    return candidates
        .where(
          (candidate) =>
              !occupied.contains(normalizePin(candidate)) ||
              normalizePin(candidate) == normalizePin(current),
        )
        .toList(growable: false);
  }

  static PinAssignment? occupiedBy(
    InfantryConfig config,
    String pin,
    String excludingFieldPath,
  ) {
    final normalized = normalizePin(pin);
    for (final assignment in _references(config)) {
      if (assignment.ownerFieldPath != excludingFieldPath &&
          !_canShare(excludingFieldPath, assignment.ownerFieldPath) &&
          assignment.pin == normalized) {
        return assignment;
      }
    }
    return null;
  }
}

class ActionMapping {
  ActionMapping({
    String? id,
    this.key = 'A',
    this.direction = Direction.forward,
    this.mode = ControlMode.direct,
    this.parameter = 1000,
    this.pin = 'P60',
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id, key, pin;
  final Direction direction;
  final ControlMode mode;
  final int? parameter;
  ActionMapping copyWith({
    String? key,
    Direction? direction,
    ControlMode? mode,
    int? parameter,
    String? pin,
  }) => ActionMapping(
    id: id,
    key: key ?? this.key,
    direction: direction ?? this.direction,
    mode: mode ?? this.mode,
    parameter: parameter ?? this.parameter,
    pin: pin ?? this.pin,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'key': key,
    'direction': direction.name,
    'mode': mode.name,
    'parameter': parameter,
    'pin': pin,
  };
  factory ActionMapping.fromJson(Map<String, Object?> j) => ActionMapping(
    id: j['id']?.toString(),
    key: j['key']?.toString() ?? 'A',
    direction: enumValue(Direction.values, j['direction'], Direction.forward),
    mode: enumValue(ControlMode.values, j['mode'], ControlMode.direct),
    parameter: (j['parameter'] as num?)?.toInt(),
    pin: j['pin']?.toString() ?? 'P60',
  );
}

class EngineerModeConfig {
  EngineerModeConfig({
    String? id,
    this.preserveChassis = false,
    List<ActionMapping>? actions,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
       actions = List.unmodifiable(actions ?? []);
  final String id;
  final bool preserveChassis;
  final List<ActionMapping> actions;
  EngineerModeConfig copyWith({
    bool? preserveChassis,
    List<ActionMapping>? actions,
  }) => EngineerModeConfig(
    id: id,
    preserveChassis: preserveChassis ?? this.preserveChassis,
    actions: actions ?? this.actions,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'preserve_chassis': preserveChassis,
    'actions': actions.map((a) => a.toJson()).toList(),
  };
  factory EngineerModeConfig.fromJson(Map<String, Object?> j) =>
      EngineerModeConfig(
        id: j['id']?.toString(),
        preserveChassis: j['preserve_chassis'] as bool? ?? false,
        actions: (j['actions'] as List? ?? [])
            .map(
              (a) =>
                  ActionMapping.fromJson(Map<String, Object?>.from(a as Map)),
            )
            .toList(),
      );
}

class EngineerConfig extends RobotConfig {
  EngineerConfig({
    super.remote = const RemoteConfig(),
    ChassisConfig? chassis,
    PwmGroupConfig? pwm,
    this.modeCount = 1,
    this.switchStrategy = SwitchStrategy.cycle,
    this.modeSwitchKey = 'E',
    List<String>? modeKeys,
    List<EngineerModeConfig>? modes,
  }) : modeKeys = List.unmodifiable(modeKeys ?? const ['A', 'B', 'C', 'D']),
       modes = List.unmodifiable(
         modes ?? [EngineerModeConfig(preserveChassis: true)],
       ),
       pwm = pwm ?? PwmGroupConfig(),
       super(chassis: chassis ?? ChassisConfig.defaults());
  @override
  ProjectKind get kind => ProjectKind.engineer;
  final int modeCount;
  final SwitchStrategy switchStrategy;
  final String modeSwitchKey;
  final List<String> modeKeys;
  final List<EngineerModeConfig> modes;
  final PwmGroupConfig pwm;
  EngineerConfig copyWith({
    RemoteConfig? remote,
    ChassisConfig? chassis,
    PwmGroupConfig? pwm,
    int? modeCount,
    SwitchStrategy? switchStrategy,
    String? modeSwitchKey,
    List<String>? modeKeys,
    List<EngineerModeConfig>? modes,
  }) => EngineerConfig(
    remote: remote ?? this.remote,
    chassis: chassis ?? this.chassis,
    pwm: pwm ?? this.pwm,
    modeCount: modeCount ?? this.modeCount,
    switchStrategy: switchStrategy ?? this.switchStrategy,
    modeSwitchKey: modeSwitchKey ?? this.modeSwitchKey,
    modeKeys: modeKeys ?? this.modeKeys,
    modes: modes ?? this.modes,
  );
  @override
  Map<String, Object?> toJson() => {
    'remote': remote.toJson(),
    'chassis': chassis.toJson(),
    'pwm': pwm.toJson(),
    'mode_count': modeCount,
    'switch_strategy': switchStrategy.name,
    'mode_switch_key': modeSwitchKey,
    'mode_keys': modeKeys,
    'modes': modes.map((m) => m.toJson()).toList(),
  };
  factory EngineerConfig.fromJson(Map<String, Object?> j) => EngineerConfig(
    remote: RemoteConfig.fromJson(
      Map<String, Object?>.from(j['remote'] as Map? ?? {}),
    ),
    chassis: ChassisConfig.fromJson(
      Map<String, Object?>.from(j['chassis'] as Map? ?? {}),
    ),
    pwm: PwmGroupConfig.fromJson(
      Map<String, Object?>.from(j['pwm'] as Map? ?? {}),
    ),
    modeCount: (j['mode_count'] as num?)?.toInt() ?? 1,
    switchStrategy: enumValue(
      SwitchStrategy.values,
      j['switch_strategy'],
      SwitchStrategy.cycle,
    ),
    modeSwitchKey: j['mode_switch_key']?.toString() ?? 'E',
    modeKeys: (j['mode_keys'] as List? ?? const ['A', 'B', 'C', 'D'])
        .map((e) => e.toString())
        .toList(),
    modes: (j['modes'] as List? ?? [])
        .map(
          (m) =>
              EngineerModeConfig.fromJson(Map<String, Object?>.from(m as Map)),
        )
        .toList(),
  );
}

class ProjectDocument {
  const ProjectDocument({
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    required this.config,
  });
  static const formatVersion = 13;
  final String name;
  final ProjectKind kind;
  final DateTime createdAt, updatedAt;
  final RobotConfig config;
  factory ProjectDocument.create(String name, ProjectKind kind) {
    final now = DateTime.now().toUtc();
    return ProjectDocument(
      name: name,
      kind: kind,
      createdAt: now,
      updatedAt: now,
      config: kind == ProjectKind.infantry
          ? InfantryConfig()
          : EngineerConfig(),
    );
  }
  ProjectDocument copyWith({String? name, RobotConfig? config}) =>
      ProjectDocument(
        name: name ?? this.name,
        kind: kind,
        createdAt: createdAt,
        updatedAt: DateTime.now().toUtc(),
        config: config ?? this.config,
      );
  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'name': name,
    'project_kind': kind.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'config': config.toJson(),
  };
  factory ProjectDocument.fromJson(Map<String, Object?> j) {
    if ((j['format_version'] as num?)?.toInt() != formatVersion) {
      throw const FormatException('不受支持的项目格式，请在对应旧版 PIE-Block 中打开');
    }
    final kind = enumValue(
          ProjectKind.values,
          j['project_kind'],
          ProjectKind.infantry,
        ),
        config = Map<String, Object?>.from(j['config'] as Map? ?? {}),
        now = DateTime.now().toUtc();
    return ProjectDocument(
      name: j['name']?.toString() ?? '未命名项目',
      kind: kind,
      createdAt: DateTime.tryParse(j['created_at']?.toString() ?? '') ?? now,
      updatedAt: DateTime.tryParse(j['updated_at']?.toString() ?? '') ?? now,
      config: kind == ProjectKind.infantry
          ? InfantryConfig.fromJson(config)
          : EngineerConfig.fromJson(config),
    );
  }
}

class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.fieldPath,
    required this.message,
    required this.stepId,
  });
  final IssueSeverity severity;
  final String fieldPath, message, stepId;
}

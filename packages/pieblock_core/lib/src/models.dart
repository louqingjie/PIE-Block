enum ProjectKind { infantry, engineer, debug, music }

enum Direction { forward, reverse }

enum DriveType { servo, motor }

enum DebugDriveType { motor, servo, friction }

enum ArrowBehavior { move, sprint, other }

enum FeedMode { blockingOpenLoop, visualClosedLoop }

enum FrictionMode { brushlessEsc, disabled }

enum PinRole { motor, servo, friction, jitterMotor, unused }

enum PwmFrequency { hz50, hz10000 }

enum SwitchStrategy { cycle, direct }

enum ControlMode { direct, incremental, speed, accelerate, single, continuous }

enum IssueSeverity { error, warning }

enum ValidationIssueKind { required, invalid }

const expansionPins = ['P60', 'P62', 'P64', 'P66', 'P74', 'P75', 'P76', 'P77'];
const mainServoPins = ['MP03', 'MP74'];

/// Hardware capabilities for engineer-project output pins.
abstract final class EngineerPinCapabilities {
  static const motorPins = ['P60', 'P62', 'P74', 'P75', 'P76', 'P77'];
  static const frictionPins = ['P64', 'P66'];
  static const servoPins = [...expansionPins, ...mainServoPins];

  static List<PinRole> allowedRoles(String pin) => PinRole.values
      .where((role) => supportsRole(pin, role))
      .toList(growable: false);

  static bool supportsRole(String pin, PinRole role) => switch (role) {
    PinRole.motor || PinRole.jitterMotor => motorPins.contains(pin),
    PinRole.friction => frictionPins.contains(pin),
    PinRole.servo => servoPins.contains(pin),
    PinRole.unused => expansionPins.contains(pin),
  };
}

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
];
const axisRemoteInputs = ['LX', 'LY', 'RX', 'RY'];
const remoteKeys = [...digitalRemoteKeys, ...axisRemoteInputs];

T enumValue<T extends Enum>(List<T> values, Object? raw, T fallback) {
  for (final value in values) {
    if (value.name == raw?.toString()) return value;
  }
  return fallback;
}

T? nullableEnumValue<T extends Enum>(List<T> values, Object? raw) {
  for (final value in values) {
    if (value.name == raw?.toString()) return value;
  }
  return null;
}

const _unset = Object();

class RemoteConfig {
  const RemoteConfig({this.channel, this.deadzone});
  final int? channel;
  final int? deadzone;
  RemoteConfig copyWith({
    Object? channel = _unset,
    Object? deadzone = _unset,
  }) => RemoteConfig(
    channel: identical(channel, _unset) ? this.channel : channel as int?,
    deadzone: identical(deadzone, _unset) ? this.deadzone : deadzone as int?,
  );
  Map<String, Object?> toJson() => {'channel': channel, 'deadzone': deadzone};
  factory RemoteConfig.fromJson(Map<String, Object?> json) => RemoteConfig(
    channel: (json['channel'] as num?)?.toInt(),
    deadzone: (json['deadzone'] as num?)?.toInt(),
  );
}

class WheelConfig {
  const WheelConfig([this.pin, this.direction]);
  final String? pin;
  final Direction? direction;
  WheelConfig copyWith({Object? pin = _unset, Object? direction = _unset}) =>
      WheelConfig(
        identical(pin, _unset) ? this.pin : pin as String?,
        identical(direction, _unset) ? this.direction : direction as Direction?,
      );
  Map<String, Object?> toJson() => {'pin': pin, 'direction': direction?.name};
  factory WheelConfig.fromJson(Map<String, Object?> json) => WheelConfig(
    json['pin']?.toString(),
    nullableEnumValue(Direction.values, json['direction']),
  );
}

class ChassisConfig {
  const ChassisConfig({
    this.leftFront = const WheelConfig(),
    this.leftRear = const WheelConfig(),
    this.rightFront = const WheelConfig(),
    this.rightRear = const WheelConfig(),
    this.normalSpeed,
    this.sprintSpeed,
    this.sprintEnabled = false,
    this.turnReversed = false,
  });
  factory ChassisConfig.defaults() => const ChassisConfig();
  final WheelConfig leftFront, leftRear, rightFront, rightRear;
  final int? normalSpeed, sprintSpeed;
  final bool sprintEnabled, turnReversed;
  ChassisConfig copyWith({
    WheelConfig? leftFront,
    WheelConfig? leftRear,
    WheelConfig? rightFront,
    WheelConfig? rightRear,
    Object? normalSpeed = _unset,
    Object? sprintSpeed = _unset,
    bool? sprintEnabled,
    bool? turnReversed,
  }) => ChassisConfig(
    leftFront: leftFront ?? this.leftFront,
    leftRear: leftRear ?? this.leftRear,
    rightFront: rightFront ?? this.rightFront,
    rightRear: rightRear ?? this.rightRear,
    normalSpeed: identical(normalSpeed, _unset)
        ? this.normalSpeed
        : normalSpeed as int?,
    sprintSpeed: identical(sprintSpeed, _unset)
        ? this.sprintSpeed
        : sprintSpeed as int?,
    sprintEnabled: sprintEnabled ?? this.sprintEnabled,
    turnReversed: turnReversed ?? this.turnReversed,
  );
  Map<String, Object?> toJson() => {
    'left_front': leftFront.toJson(),
    'left_rear': leftRear.toJson(),
    'right_front': rightFront.toJson(),
    'right_rear': rightRear.toJson(),
    'normal_speed': normalSpeed,
    'sprint_speed': sprintSpeed,
    'sprint_enabled': sprintEnabled,
    'turn_reversed': turnReversed,
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
    turnReversed: j['turn_reversed'] as bool? ?? false,
  );
}

class PwmGroupConfig {
  PwmGroupConfig({
    this.pwma,
    this.pwmb,
    this.buzzerDisabled = false,
    Map<String, PinRole>? pinRoles,
    Map<String, int>? servoMids,
  }) : pinRoles = Map.unmodifiable(pinRoles ?? const {}),
       servoMids = Map.unmodifiable(servoMids ?? const {});
  final PwmFrequency? pwma, pwmb;
  final bool buzzerDisabled;
  final Map<String, PinRole> pinRoles;
  final Map<String, int> servoMids;
  PwmGroupConfig copyWith({
    Object? pwma = _unset,
    Object? pwmb = _unset,
    bool? buzzerDisabled,
    Map<String, PinRole>? pinRoles,
    Map<String, int>? servoMids,
  }) => PwmGroupConfig(
    pwma: identical(pwma, _unset) ? this.pwma : pwma as PwmFrequency?,
    pwmb: identical(pwmb, _unset) ? this.pwmb : pwmb as PwmFrequency?,
    buzzerDisabled: buzzerDisabled ?? this.buzzerDisabled,
    pinRoles: pinRoles ?? this.pinRoles,
    servoMids: servoMids ?? this.servoMids,
  );
  Map<String, Object?> toJson() => {
    'pwma': pwma?.name,
    'pwmb': pwmb?.name,
    'buzzer_disabled': buzzerDisabled,
    'pin_roles': {for (final pin in expansionPins) pin: pinRoles[pin]?.name},
    'servo_mids': {
      for (final pin in [...expansionPins, ...mainServoPins])
        pin: servoMids[pin],
    },
  };
  factory PwmGroupConfig.fromJson(Map<String, Object?> j) {
    final roles = <String, PinRole>{};
    for (final e in Map<String, Object?>.from(
      j['pin_roles'] as Map? ?? {},
    ).entries) {
      final role = nullableEnumValue(PinRole.values, e.value);
      if (role != null) roles[e.key] = role;
    }
    final mids = <String, int>{};
    for (final e in Map<String, Object?>.from(
      j['servo_mids'] as Map? ?? {},
    ).entries) {
      final value = (e.value as num?)?.toInt();
      if (value != null) mids[e.key] = value;
    }
    return PwmGroupConfig(
      pwma: nullableEnumValue(PwmFrequency.values, j['pwma']),
      pwmb: nullableEnumValue(PwmFrequency.values, j['pwmb']),
      buzzerDisabled: j['buzzer_disabled'] as bool? ?? false,
      pinRoles: roles,
      servoMids: mids,
    );
  }
}

sealed class ProjectConfig {
  const ProjectConfig();
  ProjectKind get kind;
  Map<String, Object?> toJson();
}

sealed class RobotConfig extends ProjectConfig {
  const RobotConfig({required this.remote, required this.chassis});
  final RemoteConfig remote;
  final ChassisConfig chassis;
}

const debugPins = [
  'P60',
  'P62',
  'P64',
  'P66',
  'P74',
  'P75',
  'P76',
  'P77',
  'MP03',
  'MP74',
];

class DebugTestItem {
  const DebugTestItem({
    required this.pin,
    this.enabled = false,
    this.driveType,
    this.direction,
    this.value,
    this.durationMs = 3000,
  });
  final String pin;
  final bool enabled;
  final DebugDriveType? driveType;
  final Direction? direction;
  final int? value;
  final int durationMs;

  DebugTestItem copyWith({
    bool? enabled,
    Object? driveType = _unset,
    Object? direction = _unset,
    Object? value = _unset,
    int? durationMs,
  }) => DebugTestItem(
    pin: pin,
    enabled: enabled ?? this.enabled,
    driveType: identical(driveType, _unset)
        ? this.driveType
        : driveType as DebugDriveType?,
    direction: identical(direction, _unset)
        ? this.direction
        : direction as Direction?,
    value: identical(value, _unset) ? this.value : value as int?,
    durationMs: durationMs ?? this.durationMs,
  );

  Map<String, Object?> toJson() => {
    'pin': pin,
    'enabled': enabled,
    'drive_type': driveType?.name,
    'direction': direction?.name,
    'value': value,
    if (driveType != DebugDriveType.friction) 'duration_ms': durationMs,
  };

  factory DebugTestItem.fromJson(Map<String, Object?> json) => DebugTestItem(
    pin: json['pin']?.toString() ?? '',
    enabled: json['enabled'] as bool? ?? false,
    driveType: nullableEnumValue(DebugDriveType.values, json['drive_type']),
    direction: nullableEnumValue(Direction.values, json['direction']),
    value: (json['value'] as num?)?.toInt(),
    durationMs: (json['duration_ms'] as num?)?.toInt() ?? 3000,
  );
}

class DebugConfig extends ProjectConfig {
  DebugConfig({List<DebugTestItem>? tests})
    : tests = List.unmodifiable(
        tests ?? [for (final pin in debugPins) DebugTestItem(pin: pin)],
      );
  final List<DebugTestItem> tests;
  @override
  ProjectKind get kind => ProjectKind.debug;
  DebugConfig copyWith({List<DebugTestItem>? tests}) =>
      DebugConfig(tests: tests ?? this.tests);
  @override
  Map<String, Object?> toJson() => {
    'tests': tests.map((item) => item.toJson()).toList(),
  };
  factory DebugConfig.fromJson(Map<String, Object?> json) {
    final tests = <DebugTestItem>[], seen = <String>{};
    for (final raw in json['tests'] as List? ?? const []) {
      if (raw is! Map) continue;
      final item = DebugTestItem.fromJson(Map<String, Object?>.from(raw));
      if (debugPins.contains(item.pin) && seen.add(item.pin)) tests.add(item);
    }
    for (final pin in debugPins) {
      if (seen.add(pin)) tests.add(DebugTestItem(pin: pin));
    }
    return DebugConfig(tests: tests);
  }
}

class MusicNote {
  const MusicNote({
    required this.id,
    required this.pitch,
    required this.startTick,
    required this.durationTicks,
    this.primary = true,
  });

  final String id;
  final int pitch, startTick, durationTicks;
  final bool primary;
  int get endTick => startTick + durationTicks;

  MusicNote copyWith({
    String? id,
    int? pitch,
    int? startTick,
    int? durationTicks,
    bool? primary,
  }) => MusicNote(
    id: id ?? this.id,
    pitch: pitch ?? this.pitch,
    startTick: startTick ?? this.startTick,
    durationTicks: durationTicks ?? this.durationTicks,
    primary: primary ?? this.primary,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'pitch': pitch,
    'start_tick': startTick,
    'duration_ticks': durationTicks,
    'primary': primary,
  };

  factory MusicNote.fromJson(Map<String, Object?> json) => MusicNote(
    id: json['id']?.toString() ?? '',
    pitch: (json['pitch'] as num?)?.toInt() ?? 60,
    startTick: (json['start_tick'] as num?)?.toInt() ?? 0,
    durationTicks: (json['duration_ticks'] as num?)?.toInt() ?? 1,
    primary: json['primary'] as bool? ?? true,
  );
}

class TempoEvent {
  const TempoEvent({required this.tick, required this.microsecondsPerQuarter});
  final int tick, microsecondsPerQuarter;
  double get bpm => 60000000 / microsecondsPerQuarter;
  Map<String, Object?> toJson() => {
    'tick': tick,
    'microseconds_per_quarter': microsecondsPerQuarter,
  };
  factory TempoEvent.fromJson(Map<String, Object?> json) => TempoEvent(
    tick: (json['tick'] as num?)?.toInt() ?? 0,
    microsecondsPerQuarter:
        (json['microseconds_per_quarter'] as num?)?.toInt() ?? 500000,
  );
}

class TimeSignatureEvent {
  const TimeSignatureEvent({
    required this.tick,
    required this.numerator,
    required this.denominator,
  });
  final int tick, numerator, denominator;
  Map<String, Object?> toJson() => {
    'tick': tick,
    'numerator': numerator,
    'denominator': denominator,
  };
  factory TimeSignatureEvent.fromJson(Map<String, Object?> json) =>
      TimeSignatureEvent(
        tick: (json['tick'] as num?)?.toInt() ?? 0,
        numerator: (json['numerator'] as num?)?.toInt() ?? 4,
        denominator: (json['denominator'] as num?)?.toInt() ?? 4,
      );
}

class MusicConfig extends ProjectConfig {
  MusicConfig({
    this.ticksPerQuarter = 480,
    this.sourceName,
    this.trackName,
    List<MusicNote> notes = const [],
    List<TempoEvent>? tempoEvents,
    List<TimeSignatureEvent>? timeSignatureEvents,
  }) : notes = List.unmodifiable(notes),
       tempoEvents = List.unmodifiable(
         tempoEvents ??
             const [TempoEvent(tick: 0, microsecondsPerQuarter: 500000)],
       ),
       timeSignatureEvents = List.unmodifiable(
         timeSignatureEvents ??
             const [TimeSignatureEvent(tick: 0, numerator: 4, denominator: 4)],
       );

  final int ticksPerQuarter;
  final String? sourceName, trackName;
  final List<MusicNote> notes;
  final List<TempoEvent> tempoEvents;
  final List<TimeSignatureEvent> timeSignatureEvents;

  @override
  ProjectKind get kind => ProjectKind.music;

  MusicConfig copyWith({
    int? ticksPerQuarter,
    Object? sourceName = _unset,
    Object? trackName = _unset,
    List<MusicNote>? notes,
    List<TempoEvent>? tempoEvents,
    List<TimeSignatureEvent>? timeSignatureEvents,
  }) => MusicConfig(
    ticksPerQuarter: ticksPerQuarter ?? this.ticksPerQuarter,
    sourceName: identical(sourceName, _unset)
        ? this.sourceName
        : sourceName as String?,
    trackName: identical(trackName, _unset)
        ? this.trackName
        : trackName as String?,
    notes: notes ?? this.notes,
    tempoEvents: tempoEvents ?? this.tempoEvents,
    timeSignatureEvents: timeSignatureEvents ?? this.timeSignatureEvents,
  );

  MusicConfig promote(String noteId) {
    MusicNote? target;
    for (final note in notes) {
      if (note.id == noteId) target = note;
    }
    if (target == null) return this;
    return copyWith(
      notes: [
        for (final note in notes)
          note.startTick == target.startTick
              ? note.copyWith(primary: note.id == noteId)
              : note,
      ],
    );
  }

  @override
  Map<String, Object?> toJson() => {
    'ticks_per_quarter': ticksPerQuarter,
    'source_name': sourceName,
    'track_name': trackName,
    'notes': notes.map((note) => note.toJson()).toList(),
    'tempo_events': tempoEvents.map((event) => event.toJson()).toList(),
    'time_signature_events': timeSignatureEvents
        .map((event) => event.toJson())
        .toList(),
  };

  factory MusicConfig.fromJson(Map<String, Object?> json) => MusicConfig(
    ticksPerQuarter: (json['ticks_per_quarter'] as num?)?.toInt() ?? 480,
    sourceName: json['source_name']?.toString(),
    trackName: json['track_name']?.toString(),
    notes: [
      for (final raw in json['notes'] as List? ?? const [])
        if (raw is Map) MusicNote.fromJson(Map<String, Object?>.from(raw)),
    ],
    tempoEvents: [
      for (final raw in json['tempo_events'] as List? ?? const [])
        if (raw is Map) TempoEvent.fromJson(Map<String, Object?>.from(raw)),
    ],
    timeSignatureEvents: [
      for (final raw in json['time_signature_events'] as List? ?? const [])
        if (raw is Map)
          TimeSignatureEvent.fromJson(Map<String, Object?>.from(raw)),
    ],
  );
}

/// 云台单个轴上的一个执行器：一个驱动类型、一个 IO、一个方向。
///
/// 同轴可以挂 1~N 个执行器（如两只舵机并联增扭），也可以一个都不挂。
class AxisActuator {
  const AxisActuator({this.drive, this.pin, this.direction, this.midOffset});
  final DriveType? drive;
  final String? pin;
  final Direction? direction;
  final int? midOffset;
  AxisActuator copyWith({
    Object? drive = _unset,
    Object? pin = _unset,
    Object? direction = _unset,
    Object? midOffset = _unset,
  }) => AxisActuator(
    drive: identical(drive, _unset) ? this.drive : drive as DriveType?,
    pin: identical(pin, _unset) ? this.pin : pin as String?,
    direction: identical(direction, _unset)
        ? this.direction
        : direction as Direction?,
    midOffset: identical(midOffset, _unset)
        ? this.midOffset
        : midOffset as int?,
  );
  Map<String, Object?> toJson() => {
    'drive': drive?.name,
    'pin': pin,
    'direction': direction?.name,
    'mid_offset': midOffset,
  };
  factory AxisActuator.fromJson(Map<String, Object?> json) => AxisActuator(
    drive: nullableEnumValue(DriveType.values, json['drive']),
    pin: json['pin']?.toString(),
    direction: nullableEnumValue(Direction.values, json['direction']),
    midOffset: (json['mid_offset'] as num?)?.toInt(),
  );
}

class InfantryConfig extends RobotConfig {
  InfantryConfig({
    super.remote = const RemoteConfig(),
    ChassisConfig? chassis,
    this.feederPin,
    this.feederDirection,
    List<AxisActuator> yawActuators = const [AxisActuator()],
    List<AxisActuator> pitchActuators = const [AxisActuator()],
    this.arrowBehavior,
    this.feedMode,
    this.triggerKey,
    this.reverseFeedKey,
    this.triggerSpeed,
    this.triggerTimeMs,
    this.frictionMode,
    this.frictionKey,
    this.frictionUpKey,
    this.frictionDownKey,
    this.frictionMaxDuty,
    this.frictionStep,
    this.zeroEnabled = false,
    this.buzzerDisabled = false,
  }) : yawActuators = List.unmodifiable(yawActuators),
       pitchActuators = List.unmodifiable(pitchActuators),
       super(chassis: chassis ?? ChassisConfig.defaults());
  @override
  ProjectKind get kind => ProjectKind.infantry;
  final String? feederPin,
      triggerKey,
      reverseFeedKey,
      frictionKey,
      frictionUpKey,
      frictionDownKey;
  final ArrowBehavior? arrowBehavior;
  final FeedMode? feedMode;
  final FrictionMode? frictionMode;
  final Direction? feederDirection;
  final List<AxisActuator> yawActuators, pitchActuators;
  final int? triggerSpeed,
      triggerTimeMs,
      frictionMaxDuty,
      frictionStep;
  final bool zeroEnabled, buzzerDisabled;

  /// [yaw] 为 true 时返回 Yaw 轴的执行器，否则返回 Pitch 轴的执行器。
  List<AxisActuator> actuators(bool yaw) => yaw ? yawActuators : pitchActuators;
  InfantryConfig copyWith({
    RemoteConfig? remote,
    ChassisConfig? chassis,
    Object? feederPin = _unset,
    Object? feederDirection = _unset,
    Object? yawActuators = _unset,
    Object? pitchActuators = _unset,
    Object? arrowBehavior = _unset,
    Object? feedMode = _unset,
    Object? triggerKey = _unset,
    Object? reverseFeedKey = _unset,
    Object? triggerSpeed = _unset,
    Object? triggerTimeMs = _unset,
    Object? frictionMode = _unset,
    Object? frictionKey = _unset,
    Object? frictionUpKey = _unset,
    Object? frictionDownKey = _unset,
    Object? frictionMaxDuty = _unset,
    Object? frictionStep = _unset,
    bool? zeroEnabled,
    bool? buzzerDisabled,
  }) => InfantryConfig(
    remote: remote ?? this.remote,
    chassis: chassis ?? this.chassis,
    feederPin: identical(feederPin, _unset)
        ? this.feederPin
        : feederPin as String?,
    feederDirection: identical(feederDirection, _unset)
        ? this.feederDirection
        : feederDirection as Direction?,
    yawActuators: identical(yawActuators, _unset)
        ? this.yawActuators
        : List<AxisActuator>.from(yawActuators as List),
    pitchActuators: identical(pitchActuators, _unset)
        ? this.pitchActuators
        : List<AxisActuator>.from(pitchActuators as List),
    arrowBehavior: identical(arrowBehavior, _unset)
        ? this.arrowBehavior
        : arrowBehavior as ArrowBehavior?,
    feedMode: identical(feedMode, _unset)
        ? this.feedMode
        : feedMode as FeedMode?,
    triggerKey: identical(triggerKey, _unset)
        ? this.triggerKey
        : triggerKey as String?,
    reverseFeedKey: identical(reverseFeedKey, _unset)
        ? this.reverseFeedKey
        : reverseFeedKey as String?,
    triggerSpeed: identical(triggerSpeed, _unset)
        ? this.triggerSpeed
        : triggerSpeed as int?,
    triggerTimeMs: identical(triggerTimeMs, _unset)
        ? this.triggerTimeMs
        : triggerTimeMs as int?,
    frictionMode: identical(frictionMode, _unset)
        ? this.frictionMode
        : frictionMode as FrictionMode?,
    frictionKey: identical(frictionKey, _unset)
        ? this.frictionKey
        : frictionKey as String?,
    frictionUpKey: identical(frictionUpKey, _unset)
        ? this.frictionUpKey
        : frictionUpKey as String?,
    frictionDownKey: identical(frictionDownKey, _unset)
        ? this.frictionDownKey
        : frictionDownKey as String?,
    frictionMaxDuty: identical(frictionMaxDuty, _unset)
        ? this.frictionMaxDuty
        : frictionMaxDuty as int?,
    frictionStep: identical(frictionStep, _unset)
        ? this.frictionStep
        : frictionStep as int?,
    zeroEnabled: zeroEnabled ?? this.zeroEnabled,
    buzzerDisabled: buzzerDisabled ?? this.buzzerDisabled,
  );
  @override
  Map<String, Object?> toJson() => {
    'remote': remote.toJson(),
    'chassis': chassis.toJson(),
    'feeder_pin': feederPin,
    'feeder_direction': feederDirection?.name,
    'yaw': [for (final actuator in yawActuators) actuator.toJson()],
    'pitch': [for (final actuator in pitchActuators) actuator.toJson()],
    'arrow_behavior': arrowBehavior?.name,
    'feed_mode': feedMode?.name,
    'trigger_key': triggerKey,
    'reverse_feed_key': reverseFeedKey,
    'trigger_speed': triggerSpeed,
    'trigger_time_ms': triggerTimeMs,
    'friction_mode': frictionMode?.name,
    'friction_key': frictionKey,
    'friction_up_key': frictionUpKey,
    'friction_down_key': frictionDownKey,
    'friction_max_duty': frictionMaxDuty,
    'friction_step': frictionStep,
    'zero_enabled': zeroEnabled,
    'buzzer_disabled': buzzerDisabled,
  };
  factory InfantryConfig.fromJson(Map<String, Object?> j) {
    List<AxisActuator> actuators(String key) => [
      for (final raw in j[key] as List? ?? const [])
        if (raw is Map) AxisActuator.fromJson(Map<String, Object?>.from(raw)),
    ];
    return InfantryConfig(
      remote: RemoteConfig.fromJson(
        Map<String, Object?>.from(j['remote'] as Map? ?? {}),
      ),
      chassis: ChassisConfig.fromJson(
        Map<String, Object?>.from(j['chassis'] as Map? ?? {}),
      ),
      feederPin: j['feeder_pin']?.toString(),
      feederDirection: nullableEnumValue(
        Direction.values,
        j['feeder_direction'],
      ),
      yawActuators: actuators('yaw'),
      pitchActuators: actuators('pitch'),
      arrowBehavior: nullableEnumValue(
        ArrowBehavior.values,
        j['arrow_behavior'],
      ),
      feedMode: nullableEnumValue(FeedMode.values, j['feed_mode']),
      triggerKey: j['trigger_key']?.toString(),
      reverseFeedKey: j['reverse_feed_key']?.toString(),
      triggerSpeed: (j['trigger_speed'] as num?)?.toInt(),
      triggerTimeMs: (j['trigger_time_ms'] as num?)?.toInt(),
      frictionMode: nullableEnumValue(FrictionMode.values, j['friction_mode']),
      frictionKey: j['friction_key']?.toString(),
      frictionUpKey: j['friction_up_key']?.toString(),
      frictionDownKey: j['friction_down_key']?.toString(),
      frictionMaxDuty: (j['friction_max_duty'] as num?)?.toInt(),
      frictionStep: (j['friction_step'] as num?)?.toInt(),
      zeroEnabled: j['zero_enabled'] as bool? ?? false,
      buzzerDisabled: j['buzzer_disabled'] as bool? ?? false,
    );
  }
}

class PinAssignment {
  PinAssignment({
    required this.pin,
    required this.role,
    required String ownerFieldPath,
    required String ownerLabel,
  }) : ownerFieldPaths = List.unmodifiable([ownerFieldPath]),
       ownerLabels = List.unmodifiable([ownerLabel]);

  PinAssignment.shared({
    required this.pin,
    required this.role,
    required List<String> ownerFieldPaths,
    required List<String> ownerLabels,
  }) : ownerFieldPaths = List.unmodifiable(ownerFieldPaths),
       ownerLabels = List.unmodifiable(ownerLabels);

  final String pin;
  final PinRole role;
  final List<String> ownerFieldPaths;
  final List<String> ownerLabels;
  String get ownerFieldPath => ownerFieldPaths.first;
  String get ownerLabel => ownerLabels.join('、');
}

enum InfantryPinReassignmentStrategy {
  direct,
  swap,
  takeOver,
  disableFrictionAndTakeOver,
  enableFrictionAndTakeOver,
}

class InfantryPinReassignmentOption {
  const InfantryPinReassignmentOption({
    required this.strategy,
    required this.result,
  });

  final InfantryPinReassignmentStrategy strategy;
  final InfantryConfig result;
}

class InfantryPinReassignmentPlan {
  InfantryPinReassignmentPlan({
    required this.fieldPath,
    required this.targetPin,
    required List<PinAssignment> occupants,
    required List<InfantryPinReassignmentOption> options,
  }) : occupants = List.unmodifiable(occupants),
       options = List.unmodifiable(options);

  final String fieldPath;
  final String? targetPin;
  final List<PinAssignment> occupants;
  final List<InfantryPinReassignmentOption> options;

  bool get hasConflict => occupants.isNotEmpty;

  bool supports(InfantryPinReassignmentStrategy strategy) =>
      options.any((option) => option.strategy == strategy);
}

abstract final class InfantryPinPlanner {
  static const pwmaFrequency = PwmFrequency.hz50;
  static const pwmbFrequency = PwmFrequency.hz10000;
  static const frictionPins = ['P64', 'P66'];
  static const motorPins = expansionPins;
  static const servoPins = [...expansionPins, ...mainServoPins];

  static String normalizePin(String? value) => value?.split(' ').first ?? '';

  /// 云台执行器在引脚字段路径里的定位。
  static String axisPath(bool yaw, int index, String field) =>
      'gimbal.${yaw ? 'yaw' : 'pitch'}.$index.$field';

  /// 解析 `gimbal.<yaw|pitch>.<index>.<field>` 形式的路径，非云台路径返回 null。
  static ({bool yaw, int index, String field})? parseAxisPath(
    String fieldPath,
  ) {
    final parts = fieldPath.split('.');
    if (parts.length != 4 || parts.first != 'gimbal') return null;
    final yaw = switch (parts[1]) {
      'yaw' => true,
      'pitch' => false,
      _ => null,
    };
    final index = int.tryParse(parts[2]);
    if (yaw == null || index == null || index < 0) return null;
    return (yaw: yaw, index: index, field: parts[3]);
  }

  /// 执行器在界面与报错里的显示名，单执行器时与旧文案一致。
  static String axisLabel(bool yaw, int index) =>
      '${yaw ? 'Yaw' : 'Pitch'} 轴${index == 0 ? '' : ' ${index + 1}'}';

  static AxisActuator? _actuatorAt(
    InfantryConfig config,
    ({bool yaw, int index, String field}) axis,
  ) {
    final actuators = config.actuators(axis.yaw);
    return axis.index < actuators.length ? actuators[axis.index] : null;
  }

  static String? _chassisSide(String fieldPath) => switch (fieldPath) {
    'chassis.left_front.pin' || 'chassis.left_rear.pin' => 'left',
    'chassis.right_front.pin' || 'chassis.right_rear.pin' => 'right',
    _ => null,
  };

  static bool _canShare(String firstFieldPath, String secondFieldPath) {
    final firstSide = _chassisSide(firstFieldPath);
    return firstSide != null && firstSide == _chassisSide(secondFieldPath);
  }

  static String? _fieldPin(InfantryConfig config, String fieldPath) {
    final axis = parseAxisPath(fieldPath);
    if (axis != null) return _actuatorAt(config, axis)?.pin;
    return switch (fieldPath) {
      'chassis.left_front.pin' => config.chassis.leftFront.pin,
      'chassis.left_rear.pin' => config.chassis.leftRear.pin,
      'chassis.right_front.pin' => config.chassis.rightFront.pin,
      'chassis.right_rear.pin' => config.chassis.rightRear.pin,
      'mechanism.feeder_pin' => config.feederPin,
      _ => throw ArgumentError.value(fieldPath, 'fieldPath', '未知引脚字段'),
    };
  }

  static List<PinAssignment> _references(InfantryConfig config) => [
    if (config.chassis.leftFront.pin != null)
      PinAssignment(
        pin: normalizePin(config.chassis.leftFront.pin),
        role: PinRole.motor,
        ownerFieldPath: 'chassis.left_front.pin',
        ownerLabel: '左前轮',
      ),
    if (config.chassis.leftRear.pin != null)
      PinAssignment(
        pin: normalizePin(config.chassis.leftRear.pin),
        role: PinRole.motor,
        ownerFieldPath: 'chassis.left_rear.pin',
        ownerLabel: '左后轮',
      ),
    if (config.chassis.rightFront.pin != null)
      PinAssignment(
        pin: normalizePin(config.chassis.rightFront.pin),
        role: PinRole.motor,
        ownerFieldPath: 'chassis.right_front.pin',
        ownerLabel: '右前轮',
      ),
    if (config.chassis.rightRear.pin != null)
      PinAssignment(
        pin: normalizePin(config.chassis.rightRear.pin),
        role: PinRole.motor,
        ownerFieldPath: 'chassis.right_rear.pin',
        ownerLabel: '右后轮',
      ),
    if (config.feederPin != null)
      PinAssignment(
        pin: config.feederPin!,
        role: PinRole.motor,
        ownerFieldPath: 'mechanism.feeder_pin',
        ownerLabel: '拨弹电机',
      ),
    for (var index = 0; index < config.yawActuators.length; index += 1)
      if (config.yawActuators[index].pin != null &&
          config.yawActuators[index].drive != null)
        PinAssignment(
          pin: config.yawActuators[index].pin!,
          role: config.yawActuators[index].drive == DriveType.servo
              ? PinRole.servo
              : PinRole.motor,
          ownerFieldPath: axisPath(true, index, 'pin'),
          ownerLabel: axisLabel(true, index),
        ),
    for (var index = 0; index < config.pitchActuators.length; index += 1)
      if (config.pitchActuators[index].pin != null &&
          config.pitchActuators[index].drive != null)
        PinAssignment(
          pin: config.pitchActuators[index].pin!,
          role: config.pitchActuators[index].drive == DriveType.servo
              ? PinRole.servo
              : PinRole.motor,
          ownerFieldPath: axisPath(false, index, 'pin'),
          ownerLabel: axisLabel(false, index),
        ),
    if (config.frictionMode == FrictionMode.brushlessEsc)
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
        result[assignment.pin] = PinAssignment.shared(
          pin: assignment.pin,
          role: assignment.role,
          ownerFieldPaths: [
            ...previous.ownerFieldPaths,
            ...assignment.ownerFieldPaths,
          ],
          ownerLabels: [...previous.ownerLabels, ...assignment.ownerLabels],
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
    final axis = parseAxisPath(fieldPath);
    if (axis != null) {
      final selectedDrive = driveType ?? _actuatorAt(config, axis)?.drive;
      return List.unmodifiable(
        selectedDrive == null
            ? const <String>[]
            : selectedDrive == DriveType.servo
            ? servoPins
            : motorPins,
      );
    }
    final candidates = switch (fieldPath) {
      'chassis.left_front.pin' ||
      'chassis.left_rear.pin' ||
      'chassis.right_front.pin' ||
      'chassis.right_rear.pin' => chassisPins,
      'mechanism.feeder_pin' => motorPins,
      _ => const <String>[],
    };
    return List.unmodifiable(candidates);
  }

  static List<PinAssignment> occupantsOf(
    InfantryConfig config,
    String pin,
    String excludingFieldPath,
  ) {
    final normalized = normalizePin(pin);
    return List.unmodifiable(
      _references(config).where(
        (assignment) =>
            assignment.ownerFieldPath != excludingFieldPath &&
            !_canShare(excludingFieldPath, assignment.ownerFieldPath) &&
            assignment.pin == normalized,
      ),
    );
  }

  static PinAssignment? occupiedBy(
    InfantryConfig config,
    String pin,
    String excludingFieldPath,
  ) {
    final occupants = occupantsOf(config, pin, excludingFieldPath);
    if (occupants.isEmpty) return null;
    return PinAssignment.shared(
      pin: normalizePin(pin),
      role: occupants.first.role,
      ownerFieldPaths: [
        for (final occupant in occupants) ...occupant.ownerFieldPaths,
      ],
      ownerLabels: [for (final occupant in occupants) ...occupant.ownerLabels],
    );
  }

  static InfantryPinReassignmentPlan planReassignment(
    InfantryConfig config,
    String fieldPath,
    String? targetPin,
  ) {
    final normalizedTarget = normalizePin(targetPin);
    if (targetPin != null &&
        !allowedPins(
          config,
          fieldPath,
        ).any((candidate) => normalizePin(candidate) == normalizedTarget)) {
      throw ArgumentError.value(targetPin, 'targetPin', '目标引脚与设备不兼容');
    }
    final occupants = targetPin == null
        ? const <PinAssignment>[]
        : occupantsOf(config, normalizedTarget, fieldPath);
    if (occupants.isEmpty) {
      return InfantryPinReassignmentPlan(
        fieldPath: fieldPath,
        targetPin: targetPin,
        occupants: occupants,
        options: [
          InfantryPinReassignmentOption(
            strategy: InfantryPinReassignmentStrategy.direct,
            result: _setPin(config, fieldPath, targetPin),
          ),
        ],
      );
    }

    final hasFriction = occupants.any(
      (occupant) => occupant.role == PinRole.friction,
    );
    if (hasFriction) {
      var result = config.copyWith(frictionMode: FrictionMode.disabled);
      for (final occupant in occupants.where(
        (occupant) => occupant.role != PinRole.friction,
      )) {
        result = _setPin(result, occupant.ownerFieldPath, null);
      }
      result = _setPin(result, fieldPath, targetPin);
      return InfantryPinReassignmentPlan(
        fieldPath: fieldPath,
        targetPin: targetPin,
        occupants: occupants,
        options: [
          InfantryPinReassignmentOption(
            strategy:
                InfantryPinReassignmentStrategy.disableFrictionAndTakeOver,
            result: result,
          ),
        ],
      );
    }

    var takeOverResult = config;
    for (final occupant in occupants) {
      takeOverResult = _setPin(takeOverResult, occupant.ownerFieldPath, null);
    }
    takeOverResult = _setPin(takeOverResult, fieldPath, targetPin);
    final options = <InfantryPinReassignmentOption>[
      InfantryPinReassignmentOption(
        strategy: InfantryPinReassignmentStrategy.takeOver,
        result: takeOverResult,
      ),
    ];

    final currentPin = _fieldPin(config, fieldPath);
    final normalizedCurrent = normalizePin(currentPin);
    final canMoveOccupants =
        normalizedCurrent.isNotEmpty &&
        occupants.every(
          (occupant) =>
              _supportsPin(config, occupant.ownerFieldPath, normalizedCurrent),
        );
    if (canMoveOccupants) {
      var swapResult = config;
      for (final occupant in occupants) {
        swapResult = _setPin(swapResult, occupant.ownerFieldPath, null);
      }
      swapResult = _setPin(swapResult, fieldPath, targetPin);
      for (final occupant in occupants) {
        swapResult = _setPin(
          swapResult,
          occupant.ownerFieldPath,
          normalizedCurrent,
        );
      }
      if (!_pinHasConflict(swapResult, normalizedCurrent) &&
          !_pinHasConflict(swapResult, normalizedTarget)) {
        options.insert(
          0,
          InfantryPinReassignmentOption(
            strategy: InfantryPinReassignmentStrategy.swap,
            result: swapResult,
          ),
        );
      }
    }
    return InfantryPinReassignmentPlan(
      fieldPath: fieldPath,
      targetPin: targetPin,
      occupants: occupants,
      options: options,
    );
  }

  static InfantryConfig applyReassignment(
    InfantryConfig config,
    String fieldPath,
    String? targetPin,
    InfantryPinReassignmentStrategy strategy,
  ) {
    final plan = planReassignment(config, fieldPath, targetPin);
    for (final option in plan.options) {
      if (option.strategy == strategy) return option.result;
    }
    throw StateError('当前引脚分配不支持 ${strategy.name}');
  }

  static InfantryPinReassignmentPlan planFrictionEnablement(
    InfantryConfig config,
  ) {
    final occupants = <PinAssignment>[
      for (final pin in frictionPins)
        ..._references(config).where(
          (assignment) =>
              assignment.pin == pin && assignment.role != PinRole.friction,
        ),
    ];
    if (occupants.isEmpty) {
      return InfantryPinReassignmentPlan(
        fieldPath: 'controls.friction_mode',
        targetPin: null,
        occupants: occupants,
        options: [
          InfantryPinReassignmentOption(
            strategy: InfantryPinReassignmentStrategy.direct,
            result: config.copyWith(frictionMode: FrictionMode.brushlessEsc),
          ),
        ],
      );
    }
    var result = config;
    for (final occupant in occupants) {
      result = _setPin(result, occupant.ownerFieldPath, null);
    }
    result = result.copyWith(frictionMode: FrictionMode.brushlessEsc);
    return InfantryPinReassignmentPlan(
      fieldPath: 'controls.friction_mode',
      targetPin: null,
      occupants: occupants,
      options: [
        InfantryPinReassignmentOption(
          strategy: InfantryPinReassignmentStrategy.enableFrictionAndTakeOver,
          result: result,
        ),
      ],
    );
  }

  static InfantryConfig applyFrictionEnablement(
    InfantryConfig config,
    InfantryPinReassignmentStrategy strategy,
  ) {
    final plan = planFrictionEnablement(config);
    for (final option in plan.options) {
      if (option.strategy == strategy) return option.result;
    }
    throw StateError('当前配置不支持 ${strategy.name}');
  }

  static bool _supportsPin(
    InfantryConfig config,
    String fieldPath,
    String normalizedPin,
  ) => allowedPins(
    config,
    fieldPath,
  ).any((candidate) => normalizePin(candidate) == normalizedPin);

  static String? _canonicalPin(
    InfantryConfig config,
    String fieldPath,
    String? pin,
  ) {
    if (pin == null) return null;
    final normalized = normalizePin(pin);
    for (final candidate in allowedPins(config, fieldPath)) {
      if (normalizePin(candidate) == normalized) return candidate;
    }
    throw ArgumentError.value(pin, 'pin', '引脚与设备不兼容');
  }

  static InfantryConfig _setPin(
    InfantryConfig config,
    String fieldPath,
    String? pin,
  ) {
    final value = _canonicalPin(config, fieldPath, pin);
    final axis = parseAxisPath(fieldPath);
    if (axis != null) return _setActuatorPin(config, axis, value);
    return switch (fieldPath) {
      'chassis.left_front.pin' => config.copyWith(
        chassis: config.chassis.copyWith(
          leftFront: config.chassis.leftFront.copyWith(pin: value),
        ),
      ),
      'chassis.left_rear.pin' => config.copyWith(
        chassis: config.chassis.copyWith(
          leftRear: config.chassis.leftRear.copyWith(pin: value),
        ),
      ),
      'chassis.right_front.pin' => config.copyWith(
        chassis: config.chassis.copyWith(
          rightFront: config.chassis.rightFront.copyWith(pin: value),
        ),
      ),
      'chassis.right_rear.pin' => config.copyWith(
        chassis: config.chassis.copyWith(
          rightRear: config.chassis.rightRear.copyWith(pin: value),
        ),
      ),
      'mechanism.feeder_pin' => config.copyWith(feederPin: value),
      _ => throw ArgumentError.value(fieldPath, 'fieldPath', '未知引脚字段'),
    };
  }

  static InfantryConfig _setActuatorPin(
    InfantryConfig config,
    ({bool yaw, int index, String field}) axis,
    String? pin,
  ) {
    final actuators = [...config.actuators(axis.yaw)];
    if (axis.index >= actuators.length) {
      throw ArgumentError.value(axis.index, 'fieldPath', '执行器不存在');
    }
    actuators[axis.index] = actuators[axis.index].copyWith(pin: pin);
    return axis.yaw
        ? config.copyWith(yawActuators: actuators)
        : config.copyWith(pitchActuators: actuators);
  }

  static bool _pinHasConflict(InfantryConfig config, String pin) {
    final references = _references(config)
        .where((assignment) => assignment.pin == pin)
        .toList();
    for (var first = 0; first < references.length; first += 1) {
      for (var second = first + 1; second < references.length; second += 1) {
        if (!_canShare(
          references[first].ownerFieldPath,
          references[second].ownerFieldPath,
        )) {
          return true;
        }
      }
    }
    return false;
  }
}

class ActionMapping {
  ActionMapping({
    String? id,
    this.key,
    this.direction,
    this.mode,
    this.parameter,
    this.pin,
  }) : id = id ?? DateTime.now().microsecondsSinceEpoch.toString();
  final String id;
  final String? key, pin;
  final Direction? direction;
  final ControlMode? mode;
  final num? parameter;
  ActionMapping copyWith({
    Object? key = _unset,
    Object? direction = _unset,
    Object? mode = _unset,
    Object? parameter = _unset,
    Object? pin = _unset,
  }) => ActionMapping(
    id: id,
    key: identical(key, _unset) ? this.key : key as String?,
    direction: identical(direction, _unset)
        ? this.direction
        : direction as Direction?,
    mode: identical(mode, _unset) ? this.mode : mode as ControlMode?,
    parameter: identical(parameter, _unset)
        ? this.parameter
        : parameter as num?,
    pin: identical(pin, _unset) ? this.pin : pin as String?,
  );
  Map<String, Object?> toJson() => {
    'id': id,
    'key': key,
    'direction': direction?.name,
    'mode': mode?.name,
    'parameter': parameter,
    'pin': pin,
  };
  factory ActionMapping.fromJson(Map<String, Object?> j) => ActionMapping(
    id: j['id']?.toString(),
    key: j['key']?.toString(),
    direction: nullableEnumValue(Direction.values, j['direction']),
    mode: nullableEnumValue(ControlMode.values, j['mode']),
    parameter: j['parameter'] as num?,
    pin: j['pin']?.toString(),
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
    this.modeCount,
    this.switchStrategy,
    this.modeSwitchKey,
    List<String?>? modeKeys,
    List<EngineerModeConfig>? modes,
  }) : modeKeys = List.unmodifiable(modeKeys ?? const [null, null, null, null]),
       modes = List.unmodifiable(
         modes ?? [EngineerModeConfig(preserveChassis: true)],
       ),
       pwm = pwm ?? PwmGroupConfig(),
       super(chassis: chassis ?? ChassisConfig.defaults());
  @override
  ProjectKind get kind => ProjectKind.engineer;
  final int? modeCount;
  final SwitchStrategy? switchStrategy;
  final String? modeSwitchKey;
  final List<String?> modeKeys;
  final List<EngineerModeConfig> modes;
  final PwmGroupConfig pwm;
  EngineerConfig copyWith({
    RemoteConfig? remote,
    ChassisConfig? chassis,
    PwmGroupConfig? pwm,
    Object? modeCount = _unset,
    Object? switchStrategy = _unset,
    Object? modeSwitchKey = _unset,
    List<String?>? modeKeys,
    List<EngineerModeConfig>? modes,
  }) => EngineerConfig(
    remote: remote ?? this.remote,
    chassis: chassis ?? this.chassis,
    pwm: pwm ?? this.pwm,
    modeCount: identical(modeCount, _unset)
        ? this.modeCount
        : modeCount as int?,
    switchStrategy: identical(switchStrategy, _unset)
        ? this.switchStrategy
        : switchStrategy as SwitchStrategy?,
    modeSwitchKey: identical(modeSwitchKey, _unset)
        ? this.modeSwitchKey
        : modeSwitchKey as String?,
    modeKeys: modeKeys ?? this.modeKeys,
    modes: modes ?? this.modes,
  );
  @override
  Map<String, Object?> toJson() => {
    'remote': remote.toJson(),
    'chassis': chassis.toJson(),
    'pwm': pwm.toJson(),
    'mode_count': modeCount,
    'switch_strategy': switchStrategy?.name,
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
    modeCount: (j['mode_count'] as num?)?.toInt(),
    switchStrategy: nullableEnumValue(
      SwitchStrategy.values,
      j['switch_strategy'],
    ),
    modeSwitchKey: j['mode_switch_key']?.toString(),
    modeKeys: [
      for (final e in (j['mode_keys'] as List? ?? const [])) e?.toString(),
      for (var i = (j['mode_keys'] as List? ?? const []).length; i < 4; i++)
        null,
    ].take(4).toList(),
    modes: (j['modes'] as List? ?? [])
        .map(
          (m) =>
              EngineerModeConfig.fromJson(Map<String, Object?>.from(m as Map)),
        )
        .toList(),
  );
}

class GuideProgress {
  const GuideProgress({
    required this.currentStepId,
    required this.visitedStepIds,
  });

  factory GuideProgress.initial([ProjectKind kind = ProjectKind.infantry]) {
    final first = switch (kind) {
      ProjectKind.debug => 'tests',
      ProjectKind.music => 'music',
      _ => 'remote',
    };
    return GuideProgress(currentStepId: first, visitedStepIds: [first]);
  }

  final String currentStepId;
  final List<String> visitedStepIds;

  GuideProgress copyWith({
    String? currentStepId,
    List<String>? visitedStepIds,
  }) => GuideProgress(
    currentStepId: currentStepId ?? this.currentStepId,
    visitedStepIds: List.unmodifiable(visitedStepIds ?? this.visitedStepIds),
  );

  Map<String, Object?> toJson() => {
    'current_step_id': currentStepId,
    'visited_step_ids': visitedStepIds,
  };

  factory GuideProgress.fromJson(
    Map<String, Object?> json, [
    ProjectKind kind = ProjectKind.infantry,
  ]) {
    final first = switch (kind) {
      ProjectKind.debug => 'tests',
      ProjectKind.music => 'music',
      _ => 'remote',
    };
    return GuideProgress(
      currentStepId: json['current_step_id']?.toString() ?? first,
      visitedStepIds: List.unmodifiable(
        (json['visited_step_ids'] as List? ?? [first]).map(
          (item) => item.toString(),
        ),
      ),
    );
  }
}

class ProjectDocument {
  const ProjectDocument({
    required this.name,
    required this.kind,
    required this.createdAt,
    required this.updatedAt,
    required this.config,
    required this.guideProgress,
  });
  static const formatVersion = 15;
  final String name;
  final ProjectKind kind;
  final DateTime createdAt, updatedAt;
  final ProjectConfig config;
  final GuideProgress guideProgress;
  factory ProjectDocument.create(String name, ProjectKind kind) {
    final now = DateTime.now().toUtc();
    return ProjectDocument(
      name: name,
      kind: kind,
      createdAt: now,
      updatedAt: now,
      config: switch (kind) {
        ProjectKind.infantry => InfantryConfig(),
        ProjectKind.engineer => EngineerConfig(),
        ProjectKind.debug => DebugConfig(),
        ProjectKind.music => MusicConfig(),
      },
      guideProgress: GuideProgress.initial(kind),
    );
  }
  ProjectDocument copyWith({
    String? name,
    ProjectConfig? config,
    GuideProgress? guideProgress,
  }) => ProjectDocument(
    name: name ?? this.name,
    kind: kind,
    createdAt: createdAt,
    updatedAt: DateTime.now().toUtc(),
    config: config ?? this.config,
    guideProgress: guideProgress ?? this.guideProgress,
  );
  Map<String, Object?> toJson() => {
    'format_version': formatVersion,
    'name': name,
    'project_kind': kind.name,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'guide_progress': guideProgress.toJson(),
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
      guideProgress: GuideProgress.fromJson(
        Map<String, Object?>.from(j['guide_progress'] as Map? ?? {}),
        kind,
      ),
      config: switch (kind) {
        ProjectKind.infantry => InfantryConfig.fromJson(config),
        ProjectKind.engineer => EngineerConfig.fromJson(config),
        ProjectKind.debug => DebugConfig.fromJson(config),
        ProjectKind.music => MusicConfig.fromJson(config),
      },
    );
  }
}

class ValidationIssue {
  const ValidationIssue({
    required this.severity,
    required this.fieldPath,
    required this.message,
    required this.stepId,
    this.kind = ValidationIssueKind.invalid,
  });
  final IssueSeverity severity;
  final String fieldPath, message, stepId;
  final ValidationIssueKind kind;
}

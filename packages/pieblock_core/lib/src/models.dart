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

enum ControlMode { direct, incremental, speed, accelerate }

enum IssueSeverity { error, warning }

enum ValidationIssueKind { required, invalid }

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
  });
  factory ChassisConfig.defaults() => const ChassisConfig();
  final WheelConfig leftFront, leftRear, rightFront, rightRear;
  final int? normalSpeed, sprintSpeed;
  final bool sprintEnabled;
  ChassisConfig copyWith({
    WheelConfig? leftFront,
    WheelConfig? leftRear,
    WheelConfig? rightFront,
    WheelConfig? rightRear,
    Object? normalSpeed = _unset,
    Object? sprintSpeed = _unset,
    bool? sprintEnabled,
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
         tempoEvents ?? const [TempoEvent(tick: 0, microsecondsPerQuarter: 500000)],
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

class InfantryConfig extends RobotConfig {
  InfantryConfig({
    super.remote = const RemoteConfig(),
    ChassisConfig? chassis,
    this.feederPin,
    this.feederDirection,
    this.yawDrive,
    this.yawPin,
    this.yawDirection,
    this.yawMidOffset,
    this.pitchDrive,
    this.pitchPin,
    this.pitchDirection,
    this.pitchMidOffset,
    this.arrowBehavior,
    this.feedMode,
    this.triggerKey,
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
  }) : super(chassis: chassis ?? ChassisConfig.defaults());
  @override
  ProjectKind get kind => ProjectKind.infantry;
  final String? feederPin,
      yawPin,
      pitchPin,
      triggerKey,
      frictionKey,
      frictionUpKey,
      frictionDownKey;
  final ArrowBehavior? arrowBehavior;
  final FeedMode? feedMode;
  final FrictionMode? frictionMode;
  final Direction? feederDirection, yawDirection, pitchDirection;
  final DriveType? yawDrive, pitchDrive;
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
    Object? feederPin = _unset,
    Object? feederDirection = _unset,
    Object? yawDrive = _unset,
    Object? yawPin = _unset,
    Object? yawDirection = _unset,
    Object? yawMidOffset = _unset,
    Object? pitchDrive = _unset,
    Object? pitchPin = _unset,
    Object? pitchDirection = _unset,
    Object? pitchMidOffset = _unset,
    Object? arrowBehavior = _unset,
    Object? feedMode = _unset,
    Object? triggerKey = _unset,
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
    yawDrive: identical(yawDrive, _unset)
        ? this.yawDrive
        : yawDrive as DriveType?,
    yawPin: identical(yawPin, _unset) ? this.yawPin : yawPin as String?,
    yawDirection: identical(yawDirection, _unset)
        ? this.yawDirection
        : yawDirection as Direction?,
    yawMidOffset: identical(yawMidOffset, _unset)
        ? this.yawMidOffset
        : yawMidOffset as int?,
    pitchDrive: identical(pitchDrive, _unset)
        ? this.pitchDrive
        : pitchDrive as DriveType?,
    pitchPin: identical(pitchPin, _unset) ? this.pitchPin : pitchPin as String?,
    pitchDirection: identical(pitchDirection, _unset)
        ? this.pitchDirection
        : pitchDirection as Direction?,
    pitchMidOffset: identical(pitchMidOffset, _unset)
        ? this.pitchMidOffset
        : pitchMidOffset as int?,
    arrowBehavior: identical(arrowBehavior, _unset)
        ? this.arrowBehavior
        : arrowBehavior as ArrowBehavior?,
    feedMode: identical(feedMode, _unset)
        ? this.feedMode
        : feedMode as FeedMode?,
    triggerKey: identical(triggerKey, _unset)
        ? this.triggerKey
        : triggerKey as String?,
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
    'yaw': {
      'drive': yawDrive?.name,
      'pin': yawPin,
      'direction': yawDirection?.name,
      'mid_offset': yawMidOffset,
    },
    'pitch': {
      'drive': pitchDrive?.name,
      'pin': pitchPin,
      'direction': pitchDirection?.name,
      'mid_offset': pitchMidOffset,
    },
    'arrow_behavior': arrowBehavior?.name,
    'feed_mode': feedMode?.name,
    'trigger_key': triggerKey,
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
    final y = Map<String, Object?>.from(j['yaw'] as Map? ?? {}),
        p = Map<String, Object?>.from(j['pitch'] as Map? ?? {});
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
      yawDrive: nullableEnumValue(DriveType.values, y['drive']),
      yawPin: y['pin']?.toString(),
      yawDirection: nullableEnumValue(Direction.values, y['direction']),
      yawMidOffset: (y['mid_offset'] as num?)?.toInt(),
      pitchDrive: nullableEnumValue(DriveType.values, p['drive']),
      pitchPin: p['pin']?.toString(),
      pitchDirection: nullableEnumValue(Direction.values, p['direction']),
      pitchMidOffset: (p['mid_offset'] as num?)?.toInt(),
      arrowBehavior: nullableEnumValue(
        ArrowBehavior.values,
        j['arrow_behavior'],
      ),
      feedMode: nullableEnumValue(FeedMode.values, j['feed_mode']),
      triggerKey: j['trigger_key']?.toString(),
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

abstract final class InfantryPinPlanner {
  static const pwmaFrequency = PwmFrequency.hz50;
  static const pwmbFrequency = PwmFrequency.hz10000;
  static const frictionPins = ['P64', 'P66'];
  static const motorPins = expansionPins;
  static const servoPins = [...expansionPins, ...mainServoPins];

  static String normalizePin(String? value) => value?.split(' ').first ?? '';

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
    if (config.yawPin != null && config.yawDrive != null)
      PinAssignment(
        pin: config.yawPin!,
        role: config.yawDrive == DriveType.servo
            ? PinRole.servo
            : PinRole.motor,
        ownerFieldPath: 'gimbal.yaw.pin',
        ownerLabel: 'Yaw 轴',
      ),
    if (config.pitchPin != null && config.pitchDrive != null)
      PinAssignment(
        pin: config.pitchPin!,
        role: config.pitchDrive == DriveType.servo
            ? PinRole.servo
            : PinRole.motor,
        ownerFieldPath: 'gimbal.pitch.pin',
        ownerLabel: 'Pitch 轴',
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
    final selectedDrive =
        driveType ??
        (fieldPath == 'gimbal.yaw.pin' ? config.yawDrive : config.pitchDrive);
    final candidates = switch (fieldPath) {
      'chassis.left_front.pin' ||
      'chassis.left_rear.pin' ||
      'chassis.right_front.pin' ||
      'chassis.right_rear.pin' => chassisPins,
      'mechanism.feeder_pin' => motorPins,
      'gimbal.yaw.pin' || 'gimbal.pitch.pin' =>
        selectedDrive == null
            ? const <String>[]
            : selectedDrive == DriveType.servo
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
  final int? parameter;
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
        : parameter as int?,
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
    parameter: (j['parameter'] as num?)?.toInt(),
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
  static const formatVersion = 14;
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

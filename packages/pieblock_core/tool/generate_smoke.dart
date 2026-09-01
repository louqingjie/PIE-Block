import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

ChassisConfig chassis() => const ChassisConfig(
  leftFront: WheelConfig('P74 P24', Direction.forward),
  leftRear: WheelConfig('P75 P25', Direction.forward),
  rightFront: WheelConfig('P76 P26', Direction.reverse),
  rightRear: WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 4000,
  sprintSpeed: 8000,
);

InfantryConfig infantry() => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: chassis(),
  feederPin: 'P60',
  feederDirection: Direction.forward,
  yawDrive: DriveType.servo,
  yawPin: 'MP74',
  yawDirection: Direction.forward,
  yawMidOffset: 0,
  pitchDrive: DriveType.servo,
  pitchPin: 'MP03',
  pitchDirection: Direction.forward,
  pitchMidOffset: 0,
  arrowBehavior: ArrowBehavior.other,
  feedMode: FeedMode.blockingOpenLoop,
  triggerKey: 'E',
  triggerSpeed: 6000,
  triggerTimeMs: 250,
  frictionMode: FrictionMode.brushlessEsc,
  frictionKey: 'A',
  frictionUpKey: 'B',
  frictionDownKey: 'C',
  frictionMaxDuty: 800,
  frictionStep: 100,
);

EngineerConfig engineer() => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: chassis(),
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz10000,
    pwmb: PwmFrequency.hz10000,
    pinRoles: {
      for (final pin in expansionPins)
        pin: EngineerPinCapabilities.frictionPins.contains(pin)
            ? PinRole.friction
            : PinRole.motor,
    },
    servoMids: const {'MP03': 0, 'MP74': 0},
  ),
  modeCount: 1,
  modes: [EngineerModeConfig(preserveChassis: true)],
);

DebugConfig debug() => DebugConfig(
  tests: [
    const DebugTestItem(
      pin: 'P60',
      enabled: true,
      driveType: DebugDriveType.motor,
      direction: Direction.forward,
      value: 2000,
      durationMs: 3000,
    ),
    const DebugTestItem(
      pin: 'P64',
      enabled: true,
      driveType: DebugDriveType.friction,
      direction: Direction.forward,
      value: 750,
    ),
    const DebugTestItem(
      pin: 'MP03',
      enabled: true,
      driveType: DebugDriveType.servo,
      direction: Direction.reverse,
      value: 30,
    ),
    for (final pin in debugPins.where(
      (pin) => pin != 'P60' && pin != 'P64' && pin != 'MP03',
    ))
      DebugTestItem(pin: pin),
  ],
);

MusicConfig music() => MusicConfig(
  notes: const [
    MusicNote(id: 'c4', pitch: 60, startTick: 0, durationTicks: 480),
    MusicNote(id: 'e4', pitch: 64, startTick: 720, durationTicks: 480),
  ],
  tempoEvents: const [
    TempoEvent(tick: 0, microsecondsPerQuarter: 500000),
    TempoEvent(tick: 960, microsecondsPerQuarter: 400000),
  ],
);

void main(List<String> arguments) {
  if (arguments.length != 1) {
    stderr.writeln('用法：dart run tool/generate_smoke.dart <输出目录>');
    exitCode = 64;
    return;
  }
  final directory = Directory(arguments.single)..createSync(recursive: true);
  File('${directory.path}${Platform.pathSeparator}infantry.c')
      .writeAsStringSync(CodeGenerator.generate(infantry()));
  File('${directory.path}${Platform.pathSeparator}engineer.c')
      .writeAsStringSync(CodeGenerator.generate(engineer()));
  File('${directory.path}${Platform.pathSeparator}debug.c')
      .writeAsStringSync(CodeGenerator.generate(debug()));
  File('${directory.path}${Platform.pathSeparator}music.c')
      .writeAsStringSync(CodeGenerator.generate(music()));
}

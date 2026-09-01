import 'package:pieblock_core/pieblock_core.dart';

final class SdccGoldenCase {
  const SdccGoldenCase({
    required this.id,
    required this.kind,
    required this.config,
    required this.expectedHexSha256,
  });

  final String id;
  final ProjectKind kind;
  final ProjectConfig config;
  final String expectedHexSha256;
}

const _baselineHashes = <String, String>{
  'infantry_servo_blocking_friction':
      '33ef407ea1ec2533296b63bb46068cf7bd755ca805f0e876d13cd0faf01ecdbb',
  'engineer_single_mode':
      '15cd88d8b7fc8c6b835ad8ed98bb6ae6473416a0da29817c0d36e8543f0937bd',
  'infantry_motor_visual_no_friction':
      '5f275edffd755ef6ed97202a549e3ccb6fd71985ef3783ca639bcfd377f9ee9e',
  'infantry_shared_chassis_sprint':
      '51924b76d7bc8386d3871d21ad90e50dda648767a6ddf1a4b58df1494989326f',
  'engineer_four_mode_cycle':
      'aa0f05103e0aadb21e2b2222ee6e58cbecebd16b1a05a23df17203b513ac9035',
  'engineer_four_mode_direct':
      '3d8a2dd67bf2f828e8bd8633a2dde76a478f16cf4bf204bf5a0ef300c325d67f',
};

final sdccGoldenCases = <SdccGoldenCase>[
  SdccGoldenCase(
    id: 'infantry_servo_blocking_friction',
    kind: ProjectKind.infantry,
    config: _infantryServoBlockingFriction(),
    expectedHexSha256: _baselineHashes['infantry_servo_blocking_friction']!,
  ),
  SdccGoldenCase(
    id: 'infantry_motor_visual_no_friction',
    kind: ProjectKind.infantry,
    config: _infantryMotorVisualNoFriction(),
    expectedHexSha256: _baselineHashes['infantry_motor_visual_no_friction']!,
  ),
  SdccGoldenCase(
    id: 'infantry_shared_chassis_sprint',
    kind: ProjectKind.infantry,
    config: _infantrySharedChassisSprint(),
    expectedHexSha256: _baselineHashes['infantry_shared_chassis_sprint']!,
  ),
  SdccGoldenCase(
    id: 'engineer_single_mode',
    kind: ProjectKind.engineer,
    config: _engineerSingleMode(),
    expectedHexSha256: _baselineHashes['engineer_single_mode']!,
  ),
  SdccGoldenCase(
    id: 'engineer_four_mode_cycle',
    kind: ProjectKind.engineer,
    config: _engineerAdvanced(SwitchStrategy.cycle),
    expectedHexSha256: _baselineHashes['engineer_four_mode_cycle']!,
  ),
  SdccGoldenCase(
    id: 'engineer_four_mode_direct',
    kind: ProjectKind.engineer,
    config: _engineerAdvanced(SwitchStrategy.direct),
    expectedHexSha256: _baselineHashes['engineer_four_mode_direct']!,
  ),
];

ChassisConfig _chassis({bool shared = false}) => ChassisConfig(
  leftFront: const WheelConfig('P74 P24', Direction.forward),
  leftRear: WheelConfig(shared ? 'P74 P24' : 'P75 P25', Direction.forward),
  rightFront: const WheelConfig('P76 P26', Direction.reverse),
  rightRear: const WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 4000,
  sprintSpeed: 8000,
);

InfantryConfig _infantryServoBlockingFriction() => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: _chassis(),
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

InfantryConfig _infantryMotorVisualNoFriction() => InfantryConfig(
  remote: const RemoteConfig(channel: 77, deadzone: 240),
  chassis: _chassis(),
  feederPin: 'P60',
  feederDirection: Direction.reverse,
  yawDrive: DriveType.motor,
  yawPin: 'P64',
  yawDirection: Direction.reverse,
  pitchDrive: DriveType.motor,
  pitchPin: 'P66',
  pitchDirection: Direction.forward,
  arrowBehavior: ArrowBehavior.move,
  feedMode: FeedMode.visualClosedLoop,
  triggerKey: 'E',
  triggerSpeed: 7200,
  frictionMode: FrictionMode.disabled,
  zeroEnabled: true,
  buzzerDisabled: true,
);

InfantryConfig _infantrySharedChassisSprint() => InfantryConfig(
  remote: const RemoteConfig(channel: 5, deadzone: 20),
  chassis: _chassis(shared: true),
  feederPin: 'P60',
  feederDirection: Direction.forward,
  yawDrive: DriveType.servo,
  yawPin: 'P62',
  yawDirection: Direction.reverse,
  yawMidOffset: -18,
  pitchDrive: DriveType.servo,
  pitchPin: 'MP03',
  pitchDirection: Direction.forward,
  pitchMidOffset: 24,
  arrowBehavior: ArrowBehavior.sprint,
  feedMode: FeedMode.blockingOpenLoop,
  triggerKey: 'E',
  triggerSpeed: 4300,
  triggerTimeMs: 480,
  frictionMode: FrictionMode.brushlessEsc,
  frictionKey: 'A',
  frictionUpKey: 'B',
  frictionDownKey: 'C',
  frictionMaxDuty: 700,
  frictionStep: 50,
  zeroEnabled: true,
);

PwmGroupConfig _engineerPwm({bool advanced = false}) => PwmGroupConfig(
  pwma: advanced ? PwmFrequency.hz50 : PwmFrequency.hz10000,
  pwmb: PwmFrequency.hz10000,
  buzzerDisabled: advanced,
  pinRoles: {
    for (final pin in expansionPins)
      pin: advanced && pin == 'P60'
          ? PinRole.servo
          : EngineerPinCapabilities.frictionPins.contains(pin)
          ? PinRole.friction
          : PinRole.motor,
  },
  servoMids: advanced
      ? const {'P60': -10, 'MP03': 12, 'MP74': -8}
      : const {'MP03': 0, 'MP74': 0},
);

EngineerConfig _engineerSingleMode() => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: _chassis(),
  pwm: _engineerPwm(),
  modeCount: 1,
  modes: [EngineerModeConfig(id: 'mode-1', preserveChassis: true)],
);

EngineerConfig _engineerAdvanced(SwitchStrategy strategy) => EngineerConfig(
  remote: const RemoteConfig(channel: 58, deadzone: 180),
  chassis: _chassis(),
  pwm: _engineerPwm(advanced: true),
  modeCount: 4,
  switchStrategy: strategy,
  modeSwitchKey: strategy == SwitchStrategy.cycle ? 'E' : null,
  modeKeys: strategy == SwitchStrategy.direct
      ? const ['E', 'UP', 'DOWN', 'LEFT']
      : null,
  modes: [
    EngineerModeConfig(
      id: 'mode-1',
      preserveChassis: true,
      actions: [
        ActionMapping(
          id: 'servo-single',
          key: 'A',
          direction: Direction.forward,
          mode: ControlMode.single,
          parameter: 5.5,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'servo-continuous',
          key: 'B',
          direction: Direction.reverse,
          mode: ControlMode.continuous,
          parameter: 5,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'main-servo-continuous',
          key: 'D',
          direction: Direction.forward,
          mode: ControlMode.continuous,
          parameter: 0.5,
          pin: 'MP03',
        ),
        ActionMapping(
          id: 'servo-direct-preset',
          key: 'RIGHT',
          direction: Direction.forward,
          mode: ControlMode.direct,
          parameter: 45,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'motor-direct',
          key: 'C',
          direction: Direction.forward,
          mode: ControlMode.direct,
          parameter: 4000,
          pin: 'P62',
        ),
      ],
    ),
    EngineerModeConfig(
      id: 'mode-2',
      actions: [
        ActionMapping(
          id: 'motor-speed',
          key: 'RX',
          direction: Direction.forward,
          mode: ControlMode.speed,
          parameter: 5000,
          pin: 'P64',
        ),
        ActionMapping(
          id: 'motor-accelerate',
          key: 'RY',
          direction: Direction.reverse,
          mode: ControlMode.accelerate,
          parameter: 100,
          pin: 'P66',
        ),
      ],
    ),
    EngineerModeConfig(id: 'mode-3'),
    EngineerModeConfig(id: 'mode-4'),
  ],
);

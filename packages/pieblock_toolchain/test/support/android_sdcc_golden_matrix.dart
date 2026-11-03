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
      'e3245fffe31282467934f455972dc6779dff8ab8bd25b8fcd3be17bfd7b15609',
  'engineer_single_mode':
      '8b186ec479c64ec170952f44eb402c03b3bed6343eb4412d736895d9e0d355f7',
  'infantry_motor_visual_no_friction':
      '33a5695e7c64a42170e766bb4c6b8e212228555c3f24ae4c122a9fee9dd9dd57',
  'infantry_shared_chassis_sprint':
      'e53b19de8b021ae9b964c3b3fc9606a64c65cc65aba66fb76eb59d647c493e16',
  'engineer_four_mode_cycle':
      '3a4b2fa74eab4529b7bd4d1b1545c5b6cb65eee11f588ca95824b7c7a4cf07b9',
  'engineer_four_mode_direct':
      '563fd9d73478074d5df495244ade016288d3dd38073dbe76e07cdfff1d0bbc19',
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
  yawActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP74',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  pitchActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP03',
      direction: Direction.forward,
      midOffset: 0,
    ),
  ],
  arrowBehavior: ArrowBehavior.other,
  feedMode: FeedMode.blockingOpenLoop,
  triggerKey: 'E',
  triggerSpeed: 6000,
  triggerTimeMs: 250,
  frictionMode: FrictionMode.brushlessEsc,
  frictionKey: 'A',
  frictionUpKey: 'B',
  frictionDownKey: 'C',
  frictionP64MaxDuty: 800,
  frictionP66MaxDuty: 700,
  frictionLevelStep: 10,
);

InfantryConfig _infantryMotorVisualNoFriction() => InfantryConfig(
  remote: const RemoteConfig(channel: 77, deadzone: 240),
  chassis: _chassis(),
  feederPin: 'P60',
  feederDirection: Direction.reverse,
  yawActuators: const [
    AxisActuator(
      drive: DriveType.motor,
      pin: 'P64',
      direction: Direction.reverse,
    ),
  ],
  pitchActuators: const [
    AxisActuator(
      drive: DriveType.motor,
      pin: 'P66',
      direction: Direction.forward,
    ),
  ],
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
  yawActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'P62',
      direction: Direction.reverse,
      midOffset: -18,
    ),
  ],
  pitchActuators: const [
    AxisActuator(
      drive: DriveType.servo,
      pin: 'MP03',
      direction: Direction.forward,
      midOffset: 24,
    ),
  ],
  arrowBehavior: ArrowBehavior.sprint,
  feedMode: FeedMode.blockingOpenLoop,
  triggerKey: 'E',
  triggerSpeed: 4300,
  triggerTimeMs: 480,
  frictionMode: FrictionMode.brushlessEsc,
  frictionKey: 'A',
  frictionUpKey: 'B',
  frictionDownKey: 'C',
  frictionP64MaxDuty: 700,
  frictionP66MaxDuty: 800,
  frictionLevelStep: 5,
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
          : EngineerPinCapabilities.legacyFrictionPins.contains(pin)
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
      ? const ['E', '↑', '↓', '←']
      : null,
  modes: [
    EngineerModeConfig(
      id: 'mode-1',
      preserveChassis: true,
      actions: [
        ActionMapping(
          id: 'servo-single',
          key: 'A',
          mode: ControlMode.single,
          parameter: 5.5,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'servo-continuous',
          key: 'B',
          mode: ControlMode.continuous,
          parameter: -5,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'main-servo-continuous',
          key: 'D',
          mode: ControlMode.continuous,
          parameter: 0.5,
          pin: 'MP03',
        ),
        ActionMapping(
          id: 'servo-direct-preset',
          key: '→',
          mode: ControlMode.direct,
          parameter: 45,
          pin: 'P60',
        ),
        ActionMapping(
          id: 'motor-direct',
          key: 'C',
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
          mode: ControlMode.speed,
          parameter: 5000,
          pin: 'P64',
        ),
        ActionMapping(
          id: 'motor-accelerate',
          key: 'RY',
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

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
      'd80316055967fbbff9104336c39c8e17e9b8f045e45436ea68c8e003087b0eaa',
  'engineer_single_mode':
      'fbdd8ec076160830d3d2d839c24ea33eb9a5003bc376dbde499fb58194d1d0ed',
  'infantry_motor_visual_no_friction':
      'ed858c2ed5664481c59bb6fd0272db57321dc1036fbf5d81d8dbb20ff8c7766c',
  'infantry_shared_chassis_sprint':
      'b8aba520d291cd8c0debaa4b0ce2a4cf8a419385e0cd65530b0709e58bb7822f',
  'engineer_four_mode_cycle':
      '5f87fb5ecb49f6a610f6990351dbd75fdea1b5e8f5c7115f965577f491707e7a',
  'engineer_four_mode_direct':
      '8d7c8dc20da6e1beb2cba08ad5915deed7b670ee40c287a0f468d7896dc0f63d',
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
  frictionMaxDuty: 800,
  frictionStep: 100,
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
          key: '→',
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

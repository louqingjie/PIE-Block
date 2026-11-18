import 'package:pieblock_core/pieblock_core.dart';

/// 一份能通过 `ProjectValidator` 校验的完整步兵配置。
///
/// CLI、提案与校验相关的测试共用，避免每个文件各写一遍字段而漂移。
InfantryConfig validInfantryConfig() => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: ChassisConfig(
    leftFront: const WheelConfig('P74 P24', Direction.forward),
    leftRear: const WheelConfig('P75 P25', Direction.forward),
    rightFront: const WheelConfig('P76 P26', Direction.reverse),
    rightRear: const WheelConfig('P77 P27', Direction.reverse),
    normalSpeed: 4000,
    sprintSpeed: 8000,
  ),
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

/// 带上述配置的步兵工程文档。
ProjectDocument validInfantryDocument() =>
    ProjectDocument.create(ProjectKind.infantry)
        .copyWith(config: validInfantryConfig());

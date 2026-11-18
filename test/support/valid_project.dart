import 'package:pieblock_core/pieblock_core.dart';

/// 一份能通过 `ProjectValidator` 校验的完整步兵配置，应用侧测试共用。
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

ProjectDocument validInfantryDocument() =>
    ProjectDocument.create(ProjectKind.infantry)
        .copyWith(config: validInfantryConfig());

/// 把 `config.chassis.normal_speed` 改成一个新值后的完整工程 JSON。
Map<String, Object?> projectJsonWithSpeed(int speed) {
  final json = Map<String, Object?>.from(validInfantryDocument().toJson());
  final config = Map<String, Object?>.from(json['config']! as Map);
  final chassis = Map<String, Object?>.from(config['chassis']! as Map);
  chassis['normal_speed'] = speed;
  config['chassis'] = chassis;
  json['config'] = config;
  return json;
}

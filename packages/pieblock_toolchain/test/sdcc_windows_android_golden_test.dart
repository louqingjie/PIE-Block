import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

const _androidGoldenHashes = <ProjectKind, String>{
  ProjectKind.infantry:
      '2a877e2d2a2c56039ad095e17bf8b4b6c01e9f691fecd87b4d3c964459367ce3',
  ProjectKind.engineer:
      'e44e99c589eaf33914d91ae4bb5877fef9f439ea28a9270eb82eed6d453816a8',
};

void main() {
  final enabled = Platform.environment['PIEBLOCK_RUN_SDCC_GOLDEN'] == '1';

  for (final entry in <ProjectKind, ProjectConfig>{
    ProjectKind.infantry: _completeInfantry(),
    ProjectKind.engineer: _completeEngineer(),
  }.entries) {
    test(
      'Windows 与 Android ${entry.key.name} SDCC 固件字节级一致',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'pieblock-sdcc-golden-${entry.key.name}-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final builder = FirmwareBuilder(
          runtimeRoot: '${directory.path}/runtime',
          workRoot: '${directory.path}/work',
          artifacts: BuildArtifactRepository(
            root: '${directory.path}/artifacts',
          ),
        );
        final compilerFingerprint = await builder.resolveCompilerFingerprint(
          CompilerKind.sdcc,
        );
        final operation = builder.start(
          BuildRequest(
            projectKind: entry.key,
            sourceCode: CodeGenerator.generate(entry.value),
            compiler: CompilerKind.sdcc,
            compilerFingerprint: compilerFingerprint,
          ),
        );
        final result = await operation.result;
        expect(result.success, isTrue, reason: result.log);
        final artifact = result.artifact!;
        stdout.writeln(
          '${entry.key.name}: windowsSha256=${artifact.hexSha256}, '
          'bytes=${artifact.byteCount}',
        );
        final androidHash = _androidGoldenHashes[entry.key];
        if (androidHash != null) expect(artifact.hexSha256, androidHash);
      },
      skip: enabled ? false : '设置 PIEBLOCK_RUN_SDCC_GOLDEN=1 后运行',
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }
}

ChassisConfig _completeChassis() => const ChassisConfig(
  leftFront: WheelConfig('P74 P24', Direction.forward),
  leftRear: WheelConfig('P75 P25', Direction.forward),
  rightFront: WheelConfig('P76 P26', Direction.reverse),
  rightRear: WheelConfig('P77 P27', Direction.reverse),
  normalSpeed: 4000,
  sprintSpeed: 8000,
);

InfantryConfig _completeInfantry() => InfantryConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: _completeChassis(),
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

EngineerConfig _completeEngineer() => EngineerConfig(
  remote: const RemoteConfig(channel: 36, deadzone: 100),
  chassis: _completeChassis(),
  pwm: PwmGroupConfig(
    pwma: PwmFrequency.hz10000,
    pwmb: PwmFrequency.hz10000,
    pinRoles: {for (final pin in expansionPins) pin: PinRole.motor},
    servoMids: const {'MP03': 0, 'MP74': 0},
  ),
  modeCount: 1,
  modes: [EngineerModeConfig(preserveChassis: true)],
);

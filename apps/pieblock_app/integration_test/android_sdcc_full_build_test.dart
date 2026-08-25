import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

const _selectedKind = String.fromEnvironment(
  'PIEBLOCK_GOLDEN_KIND',
  defaultValue: 'all',
);
const _windowsGoldenHashes = <ProjectKind, String>{
  ProjectKind.infantry:
      '2a877e2d2a2c56039ad095e17bf8b4b6c01e9f691fecd87b4d3c964459367ce3',
  ProjectKind.engineer:
      'e44e99c589eaf33914d91ae4bb5877fef9f439ea28a9270eb82eed6d453816a8',
};

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android 多进程 SDCC 完成步兵与工程全量构建', (tester) async {
    expect(Platform.isAndroid, isTrue);
    const documents = MethodChannel('cn.edu.cnu.pieblock/documents');
    const compiler = MethodChannel('cn.edu.cnu.pieblock/sdcc_compiler');
    const events = EventChannel('cn.edu.cnu.pieblock/sdcc_compiler_events');
    final resourceRoot = await documents.invokeMethod<String>(
      'prepareSdccResources',
    );
    expect(resourceRoot, isNotNull);
    final stream = events.receiveBroadcastStream();

    final configurations = <ProjectKind, ProjectConfig>{
      ProjectKind.infantry: _completeInfantry(),
      ProjectKind.engineer: _completeEngineer(),
    };
    for (final entry in configurations.entries.where(
      (entry) => _selectedKind == 'all' || entry.key.name == _selectedKind,
    )) {
      final validation = ProjectValidator.validate(entry.value)
          .where((issue) => issue.severity == IssueSeverity.error);
      expect(validation, isEmpty, reason: '$validation');
      final stopwatch = Stopwatch()..start();
      final result = await _buildFirmware(
        compiler: compiler,
        eventStream: stream,
        resourceRoot: resourceRoot!,
        kind: entry.key,
        source: CodeGenerator.generate(entry.value),
      );
      stopwatch.stop();
      expect(result['success'], isTrue, reason: '${entry.key}: $result');
      expect(File(result['hexPath'] as String).lengthSync(), greaterThan(0));
      expect(File(result['mapPath'] as String).lengthSync(), greaterThan(0));
      expect(result['hexSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(result['hexSha256'], _windowsGoldenHashes[entry.key]);
      expect(result['warningCount'], greaterThan(0));
      final workerPids = (result['workerPids'] as List).cast<int>();
      final workerNonces = (result['workerNonces'] as List).cast<String>();
      expect(workerPids, hasLength(result['expectedWorkerCount'] as int));
      expect(workerPids.toSet(), hasLength(workerPids.length));
      expect(workerNonces.toSet(), hasLength(workerNonces.length));
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 120)));
      tester.printToConsole(
        '${entry.key.name}: sha256=${result['hexSha256']}, '
        'elapsed=${stopwatch.elapsedMilliseconds}ms, '
        'warnings=${result['warningCount']}',
      );
      final intermediateExtensions = <String>{
        '.rel',
        '.asm',
        '.lst',
        '.sym',
        '.rst',
        '.lk',
        '.mem',
      };
      expect(
        Directory(File(result['hexPath'] as String).parent.path)
            .listSync()
            .whereType<File>()
            .where((file) => intermediateExtensions.any(file.path.endsWith)),
        isEmpty,
      );
    }
  });
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

Future<Map<Object?, Object?>> _buildFirmware({
  required MethodChannel compiler,
  required Stream<Object?> eventStream,
  required String resourceRoot,
  required ProjectKind kind,
  required String source,
}) async {
  final work = Directory(
    p.join(
      Directory(resourceRoot).parent.parent.path,
      'sdcc_full_${kind.name}',
    ),
  );
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);
  final mainSource = File(p.join(work.path, 'main.c'))
    ..writeAsStringSync(source, flush: true);
  final output = Directory(p.join(work.path, 'output'))
    ..createSync(recursive: true);
  final plan = await SdccBuildPlan.prepare(
    resourceRoot: resourceRoot,
    projectName: kind.name,
    mainSourcePath: mainSource.path,
    outputDirectory: output.path,
  );
  final hex = p.join(output.path, '${kind.name}.hex');
  final map = p.join(output.path, '${kind.name}.map');
  final log = p.join(output.path, '${kind.name}.log');
  final resultFuture = eventStream.firstWhere(
    (event) => event is Map && event['type'] == 'result',
  );
  final operationId = await compiler.invokeMethod<String>('start', {
    'workingDirectory': work.path,
    'resourceDirectory': resourceRoot,
    'projectKind': kind.name,
    'mainSourcePath': mainSource.path,
    'interruptHeaderPath': plan.interruptHeaderPath,
    'sourcePaths': plan.sourcePaths,
    'librarySourcePaths': plan.librarySourcePaths,
    'compileArguments': plan.compileArguments,
    'linkArguments': plan.linkArguments,
    'hexOutputPath': hex,
    'mapOutputPath': map,
    'logOutputPath': log,
  });
  expect(operationId, isNotEmpty);
  final result = (await resultFuture as Map).cast<Object?, Object?>()
    ..['expectedWorkerCount'] = plan.sourcePaths.length + 1
    ..['diagnosticLog'] = File(log).existsSync()
        ? File(log).readAsStringSync()
        : '<missing log>';
  await compiler.invokeMethod<void>('acknowledge', {
    'operationId': operationId,
  });
  return result;
}

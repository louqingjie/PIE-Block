import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import '../../../packages/pieblock_toolchain/test/support/android_sdcc_golden_matrix.dart';

const _selectedKind = String.fromEnvironment(
  'PIEBLOCK_GOLDEN_KIND',
  defaultValue: 'all',
);
const _repetitions = int.fromEnvironment(
  'PIEBLOCK_GOLDEN_REPETITIONS',
  defaultValue: 1,
);
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

    for (final golden in sdccGoldenCases.where(
      (item) =>
          _selectedKind == 'all' ||
          item.kind.name == _selectedKind ||
          item.id == _selectedKind,
    )) {
      final validation = ProjectValidator.validate(golden.config)
          .where((issue) => issue.severity == IssueSeverity.error);
      expect(validation, isEmpty, reason: '$validation');
      final allNonces = <String>[];
      for (var repetition = 0; repetition < _repetitions; repetition++) {
        final stopwatch = Stopwatch()..start();
        final result = await _buildFirmware(
          compiler: compiler,
          eventStream: stream,
          resourceRoot: resourceRoot!,
          kind: golden.kind,
          caseId: golden.id,
          repetition: repetition,
          source: CodeGenerator.generate(golden.config),
        );
        stopwatch.stop();
        expect(result['success'], isTrue, reason: '${golden.id}: $result');
        expect(File(result['hexPath'] as String).lengthSync(), greaterThan(0));
        expect(File(result['mapPath'] as String).lengthSync(), greaterThan(0));
        expect(result['hexSha256'], golden.expectedHexSha256);
        expect(result['warningCount'], greaterThan(0));
        final workerPids = (result['workerPids'] as List).cast<int>();
        final workerNonces = (result['workerNonces'] as List).cast<String>();
        expect(workerPids, hasLength(result['expectedWorkerCount'] as int));
        expect(workerPids.toSet(), hasLength(workerPids.length));
        expect(workerNonces.toSet(), hasLength(workerNonces.length));
        allNonces.addAll(workerNonces);
        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 120)));
        tester.printToConsole(
          '${golden.id}#$repetition: sha256=${result['hexSha256']}, '
          'elapsed=${stopwatch.elapsedMilliseconds}ms, '
          'warnings=${result['warningCount']}',
        );
        final intermediateExtensions = <String>{
          '.rel', '.asm', '.lst', '.sym', '.rst', '.lk', '.mem',
        };
        expect(
          Directory(File(result['hexPath'] as String).parent.path)
              .listSync()
              .whereType<File>()
              .where((file) => intermediateExtensions.any(file.path.endsWith)),
          isEmpty,
        );
      }
      expect(allNonces.toSet(), hasLength(allNonces.length));
    }
  });
}

Future<Map<Object?, Object?>> _buildFirmware({
  required MethodChannel compiler,
  required Stream<Object?> eventStream,
  required String resourceRoot,
  required ProjectKind kind,
  required String caseId,
  required int repetition,
  required String source,
}) async {
  final work = Directory(
    p.join(
      Directory(resourceRoot).parent.parent.path,
      'sdcc_full_${caseId}_$repetition',
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
  final hex = p.join(output.path, '$caseId.hex');
  final map = p.join(output.path, '$caseId.map');
  final log = p.join(output.path, '$caseId.log');
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

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

const _stabilityIterations = int.fromEnvironment(
  'PIEBLOCK_STABILITY_ITERATIONS',
  defaultValue: 2,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android SDCC 多进程服务完成确定性最小固件构建', (tester) async {
    expect(Platform.isAndroid, isTrue);

    const documents = MethodChannel('cn.edu.cnu.pieblock/documents');
    final nativeInfo = await documents.invokeMapMethod<String, String>(
      'getSdccNativeInfo',
    );
    expect(nativeInfo, isNotNull);
    expect(<String>['arm64-v8a', 'x86_64'], contains(nativeInfo!['abi']));
    expect(nativeInfo['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));

    final firstRoot = await documents.invokeMethod<String>(
      'prepareSdccResources',
    );
    expect(firstRoot, isNotNull);
    final root = Directory(firstRoot!);
    expect(root.existsSync(), isTrue);
    final marker = File('${root.path}${Platform.pathSeparator}.ready');
    expect(marker.existsSync(), isTrue);
    expect(marker.readAsStringSync(), matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path != marker.path)
          .length,
      204,
    );
    expect(
      await documents.invokeMethod<String>('prepareSdccResources'),
      firstRoot,
    );

    const compiler = MethodChannel('cn.edu.cnu.pieblock/sdcc_compiler');
    const compilerEvents = EventChannel(
      'cn.edu.cnu.pieblock/sdcc_compiler_events',
    );
    expect(await compiler.invokeMethod<int>('protocolVersion'), 2);
    final capabilities = await compiler.invokeMapMethod<Object?, Object?>(
      'probe',
    );
    expect(capabilities?['protocolVersion'], 2);
    expect(capabilities?['workerProtocolVersion'], 1);
    expect(capabilities?['apiVersion'], 5);
    expect(capabilities?['available'], isTrue);
    expect(capabilities?['fingerprint'], contains('ffi:5'));
    expect(capabilities?['fingerprint'], contains('coordinator:2'));
    expect(capabilities?['fingerprint'], contains('worker:1'));
    expect(capabilities?['fingerprint'], contains('scheduler:1'));

    final flutterPid = await documents.invokeMethod<int>('getProcessId');
    final initialMetrics = await documents.invokeMapMethod<Object?, Object?>(
      'getProcessMetrics',
    );
    final eventStream = compilerEvents.receiveBroadcastStream();
    final canceled = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 0,
      cancelImmediately: true,
      assertConcurrentRejection: true,
    );
    expect(canceled.result['success'], isFalse);
    expect(canceled.result['canceled'], isTrue);
    expect(canceled.hexBytes, isEmpty);
    final canceledDuringCompile = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 1,
      cancelAtStage: 2,
    );
    expect(canceledDuringCompile.result['canceled'], isTrue);
    expect(canceledDuringCompile.hexBytes, isEmpty);
    final canceledDuringLink = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 2,
      cancelAtStage: 4,
    );
    expect(canceledDuringLink.result['canceled'], isTrue);
    expect(canceledDuringLink.hexBytes, isEmpty);

    for (final fault in <({String name, int phase})>[
      (name: 'worker_crash', phase: 0),
      (name: 'worker_disconnect', phase: 3),
      (name: 'worker_no_space', phase: 1),
    ]) {
      final failed = await _buildMinimal(
        compiler: compiler,
        eventStream: eventStream,
        resourceRoot: root.path,
        runIndex: 10 + fault.phase,
        testFault: fault.name,
        testFaultPhase: fault.phase,
      );
      expect(failed.result['success'], isFalse);
      expect(
        failed.result['errorCode'],
        fault.name == 'worker_no_space' ? 'worker_failed' : 'worker_disconnected',
      );
      expect(failed.hexBytes, isEmpty);
    }

    final coordinatorCrash = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 20,
      testFault: 'coordinator_crash',
    );
    expect(coordinatorCrash.result['success'], isFalse);
    expect(coordinatorCrash.result['errorCode'], 'compiler_process_exited');
    expect(coordinatorCrash.hexBytes, isEmpty);
    await compiler.invokeMethod<Object?>('probe');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(File('${coordinatorCrash.workPath}${Platform.pathSeparator}.in_progress').existsSync(), isFalse);

    final backgroundBuild = await _buildMinimal(
      compiler: compiler,
      documents: documents,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 30,
      backgroundAtStage: 2,
    );
    expect(backgroundBuild.result['success'], isTrue);

    final stableBuilds = <_BuildResult>[];
    for (var index = 0; index < _stabilityIterations; index++) {
      stableBuilds.add(
        await _buildMinimal(
          compiler: compiler,
          eventStream: eventStream,
          resourceRoot: root.path,
          runIndex: 100 + index,
        ),
      );
    }
    expect(stableBuilds, isNotEmpty);
    final first = stableBuilds.first;
    final second = stableBuilds.last;

    expect(first.result['success'], isTrue, reason: '${first.result}');
    expect(second.result['success'], isTrue, reason: '${second.result}');
    expect(first.result['compilerPid'], isNot(flutterPid));
    expect(second.result['compilerPid'], isNot(flutterPid));
    expect(first.workerPids, hasLength(4));
    expect(first.workerPids.toSet(), hasLength(4));
    expect(first.workerNonces, hasLength(4));
    expect(first.workerNonces.toSet(), hasLength(4));
    expect(second.workerNonces.toSet(), hasLength(4));
    expect(
      first.workerNonces.toSet().intersection(second.workerNonces.toSet()),
      isEmpty,
    );
    expect(first.hexBytes, isNotEmpty);
    expect(second.hexBytes, first.hexBytes);
    expect(first.result['hexSha256'], second.result['hexSha256']);
    final allNonces = stableBuilds.expand((build) => build.workerNonces).toList();
    expect(allNonces.toSet(), hasLength(allNonces.length));
    final coordinatorNonces = stableBuilds
        .map((build) => build.result['coordinatorNonce'])
        .toList();
    expect(coordinatorNonces, everyElement(isNotNull));
    expect(coordinatorNonces.toSet(), hasLength(coordinatorNonces.length));
    final finalMetrics = await documents.invokeMapMethod<Object?, Object?>(
      'getProcessMetrics',
    );
    expect(finalMetrics, isNotNull);
    expect(initialMetrics, isNotNull);
    expect(
      (finalMetrics!['pssKb'] as int) - (initialMetrics!['pssKb'] as int),
      lessThan(96 * 1024),
    );
    expect(
      (finalMetrics['openFdCount'] as int) -
          (initialMetrics['openFdCount'] as int),
      lessThan(64),
    );
  });
}

class _BuildResult {
  const _BuildResult({
    required this.result,
    required this.workerPids,
    required this.workerNonces,
    required this.hexBytes,
    required this.workPath,
  });

  final Map<Object?, Object?> result;
  final List<int> workerPids;
  final List<String> workerNonces;
  final List<int> hexBytes;
  final String workPath;
}

Future<_BuildResult> _buildMinimal({
  required MethodChannel compiler,
  required Stream<Object?> eventStream,
  required String resourceRoot,
  required int runIndex,
  MethodChannel? documents,
  bool cancelImmediately = false,
  bool assertConcurrentRejection = false,
  int? cancelAtStage,
  String? testFault,
  int? testFaultPhase,
  int? backgroundAtStage,
}) async {
  final separator = Platform.pathSeparator;
  final supportRoot = Directory(resourceRoot).parent.parent;
  final work = Directory('${supportRoot.path}${separator}sdcc_smoke_$runIndex');
  if (work.existsSync()) work.deleteSync(recursive: true);
  work.createSync(recursive: true);
  final mainSource = File('${work.path}${separator}main.c')
    ..writeAsStringSync('void main(void) { while (1) {} }\n', flush: true);
  final isrSource = File('${work.path}${separator}isr.c')
    ..writeAsStringSync(
      '#include "STC32Gxx.h"\n'
      'void Default_Isr(void) __interrupt (I2SRXDMA_VECTOR) {}\n',
      flush: true,
    );
  final interruptHeader =
      File('${work.path}${separator}generated_interrupt_declarations.h')
        ..writeAsStringSync(
          '#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
          '#define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
          '#include "STC32Gxx.h"\n'
          '#endif\n',
          flush: true,
        );
  final startup =
      '$resourceRoot${separator}firmware${separator}startup'
      '${separator}stc32g12k128_startup.c';
  final toolchain = '$resourceRoot${separator}toolchain';
  final firmware = '$resourceRoot${separator}firmware';
  final includes = <String>[
    '-I$toolchain${separator}include',
    '-I$toolchain${separator}include${separator}mcs51',
    '-I$firmware${separator}include',
    '-I$firmware${separator}startup',
  ];
  final hex = '${work.path}${separator}minimal.hex';
  final map = '${work.path}${separator}minimal.map';
  final log = '${work.path}${separator}minimal.log';
  final resultFuture = eventStream.firstWhere(
    (event) => event is Map && event['type'] == 'result',
  );
  final cancelFuture = cancelAtStage == null
      ? null
      : eventStream.firstWhere(
          (event) =>
              event is Map &&
              event['type'] == 'event' &&
              event['stage'] == cancelAtStage,
        );
  final backgroundFuture = backgroundAtStage == null
      ? null
      : eventStream.firstWhere(
          (event) =>
              event is Map &&
              event['type'] == 'event' &&
              event['stage'] == backgroundAtStage,
        );
  final request = <String, Object>{
    'workingDirectory': work.path,
    'resourceDirectory': resourceRoot,
    'projectKind': 'minimal',
    'mainSourcePath': mainSource.path,
    'interruptHeaderPath': interruptHeader.path,
    'sourcePaths': <String>[startup, isrSource.path, mainSource.path],
    'librarySourcePaths': <String>[],
    'compileArguments': <String>[
      '-mmcs251',
      '--model-large',
      '--stack-auto',
      '--opt-code-size',
      '--constseg',
      'CSEG',
      '-c',
      ...includes,
    ],
    'linkArguments': <String>[
      '-mmcs251',
      '--model-large',
      '--stack-auto',
      '--constseg',
      'CSEG',
      '--nostdlib',
      '--iram-size',
      '0x1000',
      '--xram-loc',
      '0x010000',
      '--xram-size',
      '0x2000',
      '--code-loc',
      '0xff0000',
      '-Wl-b GSINIT0=0xfe0000',
      '-L$toolchain${separator}lib${separator}mcs251-large-stack-auto',
      ...includes,
      'mcs251.lib',
      'libsdcc.lib',
      'liblong.lib',
      'libint.lib',
      'libfloat.lib',
      'liblonglong.lib',
    ],
    'hexOutputPath': hex,
    'mapOutputPath': map,
    'logOutputPath': log,
  };
  if (testFault != null) request['testFault'] = testFault;
  if (testFaultPhase != null) request['testFaultPhase'] = testFaultPhase;
  final operationId = await compiler.invokeMethod<String>('start', request);
  expect(operationId, isNotEmpty);
  if (assertConcurrentRejection) {
    await expectLater(
      compiler.invokeMethod<String>('start', request),
      throwsA(isA<PlatformException>()),
    );
  }
  if (cancelImmediately) {
    await compiler.invokeMethod<void>('cancel', {'operationId': operationId});
  }
  if (cancelFuture != null) {
    await cancelFuture;
    await compiler.invokeMethod<void>('cancel', {'operationId': operationId});
  }
  if (backgroundFuture != null) {
    await backgroundFuture;
    expect(documents, isNotNull);
    expect(
      await documents!.invokeMethod<bool>('debugMoveTaskToBackground'),
      isTrue,
    );
  }
  Map<Object?, Object?> result;
  try {
    result = (await resultFuture as Map).cast<Object?, Object?>();
  } on PlatformException catch (error) {
    if (testFault != 'coordinator_crash') rethrow;
    result = <Object?, Object?>{
      'success': false,
      'canceled': false,
      'errorCode': error.code,
      'message': error.message,
      'workerPids': <int>[],
      'workerNonces': <String>[],
    };
  }
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
    work.listSync().whereType<File>().where(
      (file) => intermediateExtensions.any(file.path.endsWith),
    ),
    isEmpty,
  );
  if (testFault != 'coordinator_crash') {
    await compiler.invokeMethod<void>('acknowledge', {
      'operationId': operationId,
    });
  }
  return _BuildResult(
    result: result,
    workerPids: (result['workerPids'] as List).cast<int>(),
    workerNonces: (result['workerNonces'] as List).cast<String>(),
    hexBytes: File(hex).existsSync() ? File(hex).readAsBytesSync() : const [],
    workPath: work.path,
  );
}

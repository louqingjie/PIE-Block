import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

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
    final first = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 1,
    );
    final second = await _buildMinimal(
      compiler: compiler,
      eventStream: eventStream,
      resourceRoot: root.path,
      runIndex: 2,
    );

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
  });
}

class _BuildResult {
  const _BuildResult({
    required this.result,
    required this.workerPids,
    required this.workerNonces,
    required this.hexBytes,
  });

  final Map<Object?, Object?> result;
  final List<int> workerPids;
  final List<String> workerNonces;
  final List<int> hexBytes;
}

Future<_BuildResult> _buildMinimal({
  required MethodChannel compiler,
  required Stream<Object?> eventStream,
  required String resourceRoot,
  required int runIndex,
  bool cancelImmediately = false,
  bool assertConcurrentRejection = false,
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
  final result = (await resultFuture as Map).cast<Object?, Object?>();
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
  await compiler.invokeMethod<void>('acknowledge', {
    'operationId': operationId,
  });
  return _BuildResult(
    result: result,
    workerPids: (result['workerPids'] as List).cast<int>(),
    workerNonces: (result['workerNonces'] as List).cast<String>(),
    hexBytes: File(hex).existsSync() ? File(hex).readAsBytesSync() : const [],
  );
}

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android SDCC 原生库与资源包可以在真机加载和部署', (tester) async {
    expect(Platform.isAndroid, isTrue);

    const channel = MethodChannel('cn.edu.cnu.pieblock/documents');
    final nativeInfo = await channel.invokeMapMethod<String, String>(
      'getSdccNativeInfo',
    );
    debugPrint('Android SDCC smoke: native info loaded');
    expect(nativeInfo, isNotNull);
    expect(<String>['arm64-v8a', 'x86_64'], contains(nativeInfo!['abi']));
    expect(nativeInfo['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));

    final firstRoot = await channel.invokeMethod<String>(
      'prepareSdccResources',
    );
    debugPrint('Android SDCC smoke: resources prepared');
    expect(firstRoot, isNotNull);
    final root = Directory(firstRoot!);
    expect(root.existsSync(), isTrue);
    final marker = File('${root.path}${Platform.pathSeparator}.ready');
    expect(marker.existsSync(), isTrue);
    expect(marker.readAsStringSync(), matches(RegExp(r'^[0-9a-f]{64}$')));

    final deployedFiles = root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path != marker.path)
        .length;
    expect(deployedFiles, 204);

    // A second preparation must validate and reuse the atomic deployment.
    final secondRoot = await channel.invokeMethod<String>(
      'prepareSdccResources',
    );
    debugPrint('Android SDCC smoke: resources reused');
    expect(secondRoot, firstRoot);
    expect(marker.readAsStringSync(), matches(RegExp(r'^[0-9a-f]{64}$')));

    // The compiler must be loaded in the private :compiler process. During
    // development the safety gate intentionally rejects the build, but that
    // rejection must arrive as a structured result without terminating the
    // Flutter process.
    const compiler = MethodChannel('cn.edu.cnu.pieblock/sdcc_compiler');
    const compilerEvents = EventChannel(
      'cn.edu.cnu.pieblock/sdcc_compiler_events',
    );
    expect(await compiler.invokeMethod<int>('protocolVersion'), 1);
    final capabilities = await compiler.invokeMapMethod<Object?, Object?>(
      'probe',
    );
    debugPrint('Android SDCC smoke: compiler service probed');
    expect(capabilities?['apiVersion'], 4);
    expect(capabilities?['available'], isFalse);
    expect(capabilities?['fingerprint'], contains('stages-linked:1'));
    final flutterPid = await channel.invokeMethod<int>('getProcessId');
    final resultFuture = compilerEvents.receiveBroadcastStream().firstWhere(
      (event) => event is Map && event['type'] == 'result',
    );
    final output = Directory('${root.path}${Platform.pathSeparator}smoke')
      ..createSync();
    final operationId = await compiler.invokeMethod<String>('start', {
      'workingDirectory': output.path,
      'resourceDirectory': root.path,
      'projectKind': 'infantry',
      'mainSourcePath': '${output.path}${Platform.pathSeparator}main.c',
      'interruptHeaderPath':
          '${output.path}${Platform.pathSeparator}interrupt.h',
      'sourcePaths': <String>['${output.path}${Platform.pathSeparator}main.c'],
      'librarySourcePaths': <String>[],
      'compileArguments': <String>[],
      'linkArguments': <String>[],
      'hexOutputPath': '${output.path}${Platform.pathSeparator}smoke.hex',
      'mapOutputPath': '${output.path}${Platform.pathSeparator}smoke.map',
      'logOutputPath': '${output.path}${Platform.pathSeparator}smoke.log',
    });
    debugPrint('Android SDCC smoke: gated operation started');
    expect(operationId, isNotEmpty);
    final compilerResult = (await resultFuture as Map).cast<Object?, Object?>();
    debugPrint('Android SDCC smoke: gated result received');
    expect(compilerResult['success'], isFalse);
    expect(compilerResult['message'], contains('安全门'));
    expect(compilerResult['fingerprint'], contains('ffi:4'));
    expect(compilerResult['compilerPid'], isNot(flutterPid));
    await compiler.invokeMethod<void>('acknowledge', {
      'operationId': operationId,
    });
  });
}

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pieblock_sdcc_native/pieblock_sdcc_native.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Android SDCC 原生库与资源包可以在真机加载和部署', (tester) async {
    expect(Platform.isAndroid, isTrue);

    final client = NativeSdccClient();
    expect(client.fingerprint, contains('ffi:3'));
    // The production compiler remains disabled until all four in-process
    // stages pass the Windows/Android golden comparison.
    expect(client.isAvailable, isFalse);

    const channel = MethodChannel('cn.edu.cnu.pieblock/documents');
    final nativeInfo = await channel.invokeMapMethod<String, String>(
      'getSdccNativeInfo',
    );
    expect(nativeInfo, isNotNull);
    expect(<String>['arm64-v8a', 'x86_64'], contains(nativeInfo!['abi']));
    expect(nativeInfo['sha256'], matches(RegExp(r'^[0-9a-f]{64}$')));

    final firstRoot = await channel.invokeMethod<String>(
      'prepareSdccResources',
    );
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
    expect(secondRoot, firstRoot);
    expect(marker.readAsStringSync(), matches(RegExp(r'^[0-9a-f]{64}$')));
  });
}

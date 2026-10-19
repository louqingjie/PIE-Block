import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:pieblock_toolchain/src/sdcc_runtime_deployer.dart';
import 'package:test/test.dart';

const _fingerprint =
    '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void _noopSink(
  BuildStage stage,
  String message, {
  BuildEventLevel level = BuildEventLevel.info,
  int? current,
  int? total,
}) {}

String get _executableName => Platform.isWindows ? 'sdcc.exe' : 'sdcc';

void main() {
  late Directory root;
  late Directory sdccRoot;
  late String runtimeRoot;
  late String toolchainAssets;
  late String firmwareAssets;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('pieblock-deploy-');
    runtimeRoot = p.join(root.path, 'runtime');
    sdccRoot = Directory(p.join(runtimeRoot, 'sdcc'));
    final assets = Directory(p.join(root.path, 'assets'));
    final toolchain = Directory(p.join(assets.path, 'toolchain'));
    firmwareAssets = p.join(assets.path, 'firmware');
    File(p.join(toolchain.path, 'bin', _executableName))
      ..createSync(recursive: true)
      ..writeAsStringSync('fake-sdcc');
    File(p.join(firmwareAssets, 'build_manifest.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{}');
    await File(p.join(toolchain.path, 'bundle_manifest.json')).writeAsString(
      jsonEncode({
        'files': {
          'bin/$_executableName': sha256
              .convert(utf8.encode('fake-sdcc'))
              .toString(),
        },
      }),
    );
    toolchainAssets = toolchain.path;
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  Future<SdccRuntimeDeployment> deploy(SdccRuntimeDeployer deployer) =>
      deployer.ensure(
        toolchainAssets: toolchainAssets,
        firmwareAssets: firmwareAssets,
        fingerprint: _fingerprint,
        emit: _noopSink,
      );

  List<String> sdccDirectoryNames() => sdccRoot
      .listSync()
      .whereType<Directory>()
      .map((directory) => p.basename(directory.path))
      .toList();

  test('首次部署复制工具链并写入 .ready', () async {
    final deployer = SdccRuntimeDeployer(runtimeRoot: runtimeRoot);
    final deployment = await deploy(deployer);
    expect(
      File(p.join(deployment.toolchain, 'bin', _executableName)).existsSync(),
      isTrue,
    );
    expect(
      File(p.join(deployment.firmware, 'build_manifest.json')).existsSync(),
      isTrue,
    );
    final destination = p.join(runtimeRoot, 'sdcc', _fingerprint);
    expect(
      File(p.join(destination, '.ready')).readAsStringSync(),
      _fingerprint,
    );
    expect(sdccDirectoryNames(), [_fingerprint], reason: '不应残留暂存目录');
  });

  test('已就绪的部署会被复用而不是重新复制', () async {
    final deployer = SdccRuntimeDeployer(runtimeRoot: runtimeRoot);
    final first = await deploy(deployer);
    final sentinel = File(p.join(first.firmware, 'sentinel.txt'))
      ..writeAsStringSync('keep');
    final second = await deploy(deployer);
    expect(second.toolchain, first.toolchain);
    expect(sentinel.existsSync(), isTrue, reason: '复用不应重建目标目录');
    expect(sdccDirectoryNames(), [_fingerprint]);
  });

  test('缺少 .ready 的半成品目标会被重建', () async {
    final destination = Directory(p.join(sdccRoot.path, _fingerprint));
    File(p.join(destination.path, 'junk.txt'))
      ..createSync(recursive: true)
      ..writeAsStringSync('junk');
    final deployment = await deploy(
      SdccRuntimeDeployer(runtimeRoot: runtimeRoot),
    );
    expect(File(p.join(destination.path, 'junk.txt')).existsSync(), isFalse);
    expect(
      File(p.join(deployment.toolchain, 'bin', _executableName)).existsSync(),
      isTrue,
    );
    expect(sdccDirectoryNames(), [_fingerprint]);
  });

  test('崩溃残留的 pending/staging 目录会被清理', () async {
    Directory(p.join(sdccRoot.path, '$_fingerprint.pending'))
        .createSync(recursive: true);
    Directory(p.join(sdccRoot.path, '$_fingerprint.staging-123-456'))
        .createSync(recursive: true);
    await deploy(
      SdccRuntimeDeployer(
        runtimeRoot: runtimeRoot,
        staleStagingAge: Duration.zero,
      ),
    );
    expect(sdccDirectoryNames(), [_fingerprint]);
  });

  test('并发部署会收敛到同一份可用运行时', () async {
    final results = await Future.wait([
      deploy(SdccRuntimeDeployer(runtimeRoot: runtimeRoot)),
      deploy(SdccRuntimeDeployer(runtimeRoot: runtimeRoot)),
    ]);
    expect(results[0].toolchain, results[1].toolchain);
    expect(
      File(p.join(runtimeRoot, 'sdcc', _fingerprint, '.ready')).existsSync(),
      isTrue,
    );
    expect(sdccDirectoryNames(), [_fingerprint]);
  });

  test('清单缺失时抛出带处理建议的部署异常并清理暂存', () async {
    File(p.join(toolchainAssets, 'bundle_manifest.json')).deleteSync();
    await expectLater(
      deploy(SdccRuntimeDeployer(runtimeRoot: runtimeRoot)),
      throwsA(
        isA<SdccDeploymentException>().having(
          (error) => error.hint ?? '',
          'hint',
          contains('白名单'),
        ),
      ),
    );
    expect(
      sdccRoot.existsSync() ? sdccDirectoryNames() : const <String>[],
      isEmpty,
    );
  });
}

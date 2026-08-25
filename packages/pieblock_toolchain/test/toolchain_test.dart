import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

const _validHex =
    ':0200000400FEFC\n'
    ':0100000001FE\n'
    ':0200000400FFFB\n'
    ':03000000020000FB\n'
    ':00000001FF\n';

void main() {
  test('应用 HEX 校验要求 FE 和 FF 两个区域', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-hex-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/firmware.hex');
    await file.writeAsString(_validHex);
    final result = await IntelHexValidator.validateApplication(file.path);
    expect(result.ok, isTrue);
    expect(result.image!.bytes, containsPair(0xfe0000, 1));
    expect(result.image!.bytes, containsPair(0xff0000, 0x02));

    await file.writeAsString(_validHex.replaceFirst('01FE', '01FF'));
    expect(
      (await IntelHexValidator.validateApplication(file.path)).ok,
      isFalse,
    );
  });

  test('SDCC 布局校验要求复位向量、内存区和启动符号', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-map-');
    addTearDown(() => directory.delete(recursive: true));
    final hex = File('${directory.path}/firmware.hex')
      ..writeAsStringSync(_validHex);
    final map = File('${directory.path}/firmware.map')
      ..writeAsStringSync(
        ' HOME     00FF0000 00000003 =\n'
        ' CSEG     00FE0000 00000001 =\n'
        ' XSEG     00010000 00000010 =\n'
        ' DSEG     00000000 00000010 =\n'
        '__sdcc_mcs251_reset_trampoline\n'
        '__sdcc_gsinit_startup\n'
        '_Default_Isr\n',
      );
    expect(
      (await IntelHexValidator.validateSdccLayout(
        hexPath: hex.path,
        mapPath: map.path,
      )).ok,
      isTrue,
    );
    await map.writeAsString(' HOME     00FF0000 00001001 =\n');
    expect(
      (await IntelHexValidator.validateSdccLayout(
        hexPath: hex.path,
        mapPath: map.path,
      )).ok,
      isFalse,
    );
  });

  test('构建指纹随源码、类型和编译器变化', () {
    BuildFingerprint fingerprint(
      String code,
      ProjectKind kind,
      CompilerKind compiler,
    ) => FirmwareBuilder.fingerprint(
      BuildRequest(
        projectKind: kind,
        sourceCode: code,
        compiler: compiler,
        compilerFingerprint: 'compiler-v1',
      ),
    );
    final base = fingerprint(
      'int main(void){}',
      ProjectKind.infantry,
      CompilerKind.sdcc,
    );
    expect(
      base.value,
      isNot(
        fingerprint(
          'int main(void){return 0;}',
          ProjectKind.infantry,
          CompilerKind.sdcc,
        ).value,
      ),
    );
    expect(
      base.value,
      isNot(
        fingerprint(
          'int main(void){}',
          ProjectKind.engineer,
          CompilerKind.sdcc,
        ).value,
      ),
    );
    expect(
      base.value,
      isNot(
        fingerprint(
          'int main(void){}',
          ProjectKind.infantry,
          CompilerKind.keil,
        ).value,
      ),
    );
  });

  test('构建缓存只复用哈希和布局均有效的 HEX', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-cache-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.hex')
      ..writeAsStringSync(_validHex);
    const fingerprint = BuildFingerprint(
      value: 'fingerprint',
      sourceHash: 'source',
    );
    final repository = BuildArtifactRepository(root: '${directory.path}/cache');
    final artifact = await repository.store(
      sourceHex: source.path,
      log: 'ok',
      artifact: BuildArtifact(
        hexPath: source.path,
        hexSha256: '',
        fingerprint: fingerprint.value,
        sourceSha256: fingerprint.sourceHash,
        compiler: CompilerKind.sdcc,
        compilerFingerprint: 'compiler',
        templateVersion: 'template',
        builtAt: DateTime.utc(2026),
        byteCount: 2,
        warningCount: 0,
      ),
    );
    expect(await repository.findFresh(fingerprint), isNotNull);
    await File(artifact.hexPath).writeAsString('corrupt');
    expect(await repository.findFresh(fingerprint), isNull);
  });

  test('缓存清理不删除正在使用的产物', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-prune-');
    addTearDown(() => directory.delete(recursive: true));
    final protected = Directory('${directory.path}/protected')
      ..createSync(recursive: true);
    File('${protected.path}/firmware.hex').writeAsStringSync(_validHex);
    await BuildArtifactRepository(root: directory.path).prune(
      maxAge: Duration.zero,
      maxBytes: 0,
      protectedFingerprints: const {'protected'},
    );
    expect(await protected.exists(), isTrue);
  });

  test('Keil 安装验证和许可证失败识别', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-keil-');
    addTearDown(() => directory.delete(recursive: true));
    File('${directory.path}/UV4/uVision.com')
      ..createSync(recursive: true)
      ..writeAsStringSync('uv4');
    File('${directory.path}/C251/BIN/C251.EXE')
      ..createSync(recursive: true)
      ..writeAsStringSync('c251');
    File('${directory.path}/TOOLS.INI').writeAsStringSync('[C251]\r\n');
    final discovery = const ToolchainDiscovery();
    final installation = await discovery.validateKeil(directory.path);
    expect(installation, isNotNull);
    expect(
      ToolchainDiscovery.isLicenseFailure('ERROR L250: RESTRICTED VERSION'),
      isTrue,
    );
    expect(
      await discovery.keilFingerprint(installation!),
      hasLength(sha256.convert([]).toString().length),
    );
  });
}

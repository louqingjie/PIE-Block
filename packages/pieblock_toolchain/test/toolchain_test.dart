import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';
import 'package:test/test.dart';

const _validHex =
    ':0200000400FEFC\n'
    ':0100000001FE\n'
    ':0200000400FFFB\n'
    ':03000000020000FB\n'
    ':00000001FF\n';

const _keilHexWithHighApplicationData =
    ':0200000400FEFC\n'
    ':0100000001FE\n'
    ':0200000400FFFB\n'
    ':03000000020000FB\n'
    ':01200000AA35\n'
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

  test('Keil 允许在 0xFF1000 之后的应用区放置数据', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pieblock-keil-hex-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final hex = File('${directory.path}/firmware.hex')
      ..writeAsStringSync(_keilHexWithHighApplicationData);
    expect((await IntelHexValidator.validateApplication(hex.path)).ok, isTrue);
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

  test('音乐和调试项目按编译器选择明确模板', () {
    expect(
      firmwareProjectFor(ProjectKind.music, CompilerKind.sdcc),
      'BUZZER_MUSIC_GENERATED',
    );
    expect(
      firmwareProjectFor(ProjectKind.music, CompilerKind.keil),
      'ROBOMASTER_INFANTRY',
    );
    expect(
      firmwareProjectFor(ProjectKind.debug, CompilerKind.sdcc),
      'ROBOMASTER_INFANTRY',
    );
    expect(
      firmwareProjectFor(ProjectKind.debug, CompilerKind.keil),
      'ROBOMASTER_INFANTRY',
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

  test('可注入的 SDCC 后端保持公共构建接口和布局校验', () async {
    final directory = await Directory.systemTemp.createTemp(
      'pieblock-backend-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final backend = _FakeSdccBackend();
    final builder = FirmwareBuilder(
      sdccBackend: backend,
      runtimeRoot: '${directory.path}/runtime',
      workRoot: '${directory.path}/work',
      artifacts: BuildArtifactRepository(root: '${directory.path}/artifacts'),
    );
    expect(
      await builder.resolveCompilerFingerprint(CompilerKind.sdcc),
      'native-test',
    );
    final operation = builder.start(
      const BuildRequest(
        projectKind: ProjectKind.infantry,
        sourceCode: 'void main(void) {}',
        compiler: CompilerKind.sdcc,
        compilerFingerprint: 'native-test',
      ),
    );
    final result = await operation.result;
    expect(result.success, isTrue);
    expect(result.artifact, isNotNull);
    expect(backend.buildCount, 1);
    builder.cancel();
    expect(backend.canceled, isTrue);
  });

  test('Android SDCC 构建计划保持源码顺序并生成中断声明', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-plan-');
    addTearDown(() => directory.delete(recursive: true));
    final resource = Directory('${directory.path}/resource');
    final firmware = Directory('${resource.path}/firmware');
    final toolchain = Directory('${resource.path}/toolchain');
    for (final path in [
      '${firmware.path}/startup/common.c',
      '${firmware.path}/projects/PROJECT/src/isr.c',
      '${firmware.path}/libraries/driver.c',
      '${firmware.path}/include/.keep',
      '${firmware.path}/projects/PROJECT/inc/.keep',
      '${toolchain.path}/include/.keep',
      '${toolchain.path}/include/mcs51/.keep',
      '${toolchain.path}/lib/mcs251-large-stack-auto/.keep',
    ]) {
      await File(path).create(recursive: true);
    }
    await File('${firmware.path}/startup/common.c')
        .writeAsString('void timer(void) __interrupt (2) {}');
    await File('${firmware.path}/projects/PROJECT/src/isr.c')
        .writeAsString('void uart(void) __interrupt (4) {}');
    await File('${firmware.path}/libraries/driver.c')
        .writeAsString('void driver(void) {}');
    final mainSource = File('${directory.path}/main.c')
      ..writeAsStringSync('void main(void) {}');
    await File('${firmware.path}/build_manifest.json').writeAsString(
      jsonEncode({
        'include_dirs': ['include'],
        'compile_flags': ['-mmcs251', '-c'],
        'link_flags': ['-mmcs251', '--nostdlib'],
        'runtime_libraries': ['mcs251.lib'],
        'source_groups': {
          'common': ['startup/common.c'],
          'drivers': ['libraries/driver.c'],
        },
        'projects': {
          'PROJECT': {
            'library_groups': ['drivers'],
          },
        },
      }),
    );

    final plan = await SdccBuildPlan.prepare(
      resourceRoot: resource.path,
      projectName: 'PROJECT',
      mainSourcePath: mainSource.path,
      outputDirectory: '${directory.path}/output',
    );
    final plannedFirmware = p.join(resource.path, 'firmware');
    expect(plan.sourcePaths, [
      p.join(plannedFirmware, 'startup', 'common.c'),
      p.join(plannedFirmware, 'projects', 'PROJECT', 'src', 'isr.c'),
      mainSource.path,
      p.join(plannedFirmware, 'libraries', 'driver.c'),
    ]);
    expect(plan.compileArguments, containsAllInOrder(['-mmcs251', '-c']));
    expect(plan.linkArguments, containsAll(['--nostdlib', 'mcs251.lib']));
    final header = await File(plan.interruptHeaderPath).readAsString();
    expect(header, contains('void timer(void) __interrupt (2);'));
    expect(header, contains('void uart(void) __interrupt (4);'));
  });
}

class _FakeSdccBackend implements SdccCompilerBackend {
  int buildCount = 0;
  bool canceled = false;

  @override
  Future<String> resolveFingerprint() async => 'native-test';

  @override
  Future<CompilerBackendResult> build(
    BuildRequest request,
    String workDirectory,
    BuildEventSink emit,
  ) async {
    buildCount++;
    final output = Directory('$workDirectory/output')
      ..createSync(recursive: true);
    final hex = File('${output.path}/firmware.hex')
      ..writeAsStringSync(_validHex);
    final map = File('${output.path}/firmware.map')
      ..writeAsStringSync(
        ' HOME     00FF0000 00000003 =\n'
        ' CSEG     00FE0000 00000001 =\n'
        ' XSEG     00010000 00000010 =\n'
        ' DSEG     00000000 00000010 =\n'
        '__sdcc_mcs251_reset_trampoline\n'
        '__sdcc_gsinit_startup\n'
        '_Default_Isr\n',
      );
    emit(BuildStage.compiling, 'fake native compile');
    return CompilerBackendResult(
      success: true,
      exitCode: 0,
      hexPath: hex.path,
      mapPath: map.path,
    );
  }

  @override
  void cancel() => canceled = true;
}

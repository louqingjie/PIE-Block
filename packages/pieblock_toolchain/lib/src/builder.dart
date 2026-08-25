import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:pieblock_core/pieblock_core.dart';

import 'artifact_repository.dart';
import 'compiler_backend.dart';
import 'hex_validator.dart';
import 'models.dart';

const _buildSchemaVersion = 'flutter_build_v1';

class KeilInstallation {
  const KeilInstallation({
    required this.root,
    required this.uv4,
    required this.c251,
    this.toolsIni,
  });

  final String root;
  final String uv4;
  final String c251;
  final String? toolsIni;
}

class ToolchainDiscovery {
  const ToolchainDiscovery();

  Future<KeilInstallation?> validateKeil(String root) async {
    if (root.trim().isEmpty) return null;
    final normalized = Directory(root).absolute.path;
    if (!await Directory(normalized).exists()) return null;
    final uv4 = await _findFirst(
      normalized,
      const [r'UV4\uVision.com', r'UV4\UV4.exe'],
      const ['uVision.com', 'UV4.exe'],
    );
    final c251 = await _findFirst(
      normalized,
      const [r'C251\BIN\C251.EXE'],
      const ['C251.EXE'],
    );
    if (uv4 == null || c251 == null) return null;
    final tools = File(p.join(normalized, 'TOOLS.INI'));
    return KeilInstallation(
      root: normalized,
      uv4: uv4,
      c251: c251,
      toolsIni: await tools.exists() ? tools.path : null,
    );
  }

  Future<KeilInstallation?> resolveKeil({String? configuredPath}) async {
    final candidates = <String>{
      if ((Platform.environment['PIEBLOCK_KEIL'] ?? '').trim().isNotEmpty)
        Platform.environment['PIEBLOCK_KEIL']!.trim(),
      if ((configuredPath ?? '').trim().isNotEmpty) configuredPath!.trim(),
      r'C:\Keil_v5',
      r'C:\Keil',
    };
    for (final candidate in candidates) {
      final result = await validateKeil(candidate);
      if (result != null) return result;
    }
    return null;
  }

  Future<String> keilFingerprint(KeilInstallation installation) async {
    final bytes = <int>[];
    for (final filePath in [installation.uv4, installation.c251]) {
      bytes.addAll(utf8.encode(p.basename(filePath).toLowerCase()));
      bytes.addAll(await File(filePath).readAsBytes());
    }
    return sha256.convert(bytes).toString();
  }

  Future<bool> applyKeilLicense(
    KeilInstallation installation,
    String key,
  ) async {
    final iniPath = installation.toolsIni;
    if (iniPath == null || key.trim().isEmpty) return false;
    final file = File(iniPath);
    final original = await file.readAsString();
    final lines = const LineSplitter().convert(original).toList();
    var inC251 = false;
    var replaced = false;
    var section = -1;
    for (var index = 0; index < lines.length; index++) {
      final trimmed = lines[index].trim();
      if (trimmed.toUpperCase() == '[C251]') {
        inC251 = true;
        section = index;
        continue;
      }
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) inC251 = false;
      if (inC251 && trimmed.toUpperCase().startsWith('LIC0=')) {
        lines[index] = 'LIC0=${key.trim()}';
        replaced = true;
      }
    }
    if (!replaced) {
      if (section < 0) {
        lines.addAll(['[C251]', 'LIC0=${key.trim()}']);
      } else {
        lines.insert(section + 1, 'LIC0=${key.trim()}');
      }
    }
    final backup = File('$iniPath.pieblock.bak');
    if (!await backup.exists()) await file.copy(backup.path);
    final temporary = File('$iniPath.pieblock.tmp');
    await temporary.writeAsString('${lines.join('\r\n')}\r\n', flush: true);
    await file.delete();
    await temporary.rename(file.path);
    return true;
  }

  static bool isLicenseFailure(String log) =>
      log.contains('RESTRICTED VERSION') ||
      log.contains('LICENSE ERROR') ||
      log.contains('ERROR L250');

  static Future<String?> _findFirst(
    String root,
    List<String> preferred,
    List<String> names,
  ) async {
    for (final relative in preferred) {
      final candidate = File(p.join(root, relative));
      if (await candidate.exists()) return candidate.path;
    }
    final lowerNames = names.map((name) => name.toLowerCase()).toSet();
    await for (final entity in Directory(
      root,
    ).list(recursive: true, followLinks: false).handleError((_) {})) {
      if (entity is File &&
          lowerNames.contains(p.basename(entity.path).toLowerCase())) {
        return entity.path;
      }
    }
    return null;
  }
}

class FirmwareBuilder {
  // A public parameter is required because the injected field is intentionally
  // private to the toolchain implementation.
  // ignore: prefer_initializing_formals
  FirmwareBuilder({
    BuildArtifactRepository? artifacts,
    String? runtimeRoot,
    String? workRoot,
    SdccCompilerBackend? sdccBackend,
  }) : artifacts = artifacts ?? BuildArtifactRepository(),
       _runtimeRoot = runtimeRoot ?? _defaultRuntimeRoot(),
       _workRoot = workRoot ?? _defaultWorkRoot(),
       _sdccBackend = sdccBackend;

  final BuildArtifactRepository artifacts;
  final String _runtimeRoot;
  final String _workRoot;
  final SdccCompilerBackend? _sdccBackend;
  Process? _process;
  bool _canceled = false;

  static String _defaultRuntimeRoot() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return p.join(base, 'PIE-Block', 'runtime');
  }

  static String _defaultWorkRoot() {
    final base =
        Platform.environment['LOCALAPPDATA'] ?? Directory.systemTemp.path;
    return p.join(base, 'PIE-Block', 'work');
  }

  static BuildFingerprint fingerprint(BuildRequest request) {
    final sourceHash = sha256
        .convert(utf8.encode(request.sourceCode))
        .toString();
    final value = sha256
        .convert(
          utf8.encode(
            [
              _buildSchemaVersion,
              'STC32G12K128',
              request.projectKind.name,
              request.compiler.name,
              request.compilerFingerprint,
              sourceHash,
            ].join('|'),
          ),
        )
        .toString();
    return BuildFingerprint(value: value, sourceHash: sourceHash);
  }

  Future<String> resolveCompilerFingerprint(
    CompilerKind compiler, {
    String? keilRoot,
  }) async {
    if (compiler == CompilerKind.keil) {
      final installation = await const ToolchainDiscovery().validateKeil(
        keilRoot ?? '',
      );
      if (installation == null) throw StateError('Keil 目录无效或缺少 C251');
      return const ToolchainDiscovery().keilFingerprint(installation);
    }
    final backend = _sdccBackend;
    if (backend != null) return backend.resolveFingerprint();
    final assets = await _locateAssets();
    final bundle = await File(
      p.join(assets.sdccToolchain, 'bundle_manifest.json'),
    ).readAsString();
    final firmware = await File(
      p.join(assets.sdccFirmware, 'build_manifest.json'),
    ).readAsString();
    return sha256.convert(utf8.encode('$bundle\n$firmware')).toString();
  }

  BuildOperation start(BuildRequest request) {
    final events = StreamController<BuildEvent>.broadcast();
    _canceled = false;
    final result = _build(request, events).whenComplete(events.close);
    return BuildOperation(events.stream, result, cancel);
  }

  void cancel() {
    _canceled = true;
    _sdccBackend?.cancel();
    final process = _process;
    if (process == null) return;
    process.kill();
    if (Platform.isWindows) {
      unawaited(
        Process.run('taskkill.exe', ['/T', '/F', '/PID', '${process.pid}']),
      );
    }
  }

  Future<BuildResult> _build(
    BuildRequest request,
    StreamController<BuildEvent> events,
  ) async {
    final fingerprintValue = fingerprint(request);
    final logs = <String>[];
    void emit(
      BuildStage stage,
      String message, {
      BuildEventLevel level = BuildEventLevel.info,
      int? current,
      int? total,
    }) {
      logs.add(message);
      events.add(
        BuildEvent(
          stage: stage,
          message: message,
          level: level,
          current: current,
          total: total,
        ),
      );
    }

    final work = Directory(
      p.join(
        _workRoot,
        '${fingerprintValue.value.substring(0, 16)}.${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    await work.create(recursive: true);
    try {
      emit(
        BuildStage.preparing,
        '正在准备 ${request.compiler == CompilerKind.sdcc ? 'SDCC' : 'Keil'} 构建环境…',
      );
      final raw = request.compiler == CompilerKind.sdcc
          ? await _buildSelectedSdcc(request, work.path, emit)
          : await _buildKeil(request, work.path, emit);
      if (_canceled) {
        return BuildResult(
          success: false,
          canceled: true,
          log: logs.join('\n'),
        );
      }
      if (!raw.success || raw.hexPath == null) {
        return BuildResult(
          success: false,
          log: logs.join('\n'),
          exitCode: raw.exitCode,
          licenseFailure: raw.licenseFailure,
        );
      }
      emit(BuildStage.validating, '正在校验 HEX 地址和校验和…');
      final validation = await IntelHexValidator.validateApplication(
        raw.hexPath!,
      );
      emit(
        BuildStage.validating,
        validation.message,
        level: validation.ok ? BuildEventLevel.info : BuildEventLevel.error,
      );
      if (!validation.ok) {
        return BuildResult(success: false, log: logs.join('\n'));
      }
      final artifact = await artifacts.store(
        sourceHex: raw.hexPath!,
        log: logs.join('\n'),
        artifact: BuildArtifact(
          hexPath: raw.hexPath!,
          hexSha256: '',
          fingerprint: fingerprintValue.value,
          sourceSha256: fingerprintValue.sourceHash,
          compiler: request.compiler,
          compilerFingerprint: request.compilerFingerprint,
          templateVersion: _buildSchemaVersion,
          builtAt: DateTime.now(),
          byteCount: validation.image!.bytes.length,
          warningCount: raw.warningCount,
        ),
      );
      emit(BuildStage.done, '编译完成：${artifact.byteCount} 字节');
      return BuildResult(
        success: true,
        artifact: artifact,
        log: logs.join('\n'),
        exitCode: 0,
      );
    } catch (error) {
      emit(BuildStage.done, '编译失败：$error', level: BuildEventLevel.error);
      return BuildResult(success: false, log: logs.join('\n'));
    } finally {
      _process = null;
      if (await work.exists()) {
        try {
          await work.delete(recursive: true);
        } catch (_) {}
      }
    }
  }

  Future<_RawBuildResult> _buildSelectedSdcc(
    BuildRequest request,
    String work,
    BuildEventSink emit,
  ) async {
    final backend = _sdccBackend;
    if (backend == null) return _buildSdcc(request, work, emit);
    final result = await backend.build(request, work, emit);
    var success = result.success;
    if (success && result.hexPath != null && result.mapPath != null) {
      final layout = await IntelHexValidator.validateSdccLayout(
        hexPath: result.hexPath!,
        mapPath: result.mapPath!,
      );
      emit(
        BuildStage.validating,
        layout.message,
        level: layout.ok ? BuildEventLevel.info : BuildEventLevel.error,
      );
      success = layout.ok;
    } else if (success) {
      emit(
        BuildStage.validating,
        'Android SDCC 未返回完整的 HEX/MAP 产物',
        level: BuildEventLevel.error,
      );
      success = false;
    }
    if ((result.message ?? '').isNotEmpty) {
      emit(
        BuildStage.done,
        result.message!,
        level: success
            ? BuildEventLevel.info
            : result.canceled
            ? BuildEventLevel.warning
            : BuildEventLevel.error,
      );
    }
    if (result.canceled) _canceled = true;
    return _RawBuildResult(
      success,
      exitCode: result.exitCode,
      hexPath: result.hexPath,
      warningCount: result.warningCount,
    );
  }

  Future<_RawBuildResult> _buildSdcc(
    BuildRequest request,
    String work,
    void Function(
      BuildStage,
      String, {
      BuildEventLevel level,
      int? current,
      int? total,
    })
    emit,
  ) async {
    final assets = await _locateAssets();
    final deployed = await _deploySdcc(assets, emit);
    final manifest = (jsonDecode(
      await File(p.join(deployed.firmware, 'build_manifest.json'))
          .readAsString(),
    ) as Map).cast<String, Object?>();
    final project = request.projectKind == ProjectKind.infantry
        ? 'ROBOMASTER_INFANTRY'
        : 'ROBOMASTER_ENGINEER';
    final sources = _sourcesFor(manifest, project);
    final output = Directory(p.join(work, 'output'))
      ..createSync(recursive: true);
    final mainPath = p.join(work, 'main.c');
    await File(mainPath).writeAsString(request.sourceCode);
    final interruptHeader = p.join(
      output.path,
      'generated_interrupt_declarations.h',
    );
    await _writeInterruptHeader(
      deployed.firmware,
      sources,
      mainPath,
      interruptHeader,
      project,
    );
    final includeArgs = <String>[
      '-I${p.join(deployed.toolchain, 'include')}',
      '-I${p.join(deployed.toolchain, 'include', 'mcs51')}',
      for (final dir in (manifest['include_dirs']! as List))
        '-I${p.join(deployed.firmware, '$dir')}',
      '-I${p.join(deployed.firmware, 'projects', project, 'inc')}',
    ];
    final directObjects = <String>[];
    final libraryObjects = <String>[];
    final librarySources = sources.$2.toSet();
    var warningCount = 0;
    for (var index = 0; index < sources.$1.length; index++) {
      final relative = sources.$1[index];
      final source = relative.endsWith('/src/main.c')
          ? mainPath
          : p.join(deployed.firmware, relative.replaceAll('/', p.separator));
      final object = p.join(
        output.path,
        '${p.basenameWithoutExtension(source)}_$index.rel',
      );
      emit(
        BuildStage.compiling,
        '[${index + 1}/${sources.$1.length}] 编译 $relative',
        current: index + 1,
        total: sources.$1.length,
      );
      final args = <String>[
        for (final flag in (manifest['compile_flags']! as List)) '$flag',
        ...includeArgs,
        if (relative.endsWith('/src/main.c')) ...['--include', interruptHeader],
        '-o',
        object,
        source,
      ];
      final run = await _run(
        p.join(deployed.toolchain, 'bin', 'sdcc.exe'),
        args,
        emit,
        BuildStage.compiling,
      );
      warningCount += _visibleWarningCount(run.output);
      if (run.exitCode != 0 || _canceled) {
        return _RawBuildResult(
          false,
          exitCode: run.exitCode,
          warningCount: warningCount,
        );
      }
      (librarySources.contains(relative) ? libraryObjects : directObjects).add(
        object,
      );
    }
    final sharedLibrary = File(p.join(output.path, 'stc32g_shared.lib'));
    await sharedLibrary.writeAsString(
      '${libraryObjects.map(p.basenameWithoutExtension).join('\n')}\n',
    );
    final libDir = p.join(deployed.toolchain, 'lib', 'mcs251-large-stack-auto');
    final hexPath = p.join(output.path, '$project.hex');
    emit(BuildStage.linking, '正在链接 $project.hex…');
    final linkArgs = <String>[
      for (final flag in (manifest['link_flags']! as List)) '$flag',
      '-L${output.path}',
      '-L$libDir',
      ...includeArgs,
      ...directObjects,
      p.basename(sharedLibrary.path),
      for (final library in (manifest['runtime_libraries']! as List))
        '$library',
      '-o',
      hexPath,
    ];
    final link = await _run(
      p.join(deployed.toolchain, 'bin', 'sdcc.exe'),
      linkArgs,
      emit,
      BuildStage.linking,
      workingDirectory: output.path,
    );
    warningCount += _visibleWarningCount(link.output);
    if (link.exitCode == 0 && !_canceled) {
      final layout = await IntelHexValidator.validateSdccLayout(
        hexPath: hexPath,
        mapPath: p.setExtension(hexPath, '.map'),
      );
      emit(
        BuildStage.validating,
        layout.message,
        level: layout.ok ? BuildEventLevel.info : BuildEventLevel.error,
      );
      if (!layout.ok) {
        return _RawBuildResult(
          false,
          exitCode: link.exitCode,
          warningCount: warningCount,
        );
      }
    }
    return _RawBuildResult(
      link.exitCode == 0 && await File(hexPath).exists(),
      exitCode: link.exitCode,
      hexPath: hexPath,
      warningCount: warningCount,
    );
  }

  Future<_RawBuildResult> _buildKeil(
    BuildRequest request,
    String work,
    void Function(
      BuildStage,
      String, {
      BuildEventLevel level,
      int? current,
      int? total,
    })
    emit,
  ) async {
    final installation = await const ToolchainDiscovery().validateKeil(
      request.keilRoot ?? '',
    );
    if (installation == null) {
      emit(
        BuildStage.preparing,
        'Keil 目录无效或缺少 C251',
        level: BuildEventLevel.error,
      );
      return const _RawBuildResult(false);
    }
    final assets = await _locateAssets();
    final projectName = request.projectKind == ProjectKind.infantry
        ? 'ROBOMASTER_INFANTRY'
        : 'ROBOMASTER_ENGINEER';
    final workspace = p.join(work, 'stc32g');
    await _copyDirectory(
      Directory(p.join(assets.keil, 'Libraries')),
      Directory(p.join(workspace, 'Libraries')),
    );
    final projectDir = p.join(workspace, 'Projects', projectName);
    await _copyDirectory(
      Directory(p.join(assets.keil, 'Projects', projectName)),
      Directory(projectDir),
    );
    final mdk = p.join(projectDir, 'MDK');
    for (final generated in [
      Directory(p.join(mdk, 'Objects')),
      Directory(p.join(mdk, 'Listings')),
    ]) {
      if (await generated.exists()) await generated.delete(recursive: true);
    }
    final logFile = File(p.join(mdk, 'pie_block_build.log'));
    if (await logFile.exists()) await logFile.delete();
    await File(p.join(projectDir, 'USER', 'src', 'main.c'))
        .writeAsString(request.sourceCode);
    final projectFile = p.join(mdk, 'Project_Template.uvproj');
    final logPath = p.join(mdk, 'pie_block_build.log');
    emit(BuildStage.compiling, '正在调用 Keil C251 全量重建…');
    final run = await _run(
      installation.uv4,
      ['-r', projectFile, '-o', logPath],
      emit,
      BuildStage.compiling,
      workingDirectory: mdk,
      publishOutput: false,
    );
    final log = await File(logPath).exists()
        ? await File(logPath).readAsString()
        : run.output;
    for (final line in const LineSplitter().convert(log)) {
      if (line.trim().isNotEmpty) {
        emit(
          BuildStage.compiling,
          line,
          level: line.toLowerCase().contains('error')
              ? BuildEventLevel.error
              : line.toLowerCase().contains('warning')
              ? BuildEventLevel.warning
              : BuildEventLevel.info,
        );
      }
    }
    final hexPath = p.join(mdk, 'Objects', 'Project_Template.hex');
    return _RawBuildResult(
      log.contains('0 Error(s)') && await File(hexPath).exists(),
      exitCode: run.exitCode,
      hexPath: hexPath,
      warningCount: RegExp(
        r'\bwarning\b',
        caseSensitive: false,
      ).allMatches(log).length,
      licenseFailure: ToolchainDiscovery.isLicenseFailure(log),
    );
  }

  Future<_RunResult> _run(
    String executable,
    List<String> args,
    void Function(
      BuildStage,
      String, {
      BuildEventLevel level,
      int? current,
      int? total,
    })
    emit,
    BuildStage stage, {
    String? workingDirectory,
    bool publishOutput = true,
  }) async {
    final process = await Process.start(
      executable,
      args,
      workingDirectory: workingDirectory,
      mode: ProcessStartMode.normal,
    );
    _process = process;
    final output = StringBuffer();
    final streamDone = <Future<void>>[];
    void listen(Stream<List<int>> stream) {
      streamDone.add(
        stream
            .transform(const Utf8Decoder(allowMalformed: true))
            .transform(const LineSplitter())
            .listen((line) {
              output.writeln(line);
              if (!publishOutput || _isInternalCompilerNoise(line)) return;
              emit(
                stage,
                line,
                level: line.toLowerCase().contains('error')
                    ? BuildEventLevel.error
                    : line.toLowerCase().contains('warning')
                    ? BuildEventLevel.warning
                    : BuildEventLevel.info,
              );
            })
            .asFuture<void>(),
      );
    }

    listen(process.stdout);
    listen(process.stderr);
    final exitCode = await process.exitCode;
    await Future.wait(streamDone);
    if (identical(_process, process)) _process = null;
    return _RunResult(exitCode, output.toString());
  }

  static (List<String>, List<String>) _sourcesFor(
    Map<String, Object?> manifest,
    String project,
  ) {
    final groups = (manifest['source_groups']! as Map).cast<String, Object?>();
    final projects = (manifest['projects']! as Map).cast<String, Object?>();
    final spec = (projects[project]! as Map).cast<String, Object?>();
    final sources = <String>[];
    final libraries = <String>[];
    void add(String value) {
      if (!sources.contains(value)) sources.add(value);
    }

    for (final value in groups['common']! as List) {
      add('$value');
    }
    add('projects/$project/src/isr.c');
    add('projects/$project/src/main.c');
    for (final groupName in spec['library_groups']! as List) {
      for (final value in groups['$groupName']! as List) {
        add('$value');
        if (!libraries.contains('$value')) libraries.add('$value');
      }
    }
    return (sources, libraries);
  }

  static bool _isInternalCompilerNoise(String line) =>
      line.contains('__has_builtin') ||
      line.contains('__STDC_HOSTED__') ||
      line.contains('<built-in>: note:') ||
      line.startsWith('DPTR no-match:') ||
      line.contains('warning 110:') ||
      line.contains('warning 126:');

  static int _visibleWarningCount(String output) => const LineSplitter()
      .convert(output)
      .where(
        (line) =>
            line.toLowerCase().contains('warning') &&
            !_isInternalCompilerNoise(line),
      )
      .length;

  static Future<void> _writeInterruptHeader(
    String firmware,
    (List<String>, List<String>) sources,
    String mainPath,
    String destination,
    String project,
  ) async {
    final declarations = <String>{};
    final pattern = RegExp(
      r'^\s*(?:static\s+)?void\s+([A-Za-z_]\w*)\s*\(\s*void\s*\)\s*__interrupt\s*\(\s*([^)]*?)\s*\)',
      multiLine: true,
    );
    for (final relative in sources.$1) {
      final source = relative.endsWith('/src/main.c')
          ? mainPath
          : p.join(firmware, relative.replaceAll('/', p.separator));
      final text = await File(source).readAsString();
      for (final match in pattern.allMatches(text)) {
        declarations.add(
          'void ${match.group(1)}(void) __interrupt (${match.group(2)!.trim()});',
        );
      }
    }
    final sorted = declarations.toList()..sort();
    await File(destination).writeAsString(
      '#ifndef PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
      '#define PIE_BLOCK_GENERATED_INTERRUPT_DECLARATIONS_H\n'
      '#include "STC32Gxx.h"\n#include <stdlib.h>\n'
      '${sorted.join('\n')}\n#endif\n',
    );
  }

  Future<_DeployedSdcc> _deploySdcc(
    _ToolchainAssets assets,
    void Function(
      BuildStage,
      String, {
      BuildEventLevel level,
      int? current,
      int? total,
    })
    emit,
  ) async {
    final bundleManifest = File(
      p.join(assets.sdccToolchain, 'bundle_manifest.json'),
    );
    final firmwareManifest = File(
      p.join(assets.sdccFirmware, 'build_manifest.json'),
    );
    final fingerprintValue = sha256
        .convert(
          utf8.encode(
            '${await bundleManifest.readAsString()}\n${await firmwareManifest.readAsString()}',
          ),
        )
        .toString();
    final destination = Directory(
      p.join(_runtimeRoot, 'sdcc', fingerprintValue),
    );
    final marker = File(p.join(destination.path, '.ready'));
    if (!await marker.exists()) {
      emit(BuildStage.preparing, '首次使用，正在部署内置 SDCC 工具链…');
      final pending = Directory('${destination.path}.pending');
      if (await pending.exists()) await pending.delete(recursive: true);
      await _copyDirectory(
        Directory(assets.sdccToolchain),
        Directory(p.join(pending.path, 'toolchain')),
      );
      await _copyDirectory(
        Directory(assets.sdccFirmware),
        Directory(p.join(pending.path, 'firmware')),
      );
      await _validateSdccBundle(Directory(p.join(pending.path, 'toolchain')));
      await File(p.join(pending.path, '.ready'))
          .writeAsString(fingerprintValue, flush: true);
      if (await destination.exists()) await destination.delete(recursive: true);
      await pending.rename(destination.path);
    }
    return _DeployedSdcc(
      p.join(destination.path, 'toolchain'),
      p.join(destination.path, 'firmware'),
    );
  }

  static Future<void> _validateSdccBundle(Directory toolchain) async {
    final manifestFile = File(p.join(toolchain.path, 'bundle_manifest.json'));
    final manifest = (jsonDecode(await manifestFile.readAsString()) as Map)
        .cast<String, Object?>();
    final files = (manifest['files']! as Map).cast<String, Object?>();
    for (final entry in files.entries) {
      final file = File(
        p.join(toolchain.path, entry.key.replaceAll('/', p.separator)),
      );
      if (!await file.exists()) {
        throw StateError('内置 SDCC 工具链文件缺失：${entry.key}');
      }
      final actual = sha256.convert(await file.readAsBytes()).toString();
      if (actual != entry.value) {
        throw StateError('内置 SDCC 工具链文件校验失败：${entry.key}');
      }
    }
  }

  static Future<_ToolchainAssets> _locateAssets() async {
    final candidates = <String>[
      if ((Platform.environment['PIEBLOCK_RUNTIME_ROOT'] ?? '').isNotEmpty)
        Platform.environment['PIEBLOCK_RUNTIME_ROOT']!,
      p.join(
        File(Platform.resolvedExecutable).parent.path,
        'data',
        'pieblock_runtime',
      ),
    ];
    var cursor = Directory.current.absolute;
    for (var depth = 0; depth < 8; depth++) {
      candidates.add(cursor.path);
      final parent = cursor.parent;
      if (parent.path == cursor.path) break;
      cursor = parent;
    }
    for (final root in candidates) {
      final directToolchain = Directory(p.join(root, 'sdcc-toolchain'));
      final repoToolchain = Directory(p.join(root, 'vendor', 'sdcc-toolchain'));
      final firmware = Directory(p.join(root, 'stc32g_sdcc'));
      final keil = Directory(p.join(root, 'stc32g'));
      final toolchain = await directToolchain.exists()
          ? directToolchain
          : repoToolchain;
      if (await toolchain.exists() &&
          await firmware.exists() &&
          await keil.exists()) {
        return _ToolchainAssets(toolchain.path, firmware.path, keil.path);
      }
    }
    throw StateError('发布包缺少 C251 工具链资源');
  }

  static Future<void> _copyDirectory(
    Directory source,
    Directory destination,
  ) async {
    await destination.create(recursive: true);
    await for (final entity in source.list(followLinks: false)) {
      final target = p.join(destination.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyDirectory(entity, Directory(target));
      } else if (entity is File) {
        await entity.copy(target);
      }
    }
  }
}

class _RunResult {
  const _RunResult(this.exitCode, this.output);
  final int exitCode;
  final String output;
}

class _RawBuildResult {
  const _RawBuildResult(
    this.success, {
    this.exitCode,
    this.hexPath,
    this.warningCount = 0,
    this.licenseFailure = false,
  });
  final bool success;
  final int? exitCode;
  final String? hexPath;
  final int warningCount;
  final bool licenseFailure;
}

class _ToolchainAssets {
  const _ToolchainAssets(this.sdccToolchain, this.sdccFirmware, this.keil);
  final String sdccToolchain;
  final String sdccFirmware;
  final String keil;
}

class _DeployedSdcc {
  const _DeployedSdcc(this.toolchain, this.firmware);
  final String toolchain;
  final String firmware;
}

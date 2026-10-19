import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'compiler_backend.dart';
import 'file_ops.dart';
import 'models.dart';

const _readyMarker = '.ready';

/// 一份已部署且通过校验的内置 SDCC 运行时。
class SdccRuntimeDeployment {
  const SdccRuntimeDeployment({
    required this.toolchain,
    required this.firmware,
  });

  final String toolchain;
  final String firmware;
}

/// 内置 SDCC 工具链部署失败，[hint] 给用户可操作的处理建议。
class SdccDeploymentException implements Exception {
  SdccDeploymentException(this.message, {this.hint});

  final String message;
  final String? hint;

  @override
  String toString() => hint == null ? message : '$message\n$hint';
}

/// 把发布包里的 SDCC 工具链与固件源码复制到用户运行时目录。
///
/// 部署过程坚持“先写唯一暂存目录、校验通过后再晋升”的顺序：
/// - 暂存目录名带进程号与时间戳，避免烧录页和「生成代码 → 汇编」页各自
///   的 [FirmwareBuilder] 同时首次部署时互相删除/覆盖；
/// - 目标目录只有在 `.ready` 落盘后才可能被 rename 出来，半成品目标目录
///   会被清理后重装；
/// - 目录 rename 被杀毒软件等进程短暂占用时会退避重试；仍失败则抛出带
///   处理建议的 [SdccDeploymentException]。
class SdccRuntimeDeployer {
  SdccRuntimeDeployer({
    required this.runtimeRoot,
    this.staleStagingAge = const Duration(hours: 1),
  });

  final String runtimeRoot;

  /// 超过该时长的 `*.pending` / `*.staging-*` 视为崩溃残留并清理。
  final Duration staleStagingAge;

  /// 同一进程内的部署串行化：烧录页与汇编栏共用同一个运行时目录。
  static Future<void> _queue = Future<void>.value();

  static const _promoteAttempts = 8;
  static const _initialRetryDelay = Duration(milliseconds: 120);
  static const _maxRetryDelay = Duration(seconds: 2);

  /// 确保 [fingerprint] 对应的运行时已就绪，返回工具链与固件源码路径。
  Future<SdccRuntimeDeployment> ensure({
    required String toolchainAssets,
    required String firmwareAssets,
    required String fingerprint,
    required BuildEventSink emit,
  }) {
    final result = _queue.then(
      (_) => _ensure(
        toolchainAssets: toolchainAssets,
        firmwareAssets: firmwareAssets,
        fingerprint: fingerprint,
        emit: emit,
      ),
    );
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<SdccRuntimeDeployment> _ensure({
    required String toolchainAssets,
    required String firmwareAssets,
    required String fingerprint,
    required BuildEventSink emit,
  }) async {
    final root = Directory(p.join(runtimeRoot, 'sdcc'));
    final destination = Directory(p.join(root.path, fingerprint));
    if (await _isReady(destination, fingerprint)) {
      return _deployment(destination);
    }
    emit(BuildStage.preparing, '首次使用，正在部署内置 SDCC 工具链…');
    final staging = Directory(
      p.join(
        root.path,
        '$fingerprint.staging-$pid-${DateTime.now().microsecondsSinceEpoch}',
      ),
    );
    try {
      await _pruneStaleStaging(root, staging);
      await copyDirectory(
        Directory(toolchainAssets),
        Directory(p.join(staging.path, 'toolchain')),
      );
      await copyDirectory(
        Directory(firmwareAssets),
        Directory(p.join(staging.path, 'firmware')),
      );
      await _validateBundle(Directory(p.join(staging.path, 'toolchain')));
      await File(p.join(staging.path, _readyMarker))
          .writeAsString(fingerprint, flush: true);
      await _promote(staging, destination, fingerprint, emit);
      return _deployment(destination);
    } on SdccDeploymentException {
      rethrow;
    } on Object catch (error) {
      throw SdccDeploymentException(
        '内置 SDCC 工具链部署失败：$error',
        hint: _deploymentHint(root),
      );
    } finally {
      await _bestEffortDelete(staging);
    }
  }

  String _deploymentHint(Directory root) =>
      '请关闭杀毒软件实时防护，或将 ${root.path} 加入白名单后重试；'
      '若仍失败，可退出应用后删除该目录再重试。';

  SdccRuntimeDeployment _deployment(Directory destination) =>
      SdccRuntimeDeployment(
        toolchain: p.join(destination.path, 'toolchain'),
        firmware: p.join(destination.path, 'firmware'),
      );

  /// `.ready` 只在复制与校验全部完成后写入；同时检查关键文件，避免
  /// 把历史版本或半成品目录当成可用部署。
  Future<bool> _isReady(Directory destination, String fingerprint) async {
    try {
      final marker = File(p.join(destination.path, _readyMarker));
      if (!await marker.exists()) return false;
      if ((await marker.readAsString()).trim() != fingerprint) return false;
      final bin = p.join(destination.path, 'toolchain', 'bin');
      final executable = File(
        p.join(bin, Platform.isWindows ? 'sdcc.exe' : 'sdcc'),
      );
      if (!await executable.exists()) return false;
      return await File(
        p.join(destination.path, 'firmware', 'build_manifest.json'),
      ).exists();
    } on FileSystemException {
      return false;
    }
  }

  Future<void> _pruneStaleStaging(Directory root, Directory current) async {
    if (!await root.exists()) return;
    final now = DateTime.now();
    await for (final entity in root.list(followLinks: false)) {
      if (entity is! Directory || entity.path == current.path) continue;
      final name = p.basename(entity.path);
      if (!name.endsWith('.pending') && !name.contains('.staging-')) continue;
      try {
        final stat = await entity.stat();
        if (now.difference(stat.modified) < staleStagingAge) continue;
        await entity.delete(recursive: true);
      } on FileSystemException {
        // 残留清理失败不影响本次部署。
      }
    }
  }

  /// 晋升暂存目录。每一轮都先确认目标是否已被另一实例部署好，只有目标
  /// 不可用时才删除，绝不主动删掉一份已就绪的部署。
  Future<void> _promote(
    Directory staging,
    Directory destination,
    String fingerprint,
    BuildEventSink emit,
  ) async {
    var delay = _initialRetryDelay;
    for (var attempt = 1; attempt <= _promoteAttempts; attempt++) {
      if (await _isReady(destination, fingerprint)) {
        await _bestEffortDelete(staging);
        return;
      }
      try {
        if (await destination.exists()) {
          await destination.delete(recursive: true);
        }
        await staging.rename(destination.path);
        return;
      } on FileSystemException {
        if (attempt == 1) {
          emit(
            BuildStage.preparing,
            '内置 SDCC 工具链目录暂时被占用，正在重试…',
            level: BuildEventLevel.warning,
          );
        }
        if (attempt < _promoteAttempts) {
          await Future<void>.delayed(delay);
          final next = delay.inMilliseconds * 2;
          delay = Duration(
            milliseconds: next > _maxRetryDelay.inMilliseconds
                ? _maxRetryDelay.inMilliseconds
                : next,
          );
        }
      }
    }
    if (await _isReady(destination, fingerprint)) {
      await _bestEffortDelete(staging);
      return;
    }
    throw SdccDeploymentException(
      '内置 SDCC 工具链部署失败：${destination.path} 无法替换（文件被其它进程占用）',
      hint: _deploymentHint(Directory(p.join(runtimeRoot, 'sdcc'))),
    );
  }

  Future<void> _validateBundle(Directory toolchain) async {
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

  Future<void> _bestEffortDelete(Directory directory) async {
    try {
      if (await directory.exists()) await directory.delete(recursive: true);
    } on FileSystemException {
      // 尽力清理；失败则留待下次部署按 staleStagingAge 处理。
    }
  }
}

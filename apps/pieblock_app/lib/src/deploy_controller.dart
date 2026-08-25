import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_sdcc_native/pieblock_sdcc_native.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

enum DeployActivity { idle, preparing, building, flashing }

class DeployState {
  const DeployState({
    this.activity = DeployActivity.idle,
    this.artifact,
    this.events = const [],
    this.message,
    this.deviceCount = 0,
    this.progress,
    this.compilerFingerprint,
    this.compilerAvailable = true,
    this.licenseFailure = false,
  });

  final DeployActivity activity;
  final BuildArtifact? artifact;
  final List<String> events;
  final String? message;
  final int deviceCount;
  final double? progress;
  final String? compilerFingerprint;
  final bool compilerAvailable;
  final bool licenseFailure;

  bool get busy => activity != DeployActivity.idle;

  DeployState copyWith({
    DeployActivity? activity,
    BuildArtifact? artifact,
    bool clearArtifact = false,
    List<String>? events,
    String? message,
    bool clearMessage = false,
    int? deviceCount,
    double? progress,
    bool clearProgress = false,
    String? compilerFingerprint,
    bool? compilerAvailable,
    bool? licenseFailure,
  }) => DeployState(
    activity: activity ?? this.activity,
    artifact: clearArtifact ? null : artifact ?? this.artifact,
    events: events ?? this.events,
    message: clearMessage ? null : message ?? this.message,
    deviceCount: deviceCount ?? this.deviceCount,
    progress: clearProgress ? null : progress ?? this.progress,
    compilerFingerprint: compilerFingerprint ?? this.compilerFingerprint,
    compilerAvailable: compilerAvailable ?? this.compilerAvailable,
    licenseFailure: licenseFailure ?? this.licenseFailure,
  );
}

final deployControllerProvider =
    NotifierProvider<DeployController, DeployState>(DeployController.new);

class DeployController extends Notifier<DeployState> {
  late final Future<FirmwareBuilder> _builderFuture;
  late final HidFlasher _flasher;
  BuildOperation? _buildOperation;
  FlashOperation? _flashOperation;
  StreamSubscription<Object?>? _eventSubscription;
  int _prepareGeneration = 0;

  @override
  DeployState build() {
    _builderFuture = _createBuilder();
    _flasher = HidFlasher();
    ref.onDispose(cancelAll);
    return DeployState(compilerAvailable: !Platform.isAndroid);
  }

  static Future<FirmwareBuilder> _createBuilder() async {
    if (!Platform.isAndroid) return FirmwareBuilder();
    final support = await getApplicationSupportDirectory();
    final cache = await getTemporaryDirectory();
    final runtime = Directory(p.join(support.path, 'runtime'));
    await runtime.create(recursive: true);
    final client = NativeSdccClient();
    const platform = MethodChannel('cn.edu.cnu.pieblock/documents');
    final nativeInfo = await platform.invokeMapMethod<String, String>(
      'getSdccNativeInfo',
    );
    if (nativeInfo == null ||
        nativeInfo['abi'] == null ||
        nativeInfo['sha256'] == null) {
      throw StateError('无法读取 Android SDCC 原生库信息');
    }
    final resourceRoot = client.isAvailable
        ? await platform.invokeMethod<String>('prepareSdccResources')
        : null;
    return FirmwareBuilder(
      artifacts: BuildArtifactRepository(root: p.join(support.path, 'builds')),
      runtimeRoot: runtime.path,
      workRoot: p.join(cache.path, 'builds'),
      sdccBackend: NativeSdccBackend(
        resourceRoot: resourceRoot ?? p.join(runtime.path, 'sdcc-unavailable'),
        librarySha256: nativeInfo['sha256']!,
        androidAbi: nativeInfo['abi']!,
        client: client,
      ),
    );
  }

  Future<void> prepare(
    ProjectConfig config,
    CompilerKind compiler, {
    String? keilRoot,
  }) async {
    if (state.busy) return;
    final generation = ++_prepareGeneration;
    state = state.copyWith(
      activity: DeployActivity.preparing,
      clearMessage: true,
    );
    try {
      final builder = await _builderFuture;
      final code = CodeGenerator.generate(config);
      final compilerFingerprint = await builder.resolveCompilerFingerprint(
        compiler,
        keilRoot: keilRoot,
      );
      final request = BuildRequest(
        projectKind: config.kind,
        sourceCode: code,
        compiler: compiler,
        compilerFingerprint: compilerFingerprint,
        keilRoot: keilRoot,
      );
      final artifact = await builder.artifacts.findFresh(
        FirmwareBuilder.fingerprint(request),
      );
      if (generation != _prepareGeneration) return;
      state = state.copyWith(
        activity: DeployActivity.idle,
        artifact: artifact,
        clearArtifact: artifact == null,
        compilerFingerprint: compilerFingerprint,
        compilerAvailable: true,
      );
      unawaited(refreshDevices());
      unawaited(
        builder.artifacts.prune(
          protectedFingerprints: {if (artifact != null) artifact.fingerprint},
        ),
      );
    } catch (error) {
      if (generation != _prepareGeneration) return;
      state = state.copyWith(
        activity: DeployActivity.idle,
        clearArtifact: true,
        message: '$error',
        compilerAvailable: !Platform.isAndroid,
      );
    }
  }

  Future<bool> buildFirmware(
    ProjectConfig config,
    CompilerKind compiler, {
    String? keilRoot,
  }) async {
    if (state.busy) return false;
    state = state.copyWith(
      activity: DeployActivity.preparing,
      events: const [],
      clearMessage: true,
      clearProgress: true,
      licenseFailure: false,
    );
    try {
      final builder = await _builderFuture;
      final fingerprint = await builder.resolveCompilerFingerprint(
        compiler,
        keilRoot: keilRoot,
      );
      final request = BuildRequest(
        projectKind: config.kind,
        sourceCode: CodeGenerator.generate(config),
        compiler: compiler,
        compilerFingerprint: fingerprint,
        keilRoot: keilRoot,
      );
      final operation = builder.start(request);
      _buildOperation = operation;
      state = state.copyWith(
        activity: DeployActivity.building,
        clearArtifact: true,
        compilerFingerprint: fingerprint,
        compilerAvailable: true,
      );
      _eventSubscription = operation.events.listen((event) {
        final progress =
            event.current == null || event.total == null || event.total == 0
            ? null
            : event.current! / event.total!;
        state = state.copyWith(
          events: [...state.events, event.message].takeLast(500),
          progress: progress,
          clearProgress: progress == null,
        );
      });
      final result = await operation.result;
      await _eventSubscription?.cancel();
      _eventSubscription = null;
      _buildOperation = null;
      state = state.copyWith(
        activity: DeployActivity.idle,
        artifact: result.artifact,
        clearArtifact: result.artifact == null,
        message: result.success
            ? '编译成功，可以烧录或导出 HEX'
            : result.canceled
            ? '已取消编译'
            : '编译失败，请查看构建日志',
        clearProgress: true,
        licenseFailure: result.licenseFailure,
      );
      return result.success;
    } catch (error) {
      _buildOperation = null;
      state = state.copyWith(
        activity: DeployActivity.idle,
        clearArtifact: true,
        message: '编译失败：$error',
        compilerAvailable: !Platform.isAndroid,
        clearProgress: true,
      );
      return false;
    }
  }

  Future<bool> flashFirmware() async {
    final artifact = state.artifact;
    if (artifact == null || state.busy) return false;
    state = state.copyWith(
      activity: DeployActivity.flashing,
      clearMessage: true,
      progress: 0,
    );
    final operation = _flasher.start(
      hexPath: artifact.hexPath,
      expectedSha256: artifact.hexSha256,
    );
    _flashOperation = operation;
    _eventSubscription = operation.events.listen((event) {
      final progress =
          event.current == null || event.total == null || event.total == 0
          ? state.progress
          : event.current! / event.total!;
      state = state.copyWith(
        events: [...state.events, event.message].takeLast(500),
        progress: progress,
      );
    });
    final result = await operation.result;
    await _eventSubscription?.cancel();
    _eventSubscription = null;
    _flashOperation = null;
    if (result.success) {
      final builder = await _builderFuture;
      await builder.artifacts.markFlashed(artifact);
    }
    state = state.copyWith(
      activity: DeployActivity.idle,
      artifact: result.success
          ? artifact.copyWith(lastFlashedAt: DateTime.now())
          : artifact,
      message: result.message,
      clearProgress: true,
      deviceCount: result.success ? 0 : state.deviceCount,
    );
    return result.success;
  }

  Future<void> refreshDevices() async {
    if (state.busy) return;
    final count = await _flasher.detectDeviceCount();
    if (!state.busy) state = state.copyWith(deviceCount: count);
  }

  Future<bool> exportHex(String path) async {
    final artifact = state.artifact;
    if (artifact == null) return false;
    final builder = await _builderFuture;
    final fresh = await builder.artifacts.findFresh(
      BuildFingerprint(
        value: artifact.fingerprint,
        sourceHash: artifact.sourceSha256,
      ),
    );
    if (fresh == null) {
      state = state.copyWith(
        clearArtifact: true,
        message: 'HEX 已丢失、被修改或布局无效，请重新编译',
      );
      return false;
    }
    final destination = path.toLowerCase().endsWith('.hex')
        ? path
        : '$path.hex';
    final temporary = '$destination.pieblock.tmp';
    await File(fresh.hexPath).copy(temporary);
    final target = File(destination);
    if (await target.exists()) await target.delete();
    await File(temporary).rename(destination);
    state = state.copyWith(message: 'HEX 已导出到 $destination');
    return true;
  }

  Future<bool> exportHexOnAndroid() async {
    final artifact = state.artifact;
    if (!Platform.isAndroid || artifact == null) return false;
    final builder = await _builderFuture;
    final fresh = await builder.artifacts.findFresh(
      BuildFingerprint(
        value: artifact.fingerprint,
        sourceHash: artifact.sourceSha256,
      ),
    );
    if (fresh == null) {
      state = state.copyWith(
        clearArtifact: true,
        message: 'HEX 已丢失、被修改或布局无效，请重新编译',
      );
      return false;
    }
    try {
      final saved = await const MethodChannel('cn.edu.cnu.pieblock/documents')
          .invokeMethod<bool>('saveHex', {
            'suggestedName': 'firmware.hex',
            'bytes': await File(fresh.hexPath).readAsBytes(),
          });
      state = state.copyWith(message: saved == true ? 'HEX 已导出' : '已取消导出');
      return saved == true;
    } on PlatformException catch (error) {
      state = state.copyWith(
        message: 'HEX 导出失败：${error.message ?? error.code}',
      );
      return false;
    }
  }

  void cancelAll() {
    _buildOperation?.cancel();
    _flashOperation?.cancel();
    _buildOperation = null;
    _flashOperation = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    unawaited(_builderFuture.then((builder) => builder.cancel()));
  }
}

extension<T> on Iterable<T> {
  List<T> takeLast(int count) {
    final values = toList();
    return values.length <= count
        ? values
        : values.sublist(values.length - count);
  }
}

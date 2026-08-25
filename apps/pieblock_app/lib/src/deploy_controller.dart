import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_hid/pieblock_hid.dart';
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
    this.licenseFailure = false,
  });

  final DeployActivity activity;
  final BuildArtifact? artifact;
  final List<String> events;
  final String? message;
  final int deviceCount;
  final double? progress;
  final String? compilerFingerprint;
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
    bool? licenseFailure,
  }) => DeployState(
    activity: activity ?? this.activity,
    artifact: clearArtifact ? null : artifact ?? this.artifact,
    events: events ?? this.events,
    message: clearMessage ? null : message ?? this.message,
    deviceCount: deviceCount ?? this.deviceCount,
    progress: clearProgress ? null : progress ?? this.progress,
    compilerFingerprint: compilerFingerprint ?? this.compilerFingerprint,
    licenseFailure: licenseFailure ?? this.licenseFailure,
  );
}

final deployControllerProvider =
    NotifierProvider<DeployController, DeployState>(DeployController.new);

class DeployController extends Notifier<DeployState> {
  late final FirmwareBuilder _builder;
  late final HidFlasher _flasher;
  BuildOperation? _buildOperation;
  FlashOperation? _flashOperation;
  StreamSubscription<Object?>? _eventSubscription;
  int _prepareGeneration = 0;

  @override
  DeployState build() {
    _builder = FirmwareBuilder();
    _flasher = HidFlasher();
    ref.onDispose(cancelAll);
    return const DeployState();
  }

  Future<void> prepare(
    RobotConfig config,
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
      final code = CodeGenerator.generate(config);
      final compilerFingerprint = await _builder.resolveCompilerFingerprint(
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
      final artifact = await _builder.artifacts.findFresh(
        FirmwareBuilder.fingerprint(request),
      );
      if (generation != _prepareGeneration) return;
      state = state.copyWith(
        activity: DeployActivity.idle,
        artifact: artifact,
        clearArtifact: artifact == null,
        compilerFingerprint: compilerFingerprint,
      );
      unawaited(refreshDevices());
      unawaited(
        _builder.artifacts.prune(
          protectedFingerprints: {if (artifact != null) artifact.fingerprint},
        ),
      );
    } catch (error) {
      if (generation != _prepareGeneration) return;
      state = state.copyWith(
        activity: DeployActivity.idle,
        clearArtifact: true,
        message: '$error',
      );
    }
  }

  Future<bool> buildFirmware(
    RobotConfig config,
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
      final fingerprint = await _builder.resolveCompilerFingerprint(
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
      final operation = _builder.start(request);
      _buildOperation = operation;
      state = state.copyWith(
        activity: DeployActivity.building,
        clearArtifact: true,
        compilerFingerprint: fingerprint,
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
    if (result.success) await _builder.artifacts.markFlashed(artifact);
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
    final fresh = await _builder.artifacts.findFresh(
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

  void cancelAll() {
    _buildOperation?.cancel();
    _flashOperation?.cancel();
    _buildOperation = null;
    _flashOperation = null;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
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

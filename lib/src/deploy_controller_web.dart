import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

/// 浏览器里既没有本地编译器，也没有 USB-HID。
///
/// 编译与烧录整条链路用这个桩顶上：接口与桌面版一致，任何调用都只是
/// 把「去桌面版做」这句话写进状态，好在向导页（Web 上会整块换成引导页）
/// 万一被调用时不会崩。真正切掉的是两个 dart:ffi 包——它们只被桌面版的
/// 部署控制器引用，这一刀之后 Web 构建就干净了。
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
  static const _message = '网页版不提供编译与烧录，请在桌面版完成';

  @override
  DeployState build() => const DeployState(compilerAvailable: false);

  Future<void> prepare(
    ProjectConfig config,
    CompilerKind compiler, {
    String? keilRoot,
  }) async {
    state = state.copyWith(message: _message);
  }

  Future<bool> buildFirmware(
    ProjectConfig config,
    CompilerKind compiler, {
    String? keilRoot,
  }) async {
    state = state.copyWith(message: _message);
    return false;
  }

  Future<bool> flashFirmware() async {
    state = state.copyWith(message: _message);
    return false;
  }

  Future<void> refreshDevices() async {}

  Future<bool> exportHex(String path) async => false;

  Future<bool> exportHexOnAndroid() async => false;

  void cancelAll() {}
}

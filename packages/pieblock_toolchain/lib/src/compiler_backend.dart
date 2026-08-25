import 'models.dart';

typedef BuildEventSink = void Function(
  BuildStage stage,
  String message, {
  BuildEventLevel level,
  int? current,
  int? total,
});

class CompilerBackendResult {
  const CompilerBackendResult({
    required this.success,
    this.canceled = false,
    this.exitCode,
    this.hexPath,
    this.mapPath,
    this.warningCount = 0,
    this.message,
  });

  final bool success;
  final bool canceled;
  final int? exitCode;
  final String? hexPath;
  final String? mapPath;
  final int warningCount;
  final String? message;
}

/// Platform implementation for SDCC builds that cannot use a child process.
///
/// Windows keeps the existing process backend. Android injects an
/// implementation backed by `libpieblock_sdcc_native.so`.
abstract interface class SdccCompilerBackend {
  Future<String> resolveFingerprint();

  Future<CompilerBackendResult> build(
    BuildRequest request,
    String workDirectory,
    BuildEventSink emit,
  );

  void cancel();
}

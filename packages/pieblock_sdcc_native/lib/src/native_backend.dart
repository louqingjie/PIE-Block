import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'native_client.dart';

/// Diagnostic-only direct FFI backend.
///
/// Production Android builds must use [AndroidSdccServiceBackend] so every
/// translation unit gets a fresh worker process.
class NativeSdccBackend implements SdccCompilerBackend {
  NativeSdccBackend({
    required this.resourceRoot,
    required this.librarySha256,
    required this.androidAbi,
    NativeSdccClient? client,
  }) : _client = client ?? NativeSdccClient();

  final String resourceRoot;
  final String librarySha256;
  final String androidAbi;
  final NativeSdccClient _client;

  @override
  Future<String> resolveFingerprint() async {
    if (!_client.isAvailable) {
      throw UnsupportedError('Android SDCC 单阶段原生能力不可用');
    }
    return '${_client.fingerprint};direct-diagnostic-only:1';
  }

  @override
  Future<CompilerBackendResult> build(
    BuildRequest request,
    String workDirectory,
    BuildEventSink emit,
  ) async => const CompilerBackendResult(
    success: false,
    message: '完整 Android 构建必须通过多进程编译服务执行',
  );

  @override
  void cancel() {}
}

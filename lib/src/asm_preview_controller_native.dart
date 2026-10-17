import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'asm_preview_state.dart';
import 'deploy_controller_native.dart';

export 'asm_preview_state.dart';

final asmPreviewControllerProvider =
    NotifierProvider<AsmPreviewController, AsmPreviewState>(
      AsmPreviewController.new,
    );

/// 「生成代码」页的汇编栏：用户点「汇编」时把生成的 main.c 交给内置 SDCC
/// **完整构建一次**（编译全部源文件 + 链接，链接器才会产出带机器码与真实
/// 地址的 `main.rst`），按生成的 C 文本缓存，配置没变就不再编译。
///
/// 这里固定用内置 SDCC，与烧录页选的编译器无关；构建结果会照常进入构建
/// 缓存，因此随后到烧录页通常不必重新编译。
class AsmPreviewController extends Notifier<AsmPreviewState> {
  Future<FirmwareBuilder>? _builderFuture;
  int _generation = 0;

  @override
  AsmPreviewState build() => const AsmPreviewState();

  /// 切到「汇编」时调用：源码没变且已编译过就直接复用上次结果。
  Future<void> compile(ProjectConfig config) async {
    if (state.compiling) return;
    final code = _generate(config);
    if (code == null) return;
    if (state.listing != null && state.sourceCode == code) return;
    await _build(config.kind, code);
  }

  /// 「重新编译」按钮与失败重试用：忽略缓存。
  Future<void> recompile(ProjectConfig config) async {
    if (state.compiling) return;
    final code = _generate(config);
    if (code == null) return;
    await _build(config.kind, code);
  }

  String? _generate(ProjectConfig config) {
    try {
      return CodeGenerator.generate(config);
    } catch (error) {
      state = AsmPreviewState(
        activity: AsmPreviewActivity.failed,
        message: '$error',
      );
      return null;
    }
  }

  Future<void> _build(ProjectKind kind, String code) async {
    final generation = ++_generation;
    state = AsmPreviewState(
      activity: AsmPreviewActivity.compiling,
      sourceCode: code,
      progress: '正在准备内置 SDCC C251 工具链…',
    );
    if (Platform.isAndroid) {
      state = AsmPreviewState(
        activity: AsmPreviewActivity.failed,
        sourceCode: code,
        message: 'Android 版暂不提供汇编列表，请在桌面版查看',
      );
      return;
    }
    try {
      final builder = await (_builderFuture ??= createDesktopFirmwareBuilder());
      final request = BuildRequest(
        projectKind: kind,
        sourceCode: code,
        compiler: CompilerKind.sdcc,
        compilerFingerprint: await builder.resolveCompilerFingerprint(
          CompilerKind.sdcc,
        ),
      );
      final operation = builder.start(request);
      final events = operation.events.listen((event) {
        if (generation != _generation) return;
        state = AsmPreviewState(
          activity: AsmPreviewActivity.compiling,
          sourceCode: code,
          progress: event.message,
        );
      });
      final result = await operation.result;
      await events.cancel();
      if (generation != _generation) return;
      final listing = result.listing;
      if (!result.success || listing == null) {
        state = AsmPreviewState(
          activity: AsmPreviewActivity.failed,
          sourceCode: code,
          message: result.success
              ? 'SDCC 未产出列表文件（main.rst），请重试'
              : '构建失败：${_lastLogLine(result.log)}',
        );
        return;
      }
      state = AsmPreviewState(
        activity: AsmPreviewActivity.ready,
        sourceCode: code,
        listing: listing,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = AsmPreviewState(
        activity: AsmPreviewActivity.failed,
        sourceCode: code,
        message: '$error',
      );
    }
  }

  /// 失败时只把日志最后一行非空内容带进提示，完整日志在烧录页的编译日志里。
  String _lastLogLine(String log) {
    final lines = log
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    return lines.isEmpty ? '请查看编译日志' : lines.last;
  }
}

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

/// 「生成代码」页的 C/汇编对照：进入页面时把生成的 main.c 交给内置 SDCC
/// 编译成汇编，按源码文本缓存，配置没变就不重复编译。
class AsmPreviewController extends Notifier<AsmPreviewState> {
  Future<FirmwareBuilder>? _builderFuture;
  int _generation = 0;

  @override
  AsmPreviewState build() => const AsmPreviewState();

  /// 进入页面时调用：命中缓存直接复用上次结果。
  Future<void> ensure(ProjectConfig config) async {
    if (state.compiling) return;
    final code = _generate(config);
    if (code == null) return;
    if (state.listing != null && state.sourceCode == code) return;
    await _compile(config.kind, code);
  }

  /// 「重新编译」按钮与失败重试用：忽略缓存。
  Future<void> recompile(ProjectConfig config) async {
    if (state.compiling) return;
    final code = _generate(config);
    if (code == null) return;
    await _compile(config.kind, code);
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

  Future<void> _compile(ProjectKind kind, String code) async {
    final generation = ++_generation;
    state = AsmPreviewState(
      activity: AsmPreviewActivity.compiling,
      sourceCode: code,
    );
    if (Platform.isAndroid) {
      state = AsmPreviewState(
        activity: AsmPreviewActivity.failed,
        sourceCode: code,
        message: 'Android 版暂不提供汇编对照，请在桌面版查看',
      );
      return;
    }
    try {
      final builder = await (_builderFuture ??= createDesktopFirmwareBuilder());
      final result = await builder.previewAssembly(
        projectKind: kind,
        sourceCode: code,
      );
      if (generation != _generation) return;
      final assembly = result.assembly;
      if (!result.success || assembly == null) {
        state = AsmPreviewState(
          activity: AsmPreviewActivity.failed,
          sourceCode: code,
          message: result.message ?? '汇编编译失败，请查看编译日志',
        );
        return;
      }
      state = AsmPreviewState(
        activity: AsmPreviewActivity.ready,
        sourceCode: code,
        cLineCount: '\n'.allMatches(code).length + 1,
        listing: AsmListing.parse(assembly),
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
}

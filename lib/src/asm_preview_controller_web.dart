import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'asm_preview_state.dart';

export 'asm_preview_state.dart';

/// 网页版既不能跑本地编译器，也就没有汇编对照——接口与桌面版一致，
/// 任何调用都只是把「去桌面版看」写进状态，页面据此降级为只有 C 栏。
final asmPreviewControllerProvider =
    NotifierProvider<AsmPreviewController, AsmPreviewState>(
      AsmPreviewController.new,
    );

class AsmPreviewController extends Notifier<AsmPreviewState> {
  static const _message = '网页版不提供汇编对照，请在桌面版查看';

  @override
  AsmPreviewState build() => const AsmPreviewState();

  Future<void> ensure(ProjectConfig config) async {
    state = const AsmPreviewState(
      activity: AsmPreviewActivity.failed,
      message: _message,
    );
  }

  Future<void> recompile(ProjectConfig config) async {
    state = const AsmPreviewState(
      activity: AsmPreviewActivity.failed,
      message: _message,
    );
  }
}

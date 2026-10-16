import 'package:pieblock_toolchain/asm_listing.dart';

/// 汇编对照视图的编译状态。桌面版与 Web 桩共用同一份定义，
/// 两侧只在控制器实现上分叉（见 asm_preview_controller.dart 的条件导入）。
enum AsmPreviewActivity { idle, compiling, ready, failed }

class AsmPreviewState {
  const AsmPreviewState({
    this.activity = AsmPreviewActivity.idle,
    this.listing,
    this.sourceCode,
    this.cLineCount = 0,
    this.message,
  });

  final AsmPreviewActivity activity;
  final AsmListing? listing;

  /// 上次编译对应的 C 源码，用于「配置没变就不重复编译」的缓存判断。
  final String? sourceCode;
  final int cLineCount;
  final String? message;

  bool get compiling => activity == AsmPreviewActivity.compiling;

  bool get ready => activity == AsmPreviewActivity.ready && listing != null;

  /// 对照视图标题下的说明：覆盖率即「能生成汇编的 C 行」占比；
  /// 两侧逐行严格对齐、较短的一侧补空行，行号列各自独立。
  String get coverageText {
    final value = listing;
    if (value == null || cLineCount == 0) return '汇编由内置 SDCC C251 生成';
    return '汇编由内置 SDCC C251 生成 · 覆盖 ${value.mappedCLineCount}/$cLineCount 行 C 代码'
        ' · 两侧逐行对齐、多出的部分补空行'
        '（左栏为 C 行号、右栏为汇编行号，补空行的行留空；'
        '预处理、注释与纯声明不产生汇编）';
  }
}

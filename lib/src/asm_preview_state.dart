/// 「生成代码」页汇编栏的编译状态。桌面版与 Web 桩共用同一份定义，
/// 两侧只在控制器实现上分叉（见 asm_preview_controller.dart 的条件导入）。
enum AsmPreviewActivity { idle, compiling, ready, failed }

class AsmPreviewState {
  const AsmPreviewState({
    this.activity = AsmPreviewActivity.idle,
    this.listing,
    this.sourceCode,
    this.message,
    this.progress,
  });

  final AsmPreviewActivity activity;

  /// 链接后产出的列表文件（`main_<序号>.rst`）原文：每行带地址、机器码、
  /// 指令周期与 asm 行号，C 源码以 `; main.c:66: …` 锚点插在对应位置。
  final String? listing;

  /// 上次编译对应的 C 源码，用于「配置没变就不重复编译」的缓存判断。
  final String? sourceCode;

  /// 失败或降级时的说明。
  final String? message;

  /// 构建阶段文案（准备工具链 / 编译 x/y / 链接…），编译期间给全屏遮罩显示。
  final String? progress;

  bool get compiling => activity == AsmPreviewActivity.compiling;

  bool get ready => activity == AsmPreviewActivity.ready && listing != null;
}

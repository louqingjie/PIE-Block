import 'package:material_ui/material_ui.dart';

import 'app_theme.dart';

/// 应用统一的 AlertDialog。
///
/// M3 里对话框容器是 surfaceContainerHigh，与 filled 文本框的填充
/// surfaceContainerHighest 只差 2 个色调步进，输入框在对话框里几乎
/// 不可见；M3 对这种场景的标准答案是并列的 outlined 文本框变体
/// （静止 outline 描边、聚焦 primary 2dp 描边），在任何容器上都可读。
/// 含输入框的对话框一律用 [AppDialog]，纯文本对话框可直接用 AlertDialog。
class AppDialog extends StatelessWidget {
  const AppDialog({super.key, this.title, this.content, this.actions});

  final Widget? title;
  final Widget? content;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(
        inputDecorationTheme: InputDecorationTheme(
          filled: false,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          border: OutlineInputBorder(borderRadius: AppRadius.md),
          enabledBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: scheme.outline),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: scheme.primary, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: scheme.error, width: 1.5),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: AppRadius.md,
            borderSide: BorderSide(color: scheme.error, width: 2),
          ),
        ),
      ),
      child: AlertDialog(title: title, content: content, actions: actions),
    );
  }
}

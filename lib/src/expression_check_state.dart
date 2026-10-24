/// 表达式编译检查状态：桌面端用内置 SDCC 完整构建一次生成代码。
enum ExpressionCheckActivity {
  idle,
  checking,
  passed,
  failed,
  unsupported,
  noExpressions,
}

class ExpressionCheckIssue {
  const ExpressionCheckIssue({
    required this.fieldPath,
    required this.line,
    required this.message,
  });
  final String fieldPath;
  final int line;
  final String message;
}

class ExpressionCheckState {
  const ExpressionCheckState({
    this.activity = ExpressionCheckActivity.idle,
    this.message,
    this.progress,
    this.issues = const [],
  });

  final ExpressionCheckActivity activity;
  final String? message;
  final String? progress;
  final List<ExpressionCheckIssue> issues;

  bool get busy => activity == ExpressionCheckActivity.checking;
  bool get hasIssues => issues.isNotEmpty;

  ExpressionCheckState copyWith({
    ExpressionCheckActivity? activity,
    String? message,
    String? progress,
    List<ExpressionCheckIssue>? issues,
  }) => ExpressionCheckState(
    activity: activity ?? this.activity,
    message: message ?? this.message,
    progress: progress ?? this.progress,
    issues: issues ?? this.issues,
  );
}

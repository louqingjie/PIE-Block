/// 教材第 5 章三个示例工程（`book/examples/*.pieproj`）的共享小库。
///
/// 示例文件本身必须能被当前格式版本解析、通过 `ProjectValidator` 的零 error
/// 校验，并能直接生成固件源码。`tool/generate_book_examples.dart` 与
/// `test/book_examples_test.dart` 都从这里加载，避免路径、校验与源码提取逻辑
/// 在两处各写一套后悄悄漂移。
///
/// 用法：`dart run tool/generate_book_examples.dart`
library;

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

/// 示例工程所在目录，相对仓库根目录（仓库根目录即 Flutter 应用根）。
const bookExamplesDirectory = 'book/examples';

/// 一个教材示例工程的静态说明。
class BookExample {
  const BookExample({
    required this.name,
    required this.title,
    required this.summary,
    required this.expectedHelpers,
  });

  /// 文件名主干，如 `mecanum4`。
  final String name;

  /// 教材里使用的中文标题。
  final String title;

  /// 一句话说明构型与控制律，供工具摘要输出使用。
  final String summary;

  /// 生成代码中必须出现的表达式 helper 名（不带括号），如 `pb_atan2`。
  ///
  /// 这些 helper 由 `ExpressionRuntime` 按实际用到的运算按需生成；缺一个就说明
  /// 示例用到的函数在生成链路上丢了。
  final List<String> expectedHelpers;

  String get projectPath => '$bookExamplesDirectory/$name.pieproj';

  String get cFileName => '$name.c';
}

/// 第 5 章的三个示例，顺序与教材小节一致。
const bookExamples = <BookExample>[
  BookExample(
    name: 'mecanum4',
    title: '四轮麦轮工程',
    summary: 'P74–P77 四路平滑电机，整数麦轮解算 (vx±vy)*10000/2047',
    expectedHelpers: ['pb_div_i', 'pb_clamp_i'],
  ),
  BookExample(
    name: 'omni3',
    title: '三轮全向工程',
    summary: 'P74–P76 三路平滑电机，按 120° 布置做全向解算',
    expectedHelpers: ['pb_div_i', 'pb_div_f', 'pb_clamp_i', 'pb_clamp_f'],
  ),
  BookExample(
    name: 'arm2dof',
    title: '二自由度机械臂工程',
    summary: 'MP03/MP74 主舵机，按几何逆解算关节角并换算舵机角度',
    expectedHelpers: [
      'pb_max_f',
      'pb_min_f',
      'pb_sqrt',
      'pb_atan2',
      'pb_clamp_f',
      'pb_servo_duty',
    ],
  ),
];

/// 加载并校验后的示例工程。
class BookExampleProject {
  BookExampleProject({
    required this.example,
    required this.document,
    required this.issues,
  }) : program = _generateOrNull(document, issues);

  final BookExample example;
  final ProjectDocument document;
  final List<ValidationIssue> issues;

  /// 生成结果；配置有 error 时为 null。
  final GeneratedProgram? program;

  /// 有 error 时 `CodeGenerator.generate` 会直接抛 StateError 并把第一条错误藏
  /// 起来；工具需要逐条打印校验结果，所以这里返回 null 由调用方决定是否继续。
  static GeneratedProgram? _generateOrNull(
    ProjectDocument document,
    List<ValidationIssue> issues,
  ) {
    if (issues.any((issue) => issue.severity == IssueSeverity.error)) {
      return null;
    }
    return CodeGenerator.generateProgram(document.config);
  }

  EngineerConfig get config {
    final value = document.config;
    if (value is! EngineerConfig) {
      throw StateError('${example.projectPath} 不是工程项目');
    }
    return value;
  }

  List<ValidationIssue> get errors => issues
      .where((issue) => issue.severity == IssueSeverity.error)
      .toList(growable: false);

  List<ValidationIssue> get warnings => issues
      .where((issue) => issue.severity == IssueSeverity.warning)
      .toList(growable: false);
}

/// 读取并校验一个示例工程；生成失败与否通过 [BookExampleProject.program] 体现。
BookExampleProject loadBookExample(BookExample example) {
  final raw = File(example.projectPath).readAsStringSync();
  final decoded = jsonDecode(raw);
  if (decoded is! Map) {
    throw FormatException('${example.projectPath} 不是 JSON 对象');
  }
  final document = ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
  return BookExampleProject(
    example: example,
    document: document,
    issues: ProjectValidator.validate(document.config),
  );
}

/// 按教材顺序加载全部示例。
List<BookExampleProject> loadBookExamples() =>
    bookExamples.map(loadBookExample).toList(growable: false);

/// 表达式行标记，形如 ` /*@expr:modes.0.actions.2.expression*/`。
///
/// 标记是桌面端把 SDCC 报错回填到具体动作行的锚点，编译前必须剥离，否则
/// 教材里贴出来的 C 代码会带着一串与业务无关的注释。
final _expressionMarker = RegExp(r' /\*@expr:[^*]+\*/');

/// 去掉生成源码里的表达式行标记。
///
/// 只删除行尾注释，不增删换行：剥离前后行号一一对应，便于对照教材正文。
String stripExpressionMarkers(String source) =>
    source.replaceAll(_expressionMarker, '');

/// 提取生成源码中的 `RunMode1` 函数（含函数签名与收尾大括号）。
///
/// 教材正文只排版每个示例的这一个函数，其余框架代码不必占版面。
String extractRunMode1(String source) {
  const signature = 'void RunMode1(void)';
  final start = source.indexOf(signature);
  if (start < 0) {
    throw StateError('生成源码中没有 RunMode1，示例应只配置一个模式');
  }
  final end = source.indexOf('\n}', start);
  if (end < 0) {
    throw StateError('RunMode1 函数体不完整');
  }
  return source.substring(start, end + 2);
}

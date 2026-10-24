/// 校验 `book/examples/` 下的三个教材示例工程，并把生成的 C 落到
/// `build/book_examples/`，供教材排版、SDCC 编译验证与人工对照使用。
///
/// 每个示例都会先过 `ProjectValidator`：有任何 error 就跳过该示例的代码生成，
/// 最后以非零退出码结束，避免「教材示例发布出去却打不开代码页」。
///
/// 用法：`dart run tool/generate_book_examples.dart`
library;

import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

import 'book_examples.dart';

const _outputDir = 'build/book_examples';

/// `--help` 里给出的 SDCC 编译命令模板（使用应用构建产物里的内置工具链）。
const _sdccHint = '''
SDCC 编译验证（在仓库根目录执行）：

  ROOT=build/linux/x64/debug/bundle/data/pieblock_runtime
  FW=\$ROOT/stc32g_sdcc
  \$ROOT/sdcc-toolchain/bin/sdcc -mmcs251 --model-large --stack-auto \\
    --opt-code-size --constseg CSEG -c build/book_examples/mecanum4.c \\
    -I\$ROOT/sdcc-toolchain/include -I\$ROOT/sdcc-toolchain/include/mcs51 \\
    -I\$FW/include -I\$FW/startup -I\$FW/libraries/drivers/inc \\
    -I\$FW/libraries/boards/inc -I\$FW/projects/ROBOMASTER_ENGINEER/inc \\
    -o build/book_examples/mecanum4.rel''';

void main(List<String> args) {
  if (args.contains('--help') || args.contains('-h')) {
    stdout.writeln('''
用法：dart run tool/generate_book_examples.dart

依次校验 ${bookExamples.length} 个教材示例工程，把生成的 C 源码（已剥离
/*@expr:...*/ 行号标记）写入 $_outputDir/，并打印校验摘要与 RunMode1 摘录。
有 error 时以退出码 1 结束。

$_sdccHint''');
    return;
  }
  final output = Directory(_outputDir);
  output.createSync(recursive: true);

  var failed = false;
  for (final example in bookExamples) {
    stdout.writeln('== ${example.title}（${example.projectPath}）');
    stdout.writeln('   ${example.summary}');
    final project = loadBookExample(example);
    final errors = project.errors, warnings = project.warnings;
    stdout.writeln('   校验：${errors.length} error / ${warnings.length} warning');
    for (final issue in project.issues) {
      final mark = issue.severity == IssueSeverity.error ? 'ERROR' : 'warn ';
      stdout.writeln('     [$mark] ${issue.fieldPath}: ${issue.message}');
    }
    final program = project.program;
    if (program == null) {
      failed = true;
      stdout.writeln('   跳过代码生成：配置仍有 error。\n');
      continue;
    }
    final source = stripExpressionMarkers(program.source);
    final file = File('$_outputDir/${example.cFileName}');
    file.writeAsStringSync(source);
    final config = project.config;
    final actions = config.modes.first.actions.length;
    stdout.writeln(
      '   已生成 ${file.path}：${source.length} 字符，'
      '$actions 行动作，'
      '${program.expressionLineFields.length} 条表达式行',
    );
    stdout.writeln('   --- RunMode1 ---');
    for (final line in extractRunMode1(source).split('\n')) {
      stdout.writeln('   $line');
    }
    stdout.writeln('');
  }

  if (failed) {
    stderr.writeln('存在 error 的示例未生成 C 源码，请先修复 .pieproj。');
    exitCode = 1;
    return;
  }
  stdout.writeln('全部示例校验通过，C 源码位于 $_outputDir/。');
  stdout.writeln(_sdccHint);
}

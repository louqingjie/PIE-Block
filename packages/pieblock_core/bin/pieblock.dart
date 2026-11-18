// PIE-Block 命令行入口：把核心能力（读工程、校验、生成代码）暴露给脚本与 AI Agent。
//
// 设计约定（与桌面端保持同一套语义）：
//   - stdout 只输出机器可读数据：validate 为 JSON，codegen 为纯 C 源码。
//   - stderr 只输出人类可读的进度与错误。
//   - 退出码：0 成功 / 1 参数错误 / 2 校验失败 / 3 IO 或格式错误 / 4 生成失败 /
//     5 内部错误（兜底，不应发生）。
//   - 不触碰存档写回，不编译、不烧录（这两个动作代价是硬件，仅桌面 GUI 提供）。
//
// 用法：
//   dart run packages/pieblock_core/bin/pieblock.dart validate <工程.pieproj>
//   dart run packages/pieblock_core/bin/pieblock.dart codegen  <工程.pieproj> [--out main.c]
//   dart run packages/pieblock_core/bin/pieblock.dart describe
//   dart run packages/pieblock_core/bin/pieblock.dart --help

import 'dart:convert';
import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';

const int exitUsage = 1;
const int exitInvalid = 2;
const int exitIo = 3;
const int exitGenerate = 4;
const int exitInternal = 5;
const String toolName = 'pieblock-cli';

void main(List<String> args) {
  try {
    _run(args);
  } catch (error, stack) {
    // 兜底：任何未预期的异常都必须落回契约里的退出码。CLI 的调用方是脚本和
    // AI Agent，它们只会把 Dart 栈原样转述给用户，不会从栈里读出有效信息。
    if (Platform.environment['PIEBLOCK_DEBUG'] == '1') {
      stderr.writeln('$error\n$stack');
    } else {
      stderr.writeln('内部错误：$error');
      stderr.writeln('设置 PIEBLOCK_DEBUG=1 可查看调用栈。');
    }
    exitCode = exitInternal;
  }
}

void _run(List<String> args) {
  if (args.isEmpty) {
    _usage();
    exitCode = exitUsage;
    return;
  }

  final command = args.first;
  final rest = args.sublist(1);

  switch (command) {
    case '--help':
    case '-h':
    case 'help':
      _usage();
    case 'describe':
      _describe();
    case 'validate':
      _validate(rest);
    case 'codegen':
      _codegen(rest);
    default:
      stderr.writeln('未知命令：$command，见 --help。');
      exitCode = exitUsage;
  }
}

void _usage() {
  stdout.writeln('''
$toolName — PIE-Block 工程命令行工具（只读，不编译不烧录）

用法：
  $toolName validate <工程.pieproj>          校验配置，stdout 输出 JSON
  $toolName codegen  <工程.pieproj> [--out f] 生成 main.c，stdout 输出纯 C 源码
  $toolName describe                         输出机器可读的命令契约（JSON）
  $toolName --help                           显示本帮助

输出约定：
  stdout 仅机器可读数据；stderr 仅人类可读的进度与错误。
  退出码：0 成功 / 1 参数错误 / 2 校验失败 / 3 IO或格式错误 / 4 生成失败 / 5 内部错误。
''');
}

void _describe() {
  stdout.writeln(jsonEncode({
    'name': toolName,
    'version': '1.0.0',
    'description': 'PIE-Block 工程命令行工具：只读工程、校验配置、生成代码。',
    'stdoutPolicy': '机器可读数据（validate=JSON, codegen=纯 C 源码, describe=JSON）',
    'stderrPolicy': '人类可读的进度与错误',
    'exitCodes': {
      '0': '成功',
      '1': '参数错误',
      '2': '校验失败（存在 error 级问题）',
      '3': 'IO 或格式错误（文件不存在/JSON 非法/内容结构错误/版本不兼容）',
      '4': '代码生成失败',
      '5': '内部错误（兜底；设置 PIEBLOCK_DEBUG=1 可查看调用栈）',
    },
    'commands': [
      {
        'name': 'validate',
        'usage': '$toolName validate <工程.pieproj>',
        'stdout': 'JSON: {ok, valid, project:{kind,format,sourceFormat}, '
            'counts:{errors,warnings}, issues:[{severity,kind,fieldPath,message,stepId}]}',
        'note': '无论是否有问题都以 JSON 返回；valid=false 表示存在 error。',
      },
      {
        'name': 'codegen',
        'usage': '$toolName codegen <工程.pieproj> [--out <main.c>]',
        'stdout': '纯 C 源码（可直接在 shell 里重定向到文件）',
        'stderr': '人类可读的生成摘要；失败时给出错误清单',
        'note': '配置有 error 级问题时拒绝生成（与 GUI 行为一致）。',
      },
      {
        'name': 'describe',
        'usage': '$toolName describe',
        'stdout': '本命令契约（JSON）',
      },
    ],
  }));
}

({String path, String? out}) _parseProjectArgs(List<String> args) {
  String? path;
  String? out;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--out':
        if (i + 1 >= args.length) {
          throw ArgumentError('--out 缺少取值');
        }
        out = args[++i];
      case '--help':
      case '-h':
        _usage();
        exit(0);
      default:
        if (args[i].startsWith('-')) {
          throw ArgumentError('未知参数 ${args[i]}');
        }
        if (path != null) {
          throw ArgumentError('只允许指定一个工程文件');
        }
        path = args[i];
    }
  }
  if (path == null) {
    throw ArgumentError('缺少工程文件路径');
  }
  return (path: path, out: out);
}

ProjectDocument _loadProject(String path) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('工程文件不存在：$path');
    exit(exitIo);
  }
  late final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('工程文件不是合法 JSON：$path\n${e.message}');
    exit(exitIo);
  } on IOException catch (e) {
    stderr.writeln('读取工程失败：$path\n$e');
    exit(exitIo);
  }
  if (decoded is! Map<String, Object?>) {
    stderr.writeln('工程文件内容不是 JSON 对象：$path');
    exit(exitIo);
  }
  try {
    return ProjectDocument.fromJson(decoded);
  } on FormatException catch (e) {
    stderr.writeln('工程格式错误：${e.message}');
    exit(exitIo);
  } catch (error) {
    // 结构性问题（字段类型不对、数组写成对象等）不是版本问题，模型拿到
    // Dart 类型错误只会转述给用户，这里统一收成「格式错误」。
    stderr.writeln('工程内容无法解析：$path（字段结构不符合工程格式）');
    if (Platform.environment['PIEBLOCK_DEBUG'] == '1') {
      stderr.writeln('$error');
    }
    exit(exitIo);
  }
}

void _validate(List<String> args) {
  final parsed = _parseArgsOrExit(args);
  final document = _loadProject(parsed.path);
  final issues = ProjectValidator.validate(document.config);
  final errors = issues.where((i) => i.severity == IssueSeverity.error).toList();
  final warnings =
      issues.where((i) => i.severity == IssueSeverity.warning).toList();

  stdout.writeln(jsonEncode({
    'ok': true,
    'valid': errors.isEmpty,
    'project': {
      'kind': document.kind.name,
      'format': ProjectDocument.formatVersion,
      'sourceFormat': document.sourceFormatVersion,
    },
    'counts': {
      'errors': errors.length,
      'warnings': warnings.length,
    },
    'issues': [
      for (final issue in issues)
        {
          'severity': issue.severity.name,
          'kind': issue.kind.name,
          'fieldPath': issue.fieldPath,
          'message': issue.message,
          'stepId': issue.stepId,
        },
    ],
  }));

  stderr.writeln(
    '校验完成：${document.kind.name} 工程，${errors.length} 个错误，${warnings.length} 个提醒。',
  );
  if (errors.isNotEmpty) {
    exitCode = exitInvalid;
  }
}

void _codegen(List<String> args) {
  final parsed = _parseArgsOrExit(args);
  final document = _loadProject(parsed.path);
  final issues = ProjectValidator.validate(document.config);
  final errors = issues.where((i) => i.severity == IssueSeverity.error).toList();

  if (errors.isNotEmpty) {
    stderr.writeln('配置有 ${errors.length} 个错误，不能生成代码（与 GUI 行为一致）：');
    for (final issue in errors) {
      stderr.writeln('  · [${issue.fieldPath}] ${issue.message}');
    }
    exitCode = exitInvalid;
    return;
  }

  late final String code;
  try {
    code = CodeGenerator.generate(document.config);
  } on StateError catch (e) {
    stderr.writeln('生成失败：${e.message}');
    exitCode = exitGenerate;
    return;
  } catch (error) {
    stderr.writeln('生成失败（内部错误）：$error');
    exitCode = exitGenerate;
    return;
  }

  if (parsed.out != null) {
    try {
      final outFile = File(parsed.out!);
      outFile.parent.createSync(recursive: true);
      outFile.writeAsStringSync(code);
    } on IOException catch (e) {
      stderr.writeln('写出失败：${parsed.out}\n$e');
      exitCode = exitIo;
      return;
    }
    stderr.writeln('已生成 ${code.split('\n').length} 行代码 → ${parsed.out}');
  } else {
    stdout.write(code);
    stderr.writeln(
      '已生成 ${code.split('\n').length} 行代码（${document.kind.name} 工程）。',
    );
  }
}

({String path, String? out}) _parseArgsOrExit(List<String> args) {
  try {
    return _parseProjectArgs(args);
  } on ArgumentError catch (e) {
    stderr.writeln('参数错误：${e.message}');
    stderr.writeln('用法见 --help。');
    exit(exitUsage);
  }
}

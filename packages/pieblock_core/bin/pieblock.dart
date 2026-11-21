// PIE-Block 命令行入口：把核心能力（读工程、校验、生成代码、提交改动提案）
// 暴露给脚本与 AI Agent。
//
// 设计约定（与桌面端保持同一套语义）：
//   - stdout 只输出机器可读数据：validate/propose/describe 为 JSON，codegen 为纯 C 源码。
//   - stderr 只输出人类可读的进度与错误。
//   - 退出码：0 成功 / 1 参数错误 / 2 校验失败 / 3 IO 或格式错误 / 4 生成失败 /
//     5 内部错误（兜底，不应发生）/ 6 已有待处理提案（需 --force）。
//   - 不直接改写工程：propose 只写 `<工程>.proposed` 提案文件，由用户在
//     PIE-Block 里确认后由应用写入；不编译、不烧录（代价是硬件，仅桌面 GUI 提供）。
//
// 用法：
//   dart run packages/pieblock_core/bin/pieblock.dart validate <工程.pieproj>
//   dart run packages/pieblock_core/bin/pieblock.dart codegen  <工程.pieproj> [--out main.c]
//   dart run packages/pieblock_core/bin/pieblock.dart propose  <工程.pieproj> --config <候选.pieproj>
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
const int exitConflict = 6;
const String toolName = 'pieblock-cli';
const String cliVersion = '1.1.0';

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
    case 'propose':
      _propose(rest);
    default:
      stderr.writeln('未知命令：$command，见 --help。');
      exitCode = exitUsage;
  }
}

void _usage() {
  stdout.writeln('''
$toolName — PIE-Block 工程命令行工具（只写提案，不编译不烧录）

用法：
  $toolName validate <工程.pieproj>          校验配置，stdout 输出 JSON
  $toolName codegen  <工程.pieproj> [--out f] 生成 main.c，stdout 输出纯 C 源码
  $toolName propose  <工程.pieproj> --config <候选.pieproj> [--force]
                                             生成改动提案，等待用户在 PIE-Block 确认
  $toolName describe                         输出机器可读的命令契约（JSON）
  $toolName --help                           显示本帮助

输出约定：
  stdout 仅机器可读数据；stderr 仅人类可读的进度与错误。
  退出码：0 成功 / 1 参数错误 / 2 校验失败 / 3 IO或格式错误 / 4 生成失败 /
          5 内部错误 / 6 已有待处理提案（需 --force）。
''');
}

void _describe() {
  stdout.writeln(jsonEncode({
    'name': toolName,
    'version': cliVersion,
    'release': pieblockRelease,
    'formatVersion': ProjectDocument.formatVersion,
    'description': 'PIE-Block 工程命令行工具：校验配置、生成代码、提交改动提案。',
    'stdoutPolicy':
        '机器可读数据（validate/propose/describe=JSON, codegen=纯 C 源码）',
    'stderrPolicy': '人类可读的进度与错误',
    'exitCodes': {
      '0': '成功',
      '1': '参数错误',
      '2': '校验失败（存在 error 级问题）',
      '3': 'IO 或格式错误（文件不存在/JSON 非法/内容结构错误/版本不兼容）',
      '4': '代码生成失败',
      '5': '内部错误（兜底；设置 PIEBLOCK_DEBUG=1 可查看调用栈）',
      '6': '已有待处理提案（未加 --force）',
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
        'name': 'propose',
        'usage': '$toolName propose <工程.pieproj> --config <候选.pieproj> [--force]',
        'stdout': 'JSON: {ok, proposal, changed, paths, baseSha256, createdAt}',
        'stderr': '提案摘要；失败时给出字段路径',
        'note': '只写 <工程>.proposed，不改工程；候选必须是完整 .pieproj，'
            '且不得引入新的 error 级校验问题（工程原有的错误允许保留）；'
            '应用会在用户确认后写入。已有提案时需 --force 覆盖。',
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

({String path, String config, bool force}) _parseProposalArgs(List<String> args) {
  String? path;
  String? config;
  var force = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--config':
        if (i + 1 >= args.length) {
          throw ArgumentError('--config 缺少取值');
        }
        config = args[++i];
      case '--force':
        force = true;
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
  if (config == null) {
    throw ArgumentError('缺少 --config 候选工程路径');
  }
  return (path: path, config: config, force: force);
}

/// 生成改动提案：只写 `<工程>.proposed`，不修改工程本身。
void _propose(List<String> args) {
  final parsed = _parseProposalArgsOrExit(args);
  final base = _loadProject(parsed.path);

  final proposalPath = proposalPathFor(parsed.path);
  if (File(proposalPath).existsSync() && !parsed.force) {
    stderr.writeln('已存在待确认的提案：$proposalPath');
    stderr.writeln('确认覆盖请加 --force。');
    exit(exitConflict);
  }

  late final List<int> baseBytes;
  try {
    baseBytes = File(parsed.path).readAsBytesSync();
  } on IOException catch (error) {
    stderr.writeln('读取工程失败：${parsed.path}\n$error');
    exit(exitIo);
  }
  final baseHash = sha256Hex(baseBytes);
  final candidateJson = _readJsonObject(parsed.config, label: '候选工程');

  late final ProjectProposal proposal;
  try {
    proposal = ProjectProposal.create(
      base: base,
      candidateJson: candidateJson,
      baseSha256: baseHash,
      tool: '$toolName/$cliVersion',
    );
  } on FormatException catch (error) {
    stderr.writeln('候选工程格式错误：${error.message}');
    exit(exitIo);
  } on ProposalException catch (error) {
    final structural =
        error.code == 'invalid_document' || error.code == 'unsupported_schema';
    stderr.writeln('提案被拒绝：${error.message}');
    if (error.fields.isNotEmpty) {
      stderr.writeln('涉及字段：');
      for (final field in error.fields.take(20)) {
        stderr.writeln('  · $field');
      }
      if (error.fields.length > 20) stderr.writeln('  · …');
    }
    exit(structural ? exitIo : exitInvalid);
  }

  try {
    _writeFileAtomically(proposalPath, encodeProposal(proposal));
  } on IOException catch (error) {
    stderr.writeln('写入提案失败：$proposalPath\n$error');
    exit(exitIo);
  }

  stdout.writeln(
    jsonEncode({
      'ok': true,
      'proposal': proposalPath,
      'changed': proposal.changedPaths.length,
      'paths': proposal.changedPaths,
      'baseSha256': proposal.baseSha256,
      'createdAt': proposal.createdAt.toIso8601String(),
    }),
  );
  stderr.writeln('已生成提案：$proposalPath');
  stderr.writeln(
    '共 ${proposal.changedPaths.length} 处改动，等待在 PIE-Block 中确认应用。',
  );
}

({String path, String config, bool force}) _parseProposalArgsOrExit(
  List<String> args,
) {
  try {
    return _parseProposalArgs(args);
  } on ArgumentError catch (e) {
    stderr.writeln('参数错误：${e.message}');
    stderr.writeln('用法见 --help。');
    exit(exitUsage);
  }
}

Map<String, Object?> _readJsonObject(String path, {required String label}) {
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('$label不存在：$path');
    exit(exitIo);
  }
  late final Object? decoded;
  try {
    decoded = jsonDecode(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('$label不是合法 JSON：$path\n${e.message}');
    exit(exitIo);
  } on IOException catch (e) {
    stderr.writeln('读取$label失败：$path\n$e');
    exit(exitIo);
  }
  if (decoded is! Map) {
    stderr.writeln('$label内容不是 JSON 对象：$path');
    exit(exitIo);
  }
  return Map<String, Object?>.from(decoded);
}

/// 先写临时文件再改名，避免应用轮询时读到半截提案。
void _writeFileAtomically(String path, String content) {
  final temporary = File('$path.tmp-$pid');
  temporary.writeAsStringSync(content, flush: true);
  try {
    temporary.renameSync(path);
  } on FileSystemException {
    final target = File(path);
    if (target.existsSync()) target.deleteSync();
    temporary.renameSync(path);
  }
}

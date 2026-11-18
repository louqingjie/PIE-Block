/// AI 改动提案：CLI 生成、应用确认后写入，应用始终是工程文件的唯一写者。
///
/// 设计要点：
/// - 提案是独立文件，放在工程旁边（`<工程>.proposed`），AI 永远不直接改 `.pieproj`；
/// - 提案带 `baseSha256`，应用可以判断它是否基于旧版本；
/// - 「往返核对」保证模型写下的字段值能被项目模型原样读回，避免枚举拼错被
///   静默回退成默认值；未知字段也会被拒绝；
/// - diff 只用于展示与摘要，应用会重新计算，不信任文件里的 `changedPaths`。
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'models.dart';
import 'validator.dart';

/// 提案文件格式版本。
const int proposalSchema = 1;

/// 提案文件的 `kind` 标记，用来和普通 JSON 区分。
const String proposalKind = 'pieblock-proposal';

/// 提案文件后缀：`robot.pieproj.proposed`。
const String proposalSuffix = '.proposed';

/// 应用处理完提案后写回的结果文件后缀：`robot.pieproj.proposed.result`。
const String proposalResultSuffix = '.result';

/// 工程对应的提案文件路径。
String proposalPathFor(String projectPath) => '$projectPath$proposalSuffix';

/// 工程对应的提案结果文件路径。
String proposalResultPathFor(String projectPath) =>
    '$projectPath$proposalSuffix$proposalResultSuffix';

/// 计算文件/字节的 SHA-256 十六进制摘要。
String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

final _sha256Pattern = RegExp(r'^[0-9a-f]{64}$');

/// 提案构建或解析失败。
///
/// [code] 供 CLI 映射退出码、供应用展示：
/// - `unsupported_schema` / `invalid_document`：文件结构问题；
/// - `kind_mismatch`：候选工程类型与目标工程不一致；
/// - `unroundtripped_value`：字段值无法被项目模型原样读回（拼错、类型不对等）；
/// - `invalid_config`：候选**新增**了 error 级校验问题；
/// - `empty_changes`：候选与目标没有差异。
class ProposalException implements Exception {
  const ProposalException(this.code, this.message, {this.fields = const []});

  final String code;
  final String message;

  /// 出问题的字段路径，便于 CLI 直接打印给 Agent。
  final List<String> fields;

  @override
  String toString() => message;
}

/// 一处配置改动（用于展示）。
class ProposalChange {
  const ProposalChange({
    required this.path,
    required this.before,
    required this.after,
  });

  final String path;
  final Object? before;
  final Object? after;

  Map<String, Object?> toJson() => {
    'path': path,
    'before': before,
    'after': after,
  };
}

/// 一份 AI 改动提案。
class ProjectProposal {
  const ProjectProposal({
    required this.baseSha256,
    required this.createdAt,
    required this.changedPaths,
    required this.document,
    this.tool,
  });

  /// 提案生成时工程文件内容的 SHA-256。
  final String baseSha256;
  final DateTime createdAt;

  /// 生成提案的工具标识（例如 `pieblock-cli/1.0.0`），可为空。
  final String? tool;

  /// 摘要用的改动路径；应用展示时会重新计算。
  final List<String> changedPaths;

  /// 提案建议的完整工程文档。
  final ProjectDocument document;

  Map<String, Object?> toJson() => {
    'schema': proposalSchema,
    'kind': proposalKind,
    'baseSha256': baseSha256,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (tool != null) 'tool': tool,
    'changedPaths': changedPaths,
    'document': document.toJson(),
  };

  /// 从提案文件内容还原；结构不合法时抛 [ProposalException]。
  factory ProjectProposal.fromJson(Map<String, Object?> json) {
    if (json['schema'] != proposalSchema) {
      throw ProposalException(
        'unsupported_schema',
        '提案格式版本 ${json['schema']} 不受支持（本版本支持 $proposalSchema）',
      );
    }
    if (json['kind'] != proposalKind) {
      throw const ProposalException('invalid_document', '不是 PIE-Block 改动提案文件');
    }
    final base = json['baseSha256'];
    if (base is! String || !_sha256Pattern.hasMatch(base)) {
      throw const ProposalException('invalid_document', '提案缺少合法的 baseSha256');
    }
    final rawDocument = json['document'];
    if (rawDocument is! Map) {
      throw const ProposalException('invalid_document', '提案缺少 document 对象');
    }
    final document = _parseDocument(Map<String, Object?>.from(rawDocument));
    return ProjectProposal(
      baseSha256: base,
      createdAt:
          DateTime.tryParse(json['createdAt']?.toString() ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      tool: json['tool']?.toString(),
      changedPaths: [
        for (final path in (json['changedPaths'] as List? ?? const []))
          if (path is String) path,
      ],
      document: document,
    );
  }

  /// 用候选文档构建提案。
  ///
  /// [candidateJson] 必须是完整的 `.pieproj` JSON；[baseSha256] 是目标工程
  /// 文件字节的 SHA-256。失败时抛 [ProposalException] 或 [FormatException]
  /// （候选文件本身无法解析时）。
  static ProjectProposal create({
    required ProjectDocument base,
    required Map<String, Object?> candidateJson,
    required String baseSha256,
    String? tool,
    DateTime? now,
  }) {
    final candidate = _parseDocument(candidateJson);
    if (candidate.kind != base.kind) {
      throw ProposalException(
        'kind_mismatch',
        '候选工程类型（${candidate.kind.name}）与目标工程（${base.kind.name}）不一致',
      );
    }

    final rawConfig = candidateJson['config'];
    if (rawConfig is! Map) {
      throw const ProposalException('invalid_document', '候选工程缺少 config 对象');
    }
    final fields = findUnroundtrippedFields(
      Map<String, Object?>.from(rawConfig),
      candidate.config.toJson(),
    );
    if (fields.isNotEmpty) {
      throw ProposalException(
        'unroundtripped_value',
        '以下字段的取值无法被项目模型接受（拼写错误或类型不匹配）',
        fields: fields,
      );
    }

    final newErrors = newValidationErrors(
      base: base.config,
      candidate: candidate.config,
    );
    if (newErrors.isNotEmpty) {
      final baseErrorCount = _errorIssues(base.config).length;
      throw ProposalException(
        'invalid_config',
        '候选引入了 ${newErrors.length} 个新的校验错误'
            '（工程原有 $baseErrorCount 个错误不算在内）',
        fields: [for (final issue in newErrors) issue.fieldPath],
      );
    }

    final changes = diffConfigs(
      base.config.toJson(),
      candidate.config.toJson(),
    );
    if (changes.isEmpty) {
      throw const ProposalException('empty_changes', '候选配置与当前工程没有差异');
    }

    return ProjectProposal(
      baseSha256: baseSha256,
      createdAt: (now ?? DateTime.now()).toUtc(),
      tool: tool,
      changedPaths: [for (final change in changes) change.path],
      document: candidate,
    );
  }

  static ProjectDocument _parseDocument(Map<String, Object?> json) {
    try {
      return ProjectDocument.fromJson(json);
    } on FormatException catch (error) {
      throw ProposalException('invalid_document', error.message);
    } catch (error) {
      throw ProposalException('invalid_document', '工程内容无法解析：$error');
    }
  }
}

/// 递归比较两份配置，返回所有差异（路径按 `a.b[0].c` 形式）。
List<ProposalChange> diffConfigs(
  Map<String, Object?> before,
  Map<String, Object?> after,
) {
  final changes = <ProposalChange>[];
  _collectChanges(before, after, '', changes);
  return changes;
}

/// 候选相对基线**新增**的 error 级校验问题。
///
/// 工程可能本来就处于「没配置完」的状态（用户填到一半就保存），所以提案
/// 不以「整体无错误」为前提，只禁止 AI 让工程变差。比较键是
/// `字段路径 + 错误文案`：既有错误原样保留不算新增；同一字段换成另一种
/// 错误仍算新增。
List<ValidationIssue> newValidationErrors({
  required ProjectConfig base,
  required ProjectConfig candidate,
}) {
  final baseline = {for (final issue in _errorIssues(base)) _issueKey(issue)};
  return [
    for (final issue in _errorIssues(candidate))
      if (!baseline.contains(_issueKey(issue))) issue,
  ];
}

List<ValidationIssue> _errorIssues(ProjectConfig config) =>
    ProjectValidator.validate(config)
        .where((issue) => issue.severity == IssueSeverity.error)
        .toList();

String _issueKey(ValidationIssue issue) =>
    '${issue.fieldPath}\u0000${issue.message}';

/// 找出候选 JSON 里「写进去但模型读不回来」的字段。
///
/// 只检查候选实际写出的字段：缺省字段表示沿用默认值，不算问题。未知字段
/// （模型写错键名）会因为解析后不存在而被拒绝；枚举拼错回退到默认值时，
/// 写回值与候选值不同，同样会被拒绝。
List<String> findUnroundtrippedFields(
  Map<String, Object?> rawConfig,
  Map<String, Object?> parsedConfig,
) {
  final fields = <String>[];
  _collectUnroundtripped(rawConfig, parsedConfig, '', fields);
  return fields;
}

void _collectChanges(
  Object? before,
  Object? after,
  String path,
  List<ProposalChange> out,
) {
  if (before is Map && after is Map) {
    final keys = <String>{
      for (final key in before.keys) key.toString(),
      for (final key in after.keys) key.toString(),
    };
    for (final key in keys) {
      _collectChanges(
        before[key],
        after[key],
        path.isEmpty ? key : '$path.$key',
        out,
      );
    }
    return;
  }
  if (before is List && after is List) {
    final length = before.length > after.length ? before.length : after.length;
    for (var index = 0; index < length; index += 1) {
      _collectChanges(
        index < before.length ? before[index] : null,
        index < after.length ? after[index] : null,
        '$path[$index]',
        out,
      );
    }
    return;
  }
  if (!_deepEquals(before, after)) {
    out.add(ProposalChange(path: path, before: before, after: after));
  }
}

void _collectUnroundtripped(
  Object? raw,
  Object? parsed,
  String path,
  List<String> out,
) {
  if (raw is Map) {
    if (parsed is! Map) {
      out.add(path.isEmpty ? '<root>' : path);
      return;
    }
    for (final entry in raw.entries) {
      final key = entry.key.toString();
      final childPath = path.isEmpty ? key : '$path.$key';
      if (!parsed.containsKey(key)) {
        out.add(childPath);
        continue;
      }
      _collectUnroundtripped(entry.value, parsed[key], childPath, out);
    }
    return;
  }
  if (raw is List) {
    if (parsed is! List || parsed.length < raw.length) {
      out.add(path.isEmpty ? '<root>' : path);
      return;
    }
    for (var index = 0; index < raw.length; index += 1) {
      _collectUnroundtripped(raw[index], parsed[index], '$path[$index]', out);
    }
    return;
  }
  if (!_deepEquals(raw, parsed)) out.add(path.isEmpty ? '<root>' : path);
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (!b.containsKey(entry.key)) return false;
      if (!_deepEquals(entry.value, b[entry.key])) return false;
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var index = 0; index < a.length; index += 1) {
      if (!_deepEquals(a[index], b[index])) return false;
    }
    return true;
  }
  return a == b;
}

/// 提案文件内容是否为合法提案（供应用快速判断，异常信息可展示）。
bool isValidProposalJson(Map<String, Object?> json) {
  try {
    ProjectProposal.fromJson(json);
    return true;
  } on ProposalException {
    return false;
  }
}

/// 把提案 JSON 编码成写入文件的文本（带缩进，便于用户直接查看）。
String encodeProposal(ProjectProposal proposal) =>
    '${const JsonEncoder.withIndent('  ').convert(proposal.toJson())}\n';

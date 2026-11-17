/// 六个 `pieblock_*` 工具的声明与实现。
///
/// 工具是这一层唯一的对外入口：协议层只负责把 `tools/call` 转进来，业务
/// 全部在 `domain/` 里，宿主只实现 `McpHost`。
library;

import 'dart:convert';

import 'package:pieblock_core/pieblock_core.dart';

import '../domain/catalog.dart';
import '../domain/host.dart';
import '../domain/patch.dart';
import '../protocol/json_rpc.dart';
import '../protocol/mcp_message.dart';
import 'tool_spec.dart';

/// 工具注册表。
class McpToolRegistry {
  McpToolRegistry({
    required this.host,
    required this.engine,
    required this.protocolVersion,
    this.maxContextFields = 200,
    this.maxContextBytes = 32 * 1024,
    this.defaultCodeLines = 200,
  });

  final McpHost host;
  final PatchEngine engine;

  /// 本次会话协商出的协议版本，写进 handshake 结果。
  ///
  /// 可变：`initialize` 完成协商后由会话回填，避免 handshake 报出协商前的
  /// 默认版本。
  String protocolVersion;

  final int maxContextFields;
  final int maxContextBytes;
  final int defaultCodeLines;

  static const toolNames = [
    'pieblock_handshake',
    'pieblock_get_context',
    'pieblock_validate',
    'pieblock_propose_patch',
    'pieblock_apply_patch',
    'pieblock_generate_code',
  ];

  late final List<McpToolSpec> tools = [
    const McpToolSpec(
      name: 'pieblock_handshake',
      title: '握手',
      description:
          '开始任何操作前先调用一次：返回应用版本、协议版本、项目类型、当前 revision 与步骤列表。'
          '未打开项目时 project 为 null，此时不要尝试读写配置。',
      inputSchema: {'type': 'object', 'properties': {}},
      annotations: McpToolAnnotations(readOnlyHint: true, idempotentHint: true),
    ),
    const McpToolSpec(
      name: 'pieblock_get_context',
      title: '读取配置上下文',
      description:
          '读取当前项目的字段清单：每个字段的 JSON 路径、中文名、所属步骤、当前值、取值范围与枚举值。'
          '改配置前必须先读，因为只有这里列出的可写字段能被补丁接受。'
          '可选 stepId 缩小范围（如 remote / mechanism / controls / pwm / strategy / mappings / tests / music）。'
          '数组字段以 aggregate 形式给出数量，访问具体元素请带下标。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'stepId': {
            'type': 'string',
            'description': '只返回该步骤的字段；省略则返回全部。',
          },
        },
      },
      annotations: McpToolAnnotations(readOnlyHint: true, idempotentHint: true),
    ),
    const McpToolSpec(
      name: 'pieblock_validate',
      title: '校验配置',
      description:
          '对当前配置或一份假设的配置跑一遍项目校验器，返回问题列表（severity / fieldPath / message / stepId）。'
          '只读、无副作用。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'config': {
            'type': 'object',
            'description': '可选。整份 config JSON；省略则校验当前文档。',
          },
        },
      },
      annotations: McpToolAnnotations(readOnlyHint: true, idempotentHint: true),
    ),
    const McpToolSpec(
      name: 'pieblock_propose_patch',
      title: '提交配置改动草案',
      description:
          '提出一组配置改动，返回 patchId、逐条 diff 与改动后的校验结果。**不会修改项目**。'
          '路径用 pieblock_get_context 给出的 JSON 路径，数组用具体下标（modes[1].actions[0]）。'
          'baseRevision 必须是最近一次读到的 revision，过期会返回 stale_revision，需要重新读上下文再提。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'baseRevision': {
            'type': 'integer',
            'description': '提出改动时项目的 revision；省略则用当前值。',
          },
          'ops': {
            'type': 'array',
            'minItems': 1,
            'items': {
              'type': 'object',
              'required': ['op', 'path'],
              'properties': {
                'op': {
                  'type': 'string',
                  'enum': ['set', 'remove'],
                },
                'path': {
                  'type': 'string',
                  'description': 'JSON 路径，如 chassis.normal_speed、modes[0].actions[0].key。',
                },
                'value': {
                  'description': 'set 时的目标值；清空字段显式写 null。',
                },
              },
            },
          },
        },
        'required': ['ops'],
      },
      annotations: McpToolAnnotations(idempotentHint: false),
    ),
    const McpToolSpec(
      name: 'pieblock_apply_patch',
      title: '应用配置改动',
      description:
          '提交先前 propose 得到的 patchId。补丁只能使用一次；'
          'PIE-Block 窗口会弹出确认卡片，用户同意且项目 revision 未变时才真正写入。'
          '返回 denied 表示用户拒绝，approval_timeout 表示确认超时，stale_revision 表示期间项目被改过。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'patchId': {'type': 'string', 'description': 'propose 返回的补丁 id。'},
        },
        'required': ['patchId'],
      },
      annotations: McpToolAnnotations(destructiveHint: true),
    ),
    const McpToolSpec(
      name: 'pieblock_generate_code',
      title: '查看生成的 C 代码',
      description:
          '返回当前配置生成的 main.c 片段（配置存在 error 时拒绝生成）。用 offset / limit 分页读取，'
          '默认返回前 200 行。只读。',
      inputSchema: {
        'type': 'object',
        'properties': {
          'offset': {'type': 'integer', 'description': '起始行，从 0 开始。'},
          'limit': {'type': 'integer', 'description': '最多返回多少行。'},
        },
      },
      annotations: McpToolAnnotations(readOnlyHint: true, idempotentHint: true),
    ),
  ];

  Future<McpToolResult> call(
    String name,
    Map<String, Object?> arguments,
  ) async {
    try {
      return switch (name) {
        'pieblock_handshake' => _handshake(),
        'pieblock_get_context' => _context(arguments),
        'pieblock_validate' => _validate(arguments),
        'pieblock_propose_patch' => _propose(arguments),
        'pieblock_apply_patch' => await _apply(arguments),
        'pieblock_generate_code' => _code(arguments),
        _ => throw JsonRpcException(
          JsonRpcErrorCode.invalidParams,
          '未知工具 "$name"',
        ),
      };
    } on PatchException catch (error) {
      return McpToolResult.failure(
        error.code,
        error.message,
        details: error.details,
      );
    }
  }

  // ---------------------------------------------------------------- handshake

  McpToolResult _handshake() {
    final snapshot = host.snapshot();
    final revision = host.revision;
    final structured = <String, Object?>{
      'appVersion': host.appVersion,
      'protocolVersion': protocolVersion,
      'projectFormatVersion': ProjectDocument.formatVersion,
      'tools': toolNames,
      'project': snapshot == null
          ? null
          : {
              'kind': snapshot.kind,
              'revision': revision,
              'currentStepId': snapshot.currentStepId,
              'steps': snapshot.steps,
              'issueCount': snapshot.issues.length,
            },
    };
    final text = snapshot == null
        ? 'PIE-Block ${host.appVersion}：当前没有打开的项目，请先让用户打开或新建项目。'
        : 'PIE-Block ${host.appVersion}：项目类型 ${snapshot.kind}，'
              'revision $revision，当前步骤 ${snapshot.currentStepId ?? '未知'}，'
              '已有 ${snapshot.issues.length} 条校验问题。';
    return McpToolResult.ok(text, structured);
  }

  // ------------------------------------------------------------------ context

  McpToolResult _context(Map<String, Object?> arguments) {
    final snapshot = _requireSnapshot();
    final stepId = arguments['stepId']?.toString();
    final specs = stepId == null
        ? McpFieldCatalog.specs
        : McpFieldCatalog.forStep(stepId);
    if (specs.isEmpty) {
      throw PatchException(
        McpToolErrorCode.invalidValue,
        '未知步骤 "$stepId"；可用步骤：${snapshot.steps.join(' / ')}',
      );
    }

    final fields = <Map<String, Object?>>[];
    var bytes = 0;
    var truncated = false;
    for (final spec in specs) {
      if (fields.length >= maxContextFields) {
        truncated = true;
        break;
      }
      final entry = _describe(spec, snapshot.config);
      bytes += utf8.encode(jsonEncode(entry)).length;
      if (bytes > maxContextBytes) {
        truncated = true;
        break;
      }
      fields.add(entry);
    }

    final structured = {
      'kind': snapshot.kind,
      'revision': host.revision,
      'currentStepId': snapshot.currentStepId,
      'steps': snapshot.steps,
      'fields': fields,
      'issues': [for (final issue in snapshot.issues) _issueJson(issue)],
      'truncated': truncated,
      if (truncated)
        'hint': '结果被截断，请带 stepId 再读一次以缩小范围',
    };
    final text = '项目 ${snapshot.kind} 的 '
        '${stepId ?? '全部'} 字段共 ${fields.length} 条'
        '${truncated ? '（已截断）' : ''}，现有 '
        '${snapshot.issues.length} 条校验问题。';
    return McpToolResult.ok(text, structured);
  }

  /// 单个字段的描述。数组元素聚合成一条，避免音乐工程把上下文撑爆。
  Map<String, Object?> _describe(
    McpFieldSpec spec,
    Map<String, Object?> config,
  ) {
    if (spec.isArrayElement) {
      final scan = _scanPattern(spec.pattern, config, sampleLimit: 1);
      return {
        ...spec.toJson(),
        'arrayCount': scan.count,
        'aggregate': true,
        if (scan.sample.isNotEmpty)
          'example': {
            'path': scan.sample.first.key,
            'value': scan.sample.first.value,
          },
      };
    }
    if (!spec.pattern.contains('*')) {
      final value = readPath(config, spec.pattern);
      return {
        ...spec.toJson(),
        'value': isAbsent(value) ? null : value,
        'present': !isAbsent(value),
      };
    }
    final scan = _scanPattern(spec.pattern, config, sampleLimit: 16);
    return {
      ...spec.toJson(),
      'values': [
        for (final entry in scan.sample) {'path': entry.key, 'value': entry.value},
      ],
    };
  }

  // ----------------------------------------------------------------- validate

  McpToolResult _validate(Map<String, Object?> arguments) {
    final raw = arguments['config'];
    final List<ValidationIssue> issues;
    if (raw == null) {
      issues = _requireSnapshot().issues;
    } else if (raw is Map) {
      final snapshot = _requireSnapshot();
      final config = decodeConfig(
        snapshot.kind,
        Map<String, Object?>.from(raw),
      );
      issues = host.issuesOf(config);
    } else {
      throw const PatchException(
        McpToolErrorCode.invalidValue,
        'config 必须是对象',
      );
    }
    final errors = issues.where((i) => i.severity == IssueSeverity.error).length;
    return McpToolResult.ok(
      issues.isEmpty
          ? '校验通过，没有问题。'
          : '发现 $errors 个错误、${issues.length - errors} 个提醒。',
      {
        'errorCount': errors,
        'warningCount': issues.length - errors,
        'issues': [for (final issue in issues) _issueJson(issue)],
      },
    );
  }

  // ------------------------------------------------------------------ propose

  McpToolResult _propose(Map<String, Object?> arguments) {
    final snapshot = _requireSnapshot();
    final revision = host.revision;
    if (revision == null) {
      throw const PatchException(McpToolErrorCode.noProject, '当前没有打开的项目');
    }
    final rawOps = arguments['ops'];
    if (rawOps is! List) {
      throw const PatchException(
        McpToolErrorCode.invalidValue,
        'ops 必须是数组',
      );
    }
    final baseRevision = _readRevision(arguments) ?? revision;
    if (baseRevision != revision) {
      throw PatchException(
        McpToolErrorCode.staleRevision,
        '项目已更新到 revision $revision，请重新读取上下文后再提改动',
        details: {'currentRevision': revision, 'baseRevision': baseRevision},
      );
    }

    final plan = engine.propose(
      kind: snapshot.kind,
      baseConfig: snapshot.config,
      baseRevision: revision,
      rawOps: rawOps,
    );
    return McpToolResult.ok(
      '补丁 ${plan.patchId} 准备就绪，共 ${plan.diff.length} 处改动；'
      'apply 前需要用户在窗口内确认。',
      {
        'patchId': plan.patchId,
        'baseRevision': plan.baseRevision,
        'diff': [for (final entry in plan.diff) entry.toJson()],
        'issues': [for (final issue in plan.issues) _issueJson(issue)],
        'errorCount': plan.issues
            .where((i) => i.severity == IssueSeverity.error)
            .length,
      },
    );
  }

  // -------------------------------------------------------------------- apply

  Future<McpToolResult> _apply(Map<String, Object?> arguments) async {
    final patchId = arguments['patchId']?.toString();
    if (patchId == null || patchId.isEmpty) {
      throw const PatchException(
        McpToolErrorCode.invalidValue,
        '缺少 patchId',
      );
    }
    final revision = host.revision;
    if (revision == null) {
      throw const PatchException(McpToolErrorCode.noProject, '当前没有打开的项目');
    }
    final plan = engine.cache.take(patchId);
    if (plan == null) {
      throw PatchException(
        McpToolErrorCode.patchExpired,
        '补丁不存在或已过期，请重新 propose',
      );
    }
    if (plan.baseRevision != revision) {
      throw PatchException(
        McpToolErrorCode.staleRevision,
        '项目在确认前被改动过（revision $revision），请重新读取上下文',
        details: {'currentRevision': revision, 'baseRevision': plan.baseRevision},
      );
    }

    final result = await host.apply(
      plan,
      McpApprovalRequest(
        patchId: plan.patchId,
        baseRevision: plan.baseRevision,
        diff: plan.diff,
        issues: plan.issues,
      ),
    );
    switch (result.outcome) {
      case McpApplyOutcome.applied:
        return McpToolResult.ok(
          '已应用 ${plan.diff.length} 处改动，revision 变为 ${result.revision}。',
          {'revision': result.revision, 'patchId': plan.patchId},
        );
      case McpApplyOutcome.denied:
        throw PatchException(
          McpToolErrorCode.denied,
          result.message ?? '用户拒绝了这次改动',
        );
      case McpApplyOutcome.timeout:
        throw PatchException(
          McpToolErrorCode.approvalTimeout,
          result.message ?? '等待用户确认超时',
        );
      case McpApplyOutcome.conflict:
        throw PatchException(
          McpToolErrorCode.staleRevision,
          result.message ?? '确认期间项目被改动，改动未应用',
          details: {'currentRevision': host.revision},
        );
    }
  }

  // --------------------------------------------------------------------- code

  McpToolResult _code(Map<String, Object?> arguments) {
    final snapshot = _requireSnapshot();
    final errors = snapshot.issues
        .where((issue) => issue.severity == IssueSeverity.error)
        .toList();
    if (errors.isNotEmpty) {
      throw PatchException(
        McpToolErrorCode.incompleteConfig,
        '配置还有 ${errors.length} 个错误，先修好才能生成代码：${errors.first.message}',
        details: {'firstFieldPath': errors.first.fieldPath},
      );
    }
    final config = decodeConfig(snapshot.kind, snapshot.config);
    final source = CodeGenerator.generate(config);
    final lines = source.split('\n');
    final offset = (arguments['offset'] as num?)?.toInt() ?? 0;
    final limit =
        (arguments['limit'] as num?)?.toInt() ?? defaultCodeLines;
    final start = offset.clamp(0, lines.length);
    final end = (start + limit).clamp(start, lines.length);
    final slice = lines.sublist(start, end);
    return McpToolResult.ok(
      'main.c 第 ${start + 1}–$end 行，共 ${lines.length} 行。',
      {
        'totalLines': lines.length,
        'offset': start,
        'lines': slice,
        'hasMore': end < lines.length,
      },
    );
  }

  // ------------------------------------------------------------------ helpers

  McpSnapshot _requireSnapshot() {
    final snapshot = host.snapshot();
    if (snapshot == null) {
      throw const PatchException(
        McpToolErrorCode.noProject,
        '当前没有打开的项目，请先让用户在 PIE-Block 里打开或新建项目',
      );
    }
    return snapshot;
  }

  int? _readRevision(Map<String, Object?> arguments) {
    final raw = arguments['baseRevision'];
    if (raw is num) return raw.toInt();
    return null;
  }

  static Map<String, Object?> _issueJson(ValidationIssue issue) => {
    'severity': issue.severity.name,
    'fieldPath': issue.fieldPath,
    'message': issue.message,
    'stepId': issue.stepId,
    'kind': issue.kind.name,
    'label': McpFieldCatalog.lookupIssue(issue.fieldPath)?.label,
  };

  /// 把带 `*` 的模式展开成具体路径 → 值。
  ///
  /// 计数是完整的，样本最多 [sampleLimit] 条：音乐工程可能有上万个音符，
  /// 只报数量、不把它们全塞进模型上下文。
  ({int count, List<MapEntry<String, Object?>> sample}) _scanPattern(
    String pattern,
    Map<String, Object?> config, {
    int sampleLimit = 64,
  }) {
    final parts = pattern.split('.');
    final sample = <MapEntry<String, Object?>>[];
    var count = 0;

    void walk(Object? node, int depth, String path) {
      if (depth == parts.length) {
        count += 1;
        if (sample.length < sampleLimit) {
          sample.add(MapEntry(path, node));
        }
        return;
      }
      final raw = parts[depth];
      final open = raw.indexOf('[');
      final name = open < 0 ? raw : raw.substring(0, open);
      final index = open < 0 ? null : raw.substring(open + 1, raw.length - 1);

      if (name == '*') {
        if (node is! Map) return;
        for (final entry in node.entries) {
          walk(
            entry.value,
            depth + 1,
            path.isEmpty ? entry.key.toString() : '$path.${entry.key}',
          );
        }
        return;
      }
      if (node is! Map || !node.containsKey(name)) return;
      final child = node[name];
      final base = path.isEmpty ? name : '$path.$name';
      if (index == null) {
        walk(child, depth + 1, base);
        return;
      }
      if (child is! List) return;
      if (index == '*') {
        for (var i = 0; i < child.length; i += 1) {
          walk(child[i], depth + 1, '$base[$i]');
        }
        return;
      }
      final at = int.tryParse(index);
      if (at == null || at < 0 || at >= child.length) return;
      walk(child[at], depth + 1, '$base[$at]');
    }

    walk(config, 0, '');
    return (count: count, sample: sample);
  }
}

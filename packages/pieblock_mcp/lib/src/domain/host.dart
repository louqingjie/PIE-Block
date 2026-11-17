/// 宿主接口：契约层唯一需要 Flutter 侧实现的东西。
///
/// 所有「写」都必须经过 `AppController.updateConfig`，这样校验、撤销、
/// 500ms 防抖保存三处行为与界面手改完全一致。
library;

import 'package:pieblock_core/pieblock_core.dart';

import 'patch.dart';

/// 当前文档的一次快照。
class McpSnapshot {
  const McpSnapshot({
    required this.kind,
    required this.config,
    required this.issues,
    required this.steps,
    this.currentStepId,
    this.path,
  });

  /// `ProjectKind.name`。
  final String kind;

  /// `ProjectConfig.toJson()` 的结果，补丁以它为基准。
  final Map<String, Object?> config;

  /// 生成快照时的校验结果。
  final List<ValidationIssue> issues;

  /// 该类型项目的向导步骤 id，来自宿主，避免契约层再抄一份。
  final List<String> steps;

  /// 用户当前停留的步骤，用于给模型一个默认上下文。
  final String? currentStepId;

  /// 项目文件路径；只用于审计与 UI，不下发给模型。
  final String? path;
}

/// 审批请求：交给宿主变成一张确认卡片。
class McpApprovalRequest {
  const McpApprovalRequest({
    required this.patchId,
    required this.baseRevision,
    required this.diff,
    required this.issues,
  });

  final String patchId;
  final int baseRevision;
  final List<McpDiffEntry> diff;
  final List<ValidationIssue> issues;
}

enum McpApplyOutcome {
  applied,
  denied,
  timeout,

  /// 确认期间项目被改动，补丁作废。
  conflict,
}

/// 应用结果。`applied` 时带回新的 revision。
class McpApplyResult {
  const McpApplyResult(this.outcome, {this.revision, this.message});

  final McpApplyOutcome outcome;
  final int? revision;
  final String? message;

  bool get applied => outcome == McpApplyOutcome.applied;

  Map<String, Object?> toJson() => {
    'outcome': outcome.name,
    if (revision != null) 'revision': revision,
    if (message != null) 'message': message,
  };
}

/// 审计条目。刻意不含 token 与文档正文，只记「谁在什么时候动了什么」。
class McpAuditEntry {
  const McpAuditEntry({
    required this.at,
    required this.method,
    required this.outcome,
    this.detail,
    this.revisionBefore,
    this.revisionAfter,
  });

  final DateTime at;
  final String method;

  /// `ok` 或某个工具错误码。
  final String outcome;
  final String? detail;
  final int? revisionBefore;
  final int? revisionAfter;

  Map<String, Object?> toJson() => {
    'at': at.toIso8601String(),
    'method': method,
    'outcome': outcome,
    if (detail != null) 'detail': detail,
    if (revisionBefore != null) 'revisionBefore': revisionBefore,
    if (revisionAfter != null) 'revisionAfter': revisionAfter,
  };
}

/// 宿主能力。
abstract interface class McpHost {
  /// 应用版本号，写进 `serverInfo.version` 与 handshake 结果。
  String get appVersion;

  /// 文档版本号；未打开项目时为 null。
  int? get revision;

  /// 当前文档切片；未打开项目时为 null。
  McpSnapshot? snapshot();

  /// 对给定配置做校验（复用 `ProjectValidator`，不新增规则）。
  List<ValidationIssue> issuesOf(ProjectConfig config);

  /// 等人工确认后落到 `AppController.updateConfig`。
  Future<McpApplyResult> apply(
    McpPatchPlan plan,
    McpApprovalRequest request,
  );

  /// 记一条审计。
  void record(McpAuditEntry entry);
}

import 'dart:async';

import 'package:pieblock_mcp/pieblock_mcp.dart';

/// 一条等待用户确认的 AI 改动。
///
/// 这里刻意不放 `Timer` 之外的任何可变状态：取消、超时、同意都由
/// `McpApprovalController` 通过 [completer] 决定结果，避免两处各记一份。
class McpPendingApproval {
  McpPendingApproval({
    required this.plan,
    required this.request,
    required this.deadline,
    required this.completer,
  });

  final McpPatchPlan plan;
  final McpApprovalRequest request;
  final DateTime deadline;
  final Completer<McpApplyResult> completer;

  String get patchId => request.patchId;

  Duration get remaining {
    final left = deadline.difference(DateTime.now());
    return left.isNegative ? Duration.zero : left;
  }
}

/// 本地 MCP 服务的运行状态。
class McpServiceState {
  const McpServiceState({
    this.running = false,
    this.endpoint,
    this.token,
    this.bridgePath,
    this.error,
    this.audit = const [],
  });

  final bool running;

  /// 客户端要连接的完整地址，含 `/mcp` 路径但不含 token。
  final String? endpoint;

  /// 本进程的访问 token；只展示给本机用户。
  final String? token;

  /// `mcp-bridge.json` 的落点，便于排查。
  final String? bridgePath;

  /// 启动失败原因；Web 与 Android 上固定为「不支持」。
  final String? error;

  /// 最近的调用记录，新的在前，最多 100 条。
  final List<McpAuditEntry> audit;

  /// 贴给客户端的 `Authorization` 头内容。
  String? get authorizationHeader =>
      token == null ? null : 'Bearer $token';

  McpServiceState copyWith({
    bool? running,
    String? endpoint,
    String? token,
    String? bridgePath,
    String? error,
    bool clearError = false,
    List<McpAuditEntry>? audit,
  }) => McpServiceState(
    running: running ?? this.running,
    endpoint: endpoint ?? this.endpoint,
    token: token ?? this.token,
    bridgePath: bridgePath ?? this.bridgePath,
    error: clearError ? null : error ?? this.error,
    audit: audit ?? this.audit,
  );
}

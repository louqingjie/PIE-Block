import 'package:pieblock_mcp/pieblock_mcp.dart';

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

/// MCP 的会话结构与 `tools/*` 消息形状。
///
/// 这里只放「协议层面的形状」，不放任何 PIE-Block 业务：工具名、字段、
/// 补丁都在 `tools/` 与 `domain/` 里。
library;

/// 协议版本与能力协商。
abstract final class McpProtocol {
  /// 当前实现对准的规范版本。
  static const latest = '2025-06-18';

  /// 认识的版本，新的在前。
  ///
  /// 客户端请求旧版本时按旧版本回，避免为了兼容一个小版本而改造解析；
  /// 请求了不认识的更新版本时按规范回 [latest]，由客户端决定是否继续。
  static const supported = ['2025-06-18', '2025-03-26', '2024-11-05'];

  static String negotiate(Object? requested) =>
      requested is String && supported.contains(requested) ? requested : latest;
}

/// MCP 方法名。集中一处，避免 handler 里散落字符串。
abstract final class McpMethod {
  static const initialize = 'initialize';
  static const initialized = 'notifications/initialized';
  static const ping = 'ping';
  static const toolsList = 'tools/list';
  static const toolsCall = 'tools/call';
  static const cancelled = 'notifications/cancelled';
}

/// 工具级错误码：放在 `structuredContent.code` 里。
///
/// 用字符串而不是数字，是因为这些码要同时给两种读者看——模型据此分支，
/// 用户据此理解「为什么没改成」，字符串比 -32001 可读性高得多。
abstract final class McpToolErrorCode {
  static const unauthorized = 'unauthorized';
  static const noProject = 'no_project';
  static const staleRevision = 'stale_revision';
  static const patchExpired = 'patch_expired';
  static const invalidPath = 'invalid_path';
  static const notWritable = 'not_writable';
  static const invalidValue = 'invalid_value';
  static const emptyPatch = 'empty_patch';
  static const projectMismatch = 'project_mismatch';
  static const denied = 'denied';
  static const approvalTimeout = 'approval_timeout';
  static const incompleteConfig = 'incomplete_config';
  static const unsupported = 'unsupported';
}

/// `initialize` 里的 `serverInfo`。
class McpServerInfo {
  const McpServerInfo({
    required this.name,
    required this.version,
    this.title,
    this.instructions = '',
  });

  final String name;
  final String version;
  final String? title;

  /// 给模型看的服务说明；为空时不下发。
  final String instructions;

  Map<String, Object?> toJson() => {
    'name': name,
    'version': version,
    if (title != null) 'title': title,
  };
}

/// `initialize` 的结果。
Map<String, Object?> buildInitializeResult({
  required String protocolVersion,
  required McpServerInfo server,
  bool toolsListChanged = false,
}) => {
  'protocolVersion': protocolVersion,
  'capabilities': {
    'tools': {'listChanged': toolsListChanged},
  },
  'serverInfo': server.toJson(),
  if (server.instructions.isNotEmpty) 'instructions': server.instructions,
};

/// `tools/call` 的结果。
///
/// MCP 要求至少有一个 text content，所以即使带 `structuredContent` 也要写
/// 一段人话摘要——它同时也是用户在客户端界面上唯一能看到的东西。
class McpToolResult {
  const McpToolResult({
    required this.text,
    this.structuredContent,
    this.isError = false,
  });

  factory McpToolResult.ok(
    String text, [
    Map<String, Object?>? structuredContent,
  ]) => McpToolResult(text: text, structuredContent: structuredContent);

  factory McpToolResult.failure(
    String code,
    String message, {
    Map<String, Object?> details = const {},
  }) => McpToolResult(
    text: message,
    isError: true,
    structuredContent: {'code': code, 'message': message, ...details},
  );

  final String text;
  final Map<String, Object?>? structuredContent;
  final bool isError;

  Map<String, Object?> toJson() => {
    'content': [
      {'type': 'text', 'text': text},
    ],
    if (structuredContent != null) 'structuredContent': structuredContent,
    if (isError) 'isError': true,
  };
}

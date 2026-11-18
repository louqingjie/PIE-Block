import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import 'mcp_models.dart';

/// Web 上的空桩：浏览器无法监听端口，按设计不提供 MCP 接入。
///
/// 这里**不能** import `package:pieblock_mcp/http.dart`，否则 `dart:io` 会把
/// Web 构建打挂。UI 侧靠 [McpServiceState.error] 判断是否显示入口。
final mcpServiceProvider = NotifierProvider<McpService, McpServiceState>(
  McpService.new,
);

class McpService extends Notifier<McpServiceState> {
  @override
  McpServiceState build() => const McpServiceState(
    error: '网页版不提供本地 MCP 服务，请使用桌面版',
  );

  Future<void> start() async {}

  Future<void> stop() async {}

  Future<void> restart() async {}

  Future<void> rotateToken() async {}

  Future<void> setPort(int port) async {}

  void appendAudit(McpAuditEntry entry) {}
}

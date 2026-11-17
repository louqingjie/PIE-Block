/// PIE-Block 的 MCP 契约层。
///
/// 这一层完全不知道 Flutter、Riverpod 与 `.pieproj` 文件的存在：它只处理
/// 「一条 MCP 消息进来，应该回什么」，宿主通过 `McpHost` 把文档读写接上去。
///
/// 与 `pieblock_core` 的 barrel 一样，这里必须保持「Web 上不引入 dart:io」：
/// HTTP 传输放在单独的 `http.dart` 入口，Web 构建不要 import 它。
library;

export 'src/domain/catalog.dart';
export 'src/domain/host.dart';
export 'src/domain/patch.dart';
export 'src/protocol/json_rpc.dart';
export 'src/protocol/mcp_message.dart';
export 'src/server/mcp_server.dart';
export 'src/tools/registry.dart';
export 'src/tools/tool_spec.dart';

/// 仅在 native 平台可用的入口：本地 MCP HTTP 传输。
///
/// **Web 构建不要 import 这个文件**——它会引入 `dart:io`。Web 版按设计不提供
/// MCP 接入（浏览器无法监听端口），见 `lib/pieblock_mcp.dart` 的说明。
library;

export 'src/http/mcp_http_server.dart';

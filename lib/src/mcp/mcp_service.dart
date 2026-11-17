/// 本地 MCP 服务：桌面端监听 `127.0.0.1`，Web 上是空桩。
library;

export 'mcp_service_native.dart'
    if (dart.library.js_interop) 'mcp_service_web.dart';

/// 告诉宿主页面「应用已经画出第一帧了」。
///
/// 官网把 Web 版放在 iframe 里，并且约定：收到这个信号之前一直显示加载态，
/// 超时就退回静态示例。所以它是嵌入体验能优雅降级的关键一环。
library;

export 'host_bridge_stub.dart' if (dart.library.js_interop) 'host_bridge_web.dart';

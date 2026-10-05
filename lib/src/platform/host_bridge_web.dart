import 'dart:js_interop';

extension type _Window._(JSObject _) implements JSObject {
  external _Window get parent;
  external void postMessage(JSAny message, String targetOrigin);
}

@JS('window')
external _Window get _window;

const _readyMessage = 'pieblock:ready';

void notifyHostReady() {
  try {
    // 独立打开 /app/ 时 parent 就是自己，发出去没人听，无害。
    _window.parent.postMessage(_readyMessage.toJS, '*');
  } catch (_) {
    // 极少数沙箱环境不允许 postMessage，忽略即可——宿主那边会走超时降级。
  }
}

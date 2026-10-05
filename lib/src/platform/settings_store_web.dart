import 'dart:convert';
import 'dart:js_interop';

extension type _LocalStorage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
}

// 注意：隐私模式下取用 localStorage 本身就会抛 SecurityError，
// 所以每次访问都要包在 try 里。
@JS('localStorage')
external _LocalStorage get _storage;

const _key = 'pieblock.settings';

Future<Map<String, Object?>?> readSettings() async {
  try {
    final text = _storage.getItem(_key);
    if (text == null) return null;
    final decoded = jsonDecode(text);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeSettings(Map<String, Object?> values) async {
  try {
    _storage.setItem(_key, jsonEncode(values));
  } catch (_) {
    // 隐私模式或配额用尽：放弃保存，不打断用户。
  }
}

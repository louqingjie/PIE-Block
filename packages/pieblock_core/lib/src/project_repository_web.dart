import 'dart:convert';
import 'dart:js_interop';

import 'models.dart';

/// 浏览器里的 localStorage 最小封装。
extension type _LocalStorage._(JSObject _) implements JSObject {
  external String? getItem(String key);
  external void setItem(String key, String value);
  external void removeItem(String key);
}

@JS('localStorage')
external _LocalStorage get _storage;

/// Web 版项目仓库：项目存在 localStorage 里。
///
/// 引用就是文件名（例如 `我的机器人.pieproj`），不像 Android 那样需要
/// `content://` 前缀——浏览器里没有真实路径，不存在歧义，最近项目列表
/// 直接显示这个名字也更自然。
class ProjectRepository {
  const ProjectRepository();

  /// localStorage 的键前缀，避免和别的键撞车。
  static const _prefix = 'pieblock.project:';

  static String _key(String reference) => '$_prefix$reference';

  Future<ProjectDocument> create(
    String path,
    String name,
    ProjectKind kind,
  ) async {
    final document = ProjectDocument.create(name, kind);
    await save(path, document);
    return document;
  }

  Future<ProjectDocument> open(String path) async {
    final text = _storage.getItem(_key(path));
    if (text == null) {
      throw const FormatException('这个浏览器里没有找到该项目');
    }
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('项目文件不是有效的 JSON 对象');
    return ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> save(String path, ProjectDocument document) async {
    if (!path.toLowerCase().endsWith('.pieproj')) {
      throw const FormatException('项目文件必须使用 .pieproj 扩展名');
    }
    final encoder = const JsonEncoder.withIndent('  ');
    _storage.setItem(_key(path), encoder.convert(document.toJson()));
  }

  /// 项目是否还在（设置里的最近项目列表要据此过滤掉已被清掉的那些）。
  Future<bool> exists(String path) async =>
      _storage.getItem(_key(path)) != null;
}

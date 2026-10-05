import 'dart:convert';
import 'dart:io';

import 'models.dart';

/// 桌面 / 移动端项目仓库：项目是文件系统上的 `.pieproj` 文件。
///
/// Android 的 content URI 不走这里（见应用侧的 AppDocumentIo）。
class ProjectRepository {
  const ProjectRepository();

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
    final text = await File(path).readAsString();
    final decoded = jsonDecode(text);
    if (decoded is! Map) throw const FormatException('项目文件不是有效的 JSON 对象');
    return ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
  }

  Future<void> save(String path, ProjectDocument document) async {
    if (!path.toLowerCase().endsWith('.pieproj')) {
      throw const FormatException('项目文件必须使用 .pieproj 扩展名');
    }
    final target = File(path), temporary = File('$path.tmp');
    await target.parent.create(recursive: true);
    final encoder = const JsonEncoder.withIndent('  ');
    final sink = temporary.openWrite();
    sink.write('${encoder.convert(document.toJson())}\n');
    await sink.flush();
    await sink.close();
    try {
      await temporary.rename(path);
    } on FileSystemException {
      if (await target.exists()) await target.delete();
      await temporary.rename(path);
    }
  }

  /// 项目是否还在（设置里的最近项目列表要据此过滤掉已被删掉的那些）。
  Future<bool> exists(String path) async => File(path).exists();
}

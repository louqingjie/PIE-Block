import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

class SelectedDocument {
  const SelectedDocument({
    required this.reference,
    required this.name,
    required this.bytes,
  });

  final String reference;
  final String name;
  final Uint8List bytes;
}

/// Web 版文档访问。
///
/// 浏览器里没有可写的文件系统，所以只有「选一个文件」是真实存在的操作：
/// - `open` 走 file_selector 的 `<input type=file>`。引用取文件名而不是
///   `XFile.path`——Web 上那是一个 blob URL，既不能当项目引用，也没法二次读取。
/// - `create` / `read` / `write` 在 Web 上不会被调用（保存走浏览器存储，
///   导出走浏览器下载），留着是为了让上层代码两端都能编译。
class AppDocumentIo {
  const AppDocumentIo();

  Future<SelectedDocument?> open({
    required String label,
    required List<String> extensions,
    required List<String> mimeTypes,
  }) async {
    final file = await openFile(
      acceptedTypeGroups: [
        XTypeGroup(label: label, extensions: extensions, mimeTypes: mimeTypes),
      ],
    );
    if (file == null) return null;
    return SelectedDocument(
      reference: file.name,
      name: file.name,
      bytes: await file.readAsBytes(),
    );
  }

  /// Web 不支持「另存为」，返回 null 表示用户没有选到位置。
  Future<String?> create({
    required String suggestedName,
    required String mimeType,
    Uint8List? bytes,
    String? initialDirectory,
    List<String> extensions = const [],
  }) async => null;

  Future<Uint8List> read(String reference) async =>
      throw UnsupportedError('Web 版不支持按路径读取文件');

  Future<void> write(String reference, Uint8List bytes) async =>
      throw UnsupportedError('Web 版不支持按路径写入文件');

  static String displayName(String reference) =>
      reference.split('/').last.split('\\').last;
}

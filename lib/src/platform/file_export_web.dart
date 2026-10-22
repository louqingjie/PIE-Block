import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import 'document_io.dart';

extension type _Blob._(JSObject _) implements JSObject {
  external factory _Blob(JSArray<JSAny> parts, JSObject options);
}

extension type _BlobOptions._(JSObject _) implements JSObject {
  external factory _BlobOptions({String type});
}

extension type _Anchor._(JSObject _) implements JSObject {
  external set href(String value);
  external set download(String value);
  external void click();
}

@JS('URL.createObjectURL')
external String _createObjectUrl(_Blob blob);

@JS('URL.revokeObjectURL')
external void _revokeObjectUrl(String url);

@JS('document.createElement')
external _Anchor _createAnchor(String tag);

/// Web：没有可写文件系统，直接把这串文本作为文件下载下来。
///
/// [documentIo] 与原生版保持同一签名（浏览器里不需要选择位置，用不到）。
Future<bool> exportGeneratedText(
  BuildContext context, {
  required String suggestedName,
  required String text,
  String mimeType = 'text/plain',
  AppDocumentIo documentIo = const AppDocumentIo(),
}) async {
  final data = Uint8List.fromList(utf8.encode(text));
  final blob = _Blob(
    <JSAny>[data.toJS].toJS,
    _BlobOptions(type: mimeType),
  );
  final url = _createObjectUrl(blob);
  final anchor = _createAnchor('a');
  anchor
    ..href = url
    ..download = suggestedName
    ..click();
  // 立刻释放会让部分浏览器来不及取数据，延后一秒再回收。
  Future<void>.delayed(const Duration(seconds: 1), () => _revokeObjectUrl(url));
  return true;
}

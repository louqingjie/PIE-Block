import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

Future<Map<String, Object?>?> readSettings() async {
  try {
    final file = await _settingsFile();
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

Future<void> writeSettings(Map<String, Object?> values) async {
  try {
    final file = await _settingsFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(values));
  } catch (_) {
    // 目录不可写就放弃保存，不打断用户。
  }
}

Future<File> _settingsFile() async {
  final directory = await getApplicationSupportDirectory();
  return File('${directory.path}${Platform.pathSeparator}settings.json');
}

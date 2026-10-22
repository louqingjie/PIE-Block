import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 全应用必须统一使用 material_ui；只有 re_editor 的主题桥允许保留
/// flutter/material。
void main() {
  test('lib 不再直接依赖 flutter/material', () {
    final offenders = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      if (entity.path.endsWith('legacy_theme_bridge.dart')) continue;
      final source = entity.readAsStringSync();
      if (source.contains("package:flutter/material.dart")) {
        offenders.add(entity.path);
      }
    }
    expect(offenders, isEmpty, reason: '这些文件仍在使用 flutter/material');
  });
}

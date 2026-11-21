import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// CLI 的 `describe.release` 必须与仓库根 pubspec 的发布版本一致：
/// 发版时只改 pubspec 而忘记同步常量，会让 AI 误判“CLI 与应用版本不一致”。
void main() {
  test('pieblockRelease 与根 pubspec 的版本前缀一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'pubspec.yaml 缺少 version');
    expect(pieblockRelease, match!.group(1));
  });
}

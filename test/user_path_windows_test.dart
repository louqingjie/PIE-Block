import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/platform/user_path.dart';

void main() {
  final onWindows = Platform.isWindows;

  test('读取当前用户的 PATH', () {
    final value = UserPath.read();
    expect(value, isNotNull);
    expect(value!.type, anyOf(1, 2));
  }, skip: !onWindows);

  test('在测试键上读写并保持 REG_EXPAND_SZ', () {
    const keyPath = r'HKCU\Software\PIE-Block\CliPathTest';
    final created = Process.runSync('reg', ['add', keyPath, '/f']);
    expect(created.exitCode, 0, reason: created.stderr.toString());
    try {
      const sample = r'C:\A;%USERPROFILE%\B';
      expect(
        UserPath.write(sample, subKey: r'Software\PIE-Block\CliPathTest'),
        isTrue,
      );
      final value = UserPath.read(subKey: r'Software\PIE-Block\CliPathTest');
      expect(value, isNotNull);
      expect(value!.value, sample);
      expect(value.type, 2, reason: '必须保持 REG_EXPAND_SZ，不能把变量展开写死');
    } finally {
      Process.runSync('reg', ['delete', keyPath, '/f']);
    }
  }, skip: !onWindows);
}

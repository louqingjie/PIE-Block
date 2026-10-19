import 'dart:io';

import 'package:pieblock_toolchain/src/file_ops.dart';
import 'package:test/test.dart';

void main() {
  test('瞬时文件占用会重试并最终成功', () async {
    var calls = 0;
    final result = await retryFileSystem(
      () async {
        calls++;
        if (calls < 3) throw FileSystemException('locked', 'x');
        return calls;
      },
      initialDelay: Duration.zero,
      maxDelay: Duration.zero,
    );
    expect(result, 3);
    expect(calls, 3);
  });

  test('持续失败会在尝试次数用尽后抛出最后的异常', () async {
    var calls = 0;
    await expectLater(
      retryFileSystem<void>(
        () async {
          calls++;
          throw FileSystemException('locked', 'x');
        },
        attempts: 3,
        initialDelay: Duration.zero,
        maxDelay: Duration.zero,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(calls, 3);
  });

  test('copyDirectory 递归复制目录与文件', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock-copy-');
    addTearDown(() => directory.delete(recursive: true));
    final source = Directory('${directory.path}/source');
    File('${source.path}/a.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('a');
    final nested = File('${source.path}/nested/b.txt')
      ..createSync(recursive: true)
      ..writeAsStringSync('b');
    final destination = Directory('${directory.path}/destination');
    await copyDirectory(source, destination);
    expect(File('${destination.path}/a.txt').readAsStringSync(), 'a');
    expect(File('${destination.path}/nested/b.txt').readAsStringSync(), 'b');
    expect(nested.existsSync(), isTrue);
  });
}

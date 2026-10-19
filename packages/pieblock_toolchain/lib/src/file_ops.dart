import 'dart:io';

import 'package:path/path.dart' as p;

/// 对可能被杀毒软件、索引器或其它进程短暂占用的文件操作做有限重试。
///
/// Windows 上刚写出的目录/可执行文件句柄可能被扫描进程短暂持有，
/// `File.copy`、`Directory.rename`、`delete` 会抛 [FileSystemException]。
/// 这里只重试这类异常，编码错误等其它异常立即抛出。
Future<T> retryFileSystem<T>(
  Future<T> Function() action, {
  int attempts = 4,
  Duration initialDelay = const Duration(milliseconds: 120),
  Duration maxDelay = const Duration(seconds: 2),
}) async {
  var delay = initialDelay;
  for (var attempt = 1; ; attempt++) {
    try {
      return await action();
    } on FileSystemException {
      if (attempt >= attempts) rethrow;
      if (delay > Duration.zero) await Future<void>.delayed(delay);
      final next = delay.inMilliseconds * 2;
      delay = Duration(
        milliseconds: next > maxDelay.inMilliseconds
            ? maxDelay.inMilliseconds
            : next,
      );
    }
  }
}

/// 递归复制目录，逐文件重试瞬时占用。
Future<void> copyDirectory(Directory source, Directory destination) async {
  await retryFileSystem(() => destination.create(recursive: true));
  await for (final entity in source.list(followLinks: false)) {
    final target = p.join(destination.path, p.basename(entity.path));
    if (entity is Directory) {
      await copyDirectory(entity, Directory(target));
    } else if (entity is File) {
      await retryFileSystem(() => entity.copy(target));
    }
  }
}

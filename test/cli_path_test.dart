import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/platform/cli_path.dart';

void main() {
  const cli = r'C:\Apps\PIE-Block\cli';

  test('空 PATH：追加 CLI 目录', () {
    final update = planCliPathUpdate(currentPath: '', cliDirectory: cli);
    expect(update.added, isTrue);
    expect(update.removed, isEmpty);
    expect(update.path, cli);
  });

  test('已存在（大小写/斜杠/末尾分隔符不同）：不重复追加', () {
    for (final existing in <String>[
      r'c:\apps\pie-block\cli',
      r'C:/Apps/PIE-Block/cli/',
      r'"C:\Apps\PIE-Block\cli"',
    ]) {
      final update = planCliPathUpdate(
        currentPath: r'C:\Windows\system32;' + existing + r';C:\Windows',
        cliDirectory: cli,
      );
      expect(update.added, isFalse, reason: existing);
      expect(update.changed, isFalse, reason: existing);
      expect(update.path, contains(r'C:\Windows\system32'));
    }
  });

  test('旧安装目录：按记录条目删除，保留无关条目', () {
    final update = planCliPathUpdate(
      currentPath: r'C:\Windows;C:\Old\PIE-Block\cli;C:\Tools\bin',
      cliDirectory: cli,
      previouslyAdded: r'C:\Old\PIE-Block\cli',
    );
    expect(update.removed, [r'C:\Old\PIE-Block\cli']);
    expect(update.added, isTrue);
    expect(update.path, r'C:\Windows;C:\Tools\bin;' + cli);
  });

  test('旧目录仍在但应用已不在：按目录归属删除', () {
    final update = planCliPathUpdate(
      currentPath: r'D:\Moved\PIE-Block\cli;C:\Windows',
      cliDirectory: cli,
      directoryOwnedByPieBlock: (dir) =>
          dir.toLowerCase() == r'd:\moved\pie-block\cli',
    );
    expect(update.removed, [r'D:\Moved\PIE-Block\cli']);
    expect(update.path, r'C:\Windows;' + cli);
  });

  test('把可执行文件当目录写进 PATH：删除并补目录', () {
    final update = planCliPathUpdate(
      currentPath: r'C:\Apps\PIE-Block\cli\pieblock-cli.exe',
      cliDirectory: cli,
    );
    expect(update.removed, [r'C:\Apps\PIE-Block\cli\pieblock-cli.exe']);
    expect(update.path, cli);
  });

  test('重复的目标条目只保留第一个', () {
    final update = planCliPathUpdate(
      currentPath: [cli, r'C:\Windows', r'c:\apps\pie-block\cli'].join(';'),
      cliDirectory: cli,
    );
    expect(update.added, isFalse);
    expect(update.removed, [r'c:\apps\pie-block\cli']);
    expect(update.path, '$cli;C:\\Windows');
  });

  test('空条目、分号残留不会写回', () {
    final update = planCliPathUpdate(
      currentPath: r'C:\Windows;;C:\Tools\;',
      cliDirectory: cli,
    );
    expect(update.path, r'C:\Windows;C:\Tools\;' + cli);
  });

  test('不改写用户自己的条目顺序与写法', () {
    const current = r'%USERPROFILE%\bin;C:\Windows\system32';
    final update = planCliPathUpdate(currentPath: current, cliDirectory: cli);
    expect(update.path, '$current;$cli');
  });

  test('用户删掉同一目录的条目后不重新加回去', () {
    final update = planCliPathUpdate(
      currentPath: r'C:\Windows',
      cliDirectory: cli,
      previouslyAdded: cli,
    );
    expect(update.added, isTrue);
    expect(
      shouldApplyPathUpdate(
        update: update,
        cliDirectory: cli,
        previouslyAdded: cli,
      ),
      isFalse,
    );
  });

  test('首次启动或换目录时照常写入', () {
    final first = planCliPathUpdate(
      currentPath: r'C:\Windows',
      cliDirectory: cli,
    );
    expect(shouldApplyPathUpdate(update: first, cliDirectory: cli), isTrue);

    final moved = planCliPathUpdate(
      currentPath: r'C:\Old\PIE-Block\cli',
      cliDirectory: cli,
      previouslyAdded: r'C:\Old\PIE-Block\cli',
    );
    expect(
      shouldApplyPathUpdate(
        update: moved,
        cliDirectory: cli,
        previouslyAdded: r'C:\Old\PIE-Block\cli',
      ),
      isTrue,
    );
  });

  test('路径比较忽略大小写、斜杠与末尾分隔符', () {
    expect(
      samePath(r'C:\Apps\PIE-Block\cli', r'c:/apps/pie-block/cli/'),
      isTrue,
    );
    expect(samePath(r'C:\Apps\PIE-Block\cli', r'C:\Apps\PIE-Block'), isFalse);
  });

  test('便携版与开发构建不参与 PATH 维护', () {
    expect(
      isPortableInstall(
        r'C:\Users\u\AppData\Local\PIE-Block\portable\app\1.8.0-abc\bin',
      ),
      isTrue,
    );
    expect(
      isDevelopmentBuild(r'C:\repo\build\windows\x64\runner\Release'),
      isTrue,
    );
    expect(isDevelopmentBuild(r'D:\Apps\PIE-Block-1.8.0'), isFalse);
    expect(isPortableInstall(r'D:\Apps\PIE-Block-1.8.0'), isFalse);
  });
}

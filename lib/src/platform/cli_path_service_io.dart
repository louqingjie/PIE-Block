/// 免安装版启动时维护用户 PATH：把 `cli` 目录加进去，并清掉旧版本的条目。
///
/// 只在“看起来像正式发行包”的 Windows 运行目录下生效：
/// - 便携单文件版每次解压到带哈希的新目录，写 PATH 只会制造垃圾，跳过；
/// - 开发构建（`build\windows\...\Release`）跳过，避免把仓库路径塞进用户环境；
/// - 目录里没有 `cli\pieblock-cli.exe` 时跳过（旧包或裁剪过的包）。
///
/// 写的是 HKCU 的 PATH，不需要管理员；路径、旧条目清理规则见 [planCliPathUpdate]。
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cli_path.dart';
import 'user_path.dart';

class CliPathMaintenance {
  const CliPathMaintenance._();

  static const _stateFileName = 'cli-path.json';

  /// 确保当前发行包的 `cli` 目录在用户 PATH 里。
  ///
  /// 返回值表示是否真的改写了 PATH（用于界面提示）；任何不确定的情况都返回
  /// false 并保持系统原样，不能因为 PATH 维护失败影响应用启动。
  static Future<bool> ensure() async {
    if (!Platform.isWindows) return false;

    final exeDirectory = p.dirname(Platform.resolvedExecutable);
    if (isPortableInstall(exeDirectory) || isDevelopmentBuild(exeDirectory)) {
      return false;
    }

    final cliDirectory = p.join(exeDirectory, 'cli');
    if (!File(p.join(cliDirectory, 'pieblock-cli.exe')).existsSync()) {
      return false;
    }

    final current = UserPath.read();
    if (current == null) return false;

    final previousEntry = await _readPreviousEntry();
    final update = planCliPathUpdate(
      currentPath: current.value,
      cliDirectory: cliDirectory,
      previouslyAdded: previousEntry,
      directoryOwnedByPieBlock: _ownsPieBlock,
    );
    if (!shouldApplyPathUpdate(
      update: update,
      cliDirectory: cliDirectory,
      previouslyAdded: previousEntry,
    )) {
      return false;
    }

    if (!UserPath.write(update.path, type: current.type)) return false;

    UserPath.notifyEnvironmentChanged();
    await _writeState(cliDirectory);
    return true;
  }

  /// 便携单文件版：`%LOCALAPPDATA%\PIE-Block\portable\app\<id>\`。
  /// 目录是否属于 PIE-Block：同级有应用本体，或目录内已经有 CLI。
  static bool _ownsPieBlock(String cliDirectory) {
    final parent = p.dirname(cliDirectory);
    return File(p.join(parent, 'PIE-Block.exe')).existsSync() ||
        File(p.join(cliDirectory, 'pieblock-cli.exe')).existsSync() ||
        File(p.join(cliDirectory, 'pie-block.exe')).existsSync();
  }

  /// 上次由我们写入的条目；应用被挪动后靠它找到旧目录（即使旧目录已删除）。
  static Future<String?> _readPreviousEntry() async {
    try {
      final file = File(p.join(await _stateDirectory(), _stateFileName));
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map && decoded['schema'] == 1) {
        return decoded['entry']?.toString();
      }
    } catch (_) {
      // 状态文件损坏就当没有记录，按目录内容重新判断。
    }
    return null;
  }

  static Future<void> _writeState(String cliDirectory) async {
    try {
      final directory = await _stateDirectory();
      await File(p.join(directory, _stateFileName)).writeAsString(
        jsonEncode({
          'schema': 1,
          'entry': cliDirectory,
          'updatedAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );
    } catch (_) {
      // 记不住状态只会让下次多判断一次目录，不影响 PATH。
    }
  }

  static Future<String> _stateDirectory() async {
    final directory = await getApplicationSupportDirectory();
    await directory.create(recursive: true);
    return directory.path;
  }
}

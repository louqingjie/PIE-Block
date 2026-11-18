/// 用户 PATH 的纯逻辑：决定要不要把 CLI 目录加进去、哪些旧条目该删。
///
/// 这里不碰注册表、不碰文件系统，方便用普通单测覆盖边界情况。Windows 上
/// PATH 是分号分隔的目录列表；免安装发行版可能被解压到任意位置、被用户挪
/// 动，所以“谁是我们写的条目”必须按规则判断，不能按名字模糊匹配。
library;

/// 一次 PATH 规划的结果。
class CliPathUpdate {
  const CliPathUpdate({
    required this.path,
    required this.added,
    required this.removed,
  });

  /// 规划后的完整 PATH 值。
  final String path;

  /// 是否追加了当前 CLI 目录。
  final bool added;

  /// 被判定为“我们自己但已失效”的条目（原样保留，便于日志与测试）。
  final List<String> removed;

  /// 是否真的需要写回注册表。
  bool get changed => added || removed.isNotEmpty;
}

/// 判断 `cliDirectory` 是否应该出现在 PATH 里，并清理旧条目。
///
/// 规则：
/// - 目标目录已存在（大小写、斜杠、末尾分隔符不同也算）时保持原样；
/// - 重复的目标条目只保留第一个；
/// - 删除 [previouslyAdded] 记录的旧条目（应用挪动/升级后最常见的情况）；
/// - 删除“误把可执行文件路径当目录加进来”的条目；
/// - 删除形如 `...\cli` 且 [directoryOwnedByPieBlock] 判定属于本产品的目录；
/// - 其余条目原样保留、顺序不变。
///
/// [directoryOwnedByPieBlock] 由调用方检查目录内容（例如同级的
/// `PIE-Block.exe`），这样即使旧目录已经被删除也不会误判。
CliPathUpdate planCliPathUpdate({
  required String currentPath,
  required String cliDirectory,
  String? previouslyAdded,
  bool Function(String cliDirectory)? directoryOwnedByPieBlock,
}) {
  if (cliDirectory.trim().isEmpty) {
    throw ArgumentError.value(cliDirectory, 'cliDirectory', '不能为空');
  }

  final target = _normalize(cliDirectory);
  final recorded = previouslyAdded == null ? null : _normalize(previouslyAdded);
  final kept = <String>[];
  final removed = <String>[];
  var present = false;

  for (final raw in currentPath.split(';')) {
    final entry = _cleanEntry(raw);
    if (entry.isEmpty) continue;

    final normalized = _normalize(entry);
    if (normalized == target) {
      if (present) {
        removed.add(entry);
        continue;
      }
      present = true;
      kept.add(entry);
      continue;
    }

    if (recorded != null && normalized == recorded) {
      removed.add(entry);
      continue;
    }
    if (_isExecutableEntry(entry)) {
      removed.add(entry);
      continue;
    }
    if (_baseName(entry).toLowerCase() == 'cli' &&
        (directoryOwnedByPieBlock?.call(entry) ?? false)) {
      removed.add(entry);
      continue;
    }

    kept.add(entry);
  }

  if (!present) kept.add(cliDirectory);
  return CliPathUpdate(path: kept.join(';'), added: !present, removed: removed);
}

/// 便携单文件版的解压目录（`%LOCALAPPDATA%\PIE-Block\portable\app\<id>\`）。
///
/// 这类目录每次随版本变化，写进 PATH 只会积累失效条目，所以不管理。
bool isPortableInstall(String directory) => RegExp(
  r'[\\/]portable[\\/]app[\\/]',
  caseSensitive: false,
).hasMatch(directory);

/// 开发构建目录（`<repo>\build\windows\x64\runner\Release`），不写用户 PATH。
bool isDevelopmentBuild(String directory) => RegExp(
  r'[\\/]build[\\/]windows[\\/]',
  caseSensitive: false,
).hasMatch(directory);

/// 比较两个路径是否指向同一个目录（Windows 语义：忽略大小写、斜杠方向、
/// 末尾分隔符与成对引号）。
bool samePath(String a, String b) => _normalize(a) == _normalize(b);

/// 是否应该把 [update] 写回注册表。
///
/// 例外：同一个目录以前加过、现在却不在 PATH 里，说明用户主动删掉了它；
/// 这时不再加回去。换到新目录（解压到别处、移动安装位置）仍然会自动迁移。
bool shouldApplyPathUpdate({
  required CliPathUpdate update,
  required String cliDirectory,
  String? previouslyAdded,
}) {
  if (!update.changed) return false;
  if (update.added &&
      previouslyAdded != null &&
      samePath(previouslyAdded, cliDirectory)) {
    return false;
  }
  return true;
}

/// 去掉首尾空白和成对引号；其它内容保持原样，避免改写用户自己的路径写法。
String _cleanEntry(String raw) {
  var entry = raw.trim();
  while (entry.length >= 2 && entry.startsWith('"') && entry.endsWith('"')) {
    entry = entry.substring(1, entry.length - 1).trim();
  }
  return entry;
}

/// 比较用的归一化：统一分隔符、去掉末尾分隔符、忽略大小写。
String _normalize(String path) {
  var value = _cleanEntry(path).replaceAll('/', r'\');
  while (value.length > 3 && value.endsWith(r'\')) {
    value = value.substring(0, value.length - 1);
  }
  return value.toLowerCase();
}

String _baseName(String path) {
  final normalized = path.replaceAll('/', r'\');
  final index = normalized.lastIndexOf(r'\');
  return index < 0 ? normalized : normalized.substring(index + 1);
}

/// 用户把 `pieblock-cli.exe` 本身写进 PATH 是常见错误：PATH 只接受目录。
bool _isExecutableEntry(String entry) {
  final name = _baseName(entry).toLowerCase();
  return name == 'pieblock-cli.exe' || name == 'pie-block.exe';
}

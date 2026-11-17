/// 补丁引擎：在 `ProjectConfig.toJson()` 上做 `set` / `remove`，再用项目
/// 自己的 `fromJson` 重建，最后跑一遍校验器。
///
/// 这条路线的好处是默认值、枚举回退、旧格式迁移全部复用 `pieblock_core`，
/// 不在 MCP 里另写一份模型。代价是「不认识的枚举值会静默回退成默认值」，
/// 所以每次改写都做一次**往返校验**：重建后把目标路径读回来，和请求的值比对，
/// 不一致就报 `invalid_value`，而不是假装改成功了。
library;

import 'package:pieblock_core/pieblock_core.dart';

import '../protocol/mcp_message.dart';
import 'catalog.dart';

/// 用项目自己的 `ProjectDocument.fromJson` 重建配置：默认值、枚举回退与
/// 旧字段迁移全部复用 `pieblock_core`，不在 MCP 里另写一份模型。
ProjectConfig decodeConfig(String kind, Map<String, Object?> config) {
  ProjectKind? projectKind;
  for (final value in ProjectKind.values) {
    if (value.name == kind) projectKind = value;
  }
  if (projectKind == null) {
    throw PatchException(McpToolErrorCode.invalidValue, '未知项目类型 "$kind"');
  }
  try {
    return ProjectDocument.fromJson({
      'format_version': ProjectDocument.formatVersion,
      'project_kind': projectKind.name,
      'config': config,
    }).config;
  } on FormatException catch (error) {
    throw PatchException(
      McpToolErrorCode.invalidValue,
      '改完的配置无法被项目模型解析：${error.message}',
    );
  }
}

/// 补丁级错误：最终会变成 `tools/call` 的 `isError` 结果。
class PatchException implements Exception {
  const PatchException(this.code, this.message, {this.details = const {}});

  final String code;
  final String message;
  final Map<String, Object?> details;

  @override
  String toString() => 'PatchException($code): $message';
}

/// 一条补丁操作。
class PatchOp {
  const PatchOp.set(this.path, this.value) : op = 'set';
  const PatchOp.remove(this.path) : op = 'remove', value = null;

  final String op;
  final String path;
  final Object? value;

  bool get isRemove => op == 'remove';

  static PatchOp parse(Object? raw, int index) {
    if (raw is! Map) {
      throw PatchException(
        McpToolErrorCode.invalidValue,
        '第 $index 条操作不是对象',
      );
    }
    final json = Map<String, Object?>.from(raw);
    final op = json['op']?.toString();
    final path = json['path']?.toString();
    if (path == null || path.isEmpty) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '第 $index 条操作缺少 path',
      );
    }
    switch (op) {
      case 'set':
        if (!json.containsKey('value')) {
          throw PatchException(
            McpToolErrorCode.invalidValue,
            '第 $index 条 set 操作缺少 value；清空字段请显式写 null',
          );
        }
        return PatchOp.set(path, json['value']);
      case 'remove':
        return PatchOp.remove(path);
      default:
        throw PatchException(
          McpToolErrorCode.invalidValue,
          '第 $index 条操作的 op 只能是 set 或 remove，收到 "${op ?? ''}"',
        );
    }
  }

  Map<String, Object?> toJson() => {
    'op': op,
    'path': path,
    if (!isRemove) 'value': value,
  };
}

/// 路径里的一段：`modes[1]` → name `modes` + index 1。
class PathSegment {
  const PathSegment(this.name, this.index);

  final String name;
  final int? index;

  @override
  String toString() => index == null ? name : '$name[$index]';
}

final _segmentPattern = RegExp(r'^([A-Za-z_][A-Za-z0-9_]*)(?:\[(\d+)\])?$');

/// 解析路径；语法不合法统一报 `invalid_path`。
List<PathSegment> parsePath(String path) {
  if (path.isEmpty) {
    throw const PatchException(McpToolErrorCode.invalidPath, '路径不能为空');
  }
  final segments = <PathSegment>[];
  for (final raw in path.split('.')) {
    final match = _segmentPattern.firstMatch(raw);
    if (match == null) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '无法解析路径段 "$raw"（示例：chassis.pins.p64、modes[1].actions[0]）',
      );
    }
    segments.add(
      PathSegment(
        match.group(1)!,
        match.group(2) == null ? null : int.parse(match.group(2)!),
      ),
    );
  }
  return segments;
}

const _absent = Object();

/// 读路径；不存在时返回内部哨兵，需要调用方用 [isAbsent] 判断。
Object? readPath(Map<String, Object?> root, String path) {
  Object? cursor = root;
  for (final segment in parsePath(path)) {
    final next = _step(cursor, segment);
    if (identical(next, _absent)) return _absent;
    cursor = next;
  }
  return cursor;
}

bool isAbsent(Object? value) => identical(value, _absent);

/// 走一步：先按键取值，再按下标取元素。
///
/// 两件事写在同一步里，是因为路径语法就是 `name[index]`——`yaw[1]` 的父级
/// 是根对象，而不是「名字叫 yaw 的那个数组」。
Object? _step(Object? cursor, PathSegment segment) {
  if (cursor is! Map || !cursor.containsKey(segment.name)) return _absent;
  final child = cursor[segment.name];
  if (segment.index case final index?) {
    if (child is! List) return _absent;
    if (index < 0 || index >= child.length) return _absent;
    return child[index];
  }
  return child;
}

/// 深拷贝并归一化类型：Map 统一成 `Map<String, Object?>`，List 统一成
/// `List<Object?>`。归一化是必须的——`toJson()` 会产出
/// `List<Map<String, Object?>>` 这类具体泛型，直接写回会抛类型错误。
Object? deepCopy(Object? node) {
  if (node is Map) {
    return <String, Object?>{
      for (final entry in node.entries)
        entry.key.toString(): deepCopy(entry.value),
    };
  }
  if (node is List) return <Object?>[for (final item in node) deepCopy(item)];
  return node;
}

Map<String, Object?> deepCopyMap(Map<String, Object?> value) =>
    deepCopy(value)! as Map<String, Object?>;

/// 找到「装着最后一段的对象」：`modes[0].actions[1]` 的最后一段是
/// `actions[1]`，它的容器是 `modes[0]`。
Map<Object?, Object?> _containerOf(
  Map<String, Object?> root,
  List<PathSegment> head,
  String fullPath,
) {
  final container = head.isEmpty ? root : _navigate(root, head, fullPath);
  if (container is! Map) {
    throw PatchException(
      McpToolErrorCode.invalidPath,
      '$fullPath：父级不是对象',
    );
  }
  return container;
}

void _setAt(Map<String, Object?> root, String path, Object? value) {
  final segments = parsePath(path);
  final last = segments.removeLast();
  final container = _containerOf(root, segments, path);
  if (last.index case final index?) {
    final target = container[last.name];
    if (target is! List) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '$path：${last.name} 不是数组，不能用下标',
      );
    }
    if (index < 0 || index > target.length) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '$path：下标 $index 越界（当前长度 ${target.length}，只能追加到末尾）',
      );
    }
    if (index == target.length) {
      target.add(deepCopy(value));
    } else {
      target[index] = deepCopy(value);
    }
    return;
  }
  container[last.name] = deepCopy(value);
}

void _removeAt(Map<String, Object?> root, String path) {
  final segments = parsePath(path);
  final last = segments.removeLast();
  final container = _containerOf(root, segments, path);
  if (last.index case final index?) {
    final target = container[last.name];
    if (target is! List) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '$path：${last.name} 不是数组',
      );
    }
    if (index < 0 || index >= target.length) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '$path：下标 $index 越界（当前长度 ${target.length}）',
      );
    }
    target.removeAt(index);
    return;
  }
  if (!container.containsKey(last.name)) {
    throw PatchException(
      McpToolErrorCode.invalidPath,
      '$path：字段不存在，无法删除',
    );
  }
  container.remove(last.name);
}

Object? _navigate(
  Map<String, Object?> root,
  List<PathSegment> segments,
  String fullPath,
) {
  Object? cursor = root;
  for (final segment in segments) {
    final next = _step(cursor, segment);
    if (identical(next, _absent)) {
      throw PatchException(
        McpToolErrorCode.invalidPath,
        '$fullPath：路径不存在（在 "$segment" 处断开）',
      );
    }
    cursor = next;
  }
  return cursor;
}

/// 一条改动，用于人工审批时展示。
class McpDiffEntry {
  const McpDiffEntry({
    required this.path,
    required this.label,
    required this.before,
    required this.after,
    this.removed = false,
  });

  final String path;
  final String label;
  final Object? before;
  final Object? after;
  final bool removed;

  Map<String, Object?> toJson() => {
    'path': path,
    'label': label,
    'before': before,
    'after': after,
    if (removed) 'removed': true,
  };
}

/// 待审批的补丁。
class McpPatchPlan {
  McpPatchPlan({
    required this.patchId,
    required this.baseRevision,
    required this.config,
    required this.configJson,
    required this.diff,
    required this.issues,
    required this.ops,
    required this.createdAt,
  });

  final String patchId;

  /// 生成该补丁时项目所处的 revision。
  final int baseRevision;

  /// 重建后的配置对象，宿主直接交给 `updateConfig`。
  final ProjectConfig config;

  /// 重建后的配置 JSON，供往返校验与审计。
  final Map<String, Object?> configJson;

  final List<McpDiffEntry> diff;
  final List<ValidationIssue> issues;
  final List<PatchOp> ops;
  final DateTime createdAt;
}

/// 补丁缓存：短 TTL + 容量上限，取出即作废。
///
/// 取出即作废是刻意的：`apply_patch` 只认 `patchId` 不认 ops，如果允许重复
/// 提交，客户端的重试逻辑会把同一份改动写两次。
class PatchPlanCache {
  PatchPlanCache({
    this.capacity = 32,
    this.ttl = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final int capacity;
  final Duration ttl;
  final DateTime Function() _clock;

  /// 入缓存时间由缓存自己记，不与补丁的 `createdAt` 混用——TTL 属于缓存策略。
  final Map<String, ({McpPatchPlan plan, DateTime storedAt})> _plans = {};

  int get length => _plans.length;

  void put(McpPatchPlan plan) {
    _evictExpired();
    while (_plans.length >= capacity) {
      _plans.remove(_plans.keys.first);
    }
    _plans[plan.patchId] = (plan: plan, storedAt: _clock());
  }

  /// 取出并删除；过期或不存在返回 null。
  McpPatchPlan? take(String patchId) {
    _evictExpired();
    return _plans.remove(patchId)?.plan;
  }

  void clear() => _plans.clear();

  void _evictExpired() {
    final now = _clock();
    _plans.removeWhere(
      (_, entry) => now.difference(entry.storedAt) > ttl,
    );
  }
}

/// 补丁引擎。无状态之外只持有缓存，可被整个进程共享一份。
class PatchEngine {
  PatchEngine({PatchPlanCache? cache}) : cache = cache ?? PatchPlanCache();

  final PatchPlanCache cache;

  /// 进程级自增，保证同一微秒内创建的两个引擎也不会撞 id。
  static int _serial = 0;

  /// 生成待审批补丁。任何失败都抛 [PatchException]，不产生副作用。
  McpPatchPlan propose({
    required String kind,
    required Map<String, Object?> baseConfig,
    required int baseRevision,
    required List<Object?> rawOps,
  }) {
    if (rawOps.isEmpty) {
      throw const PatchException(McpToolErrorCode.emptyPatch, '补丁不能为空');
    }
    final ops = [
      for (var index = 0; index < rawOps.length; index += 1)
        PatchOp.parse(rawOps[index], index),
    ];

    // 1. 目录门禁：字段必须已知且可写。
    for (final op in ops) {
      if (op.path.contains('[*]')) {
        throw PatchException(
          McpToolErrorCode.invalidPath,
          '${op.path}：请用具体下标，不要写 [*]',
        );
      }
      final spec = McpFieldCatalog.lookup(op.path);
      if (spec == null) {
        throw PatchException(
          McpToolErrorCode.invalidPath,
          '${op.path}：未知字段。先用 pieblock_get_context 查可写字段',
        );
      }
      if (!spec.writable) {
        throw PatchException(
          McpToolErrorCode.notWritable,
          '${op.path}（${spec.label}）是只读字段',
        );
      }
    }

    // 2. 在副本上应用。
    final working = deepCopyMap(baseConfig);
    for (final op in ops) {
      if (op.isRemove) {
        _removeAt(working, op.path);
      } else {
        _setAt(working, op.path, op.value);
      }
    }

    // 3. 用项目自己的 fromJson 重建，并逐条核对真的生效了。
    final config = _decode(kind, working);
    final rebuilt = deepCopyMap(config.toJson());
    for (final op in ops) {
      if (op.isRemove) {
        if (!isAbsent(readPath(rebuilt, op.path))) {
          throw PatchException(
            McpToolErrorCode.invalidValue,
            '${op.path}：删除没有生效，该字段可能带默认值',
          );
        }
      } else {
        final actual = readPath(rebuilt, op.path);
        if (isAbsent(actual) || !_sameValue(op.value, actual)) {
          throw PatchException(
            McpToolErrorCode.invalidValue,
            '${op.path}：取值被项目模型拒绝或改写了（请求 ${_preview(op.value)}，'
            '实际 ${isAbsent(actual) ? '不存在' : _preview(actual)}）',
            details: {'requested': op.value},
          );
        }
        // 键名拼错的典型症状是「改完和改前一样」：对象比对放宽到子集之后，
        // 这一条是唯一还能兜住它的检查。
        final before = readPath(baseConfig, op.path);
        if (!isAbsent(before) && _sameValue(before, actual)) {
          throw PatchException(
            McpToolErrorCode.invalidValue,
            '${op.path}：改完与改前完全一致，可能字段名拼错、或本来就是该值。'
            '请用 pieblock_get_context 对照字段名',
          );
        }
      }
    }

    // 4. 记录改动与变更后的校验结果。
    final diff = <McpDiffEntry>[
      for (final op in ops)
        McpDiffEntry(
          path: op.path,
          label: McpFieldCatalog.lookup(op.path)?.label ?? op.path,
          before: readPath(baseConfig, op.path),
          after: op.isRemove ? null : readPath(rebuilt, op.path),
          removed: op.isRemove,
        ),
    ];

    final plan = McpPatchPlan(
      patchId: _nextPatchId(),
      baseRevision: baseRevision,
      config: config,
      configJson: rebuilt,
      diff: diff,
      issues: ProjectValidator.validate(config),
      ops: ops,
      createdAt: DateTime.now(),
    );
    cache.put(plan);
    return plan;
  }

  ProjectConfig _decode(String kind, Map<String, Object?> config) =>
      decodeConfig(kind, config);

  String _nextPatchId() {
    _serial += 1;
    final stamp = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'p$stamp-$_serial';
  }


  /// 比对「请求的值」与「重建后读回来的值」。
  ///
  /// 两条放宽是有意的：
  /// - 忽略 `id`：模型不给 id 时 `fromJson` 会补一个；
  /// - 请求里可以只写关心的键，其余键保留模型默认值：`toJson` 会把未填字段
  ///   都写出来，要求模型一字不差地复述全部 null 甚至默认值只会增加出错概率。
  ///
  /// 键名拼错这类问题的兜底不在这里，而在 `propose` 的「没产生任何差异」检查。
  static bool _sameValue(Object? requested, Object? actual) {
    if (requested is Map && actual is Map) {
      for (final entry in requested.entries) {
        if (entry.key == 'id') continue;
        if (!actual.containsKey(entry.key)) return false;
        if (!_sameValue(entry.value, actual[entry.key])) return false;
      }
      return true;
    }
    if (requested is List && actual is List) {
      if (requested.length != actual.length) return false;
      for (var index = 0; index < requested.length; index += 1) {
        if (!_sameValue(requested[index], actual[index])) return false;
      }
      return true;
    }
    if (requested is num && actual is num) return requested == actual;
    return requested == actual;
  }

  static String _preview(Object? value) {
    final text = value?.toString() ?? 'null';
    return text.length <= 60 ? text : '${text.substring(0, 57)}...';
  }
}

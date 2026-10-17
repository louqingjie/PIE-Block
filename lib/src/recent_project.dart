import 'package:flutter/foundation.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 首页「最近项目」里的一条记录。
///
/// 只记路径也足以打开项目，但首页要按类型显示图标，所以创建/打开项目时把
/// 文件里的 [ProjectKind] 一并记下来。旧版设置只存路径字符串，此时 [kind]
/// 为空，由加载设置的一方补读项目文件后回写；补读失败的条目继续显示通用
/// 文档图标，不影响打开。
@immutable
class RecentProject {
  const RecentProject({required this.path, this.kind});

  final String path;

  /// 项目文件里声明的类型；旧数据或补读失败时为空。
  final ProjectKind? kind;

  /// 解析设置里的一条 `recent` 记录：新格式是 `{path, kind}` 对象，旧格式
  /// 是纯路径字符串。无法识别或路径为空时返回 null，由调用方丢弃。
  static RecentProject? fromSetting(Object? entry) {
    if (entry is String) {
      final path = entry.trim();
      return path.isEmpty ? null : RecentProject(path: path);
    }
    if (entry is Map) {
      final path = entry['path']?.toString().trim() ?? '';
      if (path.isEmpty) return null;
      final kind = ProjectKind.values.asNameMap()[entry['kind']?.toString()];
      return RecentProject(path: path, kind: kind);
    }
    return null;
  }

  /// 写回设置的 JSON 形式；类型未知时不写 `kind`，留待下次加载补读。
  Map<String, Object?> toSetting() {
    final json = <String, Object?>{'path': path};
    final kind = this.kind;
    if (kind != null) json['kind'] = kind.name;
    return json;
  }

  RecentProject withKind(ProjectKind kind) =>
      RecentProject(path: path, kind: kind);
}

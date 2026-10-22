import 'package:material_ui/material_ui.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 项目类型在界面上的统一呈现。
///
/// 「新建项目」的分段按钮和首页「最近项目」共用这一份映射：同一类型在两个
/// 地方换图标或换叫法，用户会误以为是两种不同的项目。
extension ProjectKindUi on ProjectKind {
  /// 与「新建项目」分段按钮一致的图标；最近项目按类型沿用同一套。
  IconData get icon => switch (this) {
    ProjectKind.infantry => Icons.sports_esports,
    ProjectKind.engineer => Icons.precision_manufacturing,
    ProjectKind.debug => Icons.science_outlined,
    ProjectKind.music => Icons.piano,
  };

  /// 分段按钮里的短名称。
  String get label => switch (this) {
    ProjectKind.infantry => '步兵',
    ProjectKind.engineer => '工程',
    ProjectKind.debug => '调试',
    ProjectKind.music => '音乐',
  };
}

/// 最近项目里类型未知时（旧数据补读失败、文件损坏等）退回通用文档图标，
/// 至少还能从标题和路径看出这是一个项目文件。
IconData recentProjectIcon(ProjectKind? kind) =>
    kind?.icon ?? Icons.description_outlined;

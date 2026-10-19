import 'package:flutter/widgets.dart';

/// M3 动效时长；系统开启“减少动态效果”时返回零。
///
/// 用于所有显式过渡动画，保证无障碍设置下瞬时完成。
Duration m3Duration(BuildContext context, Duration token) =>
    MediaQuery.disableAnimationsOf(context) ? Duration.zero : token;

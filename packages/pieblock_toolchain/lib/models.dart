/// 编译链路里不依赖 dart:io 的那部分模型。
///
/// 给 Web 版这类不能引入本地编译能力的场景用：主 barrel
/// `pieblock_toolchain.dart` 会把 builder / hex_validator 等 dart:io 实现
/// 一起带进来，Web 上编译不过。
library;

export 'src/models.dart';

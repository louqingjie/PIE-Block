/// 用户 PATH 访问入口：Windows 走注册表，其它平台是空实现。
library;

export 'user_path_stub.dart' if (dart.library.io) 'user_path_io.dart';
export 'user_path_value.dart';

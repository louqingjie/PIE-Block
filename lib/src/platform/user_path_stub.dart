/// 非 Windows 平台（含 Web）的用户 PATH 访问：一律不做事。
///
/// 条件导入保证 `dart:ffi` 不会进入 Web 构建。
library;

import 'user_path_value.dart';

class UserPath {
  const UserPath._();

  static UserPathValue? read({
    String subKey = 'Environment',
    String valueName = 'Path',
  }) => null;

  static bool write(
    String value, {
    int type = 2,
    String subKey = 'Environment',
    String valueName = 'Path',
  }) => false;

  static void notifyEnvironmentChanged() {}
}

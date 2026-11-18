/// 非 IO 平台（Web）的 PATH 维护：不做事。
library;

class CliPathMaintenance {
  const CliPathMaintenance._();

  static Future<bool> ensure() async => false;
}

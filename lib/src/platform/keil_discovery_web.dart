/// 浏览器里没有 Keil，也不可能有——所有查询都返回「没找到」。
class KeilInstallation {
  const KeilInstallation({required this.root});
  final String root;
}

class ToolchainDiscovery {
  const ToolchainDiscovery();

  Future<KeilInstallation?> resolveKeil({String? configuredPath}) async => null;

  Future<KeilInstallation?> validateKeil(String root) async => null;

  Future<bool> applyKeilLicense(
    KeilInstallation installation,
    String key,
  ) async => false;
}

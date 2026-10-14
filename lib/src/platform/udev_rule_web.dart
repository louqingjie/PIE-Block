/// 网页版没有本地 udev，也没有 pkexec——所有查询都当作「已安装」，安装直接失败。
const String kUdevRuleTargetPath = '/etc/udev/rules.d/70-pieblock-hid.rules';
const String kUdevRuleAssetPath = 'linux/udev/70-pieblock-hid.rules';
const String kUdevInstallScript = '';

bool udevRuleInstalled({String path = kUdevRuleTargetPath}) => true;

enum UdevInstallOutcome {
  success,
  installedNoUdevadm,
  canceled,
  notAuthorized,
  pkexecMissing,
  timedOut,
  failed,
}

class UdevInstallResult {
  const UdevInstallResult(this.outcome, {this.exitCode, this.stderrText = ''});

  final UdevInstallOutcome outcome;
  final int? exitCode;
  final String stderrText;

  bool get ok =>
      outcome == UdevInstallOutcome.success ||
      outcome == UdevInstallOutcome.installedNoUdevadm;
}

class UdevRuleInstaller {
  const UdevRuleInstaller();

  Future<UdevInstallResult> install() async => const UdevInstallResult(
    UdevInstallOutcome.failed,
    stderrText: '网页版不支持安装 udev 规则',
  );
}

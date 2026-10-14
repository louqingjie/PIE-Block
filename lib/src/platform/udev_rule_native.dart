import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// 目标规则文件（与 tools/install_udev_rules.sh 保持一致）。
const String kUdevRuleTargetPath = '/etc/udev/rules.d/70-pieblock-hid.rules';

/// 规则内容来源：与脚本、打包脚本共用的同一份文件（pubspec 里声明为资产）。
const String kUdevRuleAssetPath = 'linux/udev/70-pieblock-hid.rules';

/// 交给 root shell 执行的安装脚本。规则内容 base64 后作为 `$1` 传入，不落临时
/// 文件；写规则 + 重载 + 触发一次完成，保证只弹一次系统授权对话框。
///
/// `exit 10` 用于区分「规则已写但环境里没有 udevadm」（非 systemd 发行版）。
const String kUdevInstallScript = r'''
set -eu
target=/etc/udev/rules.d/70-pieblock-hid.rules
mkdir -p /etc/udev/rules.d
printf %s "$1" | base64 -d > "$target"
chmod 0644 "$target"
if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload
  udevadm trigger --subsystem-match=hidraw
else
  exit 10
fi
''';

/// 规则是否已安装。`/etc/udev/rules.d/` 全局可读，无需 root 即可判断。
///
/// 非 Linux 平台恒为 true——对应 UI 只在 Linux 显示，这里返回 true 即让其隐藏。
bool udevRuleInstalled({String path = kUdevRuleTargetPath}) {
  if (!Platform.isLinux) return true;
  return File(path).existsSync();
}

typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);
typedef UdevRuleLoader = Future<String> Function();

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
  const UdevRuleInstaller({
    this.loadRule = _loadRuleFromAsset,
    this.runner = _runProcess,
  });

  final UdevRuleLoader loadRule;
  final ProcessRunner runner;

  /// 通过 pkexec 弹出系统授权对话框安装规则。可注入 [loadRule]/[runner] 以便测试。
  Future<UdevInstallResult> install() async {
    if (!Platform.isLinux) {
      return const UdevInstallResult(
        UdevInstallOutcome.failed,
        stderrText: '仅支持 Linux 桌面版',
      );
    }

    final String rule;
    try {
      rule = await loadRule();
    } catch (error) {
      return UdevInstallResult(UdevInstallOutcome.failed, stderrText: '$error');
    }

    final ProcessResult result;
    try {
      result = await runner('pkexec', [
        '/bin/sh',
        '-c',
        kUdevInstallScript,
        'pieblock-udev',
        base64Encode(utf8.encode(rule)),
      ]).timeout(const Duration(minutes: 2));
    } on TimeoutException {
      return const UdevInstallResult(UdevInstallOutcome.timedOut);
    } on ProcessException catch (error) {
      // pkexec 不存在（未装 polkit）时 Process.run 抛 ProcessException。
      return UdevInstallResult(
        UdevInstallOutcome.pkexecMissing,
        stderrText: error.message,
      );
    } catch (error) {
      return UdevInstallResult(UdevInstallOutcome.failed, stderrText: '$error');
    }

    final stderrText = '${result.stderr ?? ''}'.trim();
    final outcome = switch (result.exitCode) {
      0 => UdevInstallOutcome.success,
      10 => UdevInstallOutcome.installedNoUdevadm,
      126 => UdevInstallOutcome.canceled,
      127 => UdevInstallOutcome.notAuthorized,
      _ => UdevInstallOutcome.failed,
    };
    return UdevInstallResult(
      outcome,
      exitCode: result.exitCode,
      stderrText: stderrText,
    );
  }
}

Future<String> _loadRuleFromAsset() =>
    rootBundle.loadString(kUdevRuleAssetPath);

Future<ProcessResult> _runProcess(String executable, List<String> arguments) =>
    Process.run(
      executable,
      arguments,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );

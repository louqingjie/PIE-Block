import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'platform/udev_rule.dart';

/// Linux 桌面版的 hidraw 授权规则状态。非 Linux 平台 `installed` 恒为 true，
/// 相关 UI 不会出现。
class UdevRuleState {
  const UdevRuleState({
    required this.installed,
    this.installing = false,
    this.lastResult,
  });

  final bool installed;
  final bool installing;
  final UdevInstallResult? lastResult;

  UdevRuleState copyWith({
    bool? installed,
    bool? installing,
    UdevInstallResult? lastResult,
  }) => UdevRuleState(
    installed: installed ?? this.installed,
    installing: installing ?? this.installing,
    lastResult: lastResult ?? this.lastResult,
  );
}

final udevRuleControllerProvider =
    NotifierProvider<UdevRuleController, UdevRuleState>(UdevRuleController.new);

class UdevRuleController extends Notifier<UdevRuleState> {
  @override
  UdevRuleState build() => UdevRuleState(installed: udevRuleInstalled());

  /// 重新读取规则文件是否存在。页面初始化、点「重新检测」、安装成功后调用。
  void refresh() {
    state = state.copyWith(installed: udevRuleInstalled());
  }

  /// 通过 pkexec 弹出系统授权对话框安装规则，完成后重新检测。
  Future<UdevInstallResult> install() async {
    if (state.installing) {
      return state.lastResult ??
          const UdevInstallResult(UdevInstallOutcome.failed);
    }
    state = state.copyWith(installing: true);
    final result = await const UdevRuleInstaller().install();
    state = UdevRuleState(
      installed: udevRuleInstalled(),
      installing: false,
      lastResult: result,
    );
    return result;
  }
}

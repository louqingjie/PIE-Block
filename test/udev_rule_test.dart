import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/platform/udev_rule_native.dart';

/// pkexec 的真实弹窗/授权无法在单测里跑，所以这里把过程注入成假的：
/// 钉死「退出码 → 结果」映射、argv 形状、规则内容完整送达，以及资产本身。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProcessRunner runnerReturning(int exitCode, {String stderr = ''}) =>
      (executable, arguments) async =>
          ProcessResult(1, exitCode, '', stderr);

  group('UdevRuleInstaller 退出码映射', () {
    for (final (code, outcome) in <(int, UdevInstallOutcome)>[
      (0, UdevInstallOutcome.success),
      (10, UdevInstallOutcome.installedNoUdevadm),
      (126, UdevInstallOutcome.canceled),
      (127, UdevInstallOutcome.notAuthorized),
      (5, UdevInstallOutcome.failed),
    ]) {
      test('退出码 $code → ${outcome.name}', () async {
        final installer = UdevRuleInstaller(
          loadRule: () async => 'RULE\n',
          runner: runnerReturning(code, stderr: 'boom'),
        );
        final result = await installer.install();
        expect(result.outcome, outcome);
        expect(result.exitCode, code);
        if (code == 5) expect(result.stderrText, 'boom');
      });
    }

    test('pkexec 不存在（ProcessException）→ pkexecMissing', () async {
      final installer = UdevRuleInstaller(
        loadRule: () async => 'RULE\n',
        runner: (executable, arguments) async =>
            throw ProcessException('pkexec', arguments, 'not found'),
      );
      final result = await installer.install();
      expect(result.outcome, UdevInstallOutcome.pkexecMissing);
    });
  }, skip: !Platform.isLinux);

  group('argv 与脚本', () {
    test('argv 形状正确，规则以 base64 完整传入', () async {
      final calls = <List<String>>[];
      const rule = '# 规则\nKERNEL=="hidraw*"\n';
      final installer = UdevRuleInstaller(
        loadRule: () async => rule,
        runner: (executable, arguments) async {
          calls.add([executable, ...arguments]);
          return ProcessResult(1, 0, '', '');
        },
      );
      final result = await installer.install();
      expect(result.outcome, UdevInstallOutcome.success);

      expect(calls, hasLength(1));
      final argv = calls.single;
      expect(argv[0], 'pkexec');
      expect(argv.sublist(1, 4), ['/bin/sh', '-c', kUdevInstallScript]);
      expect(argv[4], 'pieblock-udev');
      expect(base64Decode(argv[5]), utf8.encode(rule));
    });

    test('安装脚本包含写规则与重载 udev 的关键步骤', () {
      expect(kUdevInstallScript, contains(kUdevRuleTargetPath));
      expect(kUdevInstallScript, contains('udevadm control --reload'));
      expect(
        kUdevInstallScript,
        contains('udevadm trigger --subsystem-match=hidraw'),
      );
      expect(kUdevInstallScript, contains('exit 10'));
    });
  }, skip: !Platform.isLinux);

  test('udevRuleInstalled 按规则文件是否存在判断', () {
    final dir = Directory.systemTemp.createTempSync('pieblock-udev-test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final path = '${dir.path}/70-pieblock-hid.rules';
    expect(udevRuleInstalled(path: path), isFalse);
    File(path).writeAsStringSync('x');
    expect(udevRuleInstalled(path: path), isTrue);
  }, skip: !Platform.isLinux);

  test('规则资产内容完整（pubspec 与文件同步）', () async {
    final raw = await rootBundle.loadString(kUdevRuleAssetPath);
    expect(raw, contains('idVendor}=="34bf"'));
    expect(raw, contains('idProduct}=="1001"'));
    expect(raw, contains('TAG+="uaccess"'));
  });
}

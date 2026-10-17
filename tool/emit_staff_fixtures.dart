// 生成/校验固件主机对拍 fixture。
//
// 产物：
//   stc32g_sdcc/tests/staff/fixtures/staff_fixture.h
//   stc32g_sdcc/tests/staff/fixtures/golden/<scenario>_<frame:03d>.bin
//
// 生成逻辑在 `tool/staff_fixtures.dart`（根目录测试 test/staff_fixture_test.dart
// 复用同一份逻辑，防止 fixture 与 Dart 渲染器/固件数据表漂移）。
//
// 用法：
//   dart run tool/emit_staff_fixtures.dart            # 重新生成 fixture
//   dart run tool/emit_staff_fixtures.dart --check    # 只校验（CI/提交前）
//   dart run tool/emit_staff_fixtures.dart --out <dir>  # 输出到临时目录（调试）

import 'dart:io';

import 'staff_fixtures.dart';

String? _fixtureRootOverride;

void _printUsage() {
  stdout.writeln('''固件主机对拍 fixture 生成器

用法：
  dart run tool/emit_staff_fixtures.dart            重新生成 fixture（写盘）
  dart run tool/emit_staff_fixtures.dart --check    只校验已提交 fixture 是否漂移
  dart run tool/emit_staff_fixtures.dart --out <dir>  指定输出/校验目录（默认仓库内路径）

产物：$staffFixtureRelativeDir/
  $staffFixtureHeaderName
  $staffFixtureGoldenDirName/<scenario>_<frame:03d>.bin（每帧 1024 字节）''');
}

Future<int> _checkFixtures() async {
  final bundle = StaffFixtureBundle.generate();
  final drifts = await verifyStaffFixtures(
    bundle,
    fixtureRootPath: _fixtureRootOverride ?? staffFixtureRootPath(),
  );
  if (drifts.isEmpty) {
    stdout.writeln(
      'fixture check OK：${bundle.scenarioCount} 个场景 / '
      '${bundle.frameCount} 帧与生成逻辑一致'
      '（${bundle.frameCount * 1024} 字节 golden）',
    );
    return 0;
  }
  stderr.writeln('fixture check 失败：已提交 fixture 与生成逻辑不一致');
  for (final drift in drifts) {
    stderr.writeln('  - $drift');
  }
  stderr.writeln('请运行 `dart run tool/emit_staff_fixtures.dart` 重新生成后再提交。');
  return 1;
}

Future<int> _writeFixtures() async {
  final bundle = StaffFixtureBundle.generate();
  final result = await writeStaffFixtures(
    bundle,
    fixtureRootPath: _fixtureRootOverride ?? staffFixtureRootPath(),
  );
  stdout.writeln(
    '已生成 fixture：${result.scenarioCount} 个场景 / ${result.frameCount} 帧',
  );
  stdout.writeln(
    '  ${_fixtureRootOverride ?? staffFixtureRootPath()}/'
    '$staffFixtureHeaderName',
  );
  stdout.writeln(
    '  ${_fixtureRootOverride ?? staffFixtureRootPath()}/'
    '$staffFixtureGoldenDirName/（每帧 1024 字节）',
  );
  if (result.removedStale > 0) {
    stdout.writeln('  已清理 ${result.removedStale} 个多余旧帧');
  }
  return 0;
}

Future<void> main(List<String> args) async {
  var check = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    switch (arg) {
      case '--check':
        check = true;
      case '--out':
        if (i + 1 >= args.length) {
          stderr.writeln('参数 --out 缺少取值');
          exitCode = 64;
          return;
        }
        _fixtureRootOverride = args[++i];
      case '--help':
      case '-h':
        _printUsage();
        return;
      default:
        stderr.writeln('未知参数 $arg（--help 查看用法）');
        exitCode = 64;
        return;
    }
  }

  try {
    exitCode = check ? await _checkFixtures() : await _writeFixtures();
  } on Object catch (error) {
    stderr.writeln('fixture ${check ? '校验' : '生成'}失败：$error');
    exitCode = 1;
  }
}

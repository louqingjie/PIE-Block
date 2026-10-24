import 'dart:io';

import 'package:pieblock_core/pieblock_core.dart';
import 'package:test/test.dart';

// 排列组合 + 编译 + 运行时执行三阶段验证，复用 tool/verify_runtime.dart 的
// 配置枚举与场景定义。gcc 不可用的环境下自动跳过编译/执行阶段。
import '../tool/verify_runtime.dart' as v;

void main() {
  final variants = [
    ...v.infantryVariants(),
    ...v.engineerVariants(),
    ...v.randomSamples(120, 20261024),
  ];
  final gcc = v.hasGcc();

  test('排列组合配置全部合法且结构检查通过', () {
    expect(variants, isNotEmpty);
    for (final (name, config) in variants) {
      final errors = ProjectValidator.validate(config)
          .where((issue) => issue.severity == IssueSeverity.error)
          .toList();
      expect(
        errors,
        isEmpty,
        reason: '$name 应为合法配置，但有错误：'
            '${errors.map((issue) => issue.message).join('；')}',
      );
      final source = CodeGenerator.generate(config);
      expect(
        v.structuralIssues(name, source),
        isEmpty,
        reason: '$name 生成的源码应通过结构检查',
      );
    }
  }, timeout: const Timeout(Duration(minutes: 2)));

  group('gcc 编译冒烟', skip: gcc ? false : '本机没有 gcc，跳过编译验证', () {
    test('所有排列组合源码 -fsyntax-only 通过', () async {
      final dir = await v.verifyWorkRoot('test-gen/');
      for (final (name, config) in variants) {
        final source = CodeGenerator.generate(config);
        final file = File('${dir.path}$name.c');
        await file.writeAsString(v.prepareSource(source));
        final result = Process.runSync('gcc', [
          '-std=c99',
          '-fsyntax-only',
          '-w',
          '-I',
          v.stubIncludeDir(),
          file.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '$name 编译失败：\n${result.stderr}',
        );
      }
    }, timeout: const Timeout(Duration(minutes: 5)));
  });

  group('运行时执行场景', skip: gcc ? false : '本机没有 gcc，跳过执行验证', () {
    for (final scenario in v.scenarios()) {
      test(scenario.name, () async {
        final summary = await v.runScenario(scenario);
        expect(
          summary.failures,
          isEmpty,
          reason: '${scenario.name} 场景断言失败：\n'
              '${summary.failures.map((f) => '  - $f').join('\n')}',
        );
      }, timeout: const Timeout(Duration(minutes: 2)));
    }
  });
}

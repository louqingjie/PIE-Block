import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/version.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

/// 只持有一份文档，不读写设置与磁盘。
class _DocController extends AppController {
  _DocController(this.document);

  final ProjectDocument document;

  @override
  AppState build() => AppState(document: document);
}

List<String> stepsOf(ProjectKind kind) {
  final container = ProviderContainer(
    overrides: [
      appControllerProvider.overrideWith(
        () => _DocController(ProjectDocument.create(kind)),
      ),
    ],
  );
  final steps = container.read(appControllerProvider.notifier).stepIds(kind);
  container.dispose();
  return steps;
}

void main() {
  final allSteps = {
    for (final kind in ProjectKind.values) ...stepsOf(kind),
  };

  test('字段目录里的步骤 id 都是真实存在的向导步骤', () {
    final unknown = {
      for (final spec in McpFieldCatalog.specs)
        if (!allSteps.contains(spec.stepId)) spec.stepId,
    };
    expect(unknown, isEmpty, reason: '这些 stepId 在 AppController.stepIds 里不存在：$unknown');
  });

  test('每个内容步骤都至少有一个可读字段', () {
    // review / code / deploy 是结果页，没有可编辑字段，不算。
    const resultSteps = {'review', 'code', 'deploy'};
    final covered = {for (final spec in McpFieldCatalog.specs) spec.stepId};
    final missing = [
      for (final step in allSteps)
        if (!resultSteps.contains(step) && !covered.contains(step)) step,
    ];
    expect(missing, isEmpty, reason: '这些步骤没有任何目录字段：$missing');
  });

  test('每类项目都能从目录里读到字段', () {
    for (final kind in ProjectKind.values) {
      final steps = stepsOf(kind);
      final fields = [
        for (final spec in McpFieldCatalog.specs)
          if (steps.contains(spec.stepId)) spec,
      ];
      expect(fields, isNotEmpty, reason: '${kind.name} 没有任何可读字段');
    }
  });

  test('AppState.revision 只在写配置时递增，且不写进存档', () {
    final container = ProviderContainer(
      overrides: [
        appControllerProvider.overrideWith(
          () => _DocController(ProjectDocument.create(ProjectKind.infantry)),
        ),
      ],
    );
    addTearDown(container.dispose);
    final notifier = container.read(appControllerProvider.notifier);
    final document = container.read(appControllerProvider).document!;

    expect(container.read(appControllerProvider).revision, 0);
    notifier.updateConfig(document.config);
    expect(container.read(appControllerProvider).revision, 1);

    // revision 只在内存里：存档键里不能出现它。
    expect(document.toJson().keys, isNot(contains('revision')));
  });

  test('版本号与 pubspec.yaml 一致', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final line = pubspec
        .split('\n')
        .firstWhere((line) => line.startsWith('version:'));
    final declared = line.split(':')[1].trim().split('+').first;
    expect(appVersion, declared);
  });
}

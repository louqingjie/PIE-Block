import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'support/valid_project.dart';

class _TestController extends AppController {
  @override
  AppState build() => const AppState();

  @override
  Future<Map<String, Object?>?> readStoredSettings() async => null;

  @override
  Future<void> writeStoredSettings(Map<String, Object?> values) async {}
}

ProviderContainer _containerFor(AppController controller) => ProviderContainer(
  overrides: [appControllerProvider.overrideWith(() => controller)],
);

Object? _speedInFile(String path) {
  final json = jsonDecode(File(path).readAsStringSync()) as Map;
  return ((json['config'] as Map)['chassis'] as Map)['normal_speed'];
}

void main() {
  test('应用提案：写入工程、更新内存状态，并可一步撤销', () async {
    final temp = Directory.systemTemp.createTempSync('pieblock-apply-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}${Platform.pathSeparator}robot.pieproj';
    File(path).writeAsStringSync(jsonEncode(validInfantryDocument().toJson()));

    final container = _containerFor(_TestController());
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    expect(await controller.openProject(path), isTrue);
    final candidate = ProjectDocument.fromJson(projectJsonWithSpeed(4321));
    expect(await controller.applyProposal(candidate.config), isTrue);

    expect(_speedInFile(path), 4321);
    final config =
        container.read(appControllerProvider).document!.config
            as InfantryConfig;
    expect(config.chassis.normalSpeed, 4321);

    expect(await controller.undoProposal(), isTrue);
    expect(_speedInFile(path), 4000);
    final restored =
        container.read(appControllerProvider).document!.config
            as InfantryConfig;
    expect(restored.chassis.normalSpeed, 4000);
  });

  test('没有打开工程时应用提案：返回 false', () async {
    final container = _containerFor(_TestController());
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    final candidate = ProjectDocument.fromJson(projectJsonWithSpeed(4321));
    expect(await controller.applyProposal(candidate.config), isFalse);
    expect(await controller.undoProposal(), isFalse);
  });

  test('用户再次编辑后，撤销快照失效', () async {
    final temp = Directory.systemTemp.createTempSync('pieblock-apply-');
    addTearDown(() => temp.deleteSync(recursive: true));
    final path = '${temp.path}${Platform.pathSeparator}robot.pieproj';
    File(path).writeAsStringSync(jsonEncode(validInfantryDocument().toJson()));

    final container = _containerFor(_TestController());
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);
    expect(await controller.openProject(path), isTrue);
    final candidate = ProjectDocument.fromJson(projectJsonWithSpeed(4321));
    expect(await controller.applyProposal(candidate.config), isTrue);

    controller.updateConfig(candidate.config);
    await controller.saveNow();
    expect(await controller.undoProposal(), isFalse);
  });
}

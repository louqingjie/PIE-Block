import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/recent_project.dart';
import 'package:pieblock_core/pieblock_core.dart';

/// 内存设置存储：让设置恢复流程可以在测试里完整跑一遍，不碰真实设置文件。
class _MemorySettings {
  _MemorySettings(this.values);

  Map<String, Object?>? values;
  int writes = 0;
}

class _SettingsController extends AppController {
  _SettingsController(this.store);

  final _MemorySettings store;

  /// 不让 build 自动加载，由测试 await loadSettings() 控制时序。
  @override
  AppState build() => const AppState();

  @override
  Future<Map<String, Object?>?> readStoredSettings() async => store.values;

  @override
  Future<void> writeStoredSettings(Map<String, Object?> values) async {
    store.values = values;
    store.writes += 1;
  }
}

/// 模拟「设置还在读，用户已经打开了一个项目」。
class _RacingSettingsController extends _SettingsController {
  _RacingSettingsController(super.store, this.project);

  final RecentProject project;

  @override
  Future<Map<String, Object?>?> readStoredSettings() async {
    state = state.copyWith(recentProjects: [project]);
    return super.readStoredSettings();
  }
}

/// 模拟「设置还在读，用户已经切换了主题」。
class _RacingThemeController extends _SettingsController {
  _RacingThemeController(super.store);

  @override
  Future<Map<String, Object?>?> readStoredSettings() async {
    state = state.copyWith(themeMode: ThemeMode.light);
    return super.readStoredSettings();
  }
}

ProviderContainer _containerFor(AppController controller) => ProviderContainer(
  overrides: [appControllerProvider.overrideWith(() => controller)],
);

Future<String> _writeProject(
  Directory directory,
  String name,
  ProjectKind kind,
) async {
  final path = '${directory.path}${Platform.pathSeparator}$name.pieproj';
  await const ProjectRepository().save(
    path,
    ProjectDocument.create(name, kind),
  );
  return path;
}

/// 设置写盘是串行异步队列，断言写入结果前先等它落地。
Future<void> _waitForWrites(_MemorySettings store, int count) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (store.writes < count) {
    if (DateTime.now().isAfter(deadline)) {
      fail('等待设置写盘超时：writes=${store.writes}，期望 $count');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// 首页「最近项目」要按类型显示图标，前提是设置里能可靠地存下类型；
/// 这里把新旧两种设置格式、旧数据迁移以及加载期间的并发操作固定住。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('RecentProject 设置序列化', () {
    test('新格式记录路径与类型，并能原样写回', () {
      final project = RecentProject.fromSetting({
        'path': r'C:\projects\robot.pieproj',
        'kind': 'engineer',
      });

      expect(project, isNotNull);
      expect(project!.path, r'C:\projects\robot.pieproj');
      expect(project.kind, ProjectKind.engineer);
      expect(project.toSetting(), {
        'path': r'C:\projects\robot.pieproj',
        'kind': 'engineer',
      });
    });

    test('旧格式纯路径字符串可解析，类型留空等待补读', () {
      final project = RecentProject.fromSetting(r'C:\projects\old.pieproj');

      expect(project, isNotNull);
      expect(project!.path, r'C:\projects\old.pieproj');
      expect(project.kind, isNull);
      // 类型没补读出来时不要写 kind，避免把「未知」固化成某个类型。
      expect(project.toSetting(), {'path': r'C:\projects\old.pieproj'});
    });

    test('未知类型名、空路径和非字符串条目不会造出脏记录', () {
      final unknownKind = RecentProject.fromSetting({
        'path': 'tank.pieproj',
        'kind': 'tank',
      });
      expect(unknownKind, isNotNull);
      expect(unknownKind!.kind, isNull);

      expect(RecentProject.fromSetting({'path': '   '}), isNull);
      expect(RecentProject.fromSetting({'kind': 'infantry'}), isNull);
      expect(RecentProject.fromSetting(42), isNull);
      expect(RecentProject.fromSetting(null), isNull);
    });
  });

  group('设置恢复与旧格式迁移', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('pieblock_settings_');
    });

    tearDown(() => directory.delete(recursive: true));

    String pathOf(String name) =>
        '${directory.path}${Platform.pathSeparator}$name.pieproj';

    test('旧版纯路径设置补读类型并回写，缺失文件剔除，content:// 保留', () async {
      final engineerPath = await _writeProject(
        directory,
        'engineer',
        ProjectKind.engineer,
      );
      final musicPath = await _writeProject(
        directory,
        'music',
        ProjectKind.music,
      );
      final missingPath = pathOf('missing');
      const contentPath = 'content://documents/remote.pieproj';
      final store = _MemorySettings({
        'theme': 'dark',
        'recent': [missingPath, engineerPath, contentPath, musicPath],
      });
      final controller = _SettingsController(store);
      final container = _containerFor(controller);
      addTearDown(container.dispose);

      await container.read(appControllerProvider.notifier).loadSettings();
      await _waitForWrites(store, 1);

      final state = container.read(appControllerProvider);
      expect(state.recentProjects.map((project) => project.path), [
        engineerPath,
        contentPath,
        musicPath,
      ]);
      expect(state.recentProjects.map((project) => project.kind), [
        ProjectKind.engineer,
        null,
        ProjectKind.music,
      ]);
      expect(state.themeMode, ThemeMode.dark);
      // 迁移后写回新格式：已知类型写成 kind，未知类型保持只有 path。
      expect(store.values!['recent'], [
        {'path': engineerPath, 'kind': 'engineer'},
        {'path': contentPath},
        {'path': musicPath, 'kind': 'music'},
      ]);
    });

    test('项目文件损坏时保留条目、类型未知且不回写', () async {
      final corruptPath = pathOf('corrupt');
      await File(corruptPath).writeAsString('{not json');
      final store = _MemorySettings({
        'recent': [corruptPath],
      });
      final controller = _SettingsController(store);
      final container = _containerFor(controller);
      addTearDown(container.dispose);

      await container.read(appControllerProvider.notifier).loadSettings();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(appControllerProvider);
      expect(state.recentProjects.single.path, corruptPath);
      expect(state.recentProjects.single.kind, isNull);
      // 没有可迁移的类型，不应触发写盘。
      expect(store.writes, 0);
    });

    test('新格式设置直接恢复类型，不重复读盘写盘', () async {
      final musicPath = await _writeProject(
        directory,
        'music',
        ProjectKind.music,
      );
      final store = _MemorySettings({
        'recent': [
          {'path': musicPath, 'kind': 'music'},
        ],
      });
      final controller = _SettingsController(store);
      final container = _containerFor(controller);
      addTearDown(container.dispose);

      await container.read(appControllerProvider.notifier).loadSettings();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(appControllerProvider);
      expect(state.recentProjects.single.path, musicPath);
      expect(state.recentProjects.single.kind, ProjectKind.music);
      expect(store.writes, 0);
    });

    test('加载期间打开的项目与设置条目合并，主题仍正常恢复', () async {
      final loadedPath = await _writeProject(
        directory,
        'loaded',
        ProjectKind.infantry,
      );
      final raceProject = RecentProject(
        path: pathOf('race'),
        kind: ProjectKind.debug,
      );
      final store = _MemorySettings({
        'theme': 'dark',
        'recent': [loadedPath],
      });
      final controller = _RacingSettingsController(store, raceProject);
      final container = _containerFor(controller);
      addTearDown(container.dispose);

      await container.read(appControllerProvider.notifier).loadSettings();
      await _waitForWrites(store, 1);

      final state = container.read(appControllerProvider);
      expect(state.recentProjects.map((project) => project.path), [
        raceProject.path,
        loadedPath,
      ]);
      expect(state.recentProjects.map((project) => project.kind), [
        ProjectKind.debug,
        ProjectKind.infantry,
      ]);
      expect(state.themeMode, ThemeMode.dark);
      // 合并后的列表整体写回，不会用迟到的设置快照把新项目冲掉。
      expect(store.values!['recent'], [
        {'path': raceProject.path, 'kind': 'debug'},
        {'path': loadedPath, 'kind': 'infantry'},
      ]);
    });

    test('加载期间切换的主题不会被迟到的设置覆盖', () async {
      final store = _MemorySettings({
        'theme': 'dark',
        'recent': const <Object?>[],
      });
      final controller = _RacingThemeController(store);
      final container = _containerFor(controller);
      addTearDown(container.dispose);

      await container.read(appControllerProvider.notifier).loadSettings();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(container.read(appControllerProvider).themeMode, ThemeMode.light);
      expect(store.writes, 0);
    });
  });

  test('打开项目后最近项目里记录该项目的类型', () async {
    final directory = await Directory.systemTemp.createTemp('pieblock_recent_');
    addTearDown(() => directory.delete(recursive: true));
    final path = '${directory.path}${Platform.pathSeparator}robot.pieproj';
    await const ProjectRepository().save(
      path,
      ProjectDocument.create('robot', ProjectKind.engineer),
    );

    final container = ProviderContainer();
    addTearDown(container.dispose);
    final controller = container.read(appControllerProvider.notifier);

    expect(await controller.openProject(path), isTrue);
    final recent = container.read(appControllerProvider).recentProjects;
    expect(recent.map((project) => project.path), [path]);
    expect(recent.single.kind, ProjectKind.engineer);
  });
}

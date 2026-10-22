import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

import 'platform/document_io.dart';
import 'platform/settings_store.dart';
import 'recent_project.dart';

enum SaveStatus { idle, saving, saved, failed }

class AppState {
  const AppState({
    this.document,
    this.path,
    this.step = 0,
    this.maxVisitedStep = 0,
    this.saveStatus = SaveStatus.idle,
    this.message,
    this.pendingFieldPath,
    this.validationAttemptedStepIds = const {},
    this.themeMode = ThemeMode.system,
    this.recentProjects = const [],
    this.compiler = CompilerKind.sdcc,
    this.keilPath,
    this.suppressFlashGuide = false,
    this.suppressTemplateGuide = false,
  });
  final ProjectDocument? document;
  final String? path;
  final int step, maxVisitedStep;
  final SaveStatus saveStatus;
  final String? message;
  final String? pendingFieldPath;
  final Set<String> validationAttemptedStepIds;
  final ThemeMode themeMode;

  /// 最近打开的项目，最近打开的排在最前面。
  final List<RecentProject> recentProjects;
  final CompilerKind compiler;
  final String? keilPath;
  final bool suppressFlashGuide;
  final bool suppressTemplateGuide;
  AppState copyWith({
    ProjectDocument? document,
    String? path,
    int? step,
    int? maxVisitedStep,
    SaveStatus? saveStatus,
    String? message,
    bool clearMessage = false,
    String? pendingFieldPath,
    bool clearPendingField = false,
    Set<String>? validationAttemptedStepIds,
    bool clearValidationAttempts = false,
    ThemeMode? themeMode,
    List<RecentProject>? recentProjects,
    CompilerKind? compiler,
    String? keilPath,
    bool clearKeilPath = false,
    bool? suppressFlashGuide,
    bool? suppressTemplateGuide,
    bool clearProject = false,
  }) => AppState(
    document: clearProject ? null : document ?? this.document,
    path: clearProject ? null : path ?? this.path,
    step: clearProject ? 0 : step ?? this.step,
    maxVisitedStep: clearProject ? 0 : maxVisitedStep ?? this.maxVisitedStep,
    saveStatus: clearProject ? SaveStatus.idle : saveStatus ?? this.saveStatus,
    message: clearMessage ? null : message ?? this.message,
    pendingFieldPath: clearProject || clearPendingField
        ? null
        : pendingFieldPath ?? this.pendingFieldPath,
    validationAttemptedStepIds: clearProject || clearValidationAttempts
        ? const {}
        : validationAttemptedStepIds ?? this.validationAttemptedStepIds,
    themeMode: themeMode ?? this.themeMode,
    recentProjects: recentProjects ?? this.recentProjects,
    compiler: compiler ?? this.compiler,
    keilPath: clearKeilPath ? null : keilPath ?? this.keilPath,
    suppressFlashGuide: suppressFlashGuide ?? this.suppressFlashGuide,
    suppressTemplateGuide:
        suppressTemplateGuide ?? this.suppressTemplateGuide,
  );
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> {
  final _repository = const ProjectRepository();
  final _documentIo = const AppDocumentIo();
  Timer? _saveTimer;

  /// 设置写盘队列：保证多次保存按调用顺序落地，后触发的快照不会先写完。
  Future<void> _settingsWrite = Future<void>.value();

  /// Web 上没有编译器，Android 只有内置 SDCC —— 这两种情况都不给选。
  bool get _forcesBuiltInCompiler =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Android 的 SAF 引用（content://）没法同步判断存在性，交给打开失败时处理。
  static bool _isContentUri(String reference) =>
      Uri.tryParse(reference)?.scheme == 'content';

  @override
  AppState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    Future.microtask(loadSettings);
    return const AppState();
  }

  /// 恢复主题、编译器和最近项目；旧版最近项目还会补读项目类型并回写设置。
  ///
  /// 正常由 [build] 在首帧后触发；测试可以直接 await，不用猜微任务时序。
  Future<void> loadSettings() async {
    final initial = state;
    try {
      final json = await readStoredSettings();
      if (json == null) return;
      // 最近项目里可能有已经不在的条目（桌面是文件被删了，Web 是浏览器
      // 存储被清了），逐个确认；content:// 引用没法判断，先留着。
      final recent = <RecentProject>[];
      var migrated = false;
      for (final entry in (json['recent'] as List? ?? []).take(8)) {
        final project = RecentProject.fromSetting(entry);
        if (project == null) continue;
        if (!_isContentUri(project.path) &&
            !await _repository.exists(project.path)) {
          continue;
        }
        if (project.kind != null) {
          recent.add(project);
          continue;
        }
        // 旧版设置只存路径：补读一次项目文件把类型迁移进来，写回后下次启动
        // 就不必再读盘。读不到（文件损坏、content:// 权限失效）就保留通用图标。
        final kind = await _readProjectKind(project.path);
        if (kind == null) {
          recent.add(project);
        } else {
          migrated = true;
          recent.add(project.withKind(kind));
        }
      }
      final mode =
          ThemeMode.values.where((e) => e.name == json['theme']).firstOrNull ??
          ThemeMode.system;
      final storedCompiler =
          CompilerKind.values
              .where((value) => value.name == json['compiler'])
              .firstOrNull ??
          CompilerKind.sdcc;
      final compiler = _forcesBuiltInCompiler
          ? CompilerKind.sdcc
          : storedCompiler;
      // 加载期间用户可能已经改过主题或新建/打开过项目：只覆盖没有被用户改
      // 过的字段，最近项目与内存里的条目合并，避免迟到的设置快照回退状态。
      state = state.copyWith(
        recentProjects: _mergeRecent(state.recentProjects, recent),
        themeMode: state.themeMode == initial.themeMode
            ? mode
            : state.themeMode,
        compiler: state.compiler == initial.compiler
            ? compiler
            : state.compiler,
        keilPath: state.keilPath == initial.keilPath
            ? json['keil_path']?.toString()
            : state.keilPath,
        suppressFlashGuide:
            state.suppressFlashGuide == initial.suppressFlashGuide
            ? json['suppress_flash_guide'] == true
            : state.suppressFlashGuide,
        suppressTemplateGuide:
            state.suppressTemplateGuide == initial.suppressTemplateGuide
            ? json['suppress_template_guide'] == true
            : state.suppressTemplateGuide,
      );
      if (migrated) unawaited(_saveSettings());
    } catch (_) {}
  }

  /// 合并最近项目：加载期间新建/打开的项目排在前面，按路径去重，最多 8 条。
  static List<RecentProject> _mergeRecent(
    List<RecentProject> current,
    List<RecentProject> loaded,
  ) {
    final seen = <String>{};
    return [
      for (final project in [...current, ...loaded])
        if (seen.add(project.path)) project,
    ].take(8).toList();
  }

  /// 设置读写入口：默认落到 platform 层，测试可覆写后换用内存存储。
  @protected
  Future<Map<String, Object?>?> readStoredSettings() => readSettings();

  @protected
  Future<void> writeStoredSettings(Map<String, Object?> values) =>
      writeSettings(values);

  /// 读项目文件里声明的类型，供旧版设置里只有路径的最近项目补全图标。
  ///
  /// 类型字段缺失或非法时 [ProjectDocument.fromJson] 会按步兵解析，这里沿用
  /// 打开项目时的结果，保证列表图标和打开后的项目类型一致。
  Future<ProjectKind?> _readProjectKind(String reference) async {
    try {
      final document = _isContentUri(reference)
          ? _decodeDocument(await _documentIo.read(reference))
          : await _repository.open(reference);
      return document.kind;
    } catch (_) {
      return null;
    }
  }

  /// 保存设置。多次触发时按调用顺序串行写盘：启动迁移与用户操作可能同时
  /// 触发保存，并发的整文件覆盖会让先前的旧快照把新内容盖掉。
  Future<void> _saveSettings() {
    final snapshot = <String, Object?>{
      'theme': state.themeMode.name,
      'recent': [
        for (final project in state.recentProjects) project.toSetting(),
      ],
      'compiler': state.compiler.name,
      if (state.keilPath != null) 'keil_path': state.keilPath,
      'suppress_flash_guide': state.suppressFlashGuide,
      'suppress_template_guide': state.suppressTemplateGuide,
    };
    _settingsWrite = _settingsWrite
        .then((_) => writeStoredSettings(snapshot))
        .catchError((Object _) {});
    return _settingsWrite;
  }

  void cycleTheme() {
    final next = switch (state.themeMode) {
      ThemeMode.system => ThemeMode.light,
      ThemeMode.light => ThemeMode.dark,
      ThemeMode.dark => ThemeMode.system,
    };
    state = state.copyWith(themeMode: next);
    unawaited(_saveSettings());
  }

  void setCompiler(CompilerKind compiler) {
    state = state.copyWith(compiler: compiler);
    unawaited(_saveSettings());
  }

  void setKeilPath(String path) {
    state = state.copyWith(keilPath: path, compiler: CompilerKind.keil);
    unawaited(_saveSettings());
  }

  void suppressFlashGuide() {
    state = state.copyWith(suppressFlashGuide: true);
    unawaited(_saveSettings());
  }

  void suppressTemplateGuide() {
    state = state.copyWith(suppressTemplateGuide: true);
    unawaited(_saveSettings());
  }

  Future<bool> createProject(
    String path,
    String name,
    ProjectKind kind, {
    ProjectConfig? template,
  }) async {
    try {
      final trimmed = path.trim();
      final isContentUri = Uri.tryParse(trimmed)?.scheme == 'content';
      final normalized =
          isContentUri || trimmed.toLowerCase().endsWith('.pieproj')
          ? trimmed
          : '$trimmed.pieproj';
      final created = ProjectDocument.create(name.trim(), kind);
      // 模板只替换 config：名称、时间戳和引导进度都按本次创建重新生成，
      // 项目文件里也不留任何「来自模板」的痕迹。
      final document = template == null
          ? created
          : created.copyWith(config: template);
      if (isContentUri) {
        await _documentIo.write(normalized, _encodeDocument(document));
      } else {
        await _repository.save(normalized, document);
      }
      _adopt(document, normalized);
      return true;
    } catch (error) {
      state = state.copyWith(message: '创建失败：$error');
      return false;
    }
  }

  /// 把外部选来的项目文件落库后再打开。
  ///
  /// 桌面与 Android 的引用本身就是「可以再次读取的位置」，直接 open 就行；
  /// Web 上引用只是文件名，内容必须先写进浏览器存储，否则打开时会找不到。
  Future<bool> importProject(SelectedDocument selected) async {
    try {
      final document = _decodeDocument(selected.bytes);
      await _repository.save(selected.reference, document);
      _adopt(document, selected.reference);
      return true;
    } catch (error) {
      state = state.copyWith(message: '导入失败：$error');
      return false;
    }
  }

  Future<bool> openProject(String path) async {
    final reference = path.trim();
    try {
      final document = Uri.tryParse(reference)?.scheme == 'content'
          ? _decodeDocument(await _documentIo.read(reference))
          : await _repository.open(reference);
      _adopt(document, reference);
      return true;
    } catch (error) {
      final recent = state.recentProjects
          .where((project) => project.path != reference)
          .toList();
      state = state.copyWith(message: '打开失败：$error', recentProjects: recent);
      unawaited(_saveSettings());
      return false;
    }
  }

  void _adopt(ProjectDocument document, String path) {
    final ids = stepIds(document.kind);
    final current = ids.indexOf(document.guideProgress.currentStepId);
    final visited = document.guideProgress.visitedStepIds
        .map(ids.indexOf)
        .where((index) => index >= 0);
    final recent = [
      RecentProject(path: path, kind: document.kind),
      ...state.recentProjects.where((project) => project.path != path),
    ].take(8).toList();
    state = state.copyWith(
      document: document,
      path: path,
      step: current < 0 ? 0 : current,
      maxVisitedStep: visited.isEmpty
          ? 0
          : visited.reduce((a, b) => a > b ? a : b),
      saveStatus: SaveStatus.saved,
      clearMessage: true,
      clearPendingField: true,
      validationAttemptedStepIds: {
        for (var index = 0; index < current && index < ids.length; index += 1)
          ids[index],
      },
      recentProjects: recent,
    );
    unawaited(_saveSettings());
  }

  void updateConfig(ProjectConfig config) {
    final document = state.document;
    if (document == null) return;
    state = state.copyWith(
      document: document.copyWith(config: config),
      saveStatus: SaveStatus.saving,
      clearMessage: true,
      clearPendingField: true,
    );
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 500), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final document = state.document, path = state.path;
    if (document == null || path == null) return;
    state = state.copyWith(saveStatus: SaveStatus.saving);
    try {
      if (Uri.tryParse(path)?.scheme == 'content') {
        await _documentIo.write(path, _encodeDocument(document));
      } else {
        await _repository.save(path, document);
      }
      state = state.copyWith(saveStatus: SaveStatus.saved);
    } catch (error) {
      state = state.copyWith(
        saveStatus: SaveStatus.failed,
        message: '自动保存失败：$error',
      );
    }
  }

  Uint8List _encodeDocument(ProjectDocument document) {
    final encoder = const JsonEncoder.withIndent('  ');
    return Uint8List.fromList(
      utf8.encode('${encoder.convert(document.toJson())}\n'),
    );
  }

  ProjectDocument _decodeDocument(Uint8List bytes) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! Map) {
      throw const FormatException('项目文件不是有效的 JSON 对象');
    }
    return ProjectDocument.fromJson(Map<String, Object?>.from(decoded));
  }

  List<ValidationIssue> get issues => state.document == null
      ? const []
      : ProjectValidator.validate(state.document!.config);

  List<ValidationIssue> get visibleIssues {
    final document = state.document;
    if (document == null) return const [];
    final all = issues;
    if (state.step >= reviewStep(document.kind)) return all;
    return all
        .where(
          (issue) =>
              issue.kind != ValidationIssueKind.required ||
              state.validationAttemptedStepIds.contains(issue.stepId),
        )
        .toList();
  }

  bool goToStep(int target) {
    final document = state.document;
    if (document == null || target < 0 || target >= stepCount(document.kind)) {
      return false;
    }
    if (target > state.step) {
      final ids = stepIds(document.kind);
      state = state.copyWith(
        validationAttemptedStepIds: {
          ...state.validationAttemptedStepIds,
          ids[state.step],
        },
      );
      final blocking = issues.where(
        (i) =>
            i.severity == IssueSeverity.error &&
            _stepIndex(i.stepId, document.kind) <= state.step,
      );
      if (blocking.isNotEmpty) {
        final first = blocking.first;
        state = state.copyWith(
          step: _stepIndex(first.stepId, document.kind),
          message: '发现 ${blocking.length} 项错误，请修正标红的配置',
          pendingFieldPath: first.fieldPath,
        );
        _persistProgress(_stepIndex(first.stepId, document.kind));
        return false;
      }
    }
    state = state.copyWith(
      step: target,
      maxVisitedStep: target > state.maxVisitedStep
          ? target
          : state.maxVisitedStep,
      clearMessage: true,
      clearPendingField: true,
    );
    _persistProgress(target);
    return true;
  }

  void _persistProgress(int currentStep) {
    final document = state.document;
    if (document == null) return;
    final ids = stepIds(document.kind);
    final visited = <String>{
      ...document.guideProgress.visitedStepIds.where(ids.contains),
      for (
        var index = 0;
        index <= state.maxVisitedStep && index < ids.length;
        index++
      )
        ids[index],
    };
    state = state.copyWith(
      document: document.copyWith(
        guideProgress: GuideProgress(
          currentStepId: ids[currentStep],
          visitedStepIds: [
            for (final id in ids)
              if (visited.contains(id)) id,
          ],
        ),
      ),
      saveStatus: SaveStatus.saving,
    );
    _scheduleSave();
  }

  int _stepIndex(String id, ProjectKind kind) {
    final index = stepIds(kind).indexOf(id);
    return index < 0 ? reviewStep(kind) : index;
  }

  int stepCount(ProjectKind kind) => stepIds(kind).length;

  List<String> stepIds(ProjectKind kind) => switch (kind) {
    ProjectKind.infantry => const [
      'remote',
      'mechanism',
      'controls',
      'review',
      'code',
      'deploy',
    ],
    ProjectKind.engineer => const [
      'remote',
      'pwm',
      'strategy',
      'mappings',
      'review',
      'code',
      'deploy',
    ],
    ProjectKind.debug => const ['tests', 'review', 'code', 'deploy'],
    ProjectKind.music => const ['music', 'review', 'code', 'deploy'],
  };

  int reviewStep(ProjectKind kind) => stepIds(kind).indexOf('review');

  int codeStep(ProjectKind kind) => stepIds(kind).indexOf('code');

  int deployStep(ProjectKind kind) => stepIds(kind).indexOf('deploy');

  void goToIssue(ValidationIssue issue) {
    final document = state.document;
    if (document == null) return;
    state = state.copyWith(
      step: _stepIndex(issue.stepId, document.kind),
      pendingFieldPath: issue.fieldPath,
      clearMessage: true,
      validationAttemptedStepIds: {
        ...state.validationAttemptedStepIds,
        issue.stepId,
      },
    );
    _persistProgress(_stepIndex(issue.stepId, document.kind));
  }

  void clearPendingField() => state = state.copyWith(clearPendingField: true);

  void clearMessage() => state = state.copyWith(clearMessage: true);
  Future<void> closeProject() async {
    await saveNow();
    state = state.copyWith(clearProject: true, clearMessage: true);
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

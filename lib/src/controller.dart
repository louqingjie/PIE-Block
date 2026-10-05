import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/models.dart';

import 'platform/document_io.dart';
import 'platform/settings_store.dart';

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
    this.recentPaths = const [],
    this.compiler = CompilerKind.sdcc,
    this.keilPath,
    this.suppressFlashGuide = false,
  });
  final ProjectDocument? document;
  final String? path;
  final int step, maxVisitedStep;
  final SaveStatus saveStatus;
  final String? message;
  final String? pendingFieldPath;
  final Set<String> validationAttemptedStepIds;
  final ThemeMode themeMode;
  final List<String> recentPaths;
  final CompilerKind compiler;
  final String? keilPath;
  final bool suppressFlashGuide;
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
    List<String>? recentPaths,
    CompilerKind? compiler,
    String? keilPath,
    bool clearKeilPath = false,
    bool? suppressFlashGuide,
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
    recentPaths: recentPaths ?? this.recentPaths,
    compiler: compiler ?? this.compiler,
    keilPath: clearKeilPath ? null : keilPath ?? this.keilPath,
    suppressFlashGuide: suppressFlashGuide ?? this.suppressFlashGuide,
  );
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> {
  final _repository = const ProjectRepository();
  final _documentIo = const AppDocumentIo();
  Timer? _saveTimer;

  /// Web 上没有编译器，Android 只有内置 SDCC —— 这两种情况都不给选。
  bool get _forcesBuiltInCompiler =>
      kIsWeb || defaultTargetPlatform == TargetPlatform.android;

  /// Android 的 SAF 引用（content://）没法同步判断存在性，交给打开失败时处理。
  static bool _isContentUri(String reference) =>
      Uri.tryParse(reference)?.scheme == 'content';

  @override
  AppState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    Future.microtask(_loadSettings);
    return const AppState();
  }

  Future<void> _loadSettings() async {
    try {
      final json = await readSettings();
      if (json == null) return;
      // 最近项目里可能有已经不在的条目（桌面是文件被删了，Web 是浏览器
      // 存储被清了），逐个确认；content:// 引用没法判断，先留着。
      final recent = <String>[];
      for (final entry in (json['recent'] as List? ?? []).take(8)) {
        final path = entry.toString();
        if (_isContentUri(path) || await _repository.exists(path)) {
          recent.add(path);
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
      state = state.copyWith(
        recentPaths: recent,
        themeMode: mode,
        compiler: compiler,
        keilPath: json['keil_path']?.toString(),
        suppressFlashGuide: json['suppress_flash_guide'] == true,
      );
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    await writeSettings({
      'theme': state.themeMode.name,
      'recent': state.recentPaths,
      'compiler': state.compiler.name,
      if (state.keilPath != null) 'keil_path': state.keilPath,
      'suppress_flash_guide': state.suppressFlashGuide,
    });
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

  Future<bool> createProject(String path, String name, ProjectKind kind) async {
    try {
      final isContentUri = Uri.tryParse(path)?.scheme == 'content';
      final normalized = isContentUri || path.toLowerCase().endsWith('.pieproj')
          ? path
          : '$path.pieproj';
      final document = ProjectDocument.create(name.trim(), kind);
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
    try {
      final reference = path.trim();
      final document = Uri.tryParse(reference)?.scheme == 'content'
          ? _decodeDocument(await _documentIo.read(reference))
          : await _repository.open(reference);
      _adopt(document, reference);
      return true;
    } catch (error) {
      final recent = [...state.recentPaths]..remove(path);
      state = state.copyWith(message: '打开失败：$error', recentPaths: recent);
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
      path,
      ...state.recentPaths.where((item) => item != path),
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
      recentPaths: recent,
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

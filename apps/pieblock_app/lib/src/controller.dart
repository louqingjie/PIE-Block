import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

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
  );
}

final appControllerProvider = NotifierProvider<AppController, AppState>(
  AppController.new,
);

class AppController extends Notifier<AppState> {
  final _repository = const ProjectRepository();
  Timer? _saveTimer;
  String get _settingsPath {
    final base = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
    return '$base${Platform.pathSeparator}PIE-Block${Platform.pathSeparator}settings.json';
  }

  @override
  AppState build() {
    ref.onDispose(() => _saveTimer?.cancel());
    Future.microtask(_loadSettings);
    return const AppState();
  }

  Future<void> _loadSettings() async {
    try {
      final file = File(_settingsPath);
      if (!await file.exists()) return;
      final json = jsonDecode(await file.readAsString()) as Map;
      final recent = (json['recent'] as List? ?? [])
          .map((e) => e.toString())
          .where((p) => File(p).existsSync())
          .take(8)
          .toList();
      final mode =
          ThemeMode.values.where((e) => e.name == json['theme']).firstOrNull ??
          ThemeMode.system;
      state = state.copyWith(recentPaths: recent, themeMode: mode);
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    final file = File(_settingsPath);
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode({'theme': state.themeMode.name, 'recent': state.recentPaths}),
    );
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

  Future<bool> createProject(String path, String name, ProjectKind kind) async {
    try {
      final normalized = path.toLowerCase().endsWith('.pieproj')
          ? path
          : '$path.pieproj';
      final document = await _repository.create(normalized, name.trim(), kind);
      _adopt(document, normalized);
      return true;
    } catch (error) {
      state = state.copyWith(message: '创建失败：$error');
      return false;
    }
  }

  Future<bool> openProject(String path) async {
    try {
      final document = await _repository.open(path.trim());
      _adopt(document, path.trim());
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

  void updateConfig(RobotConfig config) {
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
      await _repository.save(path, document);
      state = state.copyWith(saveStatus: SaveStatus.saved);
    } catch (error) {
      state = state.copyWith(
        saveStatus: SaveStatus.failed,
        message: '自动保存失败：$error',
      );
    }
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
    if (id == 'remote') return 0;
    if (kind == ProjectKind.infantry) {
      if (id == 'mechanism') return 1;
      if (id == 'controls') return 2;
      return 3;
    }
    if (id == 'pwm') return 1;
    if (id == 'strategy') return 2;
    if (id == 'mappings') return 3;
    return 4;
  }

  int stepCount(ProjectKind kind) => kind == ProjectKind.infantry ? 5 : 6;

  List<String> stepIds(ProjectKind kind) => kind == ProjectKind.infantry
      ? const ['remote', 'mechanism', 'controls', 'review', 'code']
      : const ['remote', 'pwm', 'strategy', 'mappings', 'review', 'code'];

  int reviewStep(ProjectKind kind) => kind == ProjectKind.infantry ? 3 : 4;

  int codeStep(ProjectKind kind) => kind == ProjectKind.infantry ? 4 : 5;

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

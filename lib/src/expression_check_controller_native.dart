import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

import 'deploy_controller_native.dart';
import 'expression_check_state.dart';

export 'expression_check_state.dart';

final expressionCheckControllerProvider =
    NotifierProvider<ExpressionCheckController, ExpressionCheckState>(
      ExpressionCheckController.new,
    );

class ExpressionCheckController extends Notifier<ExpressionCheckState> {
  Future<FirmwareBuilder>? _builderFuture;
  int _generation = 0;

  @override
  ExpressionCheckState build() => const ExpressionCheckState();

  Future<void> check(ProjectConfig config) async {
    if (state.busy) return;
    final generation = ++_generation;
    if (config is! EngineerConfig || !_hasExpressions(config)) {
      state = const ExpressionCheckState(
        activity: ExpressionCheckActivity.noExpressions,
      );
      return;
    }
    if (Platform.isAndroid) {
      state = const ExpressionCheckState(
        activity: ExpressionCheckActivity.unsupported,
        message: 'Android 版不做编译检查，仅做表达式语法检查',
      );
      return;
    }

    final GeneratedProgram program;
    try {
      program = CodeGenerator.generateProgram(config);
    } on StateError catch (error) {
      state = ExpressionCheckState(
        activity: ExpressionCheckActivity.failed,
        message: '$error',
      );
      return;
    }
    if (program.expressionLineFields.isEmpty) {
      state = const ExpressionCheckState(
        activity: ExpressionCheckActivity.noExpressions,
      );
      return;
    }

    state = const ExpressionCheckState(
      activity: ExpressionCheckActivity.checking,
      progress: '正在准备内置 SDCC…',
    );
    try {
      final builder = await (_builderFuture ??= createDesktopFirmwareBuilder());
      if (generation != _generation) return;
      final request = BuildRequest(
        projectKind: config.kind,
        sourceCode: program.source,
        compiler: CompilerKind.sdcc,
        compilerFingerprint: await builder.resolveCompilerFingerprint(
          CompilerKind.sdcc,
        ),
      );
      final operation = builder.start(request);
      final events = operation.events.listen((event) {
        if (generation != _generation) return;
        state = ExpressionCheckState(
          activity: ExpressionCheckActivity.checking,
          progress: event.message,
        );
      });
      final result = await operation.result;
      await events.cancel();
      if (generation != _generation) return;
      if (result.success) {
        state = const ExpressionCheckState(
          activity: ExpressionCheckActivity.passed,
          message: '表达式编译检查通过',
        );
        return;
      }
      final issues = _parseIssues(result.log, program.expressionLineFields);
      state = ExpressionCheckState(
        activity: ExpressionCheckActivity.failed,
        message: issues.isEmpty
            ? '编译失败，请在生成代码页查看构建日志'
            : '表达式编译检查未通过，共 ${issues.length} 处',
        issues: issues,
      );
    } catch (error) {
      if (generation != _generation) return;
      state = ExpressionCheckState(
        activity: ExpressionCheckActivity.failed,
        message: '编译检查环境错误：$error',
      );
    }
  }

  static bool _hasExpressions(EngineerConfig config) => config.modes
      .take(config.modeCount ?? 0)
      .any(
        (mode) => mode.actions.any(
          (action) =>
              action.inputKind == ActionInputKind.unspecified ||
              action.outputKind != ActionOutputKind.pin,
        ),
      );

  static List<ExpressionCheckIssue> _parseIssues(
    String log,
    Map<int, String> lineFields,
  ) {
    final issues = <ExpressionCheckIssue>[];
    final seen = <int>{};
    final pattern = RegExp(r'main\.c:(\d+)');
    for (final raw in const LineSplitter().convert(log)) {
      final match = pattern.firstMatch(raw);
      if (match == null) continue;
      final line = int.tryParse(match.group(1)!);
      if (line == null || !seen.add(line)) continue;
      issues.add(
        ExpressionCheckIssue(
          fieldPath: lineFields[line] ?? 'main.c:$line',
          line: line,
          message: raw.trim(),
        ),
      );
      if (issues.length >= 20) break;
    }
    return issues;
  }
}

import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

/// 内存版宿主：测试里替掉 `AppController`，行为与宿主约定一致。
class FakeHost implements McpHost {
  FakeHost({this.document, this.appVersion = '1.8.0'});

  ProjectDocument? document;
  int _revision = 0;
  int _appliedCount = 0;

  @override
  final String appVersion;

  final List<McpAuditEntry> audits = [];

  /// 由用例注入：返回 applied / denied / timeout。
  Future<McpApplyResult> Function(McpApprovalRequest request)? decide;

  /// 应用补丁前调用一次，便于断言「等待审批时会话没有被提前改掉」。
  void Function(McpPatchPlan plan)? beforeApply;

  int get appliedCount => _appliedCount;

  @override
  int? get revision => document == null ? null : _revision;

  @override
  McpSnapshot? snapshot() {
    final current = document;
    if (current == null) return null;
    return McpSnapshot(
      kind: current.kind.name,
      config: current.config.toJson(),
      issues: ProjectValidator.validate(current.config),
      steps: stepsOf(current.kind),
      currentStepId: current.guideProgress.currentStepId,
      path: 'fake.pieproj',
    );
  }

  @override
  List<ValidationIssue> issuesOf(ProjectConfig config) =>
      ProjectValidator.validate(config);

  @override
  Future<McpApplyResult> apply(
    McpPatchPlan plan,
    McpApprovalRequest request,
  ) async {
    beforeApply?.call(plan);
    final result =
        await (decide?.call(request) ??
            Future.value(const McpApplyResult(McpApplyOutcome.denied)));
    if (!result.applied) return result;
    final current = document;
    if (current == null) {
      return const McpApplyResult(
        McpApplyOutcome.denied,
        message: '项目已关闭',
      );
    }
    document = current.copyWith(config: plan.config);
    _revision += 1;
    _appliedCount += 1;
    return McpApplyResult(McpApplyOutcome.applied, revision: _revision);
  }

  @override
  void record(McpAuditEntry entry) => audits.add(entry);

  /// 与 `AppController.stepIds` 保持一致；漂移由根目录的防漂移用例兜住。
  static List<String> stepsOf(ProjectKind kind) => switch (kind) {
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
}

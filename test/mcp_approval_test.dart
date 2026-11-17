import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/controller.dart';
import 'package:pieblock_app/src/mcp/approval_controller.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

/// 直接挂一份文档的控制器：审批行为与文件读写无关，不碰真实设置与磁盘。
class _DocController extends AppController {
  _DocController(this.initial);

  final ProjectDocument initial;

  /// 不跑父类 build：它会排一个读真实设置的微任务，容器销毁后再跑会抛异常。
  /// 防抖定时器落到已销毁容器的问题由 `AppController.saveNow` 的 mounted 守卫兜住。
  @override
  AppState build() => AppState(document: initial);
}

McpPatchPlan planFor(
  ProjectDocument document, {
  int baseRevision = 0,
  num speed = 4200,
}) => PatchEngine().propose(
  kind: document.kind.name,
  baseConfig: document.config.toJson(),
  baseRevision: baseRevision,
  rawOps: [
    {'op': 'set', 'path': 'chassis.normal_speed', 'value': speed},
  ],
);

McpApprovalRequest requestOf(McpPatchPlan plan) => McpApprovalRequest(
  patchId: plan.patchId,
  baseRevision: plan.baseRevision,
  diff: plan.diff,
  issues: plan.issues,
);

void main() {
  late ProjectDocument document;
  late ProviderContainer container;
  final originalTimeout = McpApprovalController.timeout;

  setUp(() {
    document = ProjectDocument.create(ProjectKind.infantry);
    container = ProviderContainer(
      overrides: [appControllerProvider.overrideWith(() => _DocController(document))],
    );
  });

  tearDown(() {
    container.dispose();
    McpApprovalController.timeout = originalTimeout;
  });

  McpApprovalController approvals() =>
      container.read(mcpApprovalControllerProvider.notifier);

  test('同意后走 updateConfig 并推进 revision', () async {
    final plan = planFor(document);
    final future = approvals().enqueue(plan, requestOf(plan));
    expect(container.read(mcpApprovalControllerProvider), hasLength(1));

    approvals().approve(plan.patchId);

    final result = await future;
    expect(result.outcome, McpApplyOutcome.applied);
    expect(result.revision, 1);
    expect(container.read(mcpApprovalControllerProvider), isEmpty);
    final config = container.read(appControllerProvider).document!.config;
    expect((config as InfantryConfig).chassis.normalSpeed, 4200);
  });

  test('拒绝后返回 denied 且项目不变', () async {
    final plan = planFor(document);
    final future = approvals().enqueue(plan, requestOf(plan));

    approvals().reject(plan.patchId);

    final result = await future;
    expect(result.outcome, McpApplyOutcome.denied);
    expect(container.read(appControllerProvider).revision, 0);
    final config = container.read(appControllerProvider).document!.config;
    expect((config as InfantryConfig).chassis.normalSpeed, isNull);
  });

  test('确认期间项目被改动则判定为冲突', () async {
    final plan = planFor(document);
    final future = approvals().enqueue(plan, requestOf(plan));

    // 模拟用户自己改了一次配置：revision 从 0 变成 1，旧补丁作废。
    container
        .read(appControllerProvider.notifier)
        .updateConfig(document.config);

    approvals().approve(plan.patchId);

    final result = await future;
    expect(result.outcome, McpApplyOutcome.conflict);
    expect(container.read(appControllerProvider).document!.config, isA<InfantryConfig>());
  });

  test('超时自动拒绝并清空队列', () async {
    McpApprovalController.timeout = const Duration(milliseconds: 20);
    final plan = planFor(document);
    final future = approvals().enqueue(plan, requestOf(plan));

    final result = await future;

    expect(result.outcome, McpApplyOutcome.timeout);
    expect(container.read(mcpApprovalControllerProvider), isEmpty);
    expect(container.read(appControllerProvider).revision, 0);
  });

  test('rejectAll 一次性拒绝所有挂起请求', () async {
    final first = planFor(document, speed: 4000);
    final second = planFor(document, speed: 5000);
    final futures = [
      approvals().enqueue(first, requestOf(first)),
      approvals().enqueue(second, requestOf(second)),
    ];
    expect(container.read(mcpApprovalControllerProvider), hasLength(2));

    approvals().rejectAll('服务已关闭');

    for (final result in await Future.wait(futures)) {
      expect(result.outcome, McpApplyOutcome.denied);
      expect(result.message, '服务已关闭');
    }
    expect(container.read(mcpApprovalControllerProvider), isEmpty);
  });
}

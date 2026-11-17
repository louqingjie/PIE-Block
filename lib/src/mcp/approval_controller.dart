import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import '../controller.dart';
import 'mcp_models.dart';

/// 待审批队列。
///
/// 「人在回路」放在 PIE-Block 自己的窗口里，不依赖客户端的审批能力：任何
/// agent 走到 `pieblock_apply_patch` 都会停在这里等同一张卡片。
final mcpApprovalControllerProvider =
    NotifierProvider<McpApprovalController, List<McpPendingApproval>>(
      McpApprovalController.new,
    );

class McpApprovalController extends Notifier<List<McpPendingApproval>> {
  /// 等不到人点就拒绝。太长会让客户端以为卡死，太短来不及看 diff。
  ///
  /// 可变是为了让测试把它改小，生产代码不要动。
  static Duration timeout = const Duration(seconds: 120);

  final Map<String, Timer> _timers = {};

  @override
  List<McpPendingApproval> build() {
    ref.onDispose(() {
      for (final timer in _timers.values) {
        timer.cancel();
      }
      _timers.clear();
    });
    return const [];
  }

  /// 入队并等待结果。宿主 `apply` 直接返回这个 Future。
  Future<McpApplyResult> enqueue(
    McpPatchPlan plan,
    McpApprovalRequest request,
  ) {
    final completer = Completer<McpApplyResult>();
    final pending = McpPendingApproval(
      plan: plan,
      request: request,
      deadline: DateTime.now().add(timeout),
      completer: completer,
    );
    state = [...state, pending];
    _timers[request.patchId] = Timer(timeout, () {
      _resolve(
        request.patchId,
        const McpApplyResult(
          McpApplyOutcome.timeout,
          message: '等待确认超时，改动未应用',
        ),
      );
    });
    return completer.future;
  }

  /// 用户点了「应用」。
  void approve(String patchId) {
    final pending = _find(patchId);
    if (pending == null) return;
    final app = ref.read(appControllerProvider);
    if (app.document == null) {
      _resolve(
        patchId,
        const McpApplyResult(McpApplyOutcome.denied, message: '项目已关闭'),
      );
      return;
    }
    if (pending.plan.baseRevision != app.revision) {
      _resolve(
        patchId,
        McpApplyResult(
          McpApplyOutcome.conflict,
          message: '确认期间项目被改动过（现在是 revision ${app.revision}），'
              '这次改动没有应用',
        ),
      );
      return;
    }
    // 唯一写入口：校验、撤销、自动保存都与界面手改走同一条路。
    ref.read(appControllerProvider.notifier).updateConfig(pending.plan.config);
    final revision = ref.read(appControllerProvider).revision;
    _resolve(
      patchId,
      McpApplyResult(McpApplyOutcome.applied, revision: revision),
    );
  }

  /// 用户点了「拒绝」。
  void reject(String patchId) {
    _resolve(
      patchId,
      const McpApplyResult(McpApplyOutcome.denied, message: '用户拒绝了这次改动'),
    );
  }

  /// 服务停掉时把挂起的请求全部拒绝，避免客户端一直等着。
  void rejectAll(String reason) {
    for (final pending in [...state]) {
      _resolve(
        pending.patchId,
        McpApplyResult(McpApplyOutcome.denied, message: reason),
      );
    }
  }

  McpPendingApproval? _find(String patchId) {
    for (final pending in state) {
      if (pending.patchId == patchId) return pending;
    }
    return null;
  }

  void _resolve(String patchId, McpApplyResult result) {
    _timers.remove(patchId)?.cancel();
    final pending = _find(patchId);
    if (pending == null) return;
    state = [
      for (final item in state)
        if (item.patchId != patchId) item,
    ];
    if (!pending.completer.isCompleted) {
      pending.completer.complete(result);
    }
  }
}

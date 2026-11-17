import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:pieblock_mcp/pieblock_mcp.dart';

import 'approval_controller.dart';
import 'mcp_models.dart';

/// 全局审批宿主：挂在 `MaterialApp.builder` 上，任何页面都能弹卡片。
///
/// 「人在回路」放在这里而不是客户端，是本方案的关键取舍：各客户端对工具审批
/// 的支持参差不齐，放在我们窗口里，任何 agent 的行为才完全一致。
class McpApprovalHost extends ConsumerStatefulWidget {
  const McpApprovalHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<McpApprovalHost> createState() => _McpApprovalHostState();
}

class _McpApprovalHostState extends ConsumerState<McpApprovalHost> {
  String? _showing;

  @override
  Widget build(BuildContext context) {
    final queue = ref.watch(mcpApprovalControllerProvider);
    if (queue.isNotEmpty && _showing == null) {
      final next = queue.first;
      _showing = next.patchId;
      WidgetsBinding.instance.addPostFrameCallback((_) => _present(next));
    }
    return widget.child;
  }

  Future<void> _present(McpPendingApproval pending) async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ApprovalDialog(patchId: pending.patchId),
    );
    if (approved == true) {
      ref.read(mcpApprovalControllerProvider.notifier).approve(pending.patchId);
    } else if (approved == false) {
      ref.read(mcpApprovalControllerProvider.notifier).reject(pending.patchId);
    }
    _showing = null;
    if (mounted) setState(() {});
  }
}

class _ApprovalDialog extends ConsumerStatefulWidget {
  const _ApprovalDialog({required this.patchId});

  final String patchId;

  @override
  ConsumerState<_ApprovalDialog> createState() => _ApprovalDialogState();
}

class _ApprovalDialogState extends ConsumerState<_ApprovalDialog> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // 只为刷新倒计时；队列本身的变化由 ref.watch 驱动。
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  McpPendingApproval? _current() {
    for (final pending in ref.watch(mcpApprovalControllerProvider)) {
      if (pending.patchId == widget.patchId) return pending;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final pending = _current();
    if (pending == null) {
      // 超时或被其它路径清掉：自己退场，别让用户对着过期内容点按钮。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    final errors = pending.request.issues
        .where((issue) => issue.severity == IssueSeverity.error)
        .length;
    final seconds = pending.remaining.inSeconds;

    return AlertDialog(
      icon: const Icon(Icons.smart_toy_outlined),
      title: const Text('AI 想修改项目配置'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '共 ${pending.request.diff.length} 处改动 · revision '
                '${pending.request.baseRevision} · $seconds 秒后自动拒绝',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (final entry in pending.request.diff)
                _DiffRow(entry: entry),
              if (errors > 0) ...[
                const SizedBox(height: 12),
                Text(
                  '应用后仍有 $errors 个错误：${pending.request.issues.firstWhere((issue) => issue.severity == IssueSeverity.error).message}',
                  style: TextStyle(color: scheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            ref
                .read(mcpApprovalControllerProvider.notifier)
                .reject(widget.patchId);
            Navigator.of(context).pop(false);
          },
          child: const Text('拒绝'),
        ),
        FilledButton(
          onPressed: () {
            ref
                .read(mcpApprovalControllerProvider.notifier)
                .approve(widget.patchId);
            Navigator.of(context).pop(true);
          },
          child: const Text('应用改动'),
        ),
      ],
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow({required this.entry});

  final McpDiffEntry entry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            entry.label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          Text(
            entry.path,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontFamily: 'PieBlockMono',
              fontSize: 11,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            entry.removed
                ? '删除（原值 ${_format(entry.before)}）'
                : '${_format(entry.before)}  →  ${_format(entry.after)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  static String _format(Object? value) {
    if (value == null) return '未填';
    if (value is Map || value is List) {
      final text = jsonEncode(value);
      return text.length <= 90 ? text : '${text.substring(0, 87)}…';
    }
    return value.toString();
  }
}

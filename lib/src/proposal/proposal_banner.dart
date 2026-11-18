import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../controller.dart';
import 'proposal_diff_dialog.dart';
import 'proposal_service.dart';

/// 编辑器顶部的提案横幅：发现 AI 提案时提示「查看 / 应用 / 丢弃」。
class ProposalBanner extends ConsumerWidget {
  const ProposalBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proposalServiceProvider);
    if (state.status == ProposalStatus.none) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (state.isInvalid) {
      return MaterialBanner(
        backgroundColor: scheme.errorContainer,
        contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
          color: scheme.onErrorContainer,
        ),
        leading: Icon(Icons.error_outline, color: scheme.onErrorContainer),
        content: Text('AI 提案无法读取：${state.error ?? '未知错误'}'),
        actions: [
          TextButton(
            onPressed: () =>
                ref.read(proposalServiceProvider.notifier).discard(),
            child: const Text('丢弃'),
          ),
        ],
      );
    }

    final proposal = state.proposal!;
    final flags = [
      if (state.stale) '基于旧版本',
      if (state.dirty) '你有未保存的改动',
      if (state.remainingErrors > 0) '工程仍有 ${state.remainingErrors} 个错误',
    ];
    // 主题把 bannerTheme 统一设成了错误色（给校验失败提示用），提案不是错误，
    // 必须显式覆盖，否则横幅会渲染成红色。
    return MaterialBanner(
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurface,
      ),
      leading: Icon(Icons.auto_awesome, color: scheme.primary),
      content: Text(
        'AI 提交了改动提案：${proposal.changedPaths.length} 处改动'
        '${flags.isEmpty ? '' : '（${flags.join('，')}）'}',
      ),
      actions: [
        TextButton(
          onPressed: () => _review(context, ref),
          child: const Text('查看'),
        ),
        TextButton(
          onPressed: () => _apply(context, ref),
          child: const Text('应用'),
        ),
        TextButton(
          onPressed: () => ref.read(proposalServiceProvider.notifier).discard(),
          child: const Text('丢弃'),
        ),
      ],
    );
  }

  Future<void> _review(BuildContext context, WidgetRef ref) async {
    final state = ref.read(proposalServiceProvider);
    final proposal = state.proposal;
    final current = ref.read(appControllerProvider).document;
    if (proposal == null || current == null) return;
    final apply = await showDialog<bool>(
      context: context,
      builder: (_) => ProposalDiffDialog(
        current: current.config,
        proposal: proposal,
        stale: state.stale,
        dirty: state.dirty,
        remainingErrors: state.remainingErrors,
      ),
    );
    if (apply == true && context.mounted) await _apply(context, ref);
  }

  Future<void> _apply(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await ref.read(proposalServiceProvider.notifier).accept();
    if (!context.mounted) return;
    switch (result) {
      case ProposalApplyResult.applied:
        messenger.showSnackBar(
          SnackBar(
            content: const Text('已应用 AI 提案'),
            action: SnackBarAction(
              label: '撤销',
              onPressed: () =>
                  ref.read(appControllerProvider.notifier).undoProposal(),
            ),
          ),
        );
      case ProposalApplyResult.failed:
        messenger.showSnackBar(
          const SnackBar(content: Text('应用 AI 提案失败，请查看提示')),
        );
      case ProposalApplyResult.unavailable:
        break;
    }
  }
}

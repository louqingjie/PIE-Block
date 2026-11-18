import 'dart:convert';

import 'package:material_ui/material_ui.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../design/app_dialog.dart';

/// 展示提案的逐字段差异，返回 true 表示用户点了「应用」。
class ProposalDiffDialog extends StatelessWidget {
  const ProposalDiffDialog({
    super.key,
    required this.current,
    required this.proposal,
    this.stale = false,
    this.dirty = false,
  });

  final ProjectConfig current;
  final ProjectProposal proposal;
  final bool stale;
  final bool dirty;

  static const _maxRows = 200;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final changes = diffConfigs(
      current.toJson(),
      proposal.document.config.toJson(),
    );
    final visible = changes.take(_maxRows).toList();
    return AppDialog(
      title: const Text('AI 改动提案'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (stale)
              _Warning(
                icon: Icons.history,
                color: scheme.tertiary,
                text: '提案基于旧版本生成，应用会覆盖此后对工程的改动。',
              ),
            if (dirty)
              _Warning(
                icon: Icons.edit_note,
                color: scheme.error,
                text: '当前有未保存的改动，应用提案会覆盖它们。',
              ),
            Text(
              '共 ${changes.length} 处改动',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            if (visible.isEmpty)
              Text('没有可展示的差异', style: Theme.of(context).textTheme.bodySmall)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final change in visible) _ChangeRow(change: change),
                      if (changes.length > visible.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            '还有 ${changes.length - visible.length} 处改动未显示',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('应用'),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.icon, required this.color, required this.text});

  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: color),
          ),
        ),
      ],
    ),
  );
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final ProposalChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            change.path.isEmpty ? '<root>' : change.path,
            style: theme.textTheme.bodySmall?.copyWith(
              fontFamily: 'PieBlockMono',
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.remove_circle_outline, size: 14, color: scheme.error),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _format(change.before),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.add_circle_outline, size: 14, color: scheme.primary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  _format(change.after),
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _format(Object? value) {
    if (value == null) return '（空）';
    final text = value is String ? '"$value"' : _encode(value);
    return text.length <= 160 ? text : '${text.substring(0, 157)}…';
  }

  static String _encode(Object? value) {
    try {
      return const JsonEncoder().convert(value);
    } catch (_) {
      return value.toString();
    }
  }
}

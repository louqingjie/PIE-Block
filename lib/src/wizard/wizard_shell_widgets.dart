part of '../wizard_screen.dart';

class _SaveBadge extends StatelessWidget {
  const _SaveBadge(this.status);
  final SaveStatus status;
  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (status) {
      SaveStatus.saving => (Icons.sync, '保存中'),
      SaveStatus.saved => (Icons.cloud_done_outlined, '已保存'),
      SaveStatus.failed => (Icons.cloud_off_outlined, '保存失败'),
      _ => (Icons.cloud_outlined, '等待保存'),
    };
    return Chip(avatar: Icon(icon, size: 17), label: Text(text));
  }
}

class _CompactSaveBadge extends StatelessWidget {
  const _CompactSaveBadge(this.status);
  final SaveStatus status;

  @override
  Widget build(BuildContext context) {
    final (icon, text) = switch (status) {
      SaveStatus.saving => (Icons.sync, '保存中'),
      SaveStatus.saved => (Icons.cloud_done_outlined, '已保存'),
      SaveStatus.failed => (Icons.cloud_off_outlined, '保存失败'),
      _ => (Icons.cloud_outlined, '等待保存'),
    };
    return Semantics(
      label: text,
      child: Tooltip(message: text, child: Icon(icon, size: 22)),
    );
  }
}

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.title,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });
  final int index;
  final String title;
  final bool selected, enabled;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      enabled: enabled,
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.secondaryContainer,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: CircleAvatar(radius: 15, child: Text('${index + 1}')),
      title: Text(title),
      onTap: enabled ? onTap : null,
    ),
  );
}

class _CompactStepPicker extends ConsumerWidget {
  const _CompactStepPicker({
    required this.steps,
    required this.selected,
    required this.busy,
  });

  final List<String> steps;
  final int selected;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maxStep = ref.watch(appControllerProvider).maxVisitedStep + 1;
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
        child: DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '当前步骤 · ${selected + 1} / ${steps.length}',
            prefixIcon: const Icon(Icons.route_outlined),
            isDense: true,
          ),
          items: [
            for (var i = 0; i < steps.length; i++)
              DropdownMenuItem(
                value: i,
                enabled: !busy && i <= maxStep,
                child: Text('${i + 1}. ${steps[i]}'),
              ),
          ],
          onChanged: busy
              ? null
              : (step) {
                  if (step != null && step <= maxStep) {
                    _endTextInput(ref);
                    ref.read(appControllerProvider.notifier).goToStep(step);
                  }
                },
        ),
      ),
    );
  }
}

class _PageFrame extends ConsumerWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.stepId,
    this.fill = false,
  });
  final String title, subtitle;
  final String? stepId;
  final Widget child;

  /// 由 child 自己承担滚动时置为 true：页头固定，child 填满剩余高度。
  final bool fill;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeInputField = _activeInputField(ref);
    final issues = stepId == null
        ? const <ValidationIssue>[]
        : ref
              .read(appControllerProvider.notifier)
              .visibleIssues
              .where(
                (issue) =>
                    issue.stepId == stepId &&
                    issue.fieldPath != activeInputField,
              )
              .toList();
    final compact = _isCompact(context);
    final header = <Widget>[
      Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
      if (issues.isNotEmpty) ...[
        const SizedBox(height: 16),
        if (fill)
          // 留给问题面板的高度有上限，短窗口下不能把列表挤成零高。
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: _StepProblemPanel(issues: issues),
            ),
          )
        else
          _StepProblemPanel(issues: issues),
      ],
    ];
    if (fill) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 32,
          compact ? 18 : 26,
          compact ? 16 : 32,
          compact ? 16 : 24,
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...header,
                const SizedBox(height: 24),
                Expanded(child: child),
              ],
            ),
          ),
        ),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        compact ? 16 : 32,
        compact ? 18 : 26,
        compact ? 16 : 32,
        40 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 980),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [...header, const SizedBox(height: 24), child],
          ),
        ),
      ),
    );
  }
}

class _StepProblemPanel extends ConsumerWidget {
  const _StepProblemPanel({required this.issues});

  final List<ValidationIssue> issues;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .35),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(
        color: Theme.of(context).colorScheme.error.withValues(alpha: .35),
      ),
    ),
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本页有 ${issues.where((i) => i.severity == IssueSeverity.error).length} 项错误、${issues.where((i) => i.severity == IssueSeverity.warning).length} 项提醒',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          for (final issue in issues)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                issue.severity == IssueSeverity.error
                    ? Icons.error_outline
                    : Icons.warning_amber,
                color: issue.severity == IssueSeverity.error
                    ? Theme.of(context).colorScheme.error
                    : Colors.orange,
              ),
              title: Text(issue.message),
              trailing: const Icon(Icons.my_location, size: 18),
              onTap: () {
                _endTextInput(ref);
                _scrollToField(issue.fieldPath);
              },
            ),
        ],
      ),
    ),
  );
}

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

enum _StepVisual { current, completed, next, locked }

_StepVisual _stepVisual(int index, AppState state) => index == state.step
    ? _StepVisual.current
    : index <= state.maxVisitedStep
    ? _StepVisual.completed
    : index == state.maxVisitedStep + 1
    ? _StepVisual.next
    : _StepVisual.locked;

class _StepTile extends StatelessWidget {
  const _StepTile({
    required this.index,
    required this.title,
    required this.visual,
    required this.onTap,
  });
  final int index;
  final String title;
  final _StepVisual visual;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final badge = _StepBadge(index: index, visual: visual);
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey('wizard-step-tile-$index'),
        enabled: visual != _StepVisual.locked,
        selected: visual == _StepVisual.current,
        selectedTileColor: scheme.secondaryContainer,
        selectedColor: scheme.onSecondaryContainer,
        minTileHeight: 48,
        shape: AppShape.full,
        titleTextStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
          fontWeight: visual == _StepVisual.current
              ? FontWeight.w700
              : FontWeight.w500,
        ),
        leading: switch (visual) {
          _StepVisual.completed => Semantics(
            label: '已完成',
            child: ExcludeSemantics(child: badge),
          ),
          _StepVisual.locked => Semantics(
            label: '未解锁',
            child: ExcludeSemantics(child: badge),
          ),
          _ => badge,
        },
        title: Text(title),
        onTap: visual == _StepVisual.locked ? null : onTap,
      ),
    );
  }
}

class _StepBadge extends StatelessWidget {
  const _StepBadge({required this.index, required this.visual});
  final int index;
  final _StepVisual visual;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (Color? fill, Color foreground, Color? outline) = switch (visual) {
      _StepVisual.current => (scheme.primary, scheme.onPrimary, null),
      _StepVisual.completed => (
        scheme.primaryContainer,
        scheme.onPrimaryContainer,
        null,
      ),
      _StepVisual.next => (null, scheme.onSurfaceVariant, scheme.outline),
      _StepVisual.locked => (
        null,
        scheme.onSurface.withValues(alpha: .38),
        scheme.outlineVariant,
      ),
    };
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: fill ?? Colors.transparent,
        border: outline == null ? null : Border.all(color: outline, width: 1.5),
      ),
      child: visual == _StepVisual.completed
          ? Icon(Icons.check, size: 18, color: foreground)
          : Text(
              '${index + 1}',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: foreground, fontWeight: FontWeight.w600),
            ),
    );
  }
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
        child: Row(
          children: [
            // 完整标识的三行文字在步骤栏高度下无法辨认，窄屏改用词标；
            // 词标同样按主题切换透明彩色 / 白色单通道资源。
            const WpieWordmark(key: ValueKey('wizard.lab-wordmark')),
            const SizedBox(width: 12),
            Expanded(
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
                          ref
                              .read(appControllerProvider.notifier)
                              .goToStep(step);
                        }
                      },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.fill = false,
  });
  final String title, subtitle;
  final Widget child;

  /// 由 child 自己承担滚动时置为 true：页头固定，child 填满剩余高度。
  final bool fill;

  @override
  Widget build(BuildContext context) {
    final compact = _isCompact(context);
    final header = <Widget>[
      Text(
        title,
        style: Theme.of(context).textTheme.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
      const SizedBox(height: 6),
      Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
    ];
    if (fill) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          compact ? 16 : 32,
          compact ? 18 : 26,
          compact ? 16 : 32,
          compact ? 104 : 116,
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
        (compact ? 104 : 116) + MediaQuery.viewInsetsOf(context).bottom,
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

String _problemSummaryLabel(int errors, int warnings) {
  if (errors == 0) return '$warnings 项提醒';
  if (warnings == 0) return '$errors 项错误';
  return '$errors 项错误 · $warnings 项提醒';
}

/// 底部操作区左侧的问题摘要；点击展开问题列表。
class _ProblemSummaryButton extends StatelessWidget {
  const _ProblemSummaryButton({required this.issues, required this.onPressed});

  final List<ValidationIssue> issues;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final errors = issues
        .where((issue) => issue.severity == IssueSeverity.error)
        .length;
    final warnings = issues.length - errors;
    final accent = errors > 0
        ? scheme.error
        : AppStatusColors.warn(brightness);
    return Tooltip(
      message: '展开问题',
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: AppShape.full,
        child: InkWell(
          customBorder: AppShape.full,
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  errors > 0 ? Icons.error_outline : Icons.warning_amber,
                  size: 18,
                  color: accent,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    _problemSummaryLabel(errors, warnings),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.expand_less,
                  size: 18,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 浮在底部操作区上的问题列表；默认折叠，展开后可滚动查看并跳转字段。
class _StepProblemPanel extends ConsumerWidget {
  const _StepProblemPanel({required this.issues, required this.onCollapse});

  final List<ValidationIssue> issues;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    final warn = AppStatusColors.warn(brightness);
    final errors = issues
        .where((issue) => issue.severity == IssueSeverity.error)
        .length;
    final warnings = issues.length - errors;
    return Material(
      color: scheme.surfaceContainerHigh,
      shape: AppShape.lg,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: .24),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  errors > 0 ? Icons.error_outline : Icons.warning_amber,
                  size: 20,
                  color: errors > 0 ? scheme.error : warn,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '本页有 $errors 项错误、$warnings 项提醒',
                    style: AppText.cardTitle(context),
                  ),
                ),
                IconButton(
                  onPressed: onCollapse,
                  tooltip: '收起问题',
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.expand_more),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final issue in issues)
                      ListTile(
                        dense: true,
                        shape: AppShape.md,
                        contentPadding: EdgeInsets.zero,
                        leading: Icon(
                          issue.severity == IssueSeverity.error
                              ? Icons.error_outline
                              : Icons.warning_amber,
                          color: issue.severity == IssueSeverity.error
                              ? scheme.error
                              : warn,
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
            ),
          ],
        ),
      ),
    );
  }
}

/// 悬浮在内容右下角的步骤操作组：步骤计数 + 上一步/下一步。
///
/// 不再占用整条底栏，避免底栏圆角与侧栏、页面内容互相切割。
class _WizardActionCluster extends StatelessWidget {
  const _WizardActionCluster({
    required this.compact,
    required this.step,
    required this.totalSteps,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final bool compact;
  final int step;
  final int totalSteps;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        DecoratedBox(
          decoration: ShapeDecoration(
            color: scheme.surfaceContainerHigh,
            shape: AppShape.full,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              '${step + 1} / $totalSteps',
              style: AppText.count(context),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (onPrevious != null) ...[
              compact
                  ? IconButton.outlined(
                      onPressed: onPrevious,
                      tooltip: '上一步',
                      icon: const Icon(Icons.arrow_back),
                    )
                  : OutlinedButton.icon(
                      onPressed: onPrevious,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('上一步'),
                    ),
              const SizedBox(width: 8),
            ],
            compact
                ? IconButton.filled(
                    onPressed: onNext,
                    tooltip: nextLabel,
                    icon: const Icon(Icons.arrow_forward),
                  )
                // M3E：前进类动作的箭头跟在文字后面，按下只做形变不放大。
                : FilledButton.icon(
                    onPressed: onNext,
                    iconAlignment: IconAlignment.end,
                    icon: const Icon(Icons.arrow_forward),
                    label: Text(nextLabel),
                  ),
          ],
        ),
      ],
    );
  }
}

/// 右下角操作区：问题摘要/面板 + 步骤计数 + 上一步/下一步。
class _WizardBottomDock extends ConsumerStatefulWidget {
  const _WizardBottomDock({
    required this.compact,
    required this.step,
    required this.totalSteps,
    required this.nextLabel,
    required this.onPrevious,
    required this.onNext,
  });

  final bool compact;
  final int step;
  final int totalSteps;
  final String nextLabel;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  ConsumerState<_WizardBottomDock> createState() => _WizardBottomDockState();
}

class _WizardBottomDockState extends ConsumerState<_WizardBottomDock> {
  bool _expanded = false;

  /// 只有这些步骤原先在页头展示问题面板。
  static const _problemStepIds = {
    'remote',
    'mechanism',
    'controls',
    'pwm',
    'strategy',
    'mappings',
    'tests',
  };

  @override
  void didUpdateWidget(covariant _WizardBottomDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.step != widget.step) _expanded = false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    final controller = ref.read(appControllerProvider.notifier);
    final cluster = _WizardActionCluster(
      compact: widget.compact,
      step: widget.step,
      totalSteps: widget.totalSteps,
      nextLabel: widget.nextLabel,
      onPrevious: widget.onPrevious,
      onNext: widget.onNext,
    );
    final document = state.document;
    final issues = <ValidationIssue>[];
    if (document != null) {
      final stepIds = controller.stepIds(document.kind);
      if (widget.step >= 0 &&
          widget.step < stepIds.length &&
          _problemStepIds.contains(stepIds[widget.step])) {
        final activeInput = _activeInputField(ref);
        issues.addAll(
          controller.visibleIssues.where(
            (issue) =>
                issue.stepId == stepIds[widget.step] &&
                issue.fieldPath != activeInput,
          ),
        );
      }
    }
    if (issues.isEmpty) return cluster;

    final summary = _ProblemSummaryButton(
      issues: issues,
      onPressed: () => setState(() => _expanded = !_expanded),
    );
    final panel = _StepProblemPanel(
      issues: issues,
      onCollapse: () => setState(() => _expanded = false),
    );
    final stickAbove = widget.compact || MediaQuery.sizeOf(context).width < 900;
    if (!_expanded) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Flexible(child: summary),
          SizedBox(width: widget.compact ? 8 : 12),
          cluster,
        ],
      );
    }
    if (stickAbove) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: widget.compact
                  ? MediaQuery.sizeOf(context).width - 24
                  : 380,
              maxHeight: widget.compact ? 240 : 280,
            ),
            child: panel,
          ),
          const SizedBox(height: 8),
          cluster,
        ],
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380, maxHeight: 280),
          child: panel,
        ),
        const SizedBox(width: 12),
        cluster,
      ],
    );
  }
}

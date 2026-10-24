part of '../wizard_screen.dart';

class _ReviewPage extends ConsumerWidget {
  const _ReviewPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider),
        issues = ref.read(appControllerProvider.notifier).issues,
        config = state.document!.config;
    final errors = issues
            .where((i) => i.severity == IssueSeverity.error)
            .length,
        warnings = issues.length - errors;
    String frequency(PwmFrequency? value) => switch (value) {
      PwmFrequency.hz50 => '50',
      PwmFrequency.hz10000 => '10000',
      null => '未选择',
    };
    return _PageFrame(
      title: '检查与配置摘要',
      subtitle: '生成前完成跨页面检查。点击问题可返回对应步骤。',
      child: Column(
        children: [
          _Section(
            title: '检查结果',
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 10,
                children: [
                  _CountBadge(
                    icon: Icons.error_outline,
                    label: '错误',
                    count: errors,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  _CountBadge(
                    icon: Icons.warning_amber,
                    label: '警告',
                    count: warnings,
                    color: AppStatusColors.warn(Theme.of(context).brightness),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (issues.isEmpty)
                ListTile(
                  leading: Icon(
                    Icons.check_circle,
                    color: AppStatusColors.ok(Theme.of(context).brightness),
                  ),
                  title: Text('配置检查通过，可以生成代码'),
                )
              else
                for (final issue in issues)
                  ListTile(
                    leading: Icon(
                      issue.severity == IssueSeverity.error
                          ? Icons.error
                          : Icons.warning_amber,
                      color: issue.severity == IssueSeverity.error
                          ? Theme.of(context).colorScheme.error
                          : AppStatusColors.warn(Theme.of(context).brightness),
                    ),
                    title: Text(issue.message),
                    subtitle: Text(issue.fieldPath),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () {
                      _endTextInput(ref);
                      ref.read(appControllerProvider.notifier).goToIssue(issue);
                    },
                  ),
            ],
          ),
          if (config is EngineerConfig && _hasExpressionRows(config)) ...[
            const SizedBox(height: 18),
            _Section(
              title: '表达式编译检查',
              subtitle:
                  '桌面端会用内置 SDCC 对生成代码做一次完整编译，并把错误回填到对应表达式行；Web/Android 仅做语法检查。',
              children: [_ExpressionCheckCard(config: config)],
            ),
          ],
          const SizedBox(height: 18),
          _Section(
            title: '配置概览',
            children: [
              if (config is RobotConfig) ...[
                ListTile(
                  leading: const Icon(Icons.sports_esports),
                  title: Text(
                    '遥控器通道 ${config.remote.channel ?? '未填写'} · 死区 ${config.remote.deadzone ?? '未填写'}',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.speed),
                  title: Text(
                    config.chassis.enabled
                        ? '普通速度 ${config.chassis.normalSpeed ?? '未填写'} · 冲刺速度 ${config.chassis.sprintSpeed ?? '未填写'}'
                        : '底盘控制：未启用（自定义输出）',
                  ),
                  subtitle: config.chassis.enabled
                      ? Text(
                          config.chassis.turnReversed ? '左右转向：反向' : '左右转向：标准',
                        )
                      : null,
                ),
              ],
              ListTile(
                leading: const Icon(Icons.route),
                title: Text(
                  '向导进度 ${state.document!.guideProgress.visitedStepIds.length} / ${ref.read(appControllerProvider.notifier).stepIds(config.kind).length} · 当前 ${state.document!.guideProgress.currentStepId}',
                ),
              ),
              if (config is InfantryConfig) ...[
                const ListTile(
                  leading: Icon(Icons.memory),
                  title: Text('PWMA 50 Hz · PWMB 10000 Hz（硬件固定）'),
                ),
                ListTile(
                  leading: const Icon(Icons.rotate_right),
                  title: Text(
                    config.frictionMode == FrictionMode.brushlessEsc
                        ? '摩擦轮：无刷电调，固定占用 P64/P66'
                        : config.frictionMode == FrictionMode.disabled
                        ? '摩擦轮：不使用，P64/P66 已释放'
                        : '摩擦轮：未选择',
                  ),
                ),
                for (final assignment in InfantryPinPlanner.derive(
                  config,
                ).values)
                  ListTile(
                    dense: true,
                    leading: const Icon(Icons.cable, size: 18),
                    title: Text('${assignment.pin} · ${assignment.ownerLabel}'),
                  ),
              ] else if (config is EngineerConfig)
                ListTile(
                  leading: const Icon(Icons.memory),
                  title: Text(
                    'PWMA ${frequency(config.pwm.pwma)} Hz · PWMB ${frequency(config.pwm.pwmb)} Hz',
                  ),
                ),
              if (config is EngineerConfig)
                ListTile(
                  leading: const Icon(Icons.layers),
                  title: Text(
                    '${config.modeCount?.toString() ?? '未选择'} 个工程模式 · ${config.modeCount == 1 ? '单模式无需切换' : switch (config.switchStrategy) {
                            SwitchStrategy.cycle => '单击轮换',
                            SwitchStrategy.direct => '一一对应',
                            null => '未选择切换策略',
                          }}',
                  ),
                ),
              if (config is DebugConfig) ...[
                ListTile(
                  leading: const Icon(Icons.science_outlined),
                  title: Text(
                    '已启用 ${config.tests.where((item) => item.enabled).length} / ${config.tests.length} 项测试',
                  ),
                  subtitle: const Text('每轮结束输出归零，随后自动回到第 1 项循环执行'),
                ),
                for (final entry in config.tests.indexed.where(
                  (entry) => entry.$2.enabled,
                ))
                  ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 13,
                      child: Text('${entry.$1 + 1}'),
                    ),
                    title: Text(
                      '${entry.$2.pin} · ${_debugDriveSummary(entry.$2)}',
                    ),
                  ),
              ],
              if (config is MusicConfig) ...[
                ListTile(
                  leading: const Icon(Icons.piano),
                  title: Text(
                    '${config.notes.length} 个音符 · ${MusicTimeline.overlapCount(config)} 处重叠',
                  ),
                  subtitle: Text(
                    '${config.ticksPerQuarter} PPQ · ${config.tempoEvents.length} 个速度事件 · ${config.timeSignatureEvents.length} 个拍号事件',
                  ),
                ),
                if (config.sourceName != null)
                  ListTile(
                    leading: const Icon(Icons.audio_file_outlined),
                    title: Text('来源：${config.sourceName}'),
                    subtitle: Text('轨道：${config.trackName ?? '未命名'}'),
                  ),
                ListTile(
                  leading: const Icon(Icons.volume_up_outlined),
                  title: const Text('P33 无源蜂鸣器单音播放'),
                  subtitle: Text(
                    '重叠时按「${config.overlapMode.label}」只发声一个'
                    '${config.newNoteInterrupts ? '，新音符打断前一个' : ''}；'
                    '不发声的音符/片段在卷帘里显示为灰色，固件播放完立即循环',
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({
    required this.icon,
    required this.label,
    required this.count,
    required this.color,
  });
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .12),
      borderRadius: BorderRadius.circular(AppCorner.md),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 8),
        Text('$label $count'),
      ],
    ),
  );
}

bool _hasExpressionRows(EngineerConfig config) => config.modes
    .take(config.modeCount ?? 0)
    .any(
      (mode) => mode.actions.any(
        (action) =>
            action.inputKind == ActionInputKind.unspecified ||
            action.outputKind != ActionOutputKind.pin,
      ),
    );

class _ExpressionCheckCard extends ConsumerWidget {
  const _ExpressionCheckCard({required this.config});
  final EngineerConfig config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(expressionCheckControllerProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: state.busy
                  ? null
                  : () => ref
                        .read(expressionCheckControllerProvider.notifier)
                        .check(config),
              icon: state.busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check),
              label: Text(state.busy ? '正在编译检查…' : '检查表达式'),
            ),
            OutlinedButton.icon(
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => _ExpressionPreviewDialog(config: config),
              ),
              icon: const Icon(Icons.calculate_outlined),
              label: const Text('试算表达式'),
            ),
          ],
        ),
        if (state.progress != null) ...[
          const SizedBox(height: 10),
          Text(state.progress!, style: Theme.of(context).textTheme.bodySmall),
        ],
        if (state.message != null) ...[
          const SizedBox(height: 10),
          Text(
            state.message!,
            style: TextStyle(
              color: state.activity == ExpressionCheckActivity.failed
                  ? Theme.of(context).colorScheme.error
                  : null,
            ),
          ),
        ],
        for (final issue in state.issues)
          ListTile(
            dense: true,
            leading: Icon(
              Icons.error_outline,
              color: Theme.of(context).colorScheme.error,
            ),
            title: Text(issue.message),
            subtitle: Text(issue.fieldPath),
          ),
      ],
    );
  }
}

class _ExpressionPreviewDialog extends StatefulWidget {
  const _ExpressionPreviewDialog({required this.config});
  final EngineerConfig config;

  @override
  State<_ExpressionPreviewDialog> createState() =>
      _ExpressionPreviewDialogState();
}

class _ExpressionPreviewDialogState extends State<_ExpressionPreviewDialog> {
  final Map<String, num> _inputs = {
    for (final name in expressionAxisInputs) name: 0,
    for (final name in expressionButtonInputs) name: 0,
  };
  int _modeIndex = 0;

  @override
  Widget build(BuildContext context) {
    final result = EngineerPreview.evaluateMode(
      widget.config,
      _modeIndex,
      _inputs,
    );
    return AlertDialog(
      title: const Text('表达式试算'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _modeIndex,
                decoration: const InputDecoration(labelText: '模式'),
                items: [
                  for (
                    var index = 0;
                    index < (widget.config.modeCount ?? 1);
                    index++
                  )
                    DropdownMenuItem(
                      value: index,
                      child: Text('模式 ${index + 1}'),
                    ),
                ],
                onChanged: (value) => setState(() {
                  if (value != null) _modeIndex = value;
                }),
              ),
              const SizedBox(height: 12),
              for (final name in expressionAxisInputs)
                Row(
                  children: [
                    SizedBox(width: 42, child: Text(name)),
                    Expanded(
                      child: Slider(
                        min: -2047,
                        max: 2047,
                        divisions: 4094,
                        value: (_inputs[name] ?? 0).toDouble(),
                        label: '${_inputs[name] ?? 0}',
                        onChanged: (value) =>
                            setState(() => _inputs[name] = value.round()),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '${_inputs[name] ?? 0}',
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final name in expressionButtonInputs)
                    FilterChip(
                      label: Text(name),
                      selected: (_inputs[name] ?? 0) != 0,
                      onSelected: (selected) =>
                          setState(() => _inputs[name] = selected ? 1 : 0),
                    ),
                ],
              ),
              const Divider(height: 28),
              Text('结果', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              for (final row in result.rows)
                ListTile(
                  dense: true,
                  title: Text(
                    row.error == null ? row.label : '${row.label}：${row.error}',
                  ),
                  subtitle: Text(row.fieldPath),
                  trailing: Text(row.value?.toString() ?? '—'),
                ),
              if (result.variables.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  '变量：${result.variables.entries.map((entry) => '${entry.key}=${entry.value}').join('，')}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}

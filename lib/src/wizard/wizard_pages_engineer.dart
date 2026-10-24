part of '../wizard_screen.dart';

class _EngineerStrategyPage extends ConsumerWidget {
  const _EngineerStrategyPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c =
        ref.watch(appControllerProvider).document!.config as EngineerConfig;
    void update(EngineerConfig v) =>
        ref.read(appControllerProvider.notifier).updateConfig(v);
    void countChanged(int count) {
      final modes = [...c.modes];
      while (modes.length < count) {
        modes.add(EngineerModeConfig());
      }
      update(c.copyWith(modeCount: count, modes: modes));
    }

    return _PageFrame(
      title: '模式切换',
      stepId: 'strategy',
      subtitle: '工程机器人可设置 1–4 套互相独立的控制映射。',
      child: _Section(
        title: '模式策略',
        children: [
          _FieldAnchor(
            path: 'modes.count',
            child: DropdownButtonFormField(
              initialValue: c.modeCount,
              decoration: _fieldDecoration(ref, 'modes.count', '模式数量'),
              items: [1, 2, 3, 4]
                  .map((e) => DropdownMenuItem(value: e, child: Text('$e 个模式')))
                  .toList(),
              onChanged: (v) {
                if (v != null) countChanged(v);
              },
            ),
          ),
          if ((c.modeCount ?? 0) > 1) ...[
            const SizedBox(height: 16),
            _FieldAnchor(
              path: 'modes.switch_strategy',
              child: DropdownButtonFormField<SwitchStrategy>(
                initialValue: c.switchStrategy,
                decoration: _fieldDecoration(
                  ref,
                  'modes.switch_strategy',
                  '切换策略',
                ),
                items: const [
                  DropdownMenuItem(
                    value: SwitchStrategy.cycle,
                    child: Text('单击轮换'),
                  ),
                  DropdownMenuItem(
                    value: SwitchStrategy.direct,
                    child: Text('一一对应'),
                  ),
                ],
                onChanged: (v) => update(c.copyWith(switchStrategy: v)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if ((c.modeCount ?? 0) > 1 &&
              c.switchStrategy == SwitchStrategy.cycle)
            _FieldAnchor(
              path: 'modes.switch_key',
              child: DropdownButtonFormField(
                initialValue: c.modeSwitchKey,
                decoration: _fieldDecoration(ref, 'modes.switch_key', '切换按键'),
                items: digitalRemoteKeys
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: (v) => update(c.copyWith(modeSwitchKey: v)),
              ),
            )
          else if ((c.modeCount ?? 0) > 1 &&
              c.switchStrategy == SwitchStrategy.direct)
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < (c.modeCount ?? 0); i++)
                  SizedBox(
                    width: 190,
                    child: _FieldAnchor(
                      path: 'modes.keys.$i',
                      child: DropdownButtonFormField(
                        initialValue: c.modeKeys[i],
                        decoration: _fieldDecoration(
                          ref,
                          'modes.keys.$i',
                          '模式 ${i + 1} 按键',
                        ),
                        items: digitalRemoteKeys
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                        onChanged: (v) {
                          final keys = [...c.modeKeys];
                          keys[i] = v;
                          update(c.copyWith(modeKeys: keys));
                        },
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}

class _EngineerMappingsPage extends ConsumerStatefulWidget {
  const _EngineerMappingsPage();
  @override
  ConsumerState<_EngineerMappingsPage> createState() =>
      _EngineerMappingsPageState();
}

class _EngineerMappingsPageState extends ConsumerState<_EngineerMappingsPage> {
  int selected = 0;
  @override
  Widget build(BuildContext context) {
    final c =
        ref.watch(appControllerProvider).document!.config as EngineerConfig;
    final modeCount = c.modeCount ?? 0;
    final availableModeCount = modeCount < c.modes.length
        ? modeCount
        : c.modes.length;
    if (selected >= availableModeCount) selected = 0;
    if (availableModeCount == 0) {
      return const _PageFrame(
        title: '动作映射',
        stepId: 'mappings',
        subtitle: '请先完成模式数量配置。',
        child: _InfoBanner('当前没有可编辑的模式，请返回“模式切换”页面。'),
      );
    }
    void updateMode(EngineerModeConfig mode) {
      final modes = [...c.modes];
      modes[selected] = mode;
      ref
          .read(appControllerProvider.notifier)
          .updateConfig(c.copyWith(modes: modes));
    }

    final mode = c.modes[selected];
    final preserveChassis = selected == 0 || mode.preserveChassis;
    return _PageFrame(
      title: '动作映射',
      stepId: 'mappings',
      subtitle: '每个动作都有稳定 ID；增删和切换模式不会让配置串行。',
      child: Column(
        children: [
          ConnectedButtonGroup<int>(
            semanticLabel: '模式',
            segments: [
              for (var i = 0; i < availableModeCount; i++)
                ConnectedSegment(value: i, label: '模式 ${i + 1}'),
            ],
            value: selected,
            onChanged: (value) => setState(() => selected = value),
          ),
          const SizedBox(height: 18),
          _Section(
            title: '模式 ${selected + 1}',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('保留左摇杆底盘控制'),
                value: preserveChassis,
                onChanged: selected == 0
                    ? null
                    : (v) => updateMode(mode.copyWith(preserveChassis: v)),
              ),
              if (selected == 0)
                const _InfoBanner('模式 1 固定保留底盘控制；因此该模式动作不能使用 LX/LY。'),
              for (var i = 0; i < mode.actions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ActionRow(
                    action: mode.actions[i],
                    preserveChassis: preserveChassis,
                    pinRoles: c.pwm.pinRoles,
                    fieldPath: 'modes.$selected.actions.$i',
                    onChanged: (a) {
                      final actions = [...mode.actions];
                      actions[i] = a;
                      updateMode(mode.copyWith(actions: actions));
                    },
                    onRemove: () {
                      final actions = [...mode.actions]..removeAt(i);
                      updateMode(mode.copyWith(actions: actions));
                    },
                  ),
                ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => updateMode(
                  mode.copyWith(actions: [...mode.actions, ActionMapping()]),
                ),
                icon: const Icon(Icons.add),
                label: const Text('添加动作'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({
    required this.action,
    required this.preserveChassis,
    required this.pinRoles,
    required this.fieldPath,
    required this.onChanged,
    required this.onRemove,
  });
  final ActionMapping action;
  final bool preserveChassis;
  final Map<String, PinRole> pinRoles;
  final String fieldPath;
  final ValueChanged<ActionMapping> onChanged;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableInputs = preserveChassis
        ? remoteKeys.where((key) => key != 'LX' && key != 'LY').toList()
        : remoteKeys;
    final visibleInputs = _includeCurrent(availableInputs, action.key);
    final role = action.pin == null
        ? null
        : mainServoPins.contains(action.pin)
        ? PinRole.servo
        : pinRoles[action.pin];
    final isAxis = axisRemoteInputs.contains(action.key);
    final isButton = digitalRemoteKeys.contains(action.key);
    final isMotorRole =
        role != null && role != PinRole.servo && role != PinRole.unused;
    final modes = role == PinRole.servo
        ? isAxis
              ? const [ControlMode.direct, ControlMode.incremental]
              : isButton
              ? const [
                  ControlMode.direct,
                  ControlMode.single,
                  ControlMode.continuous,
                ]
              : const <ControlMode>[]
        : isMotorRole
        ? (isAxis
              ? const [ControlMode.speed, ControlMode.accelerate]
              : isButton
              ? const [ControlMode.direct]
              : const <ControlMode>[])
        : const <ControlMode>[];
    final visibleModes = <ControlMode>[
      if (action.mode != null && !modes.contains(action.mode)) action.mode!,
      ...modes,
    ];
    final usablePins = <String>[
      for (final pin in expansionPins)
        if (pinRoles[pin] != null && pinRoles[pin] != PinRole.unused) pin,
      ...mainServoPins,
    ];
    final visiblePins = _includeCurrent(usablePins, action.pin);
    final usesSensitivity =
        action.mode == ControlMode.single ||
        action.mode == ControlMode.continuous;
    final parameterLabel = usesSensitivity
        ? '灵敏度 °/周期'
        : switch (action.mode) {
            ControlMode.incremental => '步进角度 °',
            ControlMode.speed => '最大速度 duty',
            ControlMode.accelerate => '加速度 duty/周期',
            ControlMode.direct => role == PinRole.servo ? '目标角度 °' : '占空比 duty',
            ControlMode.single || ControlMode.continuous || null => '参数',
          };
    String modeLabel(ControlMode mode) => switch (mode) {
      ControlMode.direct => '直接',
      ControlMode.incremental => '增量',
      ControlMode.speed => '速度',
      ControlMode.accelerate => '增速',
      ControlMode.single => '单次',
      ControlMode.continuous => '持续',
    };
    final fields = <Widget>[
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.key',
          child: DropdownButtonFormField(
            initialValue: action.key,
            decoration: _fieldDecoration(ref, '$fieldPath.key', '按键'),
            items: visibleInputs
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => onChanged(action.copyWith(key: v)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.direction',
          child: DropdownButtonFormField(
            initialValue: action.direction,
            decoration: _fieldDecoration(ref, '$fieldPath.direction', '方向'),
            items: Direction.values
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e == Direction.forward ? '正' : '反'),
                  ),
                )
                .toList(),
            onChanged: (v) => onChanged(action.copyWith(direction: v)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.mode',
          child: DropdownButtonFormField(
            key: ValueKey('$fieldPath.mode'),
            initialValue: action.mode,
            decoration: _fieldDecoration(ref, '$fieldPath.mode', '控制方式'),
            selectedItemBuilder: (context) => [
              for (final mode in visibleModes) Text(modeLabel(mode)),
            ],
            items: visibleModes.map((e) {
              final label = modeLabel(e);
              final supported = modes.contains(e);
              return DropdownMenuItem(
                value: e,
                enabled: supported,
                child: Text('$label${supported ? '' : '（当前配置，不支持）'}'),
              );
            }).toList(),
            onChanged: (v) => onChanged(action.copyWith(mode: v)),
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: usesSensitivity
            ? _NumberField<double>(
                label: parameterLabel,
                fieldPath: '$fieldPath.parameter',
                value: action.parameter?.toDouble(),
                onChanged: (v) => onChanged(action.copyWith(parameter: v)),
              )
            : _NumberField(
                label: parameterLabel,
                fieldPath: '$fieldPath.parameter',
                value: action.parameter?.toInt(),
                onChanged: (v) => onChanged(action.copyWith(parameter: v)),
              ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.pin',
          child: DropdownButtonFormField(
            initialValue: action.pin,
            decoration: _fieldDecoration(ref, '$fieldPath.pin', 'IO'),
            items: visiblePins
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => onChanged(action.copyWith(pin: v)),
          ),
        ),
      ),
    ];
    return Card(
      // 动作卡嵌在 _Section 卡片里，用 block 色调保持「越往里越深」的层级。
      color: AppSurface.block.colorOf(Theme.of(context).colorScheme),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            if (constraints.maxWidth < _compactBreakpoint) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '动作配置',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                      IconButton(
                        onPressed: onRemove,
                        tooltip: '删除动作',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                  ..._unflexChildren(fields, spacing: 10),
                ],
              );
            }
            return Row(
              children: [
                ...fields,
                IconButton(
                  onPressed: onRemove,
                  tooltip: '删除动作',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

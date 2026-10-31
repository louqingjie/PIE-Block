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
    final chassisEnabled = c.chassis.enabled;
    final preserveChassis = chassisEnabled && mode.preserveChassis;
    final actionKeys = <Key>[];
    final occurrences = <String, int>{};
    for (final action in mode.actions) {
      final occurrence = occurrences.update(
        action.id,
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      actionKeys.add(ValueKey('${action.id}#$occurrence'));
    }
    // 问题面板按字段路径跳转，必须让屏幕外的动作行保持挂载。
    final cacheExtent =
        (mode.actions.length + 1) * (_isCompact(context) ? 680.0 : 360.0) + 400;
    return _PageFrame(
      title: '动作映射',
      stepId: 'mappings',
      subtitle: '每个动作都有稳定 ID；拖动左侧手柄即可调整执行顺序。',
      fill: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
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
          Expanded(
            child: ReorderableListView.builder(
              buildDefaultDragHandles: false,
              scrollCacheExtent: ScrollCacheExtent.pixels(cacheExtent),
              proxyDecorator: _reorderDragProxy,
              dragBoundaryProvider: _reorderDragBoundary,
              onReorderStart: (_) => _endTextInput(ref),
              header: Padding(
                padding: const EdgeInsets.only(bottom: _reorderCardGap),
                child: _Section(
                  title: '模式 ${selected + 1}',
                  children: [
                    if (chassisEnabled)
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('保留左摇杆底盘控制'),
                        value: preserveChassis,
                        onChanged: (v) =>
                            updateMode(mode.copyWith(preserveChassis: v)),
                      )
                    else
                      const _InfoBanner('未启用底盘控制，本模式不保留底盘控制，LX/LY 可用于动作。'),
                  ],
                ),
              ),
              footer: Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: () => updateMode(
                      mode.copyWith(
                        actions: [...mode.actions, ActionMapping()],
                      ),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加动作'),
                  ),
                ),
              ),
              itemCount: mode.actions.length,
              onReorderItem: (oldIndex, newIndex) {
                if (oldIndex == newIndex) return;
                final actions = [...mode.actions];
                actions.insert(newIndex, actions.removeAt(oldIndex));
                updateMode(mode.copyWith(actions: actions));
              },
              itemBuilder: (context, index) {
                final action = mode.actions[index];
                return _ActionRow(
                  key: actionKeys[index],
                  index: index,
                  action: action,
                  preserveChassis: preserveChassis,
                  pinRoles: c.pwm.pinRoles,
                  fieldPath: 'modes.$selected.actions.$index',
                  onChanged: (a) {
                    final actions = [...mode.actions];
                    actions[index] = a;
                    updateMode(mode.copyWith(actions: actions));
                  },
                  onRemove: () {
                    final actions = [...mode.actions]..removeAt(index);
                    updateMode(mode.copyWith(actions: actions));
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends ConsumerWidget {
  const _ActionRow({
    super.key,
    required this.index,
    required this.action,
    required this.preserveChassis,
    required this.pinRoles,
    required this.fieldPath,
    required this.onChanged,
    required this.onRemove,
  });
  final int index;
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
    final modes = role == PinRole.friction
        ? isAxis
              ? const [ControlMode.frictionAxis]
              : isButton
              ? const [
                  ControlMode.frictionToggle,
                  ControlMode.frictionStep,
                  ControlMode.frictionContinuous,
                ]
              : const <ControlMode>[]
        : role == PinRole.servo
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
            ControlMode.frictionToggle => '目标油门 %',
            ControlMode.frictionStep => '每次油门 %',
            ControlMode.frictionContinuous => '每秒油门 %',
            ControlMode.frictionAxis => '满杆每秒 %',
            ControlMode.single || ControlMode.continuous || null => '参数',
          };
    String modeLabel(ControlMode mode) => switch (mode) {
      ControlMode.direct => '直接',
      ControlMode.incremental => '增量',
      ControlMode.speed => '速度',
      ControlMode.accelerate => '增速',
      ControlMode.single => '单次',
      ControlMode.continuous => '持续',
      ControlMode.frictionToggle => '启停',
      ControlMode.frictionStep => '油门单次',
      ControlMode.frictionContinuous => '油门持续',
      ControlMode.frictionAxis => '摇杆油门',
    };
    const unspecifiedInputToken = '__unspecified__';
    const integerOutputToken = '__output_integer__';
    const rationalOutputToken = '__output_rational__';
    final inputUnspecified = action.inputKind == ActionInputKind.unspecified;
    final variableOutput = action.outputKind != ActionOutputKind.pin;
    final pinOutput = !variableOutput;
    final directionVisible =
        pinOutput &&
        !inputUnspecified &&
        action.mode != ControlMode.frictionToggle &&
        action.mode != ControlMode.frictionAxis;
    final inputChoices = <String>[unspecifiedInputToken, ...visibleInputs];
    final inputValue = inputUnspecified ? unspecifiedInputToken : action.key;
    final outputChoices = <String>[
      ...visiblePins,
      integerOutputToken,
      rationalOutputToken,
    ];
    final outputValue = pinOutput
        ? action.pin
        : action.outputKind == ActionOutputKind.integer
        ? integerOutputToken
        : rationalOutputToken;
    final primaryFields = <Widget>[
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.key',
          child: DropdownButtonFormField<String>(
            key: ValueKey('$fieldPath.key'),
            initialValue: inputValue,
            decoration: _fieldDecoration(ref, '$fieldPath.key', '输入'),
            items: inputChoices
                .map(
                  (e) => DropdownMenuItem(
                    value: e,
                    child: Text(e == unspecifiedInputToken ? '未指定' : e),
                  ),
                )
                .toList(),
            onChanged: (v) {
              if (v == null) return;
              if (v == unspecifiedInputToken) {
                onChanged(
                  action.copyWith(
                    inputKind: ActionInputKind.unspecified,
                    key: null,
                    direction: null,
                    mode: null,
                    parameter: null,
                  ),
                );
              } else {
                onChanged(
                  action.copyWith(
                    inputKind: ActionInputKind.remote,
                    key: v,
                    expression: null,
                  ),
                );
              }
            },
          ),
        ),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: _FieldAnchor(
          path: '$fieldPath.pin',
          child: DropdownButtonFormField<String>(
            key: ValueKey('$fieldPath.pin'),
            initialValue: outputValue,
            decoration: _fieldDecoration(ref, '$fieldPath.pin', '输出'),
            items: outputChoices.map((e) {
              final label = switch (e) {
                integerOutputToken => '整数',
                rationalOutputToken => '有理数',
                _ => e,
              };
              return DropdownMenuItem(value: e, child: Text(label));
            }).toList(),
            onChanged: (v) {
              if (v == null) return;
              if (v == integerOutputToken || v == rationalOutputToken) {
                onChanged(
                  action.copyWith(
                    outputKind: v == integerOutputToken
                        ? ActionOutputKind.integer
                        : ActionOutputKind.rational,
                    pin: null,
                    direction: null,
                    mode: null,
                    parameter: null,
                  ),
                );
              } else {
                onChanged(
                  action.copyWith(
                    outputKind: ActionOutputKind.pin,
                    pin: v,
                    variableName: null,
                  ),
                );
              }
            },
          ),
        ),
      ),
      if (directionVisible) ...[
        const SizedBox(width: 8),
        Expanded(
          child: _FieldAnchor(
            path: '$fieldPath.direction',
            child: DropdownButtonFormField(
              key: ValueKey('$fieldPath.direction'),
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
      ],
      if (pinOutput && !inputUnspecified) ...[
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
              onChanged: (v) {
                final clearsDirection =
                    v == ControlMode.frictionToggle ||
                    v == ControlMode.frictionAxis;
                onChanged(
                  action.copyWith(
                    mode: v,
                    direction: clearsDirection ? null : action.direction,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    ];
    final secondaryFields = <Widget>[
      if (pinOutput && !inputUnspecified)
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
      if (variableOutput) ...[
        if (secondaryFieldsNotEmpty(pinOutput, inputUnspecified))
          const SizedBox(width: 8),
        Expanded(
          child: _TextField(
            label: '变量名',
            value: action.variableName,
            fieldPath: '$fieldPath.variable',
            onChanged: (v) => onChanged(
              action.copyWith(variableName: v.trim().isEmpty ? null : v),
            ),
          ),
        ),
      ],
      if (inputUnspecified) ...[
        if (pinOutput || variableOutput) const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: _TextField(
            label: '表达式',
            value: action.expression,
            fieldPath: '$fieldPath.expression',
            monospace: true,
            hint: '例如 LX + LY、min(LX, 2047) * 4、sqrt(PI)',
            onChanged: (v) =>
                onChanged(action.copyWith(expression: v.isEmpty ? null : v)),
          ),
        ),
      ],
    ];
    return Card(
      color: AppSurface.block.colorOf(Theme.of(context).colorScheme),
      margin: const EdgeInsets.only(bottom: _reorderCardGap),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                ReorderableDragStartListener(
                  index: index,
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.drag_indicator),
                  ),
                ),
                Expanded(
                  child: Text(
                    '动作 ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: onRemove,
                  tooltip: '删除动作',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _AdaptiveRow(children: primaryFields),
            if (secondaryFields.isNotEmpty) ...[
              const SizedBox(height: 10),
              _AdaptiveRow(children: secondaryFields),
            ],
          ],
        ),
      ),
    );
  }

  bool secondaryFieldsNotEmpty(bool pinOutput, bool inputUnspecified) =>
      pinOutput && !inputUnspecified;
}

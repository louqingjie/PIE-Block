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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var tableIndex = 0;
                        tableIndex < mode.actionTables.length;
                        tableIndex++) ...[
                      _ActionTableCard(
                        key: ValueKey(
                          'action-table-${mode.actionTables[tableIndex].id}',
                        ),
                        index: tableIndex,
                        table: mode.actionTables[tableIndex],
                        pwm: c.pwm,
                        fieldPath: 'modes.$selected.action_tables.$tableIndex',
                        onChanged: (table) {
                          final tables = [...mode.actionTables];
                          tables[tableIndex] = table;
                          updateMode(mode.copyWith(actionTables: tables));
                        },
                        onRemove: () {
                          final tables = [...mode.actionTables]
                            ..removeAt(tableIndex);
                          updateMode(mode.copyWith(actionTables: tables));
                        },
                        onDuplicate: () {
                          final tables = [...mode.actionTables];
                          tables.insert(
                            tableIndex + 1,
                            mode.actionTables[tableIndex].duplicate(),
                          );
                          updateMode(mode.copyWith(actionTables: tables));
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: () => updateMode(
                            mode.copyWith(
                              actions: [...mode.actions, ActionMapping()],
                            ),
                          ),
                          icon: const Icon(Icons.add),
                          label: const Text('添加动作'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: () => updateMode(
                            mode.copyWith(
                              actionTables: [
                                ...mode.actionTables,
                                ActionTable(steps: 2),
                              ],
                            ),
                          ),
                          icon: const Icon(Icons.table_chart_outlined),
                          label: const Text('添加动作表'),
                        ),
                      ],
                    ),
                  ],
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
                  pwm: c.pwm,
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
                  onDuplicate: () {
                    final actions = [...mode.actions];
                    actions.insert(index + 1, action.duplicate());
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
    required this.pwm,
    required this.fieldPath,
    required this.onChanged,
    required this.onRemove,
    required this.onDuplicate,
  });
  final int index;
  final ActionMapping action;
  final bool preserveChassis;
  final PwmGroupConfig pwm;
  final String fieldPath;
  final ValueChanged<ActionMapping> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final availableInputs = preserveChassis
        ? remoteKeys.where((key) => key != 'LX' && key != 'LY').toList()
        : remoteKeys;
    final visibleInputs = _includeCurrent(availableInputs, action.key);
    final role = action.pin == null ? null : pwm.roleOf(action.pin!);
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
        if (pwm.pinRoles[pin] != null && pwm.pinRoles[pin] != PinRole.unused)
          pin,
      // 主控板 MP03/MP74 缺省按舵机可选；显式标为「未使用」后不再出现在
      // 动作输出引脚中，设为摩擦轮时同样可以作为动作输出。
      for (final pin in mainServoPins)
        if (pwm.isServoPin(pin) || pwm.roleOf(pin) == PinRole.friction) pin,
    ];
    final visiblePins = _includeCurrent(usablePins, action.pin);
    final usesSensitivity =
        action.mode == ControlMode.single ||
        action.mode == ControlMode.continuous;
    final parameterLabel = usesSensitivity
        ? '灵敏度 °/周期（带符号）'
        : switch (action.mode) {
            ControlMode.incremental => '步进角度 °（带符号）',
            ControlMode.speed => '最大速度 duty',
            ControlMode.accelerate => '加速度 duty/周期',
            ControlMode.direct => role == PinRole.servo
                ? '目标角度 °（带符号）'
                : '转速 duty（带符号）',
            ControlMode.frictionToggle => '目标油门 %',
            ControlMode.frictionStep => '每次油门 %（正加负减）',
            ControlMode.frictionContinuous => '每秒油门 %（正加负减）',
            ControlMode.frictionAxis => '满杆每秒 %',
            ControlMode.single || ControlMode.continuous || null => '参数',
          };
    // 同一个「直接」在电机按键（按住）、舵机按键（按下）与摇杆（跟随）下
    // 是三种触发语义，标签必须带后缀，否则用户无法从界面区分。
    String modeLabel(ControlMode mode) {
      final base = switch (mode) {
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
      final suffix = switch (mode) {
        ControlMode.direct => role == PinRole.servo
            ? (isAxis ? '（跟随）' : '（按下）')
            : (isAxis ? '（跟随）' : '（按住）'),
        ControlMode.incremental => isAxis ? '（累加）' : '',
        ControlMode.speed => '（跟随）',
        ControlMode.accelerate => '（累加）',
        ControlMode.single => '（按下）',
        ControlMode.continuous => isAxis ? '（累加）' : '（按住）',
        ControlMode.frictionToggle => '（按下）',
        ControlMode.frictionStep => '（按下）',
        ControlMode.frictionContinuous => '（按住）',
        ControlMode.frictionAxis => '（跟随）',
      };
      return '$base$suffix';
    }

    String? modeHint(ControlMode? mode) {
      if (mode == null) return null;
      if (role == PinRole.servo) {
        return switch (mode) {
          ControlMode.direct =>
            isAxis ? '随摇杆实时跟随目标角度' : '按一下到达目标角度，松开保持',
          ControlMode.incremental => '每周期按摇杆量累加角度',
          ControlMode.single => '每按一次增加一档角度，松开保持',
          ControlMode.continuous => '按住期间持续增加角度，松开保持',
          _ => null,
        };
      }
      if (role == PinRole.friction) {
        return switch (mode) {
          ControlMode.frictionToggle => '按一下在 0 与目标油门之间切换',
          ControlMode.frictionStep => '每按一次加/减一档油门',
          ControlMode.frictionContinuous => '按住期间持续加/减油门',
          ControlMode.frictionAxis => '满杆时按每秒速率加/减油门',
          _ => null,
        };
      }
      return switch (mode) {
        ControlMode.direct => isAxis ? '摇杆离开死区即满值输出' : '按住才输出，松开归零',
        ControlMode.speed => '摇杆幅度按比例输出，回中归零',
        ControlMode.accelerate => '每周期按摇杆量累加，回中保持',
        _ => null,
      };
    }
    const unspecifiedInputToken = '__unspecified__';
    const integerOutputToken = '__output_integer__';
    const rationalOutputToken = '__output_rational__';
    final inputUnspecified = action.inputKind == ActionInputKind.unspecified;
    final variableOutput = action.outputKind != ActionOutputKind.pin;
    final pinOutput = !variableOutput;
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
            isExpanded: true,
            decoration: _fieldDecoration(ref, '$fieldPath.pin', '输出'),
            items: outputChoices.map((e) {
              final label = switch (e) {
                integerOutputToken => '整数',
                rationalOutputToken => '有理数',
                _ => _pinLabel(pwm, e),
              };
              return DropdownMenuItem(
                value: e,
                child: Text(label, overflow: TextOverflow.ellipsis),
              );
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
                // 摇杆/启停类模式的方向由输入符号决定，参数只保留幅值。
                final unsigned =
                    v == ControlMode.speed ||
                    v == ControlMode.accelerate ||
                    v == ControlMode.frictionToggle ||
                    v == ControlMode.frictionAxis;
                onChanged(
                  action.copyWith(
                    mode: v,
                    parameter: unsigned && action.parameter != null
                        ? action.parameter!.abs()
                        : action.parameter,
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
                  onPressed: onDuplicate,
                  tooltip: '复制动作',
                  icon: const Icon(Icons.copy),
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
            if (modeHint(action.mode) case final hint?) ...[
              const SizedBox(height: 10),
              Text(
                hint,
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  bool secondaryFieldsNotEmpty(bool pinOutput, bool inputUnspecified) =>
      pinOutput && !inputUnspecified;
}

/// 动作映射里引脚下拉的显示名：有备注时写成 `引脚（备注）`。
String _pinLabel(PwmGroupConfig pwm, String pin) {
  final note = pwm.pinNotes[pin];
  return note == null ? pin : '$pin（$note）';
}

/// 动作表里可配置的输出引脚：舵机、电机、抖动电机；摩擦轮与未使用口排除。
bool _tablePinAllowed(PwmGroupConfig pwm, String pin) {
  final role = pwm.roleOf(pin);
  return role != null && role != PinRole.unused && role != PinRole.friction;
}

/// 按键动作表卡片：一个按键循环切档，表格的每一列是一档。
class _ActionTableCard extends ConsumerStatefulWidget {
  const _ActionTableCard({
    super.key,
    required this.index,
    required this.table,
    required this.pwm,
    required this.fieldPath,
    required this.onChanged,
    required this.onRemove,
    required this.onDuplicate,
  });

  final int index;
  final ActionTable table;
  final PwmGroupConfig pwm;
  final String fieldPath;
  final ValueChanged<ActionTable> onChanged;
  final VoidCallback onRemove;
  final VoidCallback onDuplicate;

  @override
  ConsumerState<_ActionTableCard> createState() => _ActionTableCardState();
}

class _ActionTableCardState extends ConsumerState<_ActionTableCard> {
  /// 新建的动作表默认展开；已有动作表默认收起，避免占满列表。
  late bool _expanded = widget.table.key == null;

  static const _noPrevious = '__none__';

  List<String> get _availablePins => [
    for (final pin in [...expansionPins, ...mainServoPins])
      if (_tablePinAllowed(widget.pwm, pin)) pin,
  ];

  void _update(ActionTable table) => widget.onChanged(table);

  ActionTable _withSteps(ActionTable table, int? value) {
    final steps = value?.clamp(2, 8).toInt();
    return table.copyWith(
      steps: value,
      rows: steps == null
          ? null
          : [
              for (final row in table.rows)
                row.copyWith(
                  values: [
                    for (var i = 0; i < steps; i++)
                      i < row.values.length ? row.values[i] : null,
                  ],
                ),
            ],
    );
  }

  void _updateCell(ActionTable table, int rowIndex, int step, int? value) {
    final rows = [...table.rows];
    final values = [...rows[rowIndex].values];
    while (values.length <= step) {
      values.add(null);
    }
    values[step] = value;
    rows[rowIndex] = rows[rowIndex].copyWith(values: values);
    _update(table.copyWith(rows: rows));
  }

  @override
  Widget build(BuildContext context) {
    final table = widget.table;
    final steps = table.steps ?? 2;
    final summary = [
      if (table.key != null) '键 ${table.key}',
      table.steps == null ? '档数未填' : '${table.steps} 档',
      if (table.previousKey != null) '上一档 ${table.previousKey}',
    ].join(' · ');
    final hintStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Card(
      key: ValueKey('action-table-card-${table.id}'),
      color: AppSurface.block.colorOf(Theme.of(context).colorScheme),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  tooltip: _expanded ? '收起动作表' : '展开动作表',
                  icon: Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ),
                Expanded(
                  child: Text(
                    '动作表 ${widget.index + 1}'
                    '${summary.isEmpty ? '' : ' · $summary'}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  onPressed: widget.onDuplicate,
                  tooltip: '复制动作表',
                  icon: const Icon(Icons.copy),
                ),
                IconButton(
                  onPressed: widget.onRemove,
                  tooltip: '删除动作表',
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ),
            if (_expanded) ...[
              const SizedBox(height: 8),
              _AdaptiveRow(
                children: [
                  Expanded(
                    child: _FieldAnchor(
                      path: '${widget.fieldPath}.key',
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${widget.fieldPath}.key'),
                        initialValue: table.key,
                        isExpanded: true,
                        decoration: _fieldDecoration(
                          ref,
                          '${widget.fieldPath}.key',
                          '下一档键',
                        ),
                        items: [
                          for (final key in _includeCurrent(
                            digitalRemoteKeys,
                            table.key,
                          ))
                            DropdownMenuItem(value: key, child: Text(key)),
                        ],
                        onChanged: (value) =>
                            _update(table.copyWith(key: value)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FieldAnchor(
                      path: '${widget.fieldPath}.prev_key',
                      child: DropdownButtonFormField<String>(
                        key: ValueKey('${widget.fieldPath}.prev_key'),
                        initialValue: table.previousKey ?? _noPrevious,
                        isExpanded: true,
                        decoration: _fieldDecoration(
                          ref,
                          '${widget.fieldPath}.prev_key',
                          '上一档键',
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: _noPrevious,
                            child: Text('不使用'),
                          ),
                          for (final key in _includeCurrent(
                            digitalRemoteKeys,
                            table.previousKey,
                          ))
                            DropdownMenuItem(value: key, child: Text(key)),
                        ],
                        onChanged: (value) => _update(
                          table.copyWith(
                            previousKey: value == _noPrevious ? null : value,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField<int>(
                      label: '档位数',
                      value: table.steps,
                      fieldPath: '${widget.fieldPath}.steps',
                      onChanged: (value) => _update(_withSteps(table, value)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildTable(table, steps),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: () => _update(
                    table.copyWith(
                      rows: [
                        ...table.rows,
                        ActionTableRow(values: List.filled(steps, null)),
                      ],
                    ),
                  ),
                  icon: const Icon(Icons.add),
                  label: const Text('添加引脚'),
                ),
              ),
              Text(
                '按一下前进一档，最后一档后回到第一档；每档整列写入后保持。',
                style: hintStyle,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTable(ActionTable table, int steps) {
    return Table(
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      columnWidths: {
        0: const FixedColumnWidth(240),
        for (var step = 0; step < steps; step++)
          step + 1: const FixedColumnWidth(148),
        steps + 1: const FixedColumnWidth(44),
      },
      children: [
        TableRow(
          children: [
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
              child: Text('引脚', style: TextStyle(fontSize: 12)),
            ),
            for (var step = 0; step < steps; step++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                child: Text(
                  '档 ${step + 1}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const SizedBox.shrink(),
          ],
        ),
        for (var rowIndex = 0; rowIndex < table.rows.length; rowIndex++)
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.all(4),
                child: _FieldAnchor(
                  path: '${widget.fieldPath}.rows.$rowIndex.pin',
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('${widget.fieldPath}.rows.$rowIndex.pin'),
                    initialValue: table.rows[rowIndex].pin,
                    isExpanded: true,
                    decoration: _fieldDecoration(
                      ref,
                      '${widget.fieldPath}.rows.$rowIndex.pin',
                      '',
                    ),
                    items: [
                      for (final pin in _includeCurrent(
                        _availablePins,
                        table.rows[rowIndex].pin,
                      ))
                        DropdownMenuItem(
                          value: pin,
                          child: Text(
                            _pinLabel(widget.pwm, pin),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (value) {
                      final rows = [...table.rows];
                      rows[rowIndex] = rows[rowIndex].copyWith(pin: value);
                      _update(table.copyWith(rows: rows));
                    },
                  ),
                ),
              ),
              for (var step = 0; step < steps; step++)
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: _TableCellField(
                    value: step < table.rows[rowIndex].values.length
                        ? table.rows[rowIndex].values[step]
                        : null,
                    fieldPath:
                        '${widget.fieldPath}.rows.$rowIndex.values.$step',
                    // 舵机填相对中位的角度，电机/抖动电机填转速。
                    label: switch (table.rows[rowIndex].pin) {
                      final pin? when widget.pwm.isServoPin(pin) => '角度',
                      null => '数值',
                      _ => '转速',
                    },
                    onChanged: (value) =>
                        _updateCell(table, rowIndex, step, value),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton(
                  onPressed: () {
                    final rows = [...table.rows]..removeAt(rowIndex);
                    _update(table.copyWith(rows: rows));
                  },
                  tooltip: '删除引脚',
                  icon: const Icon(Icons.close, size: 18),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

/// 动作表格子里的整数输入框：尺寸与引脚下拉框一致，沿用焦点绑定与字段错误描边。
class _TableCellField extends ConsumerStatefulWidget {
  const _TableCellField({
    required this.value,
    required this.onChanged,
    required this.fieldPath,
    required this.label,
  });

  final int? value;
  final ValueChanged<int?> onChanged;
  final String fieldPath;
  final String label;

  @override
  ConsumerState<_TableCellField> createState() => _TableCellFieldState();
}

class _TableCellFieldState extends ConsumerState<_TableCellField> {
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _TableCellField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldPath != widget.fieldPath) {
      _unbindFocusNode(oldWidget.fieldPath);
      _bindFocusNode();
    }
  }

  void _bindFocusNode() {
    final path = widget.fieldPath;
    final node = FocusNode(debugLabel: path)..addListener(_handleFocusChange);
    _focusNode = node;
    _fieldFocusNodes[path] = node;
  }

  void _unbindFocusNode(String path) {
    final node = _focusNode;
    if (node == null) return;
    if (identical(_fieldFocusNodes[path], node)) {
      _fieldFocusNodes.remove(path);
    }
    node.removeListener(_handleFocusChange);
    node.dispose();
    _focusNode = null;
  }

  void _handleFocusChange() {
    final path = widget.fieldPath;
    final controller = ref.read(_activeInputFieldProvider.notifier);
    if (_focusNode?.hasFocus ?? false) {
      controller.focus(path);
    } else {
      controller.blur(path);
    }
  }

  @override
  void dispose() {
    _unbindFocusNode(widget.fieldPath);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _FieldAnchor(
      path: widget.fieldPath,
      focusHandledByChild: true,
      child: TextFormField(
        key: ValueKey(widget.fieldPath),
        focusNode: _focusNode,
        initialValue: widget.value?.toString() ?? '',
        keyboardType: const TextInputType.numberWithOptions(signed: true),
        textAlign: TextAlign.center,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
        decoration: _fieldDecoration(
          ref,
          widget.fieldPath,
          widget.label,
        ).copyWith(floatingLabelBehavior: FloatingLabelBehavior.always),
        onChanged: (text) =>
            widget.onChanged(text.isEmpty ? null : int.tryParse(text)),
      ),
    );
  }
}

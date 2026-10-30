part of '../wizard_screen.dart';

class _PinOption extends StatelessWidget {
  const _PinOption(this.pin, {this.owner, this.enabled = true});
  final String pin;
  final String? owner;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
    decoration: BoxDecoration(
      color: enabled
          ? Colors.transparent
          : Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppCorner.sm),
    ),
    child: Row(
      children: [
        if (!enabled) ...[
          Icon(
            Icons.lock_outline,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            owner == null ? pin : '$pin · $owner',
            overflow: TextOverflow.ellipsis,
            style: enabled
                ? null
                : TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ],
    ),
  );
}

List<Widget> _selectedPinItems(Iterable<String?> pins) => [
  for (final pin in pins)
    Align(
      alignment: Alignment.centerLeft,
      child: Text(pin ?? '未分配', maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
];

String _pinOccupantLabels(InfantryPinReassignmentPlan plan) =>
    plan.occupants.expand((occupant) => occupant.ownerLabels).toSet().join('、');

InfantryConfig _reassignmentResult(
  InfantryPinReassignmentPlan plan,
  InfantryPinReassignmentStrategy strategy,
) => plan.options.firstWhere((option) => option.strategy == strategy).result;

Future<InfantryConfig?> _resolveInfantryPinSelection(
  BuildContext context,
  InfantryConfig config,
  String fieldPath,
  String? targetPin,
) async {
  final plan = InfantryPinPlanner.planReassignment(
    config,
    fieldPath,
    targetPin,
  );
  if (!plan.hasConflict) {
    return _reassignmentResult(plan, InfantryPinReassignmentStrategy.direct);
  }

  final target = InfantryPinPlanner.normalizePin(targetPin);
  final sourceLabel = _fieldLabel(fieldPath);
  final occupantLabels = _pinOccupantLabels(plan);
  final disablesFriction = plan.supports(
    InfantryPinReassignmentStrategy.disableFrictionAndTakeOver,
  );
  final strategy = await showDialog<InfantryPinReassignmentStrategy>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('$target 已被占用'),
      content: Text(
        disablesFriction
            ? '$sourceLabel 要使用 $target，但该引脚由固定摩擦轮占用。确认后将关闭摩擦轮并保留已有摩擦轮参数。'
            : '$sourceLabel 要使用 $target，当前由 $occupantLabels 占用。${plan.supports(InfantryPinReassignmentStrategy.swap) ? '可以交换双方引脚，或让原设备暂时未分配。' : '当前引脚无法合法交换，只能让原设备暂时未分配。'}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (disablesFriction)
          FilledButton(
            onPressed: () => Navigator.pop(
              context,
              InfantryPinReassignmentStrategy.disableFrictionAndTakeOver,
            ),
            child: const Text('关闭摩擦轮并占用'),
          )
        else ...[
          OutlinedButton(
            onPressed: () => Navigator.pop(
              context,
              InfantryPinReassignmentStrategy.takeOver,
            ),
            child: const Text('占用并解除原分配'),
          ),
          if (plan.supports(InfantryPinReassignmentStrategy.swap))
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, InfantryPinReassignmentStrategy.swap),
              child: const Text('交换引脚'),
            ),
        ],
      ],
    ),
  );
  if (strategy == null) return null;
  return _reassignmentResult(plan, strategy);
}

Future<InfantryConfig?> _resolveFrictionModeSelection(
  BuildContext context,
  InfantryConfig config,
  FrictionMode? mode,
) async {
  if (mode == null) return null;
  if (mode == FrictionMode.disabled) {
    return config.copyWith(frictionMode: FrictionMode.disabled);
  }
  final plan = InfantryPinPlanner.planFrictionEnablement(config);
  if (!plan.hasConflict) {
    return _reassignmentResult(plan, InfantryPinReassignmentStrategy.direct);
  }
  final occupantLabels = _pinOccupantLabels(plan);
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('P64/P66 已被占用'),
      content: Text(
        '启用无刷电调摩擦轮需要固定使用 P64/P66，当前占用者为 $occupantLabels。确认后这些设备将变为未分配。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('解除占用并启用'),
        ),
      ],
    ),
  );
  if (confirmed != true) return null;
  return _reassignmentResult(
    plan,
    InfantryPinReassignmentStrategy.enableFrictionAndTakeOver,
  );
}

class _InfantryMechanismPage extends ConsumerWidget {
  const _InfantryMechanismPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c =
            ref.watch(appControllerProvider).document!.config as InfantryConfig,
        ctrl = ref.read(appControllerProvider.notifier);
    void update(InfantryConfig value) => ctrl.updateConfig(value);
    final feederPins = _includeCurrent(
      InfantryPinPlanner.motorPins,
      c.feederPin,
    );
    final feederPinChoices = <String?>[null, ...feederPins];
    Widget axis(String name, bool yaw) {
      final actuators = c.actuators(yaw);
      void replaceActuators(List<AxisActuator> next) => update(
        yaw ? c.copyWith(yawActuators: next) : c.copyWith(pitchActuators: next),
      );
      Widget actuatorRow(int index) {
        final actuator = actuators[index],
            drive = actuator.drive,
            pin = actuator.pin,
            direction = actuator.direction,
            mid = actuator.midOffset,
            ccw = actuator.maxLimit,
            cw = actuator.minLimit == null ? null : -actuator.minLimit!,
            pinPath = InfantryPinPlanner.axisPath(yaw, index, 'pin'),
            drivePath = InfantryPinPlanner.axisPath(yaw, index, 'drive'),
            directionPath = InfantryPinPlanner.axisPath(
              yaw,
              index,
              'direction',
            ),
            midPath = InfantryPinPlanner.axisPath(yaw, index, 'mid_offset'),
            // 逆时针存非负的 max_limit，顺时针存非正的 min_limit。
            ccwPath = InfantryPinPlanner.axisPath(yaw, index, 'max_limit'),
            cwPath = InfantryPinPlanner.axisPath(yaw, index, 'min_limit');
        void updateAt(AxisActuator Function(AxisActuator) change) {
          final next = [...actuators];
          next[index] = change(next[index]);
          replaceActuators(next);
        }

        final allowedPins = InfantryPinPlanner.allowedPins(
          c,
          pinPath,
          driveType: drive,
        );
        final candidates = switch (drive) {
          DriveType.servo => InfantryPinPlanner.servoPins,
          DriveType.motor => InfantryPinPlanner.motorPins,
          null => const <String>[],
        };
        final visiblePins = _includeCurrent(candidates, pin);
        final visiblePinChoices = <String?>[null, ...visiblePins];
        return _FormRow(
          fieldPaths: [
            drivePath,
            pinPath,
            directionPath,
            if (drive == DriveType.servo) ...[midPath, ccwPath, cwPath],
          ],
          children: [
            Expanded(
              child: _FieldAnchor(
                path: drivePath,
                child: DropdownButtonFormField(
                  initialValue: drive,
                  decoration: _fieldDecoration(ref, drivePath, '驱动类型'),
                  items: DriveType.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e == DriveType.servo ? '舵机' : '电机'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    updateAt((a) => a.copyWith(drive: v));
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FieldAnchor(
                path: pinPath,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(pinPath),
                  isExpanded: true,
                  initialValue: pin,
                  decoration: _fieldDecoration(ref, pinPath, 'IO'),
                  selectedItemBuilder: (_) =>
                      _selectedPinItems(visiblePinChoices),
                  items: visiblePinChoices.map((e) {
                    if (e == null) {
                      return const DropdownMenuItem<String>(
                        value: null,
                        child: Text('未分配'),
                      );
                    }
                    final enabled = allowedPins.contains(e);
                    final owner = InfantryPinPlanner.occupiedBy(c, e, pinPath);
                    return DropdownMenuItem(
                      value: e,
                      enabled: enabled,
                      child: _PinOption(
                        e,
                        enabled: enabled,
                        owner:
                            owner?.ownerLabel ?? (enabled ? null : '当前驱动类型不支持'),
                      ),
                    );
                  }).toList(),
                  onChanged: (v) async {
                    final result = await _resolveInfantryPinSelection(
                      context,
                      c,
                      pinPath,
                      v,
                    );
                    if (result != null) update(result);
                  },
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _FieldAnchor(
                path: directionPath,
                child: DropdownButtonFormField(
                  initialValue: direction,
                  decoration: _fieldDecoration(ref, directionPath, '方向'),
                  items: Direction.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e == Direction.forward ? '正向' : '反向'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => updateAt((a) => a.copyWith(direction: v)),
                ),
              ),
            ),
            if (drive == DriveType.servo) ...[
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '归中偏移',
                  fieldPath: midPath,
                  suffix: '°',
                  value: mid,
                  onChanged: (v) => updateAt((a) => a.copyWith(midOffset: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '逆时针限幅',
                  fieldPath: ccwPath,
                  suffix: '°',
                  value: ccw,
                  onChanged: (v) => updateAt((a) => a.copyWith(maxLimit: v)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  label: '顺时针限幅',
                  fieldPath: cwPath,
                  suffix: '°',
                  value: cw,
                  onChanged: (v) => updateAt(
                    (a) => a.copyWith(minLimit: v == null ? null : -v),
                  ),
                ),
              ),
            ],
            IconButton(
              tooltip: '删除执行器',
              onPressed: () =>
                  replaceActuators([...actuators]..removeAt(index)),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        );
      }

      return _Section(
        title: '$name 轴',
        children: [
          for (var index = 0; index < actuators.length; index += 1) ...[
            if (index > 0) const SizedBox(height: 16),
            if (actuators.length > 1) ...[
              Text(
                '执行器 ${index + 1}',
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
            ],
            actuatorRow(index),
          ],
          if (actuators.isEmpty) const Text('未配置执行器；该轴可以留空。'),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => replaceActuators([
                ...actuators,
                const AxisActuator(drive: DriveType.servo),
              ]),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加执行器'),
            ),
          ),
        ],
      );
    }

    return _PageFrame(
      title: '云台与拨弹机构',
      stepId: 'mechanism',
      subtitle: '配置固定执行机构。主控板 MP03/MP74 只能连接舵机。',
      child: Column(
        children: [
          _Section(
            title: '拨弹电机',
            children: [
              _FormRow(
                fieldPaths: const [
                  'mechanism.feeder_pin',
                  'mechanism.feeder_direction',
                ],
                children: [
                  Expanded(
                    child: _FieldAnchor(
                      path: 'mechanism.feeder_pin',
                      child: DropdownButtonFormField<String>(
                        key: const ValueKey('mechanism.feeder_pin'),
                        isExpanded: true,
                        initialValue: c.feederPin,
                        decoration: _fieldDecoration(
                          ref,
                          'mechanism.feeder_pin',
                          '扩展板 IO',
                        ),
                        selectedItemBuilder: (_) =>
                            _selectedPinItems(feederPinChoices),
                        items: feederPinChoices.map((e) {
                          if (e == null) {
                            return const DropdownMenuItem<String>(
                              value: null,
                              child: Text('未分配'),
                            );
                          }
                          final enabled = InfantryPinPlanner.allowedPins(
                            c,
                            'mechanism.feeder_pin',
                          ).contains(e);
                          final owner = InfantryPinPlanner.occupiedBy(
                            c,
                            e,
                            'mechanism.feeder_pin',
                          );
                          return DropdownMenuItem(
                            value: e,
                            enabled: enabled,
                            child: _PinOption(
                              e,
                              enabled: enabled,
                              owner: owner == null
                                  ? null
                                  : '${owner.ownerLabel}占用',
                            ),
                          );
                        }).toList(),
                        onChanged: (v) async {
                          final result = await _resolveInfantryPinSelection(
                            context,
                            c,
                            'mechanism.feeder_pin',
                            v,
                          );
                          if (result != null) update(result);
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FieldAnchor(
                      path: 'mechanism.feeder_direction',
                      child: DropdownButtonFormField(
                        initialValue: c.feederDirection,
                        decoration: _fieldDecoration(
                          ref,
                          'mechanism.feeder_direction',
                          '方向',
                        ),
                        items: Direction.values
                            .map(
                              (e) => DropdownMenuItem(
                                value: e,
                                child: Text(
                                  e == Direction.forward ? '正向' : '反向',
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (v) =>
                            update(c.copyWith(feederDirection: v)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          axis('Yaw', true),
          const SizedBox(height: 18),
          axis('Pitch', false),
        ],
      ),
    );
  }
}

class _InfantryControlsPage extends ConsumerWidget {
  const _InfantryControlsPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c =
        ref.watch(appControllerProvider).document!.config as InfantryConfig;
    void update(InfantryConfig v) =>
        ref.read(appControllerProvider.notifier).updateConfig(v);
    Widget keyField(
      String label,
      String fieldPath,
      String? value,
      ValueChanged<String?> changed, {
      bool allowNone = false,
    }) {
      final decoration = _fieldDecoration(ref, fieldPath, label);
      return _FieldAnchor(
        path: fieldPath,
        child: allowNone
            ? DropdownButtonFormField<String?>(
                key: ValueKey(fieldPath),
                initialValue: value,
                decoration: decoration,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('不使用'),
                  ),
                  ...digitalRemoteKeys.map(
                    (e) => DropdownMenuItem<String?>(value: e, child: Text(e)),
                  ),
                ],
                onChanged: changed,
              )
            : DropdownButtonFormField<String>(
                key: ValueKey(fieldPath),
                initialValue: value,
                decoration: decoration,
                items: digitalRemoteKeys
                    .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                    .toList(),
                onChanged: changed,
              ),
      );
    }

    return _PageFrame(
      title: '控制与摩擦轮',
      stepId: 'controls',
      subtitle: '为不同动作分配独立按键，并设置安全范围内的速度。',
      child: Column(
        children: [
          _Section(
            title: '拨弹控制',
            children: [
              _FormRow(
                fieldPaths: const [
                  'controls.arrow_behavior',
                  'controls.feed_mode',
                ],
                children: [
                  Expanded(
                    child: _FieldAnchor(
                      path: 'controls.arrow_behavior',
                      child: DropdownButtonFormField<ArrowBehavior>(
                        initialValue: c.arrowBehavior,
                        decoration: _fieldDecoration(
                          ref,
                          'controls.arrow_behavior',
                          '方向键用途',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: ArrowBehavior.move,
                            child: Text('移动'),
                          ),
                          DropdownMenuItem(
                            value: ArrowBehavior.sprint,
                            child: Text('冲刺'),
                          ),
                          DropdownMenuItem(
                            value: ArrowBehavior.other,
                            child: Text('其他'),
                          ),
                        ],
                        onChanged: (v) => update(c.copyWith(arrowBehavior: v)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _FieldAnchor(
                      path: 'controls.feed_mode',
                      child: DropdownButtonFormField<FeedMode>(
                        initialValue: c.feedMode,
                        decoration: _fieldDecoration(
                          ref,
                          'controls.feed_mode',
                          '拨弹模式',
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: FeedMode.blockingOpenLoop,
                            child: Text('阻塞开环单发'),
                          ),
                          DropdownMenuItem(
                            value: FeedMode.visualClosedLoop,
                            child: Text('目视闭环连续拨弹'),
                          ),
                        ],
                        onChanged: (v) => update(c.copyWith(feedMode: v)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _FormRow(
                fieldPaths: [
                  'controls.trigger_key',
                  'controls.reverse_feed_key',
                  'controls.trigger_speed',
                  if (c.feedMode == FeedMode.blockingOpenLoop)
                    'controls.trigger_time_ms',
                ],
                children: [
                  Expanded(
                    child: keyField(
                      '扳机键',
                      'controls.trigger_key',
                      c.triggerKey,
                      (v) => update(c.copyWith(triggerKey: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: keyField(
                      '反向拨弹键',
                      'controls.reverse_feed_key',
                      c.reverseFeedKey,
                      (v) => update(c.copyWith(reverseFeedKey: v)),
                      allowNone: true,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: '拨弹速度',
                      fieldPath: 'controls.trigger_speed',
                      suffix: 'duty',
                      value: c.triggerSpeed,
                      onChanged: (v) => update(c.copyWith(triggerSpeed: v)),
                    ),
                  ),
                  if (c.feedMode == FeedMode.blockingOpenLoop) ...[
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        label: '单发时长',
                        fieldPath: 'controls.trigger_time_ms',
                        suffix: 'ms',
                        value: c.triggerTimeMs,
                        onChanged: (v) => update(c.copyWith(triggerTimeMs: v)),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              const _InfoBanner(
                '拨弹速度范围 0–10000；阻塞开环模式需要单发时长，闭环模式按住扳机持续拨弹。'
                '反向拨弹键留空表示不使用；按住时按相反于"拨弹电机方向"的方向持续转动，松开立即停转。',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '摩擦轮',
            children: [
              _FieldAnchor(
                path: 'controls.friction_mode',
                child: DropdownButtonFormField<FrictionMode>(
                  key: const ValueKey('controls.friction_mode'),
                  initialValue: c.frictionMode,
                  decoration: _fieldDecoration(
                    ref,
                    'controls.friction_mode',
                    '摩擦轮类型',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: FrictionMode.brushlessEsc,
                      child: Text('无刷电调'),
                    ),
                    DropdownMenuItem(
                      value: FrictionMode.disabled,
                      child: Text('不使用'),
                    ),
                  ],
                  onChanged: (v) async {
                    final result = await _resolveFrictionModeSelection(
                      context,
                      c,
                      v,
                    );
                    if (result != null) update(result);
                  },
                ),
              ),
              if (c.frictionMode == FrictionMode.brushlessEsc) ...[
                const SizedBox(height: 14),
                _FormRow(
                  fieldPaths: const [
                    'controls.friction_key',
                    'controls.friction_up_key',
                    'controls.friction_down_key',
                  ],
                  children: [
                    Expanded(
                      child: keyField(
                        '开关键',
                        'controls.friction_key',
                        c.frictionKey,
                        (v) => update(c.copyWith(frictionKey: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: keyField(
                        '增加速度',
                        'controls.friction_up_key',
                        c.frictionUpKey,
                        (v) => update(c.copyWith(frictionUpKey: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: keyField(
                        '减少速度',
                        'controls.friction_down_key',
                        c.frictionDownKey,
                        (v) => update(c.copyWith(frictionDownKey: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _FormRow(
                  fieldPaths: const [
                    'controls.friction_p64_max_duty',
                    'controls.friction_p66_max_duty',
                    'controls.friction_level_step',
                  ],
                  children: [
                    for (final pin in const ['P64', 'P66']) ...[
                      if (pin != 'P64') const SizedBox(width: 12),
                      Expanded(
                        child: _NumberField(
                          label: '$pin 最大占空比',
                          fieldPath:
                              'controls.friction_${pin.toLowerCase()}_max_duty',
                          suffix: 'duty',
                          value: pin == 'P64'
                              ? c.frictionP64MaxDuty
                              : c.frictionP66MaxDuty,
                          onChanged: (v) => update(
                            pin == 'P64'
                                ? c.copyWith(frictionP64MaxDuty: v)
                                : c.copyWith(frictionP66MaxDuty: v),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        label: '每次油门步长',
                        fieldPath: 'controls.friction_level_step',
                        suffix: '%',
                        value: c.frictionLevelStep,
                        onChanged: (v) =>
                            update(c.copyWith(frictionLevelStep: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                _InfoBanner(
                  '无刷电调固定占用 P64/P66，两个引脚各自一个满油上限（须为 '
                  '${Friction.minMaxDuty}–${Friction.maxMaxDuty} 的整百值）。'
                  '油门 0~${Friction.levelMax}% 按 '
                  'duty = ${Friction.startDuty} + 油门 ÷ ${Friction.levelMax} × (该侧上限 − ${Friction.startDuty}) '
                  '换算成两侧各自的占空比，'
                  '${Friction.startDuty} duty 是电调启动信号固定不变，输出逐周期 ±1 平滑变化；'
                  '按下开关键是先保持 ${Friction.startDuty} duty 1 秒完成电调激活，再爬目标。',
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('按下右摇杆让云台归中'),
                value: c.zeroEnabled,
                onChanged: (v) => update(c.copyWith(zeroEnabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '高级设置',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('禁用蜂鸣器反馈'),
                subtitle: const Text('关闭启动诊断和运行状态的声音提示'),
                value: c.buzzerDisabled,
                onChanged: (v) => update(c.copyWith(buzzerDisabled: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

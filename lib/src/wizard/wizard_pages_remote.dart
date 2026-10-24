part of '../wizard_screen.dart';

class _RemotePage extends ConsumerWidget {
  const _RemotePage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider).document!.config as RobotConfig,
        ctrl = ref.read(appControllerProvider.notifier);
    void updateRemote(RemoteConfig remote) => ctrl.updateConfig(switch (c) {
      InfantryConfig v => v.copyWith(remote: remote),
      EngineerConfig v => v.copyWith(remote: remote),
    });
    void updateChassis(ChassisConfig chassis) => ctrl.updateConfig(switch (c) {
      InfantryConfig v => v.copyWith(chassis: chassis),
      EngineerConfig v => v.copyWith(chassis: chassis),
    });
    Widget wheel(
      String label,
      WheelConfig wheel,
      ValueChanged<WheelConfig> update,
      String fieldPath,
    ) {
      final directionPath = fieldPath.replaceFirst('.pin', '.direction');
      final pinChoices = _includeCurrent(chassisPins, wheel.pin);
      final visiblePinChoices = <String?>[
        if (c is InfantryConfig) null,
        ...pinChoices,
      ];
      return _FormRow(
        fieldPaths: [fieldPath, directionPath],
        children: [
          Expanded(
            child: _FieldAnchor(
              path: fieldPath,
              child: DropdownButtonFormField<String>(
                key: ValueKey(fieldPath),
                isExpanded: true,
                initialValue: wheel.pin,
                decoration: _fieldDecoration(ref, fieldPath, '$label IO'),
                selectedItemBuilder: (_) =>
                    _selectedPinItems(visiblePinChoices),
                items: visiblePinChoices.map((e) {
                  if (e == null) {
                    return const DropdownMenuItem<String>(
                      value: null,
                      child: Text('未分配'),
                    );
                  }
                  final enabled =
                      c is! InfantryConfig ||
                      InfantryPinPlanner.allowedPins(c, fieldPath).contains(e);
                  final owner = c is InfantryConfig
                      ? InfantryPinPlanner.occupiedBy(c, e, fieldPath)
                      : null;
                  return DropdownMenuItem(
                    value: e,
                    enabled: enabled,
                    child: _PinOption(
                      e,
                      enabled: enabled,
                      owner: owner == null ? null : '${owner.ownerLabel}占用',
                    ),
                  );
                }).toList(),
                onChanged: (v) async {
                  if (c is! InfantryConfig) {
                    update(wheel.copyWith(pin: v));
                    return;
                  }
                  final result = await _resolveInfantryPinSelection(
                    context,
                    c,
                    fieldPath,
                    v,
                  );
                  if (result != null) ctrl.updateConfig(result);
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _FieldAnchor(
              path: directionPath,
              child: DropdownButtonFormField(
                initialValue: wheel.direction,
                decoration: _fieldDecoration(ref, directionPath, '方向'),
                items: Direction.values
                    .map(
                      (e) => DropdownMenuItem(
                        value: e,
                        child: Text(e == Direction.forward ? '正向' : '反向'),
                      ),
                    )
                    .toList(),
                onChanged: (v) => update(wheel.copyWith(direction: v)),
              ),
            ),
          ),
        ],
      );
    }

    final ch = c.chassis;
    final engineer = c is EngineerConfig ? c : null;
    final chassisEnabled = engineer?.chassis.enabled ?? true;
    return _PageFrame(
      title: '遥控器与底盘',
      stepId: 'remote',
      subtitle: chassisEnabled
          ? '先确认通信参数和四轮接线，后续页面会据此检查 IO 冲突。'
          : '未启用预制四轮底盘：原底盘引脚已释放给动作行使用。',
      child: Column(
        children: [
          _Section(
            title: '遥控器',
            children: [
              _FormRow(
                fieldPaths: const ['remote.channel', 'remote.deadzone'],
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '通道号',
                      fieldPath: 'remote.channel',
                      value: c.remote.channel,
                      onChanged: (v) =>
                          updateRemote(c.remote.copyWith(channel: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _NumberField(
                      label: '摇杆死区',
                      fieldPath: 'remote.deadzone',
                      value: c.remote.deadzone,
                      onChanged: (v) =>
                          updateRemote(c.remote.copyWith(deadzone: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const _InfoBanner(
                '通道号范围 0–125，必须与遥控器一致；摇杆死区范围 0–2047，建议不超过 500。',
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '四轮底盘',
            subtitle: chassisEnabled
                ? 'IO 名称同时标明扩展板 PWM 与方向引脚；同侧前后轮可以共用一个 IO。'
                : '关闭后四个底盘电机引脚不再被占用，可在动作映射中作为普通输出使用。',
            children: [
              if (engineer != null) ...[
                SwitchListTile(
                  key: const ValueKey('chassis.enabled'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('启用底盘控制'),
                  subtitle: const Text('关闭后使用动作行/表达式自行控制底盘输出'),
                  value: chassisEnabled,
                  onChanged: (v) {
                    final modes = v
                        ? engineer.modes
                        : [
                            for (final mode in engineer.modes)
                              mode.copyWith(preserveChassis: false),
                          ];
                    ctrl.updateConfig(
                      engineer.copyWith(
                        chassis: ch.copyWith(enabled: v),
                        modes: modes,
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
              ],
              if (chassisEnabled) ...[
                wheel(
                  '左前轮',
                  ch.leftFront,
                  (v) => updateChassis(ch.copyWith(leftFront: v)),
                  'chassis.left_front.pin',
                ),
                const SizedBox(height: 12),
                wheel(
                  '左后轮',
                  ch.leftRear,
                  (v) => updateChassis(ch.copyWith(leftRear: v)),
                  'chassis.left_rear.pin',
                ),
                const SizedBox(height: 12),
                wheel(
                  '右前轮',
                  ch.rightFront,
                  (v) => updateChassis(ch.copyWith(rightFront: v)),
                  'chassis.right_front.pin',
                ),
                const SizedBox(height: 12),
                wheel(
                  '右后轮',
                  ch.rightRear,
                  (v) => updateChassis(ch.copyWith(rightRear: v)),
                  'chassis.right_rear.pin',
                ),
                const SizedBox(height: 18),
                _FormRow(
                  fieldPaths: const [
                    'chassis.normal_speed',
                    'chassis.sprint_speed',
                  ],
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: '普通速度',
                        fieldPath: 'chassis.normal_speed',
                        suffix: 'duty',
                        value: ch.normalSpeed,
                        onChanged: (v) =>
                            updateChassis(ch.copyWith(normalSpeed: v)),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _NumberField(
                        label: '冲刺速度',
                        fieldPath: 'chassis.sprint_speed',
                        suffix: 'duty',
                        value: ch.sprintSpeed,
                        onChanged: (v) =>
                            updateChassis(ch.copyWith(sprintSpeed: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _InfoBanner(
                  '速度单位为 duty，范围 0–10000；建议普通速度不低于 4000、冲刺速度不低于 9000。未启用冲刺时冲刺速度不会参与控制。',
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('按下左摇杆启用冲刺'),
                  value: ch.sprintEnabled,
                  onChanged: (v) =>
                      updateChassis(ch.copyWith(sprintEnabled: v)),
                ),
                SwitchListTile(
                  key: const ValueKey('chassis.turn_reversed'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('反转左右转向'),
                  subtitle: const Text('前后移动正常，但左右操控相反时启用'),
                  value: ch.turnReversed,
                  onChanged: (v) => updateChassis(ch.copyWith(turnReversed: v)),
                ),
              ] else
                const _InfoBanner(
                  '当前不使用预制底盘。后续请在「PWM 与引脚」与「动作映射」中直接用动作行/表达式控制输出。',
                ),
            ],
          ),
        ],
      ),
    );
  }
}

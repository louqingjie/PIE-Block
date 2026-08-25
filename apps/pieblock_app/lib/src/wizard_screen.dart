import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';

import 'controller.dart';

class WizardScreen extends ConsumerWidget {
  const WizardScreen({super.key});

  static const infantrySteps = [
    '遥控器与底盘',
    'PWM 与引脚',
    '云台与拨弹',
    '控制与摩擦轮',
    '检查与摘要',
    '生成代码',
  ];
  static const engineerSteps = [
    '遥控器与底盘',
    'PWM 与引脚',
    '模式切换',
    '动作映射',
    '检查与摘要',
    '生成代码',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider),
        controller = ref.read(appControllerProvider.notifier);
    final document = state.document!,
        steps = document.kind == ProjectKind.infantry
            ? infantrySteps
            : engineerSteps;
    final page = switch (state.step) {
      0 => const _RemotePage(),
      1 => const _PwmPage(),
      2 =>
        document.kind == ProjectKind.infantry
            ? const _InfantryMechanismPage()
            : const _EngineerStrategyPage(),
      3 =>
        document.kind == ProjectKind.infantry
            ? const _InfantryControlsPage()
            : const _EngineerMappingsPage(),
      4 => const _ReviewPage(),
      _ => const _CodePage(),
    };
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            IconButton(
              onPressed: controller.closeProject,
              tooltip: '返回项目首页',
              icon: const Icon(Icons.arrow_back),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  document.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  document.kind == ProjectKind.infantry ? '步兵项目' : '工程项目',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const Spacer(),
            _SaveBadge(state.saveStatus),
            const SizedBox(width: 8),
            IconButton(
              onPressed: controller.cycleTheme,
              tooltip: '切换主题',
              icon: const Icon(Icons.contrast),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (state.message != null)
            MaterialBanner(
              content: Text(state.message!),
              leading: const Icon(Icons.info_outline),
              actions: [
                TextButton(
                  onPressed: controller.clearMessage,
                  child: const Text('知道了'),
                ),
              ],
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1100;
                final content = AnimatedSwitcher(
                  duration: const Duration(milliseconds: 180),
                  child: KeyedSubtree(key: ValueKey(state.step), child: page),
                );
                if (!wide) {
                  return Column(
                    children: [
                      _CompactSteps(steps: steps, selected: state.step),
                      Expanded(child: content),
                    ],
                  );
                }
                return Row(
                  children: [
                    Container(
                      width: 260,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        border: Border(
                          right: BorderSide(
                            color: Theme.of(context).colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                      child: ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          for (var i = 0; i < steps.length; i++)
                            _StepTile(
                              index: i,
                              title: steps[i],
                              selected: i == state.step,
                              enabled: i <= state.maxVisitedStep + 1,
                              onTap: () => controller.goToStep(i),
                            ),
                        ],
                      ),
                    ),
                    Expanded(child: content),
                  ],
                );
              },
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              border: Border(
                top: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
            child: Row(
              children: [
                OutlinedButton.icon(
                  onPressed: state.step > 0
                      ? () => controller.goToStep(state.step - 1)
                      : null,
                  icon: const Icon(Icons.arrow_back),
                  label: const Text('上一步'),
                ),
                const Spacer(),
                Text(
                  '${state.step + 1} / 6',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: state.step < 5
                      ? () => controller.goToStep(state.step + 1)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(state.step == 4 ? '生成代码' : '下一步'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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

class _CompactSteps extends ConsumerWidget {
  const _CompactSteps({required this.steps, required this.selected});
  final List<String> steps;
  final int selected;
  @override
  Widget build(BuildContext context, WidgetRef ref) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.all(10),
    child: Row(
      children: [
        for (var i = 0; i < steps.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: ChoiceChip(
              label: Text('${i + 1}. ${steps[i]}'),
              selected: i == selected,
              onSelected:
                  i <= ref.read(appControllerProvider).maxVisitedStep + 1
                  ? (_) => ref.read(appControllerProvider.notifier).goToStep(i)
                  : null,
            ),
          ),
      ],
    ),
  );
}

class _PageFrame extends StatelessWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title, subtitle;
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(32, 26, 32, 40),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(subtitle, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: 24),
            child,
          ],
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.subtitle});
  final String title;
  final String? subtitle;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleLarge
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          if (subtitle != null) ...[const SizedBox(height: 5), Text(subtitle!)],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.helper,
  });
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? suffix, helper;
  @override
  Widget build(BuildContext context) => TextFormField(
    key: ValueKey('$label:$value'),
    initialValue: value?.toString() ?? '',
    keyboardType: TextInputType.number,
    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
    decoration: InputDecoration(
      labelText: label,
      suffixText: suffix,
      helperText: helper,
    ),
    onChanged: (text) => onChanged(int.tryParse(text)),
  );
}

class _RemotePage extends ConsumerWidget {
  const _RemotePage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider).document!.config,
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
    ) => Row(
      children: [
        Expanded(
          child: DropdownButtonFormField(
            initialValue: wheel.pin,
            decoration: InputDecoration(labelText: '$label IO'),
            items: chassisPins
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: (v) => update(wheel.copyWith(pin: v)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField(
            initialValue: wheel.direction,
            decoration: const InputDecoration(labelText: '方向'),
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
      ],
    );
    final ch = c.chassis;
    return _PageFrame(
      title: '遥控器与底盘',
      subtitle: '先确认通信参数和四轮接线，后续页面会据此检查 IO 冲突。',
      child: Column(
        children: [
          _Section(
            title: '遥控器',
            children: [
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '通道号',
                      value: c.remote.channel,
                      helper: '0–125，与遥控器保持一致',
                      onChanged: (v) =>
                          updateRemote(c.remote.copyWith(channel: v)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _NumberField(
                      label: '摇杆死区',
                      value: c.remote.deadzone,
                      helper: '0–2047',
                      onChanged: (v) =>
                          updateRemote(c.remote.copyWith(deadzone: v)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '四轮底盘',
            subtitle: 'IO 名称同时标明扩展板 PWM 与方向引脚。',
            children: [
              wheel(
                '左前轮',
                ch.leftFront,
                (v) => updateChassis(ch.copyWith(leftFront: v)),
              ),
              const SizedBox(height: 12),
              wheel(
                '左后轮',
                ch.leftRear,
                (v) => updateChassis(ch.copyWith(leftRear: v)),
              ),
              const SizedBox(height: 12),
              wheel(
                '右前轮',
                ch.rightFront,
                (v) => updateChassis(ch.copyWith(rightFront: v)),
              ),
              const SizedBox(height: 12),
              wheel(
                '右后轮',
                ch.rightRear,
                (v) => updateChassis(ch.copyWith(rightRear: v)),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '普通速度',
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
                      suffix: 'duty',
                      value: ch.sprintSpeed,
                      onChanged: (v) =>
                          updateChassis(ch.copyWith(sprintSpeed: v)),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('按下左摇杆启用冲刺'),
                value: ch.sprintEnabled,
                onChanged: (v) => updateChassis(ch.copyWith(sprintEnabled: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PwmPage extends ConsumerWidget {
  const _PwmPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = ref.watch(appControllerProvider).document!.config,
        pwm = c.pwm,
        ctrl = ref.read(appControllerProvider.notifier);
    void update(PwmGroupConfig value) => ctrl.updateConfig(switch (c) {
      InfantryConfig v => v.copyWith(pwm: value),
      EngineerConfig v => v.copyWith(pwm: value),
    });
    return _PageFrame(
      title: 'PWM 与引脚角色',
      subtitle: '同一 PWM 组共享频率。角色与频率不匹配时会在检查页给出提示。',
      child: Column(
        children: [
          _Section(
            title: '分组频率',
            children: [
              Row(
                children: [
                  for (final item in [
                    ('PWMA · P60/P62/P64/P66', pwm.pwma, true),
                    ('PWMB · P74/P75/P76/P77', pwm.pwmb, false),
                  ])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: DropdownButtonFormField(
                          initialValue: item.$2,
                          decoration: InputDecoration(labelText: item.$1),
                          items: PwmFrequency.values
                              .map(
                                (f) => DropdownMenuItem(
                                  value: f,
                                  child: Text(
                                    f == PwmFrequency.hz50
                                        ? '50 Hz · 舵机/摩擦轮'
                                        : '10000 Hz · 电机',
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) => update(
                            item.$3
                                ? pwm.copyWith(pwma: v)
                                : pwm.copyWith(pwmb: v),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('禁用蜂鸣器反馈'),
                value: pwm.buzzerDisabled,
                onChanged: (v) => update(pwm.copyWith(buzzerDisabled: v)),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '引脚输出角色',
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final pin in [...expansionPins, ...mainServoPins])
                    SizedBox(
                      width: 280,
                      child: Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<PinRole>(
                              initialValue: pwm.pinRoles[pin] ?? PinRole.motor,
                              decoration: InputDecoration(labelText: pin),
                              items: PinRole.values
                                  .map(
                                    (r) => DropdownMenuItem(
                                      value: r,
                                      child: Text(_roleLabel(r)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: mainServoPins.contains(pin)
                                  ? null
                                  : (v) {
                                      final roles = {...pwm.pinRoles, pin: v!};
                                      update(pwm.copyWith(pinRoles: roles));
                                    },
                            ),
                          ),
                          if ((pwm.pinRoles[pin] ?? PinRole.motor) ==
                              PinRole.servo) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: _NumberField(
                                label: '中位°',
                                value: pwm.servoMids[pin],
                                onChanged: (v) {
                                  final mids = {...pwm.servoMids, pin: v ?? 0};
                                  update(pwm.copyWith(servoMids: mids));
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _roleLabel(PinRole role) => switch (role) {
    PinRole.motor => '电机',
    PinRole.servo => '舵机',
    PinRole.friction => '摩擦轮',
    PinRole.jitterMotor => '抖动电机',
    PinRole.unused => '未使用',
  };
}

class _InfantryMechanismPage extends ConsumerWidget {
  const _InfantryMechanismPage();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c =
            ref.watch(appControllerProvider).document!.config as InfantryConfig,
        ctrl = ref.read(appControllerProvider.notifier);
    void update(InfantryConfig value) => ctrl.updateConfig(value);
    Widget axis(String name, bool yaw) {
      final drive = yaw ? c.yawDrive : c.pitchDrive,
          pin = yaw ? c.yawPin : c.pitchPin,
          direction = yaw ? c.yawDirection : c.pitchDirection,
          mid = yaw ? c.yawMidOffset : c.pitchMidOffset;
      return _Section(
        title: '$name 轴',
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField(
                  initialValue: drive,
                  decoration: const InputDecoration(labelText: '驱动类型'),
                  items: DriveType.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e == DriveType.servo ? '舵机' : '电机'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => update(
                    yaw ? c.copyWith(yawDrive: v) : c.copyWith(pitchDrive: v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField(
                  initialValue: pin,
                  decoration: const InputDecoration(labelText: 'IO'),
                  items: [...expansionPins, ...mainServoPins]
                      .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                      .toList(),
                  onChanged: (v) => update(
                    yaw ? c.copyWith(yawPin: v) : c.copyWith(pitchPin: v),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField(
                  initialValue: direction,
                  decoration: const InputDecoration(labelText: '方向'),
                  items: Direction.values
                      .map(
                        (e) => DropdownMenuItem(
                          value: e,
                          child: Text(e == Direction.forward ? '正向' : '反向'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => update(
                    yaw
                        ? c.copyWith(yawDirection: v)
                        : c.copyWith(pitchDirection: v),
                  ),
                ),
              ),
              if (drive == DriveType.servo) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _NumberField(
                    label: '归中偏移',
                    suffix: '°',
                    value: mid,
                    onChanged: (v) => update(
                      yaw
                          ? c.copyWith(yawMidOffset: v)
                          : c.copyWith(pitchMidOffset: v),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      );
    }

    return _PageFrame(
      title: '云台与拨弹机构',
      subtitle: '配置固定执行机构。主控板 MP03/MP74 只能连接舵机。',
      child: Column(
        children: [
          _Section(
            title: '拨弹电机',
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField(
                      initialValue: c.feederPin,
                      decoration: const InputDecoration(labelText: '扩展板 IO'),
                      items: expansionPins
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) => update(c.copyWith(feederPin: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField(
                      initialValue: c.feederDirection,
                      decoration: const InputDecoration(labelText: '方向'),
                      items: Direction.values
                          .map(
                            (e) => DropdownMenuItem(
                              value: e,
                              child: Text(e == Direction.forward ? '正向' : '反向'),
                            ),
                          )
                          .toList(),
                      onChanged: (v) => update(c.copyWith(feederDirection: v)),
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
      String value,
      ValueChanged<String?> changed,
    ) => DropdownButtonFormField(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: remoteKeys
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: changed,
    );
    return _PageFrame(
      title: '控制与摩擦轮',
      subtitle: '为不同动作分配独立按键，并设置安全范围内的速度。',
      child: Column(
        children: [
          _Section(
            title: '拨弹控制',
            children: [
              Row(
                children: [
                  Expanded(
                    child: keyField(
                      '扳机键',
                      c.triggerKey,
                      (v) => update(c.copyWith(triggerKey: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: '拨弹速度',
                      suffix: 'duty',
                      value: c.triggerSpeed,
                      onChanged: (v) => update(c.copyWith(triggerSpeed: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: '单发时长',
                      suffix: 'ms',
                      value: c.triggerTimeMs,
                      onChanged: (v) => update(c.copyWith(triggerTimeMs: v)),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '摩擦轮',
            children: [
              Row(
                children: [
                  Expanded(
                    child: keyField(
                      '开关键',
                      c.frictionKey,
                      (v) => update(c.copyWith(frictionKey: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: keyField(
                      '增加速度',
                      c.frictionUpKey,
                      (v) => update(c.copyWith(frictionUpKey: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: keyField(
                      '减少速度',
                      c.frictionDownKey,
                      (v) => update(c.copyWith(frictionDownKey: v)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: _NumberField(
                      label: '最大占空比',
                      suffix: 'duty',
                      helper: '安全范围 500–800',
                      value: c.frictionMaxDuty,
                      onChanged: (v) => update(c.copyWith(frictionMaxDuty: v)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _NumberField(
                      label: '每次调速步长',
                      suffix: 'duty',
                      value: c.frictionStep,
                      onChanged: (v) => update(c.copyWith(frictionStep: v)),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('按下右摇杆让云台归中'),
                value: c.zeroEnabled,
                onChanged: (v) => update(c.copyWith(zeroEnabled: v)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

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
          DropdownButtonFormField(
            initialValue: c.modeCount,
            decoration: const InputDecoration(labelText: '模式数量'),
            items: [1, 2, 3, 4]
                .map((e) => DropdownMenuItem(value: e, child: Text('$e 个模式')))
                .toList(),
            onChanged: (v) => countChanged(v!),
          ),
          const SizedBox(height: 16),
          SegmentedButton<SwitchStrategy>(
            segments: const [
              ButtonSegment(value: SwitchStrategy.cycle, label: Text('单击轮换')),
              ButtonSegment(value: SwitchStrategy.direct, label: Text('一一对应')),
            ],
            selected: {c.switchStrategy},
            onSelectionChanged: (v) =>
                update(c.copyWith(switchStrategy: v.first)),
          ),
          const SizedBox(height: 16),
          if (c.switchStrategy == SwitchStrategy.cycle)
            DropdownButtonFormField(
              initialValue: c.modeSwitchKey,
              decoration: const InputDecoration(labelText: '切换按键'),
              items: remoteKeys
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => update(c.copyWith(modeSwitchKey: v)),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < c.modeCount; i++)
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField(
                      initialValue: c.modeKeys[i],
                      decoration: InputDecoration(labelText: '模式 ${i + 1} 按键'),
                      items: remoteKeys
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                      onChanged: (v) {
                        final keys = [...c.modeKeys];
                        keys[i] = v!;
                        update(c.copyWith(modeKeys: keys));
                      },
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
    if (selected >= c.modeCount) selected = 0;
    void updateMode(EngineerModeConfig mode) {
      final modes = [...c.modes];
      modes[selected] = mode;
      ref
          .read(appControllerProvider.notifier)
          .updateConfig(c.copyWith(modes: modes));
    }

    final mode = c.modes[selected];
    return _PageFrame(
      title: '动作映射',
      subtitle: '每个动作都有稳定 ID；增删和切换模式不会让配置串行。',
      child: Column(
        children: [
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < c.modeCount; i++)
                ButtonSegment(value: i, label: Text('模式 ${i + 1}')),
            ],
            selected: {selected},
            onSelectionChanged: (v) => setState(() => selected = v.first),
          ),
          const SizedBox(height: 18),
          _Section(
            title: '模式 ${selected + 1}',
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('保留左摇杆底盘控制'),
                value: mode.preserveChassis,
                onChanged: (v) => updateMode(mode.copyWith(preserveChassis: v)),
              ),
              for (var i = 0; i < mode.actions.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _ActionRow(
                    action: mode.actions[i],
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

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.action,
    required this.onChanged,
    required this.onRemove,
  });
  final ActionMapping action;
  final ValueChanged<ActionMapping> onChanged;
  final VoidCallback onRemove;
  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField(
              initialValue: action.key,
              decoration: const InputDecoration(labelText: '按键'),
              items: remoteKeys
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => onChanged(action.copyWith(key: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField(
              initialValue: action.direction,
              decoration: const InputDecoration(labelText: '方向'),
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
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField(
              initialValue: action.mode,
              decoration: const InputDecoration(labelText: '控制方式'),
              items: ControlMode.values
                  .map(
                    (e) => DropdownMenuItem(
                      value: e,
                      child: Text(switch (e) {
                        ControlMode.direct => '直接',
                        ControlMode.incremental => '增量',
                        ControlMode.speed => '速度',
                        ControlMode.accelerate => '增速',
                      }),
                    ),
                  )
                  .toList(),
              onChanged: (v) => onChanged(action.copyWith(mode: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _NumberField(
              label: '参数',
              value: action.parameter,
              onChanged: (v) => onChanged(action.copyWith(parameter: v)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField(
              initialValue: action.pin,
              decoration: const InputDecoration(labelText: 'IO'),
              items: [
                ...expansionPins,
                ...mainServoPins,
              ].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
              onChanged: (v) => onChanged(action.copyWith(pin: v)),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            tooltip: '删除动作',
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );
}

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
    return _PageFrame(
      title: '检查与配置摘要',
      subtitle: '生成前完成跨页面检查。点击问题可返回对应步骤。',
      child: Column(
        children: [
          _Section(
            title: '检查结果',
            children: [
              Row(
                children: [
                  _CountBadge(
                    icon: Icons.error_outline,
                    label: '错误',
                    count: errors,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(width: 12),
                  _CountBadge(
                    icon: Icons.warning_amber,
                    label: '警告',
                    count: warnings,
                    color: Colors.orange,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (issues.isEmpty)
                const ListTile(
                  leading: Icon(Icons.check_circle, color: Colors.green),
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
                          : Colors.orange,
                    ),
                    title: Text(issue.message),
                    subtitle: Text(issue.fieldPath),
                    trailing: const Icon(Icons.arrow_forward),
                    onTap: () => ref
                        .read(appControllerProvider.notifier)
                        .goToStep(_issueStep(issue, config.kind)),
                  ),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '配置概览',
            children: [
              ListTile(
                leading: const Icon(Icons.sports_esports),
                title: Text(
                  '遥控器通道 ${config.remote.channel ?? '未填写'} · 死区 ${config.remote.deadzone ?? '未填写'}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.speed),
                title: Text(
                  '普通速度 ${config.chassis.normalSpeed ?? '未填写'} · 冲刺速度 ${config.chassis.sprintSpeed ?? '未填写'}',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.memory),
                title: Text(
                  'PWMA ${config.pwm.pwma == PwmFrequency.hz50 ? '50' : '10000'} Hz · PWMB ${config.pwm.pwmb == PwmFrequency.hz50 ? '50' : '10000'} Hz',
                ),
              ),
              if (config is EngineerConfig)
                ListTile(
                  leading: const Icon(Icons.layers),
                  title: Text(
                    '${config.modeCount} 个工程模式 · ${config.switchStrategy == SwitchStrategy.cycle ? '单击轮换' : '一一对应'}',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static int _issueStep(ValidationIssue i, ProjectKind k) {
    if (i.stepId == 'remote') return 0;
    if (i.stepId == 'pwm') return 1;
    if (i.stepId == 'mechanism' || i.stepId == 'strategy') return 2;
    if (i.stepId == 'controls' || i.stepId == 'mappings') return 3;
    return 4;
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
      borderRadius: BorderRadius.circular(12),
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

class _CodePage extends ConsumerStatefulWidget {
  const _CodePage();
  @override
  ConsumerState<_CodePage> createState() => _CodePageState();
}

class _CodePageState extends ConsumerState<_CodePage> {
  String query = '';
  Future<void> _export(String code) async {
    final path = TextEditingController(
      text:
          '${Platform.environment['USERPROFILE'] ?? Directory.current.path}${Platform.pathSeparator}Desktop${Platform.pathSeparator}main.c',
    );
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导出 main.c'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: path,
            decoration: const InputDecoration(labelText: '完整文件路径'),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              await File(path.text).writeAsString(code);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('导出'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(appControllerProvider.notifier),
        config = ref.watch(appControllerProvider).document!.config,
        issues = ctrl.issues;
    final blocked = issues.any((i) => i.severity == IssueSeverity.error);
    final code = blocked ? '' : CodeGenerator.generate(config),
        lines = code.split('\n');
    return _PageFrame(
      title: '生成代码',
      subtitle: blocked ? '仍有错误，返回检查页修正后才能生成。' : '代码根据项目配置实时生成，只读且不会写回项目文件。',
      child: blocked
          ? _Section(
              title: '无法生成',
              children: [
                FilledButton.icon(
                  onPressed: () => ctrl.goToStep(4),
                  icon: const Icon(Icons.rule),
                  label: const Text('返回检查'),
                ),
              ],
            )
          : Column(
              children: [
                _Section(
                  title: 'main.c',
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => query = v),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              labelText: '在代码中搜索',
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton.filledTonal(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: code));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('代码已复制')),
                            );
                          },
                          tooltip: '复制全部',
                          icon: const Icon(Icons.copy),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.icon(
                          onPressed: () => _export(code),
                          icon: const Icon(Icons.save_alt),
                          label: const Text('另存为'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Container(
                      height: 560,
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? const Color(0xff091012)
                            : const Color(0xfff0f3f5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(14),
                        itemCount: lines.length,
                        itemBuilder: (context, i) {
                          final line = lines[i],
                              match =
                                  query.isNotEmpty &&
                                  line.toLowerCase().contains(
                                    query.toLowerCase(),
                                  );
                          return Container(
                            color: match
                                ? Colors.yellow.withValues(alpha: .2)
                                : null,
                            child: SelectableText(
                              '${(i + 1).toString().padLeft(4)}  $line',
                              style: const TextStyle(
                                fontFamily: 'Consolas',
                                fontFamilyFallback: [
                                  'PieBlockSans',
                                  'Microsoft YaHei UI',
                                ],
                                fontSize: 13,
                                height: 1.45,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

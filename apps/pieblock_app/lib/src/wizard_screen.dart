import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pieblock_core/pieblock_core.dart';
import 'package:re_editor/re_editor.dart';
import 'package:re_highlight/languages/c.dart';
import 'package:re_highlight/styles/atom-one-dark.dart';
import 'package:re_highlight/styles/atom-one-light.dart';

import 'controller.dart';

final _fieldAnchors = <String, GlobalKey>{};
final _fieldFocusNodes = <String, FocusNode>{};
final _highlightedField = ValueNotifier<String?>(null);
Timer? _highlightTimer;

GlobalKey _fieldAnchor(String path) =>
    _fieldAnchors.putIfAbsent(path, GlobalKey.new);

void _scrollToField(String path) {
  final context = _fieldAnchors[path]?.currentContext;
  if (context != null) {
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 280),
      alignment: .28,
    );
    _fieldFocusNodes[path]?.requestFocus();
    _highlightedField.value = path;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(
      const Duration(milliseconds: 1400),
      () => _highlightedField.value = null,
    );
  }
}

class _FieldAnchor extends StatelessWidget {
  const _FieldAnchor({required this.path, required this.child});
  final String path;
  final Widget child;

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: _fieldFocusNodes.putIfAbsent(path, FocusNode.new),
    child: ValueListenableBuilder<String?>(
      valueListenable: _highlightedField,
      builder: (context, highlighted, child) => AnimatedContainer(
        key: _fieldAnchor(path),
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: highlighted == path
              ? Theme.of(context).colorScheme.tertiaryContainer
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: child,
      ),
      child: child,
    ),
  );
}

ValidationIssue? _fieldIssue(WidgetRef ref, String path) {
  final issues = ref
      .read(appControllerProvider.notifier)
      .visibleIssues
      .where((issue) => issue.fieldPath == path);
  if (issues.isEmpty) return null;
  return issues.firstWhere(
    (issue) => issue.severity == IssueSeverity.error,
    orElse: () => issues.first,
  );
}

String _fieldLabel(String path) {
  const exact = {
    'remote.channel': '遥控器通道号',
    'remote.deadzone': '摇杆死区',
    'chassis.normal_speed': '普通速度',
    'chassis.sprint_speed': '冲刺速度',
    'mechanism.feeder_pin': '拨弹电机 IO',
    'mechanism.feeder_direction': '拨弹电机方向',
    'controls.arrow_behavior': '方向键用途',
    'controls.feed_mode': '拨弹模式',
    'controls.trigger_key': '扳机键',
    'controls.trigger_speed': '拨弹速度',
    'controls.trigger_time_ms': '单发时长',
    'controls.friction_mode': '摩擦轮类型',
    'controls.friction_key': '摩擦轮开关键',
    'controls.friction_up_key': '摩擦轮增速键',
    'controls.friction_down_key': '摩擦轮减速键',
    'controls.friction_max_duty': '最大占空比',
    'controls.friction_step': '调速步长',
    'pwm.pwma': 'PWMA 频率',
    'pwm.pwmb': 'PWMB 频率',
    'modes.count': '模式数量',
    'modes.switch_strategy': '切换策略',
    'modes.switch_key': '切换按键',
  };
  if (exact[path] case final label?) return label;
  if (path.endsWith('.direction')) return '方向';
  if (path.endsWith('.drive')) return '驱动类型';
  if (path.endsWith('.pin')) return 'IO';
  if (path.endsWith('.mode')) return '控制方式';
  if (path.endsWith('.parameter')) return '参数';
  if (path.endsWith('.key')) return '按键';
  if (path.contains('servo_mids')) return '舵机中位';
  if (path.contains('pin_roles')) return '输出角色';
  return path;
}

List<String> _includeCurrent(List<String> choices, String? current) => [
  if (current != null && !choices.contains(current)) current,
  ...choices,
];

InputDecoration _fieldDecoration(
  WidgetRef ref,
  String path,
  String label, {
  String? suffix,
}) {
  final issue = _fieldIssue(ref, path);
  final color = issue == null
      ? null
      : issue.severity == IssueSeverity.error
      ? Theme.of(ref.context).colorScheme.error
      : Colors.orange;
  return InputDecoration(
    labelText: label,
    suffixText: suffix,
    suffixIcon: issue == null
        ? null
        : Tooltip(
            message: issue.message,
            child: Icon(
              issue.severity == IssueSeverity.error
                  ? Icons.error_outline
                  : Icons.warning_amber,
              color: color,
            ),
          ),
    enabledBorder: color == null
        ? null
        : OutlineInputBorder(borderSide: BorderSide(color: color, width: 1.5)),
    focusedBorder: color == null
        ? null
        : OutlineInputBorder(borderSide: BorderSide(color: color, width: 2)),
  );
}

class _FormRow extends ConsumerWidget {
  const _FormRow({required this.fieldPaths, required this.children});
  final List<String> fieldPaths;
  final List<Widget> children;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = [
      for (final path in fieldPaths)
        if (_fieldIssue(ref, path) case final issue?) (path, issue),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(children: children),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Wrap(
                spacing: 18,
                runSpacing: 6,
                children: [
                  for (final item in issues)
                    Text(
                      '${_fieldLabel(item.$1)}：${item.$2.message}',
                      style: TextStyle(
                        color: item.$2.severity == IssueSeverity.error
                            ? Theme.of(context).colorScheme.error
                            : Colors.orange,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.secondaryContainer
          .withValues(alpha: .55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.info_outline, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

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
      borderRadius: BorderRadius.circular(8),
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

List<Widget> _selectedPinItems(List<String> pins) => [
  for (final pin in pins)
    Align(
      alignment: Alignment.centerLeft,
      child: Text(pin, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
];

class WizardScreen extends ConsumerWidget {
  const WizardScreen({super.key});

  static const infantrySteps = ['遥控器与底盘', '云台与拨弹', '控制与摩擦轮', '检查与摘要', '生成代码'];
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
    final page = document.kind == ProjectKind.infantry
        ? switch (state.step) {
            0 => const _RemotePage(),
            1 => const _InfantryMechanismPage(),
            2 => const _InfantryControlsPage(),
            3 => const _ReviewPage(),
            _ => const _CodePage(),
          }
        : switch (state.step) {
            0 => const _RemotePage(),
            1 => const _PwmPage(),
            2 => const _EngineerStrategyPage(),
            3 => const _EngineerMappingsPage(),
            4 => const _ReviewPage(),
            _ => const _CodePage(),
          };
    if (state.pendingFieldPath != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToField(state.pendingFieldPath!);
        controller.clearPendingField();
      });
    }
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
                    SizedBox(
                      width: 260,
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant,
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
                  '${state.step + 1} / ${steps.length}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Spacer(),
                FilledButton.icon(
                  onPressed: state.step < steps.length - 1
                      ? () => controller.goToStep(state.step + 1)
                      : null,
                  icon: const Icon(Icons.arrow_forward),
                  label: Text(
                    state.step == controller.reviewStep(document.kind)
                        ? '生成代码'
                        : '下一步',
                  ),
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

class _PageFrame extends ConsumerWidget {
  const _PageFrame({
    required this.title,
    required this.subtitle,
    required this.child,
    this.stepId,
  });
  final String title, subtitle;
  final String? stepId;
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final issues = stepId == null
        ? const <ValidationIssue>[]
        : ref
              .read(appControllerProvider.notifier)
              .visibleIssues
              .where((issue) => issue.stepId == stepId)
              .toList();
    return SingleChildScrollView(
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
              if (issues.isNotEmpty) ...[
                const SizedBox(height: 16),
                _StepProblemPanel(issues: issues),
              ],
              const SizedBox(height: 24),
              child,
            ],
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
              onTap: () => _scrollToField(issue.fieldPath),
            ),
        ],
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

class _NumberField extends ConsumerWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.fieldPath,
  });
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? suffix, fieldPath;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final field = TextFormField(
      key: ValueKey(fieldPath ?? label),
      initialValue: value?.toString() ?? '',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
      decoration: fieldPath == null
          ? InputDecoration(labelText: label, suffixText: suffix)
          : _fieldDecoration(ref, fieldPath!, label, suffix: suffix),
      onChanged: (text) => onChanged(int.tryParse(text)),
    );
    return fieldPath == null
        ? field
        : _FieldAnchor(path: fieldPath!, child: field);
  }
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
      String fieldPath,
    ) {
      final directionPath = fieldPath.replaceFirst('.pin', '.direction');
      final pinChoices = _includeCurrent(chassisPins, wheel.pin);
      return _FormRow(
        fieldPaths: [fieldPath, directionPath],
        children: [
          Expanded(
            child: _FieldAnchor(
              path: fieldPath,
              child: DropdownButtonFormField(
                isExpanded: true,
                initialValue: wheel.pin,
                decoration: _fieldDecoration(ref, fieldPath, '$label IO'),
                selectedItemBuilder: (_) => _selectedPinItems(pinChoices),
                items: pinChoices.map((e) {
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
                      owner: enabled || owner == null
                          ? null
                          : '${owner.ownerLabel}占用',
                    ),
                  );
                }).toList(),
                onChanged: (v) => update(wheel.copyWith(pin: v)),
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
    return _PageFrame(
      title: '遥控器与底盘',
      stepId: 'remote',
      subtitle: '先确认通信参数和四轮接线，后续页面会据此检查 IO 冲突。',
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
              const _InfoBanner('通道号范围 0–125，必须与遥控器一致；摇杆死区范围 0–2047。'),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '四轮底盘',
            subtitle: 'IO 名称同时标明扩展板 PWM 与方向引脚；同侧前后轮可以共用一个 IO。',
            children: [
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
              const _InfoBanner('速度单位为 duty，范围 0–10000；未启用冲刺时冲刺速度不会参与控制。'),
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
    final c =
            ref.watch(appControllerProvider).document!.config as EngineerConfig,
        pwm = c.pwm,
        ctrl = ref.read(appControllerProvider.notifier);
    void update(PwmGroupConfig value) =>
        ctrl.updateConfig(c.copyWith(pwm: value));
    return _PageFrame(
      title: 'PWM 与引脚角色',
      stepId: 'pwm',
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
                        child: _FieldAnchor(
                          path: item.$3 ? 'pwm.pwma' : 'pwm.pwmb',
                          child: DropdownButtonFormField(
                            initialValue: item.$2,
                            decoration: _fieldDecoration(
                              ref,
                              item.$3 ? 'pwm.pwma' : 'pwm.pwmb',
                              item.$1,
                            ),
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
                            child: _FieldAnchor(
                              path: 'pwm.pin_roles.$pin',
                              child: DropdownButtonFormField<PinRole>(
                                initialValue: mainServoPins.contains(pin)
                                    ? PinRole.servo
                                    : pwm.pinRoles[pin],
                                decoration: _fieldDecoration(
                                  ref,
                                  'pwm.pin_roles.$pin',
                                  pin,
                                ),
                                items:
                                    (mainServoPins.contains(pin)
                                            ? const [PinRole.servo]
                                            : PinRole.values)
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
                                        final roles = {
                                          ...pwm.pinRoles,
                                          pin: v!,
                                        };
                                        update(pwm.copyWith(pinRoles: roles));
                                      },
                              ),
                            ),
                          ),
                          if (mainServoPins.contains(pin) ||
                              pwm.pinRoles[pin] == PinRole.servo) ...[
                            const SizedBox(width: 8),
                            SizedBox(
                              width: 100,
                              child: _NumberField(
                                label: '中位°',
                                fieldPath: 'pwm.servo_mids.$pin',
                                value: pwm.servoMids[pin],
                                onChanged: (v) {
                                  final mids = {...pwm.servoMids};
                                  if (v == null) {
                                    mids.remove(pin);
                                  } else {
                                    mids[pin] = v;
                                  }
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
    PinRole.motor => '平滑电机',
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
    final feederPins = _includeCurrent(
      InfantryPinPlanner.motorPins,
      c.feederPin,
    );
    Widget axis(String name, bool yaw) {
      final drive = yaw ? c.yawDrive : c.pitchDrive,
          pin = yaw ? c.yawPin : c.pitchPin,
          direction = yaw ? c.yawDirection : c.pitchDirection,
          mid = yaw ? c.yawMidOffset : c.pitchMidOffset,
          pinPath = yaw ? 'gimbal.yaw.pin' : 'gimbal.pitch.pin',
          drivePath = yaw ? 'gimbal.yaw.drive' : 'gimbal.pitch.drive',
          directionPath = yaw
              ? 'gimbal.yaw.direction'
              : 'gimbal.pitch.direction',
          midPath = yaw ? 'gimbal.yaw.mid_offset' : 'gimbal.pitch.mid_offset';
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
      return _Section(
        title: '$name 轴',
        children: [
          _FormRow(
            fieldPaths: [
              drivePath,
              pinPath,
              directionPath,
              if (drive == DriveType.servo) midPath,
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
                      update(
                        yaw
                            ? c.copyWith(yawDrive: v)
                            : c.copyWith(pitchDrive: v),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _FieldAnchor(
                  path: pinPath,
                  child: DropdownButtonFormField(
                    isExpanded: true,
                    initialValue: pin,
                    decoration: _fieldDecoration(ref, pinPath, 'IO'),
                    selectedItemBuilder: (_) => _selectedPinItems(visiblePins),
                    items: visiblePins.map((e) {
                      final enabled = allowedPins.contains(e);
                      final owner = InfantryPinPlanner.occupiedBy(
                        c,
                        e,
                        pinPath,
                      );
                      return DropdownMenuItem(
                        value: e,
                        enabled: enabled,
                        child: _PinOption(
                          e,
                          enabled: enabled,
                          owner: enabled
                              ? null
                              : owner?.ownerLabel ?? '当前驱动类型不支持',
                        ),
                      );
                    }).toList(),
                    onChanged: (v) => update(
                      yaw ? c.copyWith(yawPin: v) : c.copyWith(pitchPin: v),
                    ),
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
                    onChanged: (v) => update(
                      yaw
                          ? c.copyWith(yawDirection: v)
                          : c.copyWith(pitchDirection: v),
                    ),
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
                      child: DropdownButtonFormField(
                        isExpanded: true,
                        initialValue: c.feederPin,
                        decoration: _fieldDecoration(
                          ref,
                          'mechanism.feeder_pin',
                          '扩展板 IO',
                        ),
                        selectedItemBuilder: (_) =>
                            _selectedPinItems(feederPins),
                        items: feederPins.map((e) {
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
                              owner: enabled || owner == null
                                  ? null
                                  : '${owner.ownerLabel}占用',
                            ),
                          );
                        }).toList(),
                        onChanged: (v) => update(c.copyWith(feederPin: v)),
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
      ValueChanged<String?> changed,
    ) => _FieldAnchor(
      path: fieldPath,
      child: DropdownButtonFormField(
        initialValue: value,
        decoration: _fieldDecoration(ref, fieldPath, label),
        items: digitalRemoteKeys
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: changed,
      ),
    );
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
              const _InfoBanner('拨弹速度范围 0–10000；阻塞开环模式需要单发时长，闭环模式按住扳机持续拨弹。'),
            ],
          ),
          const SizedBox(height: 18),
          _Section(
            title: '摩擦轮',
            children: [
              _FieldAnchor(
                path: 'controls.friction_mode',
                child: DropdownButtonFormField<FrictionMode>(
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
                  onChanged: (v) => update(c.copyWith(frictionMode: v)),
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
                    'controls.friction_max_duty',
                    'controls.friction_step',
                  ],
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: '最大占空比',
                        fieldPath: 'controls.friction_max_duty',
                        suffix: 'duty',
                        value: c.frictionMaxDuty,
                        onChanged: (v) =>
                            update(c.copyWith(frictionMaxDuty: v)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        label: '每次调速步长',
                        fieldPath: 'controls.friction_step',
                        suffix: 'duty',
                        value: c.frictionStep,
                        onChanged: (v) => update(c.copyWith(frictionStep: v)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const _InfoBanner(
                  '无刷电调固定占用 P64/P66；500 duty 起步，最大占空比须为 500–800 的整百值，输出逐周期 ±1 平滑变化。',
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
          SegmentedButton<int>(
            segments: [
              for (var i = 0; i < availableModeCount; i++)
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
    final isMotorRole =
        role != null && role != PinRole.servo && role != PinRole.unused;
    final modes = role == PinRole.servo
        ? const [ControlMode.direct, ControlMode.incremental]
        : isMotorRole
        ? (isAxis
              ? const [ControlMode.speed, ControlMode.accelerate]
              : const [ControlMode.direct])
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
    final parameterLabel = switch (action.mode) {
      ControlMode.incremental => '步进角度 °',
      ControlMode.speed => '最大速度 duty',
      ControlMode.accelerate => '加速度 duty/周期',
      ControlMode.direct => role == PinRole.servo ? '目标角度 °' : '占空比 duty',
      null => '参数',
    };
    return Card(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
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
                  decoration: _fieldDecoration(
                    ref,
                    '$fieldPath.direction',
                    '方向',
                  ),
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
                  initialValue: action.mode,
                  decoration: _fieldDecoration(ref, '$fieldPath.mode', '控制方式'),
                  items: visibleModes
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
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _NumberField(
                label: parameterLabel,
                fieldPath: '$fieldPath.parameter',
                value: action.parameter,
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
                        .goToIssue(issue),
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
    final code = blocked ? '' : CodeGenerator.generate(config);
    return _PageFrame(
      title: '生成代码',
      subtitle: blocked ? '仍有错误，返回检查页修正后才能生成。' : '代码根据项目配置实时生成，只读且不会写回项目文件。',
      child: blocked
          ? _Section(
              title: '无法生成',
              children: [
                FilledButton.icon(
                  onPressed: () => ctrl.goToStep(ctrl.reviewStep(config.kind)),
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
                    _GeneratedCodePreview(
                      code: code,
                      onExport: () => _export(code),
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

class _GeneratedCodePreview extends StatefulWidget {
  const _GeneratedCodePreview({required this.code, required this.onExport});

  final String code;
  final VoidCallback onExport;

  @override
  State<_GeneratedCodePreview> createState() => _GeneratedCodePreviewState();
}

class _GeneratedCodePreviewState extends State<_GeneratedCodePreview> {
  late final CodeLineEditingController _editingController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  late final ScrollController _verticalScroller;
  late final ScrollController _horizontalScroller;
  late final CodeScrollController _scrollController;
  late final FocusNode _editorFocusNode;
  List<CodeLineSelection> _matches = const [];
  int _matchIndex = -1;

  @override
  void initState() {
    super.initState();
    _editingController = CodeLineEditingController.fromText(widget.code);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode(debugLabel: 'code-search');
    _verticalScroller = ScrollController();
    _horizontalScroller = ScrollController();
    _scrollController = CodeScrollController(
      verticalScroller: _verticalScroller,
      horizontalScroller: _horizontalScroller,
    );
    _editorFocusNode = FocusNode(debugLabel: 'generated-code-editor');
  }

  @override
  void didUpdateWidget(covariant _GeneratedCodePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) {
      _editingController.text = widget.code;
      _updateSearch(_searchController.text);
    }
  }

  void _updateSearch(String query) {
    final matches = <CodeLineSelection>[];
    if (query.isNotEmpty) {
      final pattern = RegExp(RegExp.escape(query), caseSensitive: false);
      final lines = _editingController.text.split('\n');
      for (var lineIndex = 0; lineIndex < lines.length; lineIndex += 1) {
        for (final match in pattern.allMatches(lines[lineIndex])) {
          matches.add(
            CodeLineSelection(
              baseIndex: lineIndex,
              baseOffset: match.start,
              extentIndex: lineIndex,
              extentOffset: match.end,
            ),
          );
        }
      }
    }
    setState(() {
      _matches = matches;
      _matchIndex = matches.isEmpty ? -1 : 0;
    });
    if (matches.isNotEmpty) {
      _selectMatch(0, rebuild: false, focusEditor: false);
    }
  }

  void _selectMatch(int index, {bool rebuild = true, bool focusEditor = true}) {
    if (_matches.isEmpty) return;
    final normalized =
        (index % _matches.length + _matches.length) % _matches.length;
    if (rebuild) setState(() => _matchIndex = normalized);
    _editingController.selection = _matches[normalized];
    _scrollController.makeCenterIfInvisible(_matches[normalized].start);
    if (focusEditor) _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _editingController.dispose();
    _scrollController.dispose();
    _verticalScroller.dispose();
    _horizontalScroller.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = dark ? const Color(0xff091012) : const Color(0xfff0f3f5);
    final foreground = dark ? const Color(0xffd7e1e3) : const Color(0xff263238);
    final gutter = dark ? const Color(0xff789094) : const Color(0xff60777b);
    final syntaxTheme = <String, TextStyle>{
      ...(dark ? atomOneDarkTheme : atomOneLightTheme),
      'root': TextStyle(color: foreground, backgroundColor: background),
    };

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                key: const ValueKey('code-search-field'),
                controller: _searchController,
                focusNode: _searchFocusNode,
                onChanged: _updateSearch,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  labelText: '在代码中搜索',
                ),
              ),
            ),
            const SizedBox(width: 10),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 58,
                  child: Text(
                    '${_matchIndex < 0 ? 0 : _matchIndex + 1} / ${_matches.length}',
                    key: const ValueKey('code-search-count'),
                    textAlign: TextAlign.center,
                  ),
                ),
                IconButton(
                  onPressed: _matches.isEmpty
                      ? null
                      : () => _selectMatch(_matchIndex - 1),
                  tooltip: '上一个匹配',
                  icon: const Icon(Icons.keyboard_arrow_up),
                ),
                IconButton(
                  onPressed: _matches.isEmpty
                      ? null
                      : () => _selectMatch(_matchIndex + 1),
                  tooltip: '下一个匹配',
                  icon: const Icon(Icons.keyboard_arrow_down),
                ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton.filledTonal(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: widget.code));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('代码已复制')));
              },
              tooltip: '复制全部',
              icon: const Icon(Icons.copy),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: widget.onExport,
              icon: const Icon(Icons.save_alt),
              label: const Text('另存为'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          height: 560,
          child: CodeEditor(
            key: const ValueKey('generated-code-editor'),
            controller: _editingController,
            scrollController: _scrollController,
            focusNode: _editorFocusNode,
            readOnly: true,
            showCursorWhenReadOnly: true,
            wordWrap: false,
            chunkAnalyzer: const NonCodeChunkAnalyzer(),
            shortcutOverrideActions: {
              CodeShortcutFindIntent: CallbackAction<CodeShortcutFindIntent>(
                onInvoke: (intent) {
                  _searchFocusNode.requestFocus();
                  _searchController.selection = TextSelection(
                    baseOffset: 0,
                    extentOffset: _searchController.text.length,
                  );
                  return null;
                },
              ),
            },
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            border: Border.all(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            leadingDivider: Container(
              width: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            indicatorBuilder:
                (context, editingController, chunkController, notifier) =>
                    Padding(
                      padding: const EdgeInsets.only(left: 10, right: 8),
                      child: DefaultCodeLineNumber(
                        key: const ValueKey('generated-code-line-numbers'),
                        controller: editingController,
                        notifier: notifier,
                        textStyle: TextStyle(
                          color: gutter,
                          fontFamily: 'Consolas',
                          fontSize: 13,
                          height: 1.45,
                        ),
                        focusedTextStyle: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontFamily: 'Consolas',
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
            style: CodeEditorStyle(
              fontFamily: 'Consolas',
              fontFamilyFallback: const ['PieBlockSans', 'Microsoft YaHei UI'],
              fontSize: 13,
              fontHeight: 1.45,
              textColor: foreground,
              backgroundColor: background,
              selectionColor: const Color(0xff02acc0).withValues(alpha: .34),
              highlightColor: const Color(0xffef685d).withValues(alpha: .3),
              cursorColor: Theme.of(context).colorScheme.primary,
              cursorLineColor: Theme.of(context).colorScheme.primary
                  .withValues(alpha: .07),
              codeTheme: CodeHighlightTheme(
                languages: {'c': CodeHighlightThemeMode(mode: langC)},
                theme: syntaxTheme,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

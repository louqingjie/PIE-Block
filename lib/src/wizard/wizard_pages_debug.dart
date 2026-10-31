part of '../wizard_screen.dart';

/// 调试提示音试听面板：把固件里那套提示音当场播出来，并给出对照表。
///
/// 这是「不同用户辨识难度」里最关键的一环——光看文案记不住旋律，
/// 必须能听；听熟了以后，赛场噪声里靠上行音数和升降走向就能定位到第几步。
class _DebugCueAudition extends ConsumerStatefulWidget {
  const _DebugCueAudition({required this.enabledCount, this.preview});

  /// 当前启用的测试项数，决定试听面板列出几步。
  final int enabledCount;

  /// 试听实现，默认交给 flutter_soloud 出声；测试注入假实现以避开原生库。
  final DebugCuePreviewService? preview;

  @override
  ConsumerState<_DebugCueAudition> createState() => _DebugCueAuditionState();
}

class _DebugCueAuditionState extends ConsumerState<_DebugCueAudition> {
  late final DebugCuePreviewService _preview =
      widget.preview ?? SoloudDebugCuePreview();
  String? _playing;

  @override
  void dispose() {
    _preview.dispose();
    super.dispose();
  }

  Future<void> _play(String label, List<DebugCueNote> notes) async {
    final next = _playing == label ? null : label;
    setState(() => _playing = next);
    if (next == null) {
      await _preview.stop();
      return;
    }
    await _preview.play(notes);
    if (!mounted) return;
    // 播完把按钮复位。留一点余量，避免尾部静音导致过早复位。
    final ms = DebugCues.durationMs(notes) + 120;
    await Future<void>.delayed(Duration(milliseconds: ms));
    if (mounted && _playing == label) setState(() => _playing = null);
  }

  @override
  Widget build(BuildContext context) {
    final steps = [
      for (var index = 1; index <= widget.enabledCount.clamp(1, 10); index++)
        index,
    ];
    return _Section(
      title: '提示音试听',
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final index in steps)
              _StepAuditionButton(
                index: index,
                playing: _playing == 'step$index',
                onPressed: () => _play('step$index', DebugCues.step(index)),
              ),
          ],
        ),
        if (widget.enabledCount > 10) ...[
          const SizedBox(height: 12),
          Text(
            '启用超过 10 项时，第 11 项起提示音与第 6–10 项重复，请以界面序号为准。',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

/// 单个步序的试听按钮。
///
/// 用 [OutlinedButton] 直接包四行文字会挤掉按钮自身的留白与描边，看起来不像按钮；
/// 这里改成「图标 + 两行小字」的定宽卡片式按钮，靠描边和按压涟漪表明可点击。
class _StepAuditionButton extends StatelessWidget {
  const _StepAuditionButton({
    required this.index,
    required this.playing,
    required this.onPressed,
  });

  final int index;
  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 音区（八度）负责进位：项 1~5 低音区、项 6 起高音区；
    // 而每一项的「声数」就是它在音区内的序号，也正是上行音型要播的音符数。
    final inHighZone = (index - 1) ~/ DebugCues.zoneSpan != 0;
    final count = (index - 1) % DebugCues.zoneSpan + 1;
    return SizedBox(
      width: 172,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          foregroundColor: playing ? scheme.primary : null,
          side: BorderSide(
            color: playing ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(
              playing ? Icons.stop_circle_outlined : Icons.play_circle_outline,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '第 $index 项',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  Text(
                    '${inHighZone ? '高' : '低'}音区 · 上行 $count 声',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 复核页里单个调试项的一句话摘要。摩擦轮项直接就是目标占空比。
String _debugDriveSummary(DebugTestItem item) => switch (item.driveType) {
  DebugDriveType.motor => '电机 ${item.value ?? '未填写'}',
  DebugDriveType.servo => '舵机 ${item.value ?? '未填写'}°',
  DebugDriveType.friction => '摩擦轮目标占空比 ${item.value ?? '未填写'}',
  null => '未选择驱动',
};

class _DebugTestsPage extends ConsumerWidget {
  const _DebugTestsPage({this.cuePreview});

  /// 提示音试听实现，透传给试听面板；为空时走 flutter_soloud。
  final DebugCuePreviewService? cuePreview;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config =
        ref.watch(appControllerProvider).document!.config as DebugConfig;
    final controller = ref.read(appControllerProvider.notifier);
    void replace(int index, DebugTestItem item) {
      final tests = [...config.tests]..[index] = item;
      controller.updateConfig(config.copyWith(tests: tests));
    }

    void duplicate(int index) {
      final tests = [...config.tests];
      tests.insert(index + 1, tests[index].duplicate());
      controller.updateConfig(config.copyWith(tests: tests));
    }

    final itemKeys = <Key>[];
    final pinCounts = <String, int>{};
    for (final item in config.tests) {
      if (item.id case final id?) {
        itemKeys.add(ValueKey(id));
      } else {
        final occurrence = pinCounts.update(
          item.pin,
          (value) => value + 1,
          ifAbsent: () => 0,
        );
        itemKeys.add(
          ValueKey(occurrence == 0 ? item.pin : '${item.pin}#$occurrence'),
        );
      }
    }

    return _PageFrame(
      title: '调试测试序列',
      subtitle:
          '启用需要测试的引脚并拖动排序。固件会按此顺序逐项执行，'
          '跑完最后一项自动回到第 1 项，如此循环。',
      fill: true,
      child: _FieldAnchor(
        path: 'tests',
        child: ReorderableListView.builder(
          buildDefaultDragHandles: false,
          // 问题面板要跳到屏幕外的字段，按项数放宽缓存以保持测试项全部挂载。
          scrollCacheExtent: ScrollCacheExtent.pixels(
            400.0 * config.tests.length + 1000,
          ),
          proxyDecorator: _reorderDragProxy,
          dragBoundaryProvider: _reorderDragBoundary,
          onReorderStart: (_) => _endTextInput(ref),
          header: Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: _DebugCueAudition(
              enabledCount: config.tests.where((item) => item.enabled).length,
              preview: cuePreview,
            ),
          ),
          itemCount: config.tests.length,
          onReorderItem: (oldIndex, newIndex) {
            final tests = [...config.tests];
            final item = tests.removeAt(oldIndex);
            tests.insert(newIndex, item);
            controller.updateConfig(config.copyWith(tests: tests));
          },
          itemBuilder: (context, index) {
            final item = config.tests[index];
            final base = 'tests.$index';
            final mainServo = mainServoPins.contains(item.pin);
            final driveChoices = mainServo
                ? const [DebugDriveType.servo]
                : <DebugDriveType>[
                    DebugDriveType.motor,
                    DebugDriveType.servo,
                    if (const {'P64', 'P66'}.contains(item.pin))
                      DebugDriveType.friction,
                  ];
            String driveLabel(DebugDriveType value) => switch (value) {
              DebugDriveType.motor => '电机',
              DebugDriveType.servo => '舵机',
              DebugDriveType.friction => '摩擦轮',
            };
            final valueLabel = switch (item.driveType) {
              DebugDriveType.servo => '角度',
              DebugDriveType.friction => '最大占空比',
              _ => '速度',
            };
            return Card(
              key: itemKeys[index],
              margin: const EdgeInsets.only(bottom: _reorderCardGap),
              child: Padding(
                padding: EdgeInsets.all(_isCompact(context) ? 14 : 18),
                child: Column(
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
                            '${index + 1}. ${item.pin}',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          onPressed: () => duplicate(index),
                          tooltip: '复制测试项',
                          icon: const Icon(Icons.copy),
                        ),
                        Switch(
                          value: item.enabled,
                          onChanged: (value) =>
                              replace(index, item.copyWith(enabled: value)),
                        ),
                      ],
                    ),
                    if (item.enabled) ...[
                      const SizedBox(height: 12),
                      _FormRow(
                        fieldPaths: [
                          '$base.drive_type',
                          if (item.driveType != DebugDriveType.friction)
                            '$base.direction',
                          '$base.value',
                          if (item.driveType != DebugDriveType.friction)
                            '$base.duration_ms',
                        ],
                        children: [
                          Expanded(
                            child: _FieldAnchor(
                              path: '$base.drive_type',
                              child: DropdownButtonFormField<DebugDriveType>(
                                key: ValueKey(
                                  '${item.pin}-drive-${item.driveType}',
                                ),
                                initialValue: item.driveType,
                                decoration: _fieldDecoration(
                                  ref,
                                  '$base.drive_type',
                                  '驱动类型',
                                ),
                                items: [
                                  for (final value in driveChoices)
                                    DropdownMenuItem(
                                      value: value,
                                      child: Text(driveLabel(value)),
                                    ),
                                ],
                                onChanged: (value) => replace(
                                  index,
                                  item.copyWith(
                                    driveType: value,
                                    direction: value == DebugDriveType.friction
                                        ? null
                                        : item.direction,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (item.driveType != DebugDriveType.friction) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _FieldAnchor(
                                path: '$base.direction',
                                child: DropdownButtonFormField<Direction>(
                                  initialValue: item.direction,
                                  decoration: _fieldDecoration(
                                    ref,
                                    '$base.direction',
                                    '方向',
                                  ),
                                  items: Direction.values
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(
                                            value == Direction.forward
                                                ? '正向'
                                                : '反向',
                                          ),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) => replace(
                                    index,
                                    item.copyWith(direction: value),
                                  ),
                                ),
                              ),
                            ),
                          ],
                          const SizedBox(width: 12),
                          Expanded(
                            child: _NumberField(
                              label: valueLabel,
                              suffix: item.driveType == DebugDriveType.friction
                                  ? 'duty'
                                  : null,
                              value: item.value,
                              fieldPath: '$base.value',
                              onChanged: (value) =>
                                  replace(index, item.copyWith(value: value)),
                            ),
                          ),
                          if (item.driveType != DebugDriveType.friction) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: _NumberField(
                                label: '测试时长',
                                value: item.durationMs,
                                suffix: 'ms',
                                fieldPath: '$base.duration_ms',
                                onChanged: (value) {
                                  if (value != null) {
                                    replace(
                                      index,
                                      item.copyWith(durationMs: value),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

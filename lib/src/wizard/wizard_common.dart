part of '../wizard_screen.dart';

final _fieldAnchors = <String, GlobalKey>{};
final _fieldFocusNodes = <String, FocusNode>{};
final _highlightedField = ValueNotifier<String?>(null);
Timer? _highlightTimer;

final _activeInputFieldProvider =
    NotifierProvider<_ActiveInputFieldController, String?>(
      _ActiveInputFieldController.new,
    );

/// 平台判断。Web 上一律为 false——网页版既没有本地编译器，也没有 USB-HID，
/// 这些分支在网页版里必须整块消失。
bool get _isAndroid =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
bool get _isWindows =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
bool get _isLinux => !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;

/// 支持 USB-HID 烧录的桌面平台（Android 走 OTG，Linux 需 udev 规则授权）。
bool get _supportsFlashing => _isWindows || _isAndroid || _isLinux;

class _ActiveInputFieldController extends Notifier<String?> {
  @override
  String? build() => null;

  void focus(String path) => state = path;

  void blur(String path) {
    if (state == path) state = null;
  }

  void clear() => state = null;
}

void _endTextInput(WidgetRef ref) {
  FocusManager.instance.primaryFocus?.unfocus();
  FocusManager.instance.applyFocusChangesIfNeeded();
  ref.read(_activeInputFieldProvider.notifier).clear();
}

const _compactBreakpoint = 600.0;
const _wideBreakpoint = 1100.0;

bool _isCompact(BuildContext context) =>
    MediaQuery.sizeOf(context).width < _compactBreakpoint;

List<Widget> _unflexChildren(List<Widget> children, {double spacing = 12}) {
  final result = <Widget>[];
  for (final child in children) {
    if (child is SizedBox && child.width != null && child.height == null) {
      continue;
    }
    if (result.isNotEmpty) result.add(SizedBox(height: spacing));
    result.add(child is Expanded ? child.child : child);
  }
  return result;
}

class _AdaptiveRow extends StatelessWidget {
  const _AdaptiveRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      if (constraints.maxWidth < _compactBreakpoint) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: _unflexChildren(children),
        );
      }
      return Row(children: children);
    },
  );
}

Future<void> _confirmCancelOperation(
  BuildContext context,
  WidgetRef ref,
  Future<void> Function() action,
) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('取消当前任务？'),
      content: const Text('编译或烧录尚未结束。烧录中取消可能需要重新断电上电后再试。'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('继续等待'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('取消任务并返回'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;
  ref.read(deployControllerProvider.notifier).cancelAll();
  await action();
}

GlobalKey _fieldAnchor(String path) =>
    _fieldAnchors.putIfAbsent(path, GlobalKey.new);

void _scrollToField(String path, {bool requestFocus = true}) {
  final context =
      (_fieldAnchors[path] ??
              (path.startsWith('music.') ? _fieldAnchors['music.notes'] : null))
          ?.currentContext;
  if (context != null) {
    Scrollable.ensureVisible(
      context,
      duration: m3Duration(context, Durations.medium2),
      alignment: .28,
    );
    if (requestFocus) _fieldFocusNodes[path]?.requestFocus();
    _highlightedField.value = path;
    _highlightTimer?.cancel();
    _highlightTimer = Timer(
      const Duration(milliseconds: 1400),
      () => _highlightedField.value = null,
    );
  }
}

class _FieldAnchor extends StatelessWidget {
  const _FieldAnchor({
    required this.path,
    required this.child,
    this.focusHandledByChild = false,
  });
  final String path;
  final Widget child;
  final bool focusHandledByChild;

  @override
  Widget build(BuildContext context) {
    final anchored = ValueListenableBuilder<String?>(
      valueListenable: _highlightedField,
      builder: (context, highlighted, child) => AnimatedContainer(
        key: _fieldAnchor(path),
        duration: m3Duration(context, Durations.short4),
        curve: Easing.standard,
        padding: const EdgeInsets.all(2),
        decoration: ShapeDecoration(
          color: highlighted == path
              ? Theme.of(context).colorScheme.tertiaryContainer
              : Colors.transparent,
          shape: AppShape.md,
        ),
        child: child,
      ),
      child: child,
    );
    if (focusHandledByChild) return anchored;
    return Focus(
      focusNode: _fieldFocusNodes.putIfAbsent(path, FocusNode.new),
      child: anchored,
    );
  }
}

String? _activeInputField(WidgetRef ref) {
  final path = ref.watch(_activeInputFieldProvider);
  if (path == null || !(_fieldFocusNodes[path]?.hasFocus ?? false)) return null;
  return path;
}

ValidationIssue? _fieldIssue(WidgetRef ref, String path) {
  if (_activeInputField(ref) == path) return null;
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
    'controls.reverse_feed_key': '反向拨弹键',
    'controls.trigger_speed': '拨弹速度',
    'controls.trigger_time_ms': '单发时长',
    'controls.friction_mode': '摩擦轮类型',
    'controls.friction_key': '摩擦轮开关键',
    'controls.friction_up_key': '摩擦轮增速键',
    'controls.friction_down_key': '摩擦轮减速键',
    'controls.friction_p64_max_duty': 'P64 最大占空比',
    'controls.friction_p66_max_duty': 'P66 最大占空比',
    'controls.friction_level_step': '油门步长',
    'pwm.pwma': 'PWMA 频率',
    'pwm.pwmb': 'PWMB 频率',
    'modes.count': '模式数量',
    'modes.switch_strategy': '切换策略',
    'modes.switch_key': '切换按键',
    'music.notes': '音符',
    'music.tempo_events': '速度事件',
    'music.time_signature_events': '拍号事件',
  };
  if (exact[path] case final label?) return label;
  if (path.endsWith('.direction')) return '方向';
  if (path.endsWith('.drive')) return '驱动类型';
  if (path.endsWith('.pin')) return '输出';
  if (path.endsWith('.mid_offset')) return '归中偏移';
  if (path.endsWith('.min_limit')) return '顺时针限幅';
  if (path.endsWith('.max_limit')) return '逆时针限幅';
  if (path.endsWith('.mode')) return '控制方式';
  if (path.endsWith('.parameter')) return '参数';
  if (path.endsWith('.key')) return '输入';
  if (path.endsWith('.variable')) return '变量名';
  if (path.endsWith('.expression')) return '表达式';
  if (path.contains('servo_mids')) return '舵机中位';
  if (path.contains('servo_min_limits')) return '舵机顺时针限幅';
  if (path.contains('servo_max_limits')) return '舵机逆时针限幅';
  if (path.contains('friction_max_duties')) return '摩擦轮满油占空比';
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
  final brightness = Theme.of(ref.context).brightness;
  final color = issue == null
      ? null
      : issue.severity == IssueSeverity.error
      ? Theme.of(ref.context).colorScheme.error
      : AppStatusColors.warn(brightness);
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
        _AdaptiveRow(children: children),
        if (issues.isNotEmpty) ...[
          const SizedBox(height: 8),
          DecoratedBox(
            decoration: ShapeDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              shape: AppShape.md,
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
                            : AppStatusColors.warn(
                                Theme.of(context).brightness,
                              ),
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
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: ShapeDecoration(
        color: scheme.secondaryContainer,
        shape: AppShape.md,
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: scheme.onSecondaryContainer),
            ),
          ),
        ],
      ),
    );
  }
}

/// 可排序卡片之间的纵向间隙，拖拽浮层要按它把阴影收进卡片本体。
const double _reorderCardGap = 12;

/// 拖拽浮层外扩的像素数：越过 EdgeDraggingAutoScroller 的严格边界判断，
/// 同时不超过页头与列表之间的 24px 间距。
const double _reorderDragBoundaryPeek = 20;

Widget _reorderDragProxy(Widget child, int index, Animation<double> animation) {
  return AnimatedBuilder(
    animation: animation,
    child: child,
    builder: (context, child) {
      final t = Curves.easeInOut.transform(animation.value);
      return Stack(
        key: const ValueKey('reorder-drag-proxy'),
        clipBehavior: Clip.none,
        children: [
          // 只给卡片本体投圆角阴影；底部 12px 间隙保持透明，不露出矩形底。
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            bottom: _reorderCardGap,
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppCorner.lg),
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).colorScheme.shadow
                        .withValues(alpha: .24 * t),
                    blurRadius: 18 * t,
                    offset: Offset(0, 6 * t),
                  ),
                ],
              ),
            ),
          ),
          // Card 自带 Material，这里不再叠一层矩形底色。
          child!,
        ],
      );
    },
  );
}

DragBoundaryDelegate<Rect>? _reorderDragBoundary(BuildContext listContext) {
  final box = Scrollable.maybeOf(listContext)?.context.findRenderObject();
  if (box is! RenderBox || !box.hasSize) return null;
  final rect = box.localToGlobal(Offset.zero) & box.size;
  return _ReorderDragBoundary(
    Rect.fromLTRB(
      rect.left,
      rect.top - _reorderDragBoundaryPeek,
      rect.right,
      rect.bottom + _reorderDragBoundaryPeek,
    ),
  );
}

/// 把拖拽浮层夹在列表视口附近，避免它盖住页标题或跑出窗口。
class _ReorderDragBoundary extends DragBoundaryDelegate<Rect> {
  _ReorderDragBoundary(this.bounds);

  final Rect bounds;

  @override
  bool isWithinBoundary(Rect dragged) =>
      bounds.contains(dragged.topLeft) && bounds.contains(dragged.bottomRight);

  @override
  Rect nearestPositionWithinBoundary(Rect dragged) {
    // 视口比卡片还矮时退回不夹取，避免 SDK 的默认实现直接抛 FlutterError。
    if (dragged.width > bounds.width || dragged.height > bounds.height) {
      return dragged;
    }
    return Rect.fromLTWH(
      dragged.left.clamp(bounds.left, bounds.right - dragged.width).toDouble(),
      dragged.top.clamp(bounds.top, bounds.bottom - dragged.height).toDouble(),
      dragged.width,
      dragged.height,
    );
  }
}

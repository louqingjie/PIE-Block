part of '../wizard_screen.dart';

class _Section extends StatelessWidget {
  const _Section({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
    this.trailing,
  });
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    child: AppCard(
      padding: EdgeInsets.all(_isCompact(context) ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing == null)
            Text(title, style: AppText.sectionTitle(context))
          else
            SizedBox(
              width: double.infinity,
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 16,
                runSpacing: 12,
                children: [
                  Text(title, style: AppText.sectionTitle(context)),
                  ?trailing,
                ],
              ),
            ),
          if (subtitle != null) ...[const SizedBox(height: 5), Text(subtitle!)],
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    ),
  );
}

/// 整数 / 小数通用的数值输入框。
///
/// `T` 为 [int] 时只接受整数；为 [double] 时允许最多两位小数，初始值里的
/// `.0` 会被省略。带符号字段（方向、中位偏移等）需传 `signed: true`，否则
/// 软键盘不提供负号键、小数正则也会拒绝负号。两种模式共用焦点绑定、字段
/// 定位与错误装饰。
class _NumberField<T extends num> extends ConsumerStatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.fieldPath,
    this.signed = false,
  });

  final String label;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? suffix;
  final String? fieldPath;

  /// 是否允许负号：同时决定软键盘类型与输入白名单。
  final bool signed;

  @override
  ConsumerState<_NumberField<T>> createState() => _NumberFieldState<T>();
}

class _NumberFieldState<T extends num> extends ConsumerState<_NumberField<T>> {
  FocusNode? _focusNode;

  bool get _isDecimal => T == double;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _NumberField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldPath != widget.fieldPath) {
      _unbindFocusNode(oldWidget.fieldPath);
      _bindFocusNode();
    }
  }

  void _bindFocusNode() {
    final path = widget.fieldPath;
    if (path == null) return;
    final node = FocusNode(debugLabel: path)..addListener(_handleFocusChange);
    _focusNode = node;
    _fieldFocusNodes[path] = node;
  }

  void _unbindFocusNode(String? path) {
    final node = _focusNode;
    if (node == null) return;
    if (path != null && identical(_fieldFocusNodes[path], node)) {
      _fieldFocusNodes.remove(path);
    }
    node.removeListener(_handleFocusChange);
    node.dispose();
    _focusNode = null;
  }

  void _handleFocusChange() {
    final path = widget.fieldPath;
    if (path == null) return;
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

  String get _initialText {
    final value = widget.value;
    if (value == null) return '';
    if (!_isDecimal) return value.toString();
    final decimal = value.toDouble();
    return decimal == decimal.truncateToDouble()
        ? decimal.toInt().toString()
        : decimal.toString();
  }

  T? _parse(String text) {
    if (T == int) return int.tryParse(text) as T?;
    if (T == double) return double.tryParse(text) as T?;
    return num.tryParse(text) as T?;
  }

  @override
  Widget build(BuildContext context) {
    // 整串匹配：不合法的输入保留旧值，避免 allow(RegExp(r'-?\d*')) 把
    // "30-" 这类中间负号拼回去，界面显示与解析出的参数不一致。
    final pattern = switch ((_isDecimal, widget.signed)) {
      (true, true) => RegExp(r'^-?\d*(?:\.\d{0,2})?$'),
      (true, false) => RegExp(r'^\d*(?:\.\d{0,2})?$'),
      (false, true) => RegExp(r'^-?\d*$'),
      (false, false) => RegExp(r'^\d*$'),
    };
    final field = TextFormField(
      key: ValueKey(widget.fieldPath ?? widget.label),
      focusNode: _focusNode,
      initialValue: _initialText,
      keyboardType: TextInputType.numberWithOptions(
        decimal: _isDecimal,
        signed: widget.signed,
      ),
      inputFormatters: [
        TextInputFormatter.withFunction(
          (oldValue, newValue) =>
              pattern.hasMatch(newValue.text) ? newValue : oldValue,
        ),
      ],
      decoration: widget.fieldPath == null
          ? InputDecoration(labelText: widget.label, suffixText: widget.suffix)
          : _fieldDecoration(
              ref,
              widget.fieldPath!,
              widget.label,
              suffix: widget.suffix,
            ),
      onChanged: (text) => widget.onChanged(_parse(text)),
    );
    return widget.fieldPath == null
        ? field
        : _FieldAnchor(
            path: widget.fieldPath!,
            focusHandledByChild: true,
            child: field,
          );
  }
}

/// 单行文本输入框（表达式、变量名等），沿用数值框的焦点绑定与错误装饰。
class _TextField extends ConsumerStatefulWidget {
  const _TextField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.fieldPath,
    this.hint,
    this.monospace = false,
  });

  final String label;
  final String? value;
  final ValueChanged<String> onChanged;
  final String? fieldPath;
  final String? hint;
  final bool monospace;

  @override
  ConsumerState<_TextField> createState() => _TextFieldState();
}

class _TextFieldState extends ConsumerState<_TextField> {
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _TextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldPath != widget.fieldPath) {
      _unbindFocusNode(oldWidget.fieldPath);
      _bindFocusNode();
    }
  }

  void _bindFocusNode() {
    final path = widget.fieldPath;
    if (path == null) return;
    final node = FocusNode(debugLabel: path)..addListener(_handleFocusChange);
    _focusNode = node;
    _fieldFocusNodes[path] = node;
  }

  void _unbindFocusNode(String? path) {
    final node = _focusNode;
    if (node == null) return;
    if (path != null && identical(_fieldFocusNodes[path], node)) {
      _fieldFocusNodes.remove(path);
    }
    node.removeListener(_handleFocusChange);
    node.dispose();
    _focusNode = null;
  }

  void _handleFocusChange() {
    final path = widget.fieldPath;
    if (path == null) return;
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
    final field = TextFormField(
      key: ValueKey(widget.fieldPath ?? widget.label),
      focusNode: _focusNode,
      initialValue: widget.value ?? '',
      style: widget.monospace
          ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
          : null,
      decoration: widget.fieldPath == null
          ? InputDecoration(labelText: widget.label, hintText: widget.hint)
          : _fieldDecoration(
              ref,
              widget.fieldPath!,
              widget.label,
            ).copyWith(hintText: widget.hint),
      onChanged: widget.onChanged,
    );
    return widget.fieldPath == null
        ? field
        : _FieldAnchor(
            path: widget.fieldPath!,
            focusHandledByChild: true,
            child: field,
          );
  }
}

/// 百分比灵敏度：滑块按 5% 吸附提交，右侧数值框可直接键入整数。
///
/// 数值框不拦截越界值（与 [_NumberField] 一致），由校验器在字段下方提示；
/// 滑块只负责显示，超出范围时按边界定位，避免 [Slider] 断言失败。
class _SensitivitySlider extends ConsumerStatefulWidget {
  const _SensitivitySlider({
    required this.label,
    required this.fieldPath,
    required this.value,
    required this.onChanged,
  });

  static const min = 10, max = 200, step = 5;

  final String label;
  final String fieldPath;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  ConsumerState<_SensitivitySlider> createState() => _SensitivitySliderState();
}

class _SensitivitySliderState extends ConsumerState<_SensitivitySlider> {
  late final TextEditingController _controller = TextEditingController(
    text: '${widget.value}',
  );
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _SensitivitySlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldPath != widget.fieldPath) {
      _unbindFocusNode(oldWidget.fieldPath);
      _bindFocusNode();
      _syncText();
      return;
    }
    // 输入框聚焦时不回填，避免打字过程中光标被拉到末尾。
    if (oldWidget.value != widget.value && !_focused) _syncText();
  }

  bool get _focused => _focusNode?.hasFocus ?? false;

  void _bindFocusNode() {
    final node = FocusNode(debugLabel: widget.fieldPath)
      ..addListener(_handleFocusChange);
    _focusNode = node;
    _fieldFocusNodes[widget.fieldPath] = node;
  }

  void _unbindFocusNode(String path) {
    final node = _focusNode;
    if (node == null) return;
    if (identical(_fieldFocusNodes[path], node)) _fieldFocusNodes.remove(path);
    node.removeListener(_handleFocusChange);
    node.dispose();
    _focusNode = null;
  }

  void _handleFocusChange() {
    final controller = ref.read(_activeInputFieldProvider.notifier);
    if (_focused) {
      controller.focus(widget.fieldPath);
      return;
    }
    controller.blur(widget.fieldPath);
    // 清空或输入中途失去焦点时，回到配置里的真实值。
    _syncText();
  }

  void _syncText() {
    final text = '${widget.value}';
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _unbindFocusNode(widget.fieldPath);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sliderValue = widget.value
        .clamp(_SensitivitySlider.min, _SensitivitySlider.max)
        .toDouble();
    return _FieldAnchor(
      path: widget.fieldPath,
      focusHandledByChild: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.label, style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          _FormRow(
            fieldPaths: [widget.fieldPath],
            children: [
              Expanded(
                child: Slider(
                  value: sliderValue,
                  min: _SensitivitySlider.min.toDouble(),
                  max: _SensitivitySlider.max.toDouble(),
                  divisions:
                      (_SensitivitySlider.max - _SensitivitySlider.min) ~/
                      _SensitivitySlider.step,
                  label: '${widget.value}%',
                  onChanged: (value) => widget.onChanged(value.round()),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: _isCompact(context) ? 96 : 116,
                child: TextFormField(
                  key: ValueKey(widget.fieldPath),
                  controller: _controller,
                  focusNode: _focusNode,
                  textAlign: TextAlign.end,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(3),
                  ],
                  decoration: _fieldDecoration(
                    ref,
                    widget.fieldPath,
                    '百分比',
                    suffix: '%',
                  ),
                  onChanged: (text) {
                    final value = int.tryParse(text);
                    if (value != null) widget.onChanged(value);
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

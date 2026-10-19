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
    child: Card(
      child: Padding(
        padding: EdgeInsets.all(_isCompact(context) ? 16 : 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (trailing == null)
              Text(
                title,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              )
            else
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 16,
                  runSpacing: 12,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    ?trailing,
                  ],
                ),
              ),
            if (subtitle != null) ...[
              const SizedBox(height: 5),
              Text(subtitle!),
            ],
            const SizedBox(height: 20),
            ...children,
          ],
        ),
      ),
    ),
  );
}

/// 整数 / 小数通用的数值输入框。
///
/// `T` 为 [int] 时只接受整数（允许负号）；为 [double] 时允许最多两位小数，
/// 初始值里的 `.0` 会被省略。两种模式共用焦点绑定、字段定位与错误装饰。
class _NumberField<T extends num> extends ConsumerStatefulWidget {
  const _NumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.fieldPath,
  });

  final String label;
  final T? value;
  final ValueChanged<T?> onChanged;
  final String? suffix;
  final String? fieldPath;

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
    final field = TextFormField(
      key: ValueKey(widget.fieldPath ?? widget.label),
      focusNode: _focusNode,
      initialValue: _initialText,
      keyboardType: _isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.number,
      inputFormatters: _isDecimal
          ? [
              TextInputFormatter.withFunction((oldValue, newValue) {
                final valid = RegExp(r'^\d*(?:\.\d{0,2})?$')
                    .hasMatch(newValue.text);
                return valid ? newValue : oldValue;
              }),
            ]
          : [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
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

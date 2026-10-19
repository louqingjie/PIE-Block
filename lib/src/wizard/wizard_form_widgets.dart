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

class _NumberField extends ConsumerStatefulWidget {
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
  ConsumerState<_NumberField> createState() => _NumberFieldState();
}

class _NumberFieldState extends ConsumerState<_NumberField> {
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _NumberField oldWidget) {
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
      initialValue: widget.value?.toString() ?? '',
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'-?\d*'))],
      decoration: widget.fieldPath == null
          ? InputDecoration(labelText: widget.label, suffixText: widget.suffix)
          : _fieldDecoration(
              ref,
              widget.fieldPath!,
              widget.label,
              suffix: widget.suffix,
            ),
      onChanged: (text) => widget.onChanged(int.tryParse(text)),
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

class _DecimalNumberField extends ConsumerStatefulWidget {
  const _DecimalNumberField({
    required this.label,
    required this.value,
    required this.onChanged,
    required this.fieldPath,
  });

  final String label;
  final double? value;
  final ValueChanged<double?> onChanged;
  final String fieldPath;

  @override
  ConsumerState<_DecimalNumberField> createState() =>
      _DecimalNumberFieldState();
}

class _DecimalNumberFieldState extends ConsumerState<_DecimalNumberField> {
  FocusNode? _focusNode;

  @override
  void initState() {
    super.initState();
    _bindFocusNode();
  }

  @override
  void didUpdateWidget(covariant _DecimalNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fieldPath != widget.fieldPath) {
      _unbindFocusNode(oldWidget.fieldPath);
      _bindFocusNode();
    }
  }

  void _bindFocusNode() {
    final node = FocusNode(debugLabel: widget.fieldPath)
      ..addListener(_handleFocusChange);
    _focusNode = node;
    _fieldFocusNodes[widget.fieldPath] = node;
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
    final controller = ref.read(_activeInputFieldProvider.notifier);
    if (_focusNode?.hasFocus ?? false) {
      controller.focus(widget.fieldPath);
    } else {
      controller.blur(widget.fieldPath);
    }
  }

  @override
  void dispose() {
    _unbindFocusNode(widget.fieldPath);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = widget.value;
    final initialValue = value == null
        ? ''
        : value == value.truncateToDouble()
        ? value.toInt().toString()
        : value.toString();
    return _FieldAnchor(
      path: widget.fieldPath,
      focusHandledByChild: true,
      child: TextFormField(
        key: ValueKey(widget.fieldPath),
        focusNode: _focusNode,
        initialValue: initialValue,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          TextInputFormatter.withFunction((oldValue, newValue) {
            final valid = RegExp(r'^\d*(?:\.\d{0,2})?$')
                .hasMatch(newValue.text);
            return valid ? newValue : oldValue;
          }),
        ],
        decoration: _fieldDecoration(ref, widget.fieldPath, widget.label),
        onChanged: (text) => widget.onChanged(double.tryParse(text)),
      ),
    );
  }
}

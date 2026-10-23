part of '../wizard_screen.dart';

class _CodePage extends ConsumerStatefulWidget {
  const _CodePage();
  @override
  ConsumerState<_CodePage> createState() => _CodePageState();
}

class _CodePageState extends ConsumerState<_CodePage> {
  /// 当前展示哪一个视图：默认只看 C，**进入页面不编译**。
  /// 只有切到「汇编」且还没有结果时才发起一次完整构建。
  bool _showListing = false;

  Future<void> _export(String code, String fileName) async {
    await exportGeneratedText(
      context,
      suggestedName: fileName,
      text: code,
      mimeType: 'text/plain',
    );
  }

  /// 切到「汇编」时：已有**同一份源码**的列表就直接显示，否则发起构建
  /// （配置改动后 sourceCode 会变，这里会重新编译而不是显示过期列表）。
  void _selectListing(bool listing, ProjectConfig config, String code) {
    setState(() => _showListing = listing);
    if (!listing) return;
    final cached = ref.read(asmPreviewControllerProvider);
    if (cached.listing != null && cached.sourceCode == code) return;
    unawaited(ref.read(asmPreviewControllerProvider.notifier).compile(config));
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = ref.read(appControllerProvider.notifier),
        config = ref.watch(appControllerProvider).document!.config,
        issues = ctrl.issues;
    final blocked = issues.any((i) => i.severity == IssueSeverity.error);
    final asm = ref.watch(asmPreviewControllerProvider);
    final code = blocked ? '' : CodeGenerator.generate(config);
    final showListing = _showListing && !blocked;
    final listing = asm.listing;
    return _PageFrame(
      title: '生成代码',
      subtitle: blocked
          ? '仍有错误，返回检查页修正后才能生成。'
          : asm.compiling
          ? _compilingSubtitle
          : '代码根据项目配置实时生成，只读且不会写回项目文件。',
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
          : _Section(
              title: showListing ? 'main.rst' : 'main.c',
              // 窄屏（360 逻辑像素）放不下切换器 + 重新编译并排，交给 Wrap 换行。
              trailing: Wrap(
                spacing: 12,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _CodeOutputSwitch(
                    listing: showListing,
                    onChanged: (value) => _selectListing(value, config, code),
                  ),
                  if (showListing && asm.ready)
                    Tooltip(
                      message: '悬停在指令、寄存器、伪指令或数值上查看说明',
                      child: Icon(
                        Icons.info_outline,
                        size: 18,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  // 编译中保留按钮但置灰：入口位置固定，重试不会到处找。
                  if (showListing)
                    OutlinedButton.icon(
                      onPressed: asm.compiling
                          ? null
                          : () => unawaited(
                              ref
                                  .read(asmPreviewControllerProvider.notifier)
                                  .recompile(config),
                            ),
                      icon: const Icon(Icons.refresh),
                      label: const Text('重新编译'),
                    ),
                ],
              ),
              children: [
                if (!showListing)
                  _GeneratedCodePreview(
                    code: code,
                    fileName: 'main.c',
                    onExport: () => _export(code, 'main.c'),
                  )
                else
                  // 汇编栏始终是同一个编辑器：内容没好就把编辑区换成占位，
                  // 工具栏留在原位并禁用，列表到达时不会把整块内容顶下去。
                  _GeneratedCodePreview(
                    code: listing ?? '',
                    fileName: 'main.rst',
                    onExport: () => _export(listing ?? '', 'main.rst'),
                    languages: {
                      'asm': CodeHighlightThemeMode(mode: langAs251Listing),
                    },
                    controlsEnabled: asm.ready,
                    placeholder: asm.ready
                        ? null
                        : _ListingPlaceholder(
                            compiling: asm.compiling,
                            message: asm.message,
                            progress: asm.progress,
                            onRetry: () => unawaited(
                              ref
                                  .read(asmPreviewControllerProvider.notifier)
                                  .recompile(config),
                            ),
                          ),
                  ),
              ],
            ),
    );
  }
}

/// 代码区右上角的「C 代码 / 汇编」切换器。
class _CodeOutputSwitch extends StatelessWidget {
  const _CodeOutputSwitch({required this.listing, required this.onChanged});

  final bool listing;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '输出语言',
    // 分段按钮内部每段都是 Expanded，放进 Wrap 会一路撑满整行、把旁边的
    // 「重新编译」挤到下一行，这里按控件自身宽度收住。
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 300),
      child: ConnectedButtonGroup<bool>(
        semanticLabel: '输出语言',
        segments: const [
          ConnectedSegment(value: false, icon: Icons.code, label: 'C 代码'),
          ConnectedSegment(value: true, icon: Icons.memory, label: '汇编'),
        ],
        value: listing,
        onChanged: onChanged,
      ),
    ),
  );
}

/// 编译中的页面说明：交代当前状态，以及为什么此刻翻页按钮是禁用的。
/// 具体编到第几个文件由汇编栏自己报，这里不重复数字。
const _compilingSubtitle = '正在编译汇编列表，编译期间不能切换步骤。';

/// 构建阶段文案的解析结果。
///
/// 工具链按 `[7/22] 编译 libraries/…/Encoder.c` 报告逐文件进度；准备工具链、
/// 链接等阶段没有编号，此时 [value] 为 null，按不确定进度显示。
class _BuildStage {
  const _BuildStage({this.index, this.total, this.detail = ''});

  factory _BuildStage.parse(String? message) {
    final text = message?.trim() ?? '';
    if (text.isEmpty) return const _BuildStage();
    final match = RegExp(r'^\[(\d+)\s*/\s*(\d+)\]\s*(.*)$').firstMatch(text);
    if (match == null) return _BuildStage(detail: text);
    return _BuildStage(
      index: int.tryParse(match.group(1)!),
      total: int.tryParse(match.group(2)!),
      detail: match.group(3) ?? '',
    );
  }

  final int? index, total;

  /// 去掉编号后的阶段说明，例如 `编译 libraries/boards/src/Encoder.c`。
  final String detail;

  double? get value {
    final index = this.index, total = this.total;
    if (index == null || total == null || total <= 0) return null;
    return (index / total).clamp(0.0, 1.0);
  }
}

/// 代码面板的底色、前景与行号色。
///
/// 占位面板与真实编辑器共用同一套颜色、同一块高度和同一个圆角，所以编译
/// 结束时是「内容在原地淡入」，而不是先闪一块别的颜色再变成代码。
class _CodeSurface {
  const _CodeSurface({
    required this.background,
    required this.foreground,
    required this.gutter,
  });

  factory _CodeSurface.of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const _CodeSurface(
          background: Color(0xff091012),
          foreground: Color(0xffd7e1e3),
          gutter: Color(0xff789094),
        )
      : const _CodeSurface(
          background: Color(0xfff0f3f5),
          foreground: Color(0xff263238),
          gutter: Color(0xff60777b),
        );

  final Color background, foreground, gutter;
}

/// 骨架屏里的一条假代码行：缩进用像素，长度取剩余宽度的比例。
class _SkeletonLine {
  const _SkeletonLine(this.indent, this.width);
  final double indent, width;
}

const _skeletonLines = <_SkeletonLine>[
  _SkeletonLine(0, .34),
  _SkeletonLine(14, .52),
  _SkeletonLine(14, .41),
  _SkeletonLine(28, .63),
  _SkeletonLine(28, .30),
  _SkeletonLine(14, .47),
  _SkeletonLine(0, .22),
  _SkeletonLine(0, .58),
  _SkeletonLine(14, .36),
  _SkeletonLine(28, .50),
  _SkeletonLine(14, .27),
  _SkeletonLine(0, .18),
];

/// 汇编栏还没就绪时的占位。
///
/// 编译中在**内容将要出现的位置**就地等待：确定进度（由 `[7/22]` 换算）+
/// 阶段文案 + 骨架行，页面其余部分照常可读。失败或降级时在同一块里说明
/// 原因，并把「重试」放在原因旁边，不必回标题栏找按钮。
class _ListingPlaceholder extends StatefulWidget {
  const _ListingPlaceholder({
    required this.compiling,
    this.message,
    this.progress,
    this.onRetry,
  });

  final bool compiling;
  final String? message, progress;
  final VoidCallback? onRetry;

  @override
  State<_ListingPlaceholder> createState() => _ListingPlaceholderState();
}

class _ListingPlaceholderState extends State<_ListingPlaceholder>
    with SingleTickerProviderStateMixin {
  /// 骨架行的呼吸只改透明度、不做位移；系统要求减少动态效果时停在中点。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncPulse();
  }

  @override
  void didUpdateWidget(_ListingPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncPulse();
  }

  void _syncPulse() {
    if (widget.compiling && !MediaQuery.disableAnimationsOf(context)) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else {
      _pulse
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final surface = _CodeSurface.of(context);
    return Container(
      width: double.infinity,
      padding: _codeEditorPadding,
      decoration: BoxDecoration(
        color: surface.background,
        borderRadius: BorderRadius.circular(AppCorner.md),
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: widget.compiling
          ? _buildLoading(context, surface)
          : _buildFailure(context, surface),
    );
  }

  Widget _buildLoading(BuildContext context, _CodeSurface surface) {
    final theme = Theme.of(context);
    final stage = _BuildStage.parse(widget.progress);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '正在编译汇编列表',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: surface.foreground,
                ),
              ),
            ),
            if (stage.total != null) ...[
              const SizedBox(width: 12),
              Text(
                '${stage.index} / ${stage.total}',
                style: AppText.count(
                  context,
                ).copyWith(color: surface.gutter),
              ),
            ],
          ],
        ),
        const SizedBox(height: 10),
        WavyProgressIndicator(
          value: stage.value,
          height: 12,
          color: theme.colorScheme.primary,
          trackColor: surface.foreground.withValues(alpha: .2),
          semanticLabel: '编译进度',
        ),
        const SizedBox(height: 8),
        Text(
          stage.detail.isEmpty
              ? '用内置 SDCC C251 完整构建 main.c，首次使用需要先部署工具链。'
              : stage.detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: surface.gutter,
            fontFamily: 'PieBlockMono',
            fontFamilyFallback: _codeFontFallbacks,
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 14),
        Expanded(child: _buildSkeleton(surface)),
      ],
    );
  }

  Widget _buildSkeleton(_CodeSurface surface) {
    const lineHeight = _codeFontSize * _codeLineHeightFactor;
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = (constraints.maxHeight / lineHeight)
            .floor()
            .clamp(3, 24);
        return AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) {
            final breath = .45 + .55 * Curves.easeInOut.transform(_pulse.value);
            final bar = surface.foreground.withValues(alpha: .16 * breath);
            final number = surface.gutter.withValues(alpha: .55 * breath);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < count; i += 1)
                  SizedBox(
                    height: lineHeight,
                    child: Row(
                      children: [
                        SizedBox(
                          width: 26,
                          child: Text(
                            '${i + 1}',
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              color: number,
                              fontFamily: 'PieBlockMono',
                              fontFamilyFallback: _codeFontFallbacks,
                              fontSize: _codeFontSize,
                              height: _codeLineHeightFactor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Padding(
                            padding: EdgeInsetsDirectional.only(
                              start: _skeletonLines[i % _skeletonLines.length]
                                  .indent,
                            ),
                            child: FractionallySizedBox(
                              alignment: AlignmentDirectional.centerStart,
                              widthFactor:
                                  _skeletonLines[i % _skeletonLines.length]
                                      .width,
                              child: Container(
                                height: 10,
                                decoration: BoxDecoration(
                                  color: bar,
                                  borderRadius: AppRadius.xs,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildFailure(BuildContext context, _CodeSurface surface) {
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.info_outline, color: surface.gutter),
            const SizedBox(height: 12),
            Text(
              widget.message ?? '还没有汇编列表，点「重试」再编译一次。',
              textAlign: TextAlign.center,
              style: TextStyle(color: surface.foreground),
            ),
            if (widget.onRetry != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: widget.onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 代码栏的字号与行高：两栏文本行数严格相等，滚动只需同步同一个偏移量。
const double _codeFontSize = 13;
const double _codeLineHeightFactor = 1.45;
const EdgeInsets _codeEditorPadding = EdgeInsets.symmetric(
  horizontal: 14,
  vertical: 12,
);
const _codeFontFallbacks = <String>[
  'PieBlockSans',
  'Noto Sans CJK SC',
  'Source Han Sans SC',
  'WenQuanYi Micro Hei Mono',
];

class _GeneratedCodePreview extends StatefulWidget {
  const _GeneratedCodePreview({
    required this.code,
    required this.onExport,
    this.fileName = 'main.c',
    this.languages,
    this.placeholder,
    this.controlsEnabled = true,
  });

  final String code;
  final VoidCallback onExport;
  final String fileName;

  /// 为空时按 [fileName] 后缀选语言（.asm / .rst 走 AS251）。
  final Map<String, CodeHighlightThemeMode>? languages;

  /// 内容还没就绪时替换编辑区，工具栏保持原位。
  final Widget? placeholder;

  /// 搜索、复制、另存为是否可用；内容没就绪时禁用。
  final bool controlsEnabled;

  @override
  State<_GeneratedCodePreview> createState() => _GeneratedCodePreviewState();
}

class _GeneratedCodePreviewState extends State<_GeneratedCodePreview> {
  late final CodeLineEditingController _editingController;
  late final TextEditingController _searchController;
  late final FocusNode _searchFocusNode;
  ScrollController? _verticalScroller;
  ScrollController? _horizontalScroller;
  late final CodeScrollController _scrollController;
  late final FocusNode _editorFocusNode;
  List<CodeLineSelection> _matches = const [];
  int _matchIndex = -1;

  /// 汇编字段的悬停说明：C 代码不启用。
  late final AsmHoverAnnotator _hover;
  OverlayEntry? _hoverCard;
  Timer? _hoverDelay;

  /// 按下鼠标期间不弹卡片，免得拖选代码时被挡住。
  bool _pressing = false;

  static const Duration _hoverDelayDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    _hover = AsmHoverAnnotator(onEnter: _hoverEnter, onExit: _hoverExit);
    _applyHoverSource(widget.code);
    _editingController = CodeLineEditingController(
      codeLines: widget.code.codeLines,
      spanBuilder: _buildCodeSpan,
    );
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode(debugLabel: 'code-search');
    final vertical = ScrollController();
    final horizontal = ScrollController();
    _verticalScroller = vertical;
    _horizontalScroller = horizontal;
    vertical.addListener(_hideHoverCard);
    horizontal.addListener(_hideHoverCard);
    _scrollController = CodeScrollController(
      verticalScroller: vertical,
      horizontalScroller: horizontal,
    );
    _editorFocusNode = FocusNode(debugLabel: 'generated-code-editor');
  }

  @override
  void didUpdateWidget(covariant _GeneratedCodePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code ||
        oldWidget.fileName != widget.fileName) {
      _hideHoverCard();
      _applyHoverSource(widget.code);
    }
    if (oldWidget.code != widget.code) {
      _editingController.text = widget.code;
      _updateSearch(_searchController.text);
    }
  }

  /// `.rst` 是链接器列表（带前 40 列），`.asm` 是纯汇编，其它文件不悬停。
  void _applyHoverSource(String code) {
    final name = widget.fileName.toLowerCase();
    final listing = name.endsWith('.rst');
    _hover.update(
      code,
      enabled: listing || name.endsWith('.asm'),
      listing: listing,
    );
  }

  TextSpan _buildCodeSpan({
    required BuildContext context,
    required int index,
    required CodeLine codeLine,
    required TextSpan textSpan,
    required TextStyle style,
  }) => _hover.buildSpan(codeLine: codeLine, textSpan: textSpan);

  void _hoverEnter(AsmHoverToken token, List<Rect> rects) {
    if (_pressing || rects.isEmpty) return;
    _hoverDelay?.cancel();
    _hoverDelay = Timer(_hoverDelayDuration, () {
      if (!mounted || _pressing) return;
      _showHoverCard(token, rects.first);
    });
  }

  void _hoverExit(AsmHoverToken token) => _hideHoverCard();

  void _showHoverCard(AsmHoverToken token, Rect anchor) {
    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;
    _removeHoverCard();
    final entry = OverlayEntry(
      builder: (context) => Positioned.fill(
        child: IgnorePointer(
          child: CustomSingleChildLayout(
            delegate: AsmHoverCardLayout(anchor: anchor),
            child: AsmHoverCard(token: token.text, data: token.data),
          ),
        ),
      ),
    );
    overlay.insert(entry);
    _hoverCard = entry;
  }

  void _hideHoverCard() {
    _hoverDelay?.cancel();
    _hoverDelay = null;
    _removeHoverCard();
  }

  void _removeHoverCard() {
    final entry = _hoverCard;
    if (entry == null) return;
    _hoverCard = null;
    if (entry.mounted) entry.remove();
    entry.dispose();
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
    _hideHoverCard();
    _editingController.selection = _matches[normalized];
    _scrollController.makeCenterIfInvisible(_matches[normalized].start);
    if (focusEditor) _editorFocusNode.requestFocus();
  }

  @override
  void dispose() {
    _hideHoverCard();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _editingController.dispose();
    _scrollController.dispose();
    _verticalScroller?.dispose();
    _horizontalScroller?.dispose();
    _editorFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final codeSurface = _CodeSurface.of(context);
    final background = codeSurface.background,
        foreground = codeSurface.foreground,
        gutter = codeSurface.gutter;
    final syntaxTheme = <String, TextStyle>{
      ...(dark ? atomOneDarkTheme : atomOneLightTheme),
      'root': TextStyle(color: foreground, backgroundColor: background),
    };
    final compact = _isCompact(context);
    final enabled = widget.controlsEnabled;
    final search = TextField(
      key: const ValueKey('code-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
      enabled: enabled,
      onChanged: _updateSearch,
      decoration: const InputDecoration(
        prefixIcon: Icon(Icons.search),
        labelText: '在代码中搜索',
      ),
    );
    final count = SizedBox(
      width: 58,
      child: Text(
        '${_matchIndex < 0 ? 0 : _matchIndex + 1} / ${_matches.length}',
        key: const ValueKey('code-search-count'),
        textAlign: TextAlign.center,
      ),
    );
    final previous = IconButton(
      onPressed: !enabled || _matches.isEmpty
          ? null
          : () => _selectMatch(_matchIndex - 1),
      tooltip: '上一个匹配',
      icon: const Icon(Icons.keyboard_arrow_up),
    );
    final next = IconButton(
      onPressed: !enabled || _matches.isEmpty
          ? null
          : () => _selectMatch(_matchIndex + 1),
      tooltip: '下一个匹配',
      icon: const Icon(Icons.keyboard_arrow_down),
    );
    final copy = IconButton.filledTonal(
      onPressed: enabled
          ? () {
              Clipboard.setData(ClipboardData(text: widget.code));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('代码已复制')));
            }
          : null,
      tooltip: '复制全部',
      icon: const Icon(Icons.copy),
    );
    final export = compact
        ? IconButton.filled(
            onPressed: enabled ? widget.onExport : null,
            tooltip: '另存为 ${widget.fileName}',
            icon: const Icon(Icons.save_alt),
          )
        : FilledButton.icon(
            onPressed: enabled ? widget.onExport : null,
            icon: const Icon(Icons.save_alt),
            label: const Text('另存为'),
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (compact) ...[
          search,
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 4,
            runSpacing: 4,
            children: [count, previous, next, copy, export],
          ),
        ] else
          Row(
            children: [
              Expanded(child: search),
              const SizedBox(width: 10),
              count,
              previous,
              next,
              const SizedBox(width: 4),
              copy,
              const SizedBox(width: 8),
              export,
            ],
          ),
        const SizedBox(height: 16),
        LegacyMaterialThemeBridge(
          child: SizedBox(
            height: (MediaQuery.sizeOf(context).height * .55).clamp(280, 560),
            child: AnimatedSwitcher(
              duration: AppMotion.defaultEffects(context),
              switchInCurve: AppMotion.expressiveDefaultEffects,
              switchOutCurve: AppMotion.expressiveDefaultEffects,
              child:
                  widget.placeholder ??
                  Listener(
                    key: const ValueKey('generated-code-editor-area'),
                    onPointerDown: (_) {
                      _pressing = true;
                      _hideHoverCard();
                    },
                    onPointerUp: (_) => _pressing = false,
                    onPointerCancel: (_) => _pressing = false,
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
                  CodeShortcutFindIntent:
                      CallbackAction<CodeShortcutFindIntent>(
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
                padding: _codeEditorPadding,
                borderRadius: BorderRadius.circular(AppCorner.md),
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
                              fontFamily: 'PieBlockMono',
                              fontFamilyFallback: _codeFontFallbacks,
                              fontSize: _codeFontSize,
                              height: _codeLineHeightFactor,
                            ),
                            focusedTextStyle: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontFamily: 'PieBlockMono',
                              fontFamilyFallback: _codeFontFallbacks,
                              fontSize: _codeFontSize,
                              height: _codeLineHeightFactor,
                            ),
                          ),
                        ),
                style: CodeEditorStyle(
                  fontFamily: 'PieBlockMono',
                  fontFamilyFallback: _codeFontFallbacks,
                  fontSize: _codeFontSize,
                  fontHeight: _codeLineHeightFactor,
                  textColor: foreground,
                  backgroundColor: background,
                  selectionColor: const Color(0xff02acc0)
                      .withValues(alpha: .34),
                  highlightColor: const Color(0xffef685d).withValues(alpha: .3),
                  cursorColor: Theme.of(context).colorScheme.primary,
                  cursorLineColor: Theme.of(context).colorScheme.primary
                      .withValues(alpha: .07),
                  codeTheme: CodeHighlightTheme(
                    // 按输出文件选语言；保持单条目，re_editor 才走确定性高亮。
                    languages:
                        widget.languages ??
                        (widget.fileName.endsWith('.asm')
                            ? {'asm': CodeHighlightThemeMode(mode: langAs251)}
                            : widget.fileName.endsWith('.rst')
                            ? {
                                'asm': CodeHighlightThemeMode(
                                  mode: langAs251Listing,
                                ),
                              }
                            : {'c': CodeHighlightThemeMode(mode: langC)}),
                    theme: syntaxTheme,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      ],
    );
  }
}

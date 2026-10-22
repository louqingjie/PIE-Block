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
                else if (asm.ready)
                  _GeneratedCodePreview(
                    code: listing!,
                    fileName: 'main.rst',
                    onExport: () => _export(listing, 'main.rst'),
                    languages: {
                      'asm': CodeHighlightThemeMode(mode: langAs251Listing),
                    },
                  )
                else
                  _ListingPlaceholder(
                    compiling: asm.compiling,
                    message: asm.message,
                    progress: asm.progress,
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
    child: ConnectedButtonGroup<bool>(
      semanticLabel: '输出语言',
      segments: const [
        ConnectedSegment(value: false, icon: Icons.code, label: 'C 代码'),
        ConnectedSegment(value: true, icon: Icons.memory, label: '汇编'),
      ],
      value: listing,
      onChanged: onChanged,
    ),
  );
}

/// 汇编栏还没就绪时的占位：编译中显示阶段进度，失败或降级时显示原因。
class _ListingPlaceholder extends StatelessWidget {
  const _ListingPlaceholder({
    required this.compiling,
    this.message,
    this.progress,
  });

  final bool compiling;
  final String? message, progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 26),
      decoration: ShapeDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        shape: AppShape.lg,
      ),
      child: Column(
        children: [
          if (compiling) ...[
            const WavyProgressIndicator(semanticLabel: '编译进度'),
            const SizedBox(height: 16),
            Text(
              '正在用内置 SDCC C251 构建 main.c…',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(
              progress ?? '编译全部源文件并链接后才会产出带机器码的 main.rst。',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ] else ...[
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(height: 12),
            Text(
              message ?? '还没有汇编列表，点「重新编译」再试一次。',
              textAlign: TextAlign.center,
            ),
          ],
        ],
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
  });

  final String code;
  final VoidCallback onExport;
  final String fileName;

  /// 为空时按 [fileName] 后缀选语言（.asm / .rst 走 AS251）。
  final Map<String, CodeHighlightThemeMode>? languages;

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

  @override
  void initState() {
    super.initState();
    _editingController = CodeLineEditingController.fromText(widget.code);
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode(debugLabel: 'code-search');
    final vertical = ScrollController();
    final horizontal = ScrollController();
    _verticalScroller = vertical;
    _horizontalScroller = horizontal;
    _scrollController = CodeScrollController(
      verticalScroller: vertical,
      horizontalScroller: horizontal,
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
    _verticalScroller?.dispose();
    _horizontalScroller?.dispose();
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
    final compact = _isCompact(context);
    final search = TextField(
      key: const ValueKey('code-search-field'),
      controller: _searchController,
      focusNode: _searchFocusNode,
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
      onPressed: _matches.isEmpty ? null : () => _selectMatch(_matchIndex - 1),
      tooltip: '上一个匹配',
      icon: const Icon(Icons.keyboard_arrow_up),
    );
    final next = IconButton(
      onPressed: _matches.isEmpty ? null : () => _selectMatch(_matchIndex + 1),
      tooltip: '下一个匹配',
      icon: const Icon(Icons.keyboard_arrow_down),
    );
    final copy = IconButton.filledTonal(
      onPressed: () {
        Clipboard.setData(ClipboardData(text: widget.code));
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('代码已复制')));
      },
      tooltip: '复制全部',
      icon: const Icon(Icons.copy),
    );
    final export = compact
        ? IconButton.filled(
            onPressed: widget.onExport,
            tooltip: '另存为 ${widget.fileName}',
            icon: const Icon(Icons.save_alt),
          )
        : FilledButton.icon(
            onPressed: widget.onExport,
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
                selectionColor: const Color(0xff02acc0).withValues(alpha: .34),
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
      ],
    );
  }
}

/// 生成代码页正在把 main.c 编译成汇编时的全屏等待遮罩。
class _AsmCompilingOverlay extends StatelessWidget {
  const _AsmCompilingOverlay({this.progress});

  /// 当前构建阶段文案（准备工具链 / 编译 x/y / 链接…），可能为空。
  final String? progress;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AbsorbPointer(
      child: ColoredBox(
        color: colors.surface.withValues(alpha: .9),
        child: Column(
          children: [
            const WavyProgressIndicator(semanticLabel: '正在构建汇编列表'),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '正在构建汇编列表…',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      progress ?? '用内置 SDCC C251 完整构建 main.c，首次使用需要先部署工具链。',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

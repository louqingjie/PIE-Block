import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:re_editor/re_editor.dart';

import 'asm_glossary.dart';

/// 列表文件（`main.rst`）每行前 40 列是地址 / 机器码 / 周期 / 行号，
/// 这四列只由空格、十六进制字符与方括号组成。用它判断某一行有没有前缀：
/// `.globl`、`.module` 这类行是顶格写的，没有前缀。
final RegExp _listingPrefix = RegExp(r'[ 0-9A-Fa-f\[\]]{40}');

/// 一个可悬停的汇编字段。[start] / [end] 是它在整行文本里的偏移。
class AsmHoverToken {
  const AsmHoverToken({
    required this.start,
    required this.end,
    required this.text,
    required this.data,
  });

  final int start;
  final int end;
  final String text;
  final AsmHoverData data;
}

/// 列表里出现的符号类别。
enum AsmSymbolKind { sfr, sfrBit, registerAlias, bitAlias, ram, label }

/// 列表符号表里的一条记录。
class AsmSymbol {
  const AsmSymbol({
    required this.kind,
    this.address,
    this.line,
    this.exported = false,
  });

  final AsmSymbolKind kind;

  /// SFR 的字节地址、位的位地址、标号的代码地址；未知时为 null。
  final int? address;

  /// 定义所在的列表行号（1 起）；等值定义没有行号意义时为 null。
  final int? line;

  /// 标签是否以 `::` 定义（对其它模块可见）。
  final bool exported;
}

/// 一次性解析 `main.rst`，得到符号表与标签表。
///
/// 列表开头就是编译器写出的符号定义（`_P0 = 0x0080`），并按
/// `; special function registers`、`; special function bits` 等分节标题
/// 归类，因此可以直接拿来区分「SFR 字节地址」与「SFR 位地址」——
/// 例如 `_SBUF` 与 `_TI` 的地址都是 0x99，含义却不同。
class AsmListingIndex {
  const AsmListingIndex({this.symbols = const {}, this.labels = const {}});

  factory AsmListingIndex.parse(String listing) {
    final symbols = <String, AsmSymbol>{};
    final labels = <String, AsmSymbol>{};
    var section = AsmSymbolKind.ram;
    final lines = listing.split('\n');
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final prefixEnd = listingPrefixEnd(line);
      final body = line.substring(prefixEnd);
      if (body.startsWith(';')) {
        final kind = _sectionOf(body);
        if (kind != null) section = kind;
        continue;
      }
      final text = body.trim();
      if (text.isEmpty) continue;
      final equate = _equate.firstMatch(text);
      if (equate != null) {
        final name = equate.group(1)!;
        final value = _hex.firstMatch(equate.group(2)!);
        symbols.putIfAbsent(
          name,
          () => AsmSymbol(
            kind: _kindOf(name, section),
            address: value == null
                ? null
                : int.tryParse(value.group(1)!, radix: 16),
          ),
        );
        continue;
      }
      final label = _labelDefinition.firstMatch(text);
      if (label != null) {
        labels.putIfAbsent(
          label.group(1)!,
          () => AsmSymbol(
            kind: AsmSymbolKind.label,
            address: _addressOf(line.substring(0, prefixEnd)),
            line: i + 1,
            exported: label.group(2) == '::',
          ),
        );
      }
    }
    return AsmListingIndex(symbols: symbols, labels: labels);
  }

  static const empty = AsmListingIndex();

  /// 等值定义的符号：SFR、SFR 位、寄存器别名、内部 RAM 变量。
  final Map<String, AsmSymbol> symbols;

  /// 标号定义。
  final Map<String, AsmSymbol> labels;

  AsmSymbol? operator [](String name) => labels[name] ?? symbols[name];
}

final RegExp _equate = RegExp(r'^([A-Za-z_][\w.$]*)\s*=\s*(.*)$');
final RegExp _hex = RegExp(r'0[xX]([0-9a-fA-F]+)');
final RegExp _labelDefinition = RegExp(r'^([\w.$]+)(::?)$');
final RegExp _addressField = RegExp(r'^[0-9A-Fa-f]{6}$');
final RegExp _registerAlias = RegExp(r'^ar[0-7]$');
final RegExp _bitAlias = RegExp(r'^b[0-7]$');
final RegExp _localLabel = RegExp(r'^\d+\$$');
final RegExp _spaces = RegExp(r'\s+');

/// 正文起始偏移：有列表前缀时是 40，否则是 0。
int listingPrefixEnd(String line) =>
    line.length >= 40 && _listingPrefix.hasMatch(line.substring(0, 40))
    ? 40
    : 0;

AsmSymbolKind? _sectionOf(String comment) {
  final text = comment.substring(1).trim().toLowerCase();
  return switch (text) {
    'special function registers' => AsmSymbolKind.sfr,
    'special function bits' => AsmSymbolKind.sfrBit,
    'overlayable register banks' => AsmSymbolKind.registerAlias,
    'overlayable bit register bank' => AsmSymbolKind.bitAlias,
    'internal ram data' => AsmSymbolKind.ram,
    'overlayable items in internal ram' => AsmSymbolKind.ram,
    'stack segment in internal ram' => AsmSymbolKind.ram,
    _ => null,
  };
}

/// `ar7 = 0x07` 这类等值定义散落在函数体里，所在分节已经不可靠，
/// 因此优先按名字判断。
AsmSymbolKind _kindOf(String name, AsmSymbolKind section) {
  if (_registerAlias.hasMatch(name)) return AsmSymbolKind.registerAlias;
  if (_bitAlias.hasMatch(name)) return AsmSymbolKind.bitAlias;
  return name.startsWith('_') ? section : AsmSymbolKind.ram;
}

int? _addressOf(String prefix) {
  final fields = prefix.split(_spaces).where((f) => f.isNotEmpty).toList();
  if (fields.length < 2) return null;
  // 最后一个字段是列表行号，机器码字节只有 2 位，因此 6 位十六进制就是地址。
  for (final field in fields.take(fields.length - 1)) {
    if (_addressField.hasMatch(field)) return int.tryParse(field, radix: 16);
  }
  return null;
}

/// 操作数扫描：位操作数、十六进制、局部标号、十进制、标识符、`@`、字符串。
final RegExp _operand = RegExp(
  r'(?<bit>[A-Za-z_][\w]*\.\d+)'
  r'|(?<hex>0[xX][0-9a-fA-F]+)'
  r'|(?<local>\d+\$)'
  r'|(?<dec>\d+)'
  r'|(?<id>[A-Za-z_.][\w.$]*)'
  r'|(?<at>@)'
  r'''|(?<str>"[^"]*"|'[^']*')''',
);

final RegExp _firstWord = RegExp(r'^([A-Za-z]\w*)');
final RegExp _directiveWord = RegExp(r'^(\.[A-Za-z]\w*)');

enum _Context { none, globl, module }

/// 把一行汇编切成可悬停的字段。
///
/// 只处理正文：列表前缀整体挂一条说明，`;` 之后（含 C 源码锚点）不产字段。
/// 返回的 token 按位置升序且互不重叠，偏移相对整行文本。
List<AsmHoverToken> tokenizeAsmLine(
  String line, {
  required bool listing,
  required AsmListingIndex index,
}) {
  final tokens = <AsmHoverToken>[];
  final prefixEnd = listing ? listingPrefixEnd(line) : 0;
  if (prefixEnd > 0 && line.substring(0, prefixEnd).trim().isNotEmpty) {
    tokens.add(
      AsmHoverToken(
        start: 0,
        end: prefixEnd,
        text: line.substring(0, prefixEnd),
        data: asmListingPrefix,
      ),
    );
  }
  if (line.length <= prefixEnd) return tokens;

  final body = line.substring(prefixEnd);
  final code = body.substring(0, _commentStart(body));
  final text = code.trim();
  if (text.isEmpty) return tokens;
  final base = prefixEnd + code.length - code.trimLeft().length;

  void add(int start, int end, AsmHoverData data) {
    if (end <= start) return;
    tokens.add(
      AsmHoverToken(
        start: base + start,
        end: base + end,
        text: text.substring(start, end),
        data: data,
      ),
    );
  }

  var operandStart = 0;
  var context = _Context.none;

  final directive = _directiveWord.firstMatch(text);
  final label = _labelDefinition.firstMatch(text);
  final equate = _equate.firstMatch(text);
  if (directive != null) {
    final name = directive.group(1)!;
    final info = asmDirectiveInfo(name);
    if (info != null) add(directive.start, directive.end, info);
    operandStart = directive.end;
    context = switch (name.toLowerCase()) {
      '.globl' => _Context.globl,
      '.module' => _Context.module,
      _ => _Context.none,
    };
    if (name.toLowerCase() == '.optsdcc') {
      var rest = directive.end;
      while (rest < text.length && (text[rest] == ' ' || text[rest] == '\t')) {
        rest++;
      }
      add(
        rest,
        text.length,
        const AsmHoverData(
          kind: AsmTokenKind.listing,
          title: 'SDCC 编译选项',
          description: '生成该模块时使用的命令行选项，由编译器写入列表，仅作记录。',
        ),
      );
      return tokens;
    }
  } else if (label != null) {
    final name = label.group(1)!;
    add(
      label.start,
      label.end,
      _labelInfo(name, index[name], exported: label.group(2) == '::'),
    );
    return tokens;
  } else if (equate != null) {
    final name = equate.group(1)!;
    final value = equate.group(2)!;
    // Match 只提供整体匹配的偏移，等值行以 ^ 锚定，符号名必然从 0 开始。
    add(
      0,
      name.length,
      _identifierInfo(name, index, _Context.none, defining: true),
    );
    operandStart = text.length - value.length;
  } else {
    final word = _firstWord.firstMatch(text);
    if (word != null) {
      final name = word.group(1)!;
      final info =
          asmMnemonicInfo(name) ?? _identifierInfo(name, index, _Context.none);
      add(word.start, word.end, info);
      operandStart = word.end;
    }
  }

  _scanOperands(text, operandStart, index, context, add);
  return tokens;
}

void _scanOperands(
  String text,
  int from,
  AsmListingIndex index,
  _Context context,
  void Function(int start, int end, AsmHoverData data) add,
) {
  for (final match in _operand.allMatches(text).where((m) => m.start >= from)) {
    final value = match[0]!;
    final before = text.substring(0, match.start).trimRight();
    if (match.namedGroup('hex') != null || match.namedGroup('dec') != null) {
      add(
        match.start,
        match.end,
        asmNumberInfo(
          value,
          negative: before.endsWith('-'),
          immediate: before.endsWith('#'),
        ),
      );
    } else if (match.namedGroup('local') != null) {
      add(match.start, match.end, _labelInfo(value, index[value]));
    } else if (match.namedGroup('bit') != null) {
      final dot = value.lastIndexOf('.');
      final register = value.substring(0, dot);
      final bit = int.tryParse(value.substring(dot + 1));
      if (bit == null) {
        add(match.start, match.end, _identifierInfo(value, index, context));
      } else {
        final registerInfo = asmRegisterInfo(register) ?? _sfrInfo(register);
        add(
          match.start,
          match.end,
          asmBitOperandInfo(register, bit, registerInfo),
        );
      }
    } else if (match.namedGroup('id') != null) {
      if (value == '.') {
        final info = asmNotationInfo('.');
        if (info != null) add(match.start, match.end, info);
      } else {
        add(match.start, match.end, _identifierInfo(value, index, context));
      }
    } else if (match.namedGroup('at') != null) {
      final info = asmNotationInfo('@');
      if (info != null) add(match.start, match.end, info);
    } else if (match.namedGroup('str') != null) {
      add(
        match.start,
        match.end,
        const AsmHoverData(
          kind: AsmTokenKind.number,
          title: '字符串常量',
          description: '按字符顺序写入的字节数据，由 .ascii / .asciz 伪指令定义。',
        ),
      );
    }
  }
}

/// `;` 之后的内容是注释或 C 源码锚点，不产字段；引号里的 `;` 不算注释。
int _commentStart(String text) {
  String? quote;
  for (var i = 0; i < text.length; i++) {
    final char = text[i];
    if (quote != null) {
      if (char == quote) quote = null;
      continue;
    }
    if (char == '"' || char == "'") {
      quote = char;
      continue;
    }
    if (char == ';') return i;
  }
  return text.length;
}

AsmHoverData _identifierInfo(
  String name,
  AsmListingIndex index,
  _Context context, {
  bool defining = false,
}) {
  switch (context) {
    case _Context.globl:
      final symbol = index[name];
      return AsmHoverData(
        kind: AsmTokenKind.symbol,
        title: '全局符号',
        description: '由 .globl 声明对其它模块可见，链接器据此解析跨模块引用。',
        detail: symbol?.line == null ? null : '定义于列表第 ${symbol!.line} 行',
      );
    case _Context.module:
      return const AsmHoverData(
        kind: AsmTokenKind.symbol,
        title: '模块名',
        description: '当前源文件对应的模块名，只影响符号命名与调试信息。',
      );
    case _Context.none:
      break;
  }

  final register = asmRegisterInfo(name);
  if (register != null) return register;
  final segment = asmSegmentInfo(name);
  if (segment != null) return segment;

  final symbol = index[name];
  if (symbol != null) return _symbolInfo(name, symbol, defining: defining);

  final sfr = _sfrInfo(name);
  if (sfr != null) return sfr;

  if (defining) {
    return AsmHoverData(
      kind: AsmTokenKind.symbol,
      title: '符号定义',
      description: '给 $name 赋一个固定值，后续可以用符号名代替这个值。',
    );
  }
  return AsmHoverData(
    kind: AsmTokenKind.symbol,
    title: '外部符号',
    description: '在其它模块中定义的函数或变量，链接时才确定地址。',
    detail: '下划线前缀来自 C 标识符的符号化规则。',
  );
}

/// 按列表符号表里的类别给出说明，并把地址补进 detail。
AsmHoverData _symbolInfo(
  String name,
  AsmSymbol symbol, {
  bool defining = false,
}) {
  final address = symbol.address == null
      ? null
      : '0x${symbol.address!.toRadixString(16).toUpperCase()}';
  switch (symbol.kind) {
    case AsmSymbolKind.sfr:
      final info = asmSfrInfo(name);
      if (info != null) {
        return info.withDetail(
          _join(info.detail, address == null ? null : '地址 $address'),
        );
      }
      return AsmHoverData(
        kind: AsmTokenKind.sfr,
        title: 'SFR · 特殊功能寄存器',
        description: '芯片外设与 CPU 状态的寄存器，用直接地址读写。',
        detail: address == null ? null : '地址 $address',
      );
    case AsmSymbolKind.sfrBit:
      final info = asmBitInfo(name);
      if (info != null) {
        return info.withDetail(
          _join(info.detail, address == null ? null : '位地址 $address'),
        );
      }
      return AsmHoverData(
        kind: AsmTokenKind.bit,
        title: 'SFR 位',
        description: '某个特殊功能寄存器中的一位，可以用位指令直接读写。',
        detail: address == null ? null : '位地址 $address',
      );
    case AsmSymbolKind.registerAlias:
      final info = asmRegisterInfo(name);
      if (info != null) return info;
      return AsmHoverData(
        kind: AsmTokenKind.register,
        title: '寄存器直接地址别名',
        description: '通用寄存器的直接地址符号，供 push / pop 这类只接受直接地址的指令使用。',
        detail: address == null ? null : '地址 $address',
      );
    case AsmSymbolKind.bitAlias:
      return AsmHoverData(
        kind: AsmTokenKind.bit,
        title: '位变量别名',
        description: 'SDCC 为位变量分配的符号，指向位寻址区中的某一位。',
        detail: address == null ? null : '位地址 $address',
      );
    case AsmSymbolKind.ram:
      return AsmHoverData(
        kind: AsmTokenKind.symbol,
        title: defining ? '内部 RAM 变量定义' : '内部 RAM 变量',
        description: '链接器为 C 变量分配的片内存储单元。',
        detail: address == null ? null : '地址 $address',
      );
    case AsmSymbolKind.label:
      return _labelInfo(name, symbol);
  }
}

AsmHoverData _labelInfo(
  String name,
  AsmSymbol? symbol, {
  bool exported = false,
}) {
  final isLocal = _localLabel.hasMatch(name);
  final global = exported || (symbol?.exported ?? false);
  final where = <String>[
    if (symbol?.line != null) '定义于列表第 ${symbol!.line} 行',
    if (symbol?.address != null)
      '地址 0x${symbol!.address!.toRadixString(16).toUpperCase()}',
  ];
  if (isLocal) {
    return AsmHoverData(
      kind: AsmTokenKind.label,
      title: '局部标号',
      description: 'SDCC 为分支生成的标号，以 \$ 结尾，只在当前函数内有效。',
      detail: where.isEmpty ? null : where.join('，'),
    );
  }
  if (global) {
    return AsmHoverData(
      kind: AsmTokenKind.label,
      title: '全局标号',
      description: '带 :: 的标号对其它模块可见，可被跨模块调用或引用。',
      detail: where.isEmpty ? null : where.join('，'),
    );
  }
  if (symbol == null) {
    return AsmHoverData(
      kind: AsmTokenKind.label,
      title: '标号引用',
      description: '跳转、调用或数据引用的目标；本列表中没有它的定义，地址在链接其它模块时确定。',
    );
  }
  return AsmHoverData(
    kind: AsmTokenKind.label,
    title: '标号',
    description: '标记一个代码位置，供跳转与调用引用，本身不产生机器码。',
    detail: where.isEmpty ? null : where.join('，'),
  );
}

/// `_P0` 这类名字若不在本列表的符号表里，再退回静态词表。
AsmHoverData? _sfrInfo(String name) =>
    name.startsWith('_') ? asmBitInfo(name) ?? asmSfrInfo(name) : null;

String? _join(String? a, String? b) => a == null
    ? b
    : b == null
    ? a
    : '$a；$b';

/// 悬停回调：进入时给出字段的全局矩形，离开时收起卡片。
typedef AsmHoverEnter = void Function(AsmHoverToken token, List<Rect> rects);
typedef AsmHoverExit = void Function(AsmHoverToken token);

/// 把悬停字段注入 re_editor 的高亮 span。
///
/// re_editor 只在指针命中的 span 是 [MouseTrackerAnnotationTextSpan]
/// **叶子**时才回调悬停事件（见 `_code_field.dart` 的 hitTest 与
/// `_code_paragraph.dart` 的 getRangeForSpan），所以这里先把高亮结果展平成
/// 带样式的叶段，再按字段范围切片，每片单独挂回调，样式原样保留。
class AsmHoverAnnotator {
  AsmHoverAnnotator({this.onEnter, this.onExit});

  AsmHoverEnter? onEnter;
  AsmHoverExit? onExit;

  /// 只有汇编视图启用；C 视图直接返回原 span。
  bool enabled = false;

  /// 是否为链接器列表（`main.rst`）：决定要不要剥掉前 40 列。
  bool listing = true;

  AsmListingIndex _symbols = AsmListingIndex.empty;
  final Map<String, List<AsmHoverToken>> _cache = {};

  static const int _cacheLimit = 4096;

  /// 换了一份代码：重建符号表并清空按行缓存。
  void update(String text, {required bool enabled, required bool listing}) {
    this.enabled = enabled;
    this.listing = listing;
    _cache.clear();
    _symbols = enabled && listing
        ? AsmListingIndex.parse(text)
        : AsmListingIndex.empty;
  }

  List<AsmHoverToken> tokensOf(String line) {
    final cached = _cache[line];
    if (cached != null) return cached;
    final tokens = tokenizeAsmLine(line, listing: listing, index: _symbols);
    if (_cache.length >= _cacheLimit) _cache.clear();
    _cache[line] = tokens;
    return tokens;
  }

  /// 供 `CodeLineEditingController(spanBuilder:)` 转调。
  TextSpan buildSpan({required CodeLine codeLine, required TextSpan textSpan}) {
    if (!enabled) return textSpan;
    final onEnter = this.onEnter, onExit = this.onExit;
    if (onEnter == null || onExit == null) return textSpan;
    final line = codeLine.text;
    final tokens = tokensOf(line);
    if (tokens.isEmpty) return textSpan;
    return buildAsmHoverSpan(
      highlighted: textSpan,
      lineText: line,
      tokens: tokens,
      onEnter: onEnter,
      onExit: onExit,
    );
  }
}

/// 纯函数版本，便于单元测试。
TextSpan buildAsmHoverSpan({
  required TextSpan highlighted,
  required String lineText,
  required List<AsmHoverToken> tokens,
  required AsmHoverEnter onEnter,
  required AsmHoverExit onExit,
}) {
  if (tokens.isEmpty) return highlighted;
  final segments = <_StyledSegment>[];
  _flatten(highlighted, segments);
  // 高亮结果与行文本长度不一致（折叠、截断等）时不注入，避免错位。
  if (segments.isEmpty || segments.last.end != lineText.length) {
    return highlighted;
  }

  final children = <InlineSpan>[];
  var tokenIndex = 0;
  for (final segment in segments) {
    var offset = segment.start;
    while (offset < segment.end) {
      while (tokenIndex < tokens.length && tokens[tokenIndex].end <= offset) {
        tokenIndex++;
      }
      final token =
          tokenIndex < tokens.length && tokens[tokenIndex].start <= offset
          ? tokens[tokenIndex]
          : null;
      final stop = token != null
          ? math.min(segment.end, token.end)
          : tokenIndex < tokens.length
          ? math.min(segment.end, tokens[tokenIndex].start)
          : segment.end;
      final text = lineText.substring(offset, stop);
      if (token == null) {
        children.add(TextSpan(text: text, style: segment.style));
      } else {
        children.add(
          MouseTrackerAnnotationTextSpan(
            text: text,
            style: segment.style,
            mouseCursor: SystemMouseCursors.help,
            onEnterWithRect: (event, id, rects) => onEnter(token, rects),
            onExitWithRect: (event, id, rects) => onExit(token),
          ),
        );
      }
      offset = stop;
    }
  }
  return TextSpan(style: highlighted.style, children: children);
}

class _StyledSegment {
  const _StyledSegment(this.start, this.end, this.style);

  final int start;
  final int end;
  final TextStyle? style;
}

void _flatten(TextSpan span, List<_StyledSegment> out) {
  final text = span.text;
  if (text != null && text.isNotEmpty) {
    final start = out.isEmpty ? 0 : out.last.end;
    out.add(_StyledSegment(start, start + text.length, span.style));
  }
  final children = span.children;
  if (children == null) return;
  for (final child in children) {
    if (child is TextSpan) _flatten(child, out);
  }
}

/// 解析 SDCC `-S --c-code-in-asm` 汇编列表里的源码行锚点。
///
/// SDCC 会在每条语句前插入一行形如 `;<路径>:<行号>: <C 原文>` 的注释，
/// 本文件把它转成「C 行 → 汇编区间」的映射，供生成代码页的 C/汇编对照视图使用。
/// 只做纯文本处理，不依赖 dart:io。
library;

import 'dart:convert';

/// 一条 C 语句在汇编文本中对应的连续区间。
class AsmAnchor {
  const AsmAnchor({
    required this.cLine,
    required this.asmStart,
    required this.asmEnd,
  });

  /// C 源码行号（1 基）。
  final int cLine;

  /// 展示文本中的起始行下标（0 基，含锚点注释行本身）。
  final int asmStart;

  /// 展示文本中的结束行下标（0 基，含）。
  final int asmEnd;

  int get asmLineCount => asmEnd - asmStart + 1;

  bool containsAsmLine(int asmLine) => asmLine >= asmStart && asmLine <= asmEnd;

  @override
  String toString() => 'AsmAnchor(C$cLine → 汇编 $asmStart..$asmEnd)';
}

/// 严格对齐的一对文本：两侧行数相等，每条 C 语句与它的汇编行块同处一块，
/// 较短的一侧用空行补齐。
class AlignedCodePair {
  const AlignedCodePair({
    required this.codeLines,
    required this.asmLines,
    required this.codeLineNumbers,
    required this.asmLineNumbers,
    required this.asmBlockStarts,
    required this.asmBlockEnds,
  });

  /// 左栏 C 文本（C 语句之后多出的部分为空行）。
  final List<String> codeLines;

  /// 右栏汇编文本（与 [codeLines] 等长，没有汇编的行是空行）。
  final List<String> asmLines;

  /// 每一行对应的真实 C 行号（左栏行号）：语句行与它汇编块的首行为行号，
  /// 补齐行与汇编块的续行为 `null`（界面上显示为空号）。
  final List<int?> codeLineNumbers;

  /// 每一行对应的汇编自身行号（右栏行号，从左栏之外的独立计数）：
  /// 汇编块的行依次编号，补齐行为 `null`（界面上显示为空号）。
  final List<int?> asmLineNumbers;

  /// [asmLines] 每行所属汇编块的起始行下标。
  final List<int> asmBlockStarts;

  /// [asmLines] 每行所属汇编块的结束行下标（含）。
  final List<int> asmBlockEnds;

  int get rowCount => codeLines.length;

  /// 两侧行数必须严格相等，否则对齐失败。
  bool get aligned =>
      codeLines.length == asmLines.length &&
      codeLineNumbers.length == codeLines.length &&
      asmLineNumbers.length == codeLines.length &&
      asmBlockStarts.length == codeLines.length &&
      asmBlockEnds.length == codeLines.length;

  String get codeText => codeLines.join('\n');

  String get asmText => asmLines.join('\n');

  int _clampRow(int row) => row.clamp(0, rowCount == 0 ? 0 : rowCount - 1);

  /// [asmLines] 第 [row] 行所属汇编块的起始行（含）。
  int asmBlockStartAt(int row) => asmBlockStarts[_clampRow(row)];

  /// [asmLines] 第 [row] 行所属汇编块的结束行（含）。
  int asmBlockEndAt(int row) => asmBlockEnds[_clampRow(row)];
}

/// 一份可供对照阅读的汇编列表。
class AsmListing {
  AsmListing({
    required this.lines,
    required this.anchorsByCLine,
    required this.mainFileName,
  });

  /// 展示用汇编文本：已剥掉本机路径，并把锚点注释改写为 `;	L<行号>: <C 原文>`。
  final List<String> lines;

  /// C 行号（1 基）→ 该行对应的汇编区间；同一行出现多个锚点（如循环条件）时有多条。
  final Map<int, List<AsmAnchor>> anchorsByCLine;

  final String mainFileName;

  /// 源文件路径里形如 `;<路径>:<行号>: <C 原文>` 的锚点注释。
  static final RegExp _anchorPattern = RegExp(r'^\s*;\s+(.*?):(\d+):(.*)$');

  /// 首个主文件锚点之前的 SDCC 样板与 SFR 符号表整段丢弃。
  static AsmListing parse(String rawAsm, {String mainFileName = 'main.c'}) {
    final rawLines = const LineSplitter().convert(rawAsm);
    final display = <String>[];
    final anchors = <int, List<AsmAnchor>>{};

    var firstIndex = -1;
    for (var index = 0; index < rawLines.length; index += 1) {
      final match = _anchorPattern.firstMatch(rawLines[index]);
      if (match != null && _isMainFile(match.group(1)!, mainFileName)) {
        firstIndex = index;
        break;
      }
    }
    if (firstIndex < 0) {
      return AsmListing(
        lines: const [],
        anchorsByCLine: const {},
        mainFileName: mainFileName,
      );
    }

    int? activeCLine;
    var activeStart = 0;
    void closeActive() {
      final cLine = activeCLine;
      if (cLine == null) return;
      final end = display.length - 1;
      if (end < activeStart) return;
      (anchors[cLine] ??= []).add(
        AsmAnchor(cLine: cLine, asmStart: activeStart, asmEnd: end),
      );
    }

    for (var index = firstIndex; index < rawLines.length; index += 1) {
      final line = rawLines[index];
      final match = _anchorPattern.firstMatch(line);
      if (match == null) {
        display.add(line);
        continue;
      }
      final source = match.group(1)!;
      final lineNumber = int.parse(match.group(2)!);
      final text = match.group(3)!;
      if (_isMainFile(source, mainFileName)) {
        closeActive();
        activeCLine = lineNumber;
        activeStart = display.length;
        display.add(';\tL$lineNumber:$text');
        continue;
      }
      // 头文件 / 库内联展开的锚点：不新起区间，随后的汇编并入上一个主文件区间，
      // 但仍剥掉本机路径，避免把绝对路径显示在界面上。
      display.add(';\t${_fileName(source)}:$lineNumber:$text');
    }
    closeActive();

    return AsmListing(
      lines: display,
      anchorsByCLine: anchors,
      mainFileName: mainFileName,
    );
  }

  /// 把 C 源码与汇编排成严格逐行对齐的一对文本：每条 C 语句占一行，
  /// 它对应的 N 行汇编紧贴在同一行块里，较短的一侧用空行补齐。
  ///
  /// 两侧的行数因此相等、滚动只需同步同一个偏移量；但两侧的行号各自独立：
  /// 左栏是真实 C 行号，右栏是汇编自身的行号，补齐行都不编号。
  AlignedCodePair alignWith(String sourceCode) {
    final sourceLines = const LineSplitter().convert(sourceCode);
    final codeLines = <String>[];
    final asmLines = <String>[];
    final codeLineNumbers = <int?>[];
    final asmLineNumbers = <int?>[];
    final asmBlockStarts = <int>[];
    final asmBlockEnds = <int>[];
    var asmLine = 0;

    for (var index = 0; index < sourceLines.length; index += 1) {
      final cLine = index + 1;
      final instructions = <String>[];
      for (final anchor in anchorsForCLine(cLine)) {
        for (var line = anchor.asmStart + 1; line <= anchor.asmEnd; line += 1) {
          instructions.add(lines[line]);
        }
      }

      final start = asmLines.length;
      codeLines.add(sourceLines[index]);
      codeLineNumbers.add(cLine);
      if (instructions.isEmpty) {
        // 不产生汇编的 C 行（预处理、注释、空行、纯声明）右侧补一行空行。
        asmLines.add('');
        asmLineNumbers.add(null);
      } else {
        for (final instruction in instructions) {
          asmLine += 1;
          asmLines.add(instruction);
          asmLineNumbers.add(asmLine);
          if (asmLines.length - 1 > start) {
            codeLines.add('');
            codeLineNumbers.add(null);
          }
        }
      }
      // 行块内每一行都指向同一段区间，点选任意一行都能高亮整块。
      final end = asmLines.length - 1;
      for (var row = start; row <= end; row += 1) {
        asmBlockStarts.add(start);
        asmBlockEnds.add(end);
      }
    }

    return AlignedCodePair(
      codeLines: codeLines,
      asmLines: asmLines,
      codeLineNumbers: codeLineNumbers,
      asmLineNumbers: asmLineNumbers,
      asmBlockStarts: asmBlockStarts,
      asmBlockEnds: asmBlockEnds,
    );
  }

  /// 命中 C 行的锚点（可能多条：同一行被重复生成的循环条件等）。
  List<AsmAnchor> anchorsForCLine(int cLine) =>
      anchorsByCLine[cLine] ?? const <AsmAnchor>[];

  /// 已映射的 C 行数量，用于「覆盖 x/y 行」文案。
  int get mappedCLineCount => anchorsByCLine.length;

  static bool _isMainFile(String source, String mainFileName) =>
      _fileName(source).toLowerCase() == mainFileName.toLowerCase();

  /// 同时兼容 Windows 与 POSIX 分隔符的取文件名。
  static String _fileName(String source) {
    var cursor = -1;
    for (var index = 0; index < source.length; index += 1) {
      final unit = source[index];
      if (unit == '\\' || unit == '/') cursor = index;
    }
    return source.substring(cursor + 1);
  }
}

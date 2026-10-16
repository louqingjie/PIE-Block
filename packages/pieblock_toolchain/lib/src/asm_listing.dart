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

  /// 展示文本行号（0 基）→ 其所属区间的 C 行号；用于「点右栏高亮左栏」。
  final Map<int, int> _cLineByAsmLine = {};

  /// 升序的已映射 C 行号，供滚动同步做二分查找。
  List<int> _sortedCLines = const [];

  /// 源文件路径里形如 `;<路径>:<行号>: <C 原文>` 的锚点注释。
  static final RegExp _anchorPattern = RegExp(r'^\s*;\s+(.*?):(\d+):(.*)$');

  /// 首个主文件锚点之前的 SDCC 样板与 SFR 符号表整段丢弃。
  static AsmListing parse(String rawAsm, {String mainFileName = 'main.c'}) {
    final rawLines = const LineSplitter().convert(rawAsm);
    final display = <String>[];
    final anchors = <int, List<AsmAnchor>>{};
    final cLineByAsmLine = <int, int>{};

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
      for (var line = activeStart; line <= end; line += 1) {
        cLineByAsmLine[line] = cLine;
      }
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

    final listing = AsmListing(
      lines: display,
      anchorsByCLine: anchors,
      mainFileName: mainFileName,
    );
    listing._cLineByAsmLine.addAll(cLineByAsmLine);
    listing._sortedCLines = anchors.keys.toList()..sort();
    return listing;
  }

  /// 命中 C 行的锚点（可能多条：同一行被重复生成的循环条件等）。
  List<AsmAnchor> anchorsForCLine(int cLine) =>
      anchorsByCLine[cLine] ?? const <AsmAnchor>[];

  /// 汇编行所属的 C 行号；区间之外返回 `null`。
  int? cLineForAsmLine(int asmLine) => _cLineByAsmLine[asmLine];

  /// ≤ [cLine] 的最近一个已映射 C 行；没有则返回 `null`。
  int? nearestMappedCLineAtOrBefore(int cLine) {
    final lines = _sortedCLines;
    if (lines.isEmpty) return null;
    var low = 0;
    var high = lines.length - 1;
    int? found;
    while (low <= high) {
      final mid = (low + high) >> 1;
      if (lines[mid] <= cLine) {
        found = lines[mid];
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return found;
  }

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

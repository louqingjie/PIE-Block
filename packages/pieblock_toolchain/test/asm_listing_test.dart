import 'package:pieblock_toolchain/asm_listing.dart';
import 'package:test/test.dart';

/// 用 SDCC 4.6 `-mmcs251 -S --c-code-in-asm` 的真实输出格式做样例：
/// 前导是样板与 SFR 符号定义，语句前是 `;<路径>:<行号>: <C 原文>` 注释。
const _sample = '''
;--------------------------------------------------------
; File Created by SDCC : free open source ISO C Compiler
;--------------------------------------------------------
        .module main
        .optsdcc -mmcs251 --model-large
_R7 = 0x07
        .area RSEG    (ABS,DATA)
        .org 0x0000
;       C:\\Users\\tester\\AppData\\Local\\Temp\\main.c:5: void main(void) {
        .area HOME    (CODE)
_main:
        ar7 = 0x07
;       C:\\Users\\tester\\AppData\\Local\\Temp\\main.c:7: uint8_t uart1InterruptEnabled = ES;
        mov     c,_ES
;       C:\\Users\\tester\\AppData\\Local\\Temp\\main.c:9: while (!TI) ;
00101\$:
        jb      _TI,00120\$
;       C:\\Users\\tester\\AppData\\Local\\Temp\\main.c:9: while (!TI) ;
00120\$:
        sjmp    00120\$
;       /home/tester/build/main.h:12: static inline void Helper(void)
        nop
;       C:\\Users\\tester\\AppData\\Local\\Temp\\main.c:11: TI = 0;
        clr     _TI
''';

void main() {
  group('AsmListing 锚点解析', () {
    final listing = AsmListing.parse(_sample);

    test('丢弃首个主文件锚点之前的样板与符号表', () {
      expect(listing.lines.any((line) => line.contains('.optsdcc')), isFalse);
      expect(listing.lines.any((line) => line.contains('_R7 = 0x07')), isFalse);
      expect(listing.lines.first, ';\tL5: void main(void) {');
    });

    test('剥掉本机路径，锚点注释改写为 L<行号>', () {
      for (final line in listing.lines) {
        expect(line, isNot(contains('AppData')));
        expect(line, isNot(contains('/home/tester')));
      }
      expect(listing.lines, contains(';\tmain.h:12: static inline void Helper(void)'));
    });

    test('单条语句对应一段连续汇编（C 一句对汇编 N 句）', () {
      final anchors = listing.anchorsForCLine(7);
      expect(anchors, hasLength(1));
      final anchor = anchors.single;
      final anchorLine = listing.lines.indexWhere((line) => line.contains('L7:'));
      expect(anchor.asmStart, anchorLine);
      expect(listing.lines[anchor.asmStart], contains('L7:'));
      expect(listing.lines[anchor.asmEnd], '        mov     c,_ES');
      expect(anchor.containsAsmLine(anchor.asmStart), isTrue);
    });

    test('同一 C 行重复生成多个锚点区间', () {
      final anchors = listing.anchorsForCLine(9);
      expect(anchors, hasLength(2));
      expect(anchors[0].asmStart, lessThan(anchors[1].asmStart));
      expect(anchors[0].asmEnd, lessThan(anchors[1].asmStart));
    });

    test('头文件锚点不新起区间，并入上一个主文件区间', () {
      final nopLine = listing.lines.indexWhere((line) => line.trim() == 'nop');
      expect(nopLine, greaterThan(0));
      expect(listing.anchorsForCLine(9).last.asmEnd, nopLine);
    });

    test('覆盖计数正确', () {
      expect(listing.anchorsForCLine(8), isEmpty);
      expect(listing.mappedCLineCount, 4);
    });

    test('没有锚点时返回空列表', () {
      final empty = AsmListing.parse('        .module main\n');
      expect(empty.lines, isEmpty);
      expect(empty.mappedCLineCount, 0);
      expect(empty.alignWith('void main(void) {\n}\n').rowCount, 2);
    });
  });

  group('AsmListing 逐行对齐', () {
    // 与 _sample 的锚点行号对齐：5 / 7 / 9 / 11 行才有汇编。
    const source = '''
// 对齐样例：只有 5 / 7 / 9 / 11 行产生汇编
// 预处理、注释、空行与纯声明都不产生汇编
#include <stdint.h>

void main(void) {
    // 声明不产生汇编
    uint8_t uart1InterruptEnabled = ES;
    // 空语句不产生汇编
    while (!TI) ;
    ;
    TI = 0;
}''';
    final pair = AsmListing.parse(_sample).alignWith(source);

    test('两侧行数严格相等，行号列各自独立', () {
      expect(pair.aligned, isTrue);
      expect(pair.codeLines.length, pair.asmLines.length);
      expect(pair.codeLineNumbers.length, pair.rowCount);
      expect(pair.asmLineNumbers.length, pair.rowCount);
      // C 源码 12 行，其中 4 行产生汇编，其余行在右栏各占一行空行。
      expect(pair.rowCount, greaterThan(12));
      // 左栏行号是真实 C 行号（补空行留空），右栏行号是汇编自身序号。
      expect(
        pair.codeLineNumbers.whereType<int>().toList(),
        List.generate(12, (index) => index + 1),
      );
      expect(
        pair.asmLineNumbers.whereType<int>().toList(),
        List.generate(11, (index) => index + 1),
      );
      expect(pair.codeLineNumbers.contains(null), isTrue);
      expect(pair.asmLineNumbers.contains(null), isTrue);
    });

    test('一句话对应 N 句汇编，多出的部分在左栏补空行', () {
      final assignRow = pair.codeLines.indexOf(
        '    uint8_t uart1InterruptEnabled = ES;',
      );
      expect(pair.codeLineNumbers[assignRow], 7);
      expect(pair.asmLines[assignRow], '        mov     c,_ES');
      expect(pair.asmBlockStartAt(assignRow), assignRow);
      expect(pair.asmBlockEndAt(assignRow), assignRow);

      final whileRow = pair.codeLines.indexOf('    while (!TI) ;');
      expect(pair.codeLineNumbers[whileRow], 9);
      expect(pair.asmLines[whileRow], '00101\$:');
      // 循环条件被重复生成两段（含并入的头文件锚点），共 6 句汇编合成一行块。
      expect(pair.asmBlockEndAt(whileRow), whileRow + 5);
      for (var row = whileRow + 1; row <= whileRow + 5; row += 1) {
        expect(pair.codeLines[row], '');
        expect(pair.codeLineNumbers[row], isNull);
        expect(pair.asmBlockStartAt(row), whileRow);
        expect(pair.asmLines[row], isNotEmpty);
      }
    });

    test('不产生汇编的 C 行在右栏补空行', () {
      final bareRow = pair.codeLines.indexOf('    ;');
      expect(pair.codeLineNumbers[bareRow], 10);
      expect(pair.asmLines[bareRow], '');
      final braceRow = pair.codeLines.indexOf('}');
      expect(pair.asmLines[braceRow], '');
      expect(pair.asmBlockEndAt(braceRow), braceRow);
    });

    test('两侧文本可直接喂给编辑器', () {
      expect(pair.codeText.split('\n'), pair.codeLines);
      expect(pair.asmText.split('\n'), pair.asmLines);
      expect(pair.asmText.split('\n').length, pair.codeText.split('\n').length);
    });
  });
}

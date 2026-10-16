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
      expect(listing.cLineForAsmLine(nopLine), 9);
    });

    test('汇编行反查 C 行，区间外为空', () {
      final first = listing.lines.indexWhere((line) => line.contains('L5:'));
      expect(listing.cLineForAsmLine(first), 5);
      expect(listing.cLineForAsmLine(first - 1), isNull);
    });

    test('滚动同步用最近已映射行，覆盖计数正确', () {
      expect(listing.nearestMappedCLineAtOrBefore(3), isNull);
      expect(listing.nearestMappedCLineAtOrBefore(6), 5);
      expect(listing.nearestMappedCLineAtOrBefore(8), 7);
      expect(listing.nearestMappedCLineAtOrBefore(10), 9);
      expect(listing.anchorsForCLine(8), isEmpty);
      expect(listing.mappedCLineCount, 4);
    });

    test('没有锚点时返回空列表', () {
      final empty = AsmListing.parse('        .module main\n');
      expect(empty.lines, isEmpty);
      expect(empty.mappedCLineCount, 0);
      expect(empty.nearestMappedCLineAtOrBefore(10), isNull);
      expect(empty.cLineForAsmLine(0), isNull);
    });
  });
}

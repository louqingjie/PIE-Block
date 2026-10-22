import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_app/src/as251_highlight_mode.dart';
import 'package:pieblock_app/src/asm_glossary.dart';
import 'package:pieblock_app/src/design/app_theme.dart';
import 'package:pieblock_app/src/design/asm_hover_card.dart';

/// `sdcc-c251/sdas/as251/tests/instruction-families.txt` 里的 65 个指令族。
/// 抄一份放在这里，是为了在词表漏掉某一族时立刻失败。
const _instructionFamilies = [
  'acall',
  'add',
  'addc',
  'ajmp',
  'anl',
  'cjne',
  'clr',
  'cmp',
  'cpl',
  'da',
  'dec',
  'div',
  'djnz',
  'ecall',
  'ejmp',
  'eret',
  'esc',
  'inc',
  'jb',
  'jbc',
  'jc',
  'je',
  'jg',
  'jle',
  'jmp',
  'jnb',
  'jnc',
  'jne',
  'jnz',
  'jsg',
  'jsge',
  'jsl',
  'jsle',
  'jz',
  'lcall',
  'ljmp',
  'mov',
  'movc',
  'movh',
  'movs',
  'movx',
  'movz',
  'mul',
  'nop',
  'orl',
  'pop',
  'push',
  'ret',
  'reti',
  'rl',
  'rlc',
  'rr',
  'rrc',
  'setb',
  'sjmp',
  'sll',
  'sra',
  'srl',
  'sub',
  'subb',
  'swap',
  'trap',
  'xch',
  'xchd',
  'xrl',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('词表覆盖', () {
    test('65 个指令族与两个汇编器别名都有说明', () {
      expect(_instructionFamilies, hasLength(65));
      for (final mnemonic in _instructionFamilies) {
        expect(asmMnemonicInfo(mnemonic), isNotNull, reason: mnemonic);
      }
      expect(asmMnemonicInfo('call'), isNotNull);
      expect(asmMnemonicInfo('pushw'), isNotNull);
    });

    test('助记符查表忽略大小写，不存在的助记符返回空', () {
      expect(asmMnemonicInfo('MOV')?.title, asmMnemonicInfo('mov')?.title);
      expect(asmMnemonicInfo('Ecall'), isNotNull);
      // MCS-251 的移位助记符是 sll；sla 是别的架构的写法。
      expect(asmMnemonicInfo('sla'), isNull);
      expect(asmMnemonicInfo('movq'), isNull);
    });

    test('寄存器覆盖 R0–R15、AR0–AR7、WR 与 DR 元组', () {
      for (var i = 0; i <= 15; i++) {
        expect(asmRegisterInfo('r$i'), isNotNull, reason: 'r$i');
      }
      for (var i = 0; i <= 7; i++) {
        expect(asmRegisterInfo('ar$i'), isNotNull, reason: 'ar$i');
      }
      for (var i = 0; i <= 30; i += 2) {
        expect(asmRegisterInfo('wr$i'), isNotNull, reason: 'wr$i');
      }
      for (var i = 0; i <= 28; i += 4) {
        expect(asmRegisterInfo('dr$i'), isNotNull, reason: 'dr$i');
      }
      expect(asmRegisterInfo('a'), isNotNull);
      expect(asmRegisterInfo('DPX'), isNotNull);
      expect(asmRegisterInfo('spx'), isNotNull);
      // DR30 与 DPXH 都不是 MCS-251 的寄存器。
      expect(asmRegisterInfo('dr30'), isNull);
      expect(asmRegisterInfo('dpxh'), isNull);
    });

    test('每条说明都有标题、正文与类型标签', () {
      final entries = <AsmHoverData>[
        ...asmMnemonics.values,
        ...asmRegisters.values,
        ...asmSegments.values,
        ...asmDirectives.values,
        ...asmNotations.values,
        ...asmSpecialFunctionRegisters.values,
        ...asmSpecialFunctionBits.values,
        asmListingPrefix,
        asmUnknownSymbol,
      ];
      for (final entry in entries) {
        expect(entry.title.trim(), isNotEmpty);
        expect(entry.description.trim(), isNotEmpty);
        expect(entry.kindLabel.trim(), isNotEmpty);
      }
      // 静态词表的标题统一是「名字 · 中文说明」，卡片抬头才有一致的观感。
      for (final entry in [
        ...asmMnemonics.values,
        ...asmRegisters.values,
        ...asmSegments.values,
        ...asmDirectives.values,
        ...asmSpecialFunctionRegisters.values,
        ...asmSpecialFunctionBits.values,
      ]) {
        expect(entry.title, contains(' · '), reason: entry.title);
      }
    });

    test('常用 SFR 与位名可按列表里的下划线写法查到', () {
      expect(asmSfrInfo('_P0')?.title, startsWith('P0'));
      expect(asmSfrInfo('P0'), isNotNull);
      expect(asmSfrInfo('_SBUF')?.description, contains('0x99'));
      expect(asmBitInfo('_TI')?.title, startsWith('TI'));
      expect(asmBitInfo('_EA')?.kind, AsmTokenKind.bit);
      expect(asmSfrInfo('_NoSuchRegister'), isNull);
      expect(asmBitInfo('_NoSuchBit'), isNull);
    });
  });

  group('高亮词表与词表同步', () {
    final keywords = as251Mode().keywords! as Map<String, dynamic>;

    test('着色为助记符的词都能悬停', () {
      for (final word in (keywords['keyword']! as String).split(' ')) {
        expect(asmMnemonicInfo(word), isNotNull, reason: word);
      }
    });

    test('着色为寄存器的词都能悬停', () {
      for (final word in (keywords['built_in']! as String).split(' ')) {
        expect(
          asmRegisterInfo(word) ?? asmSegmentInfo(word),
          isNotNull,
          reason: word,
        );
      }
    });

    test('着色为伪指令的词都能悬停', () {
      for (final word in (keywords['meta']! as String).split(' ')) {
        expect(asmDirectiveInfo(word), isNotNull, reason: word);
      }
    });

    test('列表模式与纯汇编模式共用同一套词表', () {
      final listing =
          as251Mode(listing: true).keywords! as Map<String, dynamic>;
      expect(listing['keyword'], keywords['keyword']);
      expect(listing['built_in'], keywords['built_in']);
      expect(listing['meta'], keywords['meta']);
    });
  });

  group('悬停卡片', () {
    testWidgets('显示字段原文、类型标签与说明', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.dark),
          home: Scaffold(
            body: Center(
              child: AsmHoverCard(token: 'mov', data: asmMnemonicInfo('mov')!),
            ),
          ),
        ),
      );

      expect(find.text('mov'), findsOneWidget);
      expect(find.text('指令'), findsOneWidget);
      expect(find.text('MOV · 数据传送'), findsOneWidget);
      expect(find.textContaining('源操作数'), findsOneWidget);
      expect(find.textContaining('mov 目的, 源'), findsOneWidget);
    });

    testWidgets('列表前缀这类长字段压成单行显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(brightness: Brightness.light),
          home: Scaffold(
            body: Center(
              child: AsmHoverCard(
                token: '      FE0548 7E 70 00         [12] 1205 ',
                data: asmListingPrefix,
              ),
            ),
          ),
        ),
      );

      expect(find.text('FE0548 7E 70 00 [12] 1205'), findsOneWidget);
      expect(find.text('列表'), findsOneWidget);
    });

    test('卡片优先放在字段下方，空间不足时翻到上方并水平夹紧', () {
      const below = AsmHoverCardLayout(anchor: Rect.fromLTWH(100, 100, 30, 14));
      expect(
        below.getPositionForChild(const Size(800, 600), const Size(300, 80)),
        const Offset(100, 120),
      );

      const above = AsmHoverCardLayout(anchor: Rect.fromLTWH(100, 580, 30, 14));
      expect(
        above.getPositionForChild(const Size(800, 600), const Size(300, 80)),
        const Offset(100, 494),
      );

      const right = AsmHoverCardLayout(anchor: Rect.fromLTWH(780, 100, 30, 14));
      expect(
        right.getPositionForChild(const Size(800, 600), const Size(300, 80)).dx,
        800 - 8 - 300,
      );

      expect(
        below
            .getConstraintsForChild(
              const BoxConstraints(
                minWidth: 0,
                maxWidth: 800,
                minHeight: 0,
                maxHeight: 600,
              ),
            )
            .maxWidth,
        AsmHoverCard.maxWidth,
      );
    });
  });
}

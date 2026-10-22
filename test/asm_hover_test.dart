import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:pieblock_app/src/asm_glossary.dart';
import 'package:pieblock_app/src/asm_hover.dart';
import 'package:re_editor/re_editor.dart';

/// 以下各行摘自真实的 `main.rst`：前 40 列是地址 / 机器码 / 周期 / 行号，
/// 之后才是汇编正文。保留原样是为了让偏移量断言有意义。
const _movR7 = '      FE0548 7E 70 00         [12] 1205 \tmov\tr7,#0x00';
const _label104 = '      FE054B                       1206 00104\$:';
const _pushAr7 = '      FE054B C0 07            [24] 1208 \tpush\tar7';
const _ecall =
    '      FE054D 9A FE 60 A3      [12] 1209 \tecall\t_NRF24L01_Init';
const _movADpl = '      FE0551 E5 82            [12] 1210 \tmov\ta, dpl';
const _jnz = '      FE0555 70 04            [24] 1212 \tjnz\t00122\$';
const _movDptr = '      FE055B 90 00 C8         [24] 1216 \tmov\tdptr,#0x00c8';
const _jbAccBit = '      FE0582 20 E0 04         [24] 1249 \tjb\tacc.0,00130\$';
const _decSpx = '      FE05A2 1B FD            [12] 1263 \tdec\tspx,#2';
const _movWr2 =
    '      FE062B 69 1F FF FC      [12] 1341 \tmov\twr2,@spx-0x0004';
const _mulAb = '      FE067A A4               [48] 1399 \tmul\tab';
const _movDr28 = '      FE06CA 7F 7E            [12] 1471 \tmov\tdr28,dpx';
const _movADpx = '      FE06CC 7E EB B0         [12] 1472 \tmov\ta,@dpx';
const _setbEa = '      FE0F51 D2 AF            [12] 2488 \tsetb\t_EA';
const _movc = '      FE12FD 93               [24] 2929 \tmovc\ta,@a+dptr';
const _subWr = '      FE1760 9D 32            [12] 3421 \tsub\twr6,wr4';
const _movzWr8 = '      FE1DC0 0A 49            [12] 4162 \tmovz\twr8,r9';
const _sfrP0 = '                           000080   471 _P0\t=\t0x0080';
const _bitTi = '                           000099   649 _TI\t=\t0x0099';
const _aliasAr7 = '                           000007  1196 \tar7 = 0x07';
const _area =
    '                                    469 \t.area RSEG    (ABS,DATA)';
const _optsdcc =
    '                                      7 \t.optsdcc -mmcs251 --model-large';
const _globlMain = '                                     11 \t.globl _main';
const _cAnchor =
    '                                   1204 ;\tC:\\tmp\\main.c:93: for (retry = 0; retry < 20; retry++)';

/// 带分节标题与符号表的列表片段，用来验证 [AsmListingIndex]。
/// 行号即它在列表中的位置，断言「定义于第 N 行」时以此为准。
const _sampleLines = [
  '                                    467 ; special function registers',
  '                                    468 ;--------------------------------------------------------',
  '                           000080   471 _P0\t=\t0x0080',
  '                                    588 ;--------------------------------------------------------',
  '                                    589 ; special function bits',
  '                                    590 ;--------------------------------------------------------',
  '                           000099   649 _TI\t=\t0x0099',
  '                                    873 ; overlayable register banks',
  '                           000007  1196 \tar7 = 0x07',
  '      FE0548                       1195 _remoteControlInitWithTimeout:',
  '      FE054B                       1206 00104\$:',
  '      FE055B                       1214 00122\$:',
  '      FF0007 9A FE 08 5F      [12]  131 \tecall\t_main',
];
final _sampleListing = _sampleLines.join('\n');

List<AsmHoverToken> tokenize(String line, {AsmListingIndex? index}) =>
    tokenizeAsmLine(line, listing: true, index: index ?? AsmListingIndex.empty);

AsmHoverToken tokenOf(List<AsmHoverToken> tokens, String text) =>
    tokens.firstWhere(
      (token) => token.text == text,
      orElse: () => throw StateError(
        '没有找到字段 $text，实际得到 ${tokens.map((t) => t.text).toList()}',
      ),
    );

/// 把 span 树展平成 (文本, 样式)，用来断言样式没有因为注入悬停而改变。
List<(String, TextStyle?)> flatten(TextSpan span) {
  final out = <(String, TextStyle?)>[];
  void visit(TextSpan node) {
    final text = node.text;
    if (text != null && text.isNotEmpty) out.add((text, node.style));
    for (final child in node.children ?? const <InlineSpan>[]) {
      if (child is TextSpan) visit(child);
    }
  }

  visit(span);
  return out;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('列表前缀', () {
    test('前 40 列挂一条列表说明，机器码与地址不会被当成数值', () {
      final tokens = tokenize(_movR7);

      expect(tokens.first.start, 0);
      expect(tokens.first.end, 40);
      expect(tokens.first.data.kind, AsmTokenKind.listing);
      expect(tokens.first.data.title, contains('列表信息'));
      // 除前缀外，所有字段都落在正文里。
      expect(tokens.skip(1).every((token) => token.start >= 40), isTrue);
      expect(tokens.map((token) => token.text), isNot(contains('FE0548')));
      expect(tokens.map((token) => token.text), isNot(contains('7E')));
    });

    test('顶格书写的伪指令行没有前缀，正文从第 1 列开始', () {
      expect(listingPrefixEnd('\t.globl _main'), 0);
      final tokens = tokenizeAsmLine(
        '\t.globl _main',
        listing: true,
        index: AsmListingIndex.empty,
      );

      expect(
        tokens.any((token) => token.data.kind == AsmTokenKind.listing),
        isFalse,
      );
      expect(tokenOf(tokens, '.globl').start, 1);
      expect(tokenOf(tokens, '_main').data.title, '全局符号');
    });

    test('C 源码锚点整行是注释，只保留前缀说明', () {
      final tokens = tokenize(_cAnchor);

      expect(tokens, hasLength(1));
      expect(tokens.single.data.kind, AsmTokenKind.listing);
    });
  });

  group('指令与寄存器', () {
    test('助记符、寄存器、立即数各自成字段', () {
      final tokens = tokenize(_movR7);

      final mov = tokenOf(tokens, 'mov');
      expect(mov.data.kind, AsmTokenKind.mnemonic);
      expect(mov.data.title, startsWith('MOV'));
      expect(mov.start, 41);
      expect(mov.end, 44);
      expect(_movR7.substring(mov.start, mov.end), 'mov');

      expect(tokenOf(tokens, 'r7').data.kind, AsmTokenKind.register);
      final immediate = tokenOf(tokens, '0x00');
      expect(immediate.data.kind, AsmTokenKind.number);
      expect(immediate.data.detail, contains('立即数'));
    });

    test('十六进制立即数给出十进制值', () {
      final tokens = tokenize(_movDptr);

      expect(tokenOf(tokens, 'dptr').data.title, startsWith('DPTR'));
      expect(tokenOf(tokens, '0x00c8').data.description, contains('200'));
    });

    test('MCS-251 的 16 / 32 位寄存器与新增助记符都能识别', () {
      expect(tokenOf(tokenize(_pushAr7), 'ar7').data.title, contains('AR7'));
      expect(
        tokenOf(tokenize(_movWr2), 'wr2').data.kind,
        AsmTokenKind.register,
      );
      expect(
        tokenOf(tokenize(_movDr28), 'dr28').data.kind,
        AsmTokenKind.register,
      );
      expect(tokenOf(tokenize(_movDr28), 'dpx').data.title, contains('DPX'));
      expect(
        tokenOf(tokenize(_movzWr8), 'movz').data.kind,
        AsmTokenKind.mnemonic,
      );
      expect(tokenOf(tokenize(_subWr), 'sub').data.kind, AsmTokenKind.mnemonic);
      expect(tokenOf(tokenize(_mulAb), 'ab').data.title, startsWith('AB'));
      expect(tokenOf(tokenize(_decSpx), 'spx').data.title, contains('SPX'));
      expect(tokenOf(tokenize(_decSpx), '2').data.description, contains('0x2'));
    });

    test('间接寻址记号与栈偏移都给出说明', () {
      final tokens = tokenize(_movWr2);

      expect(tokenOf(tokens, '@').data.kind, AsmTokenKind.notation);
      expect(tokenOf(tokens, 'spx').data.kind, AsmTokenKind.register);
      expect(tokenOf(tokens, '0x0004').data.description, contains('-4'));
    });

    test('movc 的 @a+dptr 拆成记号与寄存器', () {
      final tokens = tokenize(_movc);

      expect(tokenOf(tokens, 'movc').data.kind, AsmTokenKind.mnemonic);
      expect(tokens.where((token) => token.text == 'a'), hasLength(2));
      expect(tokenOf(tokens, 'dptr').data.kind, AsmTokenKind.register);
    });

    test('mov a,@dpx 与 setb _EA 覆盖间接寻址与 SFR 位', () {
      expect(tokenOf(tokenize(_movADpx), '@').data.kind, AsmTokenKind.notation);
      expect(tokenOf(tokenize(_movADpl), 'dpl').data.title, startsWith('DPL'));

      final tokens = tokenize(
        _setbEa,
        index: AsmListingIndex.parse(_sampleListing),
      );
      expect(tokenOf(tokens, 'setb').data.kind, AsmTokenKind.mnemonic);
    });
  });

  group('位、标号与符号表', () {
    test('acc.0 说明到具体哪一位', () {
      final tokens = tokenize(_jbAccBit);
      final bit = tokenOf(tokens, 'acc.0');

      expect(bit.data.kind, AsmTokenKind.bit);
      expect(bit.data.title, contains('第 0 位'));
      expect(bit.data.title, contains('ACC'));
    });

    test('局部标号说明来源，并能报出定义位置', () {
      final index = AsmListingIndex.parse(_sampleListing);
      final reference = tokenOf(tokenize(_jnz, index: index), '00122\$');

      expect(reference.data.kind, AsmTokenKind.label);
      expect(reference.data.title, '局部标号');
      expect(reference.data.detail, contains('第 12 行'));
      expect(reference.data.detail, contains('0xFE055B'));

      final definition = tokenOf(tokenize(_label104, index: index), '00104\$:');
      expect(definition.data.title, '局部标号');
    });

    test('列表符号表区分 SFR 字节地址与位地址', () {
      final index = AsmListingIndex.parse(_sampleListing);

      expect(index['_P0']?.kind, AsmSymbolKind.sfr);
      expect(index['_P0']?.address, 0x80);
      expect(index['_TI']?.kind, AsmSymbolKind.sfrBit);
      expect(index['_TI']?.address, 0x99);
      expect(index['ar7']?.kind, AsmSymbolKind.registerAlias);
      expect(index['00104\$']?.line, isNotNull);
      expect(index['00104\$']?.address, 0xFE054B);

      final p0 = tokenOf(tokenize(_sfrP0, index: index), '_P0');
      expect(p0.data.kind, AsmTokenKind.sfr);
      expect(p0.data.title, startsWith('P0'));
      expect(p0.data.detail, contains('0x80'));

      final ti = tokenOf(tokenize(_bitTi, index: index), '_TI');
      expect(ti.data.kind, AsmTokenKind.bit);
      expect(ti.data.title, startsWith('TI'));
      expect(ti.data.detail, contains('位地址 0x99'));

      expect(
        tokenOf(tokenize(_aliasAr7, index: index), 'ar7').data.kind,
        AsmTokenKind.register,
      );
    });

    test('没有符号表时，下划线名字退化成外部符号', () {
      final token = tokenOf(tokenize(_ecall), '_NRF24L01_Init');

      expect(token.data.kind, AsmTokenKind.symbol);
      expect(token.data.title, '外部符号');
    });

    test('函数标号带出地址与列表行号', () {
      final index = AsmListingIndex.parse(_sampleListing);
      final token = tokenOf(
        tokenize(
          '      FE0548                       1195 _remoteControlInitWithTimeout:',
          index: index,
        ),
        '_remoteControlInitWithTimeout:',
      );

      expect(token.data.kind, AsmTokenKind.label);
      expect(token.data.detail, contains('0xFE0548'));
    });
  });

  group('伪指令', () {
    test('.area 的段名与属性分别说明', () {
      final tokens = tokenize(_area);

      expect(tokenOf(tokens, '.area').data.kind, AsmTokenKind.directive);
      expect(tokenOf(tokens, 'RSEG').data.kind, AsmTokenKind.segment);
      expect(tokenOf(tokens, 'ABS').data.title, contains('绝对地址'));
      expect(tokenOf(tokens, 'DATA').data.title, contains('直接寻址'));
    });

    test('.optsdcc 的选项整段挂一条说明', () {
      final tokens = tokenize(_optsdcc);

      expect(tokenOf(tokens, '.optsdcc').data.kind, AsmTokenKind.directive);
      final options = tokens.last;
      expect(options.data.title, 'SDCC 编译选项');
      expect(options.text, '-mmcs251 --model-large');
    });

    test('.globl 的符号按全局符号解释', () {
      final tokens = tokenize(_globlMain);

      expect(tokenOf(tokens, '.globl').data.kind, AsmTokenKind.directive);
      expect(tokenOf(tokens, '_main').data.title, '全局符号');
    });
  });

  group('数值换算', () {
    test('十六进制给十进制，十进制给十六进制', () {
      expect(asmNumberInfo('0x00c8').description, '0x00C8 = 200');
      expect(asmNumberInfo('0xffff').description, '0xFFFF = 65535');
      expect(asmNumberInfo('20').description, '20 = 0x14');
      expect(
        asmNumberInfo('0x0004', negative: true).description,
        '-0x0004 = -4',
      );
      expect(asmNumberInfo('0x02', immediate: true).detail, contains('#'));
      expect(asmNumberInfo('20').detail, isNull);
    });
  });

  group('span 注入', () {
    const baseStyle = TextStyle(color: Color(0xff123456), fontSize: 13);
    const prefixStyle = TextStyle(color: Color(0xff00ff00));
    const keywordStyle = TextStyle(color: Color(0xffff0000));

    TextSpan highlighted(String line) => TextSpan(
      style: baseStyle,
      children: [
        TextSpan(text: line.substring(0, 41), style: prefixStyle),
        TextSpan(text: 'mov', style: keywordStyle),
        TextSpan(text: line.substring(44)),
      ],
    );

    test('字段成为可悬停叶子，其余保持普通 span，样式不变', () {
      const line = _movR7;
      final tokens = tokenize(line);
      final result = buildAsmHoverSpan(
        highlighted: highlighted(line),
        lineText: line,
        tokens: tokens,
        onEnter: (_, _) {},
        onExit: (_) {},
      );

      expect(result.style, baseStyle);
      final leaves = flatten(result);
      expect(leaves.map((leaf) => leaf.$1).join(), line);

      final mov = leaves.firstWhere((leaf) => leaf.$1 == 'mov');
      expect(mov.$2, keywordStyle);
      // 前缀被切成「可悬停的前 40 列」+「第 41 列的制表符」两片，样式都保留。
      expect(leaves.first.$1, line.substring(0, 40));
      expect(leaves.first.$2, prefixStyle);
      expect(leaves[1].$1, '\t');
      expect(leaves[1].$2, prefixStyle);

      void visit(TextSpan span) {
        if (span.text == 'mov') {
          expect(span, isA<MouseTrackerAnnotationTextSpan>());
          expect(span.mouseCursor, SystemMouseCursors.help);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          if (child is TextSpan) visit(child);
        }
      }

      visit(result);
    });

    test('悬停回调带出字段本身与矩形', () {
      const line = _movR7;
      final tokens = tokenize(line);
      AsmHoverToken? entered, exited;
      List<Rect>? rects;
      final result = buildAsmHoverSpan(
        highlighted: highlighted(line),
        lineText: line,
        tokens: tokens,
        onEnter: (token, boxes) {
          entered = token;
          rects = boxes;
        },
        onExit: (token) => exited = token,
      );

      final span = _leafWithText(result, 'mov');
      expect(span, isA<MouseTrackerAnnotationTextSpan>());

      final rect = const Rect.fromLTWH(10, 20, 30, 14);
      (span! as MouseTrackerAnnotationTextSpan).onEnterWithRect(
        PointerEnterEvent(
          position: const Offset(12, 22),
          kind: PointerDeviceKind.mouse,
        ),
        0,
        [rect],
      );
      expect(entered?.text, 'mov');
      expect(entered?.data.kind, AsmTokenKind.mnemonic);
      expect(rects, [rect]);

      (span as MouseTrackerAnnotationTextSpan).onExitWithRect(
        PointerExitEvent(
          position: const Offset(0, 0),
          kind: PointerDeviceKind.mouse,
        ),
        0,
        [rect],
      );
      expect(exited?.text, 'mov');
    });

    test('高亮结果与行文本长度不一致时不注入', () {
      const line = _movR7;
      final tokens = tokenize(line);
      final truncated = TextSpan(
        style: baseStyle,
        children: [TextSpan(text: line.substring(0, 20))],
      );
      final result = buildAsmHoverSpan(
        highlighted: truncated,
        lineText: line,
        tokens: tokens,
        onEnter: (_, _) {},
        onExit: (_) {},
      );

      expect(identical(result, truncated), isTrue);
    });

    test('没有字段时原样返回', () {
      const line = '                                      ';
      final highlighted = TextSpan(text: line);
      final result = buildAsmHoverSpan(
        highlighted: highlighted,
        lineText: line,
        tokens: tokenize(line),
        onEnter: (_, _) {},
        onExit: (_) {},
      );

      expect(identical(result, highlighted), isTrue);
    });
  });

  group('AsmHoverAnnotator', () {
    test('未启用时原样返回高亮结果', () {
      final annotator = AsmHoverAnnotator();
      final span = TextSpan(text: 'mov');

      expect(
        identical(
          annotator.buildSpan(codeLine: const CodeLine('mov'), textSpan: span),
          span,
        ),
        isTrue,
      );
    });

    test('启用后注入悬停字段，并按行缓存', () {
      final annotator = AsmHoverAnnotator()
        ..onEnter = (_, _) {}
        ..onExit = (_) {}
        ..update(_sampleListing, enabled: true, listing: true);

      final result = annotator.buildSpan(
        codeLine: const CodeLine(_movDptr),
        textSpan: TextSpan(text: _movDptr),
      );
      expect(
        _leafWithText(result, '0x00c8'),
        isA<MouseTrackerAnnotationTextSpan>(),
      );

      // 同一行第二次拿到的是缓存结果。
      expect(annotator.tokensOf(_movDptr), same(annotator.tokensOf(_movDptr)));
    });

    test('C 代码不注入悬停字段', () {
      final annotator = AsmHoverAnnotator()
        ..onEnter = (_, _) {}
        ..onExit = (_) {}
        ..update('void main(void) { mov(); }', enabled: false, listing: false);
      final span = TextSpan(text: 'void main(void) { mov(); }');

      expect(
        identical(
          annotator.buildSpan(codeLine: CodeLine(span.text!), textSpan: span),
          span,
        ),
        isTrue,
      );
    });
  });

  group('re_editor 集成', () {
    /// 测试环境用等宽方框字体，一个字符正好 [fontSize] 宽，
    /// 因此可以按列号算出指针要落在哪里。
    const fontSize = 13.0;

    testWidgets('真实鼠标悬停会触发进入与离开回调', (tester) async {
      const line = _movR7;
      final annotator = AsmHoverAnnotator()
        ..update(line, enabled: true, listing: true);
      final entered = <String>[];
      final exited = <String>[];
      annotator
        ..onEnter = (token, rects) {
          expect(rects, isNotEmpty);
          entered.add(token.text.trim());
        }
        ..onExit = (token) => exited.add(token.text.trim());

      final controller = CodeLineEditingController(
        codeLines: line.codeLines,
        spanBuilder: ({
          required BuildContext context,
          required int index,
          required CodeLine codeLine,
          required TextSpan textSpan,
          required TextStyle style,
        }) => annotator.buildSpan(codeLine: codeLine, textSpan: textSpan),
      );
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 120,
              child: CodeEditor(
                controller: controller,
                padding: EdgeInsets.zero,
                style: CodeEditorStyle(fontSize: fontSize, fontHeight: 1.45),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      // 起点放在编辑器外，免得刚加上指针就先命中第一行。
      await gesture.addPointer(location: const Offset(4, 200));
      addTearDown(gesture.removePointer);
      await tester.pump();
      final origin = tester.getTopLeft(find.byType(CodeEditor));
      Offset at(int column) =>
          origin + Offset(column * fontSize + 2, fontSize / 2);

      // `mov` 从第 41 列开始：前 40 列是列表信息，第 41 列是制表符。
      await gesture.moveTo(at(41));
      await tester.pump();
      expect(entered, ['mov']);

      // 移到同一行的寄存器：先离开助记符，再进入寄存器。
      await gesture.moveTo(at(45));
      await tester.pump();
      expect(exited, ['mov']);
      expect(entered, ['mov', 'r7']);

      // 移到机器码列：前缀整体是一条列表说明，机器码字节本身不单独成字段。
      await gesture.moveTo(at(10));
      await tester.pump();
      expect(entered, ['mov', 'r7', line.substring(0, 40).trim()]);

      // 移出编辑器后收起。
      await gesture.moveTo(const Offset(4, 200));
      await tester.pump();
      expect(exited, hasLength(3));
    });
  });
}

TextSpan? _leafWithText(TextSpan span, String text) {
  if (span.text == text && (span.children == null || span.children!.isEmpty)) {
    return span;
  }
  for (final child in span.children ?? const <InlineSpan>[]) {
    if (child is! TextSpan) continue;
    final found = _leafWithText(child, text);
    if (found != null) return found;
  }
  return null;
}

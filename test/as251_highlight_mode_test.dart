import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/as251_highlight_mode.dart';
import 'package:re_highlight/re_highlight.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final highlight = Highlight()..registerLanguage('as251', langAs251);
  String highlightToHtml(String code) =>
      highlight.highlight(code: code, language: 'as251').toHtml();

  test('助记符、伪指令、寄存器、数字、注释按 scope 着色', () {
    final html = highlightToHtml('''
	.area	HOME    (CODE)
	.globl	_main
	.db	0xE8, 0x03	; 音符 0~3
_Music_Wait:
	ecall	_Ms_Delay		; 等待指定毫秒
	mov	dpl, #0xff
	push	acc
	dec	spx, #4
	sjmp	.
''');

    expect(html, contains('<span class="hljs-meta">.area</span>'));
    expect(html, contains('<span class="hljs-built_in">HOME</span>'));
    expect(html, contains('<span class="hljs-built_in">CODE</span>'));
    expect(html, contains('<span class="hljs-meta">.globl</span>'));
    expect(html, contains('<span class="hljs-meta">.db</span>'));
    expect(html, contains('<span class="hljs-number">0xE8</span>'));
    expect(html, contains('<span class="hljs-number">0x03</span>'));
    expect(html, contains('<span class="hljs-symbol">_Music_Wait:</span>'));
    expect(html, contains('<span class="hljs-keyword">ecall</span>'));
    expect(html, contains('<span class="hljs-comment">; 等待指定毫秒</span>'));
    expect(html, contains('<span class="hljs-keyword">mov</span>'));
    expect(html, contains('<span class="hljs-built_in">dpl</span>'));
    expect(html, contains('<span class="hljs-number">0xff</span>'));
    expect(html, contains('<span class="hljs-keyword">push</span>'));
    expect(html, contains('<span class="hljs-built_in">acc</span>'));
    expect(html, contains('<span class="hljs-keyword">dec</span>'));
    expect(html, contains('<span class="hljs-built_in">spx</span>'));
    expect(html, contains('<span class="hljs-number">4</span>'));
    expect(html, contains('<span class="hljs-keyword">sjmp</span>'));
    expect(html, contains('<span class="hljs-symbol">.</span>'));

    // SDCC 的下划线前缀符号不是关键字，保持默认颜色。
    expect(html, contains('_main'));
    expect(html, isNot(contains('hljs-keyword">_main')));
    expect(html, isNot(contains('hljs-built_in">_main')));
    expect(html, contains('_Ms_Delay'));
    expect(html, isNot(contains('hljs-keyword">_Ms_Delay')));
  });

  test('顶格符号定义行按 title 着色，标签不被误判', () {
    final html = highlightToHtml('''
ar0 = 0x00
PWMB_CH3_P33 = 0x61		; 音乐蜂鸣器所在 PWM 通道
__start__stack:
	.ds	1
''');

    expect(html, contains('<span class="hljs-title">ar0</span>'));
    expect(html, contains('<span class="hljs-title">PWMB_CH3_P33</span>'));
    expect(html, contains('<span class="hljs-number">0x00</span>'));
    expect(html, contains('<span class="hljs-number">0x61</span>'));
    expect(html, contains('<span class="hljs-comment">; 音乐蜂鸣器所在 PWM 通道</span>'));
    expect(html, contains('<span class="hljs-symbol">__start__stack:</span>'));
    expect(html, contains('<span class="hljs-meta">.ds</span>'));
  });

  test('整段真实生成汇编可完整解析', () {
    final html = highlightToHtml('''
__interrupt_vect:
	ljmp	__sdcc_mcs251_reset_trampoline
__sdcc_mcs251_reset_trampoline::
	ejmp	__sdcc_gsinit_startup	; 跳到运行库启动代码（清内存等）
	movc	a, @a+dptr
	addc	a, #(_musicFrequencies >> 8)
''');

    expect(html, contains('<span class="hljs-keyword">ljmp</span>'));
    expect(html, contains('<span class="hljs-symbol">__interrupt_vect:</span>'));
    expect(html, contains('<span class="hljs-symbol">__sdcc_mcs251_reset_trampoline::</span>'));
    expect(html, contains('<span class="hljs-keyword">ejmp</span>'));
    expect(html, contains('<span class="hljs-keyword">movc</span>'));
    expect(html, contains('<span class="hljs-built_in">dptr</span>'));
    expect(html, contains('<span class="hljs-keyword">addc</span>'));
    // 跳转目标符号保持默认颜色。
    expect(html, contains('__sdcc_gsinit_startup'));
    expect(html, isNot(contains('hljs-keyword">__sdcc_gsinit_startup')));
  });

  group('列表文件（main.rst）', () {
    final listing = Highlight()..registerLanguage('rst', langAs251Listing);
    String listingToHtml(String code) =>
        listing.highlight(code: code, language: 'rst').toHtml();

    // 前 40 列是地址 + 机器码 + [周期] + 行号，正文从第 41 列开始。
    const code = '''
                                      1 ;--------------------------------------------------------
                                      5 \t.module main
      FE008C 7E 71 82         [12]  158 \tmov\tr7, dpl
                                    200 ;\tC:\\\\tmp\\\\main.c:66: PWM_SET_Frequency(BUZZER_CH, frequency, BUZZER_DUTY_ON);
      FF0007 9A FE 08 5F      [12]  131 \tecall\t_main
''';

    test('机器码与周期列被弱化，不再当成数字着色', () {
      final html = listingToHtml(code);

      // 前缀列整段吃成 comment：地址、字节、[12]、行号都不再是数字。
      expect(html, contains('hljs-comment">                                      1'));
      expect(html, isNot(contains('hljs-number">12')));
      expect(html, isNot(contains('hljs-number">158')));
      expect(html, isNot(contains('hljs-number">131')));
      expect(html, isNot(contains('hljs-number">7E')));
      expect(html, isNot(contains('hljs-number">0x')));
    });

    test('正文仍按 as251 着色，C 锚点整行是注释', () {
      final html = listingToHtml(code);

      expect(html, contains('<span class="hljs-keyword">mov</span>'));
      expect(html, contains('<span class="hljs-built_in">r7</span>'));
      expect(html, contains('<span class="hljs-built_in">dpl</span>'));
      expect(html, contains('<span class="hljs-meta">.module</span>'));
      expect(html, contains('<span class="hljs-keyword">ecall</span>'));
      expect(html, contains('_main'));
      // C 锚点行：前 40 列弱化，`;` 之后整行是注释。
      expect(html, contains('hljs-comment">;'));
      expect(html, contains('main.c:66: PWM_SET_Frequency'));
    });
  });
}

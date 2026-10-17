import 'package:re_highlight/re_highlight.dart';

/// SDCC as251（MCS-251 内核）汇编的语法高亮模式。
///
/// re_highlight 内置的汇编模式面向 AVR、X86 等方言，对本项目代码
/// 生成器产出的 as251 语法只能覆盖一部分指令与 asxxxx 伪指令，因此
/// 按生成器实际的指令集定制。scope 键与 atom-one 主题已有的样式
/// （keyword/built_in/meta/comment/number/symbol/title/string）一一
/// 对应，无需扩充主题。
///
/// [listing] 为真时用于链接器产出的列表文件（`main.rst`）：它的每行前面
/// 还有四列列表机信息——地址、机器码字节、指令周期 `[n]` 与 asm 行号，
/// 加起来固定占前 40 列，之后才是汇编正文（注释行则是第 41 列上的 `;`）。
/// 这四列用弱色（comment）整体吃掉，免得 6 位地址、`7E 71 82` 这些字节和
/// `[12]` 被当成数字或关键字着色，正文仍按下面的 as251 规则高亮。
Mode as251Mode({bool listing = false}) => Mode(
  refs: {},
  name: listing ? 'SDCC AS251 Assembly Listing' : 'SDCC AS251 Assembly',
  caseInsensitive: true,
  disableAutodetect: true,
  keywords: {
    r'$pattern': r'\.?[a-zA-Z]\w*',
    // 8051 全部助记符 + MCS-251 新增（ecall/ejmp/eret/trap/sla/sra/srl）。
    'keyword': 'acall add addc ajmp anl cjne clr cpl da dec div djnz '
        'ecall ejmp eret inc jb jbc jc jmp jnb jnc jnz jz lcall ljmp mov '
        'movc movx mul nop orl pop push ret reti rl rlc rr rrc setb sjmp '
        'sla sra srl subb swap trap xch xchd xrl',
    // 寄存器（含 ar0~ar7 直接地址别名）与 asxxxx 地址空间、段名。
    'built_in': 'a acc ap ar0 ar1 ar2 ar3 ar4 ar5 ar6 ar7 b bit bseg c '
        'code cseg data dph dpl dpx dpxh dpxl dr28 dr30 dptr gsfinal '
        'gsinit home idata iseg mds md0 md1 md2 pdata psw pseg r0 r1 r2 '
        'r3 r4 r5 r6 r7 sseg sp spx xdata xinit xseg',
    'meta': '.area .ascii .asciz .byte .db .ds .dsb .dsw .dw .else .end '
        '.endif .endm .equ .error .even .globl .if .ifdef .ifndef '
        '.include .list .macro .module .nolist .org .page .radix .sbttl '
        '.set .title',
  },
  contains: <Mode>[
    // 列表文件的前 40 列：地址 + 机器码 + [周期] + 行号（+ 行号后的空白）。
    if (listing)
      Mode(scope: 'comment', begin: r'^.{0,40}(?=\t|;|$)', relevance: 0),
    // 行尾注释，生成器产出大量中文注释。
    Mode(scope: 'comment', begin: ';', end: r'$', relevance: 0),
    // SDCC 约定标签顶格书写，`::` 表示跨模块导出的符号。
    Mode(scope: 'symbol', begin: r'^[A-Za-z_.$][A-Za-z0-9_.$]*::?'),
    // 顶格的符号定义：ar0 = 0x00、MUSIC_TONE_FREQ = 1000。
    Mode(scope: 'title', begin: r'^[A-Za-z_][A-Za-z0-9_.$]*(?=\s*=)'),
    // sjmp 的「原地循环」自引用操作数。
    Mode(scope: 'symbol', begin: r'\.(?=\s|$)'),
    C_NUMBER_MODE,
    QUOTE_STRING_MODE,
    APOS_STRING_MODE,
  ],
);

/// `-S --c-code-in-asm` 产出的汇编文本用这个模式。
final langAs251 = as251Mode();

/// 链接器产出的列表文件（`main.rst`）用这个模式。
final langAs251Listing = as251Mode(listing: true);

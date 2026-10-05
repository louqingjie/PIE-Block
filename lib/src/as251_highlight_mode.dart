import 'package:re_highlight/re_highlight.dart';

/// SDCC as251（MCS-251 内核）汇编的语法高亮模式。
///
/// re_highlight 内置的汇编模式面向 AVR、X86 等方言，对本项目代码
/// 生成器产出的 as251 语法只能覆盖一部分指令与 asxxxx 伪指令，因此
/// 按生成器实际的指令集定制。scope 键与 atom-one 主题已有的样式
/// （keyword/built_in/meta/comment/number/symbol/title/string）一一
/// 对应，无需扩充主题。
final langAs251 = Mode(
  refs: {},
  name: 'SDCC AS251 Assembly',
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

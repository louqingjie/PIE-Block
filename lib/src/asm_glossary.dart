/// SDCC AS251（MCS-251 内核）汇编术语的中文说明。
///
/// 这份词表同时服务两处：`as251_highlight_mode.dart` 的关键字列表，以及
/// 生成代码页汇编列表（`main.rst`）的悬停卡片。两边共用同一份数据，避免
/// 「能着色却查不到说明」或反之。
///
/// 指令族全集取自 `sdcc-c251/sdas/as251/tests/instruction-families.txt`
/// （65 族）与 `instruction-forms.tsv`（操作数形式与影响标志），寄存器名
/// 取自 `sdcc-c251/sdas/as251/mcs251adr.c`，SFR 与位地址取自
/// `stc32g_sdcc/include/STC32Gxx.h`。
library;

/// 悬停目标的类别，决定卡片右上角的类型标签。
enum AsmTokenKind {
  mnemonic,
  register,
  sfr,
  bit,
  segment,
  directive,
  number,
  label,
  notation,
  listing,
  symbol,
}

/// 一条悬停说明。[token] 由调用方按代码原文填入，这里只存与位置无关的内容。
class AsmHoverData {
  const AsmHoverData({
    required this.kind,
    required this.title,
    required this.description,
    this.detail,
  });

  final AsmTokenKind kind;

  /// 一行标题，形如「MOV · 数据传送」。
  final String title;

  /// 正文说明，1–3 句，正式书面语。
  final String description;

  /// 补充一行：语法形式、影响标志、地址等。
  final String? detail;

  /// 卡片右上角的类型标签。
  String get kindLabel => switch (kind) {
    AsmTokenKind.mnemonic => '指令',
    AsmTokenKind.register => '寄存器',
    AsmTokenKind.sfr => 'SFR',
    AsmTokenKind.bit => 'SFR 位',
    AsmTokenKind.segment => '段',
    AsmTokenKind.directive => '伪指令',
    AsmTokenKind.number => '常数',
    AsmTokenKind.label => '标号',
    AsmTokenKind.notation => '记号',
    AsmTokenKind.listing => '列表',
    AsmTokenKind.symbol => '符号',
  };

  AsmHoverData withDetail(String? detail) => AsmHoverData(
    kind: kind,
    title: title,
    description: description,
    detail: detail,
  );
}

AsmHoverData _mnemonic(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.mnemonic,
      title: title,
      description: description,
      detail: detail,
    );

/// 65 个 MCS-251 指令族，外加 `call` / `pushw` 两个汇编器书写别名。
///
/// 键一律小写，查表时忽略大小写（列表里的助记符是小写）。
final Map<String, AsmHoverData> asmMnemonics = {
  // 算术与比较
  'add': _mnemonic(
    'ADD · 加法',
    '把源操作数与目的操作数相加，结果写回目的操作数。',
    '语法 add 目的, 源；影响 CY、AC、OV、N、Z。AC 只在 8 位运算时变化。',
  ),
  'addc': _mnemonic(
    'ADDC · 带进位加法',
    '目的 = 目的 + 源 + CY，多字节加法的高位部分用它把低位的进位接上。',
    '语法 addc 目的, 源；影响 CY、AC、OV、N、Z。',
  ),
  'sub': _mnemonic(
    'SUB · 减法',
    '把源操作数从目的操作数中减去，结果写回目的操作数。经典 8051 没有这条指令，MCS-251 才有。',
    '语法 sub 目的, 源；影响 CY（借位）、AC、OV、N、Z。支持 8/16/32 位寄存器。',
  ),
  'subb': _mnemonic(
    'SUBB · 带借位减法',
    '目的 = 目的 - 源 - CY，多字节减法的高位部分用它接上低位的借位。',
    '语法 subb 目的, 源；影响 CY、AC、OV、N、Z。',
  ),
  'cmp': _mnemonic(
    'CMP · 比较',
    '按「目的 - 源」设置标志位但不写回结果，通常紧跟 je / jne / jg 等条件跳转。MCS-251 新增。',
    '语法 cmp 目的, 源；影响 CY、AC、OV、N、Z。',
  ),
  'inc': _mnemonic(
    'INC · 加一',
    '把操作数的值加 1。',
    '语法 inc 操作数；不影响 CY。MCS-251 支持带步长形式，如 inc spx,#2。',
  ),
  'dec': _mnemonic(
    'DEC · 减一',
    '把操作数的值减 1。',
    '语法 dec 操作数；不影响 CY。MCS-251 支持带步长形式，如 dec spx,#2 一次释放两个栈字节。',
  ),
  'mul': _mnemonic(
    'MUL · 无符号乘法',
    '两个无符号数相乘。8051 写作 mul ab，乘积低 8 位在 A、高 8 位在 B；MCS-251 还支持 mul wr,wr 得到 32 位乘积。',
    'CY 清零；高半部分非零时 OV 置 1。',
  ),
  'div': _mnemonic(
    'DIV · 无符号除法',
    '8051 写作 div ab：A 除以 B，商写回 A、余数写回 B。除数为 0 时结果无定义。',
    'CY 清零；除数为 0 时 OV 置 1。',
  ),
  'da': _mnemonic(
    'DA · 十进制调整',
    '对 A 中刚做完的 BCD 加法结果做十进制修正，使每个半字节落回 0–9。',
    '语法 da a；影响 CY。',
  ),

  // 逻辑与位操作
  'anl': _mnemonic(
    'ANL · 按位与',
    '目的操作数与源操作数按位相与，结果写回目的操作数；对位操作数则是逻辑与。',
    '语法 anl 目的, 源；常用来清掉某几位，如 anl a,#0x0f 只保留低 4 位。',
  ),
  'orl': _mnemonic(
    'ORL · 按位或',
    '目的操作数与源操作数按位相或，结果写回目的操作数。',
    '语法 orl 目的, 源；常用来置起某几位。',
  ),
  'xrl': _mnemonic(
    'XRL · 按位异或',
    '目的操作数与源操作数按位异或，结果写回目的操作数。',
    '语法 xrl 目的, 源；与自身异或（xrl a,a）是最短的清零写法。',
  ),
  'clr': _mnemonic(
    'CLR · 清零',
    '把操作数清 0，可用于累加器 A、进位 CY 或某一位。',
    '语法 clr a / clr c / clr 位；不影响其它标志。',
  ),
  'cpl': _mnemonic(
    'CPL · 取反',
    '把操作数按位取反（求 1 的补数），可用于 A、CY 或某一位。',
    '语法 cpl a / cpl c / cpl 位。',
  ),
  'setb': _mnemonic(
    'SETB · 置位',
    '把进位 CY 或指定的位设为 1。',
    '语法 setb c / setb 位；常见用法是使能中断（setb _EA）或启动定时器（setb _TR0）。',
  ),

  // 移位、循环移位与半字节交换
  'rl': _mnemonic('RL · 循环左移', '把 A 的 8 位循环左移一位，最高位移入最低位，不经过 CY。'),
  'rlc': _mnemonic('RLC · 带进位循环左移', '把 CY 与 A 共 9 位循环左移一位，多字节左移用它串接进位。'),
  'rr': _mnemonic('RR · 循环右移', '把 A 的 8 位循环右移一位，最低位移入最高位，不经过 CY。'),
  'rrc': _mnemonic('RRC · 带进位循环右移', '把 CY 与 A 共 9 位循环右移一位；除以 2 的移位常用它。'),
  'sll': _mnemonic(
    'SLL · 逻辑左移',
    '把寄存器内容逻辑左移一位，空出的最低位补 0。MCS-251 新增。',
    '语法 sll Rm / sll WRj，操作数既是源也是目的；影响 CY、N、Z。',
  ),
  'sra': _mnemonic(
    'SRA · 算术右移',
    '把寄存器内容右移一位，最高位用原符号位填充，用于有符号数除以 2。MCS-251 新增。',
    '语法 sra Rm / sra WRj；影响 CY、N、Z。',
  ),
  'srl': _mnemonic(
    'SRL · 逻辑右移',
    '把寄存器内容右移一位，最高位补 0，用于无符号数除以 2。MCS-251 新增。',
    '语法 srl Rm / srl WRj；影响 CY、N、Z。',
  ),
  'swap': _mnemonic(
    'SWAP · 半字节交换',
    '把 A 的高 4 位与低 4 位互换，效果相当于乘或除 16。',
    '语法 swap a。',
  ),

  // 数据传送与栈
  'mov': _mnemonic(
    'MOV · 数据传送',
    '把源操作数的值复制到目的操作数，目的操作数原值被覆盖。',
    '语法 mov 目的, 源；不改变标志位。MCS-251 上还支持 16/32 位寄存器（WRj / DRk）与 24 位地址 @dpx。',
  ),
  'movc': _mnemonic(
    'MOVC · 查表传送',
    '以 A 为偏移从程序存储器（代码区）读取一字节送入 A，是查表的标准写法。',
    '语法 movc a,@a+dptr 或 movc a,@a+pc；代码区只读。',
  ),
  'movh': _mnemonic(
    'MOVH · 高半部分传送',
    '把 16 位立即数写入 32 位寄存器的高 16 位，低 16 位保持不变。MCS-251 新增。',
    '语法 movh DRk(hi),#data16。',
  ),
  'movs': _mnemonic(
    'MOVS · 符号扩展传送',
    '把 8 位寄存器按有符号数扩展成 16 位写入 WRj，负数的高位补 1。MCS-251 新增。',
    '语法 movs WRj,Rm；影响 N、Z。',
  ),
  'movx': _mnemonic(
    'MOVX · 外部数据传送',
    '在 A 与外部数据存储器之间传送一字节，地址由 @Ri 或 DPTR 给出。',
    '语法 movx a,@dptr 等；MCS-251 上更常用 mov …,@dpx 直接访问 24 位平坦地址，因此列表里很少见到 movx。',
  ),
  'movz': _mnemonic(
    'MOVZ · 零扩展传送',
    '把 8 位寄存器零扩展成 16 位写入 WRj，高位补 0，用于无符号数升位。MCS-251 新增。',
    '语法 movz WRj,Rm；影响 N、Z。',
  ),
  'xch': _mnemonic(
    'XCH · 交换',
    '交换 A 与源操作数的内容。',
    '语法 xch a,Rn / xch a,dir8 / xch a,@Ri。',
  ),
  'xchd': _mnemonic(
    'XCHD · 低半字节交换',
    '交换 A 的低 4 位与 @Ri 所指单元的低 4 位，高 4 位不变。',
    '语法 xchd a,@Ri。',
  ),
  'push': _mnemonic(
    'PUSH · 压栈',
    '把操作数压入硬件栈：栈指针先加，再写入数据。',
    '语法 push 操作数。8051 只能压直接地址（push acc、push ar7）；MCS-251 还支持寄存器、16/32 位寄存器与立即数。',
  ),
  'pop': _mnemonic(
    'POP · 出栈',
    '从硬件栈弹出一个值写入操作数：先读数据，栈指针再减。',
    '语法 pop 操作数；MCS-251 支持 8/16/32 位目的。必须与 push 的宽度配对，否则栈会错位。',
  ),

  // 条件控制流
  'cjne': _mnemonic(
    'CJNE · 比较不等则跳转',
    '比较两个操作数，不相等时跳到相对地址，相等则顺序执行。',
    '语法 cjne 目的, 源, 相对偏移；源大于目的时 CY 置 1，因此一条指令同时判相等与大小。',
  ),
  'djnz': _mnemonic(
    'DJNZ · 减一非零则跳转',
    '把操作数减 1，结果不为 0 时跳转，是循环计数的标准写法。',
    '语法 djnz Rn, 相对偏移 / djnz dir8, 相对偏移。',
  ),
  'jb': _mnemonic(
    'JB · 位为 1 跳转',
    '指定的位为 1 时跳转到相对地址。',
    '语法 jb 位, 相对偏移；位可以是 acc.n、可位寻址的 SFR 位或内部 RAM 位。',
  ),
  'jbc': _mnemonic(
    'JBC · 位为 1 跳转并清零',
    '指定的位为 1 时跳转，并把该位清 0，适合只处理一次的事件标志。',
    '语法 jbc 位, 相对偏移。',
  ),
  'jnb': _mnemonic(
    'JNB · 位为 0 跳转',
    '指定的位为 0 时跳转到相对地址；轮询等待某位置起常用它。',
    '语法 jnb 位, 相对偏移。',
  ),
  'jc': _mnemonic(
    'JC · 进位为 1 跳转',
    'CY = 1 时跳转，通常跟在加法或比较之后判断进位与借位。',
    '语法 jc 相对偏移。',
  ),
  'jnc': _mnemonic('JNC · 进位为 0 跳转', 'CY = 0 时跳转。', '语法 jnc 相对偏移。'),
  'jz': _mnemonic(
    'JZ · 为零跳转',
    '结果为零时跳转：8051 看 A 是否为 0，MCS-251 看 Z 标志。',
    '语法 jz 相对偏移。',
  ),
  'jnz': _mnemonic(
    'JNZ · 非零跳转',
    '结果非零时跳转；SDCC 用它实现 C 的 if 判断与函数返回值分支。',
    '语法 jnz 相对偏移。',
  ),
  'je': _mnemonic('JE · 相等跳转', 'Z = 1 时跳转，通常紧跟 cmp。MCS-251 新增。', '语法 je 相对偏移。'),
  'jne': _mnemonic(
    'JNE · 不等跳转',
    'Z = 0 时跳转，通常紧跟 cmp。MCS-251 新增。',
    '语法 jne 相对偏移。',
  ),
  'jg': _mnemonic(
    'JG · 无符号大于跳转',
    'CY = 0 且 Z = 0 时跳转，即按无符号比较「目的 > 源」。MCS-251 新增。',
    '语法 jg 相对偏移；先执行 cmp 设置标志。',
  ),
  'jle': _mnemonic(
    'JLE · 无符号小于等于跳转',
    'CY = 1 或 Z = 1 时跳转，即按无符号比较「目的 <= 源」。MCS-251 新增。',
    '语法 jle 相对偏移。',
  ),
  'jsg': _mnemonic(
    'JSG · 有符号大于跳转',
    'Z = 0 且 N = OV 时跳转，即按有符号比较「目的 > 源」。MCS-251 新增。',
    '语法 jsg 相对偏移。',
  ),
  'jsge': _mnemonic(
    'JSGE · 有符号大于等于跳转',
    'N = OV 时跳转，即按有符号比较「目的 >= 源」。MCS-251 新增。',
    '语法 jsge 相对偏移。',
  ),
  'jsl': _mnemonic(
    'JSL · 有符号小于跳转',
    'N ≠ OV 时跳转，即按有符号比较「目的 < 源」。MCS-251 新增。',
    '语法 jsl 相对偏移。',
  ),
  'jsle': _mnemonic(
    'JSLE · 有符号小于等于跳转',
    'Z = 1 或 N ≠ OV 时跳转，即按有符号比较「目的 <= 源」。MCS-251 新增。',
    '语法 jsle 相对偏移。',
  ),

  // 跳转、调用与返回
  'acall': _mnemonic(
    'ACALL · 绝对调用',
    '调用同一 2KB 页内的子程序：返回地址压栈后跳转，目标地址只编码 11 位，因此指令更短。',
    '语法 acall 标号；目标必须与下一条指令同页。',
  ),
  'ajmp': _mnemonic(
    'AJMP · 绝对跳转',
    '无条件跳转到同一 2KB 页内的地址，目标地址只编码 11 位。',
    '语法 ajmp 标号。',
  ),
  'lcall': _mnemonic(
    'LCALL · 长调用',
    '调用 64KB 地址空间内任意子程序，压入 16 位返回地址。',
    '语法 lcall 标号。',
  ),
  'ljmp': _mnemonic(
    'LJMP · 长跳转',
    '无条件跳转到 16 位地址，不压栈。复位向量处常用它跳向启动代码。',
    '语法 ljmp 标号。',
  ),
  'ecall': _mnemonic(
    'ECALL · 扩展调用',
    '调用 24 位代码空间内的子程序并压入 24 位返回地址；SDCC 生成的函数调用都是它。MCS-251 新增。',
    '语法 ecall 标号，或 ecall @DRk 做间接调用（目标地址先零扩展装入 DR28）。',
  ),
  'ejmp': _mnemonic(
    'EJMP · 扩展跳转',
    '无条件跳转到 24 位代码空间内的地址，不压栈。MCS-251 新增。',
    '语法 ejmp 标号；SDCC 用它实现函数出口跳转与尾调用。',
  ),
  'jmp': _mnemonic(
    'JMP · 间接跳转',
    '跳转到 A + DPTR 指向的代码地址，是 switch 跳转表的执行方式。',
    '语法 jmp @a+dptr。',
  ),
  'sjmp': _mnemonic(
    'SJMP · 短跳转',
    '相对当前 PC 跳转 -128…+127 字节。',
    '语法 sjmp 相对偏移；写作 sjmp . 表示跳到自身，即原地死循环等待中断。',
  ),
  'ret': _mnemonic(
    'RET · 子程序返回',
    '从栈中弹出返回地址并跳回调用处，用于 8051 的 16 位调用。',
    'MCS-251 的 24 位返回由 eret 完成，因此列表里通常只见 eret 与 reti。',
  ),
  'reti': _mnemonic(
    'RETI · 中断返回',
    '中断服务程序的返回：除弹栈跳回外，还恢复中断优先级状态，允许同级中断再次被响应。',
    'STC32G 使用 4 字节中断帧，reti 恢复 PSW1 与 24 位 PC。',
  ),
  'eret': _mnemonic(
    'ERET · 扩展返回',
    '从 24 位返回地址恢复 PC，与 ecall 配对；SDCC 生成的普通函数返回都是它。MCS-251 新增。',
  ),
  'nop': _mnemonic('NOP · 空操作', '只消耗一个指令周期，不改变任何寄存器与标志；用于短延时或占位对齐。'),
  'esc': _mnemonic(
    'ESC · 转义前缀',
    '指令转义前缀，用来在 MCS-251 原生编码与经典 MCS-51 编码（A5/ESC）之间切换。MCS-251 新增。',
    '由汇编器按目标编码模式插入，一般不出现在 C 编译产物中。',
  ),
  'trap': _mnemonic('TRAP · 陷阱', '触发处理器陷阱。在 STC32G 上按 NOP 处理。MCS-251 新增。'),

  // 汇编器别名
  'call': _mnemonic(
    'CALL · 调用（汇编器别名）',
    '书写别名，不是独立的机器指令：汇编器按目标地址范围自动选择 acall / lcall / ecall。',
  ),
  'pushw': _mnemonic(
    'PUSHW · 压入立即数（汇编器别名）',
    'push 的立即数写法别名，把 16 位立即数压栈；压寄存器仍写 push。',
  ),
};

AsmHoverData _register(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.register,
      title: title,
      description: description,
      detail: detail,
    );

/// CPU 寄存器与寄存器元组。`ar0`–`ar7` 是 R0–R7 的直接地址别名，
/// `wr*` / `dr*` 是 MCS-251 的 16 / 32 位寄存器元组。
final Map<String, AsmHoverData> asmRegisters = _buildRegisters();

Map<String, AsmHoverData> _buildRegisters() {
  final registers = <String, AsmHoverData>{
    'a': _register(
      'A · 累加器',
      '8 位累加器，绝大多数算术、逻辑与传送指令的默认操作数。',
      '写 a 用寄存器寻址，写 acc 用直接地址 0xE0；push / pop 只能用 acc。',
    ),
    'acc': _register(
      'ACC · 累加器（直接地址）',
      '累加器 A 的直接地址写法，地址 0xE0，内容与 a 完全相同。',
      '需要把 A 当作内存单元访问时用它，例如 push acc、xrl acc,#0xff。',
    ),
    'b': _register(
      'B · B 寄存器',
      '8 位通用寄存器，直接地址 0xF0。',
      'mul ab 与 div ab 用它存放乘数、商或余数。',
    ),
    'ab': _register(
      'AB · 累加器与 B 的组合',
      '把 A（低 8 位）与 B（高 8 位）看作一个 16 位操作数。',
      '只出现在 mul ab 与 div ab 中。',
    ),
    'c': _register(
      'CY · 进位标志',
      'PSW 的第 7 位，既是算术运算的进位与借位，也是位操作指令的「位累加器」。',
      '可以直接 mov c,位 / setb c / clr c / anl c,位 操作。',
    ),
    'cy': _register(
      'CY · 进位标志',
      'c 的等价写法，指 PSW 的第 7 位。',
      '汇编器把 c 与 cy 视为同一个寄存器。',
    ),
    'pc': _register(
      'PC · 程序计数器',
      '指向下一条要执行的指令地址，不能直接读写。',
      'MCS-251 的 PC 是 24 位，可寻址 16MB 代码空间；movc a,@a+pc 以它为基址查表。',
    ),
    'dptr': _register(
      'DPTR · 数据指针',
      '16 位数据指针，由 DPH（高 8 位）与 DPL（低 8 位）组成，用于查表与外部数据访问。',
      '在 MCS-251 上它与 DPXL 一起构成 24 位平坦指针 DPX。',
    ),
    'dpl': _register(
      'DPL · 数据指针低字节',
      'DPTR 的低 8 位，直接地址 0x82。',
      'SDCC 的调用约定用 DPL 返回字节值、用 DPL/DPH 返回 16 位值。',
    ),
    'dph': _register('DPH · 数据指针高字节', 'DPTR 的高 8 位，直接地址 0x83。'),
    'dpx': _register(
      'DPX · 24 位数据指针',
      'MCS-251 的平坦地址指针，由 DPL（位 7:0）、DPH（位 15:8）、DPXL（位 23:16）组成，可寻址 16MB。',
      '--model-large 下全局变量都在 XSEG，通过 mov …,@dpx 访问；它同时也是 32 位寄存器 DR56。',
    ),
    'dpxl': _register(
      'DPXL · 数据指针扩展字节',
      'DPX 的最高 8 位（位 23:16），直接地址 0x84。',
      '写入它就切换到另一个 64KB 页。',
    ),
    'sp': _register(
      'SP · 栈指针',
      '8051 的 8 位栈指针，直接地址 0x81，指向栈顶单元。',
      'MCS-251 的硬件栈由 16 位 SPX 寻址，SDCC 生成的代码通常操作 spx。',
    ),
    'spx': _register(
      'SPX · 扩展栈指针',
      'MCS-251 的 16 位硬件栈指针，栈向高地址增长；它同时也是 32 位寄存器 DR60。',
      '局部变量与可重入参数用 @spx+偏移 访问；dec spx,#n / inc spx,#n 一次分配或释放多个栈字节。',
    ),
    'sph': _register('SPH · 栈指针高字节', 'SPX 的高 8 位，直接地址 0x85。'),
    'psw': _register(
      'PSW · 程序状态字',
      '直接地址 0xD0，含 CY、AC、F0、RS1、RS0、OV、P 等标志，其中 RS1/RS0 选择当前寄存器组。',
      '中断服务程序常 push psw / pop psw 保存与恢复标志。',
    ),
    'psw1': _register(
      'PSW1 · 扩展程序状态字',
      'MCS-251 新增的状态字，直接地址 0xD1，保存 N（结果最高位）与 Z（结果为零）等标志。',
      'cmp、je/jne/jsg 这类有符号比较依赖它；STC32G 的 4 字节中断帧会连同 24 位 PC 一起保存与恢复 PSW1。',
    ),
    'dps': _register(
      'DPS · 数据指针选择',
      '选择当前使用哪一组数据指针（DPTR0 / DPTR1），直接地址 0xE3。',
      '双指针可在两个地址之间来回切换而不必反复重装 DPTR。',
    ),
    'dr56': _register(
      'DR56 · DPX 的 32 位别名',
      '32 位寄存器 DR56 与 24 位数据指针 DPX 是同一组物理寄存器。',
      '间接调用 ecall @dr28 之外，DPX 也可按 DR56 参与 32 位运算。',
    ),
    'dr60': _register(
      'DR60 · SPX 的 32 位别名',
      '32 位寄存器 DR60 与 16 位硬件栈指针 SPX 是同一组物理寄存器。',
      '函数返回时 DR60/SPX 必须与入口一致，否则栈会失衡。',
    ),
  };
  for (var i = 0; i <= 15; i++) {
    registers['r$i'] = _register(
      'R$i · 通用寄存器',
      '8 位通用工作寄存器。R0–R7 分成 4 组，由 PSW 的 RS1/RS0 选择当前使用哪一组；MCS-251 把编号扩展到 R15。',
      switch (i) {
        0 || 1 => 'R$i 还可作字节间接寻址指针（@r$i）；调用方必须假设 R0–R11 会被被调函数破坏。',
        _ =>
          i <= 11
              ? '调用方必须假设 R0–R11 会被被调函数破坏；SDCC 用它们传参与存放中间值。'
              : 'R12–R15 由被调函数负责保存与恢复。',
      },
    );
  }
  for (var i = 0; i <= 7; i++) {
    registers['ar$i'] = _register(
      'AR$i · R$i 的直接地址别名',
      'R$i 在当前寄存器组中的直接地址符号，由 SDCC 在列表开头用 ar$i = 0x0$i 定义。',
      'push ar$i / pop ar$i 就是保存与恢复 R$i：8051 的 push、pop 只接受直接地址。',
    );
  }
  for (var i = 0; i <= 30; i += 2) {
    registers['wr$i'] = _register(
      'WR$i · 16 位寄存器',
      '由 R$i 与 R${i + 1} 拼成的 16 位寄存器（大端：R$i 是高字节），编号必须是偶数。',
      'MCS-251 新增；movz / movs / mul wr,wr / add wr,wr 等 16 位运算用它。WR16–WR30 属于调用者可破坏的范围。',
    );
  }
  for (var i = 0; i <= 28; i += 4) {
    registers['dr$i'] = _register(
      'DR$i · 32 位寄存器',
      '由 R$i…R${i + 3} 拼成的 32 位寄存器（大端：R$i 是最高字节），编号必须是 4 的倍数。',
      'MCS-251 新增；add dr,dr / sub dr,dr 做原生 32 位加减，ecall @dr28 用它做间接调用。',
    );
  }
  return registers;
}

AsmHoverData _segment(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.segment,
      title: title,
      description: description,
      detail: detail,
    );

/// 地址空间、asxxxx 段名与 `.area` 括号里的段属性。
final Map<String, AsmHoverData> asmSegments = {
  // 地址空间
  'code': _segment(
    'CODE · 代码区',
    '存放程序与常量表的只读区，MCS-251 上是 24 位平坦地址空间。',
    'movc 从代码区取数；常量表（如音乐频率表）也放这里。',
  ),
  'data': _segment(
    'DATA · 直接寻址内部数据区',
    '内部 RAM 的低 128 字节，可用直接地址访问，也是位寻址区所在。',
    '.area 括号里出现 DATA 表示该段落在这个空间。',
  ),
  'edata': _segment(
    'EDATA · 扩展直接寻址数据区',
    '可用直接地址访问的扩展片内 RAM（STC32G 的 XRAM 低端窗口）。',
  ),
  'idata': _segment(
    'IDATA · 间接寻址内部数据区',
    '内部 RAM 的 0x00–0xFF，只能用 @R0 / @R1 间接访问。',
  ),
  'xdata': _segment(
    'XDATA · 外部数据区',
    '外部数据存储器；MCS-251 上是 24 位平坦地址空间，用 DPX 访问。',
    '--model-large 把普通全局变量放在 XSEG，缺省基址 0x010000。',
  ),
  'bit': _segment('BIT · 位寻址区', '内部 RAM 的 0x20–0x2F 与可位寻址的 SFR，可按位读写。'),

  // 段名
  'home': _segment('HOME · 启动代码段', '复位后最先执行的启动代码所在段，负责初始化栈与全局变量后跳向 main。'),
  'gsinit': _segment('GSINIT · 全局初始化段', '存放全局变量与静态变量的初始化代码，启动时按序执行。'),
  'gsinit0': _segment(
    'GSINIT0 · 全局初始化段 0',
    '全局初始化代码的第一段；SDCC 按模块拆成 GSINIT0–GSINIT5 依次执行。',
  ),
  'gsinit1': _segment('GSINIT1 · 全局初始化段 1', '全局初始化代码分段之一，按序在 GSINIT0 之后执行。'),
  'gsinit2': _segment('GSINIT2 · 全局初始化段 2', '全局初始化代码分段之一，按序执行。'),
  'gsinit3': _segment('GSINIT3 · 全局初始化段 3', '全局初始化代码分段之一，按序执行。'),
  'gsinit4': _segment('GSINIT4 · 全局初始化段 4', '全局初始化代码分段之一，按序执行。'),
  'gsinit5': _segment('GSINIT5 · 全局初始化段 5', '全局初始化代码的最后一段，执行完跳到 HOME 继续启动流程。'),
  'gsfinal': _segment('GSFINAL · 全局初始化结束段', '全局初始化结束后的收尾代码段，通常为空或只放一条跳转。'),
  'cseg': _segment('CSEG · 代码段', '存放本模块指令的代码段。'),
  'cabs': _segment('CABS · 绝对代码段', '按绝对地址定位、不参与重定位的代码段，中断向量表就放这里。'),
  'const': _segment('CONST · 常量段', '只读常量数据段，位于代码区；字符串与查找表放这里。'),
  'xinit': _segment(
    'XINIT · 外部数据初值段',
    '存放 xdata 变量的初值映像，启动时由 GSINIT 代码搬到 XSEG。',
  ),
  'dseg': _segment(
    'DSEG · 直接寻址数据段',
    '内部 RAM 中可用直接地址访问的数据段，--model-small 的全局变量放这里。',
  ),
  'dabs': _segment('DABS · 绝对直接寻址段', '按绝对地址定位的内部数据段。'),
  'iseg': _segment('ISEG · 间接寻址数据段', '内部 RAM 中只能间接访问的数据段。'),
  'iabs': _segment('IABS · 绝对间接寻址段', '按绝对地址定位的间接寻址数据段。'),
  'xseg': _segment(
    'XSEG · 外部数据段',
    'xdata 数据段；--model-large 下全局变量与数组都放这里，通过 DPX 访问。',
  ),
  'xiseg': _segment('XISEG · 间接寻址外部数据段', '需要间接寻址的外部数据段。'),
  'xabs': _segment('XABS · 绝对外部数据段', '按绝对地址定位的外部数据段。'),
  'pseg': _segment('PSEG · 分页外部数据段', '按 256 字节分页访问的外部数据段（pdata），高位地址由页寄存器给出。'),
  'sseg': _segment('SSEG · 栈段', '硬件栈所在段；--stack-auto 下局部变量与可重入参数都在这里。'),
  'bseg': _segment('BSEG · 位段', '位变量段，按位分配。'),
  'rseg': _segment('RSEG · 绝对定位段', '用 .org 固定地址的段；SFR 符号表就定义在这一段里。'),
  'reg_bank_0': _segment(
    'REG_BANK_0 · 寄存器组 0 段',
    '保存 R0–R7 直接地址副本（ar0–ar7）的段，供 push / pop 使用。',
  ),
  'reg_bank_1': _segment('REG_BANK_1 · 寄存器组 1 段', '第二组 R0–R7 的直接地址副本段。'),
  'reg_bank_2': _segment('REG_BANK_2 · 寄存器组 2 段', '第三组 R0–R7 的直接地址副本段。'),
  'reg_bank_3': _segment('REG_BANK_3 · 寄存器组 3 段', '第四组 R0–R7 的直接地址副本段。'),
  'bit_bank': _segment(
    'BIT_BANK · 位寄存器段',
    '保存可位寻址单元（bits）的段，SDCC 用 b0–b7 等别名引用其中的位。',
  ),

  // .area 属性
  'rel': _segment('REL · 可重定位', '.area 属性：段的地址由链接器决定，可以在最终映像中移动。'),
  'ovr': _segment('OVR · 可覆盖', '.area 属性：允许与其它段共用同一块内存。SDCC 用它让非重入函数复用局部变量空间。'),
  'abs': _segment('ABS · 绝对地址', '.area 属性：段内地址固定，配合 .org 使用，不参与重定位。'),
  'pag': _segment('PAG · 分页', '.area 属性：段按 256 字节边界分页。'),
  'con': _segment('CON · 连接', '.area 属性：与同名段的内容首尾相连，合并成一段。'),
  'noload': _segment('NOLOAD · 不装入映像', '.area 属性：只占地址，不写入输出文件。'),
};

AsmHoverData _directive(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.directive,
      title: title,
      description: description,
      detail: detail,
    );

/// asxxxx（sdas251）伪指令。键带前导点，查表时统一小写。
final Map<String, AsmHoverData> asmDirectives = {
  '.area': _directive(
    '.AREA · 段声明',
    '定义或切换到一个段，括号里写段属性。',
    '如 .area XSEG (REL,OVR,XDATA) 表示可重定位、可覆盖的外部数据段。',
  ),
  '.globl': _directive('.GLOBL · 全局符号声明', '列出对其它模块可见的符号，链接器据此解析跨模块引用。'),
  '.module': _directive('.MODULE · 模块名声明', '声明当前模块名，只影响符号命名与调试信息，不产生机器码。'),
  '.optsdcc': _directive(
    '.OPTSDCC · 编译选项记录',
    '写下生成该模块的 SDCC 命令行选项，供调试与工具识别，不产生机器码。',
  ),
  '.db': _directive(
    '.DB · 定义字节数据',
    '按顺序把常量写入当前位置。',
    'SDCC 会在行尾追加十进制注释，如 .db #0x02 ; 2。',
  ),
  '.byte': _directive('.BYTE · 定义字节数据', '与 .db 等价，按顺序写入若干字节常量。'),
  '.dw': _directive('.DW · 定义字数据', '写入 16 位常量。MCS-251 的内存对象是大端，高字节在前。'),
  '.ds': _directive('.DS · 保留空间', '从当前位置保留 n 个字节，不写入初值。', '常用于声明缓冲区或栈空间。'),
  '.dsb': _directive('.DSB · 保留字节空间', '保留 n 个字节，与 .ds 等价。'),
  '.dsw': _directive('.DSW · 保留字空间', '保留 n 个 16 位字的空间。'),
  '.org': _directive(
    '.ORG · 设置位置计数器',
    '把后续代码或数据的地址固定为给定值。',
    '如 .org 0x0000 把中断向量表定位到代码区起始处。',
  ),
  '.ascii': _directive('.ASCII · 定义字符串', '把字符串的字符依次写入，不追加结束符。'),
  '.asciz': _directive('.ASCIZ · 定义以 0 结尾的字符串', '把字符串写入并在末尾追加一个 0 字节。'),
  '.equ': _directive('.EQU · 定义符号常量', '给符号赋一个固定值，等价于列表里的「名字 = 值」写法。'),
  '.set': _directive('.SET · 定义可重赋值符号', '给符号赋值，且允许后面再次赋值。'),
  '.even': _directive('.EVEN · 偶地址对齐', '把位置计数器推进到下一个偶地址。'),
  '.if': _directive('.IF · 条件汇编', '当表达式为真时才汇编其后的内容，与 .endif 配对。'),
  '.ifdef': _directive('.IFDEF · 若符号已定义', '符号已定义时才汇编其后的内容。'),
  '.ifndef': _directive('.IFNDEF · 若符号未定义', '符号未定义时才汇编其后的内容。'),
  '.else': _directive('.ELSE · 条件汇编另一分支', '前面条件不成立时汇编这一段。'),
  '.endif': _directive('.ENDIF · 条件汇编结束', '结束 .if / .ifdef / .ifndef 块。'),
  '.macro': _directive('.MACRO · 宏定义开始', '定义一段可复用的汇编宏，与 .endm 配对。'),
  '.endm': _directive('.ENDM · 宏定义结束', '结束 .macro 定义的宏体。'),
  '.include': _directive('.INCLUDE · 包含源文件', '把另一个汇编源文件的内容插入到当前位置。'),
  '.end': _directive('.END · 源文件结束', '标记汇编源文件结束，其后的内容不再汇编。'),
  '.list': _directive('.LIST · 开启列表输出', '恢复列表文件输出（此前被 .nolist 关闭）。'),
  '.nolist': _directive('.NOLIST · 关闭列表输出', '暂停列表文件输出，常用于跳过大段数据。'),
  '.page': _directive('.PAGE · 列表换页', '在列表文件中插入换页。'),
  '.radix': _directive('.RADIX · 设置默认进制', '设置未加前后缀的数字按哪种进制解释。'),
  '.title': _directive('.TITLE · 列表标题', '设置列表文件的标题行。'),
  '.sbttl': _directive('.SBTTL · 列表副标题', '设置列表文件的副标题。'),
  '.error': _directive('.ERROR · 报错', '汇编到此处时报出自定义错误信息并停止。'),
};

AsmHoverData _notation(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.notation,
      title: title,
      description: description,
      detail: detail,
    );

/// 寻址与书写记号。
final Map<String, AsmHoverData> asmNotations = {
  '@': _notation(
    '@ · 间接寻址',
    '操作数是一个地址寄存器，真正访问的是它的内容所指向的单元。',
    '如 mov a,@r0 读 R0 指向的字节，mov a,@dpx 读 DPX 指向的 24 位地址，mov wr2,@spx-0x0004 读栈上的局部变量。',
  ),
  '#': _notation(
    '# · 立即数前缀',
    '写在操作数前表示这是一个常量值，而不是地址或寄存器编号。',
    '如 mov dptr,#0x00c8 把常数 200 装入 DPTR；没有 # 则是把 0x00c8 当作地址。',
  ),
  '.': _notation('. · 当前地址', '表示当前位置计数器的值。', 'sjmp . 就是跳到自身，形成原地死循环，通常用于等待中断。'),
  '::': _notation(
    ':: · 全局符号定义',
    '带两个冒号的标签对其它模块可见，需要与 .globl 声明配合。',
    '一个冒号的标签只在本模块内有效。',
  ),
  '\$': _notation(
    '数字\$ · 局部标号',
    '以 \$ 结尾的数字标签由编译器生成，只在当前函数内有效。',
    'SDCC 用它给 if、for、while 生成分支目标，如 00122\$。',
  ),
};

AsmHoverData _sfr(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.sfr,
      title: title,
      description: description,
      detail: detail,
    );

AsmHoverData _bit(String title, String description, [String? detail]) =>
    AsmHoverData(
      kind: AsmTokenKind.bit,
      title: title,
      description: description,
      detail: detail,
    );

/// 常用特殊功能寄存器。键为大写、不带下划线；列表里的写法是 `_P0`。
/// 未收录的名字由 `main.rst` 自带的符号表兜底，仍能给出类别与地址。
final Map<String, AsmHoverData> asmSpecialFunctionRegisters = {
  'P0': _sfr(
    'P0 · 端口 0',
    '8 位准双向 I/O 口，可整字节读写，也可按位操作（P0.0–P0.7）。',
    '工作模式由 P0M0 与 P0M1 配置。',
  ),
  'P1': _sfr(
    'P1 · 端口 1',
    '8 位准双向 I/O 口，可整字节读写，也可按位操作。',
    '工作模式由 P1M0 与 P1M1 配置。',
  ),
  'P2': _sfr(
    'P2 · 端口 2',
    '8 位准双向 I/O 口，可整字节读写，也可按位操作。',
    '工作模式由 P2M0 与 P2M1 配置。',
  ),
  'P3': _sfr(
    'P3 · 端口 3',
    '8 位准双向 I/O 口，多数引脚复用了串口、定时器与外部中断。',
    '工作模式由 P3M0 与 P3M1 配置。',
  ),
  'P4': _sfr('P4 · 端口 4', '8 位准双向 I/O 口。', '工作模式由 P4M0 与 P4M1 配置。'),
  'P5': _sfr('P5 · 端口 5', '8 位准双向 I/O 口。', '工作模式由 P5M0 与 P5M1 配置。'),
  'P6': _sfr('P6 · 端口 6', '8 位准双向 I/O 口。', '工作模式由 P6M0 与 P6M1 配置。'),
  'P7': _sfr('P7 · 端口 7', '8 位准双向 I/O 口。', '工作模式由 P7M0 与 P7M1 配置。'),
  'SP': _sfr(
    'SP · 栈指针',
    '8051 的 8 位栈指针，地址 0x81。',
    'MCS-251 的硬件栈由 16 位 SPX 管理。',
  ),
  'SPH': _sfr('SPH · 栈指针高字节', 'SPX 的高 8 位，地址 0x85。'),
  'DPL': _sfr('DPL · 数据指针低字节', 'DPTR 的低 8 位，地址 0x82。'),
  'DPH': _sfr('DPH · 数据指针高字节', 'DPTR 的高 8 位，地址 0x83。'),
  'DPXL': _sfr(
    'DPXL · 数据指针扩展字节',
    'DPX 的最高 8 位（位 23:16），地址 0x84，决定访问哪一个 64KB 页。',
  ),
  'DPS': _sfr('DPS · 数据指针选择', '在两组数据指针 DPTR0 / DPTR1 之间切换，地址 0xE3。'),
  'PCON': _sfr('PCON · 电源控制', '含波特率加倍位 SMOD 与空闲、掉电模式控制位，地址 0x87。'),
  'TCON': _sfr(
    'TCON · 定时器与外部中断控制',
    '含 TF1 TR1 TF0 TR0 IE1 IT1 IE0 IT0，地址 0x88。',
    'TR0/TR1 启停定时器，TF0/TF1 是溢出标志，IT0/IT1 选择外部中断触发方式。',
  ),
  'TMOD': _sfr('TMOD · 定时器模式', '设置定时器 0 与 1 的工作模式、计数方式与门控，地址 0x89。'),
  'TL0': _sfr('TL0 · 定时器 0 低字节', '定时器 0 计数值的低 8 位，地址 0x8A。'),
  'TL1': _sfr('TL1 · 定时器 1 低字节', '定时器 1 计数值的低 8 位，地址 0x8B。'),
  'TH0': _sfr('TH0 · 定时器 0 高字节', '定时器 0 计数值的高 8 位，地址 0x8C。写入初值可设定溢出周期。'),
  'TH1': _sfr('TH1 · 定时器 1 高字节', '定时器 1 计数值的高 8 位，地址 0x8D。串口波特率通常由它决定。'),
  'SCON': _sfr(
    'SCON · 串行口控制',
    '含 SM0 SM1 SM2 REN TB8 RB8 TI RI，地址 0x98。',
    'SM0/SM1 选择工作方式，REN 允许接收，TI/RI 是收发完成标志。',
  ),
  'SBUF': _sfr(
    'SBUF · 串行口数据缓冲',
    '地址 0x99：写入即启动发送，读取即得到刚收到的字节。',
    '发送与接收共用一个地址，由读或写决定方向；TI/RI 需要软件清零。',
  ),
  'IE': _sfr('IE · 中断允许', '总开关 EA 与各中断源使能位，地址 0xA8。', 'EA 清零时所有中断都被屏蔽。'),
  'IP': _sfr('IP · 中断优先级', '设置各中断源的优先级，地址 0xB8。', '高优先级中断可以打断低优先级的服务程序。'),
  'PSW': _sfr(
    'PSW · 程序状态字',
    '含 CY AC F0 RS1 RS0 OV P，地址 0xD0。',
    'RS1/RS0 选择当前寄存器组。',
  ),
  'PSW1': _sfr(
    'PSW1 · 扩展程序状态字',
    'MCS-251 新增，保存 N 与 Z 等标志，地址 0xD1。',
    'cmp 之后的有符号比较跳转依赖它。',
  ),
  'ACC': _sfr(
    'ACC · 累加器',
    '累加器 A 的直接地址形式，地址 0xE0。',
    'push acc、xrl acc,#0xff 这类需要直接地址的场合用它。',
  ),
  'B': _sfr('B · B 寄存器', '8 位通用寄存器，地址 0xF0。', 'mul ab 与 div ab 用它存放乘数、商或余数。'),
  'AUXR': _sfr('AUXR · 辅助寄存器', '含串口波特率发生器、定时器时钟分频、EXTRAM 等控制位，地址 0x8E。'),
  'AUXR2': _sfr('AUXR2 · 辅助寄存器 2', '扩展的时钟与外设控制位，地址 0x97。'),
  'WDT_CONTR': _sfr('WDT_CONTR · 看门狗控制', '看门狗的使能、清零与分频设置。', '超时未喂狗会复位芯片。'),
  'S2CON': _sfr('S2CON · 串行口 2 控制', '第二路串口的控制与状态位。'),
  'S2BUF': _sfr('S2BUF · 串行口 2 数据缓冲', '第二路串口的收发缓冲，写入发送、读取接收。'),
  'SPCTL': _sfr('SPCTL · SPI 控制', 'SPI 的使能、主从、时钟极性与相位设置。'),
  'SPSTAT': _sfr('SPSTAT · SPI 状态', 'SPI 的传输完成与写冲突标志。'),
  'SPDAT': _sfr('SPDAT · SPI 数据', 'SPI 的收发数据缓冲。'),
  'ADC_CONTR': _sfr('ADC_CONTR · ADC 控制', 'ADC 的使能、启动、通道选择与电源控制。'),
  'ADC_RES': _sfr('ADC_RES · ADC 结果高字节', '转换结果的高 8 位，低位在 ADC_RESL。'),
};

/// 常用可位寻址的 SFR 位。键为大写、不带下划线；列表里的写法是 `_TI`。
final Map<String, AsmHoverData> asmSpecialFunctionBits = {
  'CY': _bit('CY · 进位标志', 'PSW.7：加法产生进位或减法需要借位时置 1，也是位操作指令的位累加器。'),
  'AC': _bit('AC · 辅助进位标志', 'PSW.6：低 4 位向高 4 位进位时置 1，主要供 BCD 调整（da）使用。'),
  'F0': _bit('F0 · 用户标志位', 'PSW.5：供程序自由使用的通用标志位。'),
  'RS1': _bit(
    'RS1 · 寄存器组选择高位',
    'PSW.4：与 RS0 一起选择当前使用的 R0–R7 组（00–11 对应第 0–3 组）。',
  ),
  'RS0': _bit('RS0 · 寄存器组选择低位', 'PSW.3：与 RS1 一起选择当前使用的 R0–R7 组。'),
  'OV': _bit('OV · 溢出标志', 'PSW.2：有符号运算结果超出表示范围时置 1；除法除数为 0 时也置 1。'),
  'P': _bit('P · 奇偶标志', 'PSW.0：A 中 1 的个数为奇数时置 1。'),
  'N': _bit('N · 符号标志', 'PSW1 中保存：运算结果的最高位为 1 时置 1，供有符号比较跳转使用。'),
  'Z': _bit('Z · 零标志', 'PSW1 中保存：运算结果为 0 时置 1，je / jne / jz / jnz 依据它跳转。'),
  'EA': _bit('EA · 总中断允许', 'IE.7：清零时屏蔽全部中断，置 1 才允许响应中断。'),
  'ES': _bit('ES · 串口中断允许', 'IE.4：允许串行口收发中断。'),
  'ET0': _bit('ET0 · 定时器 0 中断允许', 'IE.1：允许定时器 0 溢出中断。'),
  'ET1': _bit('ET1 · 定时器 1 中断允许', 'IE.3：允许定时器 1 溢出中断。'),
  'EX0': _bit('EX0 · 外部中断 0 允许', 'IE.0 之上的使能位：允许外部中断 0。'),
  'EX1': _bit('EX1 · 外部中断 1 允许', '允许外部中断 1。'),
  'TR0': _bit('TR0 · 定时器 0 启动', 'TCON.4：置 1 开始计数，清 0 停止。'),
  'TR1': _bit('TR1 · 定时器 1 启动', 'TCON.6：置 1 开始计数，清 0 停止。'),
  'TF0': _bit('TF0 · 定时器 0 溢出标志', 'TCON.5：计数溢出时由硬件置 1，进入中断服务后自动清零。'),
  'TF1': _bit('TF1 · 定时器 1 溢出标志', 'TCON.7：计数溢出时由硬件置 1，进入中断服务后自动清零。'),
  'IT0': _bit('IT0 · 外部中断 0 触发方式', 'TCON.0：0 为低电平触发，1 为下降沿触发。'),
  'IT1': _bit('IT1 · 外部中断 1 触发方式', 'TCON.2：0 为低电平触发，1 为下降沿触发。'),
  'IE0': _bit('IE0 · 外部中断 0 请求标志', 'TCON.1：检测到外部中断 0 请求时置 1。'),
  'IE1': _bit('IE1 · 外部中断 1 请求标志', 'TCON.3：检测到外部中断 1 请求时置 1。'),
  'RI': _bit('RI · 串口接收中断标志', 'SCON.0：收到一个字节时由硬件置 1，必须由软件清零，否则会反复进入中断。'),
  'TI': _bit(
    'TI · 串口发送中断标志',
    'SCON.1：一个字节发送完毕时由硬件置 1，必须由软件清零。',
    '查询式发送常写成 jnb _TI,\$ 等待发送完成。',
  ),
  'REN': _bit('REN · 串口接收允许', 'SCON.4：置 1 才允许串行口接收数据。'),
  'SM0': _bit('SM0 · 串口工作方式高位', 'SCON.7：与 SM1 一起选择工作方式（00–11）。'),
  'SM1': _bit('SM1 · 串口工作方式低位', 'SCON.6：与 SM0 一起选择工作方式；01 是最常用的 8 位 UART。'),
  'SM2': _bit('SM2 · 多机通信控制', 'SCON.5：多机通信时配合第 9 位数据筛选目标机。'),
  'TB8': _bit('TB8 · 发送的第 9 位数据', 'SCON.3：工作方式 1 与 3 下随发送数据一起送出的第 9 位。'),
  'RB8': _bit('RB8 · 接收的第 9 位数据', 'SCON.2：接收到的第 9 位数据或停止位。'),
  'SMOD': _bit('SMOD · 波特率加倍', 'PCON.7：置 1 时串口波特率翻倍。'),
};

/// 列表前 40 列的说明。
const AsmHoverData asmListingPrefix = AsmHoverData(
  kind: AsmTokenKind.listing,
  title: '列表信息 · SDCC 链接器生成',
  description: '依次为代码地址、该指令的机器码字节、指令周期 [n] 与列表行号；汇编正文从第 41 列开始。',
  detail: '机器码按传输顺序列出，多字节立即数与地址在大端次序下高字节在前。',
);

/// 查不到的标识符兜底说明。
const AsmHoverData asmUnknownSymbol = AsmHoverData(
  kind: AsmTokenKind.symbol,
  title: '符号',
  description: '编译器生成的函数、变量或标号名。下划线前缀来自 C 标识符的符号化规则。',
);

/// 助记符说明，忽略大小写；查不到返回 null。
AsmHoverData? asmMnemonicInfo(String mnemonic) =>
    asmMnemonics[mnemonic.toLowerCase()];

/// 寄存器说明，忽略大小写。
AsmHoverData? asmRegisterInfo(String name) => asmRegisters[name.toLowerCase()];

/// 地址空间、段名与段属性说明，忽略大小写。
AsmHoverData? asmSegmentInfo(String name) => asmSegments[name.toLowerCase()];

/// 伪指令说明，忽略大小写；[name] 需带前导点。
AsmHoverData? asmDirectiveInfo(String name) =>
    asmDirectives[name.toLowerCase()];

/// 寻址记号说明。
AsmHoverData? asmNotationInfo(String notation) => asmNotations[notation];

/// 特殊功能寄存器说明。接受 `_P0` 或 `P0` 两种写法。
AsmHoverData? asmSfrInfo(String name) {
  final bare = name.startsWith('_') ? name.substring(1) : name;
  return asmSpecialFunctionRegisters[bare.toUpperCase()];
}

/// 可位寻址的 SFR 位说明。接受 `_TI` 或 `TI` 两种写法。
AsmHoverData? asmBitInfo(String name) {
  final bare = name.startsWith('_') ? name.substring(1) : name;
  return asmSpecialFunctionBits[bare.toUpperCase()];
}

/// 数值常量说明：十六进制给出十进制值，十进制给出十六进制值。
///
/// [negative] 为真表示这个常量前面带负号（如 `@spx-0x0004`）；
/// [immediate] 为真表示它前面有 `#`，是立即数。
AsmHoverData asmNumberInfo(
  String text, {
  bool negative = false,
  bool immediate = false,
}) {
  final isHex =
      text.length > 2 && (text.startsWith('0x') || text.startsWith('0X'));
  final digits = isHex ? text.substring(2) : text;
  final value = int.tryParse(digits, radix: isHex ? 16 : 10);
  final sign = negative ? '-' : '';
  final immediateNote = immediate ? '前面的 # 表示这是立即数：常量本身，而不是地址。' : null;
  if (value == null) {
    return AsmHoverData(
      kind: AsmTokenKind.number,
      title: isHex ? '十六进制常数' : '十进制常数',
      description: '$sign$text',
      detail: immediateNote,
    );
  }
  if (isHex) {
    return AsmHoverData(
      kind: AsmTokenKind.number,
      title: '十六进制常数',
      description: '${sign}0x${digits.toUpperCase()} = $sign$value',
      detail: immediateNote,
    );
  }
  return AsmHoverData(
    kind: AsmTokenKind.number,
    title: '十进制常数',
    description:
        '$sign$value = ${sign}0x${value.toRadixString(16).toUpperCase()}',
    detail: immediateNote,
  );
}

/// 寄存器位操作数（如 `acc.0`）的说明。
AsmHoverData asmBitOperandInfo(
  String register,
  int bit,
  AsmHoverData? registerInfo,
) {
  final name = registerInfo?.title.split(' · ').first ?? register.toUpperCase();
  return AsmHoverData(
    kind: AsmTokenKind.bit,
    title: '$name 的第 $bit 位',
    description: '位寻址操作数：只读写 $name 的第 $bit 位，其余位不变。',
    detail: 'jb / jnb / setb / clr / cpl 都可以直接作用在这一位上。',
  );
}

/// 高亮模式与悬停共用的关键字串（小写、空格分隔）。
final String asmMnemonicKeywords = _sortedKeys(asmMnemonics);
final String asmRegisterKeywords = _sortedKeys(asmRegisters);
final String asmSegmentKeywords = _sortedKeys(asmSegments);
final String asmDirectiveKeywords = _sortedKeys(asmDirectives);

String _sortedKeys(Map<String, AsmHoverData> table) {
  final keys = table.keys.toList()..sort();
  return keys.join(' ');
}

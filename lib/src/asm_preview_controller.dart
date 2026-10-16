/// 汇编对照控制器：桌面版接内置 SDCC 子进程，Web 上是降级桩。
library;

export 'asm_preview_controller_native.dart'
    if (dart.library.js_interop) 'asm_preview_controller_web.dart';

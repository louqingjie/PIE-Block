/// 表达式编译检查控制器：桌面版接内置 SDCC，Web/Android 是降级桩。
library;

export 'expression_check_controller_native.dart'
    if (dart.library.js_interop) 'expression_check_controller_web.dart';

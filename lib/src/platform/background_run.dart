/// 把纯计算丢到后台线程。Web 上没有 Isolate，退化为当前线程直接执行。
library;

export 'background_run_stub.dart'
    if (dart.library.js_interop) 'background_run_web.dart';

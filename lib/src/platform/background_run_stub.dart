import 'dart:isolate';

/// 桌面 / 移动端：真正开一个 Isolate 跑，计算量大时不卡界面。
Future<T> runInBackground<T>(T Function() computation) =>
    Isolate.run(computation);

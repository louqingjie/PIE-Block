/// Web 版：浏览器里没有 Isolate（Isolate.run 会抛 UnsupportedError），
/// 只能在当前线程算。音乐试听的波形渲染是毫秒级的，可以接受。
Future<T> runInBackground<T>(T Function() computation) =>
    Future<T>.sync(computation);

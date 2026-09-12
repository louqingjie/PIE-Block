/// Keil 工具链的查找与授权。
///
/// 桌面版直接用 pieblock_toolchain 里的实现；Web 上不存在本地 Keil，换成
/// 一个永远找不到的桩。这样向导不需要为了 Web 把整段 Keil UI 删掉，
/// 也不会因为引 toolchain 的 barrel 而把 dart:io 拖进 Web 构建。
library;

export 'keil_discovery_native.dart'
    if (dart.library.js_interop) 'keil_discovery_web.dart';

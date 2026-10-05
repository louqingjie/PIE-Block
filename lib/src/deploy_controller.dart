/// 部署控制器：桌面与移动端接本地工具链与 USB-HID，Web 上是空桩。
library;

export 'deploy_controller_native.dart'
    if (dart.library.js_interop) 'deploy_controller_web.dart';

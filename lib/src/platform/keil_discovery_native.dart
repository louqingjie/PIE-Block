/// 桌面 / 移动端：直接用真实的实现。
///
/// 这里 import 公开 barrel 是有意的——本文件只会在非 Web 平台被选中。
library;

export 'package:pieblock_toolchain/pieblock_toolchain.dart'
    show KeilInstallation, ToolchainDiscovery;

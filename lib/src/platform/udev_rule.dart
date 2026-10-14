/// udev 规则的安装入口：桌面/移动端走 pkexec，Web 端是空实现。
///
/// 只有 Linux 桌面版真正用到（写 `/etc/udev/rules.d/` 并重载 udev）；其它平台
/// 的 `installed` 恒为 true，让相关 UI 整块消失。
library;

export 'udev_rule_native.dart'
    if (dart.library.js_interop) 'udev_rule_web.dart';

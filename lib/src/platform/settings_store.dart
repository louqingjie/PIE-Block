/// 应用设置的持久化入口：桌面与移动端落 settings.json，Web 落 localStorage。
///
/// 两边都刻意「尽力而为」——读失败返回 null、写失败静默放弃。设置里只有
/// 主题、编译器偏好、最近项目这类东西，不值得为了它们打断用户操作。
library;

export 'settings_store_native.dart'
    if (dart.library.js_interop) 'settings_store_web.dart';

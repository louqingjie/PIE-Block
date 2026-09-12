/// 平台相关路径建议。文件对话框仍然是唯一事实来源，这里只给输入框一个
/// 初始值；Web 上没有本地目录概念，直接返回 null。
library;

export 'paths_native.dart' if (dart.library.js_interop) 'paths_web.dart';

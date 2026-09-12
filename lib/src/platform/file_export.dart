/// 把生成好的文本交给用户。
///
/// 桌面与移动端弹「完整文件路径」对话框后写盘（能自由选择位置），Web 上
/// 没有可写文件系统，改为直接触发浏览器下载。返回是否真的交付成功，
/// 用户取消时返回 false。
library;

export 'file_export_native.dart'
    if (dart.library.js_interop) 'file_export_web.dart';

/// 文档存取入口：桌面与 Android 走文件/内容 URI，Web 只有「选文件」这一件事。
///
/// 两端各自定义一份 `SelectedDocument` 与 `AppDocumentIo`（结构一致），
/// 条件导出保证每次只编译其中一份——与 pieblock_core 里
/// `project_repository_io/_web` 的处理方式相同。
library;

export 'document_io_native.dart'
    if (dart.library.js_interop) 'document_io_web.dart';

library;

export 'src/code_generator.dart';
export 'src/models.dart';
export 'src/midi_codec.dart';
export 'src/music.dart';
// 仓库实现按平台分叉：桌面/移动端落文件，Web 落 localStorage。
// 这个 barrel 必须保持「Web 上不引入 dart:io」，否则任何引用它的包
// （例如 pieblock_toolchain）都会连带编译不过。
export 'src/project_repository_io.dart'
    if (dart.library.js_interop) 'src/project_repository_web.dart';
export 'src/validator.dart';

// TODO: Export any libraries intended for clients of this package.

/// CLI PATH 维护入口：有 dart:io 的平台走真实实现，Web 是空实现。
library;

export 'cli_path_service_stub.dart'
    if (dart.library.io) 'cli_path_service_io.dart';

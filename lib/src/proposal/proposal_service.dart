/// 提案服务入口：桌面/移动端走文件系统，Web 是空实现。
library;

export 'proposal_service_stub.dart'
    if (dart.library.io) 'proposal_service_io.dart';

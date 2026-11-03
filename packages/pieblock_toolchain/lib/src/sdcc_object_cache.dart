import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import 'file_ops.dart';

/// 目标文件缓存格式版本；修改缓存键或元数据格式时递增。
const sdccObjectCacheVersion = 'v1';

class CachedSdccObject {
  const CachedSdccObject({
    required this.objectPath,
    required this.warningCount,
  });

  final String objectPath;
  final int warningCount;
}

/// 按「工具链/固件指纹 + 工程 + 源文件相对路径」缓存 SDCC 目标文件。
///
/// 缓存只服务桌面端 `FirmwareBuilder._buildSdcc()`：生成的 `main.c` 每次
/// 重建，其余固件源码在指纹不变时直接复用。对象与元数据都采用原子写入；
/// 复用前校验大小与 SHA-256，损坏时按未命中处理。
class SdccObjectCache {
  SdccObjectCache({
    required String runtimeRoot,
    required this.compilerFingerprint,
    required this.project,
  }) : root = p.join(runtimeRoot, 'object-cache', sdccObjectCacheVersion);

  final String root;
  final String compilerFingerprint;
  final String project;

  String get projectRoot => p.join(root, compilerFingerprint, project);

  String cachePath(String relative) {
    final normalized = relative.replaceAll('\\', '/');
    return p.join(
      projectRoot,
      '${normalized.replaceAll('/', p.separator)}.rel',
    );
  }

  String listingCachePath(String relative) =>
      p.setExtension(cachePath(relative), '.lst');

  String metadataPath(String objectPath) => '$objectPath.json';

  /// 清理其它指纹目录，避免工具链/固件升级后旧目标文件无限累积。
  Future<void> pruneOtherFingerprints() async {
    final base = Directory(root);
    if (!await base.exists()) return;
    try {
      await for (final entity in base.list(followLinks: false)) {
        if (entity is! Directory) continue;
        if (p.basename(entity.path) == compilerFingerprint) continue;
        try {
          await entity.delete(recursive: true);
        } on FileSystemException {
          // 清理失败不影响构建。
        }
      }
    } on FileSystemException {
      // 缓存根不可读时按无缓存构建。
    }
  }

  /// 命中时把缓存对象与对应的 `.lst` 复制到 [destination]，返回缓存的警告条数。
  Future<CachedSdccObject?> lookup(
    String relative,
    String destination,
  ) async {
    final source = File(cachePath(relative));
    final listing = File(listingCachePath(relative));
    final metadata = File(metadataPath(source.path));
    try {
      if (!await source.exists() ||
          !await listing.exists() ||
          !await metadata.exists()) {
        return null;
      }
      final json = jsonDecode(await metadata.readAsString());
      if (json is! Map) return null;
      final size = (json['size'] as num?)?.toInt();
      final hash = json['sha256'] as String?;
      final listingSize = (json['listing_size'] as num?)?.toInt();
      final listingHash = json['listing_sha256'] as String?;
      final warningCount = (json['warning_count'] as num?)?.toInt() ?? 0;
      if (size == null ||
          hash == null ||
          listingSize == null ||
          listingHash == null) {
        return null;
      }
      final bytes = await source.readAsBytes();
      final listingBytes = await listing.readAsBytes();
      if (bytes.length != size ||
          sha256.convert(bytes).toString() != hash ||
          listingBytes.length != listingSize ||
          sha256.convert(listingBytes).toString() != listingHash) {
        return null;
      }
      await Directory(p.dirname(destination)).create(recursive: true);
      await _atomicCopy(source, File(destination));
      await _atomicCopy(
        listing,
        File(p.setExtension(destination, '.lst')),
      );
      return CachedSdccObject(
        objectPath: destination,
        warningCount: warningCount,
      );
    } on Object {
      return null;
    }
  }

  /// 编译成功后写回目标文件、`.lst` 与元数据。
  Future<void> store(
    String relative,
    String objectPath, {
    required int warningCount,
  }) async {
    final listingSource = File(p.setExtension(objectPath, '.lst'));
    if (!await listingSource.exists()) {
      throw StateError('编译未产出 .lst：$objectPath');
    }
    final destination = File(cachePath(relative));
    final listingDestination = File(listingCachePath(relative));
    await Directory(destination.parent.path).create(recursive: true);
    await _atomicCopy(File(objectPath), destination);
    await _atomicCopy(listingSource, listingDestination);
    final bytes = await destination.readAsBytes();
    final listingBytes = await listingDestination.readAsBytes();
    await _atomicWrite(
      File(metadataPath(destination.path)),
      jsonEncode({
        'warning_count': warningCount,
        'size': bytes.length,
        'sha256': sha256.convert(bytes).toString(),
        'listing_size': listingBytes.length,
        'listing_sha256': sha256.convert(listingBytes).toString(),
      }),
    );
  }

  static Future<void> _atomicCopy(File source, File destination) =>
      retryFileSystem(() async {
        final temporary = File(_temporaryPath(destination));
        try {
          await source.copy(temporary.path);
          if (await destination.exists()) await destination.delete();
          await temporary.rename(destination.path);
        } finally {
          if (await temporary.exists()) {
            try {
              await temporary.delete();
            } on FileSystemException {
              // 临时文件清理失败不影响结果。
            }
          }
        }
      });

  static Future<void> _atomicWrite(File destination, String contents) =>
      retryFileSystem(() async {
        final temporary = File(_temporaryPath(destination));
        try {
          await temporary.writeAsString(contents, flush: true);
          if (await destination.exists()) await destination.delete();
          await temporary.rename(destination.path);
        } finally {
          if (await temporary.exists()) {
            try {
              await temporary.delete();
            } on FileSystemException {
              // 临时文件清理失败不影响结果。
            }
          }
        }
      });

  static String _temporaryPath(File destination) =>
      '${destination.path}.$pid-${DateTime.now().microsecondsSinceEpoch}.tmp';
}

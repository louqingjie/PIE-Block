import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pieblock_toolchain/src/sdcc_object_cache.dart';
import 'package:test/test.dart';

void main() {
  group('SDCC 目标文件缓存', () {
    late Directory temporary;

    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('pieblock-object-cache-');
    });

    tearDown(() async {
      if (await temporary.exists()) {
        await temporary.delete(recursive: true);
      }
    });

    SdccObjectCache cache({String fingerprint = 'fp-current'}) =>
        SdccObjectCache(
          runtimeRoot: temporary.path,
          compilerFingerprint: fingerprint,
          project: 'ROBOMASTER_INFANTRY',
        );

    Future<File> writeObject(List<int> bytes) async {
      final file = File(p.join(temporary.path, 'work', 'sample.rel'));
      await file.parent.create(recursive: true);
      await file.writeAsBytes(bytes, flush: true);
      await File(
        p.setExtension(file.path, '.lst'),
      ).writeAsString('sample listing', flush: true);
      return file;
    }

    test('缓存命中复制对象并保留警告条数', () async {
      final objectCache = cache();
      final source = await writeObject([1, 2, 3, 4]);
      await objectCache.store(
        'libraries/boards/src/remote_control.c',
        source.path,
        warningCount: 2,
      );

      final destination = p.join(temporary.path, 'output', 'remote_control_5.rel');
      final hit = await objectCache.lookup(
        'libraries/boards/src/remote_control.c',
        destination,
      );
      expect(hit, isNotNull);
      expect(hit!.warningCount, 2);
      expect(await File(destination).readAsBytes(), [1, 2, 3, 4]);
      expect(
        await File(p.setExtension(destination, '.lst')).readAsString(),
        'sample listing',
      );
    });

    test('对象或元数据损坏时按未命中处理', () async {
      final objectCache = cache();
      final source = await writeObject([5, 6, 7]);
      await objectCache.store('a.c', source.path, warningCount: 0);
      final destination = p.join(temporary.path, 'output', 'a.rel');

      await File(objectCache.cachePath('a.c')).writeAsBytes([9, 9], flush: true);
      expect(await objectCache.lookup('a.c', destination), isNull);

      await objectCache.store('a.c', source.path, warningCount: 0);
      await File(objectCache.listingCachePath('a.c')).delete();
      expect(await objectCache.lookup('a.c', destination), isNull);

      await objectCache.store('a.c', source.path, warningCount: 0);
      await File(
        objectCache.metadataPath(objectCache.cachePath('a.c')),
      ).writeAsString('{not-json', flush: true);
      expect(await objectCache.lookup('a.c', destination), isNull);
    });

    test('清理其它指纹目录并保留当前指纹', () async {
      final objectCache = cache();
      final source = await writeObject([8, 9]);
      await objectCache.store('b.c', source.path, warningCount: 0);
      Directory(
        p.join(objectCache.root, 'fp-old', 'ROBOMASTER_ENGINEER'),
      ).createSync(recursive: true);
      expect(Directory(objectCache.projectRoot).existsSync(), isTrue);

      await objectCache.pruneOtherFingerprints();
      expect(Directory(objectCache.projectRoot).existsSync(), isTrue);
      expect(
        Directory(p.join(objectCache.root, 'fp-old')).existsSync(),
        isFalse,
      );
      expect(Directory(objectCache.projectRoot).listSync(), isNotEmpty);
    });
  });
}

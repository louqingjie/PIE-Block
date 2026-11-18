import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/platform/document_io.dart';

void main() {
  test('Android SAF URI 显示用户可读文件名', () {
    expect(
      AppDocumentIo.displayName(
        'content://com.android.externalstorage.documents/document/'
        'primary%3ADocuments%2Frobot.pieproj',
      ),
      'robot.pieproj',
    );
  });

  test('Android SAF URI 文件名含百分号时不会重复解码', () {
    expect(
      AppDocumentIo.displayName(
        'content://com.android.externalstorage.documents/document/'
        'primary%3A%2Fstorage%2Femulated%2F0%2FDownload%2F%E6%88%91%E7%9A%84%E6%9C%BA%E5%99%A8%E4%BA%BA.pieproj%20(2).json',
      ),
      '我的机器人.pieproj (2).json',
    );
  });

  test('桌面端写入先落临时文件再原子替换，不留下临时文件', () async {
    final directory = Directory.systemTemp.createTempSync('pieblock-doc-io-');
    final target = File(
      '${directory.path}${Platform.pathSeparator}robot.pieproj',
    )..writeAsStringSync('old');
    try {
      const io = AppDocumentIo();
      await io.write(target.path, Uint8List.fromList('new'.codeUnits));
      expect(target.readAsStringSync(), 'new');
      final leftovers = directory
          .listSync()
          .where((entity) => entity.path != target.path);
      expect(leftovers, isEmpty);
    } finally {
      directory.deleteSync(recursive: true);
    }
  });
}

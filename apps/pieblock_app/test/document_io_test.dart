import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/document_io.dart';

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
}

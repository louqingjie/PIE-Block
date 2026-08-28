import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_app/src/hid/android_hid_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('cn.edu.cnu.pieblock/hid');
  final calls = <String>[];

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    calls.clear();
  });

  test('AndroidHidTransport 将传输调用映射到平台通道', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'list':
          return <Map<String, Object?>>[
            {'deviceName': '/dev/bus/usb/001/002'},
          ];
        case 'open':
          return 'ok';
        case 'write':
          expect(call.arguments, <int>[0x46, 0xb9, 0x6a]);
          return true;
        case 'read':
          return Uint8List.fromList([0x46, 0xb9, 0x68, 0, 3, 1, 0, 0]);
        default:
          return null;
      }
    });

    final transport = AndroidHidTransport(channel: channel);
    expect(await transport.countDevices(), 1);
    expect(await transport.open(), isTrue);
    expect(
      await transport.write(Uint8List.fromList([0x46, 0xb9, 0x6a])),
      isTrue,
    );
    final response = await transport.read(100);
    expect(response.take(3), <int>[0x46, 0xb9, 0x68]);
    await transport.cancel();
    await transport.close();
    expect(calls, <String>['list', 'open', 'write', 'read', 'cancel', 'close']);
  });

  test('countDevices 无设备时返回 0', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'list' ? <Object?>[] : null,
    );
    final transport = AndroidHidTransport(channel: channel);
    expect(await transport.countDevices(), 0);
  });

  test('open 返回 app_mode 时抛出带指引的错误', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => 'app_mode');
    final transport = AndroidHidTransport(channel: channel);
    await expectLater(
      transport.open(),
      throwsA(isA<StateError>().having(
        (e) => e.message,
        'message',
        contains('主控板正在运行用户程序'),
      )),
    );
  });
}

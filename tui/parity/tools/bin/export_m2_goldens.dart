// 开发期基准生成器：HEX/MAP 校验 + HID 协议/烧录状态机 golden。
//
// 运行：cd tui/parity/tools && dart run bin/export_m2_goldens.dart
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pieblock_hid/pieblock_hid.dart';
import 'package:pieblock_toolchain/pieblock_toolchain.dart';

Future<void> main() async {
  final toolsDir = Directory.current.absolute.path;
  final repoRoot = Directory(toolsDir).parent.parent.parent;
  final outputDir = Directory('${repoRoot.path}${Platform.pathSeparator}tui'
      '${Platform.pathSeparator}parity${Platform.pathSeparator}golden'
      '${Platform.pathSeparator}m2');
  outputDir.createSync(recursive: true);
  final tempDir = Directory(
    '${outputDir.path}${Platform.pathSeparator}tmp',
  )..createSync(recursive: true);

  final hexCases = _hexCases();
  final hexResults = <Object?>[];
  for (final item in hexCases) {
    final path = '${tempDir.path}${Platform.pathSeparator}${item.name}.hex';
    File(path).writeAsStringSync(item.content);
    final result = await IntelHexValidator.parse(path);
    hexResults.add({
      'name': item.name,
      'content': item.content,
      'ok': result.ok,
      'message': result.message,
      if (result.image != null)
        'bytes': [
          for (final entry in result.image!.bytes.entries)
            [entry.key, entry.value],
        ],
    });
  }
  final appResults = <Object?>[];
  for (final item in hexCases) {
    final path = '${tempDir.path}${Platform.pathSeparator}${item.name}.hex';
    File(path).writeAsStringSync(item.content);
    final result = await IntelHexValidator.validateApplication(path);
    appResults.add({
      'name': item.name,
      'ok': result.ok,
      'message': result.message,
    });
  }

  final validHex = hexCases
      .firstWhere((item) => item.name == 'valid_application')
      .content;
  final mapResults = <Object?>[];
  for (final item in _mapCases()) {
    final hexPath = '${tempDir.path}${Platform.pathSeparator}map.hex';
    final mapPath = '${tempDir.path}${Platform.pathSeparator}map.map';
    File(hexPath).writeAsStringSync(item.hex ?? validHex);
    if (item.map == null) {
      File(mapPath).deleteSync();
    } else {
      File(mapPath).writeAsStringSync(item.map!);
    }
    final result = await IntelHexValidator.validateSdccLayout(
      hexPath: hexPath,
      mapPath: mapPath,
    );
    mapResults.add({
      'name': item.name,
      'hex': item.hex,
      'map': item.map,
      'ok': result.ok,
      'message': result.message,
    });
  }

  final hid = <String, Object?>{
    'packets': [
      for (final payload in <List<int>>[
        [0x01, 0, 0, 0, 0, 0, 0, 0x80, 0],
        [0xff],
        [0x32, 0, 0, 0x5a, 0xa5, ...List.generate(128, (index) => index)],
      ])
        {
          'payload': payload,
          'packet': _hex(HidProtocol.buildPacket(payload)),
          'reports': [
            for (final report
                in HidProtocol.splitReports(HidProtocol.buildPacket(payload)))
              _hex(report),
          ],
        },
    ],
    'blocks': [
      for (final image in <Map<int, int>>[
        {0xfe0000: 1, 0xfe0200: 2, 0xff0000: 3},
        {0xfe0000: 1, 0xff0000: 2},
        {0xff0000: 0x02, 0xff0001: 0, 0xff0002: 0x10},
      ])
        {
          'bytes': [
            for (final entry in image.entries) [entry.key, entry.value],
          ],
          'blocks': [
            for (final block in HidProtocol.buildWriteBlocks(HexImage(image)))
              {
                'address': block.address,
                'command': block.command,
                'data': _hex(block.data),
              },
          ],
        },
    ],
    'flasher': await _flasherCases(),
  };

  final target = File('${outputDir.path}${Platform.pathSeparator}m2.json');
  target.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'hexParse': hexResults,
      'hexValidate': appResults,
      'mapValidate': mapResults,
      ...hid,
    })}\n',
  );
  tempDir.deleteSync(recursive: true);
  stdout.writeln('m2 golden: ${target.path}');
}

List<({String name, String content})> _hexCases() {
  String record(int type, int address, List<int> data) {
    final values = <int>[
      data.length,
      (address >> 8) & 0xff,
      address & 0xff,
      type,
      ...data,
    ];
    final checksum = (0x100 - (values.fold<int>(0, (a, b) => (a + b) & 0xff))) & 0xff;
    return ':${values.map((v) => v.toRadixString(16).padLeft(2, '0')).join()}${checksum.toRadixString(16).padLeft(2, '0')}';
  }

  final valid = [
    record(0, 0xfe0000, [1, 2, 3, 4]),
    record(0, 0xff0000, [0x02, 0x00, 0x00, 0x10, 0x20]),
    record(1, 0, []),
  ].join('\n');

  final extended = [
    record(4, 0, [0x00, 0xfe]),
    record(0, 0x0000, [1, 2, 3, 4]),
    record(4, 0, [0x00, 0xff]),
    record(0, 0x0000, [0x02, 0x00, 0x00, 0x10, 0x20]),
    record(1, 0, []),
  ].join('\n');

  final noVector = [
    record(0, 0xfe0000, [1, 2, 3, 4]),
    record(1, 0, []),
  ].join('\n');
  final noUser = [
    record(0, 0xff0000, [0x02, 0x00, 0x00]),
    record(1, 0, []),
  ].join('\n');
  final noLJmp = [
    record(0, 0xfe0000, [1, 2, 3, 4]),
    record(0, 0xff0000, [0x03, 0x00, 0x00]),
    record(1, 0, []),
  ].join('\n');
  final lowAddress = [
    record(0, 0x010000, [1, 2, 3, 4]),
    record(0, 0xff0000, [0x02, 0x00, 0x00]),
    record(1, 0, []),
  ].join('\n');
  final badChecksum = [
    record(0, 0xfe0000, [1, 2, 3, 4]),
    ':00000001FE',
  ].join('\n');

  return [
    (name: 'valid_application', content: valid),
    (name: 'extended_address', content: extended),
    (name: 'empty', content: ''),
    (name: 'no_vector', content: noVector),
    (name: 'no_user', content: noUser),
    (name: 'no_ljmp', content: noLJmp),
    (name: 'low_address', content: lowAddress),
    (name: 'bad_checksum', content: badChecksum),
    (name: 'missing_colon', content: '00000001FF'),
    (name: 'odd_length', content: ':00000001F'),
    (name: 'illegal_hex', content: ':00000001GG'),
    (name: 'wrong_length', content: ':0200000001FF'),
    (name: 'unsupported_type', content: ':00000006FF'),
  ];
}

List<({String name, String? hex, String? map})> _mapCases() {
  const symbols = '''
__sdcc_mcs251_reset_trampoline
__sdcc_gsinit_startup
_Default_Isr
''';
  return [
    (
      name: 'valid_map',
      hex: null,
      map: '''
HOME            00FF0000 00000003 =
CSEG            00FE0000 00000004 =
XSEG            00010000 00001000 =
DSEG            00000000 00000100 =
$symbols
''',
    ),
    (
      name: 'home_wrong',
      hex: null,
      map: '''
HOME            00FE0000 00000003 =
$symbols
''',
    ),
    (
      name: 'cseg_overflow',
      hex: null,
      map: '''
HOME            00FF0000 00000003 =
CSEG            00FE0000 00020000 =
$symbols
''',
    ),
    (
      name: 'xseg_overflow',
      hex: null,
      map: '''
HOME            00FF0000 00000003 =
XSEG            00010000 00003000 =
$symbols
''',
    ),
    (
      name: 'missing_symbols',
      hex: null,
      map: 'HOME            00FF0000 00000003 =',
    ),
    (name: 'missing_map', hex: null, map: null),
  ];
}

Future<List<Object?>> _flasherCases() async {
  Uint8List ack(int command, [List<int> rest = const []]) =>
      Uint8List.fromList([0x46, 0xb9, 0x68, 0, rest.length + 3, command, ...rest, 0, 0]);

  final results = <Object?>[];
  Future<void> run(
    String name,
    Map<int, int> image,
    _FakeTransport transport,
  ) async {
    final events = <Object?>[];
    final result = await HidFlasher.flashWithTransport(
      HexImage(image),
      transport,
      (stage, message, {current, total}) => events.add({
        'stage': stage.name,
        'message': message,
        'current': current,
        'total': total,
      }),
      reportGap: Duration.zero,
      retryBackoff: Duration.zero,
      probeTimeout: const Duration(milliseconds: 10),
    );
    results.add({
      'name': name,
      'devices': transport.devices,
      'image': [
        for (final entry in image.entries) [entry.key, entry.value],
      ],
      'responses': [
        for (final response in transport.script) response == null ? null : _hex(response),
      ],
      'failWriteFrom': transport.failWriteFrom,
      'events': events,
      'result': {
        'success': result.success,
        'stage': result.stage.name,
        'message': result.message,
        'canceled': result.canceled,
      },
      'writes': [for (final write in transport.writes) _hex(write)],
      'closed': transport.closed,
    });
  }

  return _runAsync(run, ack);
}

Future<List<Object?>> _runAsync(
  Future<void> Function(String, Map<int, int>, _FakeTransport) run,
  Uint8List Function(int, [List<int>]) ack,
) async {
  final results = <Object?>[];
  final small = {0xfe0000: 1, 0xff0000: 2};
  final success = _FakeTransport()
    ..script.addAll([ack(0x01), ack(0x05), ack(0x03), ack(0x02, [0x54]), ack(0x02, [0x54])]);
  await run('success', small, success);

  final zero = _FakeTransport()..devices = 0;
  await run('zero_devices', small, zero);
  final two = _FakeTransport()..devices = 2;
  await run('two_devices', small, two);

  final retry = _FakeTransport()
    ..script.addAll([
      ack(0x01),
      ack(0x05),
      ack(0x03),
      null,
      ack(0x02, [0x54]),
      ack(0x02, [0x54]),
    ]);
  await run('retry_block', small, retry);

  final interruptedDead = _FakeTransport()
    ..script.addAll([ack(0x01), ack(0x05), ack(0x03), null, null, null, null]);
  await run('interrupted_dead', small, interruptedDead);

  final interruptedAlive = _FakeTransport()
    ..script.addAll([ack(0x01), ack(0x05), ack(0x03), null, null, null, ack(0x01)]);
  await run('interrupted_alive', small, interruptedAlive);

  final writeFail = _FakeTransport()
    ..failWriteFrom = 1
    ..script.addAll([ack(0x01)]);
  await run('write_failure', small, writeFail);

  final badCommand = _FakeTransport()
    ..script.addAll([ack(0x05)]);
  await run('bad_ack_command', small, badCommand);

  final shortFrame = _FakeTransport()
    ..script.add(Uint8List.fromList([0x46, 0xb9]));
  await run('short_frame', small, shortFrame);

  return results;
}

class _FakeTransport implements HidTransport {
  int devices = 1;
  bool closed = false;
  int? failWriteFrom;
  final List<Uint8List?> script = [];
  final List<Uint8List> writes = [];

  @override
  Future<void> cancel() async {}

  @override
  Future<void> close() async => closed = true;

  @override
  Future<int> countDevices() async => devices;

  @override
  Future<bool> open() async => true;

  @override
  Future<Uint8List> read(int timeoutMilliseconds) async {
    if (script.isEmpty) return Uint8List(0);
    return script.removeAt(0) ?? Uint8List(0);
  }

  @override
  Future<bool> write(Uint8List report) async {
    writes.add(report);
    final limit = failWriteFrom;
    if (limit != null && writes.length > limit) return false;
    return true;
  }
}

String _hex(List<int> bytes) =>
    bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();

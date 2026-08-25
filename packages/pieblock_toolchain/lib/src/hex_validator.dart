import 'dart:io';

class HexImage {
  const HexImage(this.bytes);
  final Map<int, int> bytes;
  int get minAddress => bytes.keys.reduce((a, b) => a < b ? a : b);
  int get maxAddress => bytes.keys.reduce((a, b) => a > b ? a : b);
}

class HexValidationResult {
  const HexValidationResult({
    required this.ok,
    required this.message,
    this.image,
  });
  final bool ok;
  final String message;
  final HexImage? image;
}

abstract final class IntelHexValidator {
  static const _applicationBase = 0xfe0000;
  static const _vectorBase = 0xff0000;
  static const _vectorLimit = 0xff1000;
  static const _xramBase = 0x010000;
  static const _xramLimit = 0x012000;
  static const _iramLimit = 0x1000;

  static Future<HexValidationResult> validateApplication(String path) async {
    final parsed = await parse(path);
    if (!parsed.ok) return parsed;
    final image = parsed.image!;
    if (image.bytes.isEmpty) {
      return const HexValidationResult(ok: false, message: 'HEX 中没有数据');
    }
    if (image.minAddress < 0xfe0000 || image.maxAddress > 0xffffff) {
      return HexValidationResult(
        ok: false,
        message:
            'HEX 地址超出主控板应用区：0x${image.minAddress.toRadixString(16)}–0x${image.maxAddress.toRadixString(16)}',
      );
    }
    if (!image.bytes.keys.any((address) => address < 0xff0000)) {
      return const HexValidationResult(
        ok: false,
        message: 'HEX 缺少 0xFE0000 用户代码区',
      );
    }
    if (!image.bytes.keys.any((address) => address >= 0xff0000)) {
      return const HexValidationResult(
        ok: false,
        message: 'HEX 缺少 0xFF0000 向量或关键数据区',
      );
    }
    if (image.bytes[0xff0000] != 0x02 ||
        !image.bytes.containsKey(0xff0001) ||
        !image.bytes.containsKey(0xff0002)) {
      return const HexValidationResult(
        ok: false,
        message: 'HEX 缺少完整的 0xFF0000 LJMP 复位向量',
      );
    }
    if (image.bytes.keys.any((address) => address >= 0xff1000)) {
      return const HexValidationResult(
        ok: false,
        message: 'HEX 向量区数据越过 0xFF1000',
      );
    }
    return HexValidationResult(
      ok: true,
      message: 'HEX 布局有效，共 ${image.bytes.length} 字节',
      image: image,
    );
  }

  static Future<HexValidationResult> parse(String path) async {
    final file = File(path);
    if (!await file.exists()) {
      return const HexValidationResult(ok: false, message: 'HEX 文件不存在');
    }
    final image = <int, int>{};
    var upper = 0;
    final lines = await file.readAsLines();
    for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
      final line = lines[lineIndex].trim();
      if (line.isEmpty) continue;
      if (!line.startsWith(':') || (line.length - 1).isOdd) {
        return HexValidationResult(
          ok: false,
          message: 'HEX 第 ${lineIndex + 1} 行格式无效',
        );
      }
      final values = <int>[];
      try {
        for (var pos = 1; pos < line.length; pos += 2) {
          values.add(int.parse(line.substring(pos, pos + 2), radix: 16));
        }
      } on FormatException {
        return HexValidationResult(
          ok: false,
          message: 'HEX 第 ${lineIndex + 1} 行包含非法十六进制字符',
        );
      }
      if (values.length < 5 || values.length != values.first + 5) {
        return HexValidationResult(
          ok: false,
          message: 'HEX 第 ${lineIndex + 1} 行长度错误',
        );
      }
      if (values.fold<int>(0, (sum, value) => (sum + value) & 0xff) != 0) {
        return HexValidationResult(
          ok: false,
          message: 'HEX 第 ${lineIndex + 1} 行校验和错误',
        );
      }
      final count = values[0];
      final address = (values[1] << 8) | values[2];
      final type = values[3];
      if (type == 0) {
        for (var index = 0; index < count; index++) {
          image[upper + address + index] = values[4 + index];
        }
      } else if (type == 2) {
        upper = ((values[4] << 8) | values[5]) << 4;
      } else if (type == 4) {
        upper = ((values[4] << 8) | values[5]) << 16;
      } else if (type != 1 && type != 3 && type != 5) {
        return HexValidationResult(
          ok: false,
          message: 'HEX 第 ${lineIndex + 1} 行记录类型不受支持',
        );
      }
    }
    return HexValidationResult(
      ok: true,
      message: 'HEX 解析成功',
      image: HexImage(image),
    );
  }

  /// Validates the linker layout emitted by the bundled C251 SDCC backend.
  /// This is the Dart equivalent of the legacy `check_layout.py`, so release
  /// builds do not depend on Python.
  static Future<HexValidationResult> validateSdccLayout({
    required String hexPath,
    required String mapPath,
  }) async {
    final parsed = await validateApplication(hexPath);
    if (!parsed.ok) return parsed;
    final image = parsed.image!;
    for (var address = _vectorBase; address < _vectorBase + 3; address++) {
      if (!image.bytes.containsKey(address)) {
        return const HexValidationResult(
          ok: false,
          message: '复位向量 0xFF0000 不完整',
        );
      }
    }
    if (image.bytes[_vectorBase] != 0x02) {
      return HexValidationResult(
        ok: false,
        message:
            '复位向量首字节为 0x${image.bytes[_vectorBase]!.toRadixString(16).padLeft(2, '0')}，应为 LJMP 0x02',
      );
    }
    final highAddresses = image.bytes.keys
        .where((address) => address >= _vectorBase)
        .toList();
    if (highAddresses.any((address) => address >= _vectorLimit)) {
      return const HexValidationResult(ok: false, message: '向量区数据越过 0xFF1000');
    }

    final mapFile = File(mapPath);
    if (!await mapFile.exists()) {
      return const HexValidationResult(ok: false, message: '缺少 SDCC MAP 文件');
    }
    final mapText = await mapFile.readAsString();
    final areaPattern = RegExp(
      r'^\s*(HOME|GSINIT|GSFINAL|CSEG|CONST|XINIT|XISEG|DSEG|SSEG|PSEG|XSEG)\s+([0-9A-Fa-f]{8})\s+([0-9A-Fa-f]{8})\s+=',
      multiLine: true,
    );
    for (final match in areaPattern.allMatches(mapText)) {
      final name = match.group(1)!;
      final start = int.parse(match.group(2)!, radix: 16);
      final length = int.parse(match.group(3)!, radix: 16);
      final end = start + length;
      String? error;
      if (name == 'HOME') {
        if (start != _vectorBase || end > _vectorLimit) {
          error = 'HOME 超出向量区';
        }
      } else if ({
        'GSINIT',
        'GSFINAL',
        'CSEG',
        'CONST',
        'XINIT',
      }.contains(name)) {
        if (length > 0 &&
            !(start >= _applicationBase &&
                start < _vectorBase &&
                end <= _vectorBase)) {
          error = '$name 超出用户程序区';
        }
      } else if ({'XSEG', 'XISEG'}.contains(name)) {
        if (length > 0 && !(start >= _xramBase && end <= _xramLimit)) {
          error = '$name 超出 STC32G XRAM';
        }
      } else if (length > 0 && !(start >= 0 && end <= _iramLimit)) {
        error = '$name 超出 STC32G EDATA';
      }
      if (error != null) {
        return HexValidationResult(
          ok: false,
          message:
              '$error：0x${start.toRadixString(16).padLeft(8, '0')}–0x${end.toRadixString(16).padLeft(8, '0')}',
        );
      }
    }
    for (final symbol in const [
      '__sdcc_mcs251_reset_trampoline',
      '__sdcc_gsinit_startup',
      '_Default_Isr',
    ]) {
      if (!mapText.contains(symbol)) {
        return HexValidationResult(ok: false, message: 'MAP 缺少启动或向量符号：$symbol');
      }
    }
    return HexValidationResult(
      ok: true,
      message: 'SDCC HEX/MAP 布局校验通过，共 ${image.bytes.length} 字节',
      image: image,
    );
  }
}

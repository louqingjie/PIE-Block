// OLED 五线谱模拟器的画布工具：1bit 位图（SSD1306 页格式）、PNG 编码、灰度放大。
//
// 乐理/字形/版面已经迁移到 pieblock_core：
//   - 字形点阵：`staff_glyphs.dart`（StaffGlyph / staffGlyphList / digitGlyphs）
//   - 显示模型：`staff_notation.dart`（buildStaffSong / StaffEventData …）
//   - 整数版面：`staff_layout.dart`（staffLayoutX / staffYForStep …）
//
// 本文件只保留与“画布/编码”有关的纯工具，供模拟器（tool/staff_render.dart）、
// fixture 生成器（tool/staff_fixtures.dart）与测试共用；不包含任何乐理判断。

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:pieblock_core/pieblock_core.dart';

// ---------------------------------------------------------------------------
// 屏幕与帧缓冲
// ---------------------------------------------------------------------------

/// 屏幕尺寸/帧缓冲布局以 core 的 `staff_layout.dart` 为准（固件同源）。
const int screenWidth = staffScreenWidth;
const int screenHeight = staffScreenHeight;
const int screenPages = screenHeight ~/ 8;
const int frameBytes = screenWidth * screenPages;

/// 1bit 位图；字节布局与 SSD1306 页寻址一致（bit0 = 页内最上一行）。
class Bitmap {
  Bitmap(this.width, this.height)
    : bytes = Uint8List(width * ((height + 7) ~/ 8));

  final int width, height;
  final Uint8List bytes;

  void setPixel(int x, int y, [bool on = true]) {
    if (x < 0 || y < 0 || x >= width || y >= height) return;
    final index = (y >> 3) * width + x;
    final mask = 1 << (y & 7);
    if (on) {
      bytes[index] |= mask;
    } else {
      bytes[index] &= ~mask;
    }
  }

  bool pixel(int x, int y) {
    if (x < 0 || y < 0 || x >= width || y >= height) return false;
    return (bytes[(y >> 3) * width + x] & (1 << (y & 7))) != 0;
  }

  void hLine(int x1, int x2, int y) {
    for (var x = math.min(x1, x2); x <= math.max(x1, x2); x++) {
      setPixel(x, y);
    }
  }

  void vLine(int x, int y1, int y2) {
    for (var y = math.min(y1, y2); y <= math.max(y1, y2); y++) {
      setPixel(x, y);
    }
  }

  void fillRect(int x, int y, int w, int h) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        setPixel(xx, yy);
      }
    }
  }

  /// 把矩形区域清成“不着墨”，用于左端固定/禁区区域重绘。
  void clearRect(int x, int y, int w, int h) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        setPixel(xx, yy, false);
      }
    }
  }

  void strokeRect(int x, int y, int w, int h) {
    hLine(x, x + w - 1, y);
    hLine(x, x + w - 1, y + h - 1);
    vLine(x, y, y + h - 1);
    vLine(x + w - 1, y, y + h - 1);
  }
}

// ---------------------------------------------------------------------------
// PNG 输出（8bit 灰度，不依赖第三方包）
// ---------------------------------------------------------------------------

Uint8List encodePngGray(int width, int height, Uint8List gray) {
  if (gray.length != width * height) {
    throw ArgumentError('灰度数据长度应为 ${width * height}');
  }
  final raw = Uint8List(height * (width + 1));
  for (var y = 0; y < height; y++) {
    final dst = y * (width + 1);
    raw[dst] = 0; // filter: none
    raw.setRange(dst + 1, dst + 1 + width, gray, y * width);
  }
  final compressed = ZLibCodec(level: 9).encode(raw);
  final out = BytesBuilder(copy: false);
  out.add(const <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  void chunk(String type, List<int> data) {
    final typeBytes = ascii.encode(type);
    final length = ByteData(4)..setUint32(0, data.length);
    out.add(length.buffer.asUint8List());
    out.add(typeBytes);
    out.add(data);
    final crc = ByteData(4)..setUint32(0, _crc32(<int>[...typeBytes, ...data]));
    out.add(crc.buffer.asUint8List());
  }

  final header = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 0) // grayscale
    ..setUint8(10, 0) // compression
    ..setUint8(11, 0) // filter
    ..setUint8(12, 0); // interlace
  chunk('IHDR', header.buffer.asUint8List());
  chunk('IDAT', compressed);
  chunk('IEND', const <int>[]);
  return out.toBytes();
}

Uint32List? _crcTable;

int _crc32(List<int> data) {
  final table = _crcTable ??= () {
    final result = Uint32List(256);
    for (var n = 0; n < 256; n++) {
      var c = n;
      for (var k = 0; k < 8; k++) {
        c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
      }
      result[n] = c;
    }
    return result;
  }();
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}

// ---------------------------------------------------------------------------
// 灰度放大 / 字形叠加（评审图用）
// ---------------------------------------------------------------------------

/// 把 1bit 位图放大 [scale] 倍并转成 8bit 灰度（255=亮）。
Uint8List bitmapToGray(Bitmap bitmap, {int scale = 1, int margin = 0}) {
  final width = (bitmap.width + margin * 2) * scale;
  final height = (bitmap.height + margin * 2) * scale;
  final gray = Uint8List(width * height);
  for (var y = 0; y < bitmap.height; y++) {
    for (var x = 0; x < bitmap.width; x++) {
      if (!bitmap.pixel(x, y)) continue;
      final left = (x + margin) * scale;
      final top = (y + margin) * scale;
      for (var dy = 0; dy < scale; dy++) {
        final row = (top + dy) * width;
        for (var dx = 0; dx < scale; dx++) {
          gray[row + left + dx] = 255;
        }
      }
    }
  }
  return gray;
}

/// 在 8bit 灰度画布上叠加 core 字形（用于对比图的帧号）。
void blitGlyphGray(
  Uint8List canvas,
  int canvasWidth,
  int canvasHeight,
  StaffGlyph glyph,
  int x,
  int y,
  int scale,
) {
  for (var row = 0; row < glyph.height; row++) {
    for (var col = 0; col < glyph.width; col++) {
      if (glyph.rows[row][col] != '#') continue;
      for (var dy = 0; dy < scale; dy++) {
        final py = y + row * scale + dy;
        if (py < 0 || py >= canvasHeight) continue;
        for (var dx = 0; dx < scale; dx++) {
          final px = x + col * scale + dx;
          if (px < 0 || px >= canvasWidth) continue;
          canvas[py * canvasWidth + px] = 255;
        }
      }
    }
  }
}

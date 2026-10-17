/// 把 [StaffSongData] 发射成固件侧 C 数据表（主点阵 + SoA 事件表 + StaffSong）。
///
/// 代码生成器（`CodeGenerator._music`）和主机对拍 fixture 工具共用这一份发射逻辑，
/// 保证模拟器、固件、fixture 三边的数据完全一致。C 结构体定义见
/// `stc32g_sdcc/libraries/boards/inc/StaffRender.h`。
library;

import 'staff_glyphs.dart';
import 'staff_notation.dart';

/// 字形在 C 侧枚举中的顺序必须与 [StaffGlyphId] 一致。
const int staffFirmwareGlyphCount = 22;

/// 事件 flags 布局：bit0-1 临时记号，bit2 谱号，bit3-7 时值编码。
int staffFirmwareFlags(StaffEventData event) =>
    (event.accidental & 0x3) |
    ((event.clef & 0x1) << 2) |
    ((event.noteValue.code & 0x1f) << 3);

String _hex(int value, int width) =>
    '0x${value.toRadixString(16).toUpperCase().padLeft(width, '0')}';

String _rowsTable(String name, List<int> values, {int perLine = 12}) {
  final buffer = StringBuffer('static const uint16_t $name[] =\n{\n');
  for (var i = 0; i < values.length; i += perLine) {
    final end = (i + perLine < values.length) ? i + perLine : values.length;
    buffer.write('    ');
    buffer.write(
      values.sublist(i, end).map((value) => _hex(value, 4)).join(', '),
    );
    if (end < values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('};\n');
  return buffer.toString();
}

String _u8Table(String name, List<int> values, {int perLine = 16}) {
  final buffer = StringBuffer('static const uint8_t $name[] =\n{\n');
  for (var i = 0; i < values.length; i += perLine) {
    final end = (i + perLine < values.length) ? i + perLine : values.length;
    buffer.write('    ');
    buffer.write(
      values.sublist(i, end).map((value) => _hex(value, 2)).join(', '),
    );
    if (end < values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('};\n');
  return buffer.toString();
}

String _i8Table(String name, List<int> values, {int perLine = 16}) {
  final buffer = StringBuffer('static const int8_t $name[] =\n{\n');
  for (var i = 0; i < values.length; i += perLine) {
    final end = (i + perLine < values.length) ? i + perLine : values.length;
    buffer.write('    ');
    buffer.write(
      values
          .sublist(i, end)
          .map((value) => value < 0 ? '-${_hex(-value, 2)}' : _hex(value, 2))
          .join(', '),
    );
    if (end < values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('};\n');
  return buffer.toString();
}

String _u32Table(String name, List<int> values, {int perLine = 8}) {
  final buffer = StringBuffer('static const uint32_t $name[] =\n{\n');
  for (var i = 0; i < values.length; i += perLine) {
    final end = (i + perLine < values.length) ? i + perLine : values.length;
    buffer.write('    ');
    buffer.write(
      values.sublist(i, end).map((value) => '${value}UL').join(', '),
    );
    if (end < values.length) buffer.write(',');
    buffer.write('\n');
  }
  buffer.write('};\n');
  return buffer.toString();
}

/// 发射 [song] 的完整 C 数据表。[prefix] 用于区分多个场景（如 `staff` / `fixtureTwinkle`）。
String emitStaffFirmwareTables(
  StaffSongData song, {
  required String prefix,
  bool includeComment = true,
}) {
  final glyphs = staffGlyphList;
  final glyphRows = <int>[];
  final descriptors = <String>[];
  for (final glyph in glyphs) {
    final height = glyph.height;
    final width = glyph.width;
    final rowOffset = glyphRows.length;
    glyphRows.addAll(glyph.rowBits);
    // 宽度为 0 的字形（理论上不存在）也给出合法描述符。
    descriptors.add('    {$width, $height, $rowOffset}');
  }
  final events = song.events;
  final count = events.length;
  final safeCount = count == 0 ? 1 : count;
  final tickDurations = events.isEmpty
      ? <int>[0]
      : events.map((event) => event.tickDuration).toList(growable: false);
  final durationsMs = events.isEmpty
      ? <int>[1]
      : events.map((event) => event.durationMs).toList(growable: false);
  final pitches = events.isEmpty
      ? <int>[0]
      : events.map((event) => event.pitch).toList(growable: false);
  final flags = events.isEmpty
      ? <int>[0]
      : events.map(staffFirmwareFlags).toList(growable: false);
  final steps = events.isEmpty
      ? <int>[0]
      : events.map((event) => event.step).toList(growable: false);
  final keyStepsTreble = song.keyStepsTreble.isEmpty
      ? <int>[0]
      : song.keyStepsTreble;
  final keyStepsBass = song.keyStepsBass.isEmpty ? <int>[0] : song.keyStepsBass;

  final buffer = StringBuffer();
  if (includeComment) {
    buffer.writeln('/* ---- 五线谱显示数据（由 Pie-Block 代码生成器自动生成）---- */');
  }
  buffer.writeln('#define ${prefix.toUpperCase()}_EVENT_COUNT $count');
  buffer.writeln(
    '#define ${prefix.toUpperCase()}_GLYPH_COUNT $staffFirmwareGlyphCount',
  );
  buffer.writeln('#define ${prefix.toUpperCase()}_KEY_COUNT ${song.keyCount}');
  buffer.writeln('#define ${prefix.toUpperCase()}_EVENT_STORAGE $safeCount');
  buffer.writeln();
  buffer.write(_rowsTable('${prefix}GlyphRows', glyphRows));
  buffer.writeln();
  buffer.writeln('static const StaffGlyph ${prefix}GlyphDescs[] =\n{');
  buffer.writeln(descriptors.join(',\n'));
  buffer.writeln('};');
  buffer.writeln();
  buffer.writeln(
    'static const StaffGlyphSet ${prefix}GlyphSet =\n'
    '    {$staffFirmwareGlyphCount, ${prefix}GlyphRows, ${prefix}GlyphDescs};',
  );
  buffer.writeln();
  buffer.write(_u32Table('${prefix}TickDurations', tickDurations));
  buffer.writeln();
  buffer.write(_u32Table('${prefix}DurationsMs', durationsMs));
  buffer.writeln();
  buffer.write(_u8Table('${prefix}Pitches', pitches));
  buffer.writeln();
  buffer.write(_u8Table('${prefix}Flags', flags));
  buffer.writeln();
  buffer.write(_i8Table('${prefix}Steps', steps));
  buffer.writeln();
  buffer.write(_i8Table('${prefix}KeyStepsTreble', keyStepsTreble));
  buffer.writeln();
  buffer.write(_i8Table('${prefix}KeyStepsBass', keyStepsBass));
  buffer.writeln();
  buffer.writeln('static const StaffSong ${prefix}Song =');
  buffer.writeln('{');
  buffer.writeln('    $count,');
  buffer.writeln('    ${song.ticksPerQuarter},');
  buffer.writeln('    ${song.timeNumerator},');
  buffer.writeln('    ${song.timeDenominator},');
  buffer.writeln('    ${song.keyCount},');
  buffer.writeln('    ${song.keyIsSharp ? 1 : 0},');
  buffer.writeln('    ${prefix}TickDurations,');
  buffer.writeln('    ${prefix}DurationsMs,');
  buffer.writeln('    ${prefix}Pitches,');
  buffer.writeln('    ${prefix}Steps,');
  buffer.writeln('    ${prefix}Flags,');
  buffer.writeln('    ${prefix}KeyStepsTreble,');
  buffer.writeln('    ${prefix}KeyStepsBass,');
  buffer.writeln('    &${prefix}GlyphSet');
  buffer.writeln('};');
  return buffer.toString();
}

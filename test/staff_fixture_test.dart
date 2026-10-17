// 主机对拍 fixture 防漂移测试。
//
// 校验仓库内已提交的 stc32g_sdcc/tests/staff/fixtures/：
//   - staff_fixture.h（6 个场景的 C 数据表 + scenario 表）
//   - golden/<scenario>_<frame:03d>.bin（1024 字节 SSD1306 页格式帧）
// 与 `tool/staff_fixtures.dart` 重新计算的结果逐字节一致。
//
// 若本测试失败：说明改了字形/版面/事件模型但忘了重新生成 fixture，运行
//     dart run tool/emit_staff_fixtures.dart
// 重新生成后再提交。

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pieblock_core/pieblock_core.dart';

import '../tool/staff_fixtures.dart';
import '../tool/staff_render.dart';

void main() {
  late StaffFixtureBundle bundle;

  setUpAll(() {
    bundle = StaffFixtureBundle.generate();
  });

  test('已提交 fixture 与生成逻辑逐字节一致（无漂移）', () async {
    final drifts = await verifyStaffFixtures(bundle);
    expect(
      drifts,
      isEmpty,
      reason:
          'fixture 已漂移，请运行 `dart run tool/emit_staff_fixtures.dart` '
          '重新生成后再提交：\n${drifts.join('\n')}',
    );
  });

  test('fixture 目录存在且 header/golden 齐全', () {
    final rootPath = staffFixtureRootPath();
    expect(
      File('$rootPath/$staffFixtureHeaderName').existsSync(),
      isTrue,
      reason: '缺少 $rootPath/$staffFixtureHeaderName',
    );
    final goldenDir = staffFixtureGoldenDirectory(rootPath);
    expect(goldenDir.existsSync(), isTrue);
    final goldenFiles = goldenDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.bin'))
        .toList();
    expect(goldenFiles, hasLength(bundle.frameCount));
    for (final file in goldenFiles) {
      expect(file.lengthSync(), 1024, reason: '${file.path} 不是 1024 字节');
    }
    expect(bundle.frameCount * 1024, 67584);
  });

  test('6 个场景（名称/顺序/前缀）', () {
    expect(bundle.scenarioCount, 6);
    expect(bundle.scenarios.map((scenario) => scenario.name).toList(), <String>[
      'twinkle',
      'flats',
      'mixed',
      'accidentals',
      'rests',
      'sevenSharps',
    ]);
    expect(
      bundle.scenarios.map((scenario) => scenario.prefix).toList(),
      <String>[
        'fixtureTwinkle',
        'fixtureFlats',
        'fixtureMixed',
        'fixtureAccidentals',
        'fixtureRests',
        'fixtureSevenSharps',
      ],
    );
  });

  test('场景调号：twinkle/flats/mixed/accidentals/rests 与 sevenSharps', () {
    final byName = <String, StaffFixtureScenario>{
      for (final scenario in bundle.scenarios) scenario.name: scenario,
    };
    expect(byName['twinkle']!.keyFifths, 0);
    expect(byName['flats']!.keyFifths, -1);
    expect(byName['flats']!.song.keyIsSharp, isFalse);
    expect(byName['mixed']!.keyFifths, 0);
    expect(byName['accidentals']!.keyFifths, 0);
    expect(byName['rests']!.keyFifths, 0);
    expect(byName['sevenSharps']!.keyFifths, 7);
    expect(byName['sevenSharps']!.song.keyIsSharp, isTrue);
    for (final scenario in bundle.scenarios) {
      expect(
        scenario.song.keyStepsTreble,
        hasLength(scenario.song.keyCount),
        reason: '${scenario.name} 调号步数表数量不符',
      );
      expect(
        scenario.song.keyStepsBass,
        hasLength(scenario.song.keyCount),
        reason: '${scenario.name} 调号步数表数量不符',
      );
    }
  });

  test('每个场景帧数 = 事件数，golden 帧与渲染器同源', () {
    for (final scenario in bundle.scenarios) {
      final frames = bundle.frames
          .where((frame) => frame.scenario == scenario.name)
          .toList();
      expect(
        frames,
        hasLength(scenario.frameCount),
        reason: '${scenario.name} 帧数与事件数不一致',
      );
      expect(scenario.frameCount, greaterThan(0));
      for (final frame in frames) {
        expect(frame.bytes, hasLength(1024));
        expect(
          frame.fileName,
          '${scenario.name}_${frame.index.toString().padLeft(3, '0')}.bin',
        );
      }
      // 重新渲染一帧，确认 fixture 不是手工改过的旧数据。
      final renderer = StaffRenderer(config: scenario.config);
      for (final frame in frames) {
        final bitmap = renderer.renderFrame(frame.index);
        expect(
          frame.bytes,
          orderedEquals(bitmap.bytes),
          reason: '${scenario.name} 第 ${frame.index} 帧与 Dart 渲染器不一致',
        );
      }
    }
  });

  test('scenario 数/帧覆盖：66 帧', () {
    expect(bundle.frameCount, 66);
    final counts = <String, int>{
      for (final scenario in bundle.scenarios)
        scenario.name: scenario.frameCount,
    };
    expect(counts, <String, int>{
      'twinkle': 14,
      'flats': 7,
      'mixed': 15,
      'accidentals': 8,
      'rests': 8,
      'sevenSharps': 14,
    });
  });

  test('staff_fixture.h 满足 C 侧契约', () {
    final header = bundle.header;
    expect(header, startsWith('/* Host-comparison fixtures'));
    expect(header, contains('#ifndef STAFF_FIXTURE_H'));
    expect(header, contains('#include "StaffRender.h"'));
    expect(header, contains('#define STAFF_FIXTURE_SCENARIO_COUNT 6'));
    expect(header, contains('typedef struct'));
    expect(header, contains('const char *name;'));
    expect(header, contains('const StaffSong *song;'));
    expect(header, contains('} StaffFixtureScenario;'));
    expect(
      header,
      contains(
        'static const StaffFixtureScenario '
        'staffFixtureScenarios[STAFF_FIXTURE_SCENARIO_COUNT] =',
      ),
    );
    for (final scenario in bundle.scenarios) {
      expect(
        header,
        contains('{"${scenario.name}", &${scenario.prefix}Song}'),
        reason: '${scenario.name} 的 scenario 表项缺失',
      );
      expect(
        header,
        contains('static const StaffSong ${scenario.prefix}Song ='),
      );
      expect(
        header,
        contains(
          '#define ${scenario.prefix.toUpperCase()}_EVENT_COUNT '
          '${scenario.frameCount}',
        ),
      );
      expect(
        header,
        contains('static const StaffGlyphSet ${scenario.prefix}GlyphSet'),
      );
    }
    // C 头保持纯 ASCII，避免 gcc/SDCC 跨平台源码编码问题。
    expect(
      header.codeUnits.every((unit) => unit < 0x80),
      isTrue,
      reason: 'staff_fixture.h 含非 ASCII 字符',
    );
  });

  test('生成逻辑确定性：两次生成结果完全一致', () {
    final other = StaffFixtureBundle.generate();
    expect(other.header, bundle.header);
    expect(other.frameCount, bundle.frameCount);
    for (var i = 0; i < bundle.frames.length; i++) {
      expect(
        other.frames[i].bytes,
        orderedEquals(bundle.frames[i].bytes),
        reason: '第 $i 帧生成不确定',
      );
    }
  });

  test('C 侧枚举/时值编码与 fixture 数据一致', () {
    expect(StaffGlyphId.values, hasLength(staffFirmwareGlyphCount));
    // 事件 flags：bit0-1 临时记号、bit2 谱号、bit3-7 时值编码。
    for (final scenario in bundle.scenarios) {
      final song = scenario.song;
      for (final event in song.events) {
        final flags = staffFirmwareFlags(event);
        expect(flags & 0x3, event.accidental & 0x3);
        expect((flags >> 2) & 0x1, event.clef);
        expect((flags >> 3) & 0x1F, event.noteValue.code);
        expect(event.durationMs, greaterThan(0));
        expect(event.tickDuration, greaterThan(0));
      }
    }
  });
}

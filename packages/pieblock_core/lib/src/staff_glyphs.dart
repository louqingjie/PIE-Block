/// 五线谱显示用的 1bit 字形点阵（纯数据，无 dart:io，可被 Web/移动端共用）。
///
/// 这批点阵同时供三处使用，必须保持一致：
/// - `tool/render_oled_staff.dart` 离线模拟器（输出评审用 PNG/GIF）；
/// - `CodeGenerator._music` 生成的 SDCC 固件（点阵随 main.c 一起生成）；
/// - 主机对拍测试（C 渲染器读到的是同一份点阵）。
///
/// 行宽上限 16（C 侧每行用 uint16_t 掩码，bit0 = 最左像素，bit1 = 右边一格…）。
library;

/// 字形在固件里的编号；C 侧 `StaffRender.h` 的枚举必须保持同样的顺序。
enum StaffGlyphId {
  trebleClef,
  bassClef,
  sharp,
  flat,
  natural,
  noteHeadFilled,
  noteHeadHollow,
  restWhole,
  restHalf,
  restQuarter,
  restEighth,
  restSixteenth,
  digit0,
  digit1,
  digit2,
  digit3,
  digit4,
  digit5,
  digit6,
  digit7,
  digit8,
  digit9,
}

class StaffGlyph {
  const StaffGlyph(this.rows);

  final List<String> rows;

  int get width => rows.isEmpty ? 0 : rows.first.length;
  int get height => rows.length;

  /// 每行的位掩码（bit0 = 最左像素），供 C 固件表使用。
  List<int> get rowBits {
    final bits = <int>[];
    for (final row in rows) {
      var value = 0;
      for (var col = 0; col < row.length; col++) {
        if (row[col] == '#') value |= 1 << col;
      }
      bits.add(value);
    }
    return bits;
  }
}

/// 高音谱号（13×28）。放置：左端 x=1，上沿在谱表顶线上方 2px。
const StaffGlyph trebleClefGlyph = StaffGlyph(<String>[
  '......##.....',
  '.....####....',
  '.....#..#....',
  '.....#..#....',
  '.....#..#....',
  '.....#..#....',
  '.....###.....',
  '.....###.....',
  '....###......',
  '..#####......',
  '..###.#......',
  '.###..#......',
  '.##...####...',
  '##...######..',
  '#...########.',
  '#...##.#...#.',
  '#...#..#...#.',
  '##..#..#...#.',
  '.#......#..#.',
  '..#.....#.#..',
  '...#######...',
  '........#....',
  '........#....',
  '....##..##...',
  '....###.##...',
  '....###.#....',
  '.....###.....',
]);

/// 低音谱号（12×13，含右侧两个点）。
const StaffGlyph bassClefGlyph = StaffGlyph(<String>[
  '............',
  '...####.....',
  '.###..##....',
  '.##....##.##',
  '.#.....##.##',
  '.###...##...',
  '.####..##...',
  '..##...##.##',
  '.......#..##',
  '......##....',
  '....###.....',
  '.####.......',
]);

/// 升号（5×7）：两根竖线 + 两根横线；绘制时须擦掉字形包围盒内的谱线像素。
const StaffGlyph sharpGlyph = StaffGlyph(<String>[
  '.#.#.',
  '.#.#.',
  '#####',
  '.#.#.',
  '#####',
  '.#.#.',
  '.#.#.',
]);

/// 降号（4×7）。
const StaffGlyph flatGlyph = StaffGlyph(<String>[
  '#...',
  '#...',
  '#...',
  '#...',
  '###.',
  '#..#',
  '###.',
]);

/// 还原号（3×7）：紧凑 ♮，中间 1px 空洞。
const StaffGlyph naturalGlyph = StaffGlyph(<String>[
  '#..',
  '#..',
  '###',
  '#.#',
  '###',
  '..#',
  '..#',
]);

/// 符头：实心 / 空心（4×3）。
const StaffGlyph noteHeadFilled = StaffGlyph(<String>['.##.', '####', '.##.']);
const StaffGlyph noteHeadHollow = StaffGlyph(<String>['.##.', '#..#', '.##.']);

/// 休止符。
const StaffGlyph restWholeGlyph = StaffGlyph(<String>['#####', '#####']);
const StaffGlyph restHalfGlyph = StaffGlyph(<String>['#####', '#####']);
const StaffGlyph restQuarterGlyph = StaffGlyph(<String>[
  '.##',
  '#..',
  '.#.',
  '..#',
  '.#.',
  '#..',
]);
const StaffGlyph restEighthGlyph = StaffGlyph(<String>['.#', '#.', '.#', '.#']);
const StaffGlyph restSixteenthGlyph = StaffGlyph(<String>[
  '.#',
  '#.',
  '.#',
  '.#',
  '.#',
]);

/// 拍号数字（7×8）。
const Map<String, StaffGlyph> digitGlyphs = <String, StaffGlyph>{
  '0': StaffGlyph(<String>[
    '..###..',
    '.##..#.',
    '.#...##',
    '.#.####',
    '####.##',
    '.##..##',
    '.#...#.',
    '..###..',
  ]),
  '1': StaffGlyph(<String>[
    '..###..',
    '.#.##..',
    '...##..',
    '...##..',
    '...##..',
    '...##..',
    '...##..',
    '.#####.',
  ]),
  '2': StaffGlyph(<String>[
    '..###..',
    '.#..##.',
    '.....#.',
    '....##.',
    '...##..',
    '..##...',
    '.##....',
    '.######',
  ]),
  '3': StaffGlyph(<String>[
    '####..',
    '...##.',
    '...##.',
    '.###..',
    '...##.',
    '....#.',
    '...##.',
    '####..',
  ]),
  '4': StaffGlyph(<String>[
    '...###.',
    '...###.',
    '..#.##.',
    '.##.##.',
    '.#..##.',
    '#######',
    '....##.',
    '....##.',
  ]),
  '5': StaffGlyph(<String>[
    '#####.',
    '#.....',
    '#.....',
    '####..',
    '...##.',
    '....#.',
    '...##.',
    '####..',
  ]),
  '6': StaffGlyph(<String>[
    '...###.',
    '.##....',
    '.#.....',
    '.#####.',
    '.##..#.',
    '.#...##',
    '.##..#.',
    '..###..',
  ]),
  '7': StaffGlyph(<String>[
    '.#####.',
    '.....#.',
    '....##.',
    '....#..',
    '...##..',
    '...#...',
    '..##...',
    '..#....',
  ]),
  '8': StaffGlyph(<String>[
    '..####.',
    '.#...#.',
    '.##.##.',
    '..###..',
    '.##.##.',
    '.#...#.',
    '.#...#.',
    '..####.',
  ]),
  '9': StaffGlyph(<String>[
    '..###..',
    '.#...#.',
    '.#...#.',
    '.#..##.',
    '.#####.',
    '.....#.',
    '....##.',
    '.####..',
  ]),
};

/// 按 [StaffGlyphId] 顺序排列的字形表；C 侧枚举顺序必须与此一致。
List<StaffGlyph> get staffGlyphList => <StaffGlyph>[
  trebleClefGlyph,
  bassClefGlyph,
  sharpGlyph,
  flatGlyph,
  naturalGlyph,
  noteHeadFilled,
  noteHeadHollow,
  restWholeGlyph,
  restHalfGlyph,
  restQuarterGlyph,
  restEighthGlyph,
  restSixteenthGlyph,
  for (var digit = 0; digit <= 9; digit++) digitGlyphs['$digit']!,
];

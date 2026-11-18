//! 五线谱 1bit 字形点阵（与 `staff_glyphs.dart` 对齐）。
//!
//! 同一份点阵供固件代码生成、离线渲染与 M6 音乐页共用；行宽上限 16（C 侧
//! 每行用 `uint16_t` 掩码，bit0 = 最左像素）。

/// 字形编号；C 侧 `StaffRender.h` 枚举顺序必须与此一致。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StaffGlyphId {
    TrebleClef,
    BassClef,
    Sharp,
    Flat,
    Natural,
    NoteHeadFilled,
    NoteHeadHollow,
    RestWhole,
    RestHalf,
    RestQuarter,
    RestEighth,
    RestSixteenth,
    Digit0,
    Digit1,
    Digit2,
    Digit3,
    Digit4,
    Digit5,
    Digit6,
    Digit7,
    Digit8,
    Digit9,
}

/// 字形点阵：每行由 `#` 与 `.` 组成。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StaffGlyph {
    pub rows: &'static [&'static str],
}

impl StaffGlyph {
    #[must_use]
    pub fn width(&self) -> usize {
        self.rows.first().map_or(0, |row| row.len())
    }

    #[must_use]
    pub fn height(&self) -> usize {
        self.rows.len()
    }

    /// 每行位掩码（bit0 = 最左像素），供固件表使用。
    #[must_use]
    pub fn row_bits(&self) -> Vec<u16> {
        self.rows
            .iter()
            .map(|row| {
                let mut value = 0_u16;
                for (column, ch) in row.chars().enumerate() {
                    if ch == '#' {
                        value |= 1 << column;
                    }
                }
                value
            })
            .collect()
    }
}

const TREBLE_CLEF: StaffGlyph = StaffGlyph {
    rows: &[
        "......##.....",
        ".....####....",
        ".....#..#....",
        ".....#..#....",
        ".....#..#....",
        ".....#..#....",
        ".....###.....",
        ".....###.....",
        "....###......",
        "..#####......",
        "..###.#......",
        ".###..#......",
        ".##...####...",
        "##...######..",
        "#...########.",
        "#...##.#...#.",
        "#...#..#...#.",
        "##..#..#...#.",
        ".#......#..#.",
        "..#.....#.#..",
        "...#######...",
        "........#....",
        "........#....",
        "....##..##...",
        "....###.##...",
        "....###.#....",
        ".....###.....",
    ],
};

const BASS_CLEF: StaffGlyph = StaffGlyph {
    rows: &[
        "............",
        "...####.....",
        ".###..##....",
        ".##....##.##",
        ".#.....##.##",
        ".###...##...",
        ".####..##...",
        "..##...##.##",
        ".......#..##",
        "......##....",
        "....###.....",
        ".####.......",
    ],
};

const SHARP: StaffGlyph = StaffGlyph {
    rows: &[
        ".#.#.", ".#.#.", "#####", ".#.#.", "#####", ".#.#.", ".#.#.",
    ],
};

const FLAT: StaffGlyph = StaffGlyph {
    rows: &["#...", "#...", "#...", "#...", "###.", "#..#", "###."],
};

const NATURAL: StaffGlyph = StaffGlyph {
    rows: &["#..", "#..", "###", "#.#", "###", "..#", "..#"],
};

const NOTE_HEAD_FILLED: StaffGlyph = StaffGlyph {
    rows: &[".##.", "####", ".##."],
};
const NOTE_HEAD_HOLLOW: StaffGlyph = StaffGlyph {
    rows: &[".##.", "#..#", ".##."],
};

const REST_WHOLE: StaffGlyph = StaffGlyph {
    rows: &["#####", "#####"],
};
const REST_HALF: StaffGlyph = StaffGlyph {
    rows: &["#####", "#####"],
};
const REST_QUARTER: StaffGlyph = StaffGlyph {
    rows: &[".##", "#..", ".#.", "..#", ".#.", "#.."],
};
const REST_EIGHTH: StaffGlyph = StaffGlyph {
    rows: &[".#", "#.", ".#", ".#"],
};
const REST_SIXTEENTH: StaffGlyph = StaffGlyph {
    rows: &[".#", "#.", ".#", ".#", ".#"],
};

const DIGIT_0: StaffGlyph = StaffGlyph {
    rows: &[
        "..###..", ".##..#.", ".#...##", ".#.####", "####.##", ".##..##", ".#...#.", "..###..",
    ],
};
const DIGIT_1: StaffGlyph = StaffGlyph {
    rows: &[
        "..###..", ".#.##..", "...##..", "...##..", "...##..", "...##..", "...##..", ".#####.",
    ],
};
const DIGIT_2: StaffGlyph = StaffGlyph {
    rows: &[
        "..###..", ".#..##.", ".....#.", "....##.", "...##..", "..##...", ".##....", ".######",
    ],
};
const DIGIT_3: StaffGlyph = StaffGlyph {
    rows: &[
        "####..", "...##.", "...##.", ".###..", "...##.", "....#.", "...##.", "####..",
    ],
};
const DIGIT_4: StaffGlyph = StaffGlyph {
    rows: &[
        "...###.", "...###.", "..#.##.", ".##.##.", ".#..##.", "#######", "....##.", "....##.",
    ],
};
const DIGIT_5: StaffGlyph = StaffGlyph {
    rows: &[
        "#####.", "#.....", "#.....", "####..", "...##.", "....#.", "...##.", "####..",
    ],
};
const DIGIT_6: StaffGlyph = StaffGlyph {
    rows: &[
        "...###.", ".##....", ".#.....", ".#####.", ".##..#.", ".#...##", ".##..#.", "..###..",
    ],
};
const DIGIT_7: StaffGlyph = StaffGlyph {
    rows: &[
        ".#####.", ".....#.", "....##.", "....#..", "...##..", "...#...", "..##...", "..#....",
    ],
};
const DIGIT_8: StaffGlyph = StaffGlyph {
    rows: &[
        "..####.", ".#...#.", ".##.##.", "..###..", ".##.##.", ".#...#.", ".#...#.", "..####.",
    ],
};
const DIGIT_9: StaffGlyph = StaffGlyph {
    rows: &[
        "..###..", ".#...#.", ".#...#.", ".#..##.", ".#####.", ".....#.", "....##.", ".####..",
    ],
};

const ALL_GLYPHS: [StaffGlyph; 22] = [
    TREBLE_CLEF,
    BASS_CLEF,
    SHARP,
    FLAT,
    NATURAL,
    NOTE_HEAD_FILLED,
    NOTE_HEAD_HOLLOW,
    REST_WHOLE,
    REST_HALF,
    REST_QUARTER,
    REST_EIGHTH,
    REST_SIXTEENTH,
    DIGIT_0,
    DIGIT_1,
    DIGIT_2,
    DIGIT_3,
    DIGIT_4,
    DIGIT_5,
    DIGIT_6,
    DIGIT_7,
    DIGIT_8,
    DIGIT_9,
];

/// 按 [`StaffGlyphId`] 顺序排列的字形表。
#[must_use]
pub fn staff_glyph_list() -> &'static [StaffGlyph] {
    &ALL_GLYPHS
}

#[must_use]
pub fn staff_glyph(id: StaffGlyphId) -> StaffGlyph {
    ALL_GLYPHS[id as usize]
}

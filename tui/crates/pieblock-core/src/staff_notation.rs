//! 五线谱显示模型：把 [`MusicConfig`] 解析成固件/模拟器共用的显示事件。
//!
//! 与 `packages/pieblock_core/lib/src/staff_notation.dart` 对齐：
//! 发声区间来自 [`crate::music::MusicTimeline`]，区间间空白拆休止符；每个事件
//! 预计算谱号、相对底线步数（按调号拼写）、临时记号、时值编码与毫秒时长。

use crate::model::MusicConfig;
use crate::music::MusicTimeline;
use crate::staff_glyphs::{StaffGlyph, StaffGlyphId, staff_glyph};

pub const STAFF_KEY_FIFTHS_MIN: i64 = -7;
pub const STAFF_KEY_FIFTHS_MAX: i64 = 7;

/// 编辑器下拉用的调号选项（标签同时给出大调与关系小调）。
pub const STAFF_KEY_SIGNATURE_OPTIONS: [(i64, &str); 15] = [
    (0, "C 大调 / A 小调"),
    (1, "G 大调 / E 小调"),
    (2, "D 大调 / B 小调"),
    (3, "A 大调 / F♯ 小调"),
    (4, "E 大调 / C♯ 小调"),
    (5, "B 大调 / G♯ 小调"),
    (6, "F♯ 大调 / D♯ 小调"),
    (7, "C♯ 大调 / A♯ 小调"),
    (-1, "F 大调 / D 小调"),
    (-2, "B♭ 大调 / G 小调"),
    (-3, "E♭ 大调 / C 小调"),
    (-4, "A♭ 大调 / F 小调"),
    (-5, "D♭ 大调 / B♭ 小调"),
    (-6, "G♭ 大调 / E♭ 小调"),
    (-7, "C♭ 大调 / A♭ 小调"),
];

#[must_use]
pub fn staff_key_label_for_fifths(fifths: i64) -> &'static str {
    STAFF_KEY_SIGNATURE_OPTIONS
        .iter()
        .find(|(value, _)| *value == fifths)
        .map_or("C 大调 / A 小调", |(_, label)| *label)
}

const KEY_NAMES: [(&str, i64); 30] = [
    ("C", 0),
    ("G", 1),
    ("D", 2),
    ("A", 3),
    ("E", 4),
    ("B", 5),
    ("F#", 6),
    ("C#", 7),
    ("F", -1),
    ("Bb", -2),
    ("Eb", -3),
    ("Ab", -4),
    ("Db", -5),
    ("Gb", -6),
    ("Cb", -7),
    ("Am", 0),
    ("Em", 1),
    ("Bm", 2),
    ("F#m", 3),
    ("C#m", 4),
    ("G#m", 5),
    ("D#m", 6),
    ("A#m", 7),
    ("Dm", -1),
    ("Gm", -2),
    ("Cm", -3),
    ("Fm", -4),
    ("Bbm", -5),
    ("Ebm", -6),
    ("Abm", -7),
];

/// 调号名 → 升降号个数；不支持的名字返回与 Dart 相同的 ArgumentError 文案。
pub fn staff_key_fifths(key: &str) -> Result<i64, String> {
    if let Some((_, fifths)) = KEY_NAMES.iter().find(|(name, _)| *name == key) {
        return Ok(*fifths);
    }
    let names = KEY_NAMES
        .iter()
        .map(|(name, _)| *name)
        .collect::<Vec<_>>()
        .join(" / ");
    Err(format!("不支持的调号 {key}；可用：{names}"))
}

pub const LETTER_SEMITONES: [i64; 7] = [0, 2, 4, 5, 7, 9, 11];
pub const SHARP_ORDER_LETTERS: [i64; 7] = [3, 0, 4, 1, 5, 2, 6];
pub const FLAT_ORDER_LETTERS: [i64; 7] = [6, 2, 5, 1, 4, 0, 3];
const TREBLE_SHARP_STEPS: [i64; 7] = [8, 5, 9, 6, 3, 7, 4];
const TREBLE_FLAT_STEPS: [i64; 7] = [4, 7, 3, 6, 2, 5, 1];
const BASS_SHARP_STEPS: [i64; 7] = [6, 3, 7, 4, 1, 5, 2];
const BASS_FLAT_STEPS: [i64; 7] = [2, 5, 1, 4, 0, 3, -1];

#[must_use]
pub fn staff_key_steps_for_clef(fifths: i64, bass: bool) -> Vec<i64> {
    let table = if bass {
        if fifths >= 0 {
            &BASS_SHARP_STEPS
        } else {
            &BASS_FLAT_STEPS
        }
    } else if fifths >= 0 {
        &TREBLE_SHARP_STEPS
    } else {
        &TREBLE_FLAT_STEPS
    };
    table
        .iter()
        .take(usize::try_from(fifths.abs()).unwrap_or(0))
        .copied()
        .collect()
}

#[must_use]
pub fn key_alteration_for_letter(letter: i64, fifths: i64) -> i64 {
    if fifths > 0 {
        if let Some(position) = SHARP_ORDER_LETTERS.iter().position(|item| *item == letter) {
            if i64::try_from(position).unwrap_or(0) < fifths {
                return 1;
            }
        }
    }
    if fifths < 0 {
        if let Some(position) = FLAT_ORDER_LETTERS.iter().position(|item| *item == letter) {
            if i64::try_from(position).unwrap_or(0) < -fifths {
                return -1;
            }
        }
    }
    0
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct PitchSpelling {
    pub letter: i64,
    pub octave: i64,
    pub alteration: i64,
}

impl PitchSpelling {
    #[must_use]
    pub fn id(&self) -> i64 {
        (self.letter << 4) | self.octave
    }

    #[must_use]
    pub fn name(&self) -> String {
        const LETTER_NAMES: &str = "CDEFGAB";
        let letter = LETTER_NAMES
            .chars()
            .nth(usize::try_from(self.letter).unwrap_or(0))
            .unwrap_or('?');
        let suffix = if self.alteration == 1 {
            "#"
        } else if self.alteration == -1 {
            "b"
        } else {
            ""
        };
        format!("{letter}{suffix}{}", self.octave)
    }
}

/// MIDI 音高按调号倾向拼写（降号调优先用降号拼写）。
#[must_use]
pub fn spell_pitch(pitch: i64, fifths: i64) -> PitchSpelling {
    const SHARP_LETTERS: [i64; 12] = [0, 0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6];
    const SHARP_ALTERATIONS: [i64; 12] = [0, 1, 0, 1, 0, 0, 1, 0, 1, 0, 1, 0];
    const FLAT_LETTERS: [i64; 12] = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6];
    const FLAT_ALTERATIONS: [i64; 12] = [0, -1, 0, -1, 0, 0, -1, 0, -1, 0, -1, 0];
    let prefer_flat = fifths < 0;
    let pitch_class = usize::try_from(pitch.rem_euclid(12)).unwrap_or(0);
    let letter = if prefer_flat {
        FLAT_LETTERS[pitch_class]
    } else {
        SHARP_LETTERS[pitch_class]
    };
    let alteration = if prefer_flat {
        FLAT_ALTERATIONS[pitch_class]
    } else {
        SHARP_ALTERATIONS[pitch_class]
    };
    let natural_tick = LETTER_SEMITONES[usize::try_from(letter).unwrap_or(0)];
    let octave = (pitch - alteration - natural_tick) / 12 - 1;
    PitchSpelling {
        letter,
        octave,
        alteration,
    }
}

pub const TREBLE_BOTTOM_LINE_DIATONIC: i64 = 30;
pub const BASS_BOTTOM_LINE_DIATONIC: i64 = 18;

#[must_use]
pub fn clef_bottom_diatonic(clef: i64) -> i64 {
    if clef == 1 {
        BASS_BOTTOM_LINE_DIATONIC
    } else {
        TREBLE_BOTTOM_LINE_DIATONIC
    }
}

#[must_use]
pub fn spelled_diatonic_index(pitch: i64, fifths: i64) -> i64 {
    let spelling = spell_pitch(pitch, fifths);
    spelling.octave * 7 + spelling.letter
}

#[must_use]
pub fn staff_step_for_pitch(pitch: i64, clef: i64, fifths: i64) -> i64 {
    spelled_diatonic_index(pitch, fifths) - clef_bottom_diatonic(clef)
}

#[must_use]
pub fn staff_ledger_count_for_step(step: i64) -> i64 {
    if step > 8 {
        (step - 8) / 2
    } else if step < 0 {
        (-step) / 2
    } else {
        0
    }
}

#[must_use]
pub fn staff_stem_up_for_step(step: i64) -> bool {
    step - 4 < 0
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StaffNoteValue {
    pub denominator: i64,
    pub dots: i64,
    pub code: i64,
}

impl StaffNoteValue {
    #[must_use]
    pub fn beats(&self) -> f64 {
        4.0 / self.denominator as f64 * if self.dots == 1 { 1.5 } else { 1.0 }
    }

    #[must_use]
    pub fn hollow(&self) -> bool {
        self.denominator <= 2
    }

    #[must_use]
    pub fn has_stem(&self) -> bool {
        self.denominator > 1
    }

    #[must_use]
    pub fn flag_count(&self) -> i64 {
        if self.denominator == 8 {
            1
        } else if self.denominator == 16 {
            2
        } else {
            0
        }
    }
}

impl std::fmt::Display for StaffNoteValue {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(
            formatter,
            "1/{}{}",
            self.denominator,
            if self.dots == 1 { "." } else { "" }
        )
    }
}

pub const NOTE_VALUE_CANDIDATES: [StaffNoteValue; 9] = [
    StaffNoteValue {
        denominator: 1,
        dots: 0,
        code: 0,
    },
    StaffNoteValue {
        denominator: 2,
        dots: 1,
        code: 2,
    },
    StaffNoteValue {
        denominator: 2,
        dots: 0,
        code: 1,
    },
    StaffNoteValue {
        denominator: 4,
        dots: 1,
        code: 4,
    },
    StaffNoteValue {
        denominator: 4,
        dots: 0,
        code: 3,
    },
    StaffNoteValue {
        denominator: 8,
        dots: 1,
        code: 6,
    },
    StaffNoteValue {
        denominator: 8,
        dots: 0,
        code: 5,
    },
    StaffNoteValue {
        denominator: 16,
        dots: 1,
        code: 8,
    },
    StaffNoteValue {
        denominator: 16,
        dots: 0,
        code: 7,
    },
];

/// 按拍数取最近的标准时值；返回 `(时值, 是否发生取整)`。
#[must_use]
pub fn staff_note_value_for_beats(beats: f64) -> (StaffNoteValue, bool) {
    let mut best = NOTE_VALUE_CANDIDATES[0];
    let mut best_distance = f64::INFINITY;
    for candidate in NOTE_VALUE_CANDIDATES {
        let distance = (candidate.beats() - beats).abs();
        if distance < best_distance - 1e-9 {
            best = candidate;
            best_distance = distance;
        }
    }
    (best, best_distance > 1e-6)
}

#[must_use]
pub fn staff_note_value_for_code(code: i64) -> StaffNoteValue {
    NOTE_VALUE_CANDIDATES
        .iter()
        .copied()
        .find(|value| value.code == code)
        .unwrap_or(NOTE_VALUE_CANDIDATES[0])
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StaffScoreEvent {
    pub start_tick: i64,
    pub duration_ticks: i64,
    /// `None` = 休止符。
    pub pitch: Option<i64>,
}

impl StaffScoreEvent {
    #[must_use]
    pub fn is_rest(&self) -> bool {
        self.pitch.is_none()
    }

    #[must_use]
    pub fn end_tick(&self) -> i64 {
        self.start_tick + self.duration_ticks
    }
}

#[must_use]
pub fn build_staff_score_events(config: &MusicConfig) -> Vec<StaffScoreEvent> {
    let spans = MusicTimeline::sounding_spans(config);
    let mut events = Vec::new();
    let mut cursor = 0;
    for span in spans {
        if span.start_tick > cursor {
            events.extend(split_rest_events(
                cursor,
                span.start_tick - cursor,
                config.ticks_per_quarter,
            ));
        }
        events.push(StaffScoreEvent {
            start_tick: span.start_tick,
            duration_ticks: span.duration_ticks(),
            pitch: Some(span.pitch),
        });
        cursor = span.end_tick;
    }
    events
}

fn split_rest_events(
    start_tick: i64,
    duration_ticks: i64,
    ticks_per_quarter: i64,
) -> Vec<StaffScoreEvent> {
    const STANDARD_BEATS: [f64; 8] = [4.0, 3.0, 2.0, 1.5, 1.0, 0.75, 0.5, 0.25];
    let mut result = Vec::new();
    let mut remaining = duration_ticks;
    let mut tick = start_tick;
    let minimum_ticks = 1_i64.max((ticks_per_quarter as f64 * 0.25).round() as i64);
    while remaining > 0 {
        if remaining < minimum_ticks {
            result.push(StaffScoreEvent {
                start_tick: tick,
                duration_ticks: remaining,
                pitch: None,
            });
            break;
        }
        let mut chosen = STANDARD_BEATS[STANDARD_BEATS.len() - 1];
        for beats in STANDARD_BEATS {
            let ticks = (beats * ticks_per_quarter as f64).round() as i64;
            if ticks <= remaining {
                chosen = beats;
                break;
            }
        }
        let mut ticks = (chosen * ticks_per_quarter as f64).round() as i64;
        if ticks <= 0 {
            ticks = remaining;
        }
        result.push(StaffScoreEvent {
            start_tick: tick,
            duration_ticks: ticks,
            pitch: None,
        });
        tick += ticks;
        remaining -= ticks;
    }
    result
}

/// 顺序遍历事件分配谱号（3 个音符前瞻 + 迟滞）。
#[must_use]
pub fn assign_staff_clefs(
    events: &[StaffScoreEvent],
    fifths: i64,
    forced_clef: Option<i64>,
) -> Vec<i64> {
    if let Some(clef) = forced_clef {
        if clef == 0 || clef == 1 {
            return vec![clef; events.len()];
        }
    }
    let cost = |index: usize, clef: i64| -> i64 {
        let mut max_ledger = 0;
        let mut seen = 0;
        for event in events.iter().skip(index) {
            if seen >= 3 {
                break;
            }
            if event.is_rest() {
                continue;
            }
            let step = staff_step_for_pitch(event.pitch.unwrap_or(0), clef, fifths);
            max_ledger = max_ledger.max(staff_ledger_count_for_step(step));
            seen += 1;
        }
        max_ledger
    };
    let mut result = vec![0_i64; events.len()];
    let mut current = 0;
    let mut first_index = 0;
    while first_index < events.len() && events[first_index].is_rest() {
        first_index += 1;
    }
    if first_index < events.len() {
        current = if cost(first_index, 0) <= cost(first_index, 1) {
            0
        } else {
            1
        };
    }
    for (index, event) in events.iter().enumerate() {
        if !event.is_rest() {
            let other = 1 - current;
            if cost(index, other) <= cost(index, current) - 2 {
                current = other;
            }
        }
        result[index] = current;
    }
    result
}

/// 供固件 C 渲染器使用的紧凑事件。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct StaffEventData {
    pub tick_duration: i64,
    pub duration_ms: i64,
    /// MIDI 音高；0 = 休止符。
    pub pitch: i64,
    pub step: i64,
    /// 0 = 高音谱号，1 = 低音谱号。
    pub clef: i64,
    /// 0 = 无，1 = ♯，2 = ♭，3 = ♮。
    pub accidental: i64,
    pub note_value: StaffNoteValue,
}

impl StaffEventData {
    #[must_use]
    pub fn is_rest(&self) -> bool {
        self.pitch == 0
    }
}

/// 固件/模拟器共用的显示歌曲。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct StaffSongData {
    pub key_fifths: i64,
    pub ticks_per_quarter: i64,
    pub time_numerator: i64,
    pub time_denominator: i64,
    pub key_steps_treble: Vec<i64>,
    pub key_steps_bass: Vec<i64>,
    pub events: Vec<StaffEventData>,
}

impl StaffSongData {
    #[must_use]
    pub fn key_count(&self) -> i64 {
        self.key_fifths.abs()
    }

    #[must_use]
    pub fn key_is_sharp(&self) -> bool {
        self.key_fifths >= 0
    }

    #[must_use]
    pub fn bar_ticks(&self) -> i64 {
        (self.ticks_per_quarter * 4 / self.time_denominator.max(1)) * self.time_numerator.max(1)
    }
}

#[must_use]
pub fn build_staff_song(config: &MusicConfig) -> StaffSongData {
    let fifths = config
        .key_signature_fifths
        .clamp(STAFF_KEY_FIFTHS_MIN, STAFF_KEY_FIFTHS_MAX);
    let ticks_per_quarter = config.ticks_per_quarter.max(1);
    let score_events = build_staff_score_events(config);
    let clefs = assign_staff_clefs(&score_events, fifths, None);
    let bar_ticks =
        (ticks_per_quarter * 4 / first_denominator(config).max(1)) * first_numerator(config).max(1);
    let mut measure_alterations: std::collections::HashMap<i64, i64> =
        std::collections::HashMap::new();
    let mut current_measure = -1_i64;
    let mut events: Vec<StaffEventData> = Vec::new();
    for (index, event) in score_events.iter().enumerate() {
        let (note_value, _approx) =
            staff_note_value_for_beats(event.duration_ticks as f64 / ticks_per_quarter as f64);
        let start_micros = MusicTimeline::microseconds_at_tick(config, event.start_tick);
        let end_micros = MusicTimeline::microseconds_at_tick(config, event.end_tick());
        let duration_ms = 1_i64.max((((end_micros - start_micros) as f64) / 1000.0).round() as i64);
        if event.is_rest() {
            events.push(StaffEventData {
                tick_duration: event.duration_ticks,
                duration_ms,
                pitch: 0,
                step: 0,
                clef: clefs[index],
                accidental: 0,
                note_value,
            });
            continue;
        }
        let pitch = event.pitch.unwrap_or(0);
        let spelling = spell_pitch(pitch, fifths);
        let measure = if bar_ticks <= 0 {
            0
        } else {
            event.start_tick / bar_ticks
        };
        if measure != current_measure {
            measure_alterations.clear();
            current_measure = measure;
        }
        let key_alteration = key_alteration_for_letter(spelling.letter, fifths);
        let previous = measure_alterations
            .get(&spelling.id())
            .copied()
            .unwrap_or(key_alteration);
        let accidental = if spelling.alteration == previous {
            0
        } else if spelling.alteration == 0 {
            3
        } else if spelling.alteration > 0 {
            1
        } else {
            2
        };
        measure_alterations.insert(spelling.id(), spelling.alteration);
        events.push(StaffEventData {
            tick_duration: event.duration_ticks,
            duration_ms,
            pitch,
            step: staff_step_for_pitch(pitch, clefs[index], fifths),
            clef: clefs[index],
            accidental,
            note_value,
        });
    }
    StaffSongData {
        key_fifths: fifths,
        ticks_per_quarter,
        time_numerator: first_numerator(config),
        time_denominator: first_denominator(config),
        key_steps_treble: staff_key_steps_for_clef(fifths, false),
        key_steps_bass: staff_key_steps_for_clef(fifths, true),
        events,
    }
}

fn first_numerator(config: &MusicConfig) -> i64 {
    config
        .time_signature_events
        .first()
        .map_or(4, |event| event.numerator)
}

fn first_denominator(config: &MusicConfig) -> i64 {
    config
        .time_signature_events
        .first()
        .map_or(4, |event| event.denominator)
}

/// 便携访问字形表（模拟器与代码生成器共用）。
#[must_use]
pub fn staff_glyph_by_id(id: StaffGlyphId) -> StaffGlyph {
    staff_glyph(id)
}

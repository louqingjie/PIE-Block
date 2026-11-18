//! M6 五线谱视图：以终端字符呈现单谱表（高音谱号）与音符位置。

use pieblock_core::model::MusicConfig;
use pieblock_core::staff_notation::{
    PitchSpelling, clef_bottom_diatonic, spell_pitch, staff_key_label_for_fifths,
    staff_step_for_pitch,
};

/// 谱表行数（自上而下覆盖 step 10..-2）。
const TOP_STEP: i64 = 10;
const BOTTOM_STEP: i64 = -2;

fn note_label(music: &MusicConfig, pitch: i64) -> String {
    let PitchSpelling {
        letter,
        octave,
        alteration,
    } = spell_pitch(pitch, music.key_signature_fifths);
    let names = ["C", "D", "E", "F", "G", "A", "B"];
    let name = names
        .get(usize::try_from(letter.rem_euclid(7)).unwrap_or(0))
        .copied()
        .unwrap_or("?");
    let accidental = match alteration {
        value if value > 0 => "♯",
        value if value < 0 => "♭",
        _ => "",
    };
    format!("{name}{accidental}{octave}")
}

/// 生成谱面文本行（不含标题/说明）。
#[must_use]
pub fn staff_text(music: &MusicConfig, width: usize, clef: i64) -> Vec<String> {
    let width = width.max(8);
    let beat = music.ticks_per_quarter.max(1);
    let mut cells: Vec<Vec<char>> = Vec::new();
    for step in (BOTTOM_STEP..=TOP_STEP).rev() {
        let is_line = (0..=8).contains(&step) && step % 2 == 0;
        let line_char = if is_line { '─' } else { ' ' };
        cells.push(vec![line_char; width]);
    }
    let row_of = |step: i64| -> usize {
        usize::try_from(TOP_STEP - step.clamp(BOTTOM_STEP, TOP_STEP)).unwrap_or(0)
    };
    for note in &music.notes {
        let step = staff_step_for_pitch(note.pitch, clef, music.key_signature_fifths);
        let column =
            usize::try_from((note.start_tick / beat).rem_euclid(i64::try_from(width).unwrap_or(1)))
                .unwrap_or(0);
        let row = row_of(step);
        if let Some(cell_row) = cells.get_mut(row) {
            if let Some(cell) = cell_row.get_mut(column) {
                *cell = '●';
            }
        }
    }
    cells
        .into_iter()
        .map(|row| row.into_iter().collect())
        .collect()
}

/// 谱面标题信息。
#[must_use]
pub fn staff_header(music: &MusicConfig) -> String {
    let key = staff_key_label_for_fifths(music.key_signature_fifths);
    let bpm = music.tempo_events.first().map_or(120, |event| {
        60_000_000 / event.microseconds_per_quarter.max(1)
    });
    let time = music.time_signature_events.first();
    let signature = time.map_or_else(
        || "4/4".to_owned(),
        |event| format!("{}/{}", event.numerator, event.denominator),
    );
    format!(
        "高音谱号 · {key} · {signature} · {bpm} BPM · {} 个音符 · 每格 1 拍",
        music.notes.len()
    )
}

/// 音名图例（按起点排序）。
#[must_use]
pub fn staff_legend(music: &MusicConfig) -> String {
    let mut notes = music.notes.clone();
    notes.sort_by_key(|note| (note.start_tick, note.pitch));
    notes
        .iter()
        .take(24)
        .map(|note| note_label(music, note.pitch))
        .collect::<Vec<_>>()
        .join(" ")
}

/// 低音谱号（切换用）。
#[must_use]
pub fn clef_name(clef: i64) -> &'static str {
    if clef == 1 {
        "低音谱号"
    } else {
        "高音谱号"
    }
}

/// 供测试直接取谱表底部基准。
#[must_use]
pub fn bottom_diatonic(clef: i64) -> i64 {
    clef_bottom_diatonic(clef)
}

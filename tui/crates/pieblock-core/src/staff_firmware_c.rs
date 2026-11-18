//! 把 [`StaffSongData`] 发射成固件侧 C 数据表（主点阵 + SoA 事件表 + StaffSong）。
//!
//! 与 `staff_firmware_c.dart` 对齐；C 结构体定义见
//! `stc32g_sdcc/libraries/boards/inc/StaffRender.h`。

use crate::staff_glyphs::staff_glyph_list;
use crate::staff_notation::{StaffEventData, StaffSongData};

/// 字形在 C 侧枚举中的顺序必须与 `StaffGlyphId` 一致。
pub const STAFF_FIRMWARE_GLYPH_COUNT: usize = 22;

/// 事件 flags 布局：bit0-1 临时记号，bit2 谱号，bit3-7 时值编码。
#[must_use]
pub fn staff_firmware_flags(event: &StaffEventData) -> i64 {
    (event.accidental & 0x3) | ((event.clef & 0x1) << 2) | ((event.note_value.code & 0x1f) << 3)
}

fn hex_value(value: i64, width: usize) -> String {
    format!("0x{:0width$X}", value, width = width)
}

fn rows_table(name: &str, values: &[i64], per_line: usize) -> String {
    let mut output = format!("static const uint16_t {name}[] =\n{{\n");
    let mut index = 0;
    while index < values.len() {
        let end = (index + per_line).min(values.len());
        output.push_str("    ");
        output.push_str(
            &values[index..end]
                .iter()
                .map(|value| hex_value(*value, 4))
                .collect::<Vec<_>>()
                .join(", "),
        );
        if end < values.len() {
            output.push(',');
        }
        output.push('\n');
        index = end;
    }
    output.push_str("};\n");
    output
}

fn u8_table(name: &str, values: &[i64], per_line: usize) -> String {
    let mut output = format!("static const uint8_t {name}[] =\n{{\n");
    let mut index = 0;
    while index < values.len() {
        let end = (index + per_line).min(values.len());
        output.push_str("    ");
        output.push_str(
            &values[index..end]
                .iter()
                .map(|value| hex_value(*value, 2))
                .collect::<Vec<_>>()
                .join(", "),
        );
        if end < values.len() {
            output.push(',');
        }
        output.push('\n');
        index = end;
    }
    output.push_str("};\n");
    output
}

fn i8_table(name: &str, values: &[i64], per_line: usize) -> String {
    let mut output = format!("static const int8_t {name}[] =\n{{\n");
    let mut index = 0;
    while index < values.len() {
        let end = (index + per_line).min(values.len());
        output.push_str("    ");
        output.push_str(
            &values[index..end]
                .iter()
                .map(|value| {
                    if *value < 0 {
                        format!("-{}", hex_value(-value, 2))
                    } else {
                        hex_value(*value, 2)
                    }
                })
                .collect::<Vec<_>>()
                .join(", "),
        );
        if end < values.len() {
            output.push(',');
        }
        output.push('\n');
        index = end;
    }
    output.push_str("};\n");
    output
}

fn u32_table(name: &str, values: &[i64], per_line: usize) -> String {
    let mut output = format!("static const uint32_t {name}[] =\n{{\n");
    let mut index = 0;
    while index < values.len() {
        let end = (index + per_line).min(values.len());
        output.push_str("    ");
        output.push_str(
            &values[index..end]
                .iter()
                .map(|value| format!("{value}UL"))
                .collect::<Vec<_>>()
                .join(", "),
        );
        if end < values.len() {
            output.push(',');
        }
        output.push('\n');
        index = end;
    }
    output.push_str("};\n");
    output
}

/// 发射完整 C 数据表；`prefix` 用于区分多个场景（如 `staff` / `fixtureTwinkle`）。
#[must_use]
pub fn emit_staff_firmware_tables(
    song: &StaffSongData,
    prefix: &str,
    include_comment: bool,
) -> String {
    let glyphs = staff_glyph_list();
    let mut glyph_rows: Vec<i64> = Vec::new();
    let mut descriptors: Vec<String> = Vec::new();
    for glyph in glyphs {
        let height = glyph.height();
        let width = glyph.width();
        let row_offset = glyph_rows.len();
        glyph_rows.extend(glyph.row_bits().into_iter().map(i64::from));
        descriptors.push(format!("    {{{width}, {height}, {row_offset}}}"));
    }
    let events = &song.events;
    let count = events.len();
    let safe_count = if count == 0 { 1 } else { count };
    let tick_durations: Vec<i64> = if events.is_empty() {
        vec![0]
    } else {
        events.iter().map(|event| event.tick_duration).collect()
    };
    let durations_ms: Vec<i64> = if events.is_empty() {
        vec![1]
    } else {
        events.iter().map(|event| event.duration_ms).collect()
    };
    let pitches: Vec<i64> = if events.is_empty() {
        vec![0]
    } else {
        events.iter().map(|event| event.pitch).collect()
    };
    let flags: Vec<i64> = if events.is_empty() {
        vec![0]
    } else {
        events.iter().map(staff_firmware_flags).collect()
    };
    let steps: Vec<i64> = if events.is_empty() {
        vec![0]
    } else {
        events.iter().map(|event| event.step).collect()
    };
    let key_steps_treble: Vec<i64> = if song.key_steps_treble.is_empty() {
        vec![0]
    } else {
        song.key_steps_treble.clone()
    };
    let key_steps_bass: Vec<i64> = if song.key_steps_bass.is_empty() {
        vec![0]
    } else {
        song.key_steps_bass.clone()
    };
    let upper_prefix = prefix.to_uppercase();
    let mut output = String::new();
    if include_comment {
        output.push_str("/* ---- 五线谱显示数据（由 Pie-Block 代码生成器自动生成）---- */\n");
    }
    output.push_str(&format!("#define {upper_prefix}_EVENT_COUNT {count}\n"));
    output.push_str(&format!(
        "#define {upper_prefix}_GLYPH_COUNT {STAFF_FIRMWARE_GLYPH_COUNT}\n"
    ));
    output.push_str(&format!(
        "#define {upper_prefix}_KEY_COUNT {}\n",
        song.key_count()
    ));
    output.push_str(&format!(
        "#define {upper_prefix}_EVENT_STORAGE {safe_count}\n"
    ));
    output.push('\n');
    output.push_str(&rows_table(&format!("{prefix}GlyphRows"), &glyph_rows, 12));
    output.push('\n');
    output.push_str(&format!(
        "static const StaffGlyph {prefix}GlyphDescs[] =\n{{\n{}\n}};\n",
        descriptors.join(",\n")
    ));
    output.push('\n');
    output.push_str(&format!(
        "static const StaffGlyphSet {prefix}GlyphSet =\n    {{{STAFF_FIRMWARE_GLYPH_COUNT}, {prefix}GlyphRows, {prefix}GlyphDescs}};\n"
    ));
    output.push('\n');
    output.push_str(&u32_table(
        &format!("{prefix}TickDurations"),
        &tick_durations,
        8,
    ));
    output.push('\n');
    output.push_str(&u32_table(
        &format!("{prefix}DurationsMs"),
        &durations_ms,
        8,
    ));
    output.push('\n');
    output.push_str(&u8_table(&format!("{prefix}Pitches"), &pitches, 16));
    output.push('\n');
    output.push_str(&u8_table(&format!("{prefix}Flags"), &flags, 16));
    output.push('\n');
    output.push_str(&i8_table(&format!("{prefix}Steps"), &steps, 16));
    output.push('\n');
    output.push_str(&i8_table(
        &format!("{prefix}KeyStepsTreble"),
        &key_steps_treble,
        16,
    ));
    output.push('\n');
    output.push_str(&i8_table(
        &format!("{prefix}KeyStepsBass"),
        &key_steps_bass,
        16,
    ));
    output.push('\n');
    output.push_str(&format!("static const StaffSong {prefix}Song =\n{{\n"));
    output.push_str(&format!("    {count},\n"));
    output.push_str(&format!("    {},\n", song.ticks_per_quarter));
    output.push_str(&format!("    {},\n", song.time_numerator));
    output.push_str(&format!("    {},\n", song.time_denominator));
    output.push_str(&format!("    {},\n", song.key_count()));
    output.push_str(&format!(
        "    {},\n",
        if song.key_is_sharp() { 1 } else { 0 }
    ));
    output.push_str(&format!("    {prefix}TickDurations,\n"));
    output.push_str(&format!("    {prefix}DurationsMs,\n"));
    output.push_str(&format!("    {prefix}Pitches,\n"));
    output.push_str(&format!("    {prefix}Steps,\n"));
    output.push_str(&format!("    {prefix}Flags,\n"));
    output.push_str(&format!("    {prefix}KeyStepsTreble,\n"));
    output.push_str(&format!("    {prefix}KeyStepsBass,\n"));
    output.push_str(&format!("    &{prefix}GlyphSet\n"));
    output.push_str("};\n");
    output
}

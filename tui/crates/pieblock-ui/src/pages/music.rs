//! 音乐工程向导页：节拍/调号/速度/拍号与重叠策略。

use pieblock_core::model::{MusicConfig, MusicOverlapMode, ProjectConfig};

use crate::form::{Choice, FieldKind, FieldValue, FormField, FormPage};

const OVERLAP_CHOICES: [Choice; 3] = [
    Choice {
        value: "highest",
        label: "最高音",
    },
    Choice {
        value: "lowest",
        label: "最低音",
    },
    Choice {
        value: "nearest",
        label: "最近音",
    },
];

const DENOMINATOR_CHOICES: [Choice; 5] = [
    Choice {
        value: "1",
        label: "1（全音符）",
    },
    Choice {
        value: "2",
        label: "2（二分）",
    },
    Choice {
        value: "4",
        label: "4（四分）",
    },
    Choice {
        value: "8",
        label: "8（八分）",
    },
    Choice {
        value: "16",
        label: "16（十六分）",
    },
];

fn music_of(config: &ProjectConfig) -> Option<&MusicConfig> {
    match config {
        ProjectConfig::Music(value) => Some(value),
        _ => None,
    }
}

fn music_mut(config: &mut ProjectConfig) -> Option<&mut MusicConfig> {
    match config {
        ProjectConfig::Music(value) => Some(value),
        _ => None,
    }
}

fn bpm(config: &ProjectConfig) -> i64 {
    music_of(config)
        .and_then(|music| music.tempo_events.first())
        .map_or(120, |event| {
            (60_000_000 / event.microseconds_per_quarter.max(1)).clamp(1, 400)
        })
}

/// 音乐工程元信息页。
#[must_use]
pub fn music_page(_config: &ProjectConfig) -> FormPage {
    let mut fields: Vec<FormField> = Vec::new();
    fields.push(FormField {
        id: "music.source_name",
        path: "music.source_name",
        label: "源文件名称".to_owned(),
        help: "导入的 MIDI/工程来源名称（仅用于显示与审查）。",
        kind: FieldKind::Text {
            max_len: 64,
            placeholder: "（未设置）",
        },
        get: Box::new(|config| {
            FieldValue::Text(
                music_of(config)
                    .and_then(|music| music.source_name.clone())
                    .unwrap_or_default(),
            )
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Text(text)) = (music_mut(config), value) {
                let text = text.trim();
                music.source_name = if text.is_empty() {
                    None
                } else {
                    Some(text.to_owned())
                };
            }
        }),
    });
    fields.push(FormField {
        id: "music.track_name",
        path: "music.track_name",
        label: "音轨名称".to_owned(),
        help: "导入时选择的 MIDI 音轨名称。",
        kind: FieldKind::Text {
            max_len: 64,
            placeholder: "（未设置）",
        },
        get: Box::new(|config| {
            FieldValue::Text(
                music_of(config)
                    .and_then(|music| music.track_name.clone())
                    .unwrap_or_default(),
            )
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Text(text)) = (music_mut(config), value) {
                let text = text.trim();
                music.track_name = if text.is_empty() {
                    None
                } else {
                    Some(text.to_owned())
                };
            }
        }),
    });
    fields.push(FormField {
        id: "music.ticks_per_quarter",
        path: "music.ticks_per_quarter",
        label: "每四分音符 tick".to_owned(),
        help: "MIDI 时间分辨率，范围 96–960；改变会缩放音符时间。",
        kind: FieldKind::Number {
            min: 96,
            max: 960,
            step: 24,
            unit: "tick",
        },
        get: Box::new(|config| {
            FieldValue::Int(music_of(config).map_or(480, |music| music.ticks_per_quarter))
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Int(number)) = (music_mut(config), value) {
                music.ticks_per_quarter = number;
            }
        }),
    });
    fields.push(FormField {
        id: "music.key_signature_fifths",
        path: "music.key_signature_fifths",
        label: "调号（五度圈）".to_owned(),
        help: "负数为降号、正数为升号，范围 -7–7；0 为 C 大调。",
        kind: FieldKind::Number {
            min: -7,
            max: 7,
            step: 1,
            unit: "",
        },
        get: Box::new(|config| {
            FieldValue::Int(music_of(config).map_or(0, |music| music.key_signature_fifths))
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Int(number)) = (music_mut(config), value) {
                music.key_signature_fifths = number;
            }
        }),
    });
    fields.push(FormField {
        id: "music.overlap_mode",
        path: "music.overlap_mode",
        label: "重叠处理".to_owned(),
        help: "同 tick 上多个音符时选择发声策略：最高音/最低音/最近音。",
        kind: FieldKind::Choice(&OVERLAP_CHOICES),
        get: Box::new(|config| {
            FieldValue::Choice(if let Some(music) = music_of(config) {
                match music.overlap_mode {
                    MusicOverlapMode::Highest => "highest",
                    MusicOverlapMode::Lowest => "lowest",
                    MusicOverlapMode::Nearest => "nearest",
                }
                .to_owned()
            } else {
                String::new()
            })
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Choice(choice)) = (music_mut(config), value) {
                music.overlap_mode = match choice.as_str() {
                    "highest" => MusicOverlapMode::Highest,
                    "lowest" => MusicOverlapMode::Lowest,
                    _ => MusicOverlapMode::Nearest,
                };
            }
        }),
    });
    fields.push(FormField {
        id: "music.new_note_interrupts",
        path: "music.new_note_interrupts",
        label: "新音符打断".to_owned(),
        help: "启用后新音符立即打断当前发声，否则等待当前音符结束。",
        kind: FieldKind::Toggle,
        get: Box::new(|config| {
            FieldValue::Bool(music_of(config).is_none_or(|music| music.new_note_interrupts))
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Bool(flag)) = (music_mut(config), value) {
                music.new_note_interrupts = flag;
            }
        }),
    });
    fields.push(FormField {
        id: "music.tempo_events.0.microseconds_per_quarter",
        path: "music.tempo_events.0.microseconds_per_quarter",
        label: "速度 BPM".to_owned(),
        help: "起始速度（每分钟四分音符数），范围 20–400；保存为微秒/四分音符。",
        kind: FieldKind::Number {
            min: 20,
            max: 400,
            step: 1,
            unit: "BPM",
        },
        get: Box::new(|config| FieldValue::Int(bpm(config))),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Int(number)) = (music_mut(config), value) {
                let microseconds = (60_000_000 / number.max(1)).max(1);
                if let Some(event) = music.tempo_events.first_mut() {
                    event.tick = 0;
                    event.microseconds_per_quarter = microseconds;
                } else {
                    music.tempo_events.push(pieblock_core::model::TempoEvent {
                        tick: 0,
                        microseconds_per_quarter: microseconds,
                    });
                }
            }
        }),
    });
    fields.push(FormField {
        id: "music.time_signature_events.0.numerator",
        path: "music.time_signature_events.0.numerator",
        label: "拍号分子".to_owned(),
        help: "每小节拍数，范围 1–16。",
        kind: FieldKind::Number {
            min: 1,
            max: 16,
            step: 1,
            unit: "",
        },
        get: Box::new(|config| {
            FieldValue::Int(
                music_of(config)
                    .and_then(|music| music.time_signature_events.first())
                    .map_or(4, |event| event.numerator),
            )
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Int(number)) = (music_mut(config), value) {
                if let Some(event) = music.time_signature_events.first_mut() {
                    event.numerator = number;
                }
            }
        }),
    });
    fields.push(FormField {
        id: "music.time_signature_events.0.denominator",
        path: "music.time_signature_events.0.denominator",
        label: "拍号分母".to_owned(),
        help: "以几分音符为一拍：1/2/4/8/16。",
        kind: FieldKind::Choice(&DENOMINATOR_CHOICES),
        get: Box::new(|config| {
            FieldValue::Choice(
                music_of(config)
                    .and_then(|music| music.time_signature_events.first())
                    .map_or("4".to_owned(), |event| event.denominator.to_string()),
            )
        }),
        set: Box::new(|config, value| {
            if let (Some(music), FieldValue::Choice(choice)) = (music_mut(config), value) {
                if let (Ok(denominator), Some(event)) = (
                    choice.parse::<i64>(),
                    music.time_signature_events.first_mut(),
                ) {
                    event.denominator = denominator;
                }
            }
        }),
    });
    fields.push(FormField {
        id: "music.overlaps",
        path: "music.overlaps",
        label: "重叠提示".to_owned(),
        help: "只读：同 tick 多音符的重叠处数，按上方「重叠处理」策略只发声一个。",
        kind: FieldKind::Number {
            min: 0,
            max: 100_000,
            step: 1,
            unit: "处",
        },
        get: Box::new(|config| {
            FieldValue::Int(music_of(config).map_or(0, |music| {
                pieblock_core::MusicTimeline::overlap_count(music)
            }))
        }),
        set: Box::new(|_config, _value| {}),
    });
    fields.push(FormField {
        id: "music.notes",
        path: "music.notes",
        label: "音符数量".to_owned(),
        help: "只读：具体音符在下一步「钢琴卷帘」编辑（M6 进行中）。",
        kind: FieldKind::Number {
            min: 0,
            max: 100_000,
            step: 1,
            unit: "个",
        },
        get: Box::new(|config| {
            FieldValue::Int(music_of(config).map_or(0, |music| music.notes.len() as i64))
        }),
        set: Box::new(|_config, _value| {}),
    });
    FormPage {
        id: "music",
        title: "音乐工程：节拍与调号",
        subtitle: "设置时间分辨率、调号、拇指重叠处理、速度与拍号；音符编辑在钢琴卷帘页。",
        fields,
    }
}

//! 调试模式提示音曲谱（与 `debug_cues.dart` 对齐）。
//!
//! 固件代码生成与 TUI 试听共用同一份数据；这里先提供生成器需要的常量与
//! 步序映射，试听播放留到 M3/M6。

/// 提示音里的一段音；频率为 `None` 表示静音间隔。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct DebugCueNote {
    pub frequency_hz: Option<i64>,
    pub duration_ms: i64,
}

/// 调试提示音常量。
pub struct DebugCues;

impl DebugCues {
    /// 单个音区覆盖的项数，也是上行音型的音数。
    pub const ZONE_SPAN: i64 = 5;
    pub const NOTE_C5: i64 = 523;
    pub const NOTE_E5: i64 = 659;
    pub const NOTE_G5: i64 = 784;
    pub const NOTE_C6: i64 = 1047;
    pub const NOTE_E6: i64 = 1319;
    pub const NOTE_G6: i64 = 1568;
    pub const NOTE_C7: i64 = 2093;
    pub const NOTE_E7: i64 = 2637;
    pub const ASCENT_LOW: [i64; 5] = [
        Self::NOTE_C6,
        Self::NOTE_E6,
        Self::NOTE_G6,
        Self::NOTE_C7,
        Self::NOTE_E7,
    ];
    pub const ASCENT_HIGH: [i64; 5] = [Self::NOTE_C7, Self::NOTE_E7, 3136, 4186, 5274];
    pub const UNIT_MS: i64 = 220;
    pub const GAP_MS: i64 = 140;
    pub const SECTION_GAP_MS: i64 = 300;

    /// 第 `index` 项的步序提示（`index` 从 1 开始）。
    #[must_use]
    pub fn step(index: i64) -> Vec<DebugCueNote> {
        let offset = if index < 1 { 0 } else { index - 1 };
        let count = offset % Self::ZONE_SPAN + 1;
        let high = offset / Self::ZONE_SPAN != 0;
        let motif = if high {
            &Self::ASCENT_HIGH
        } else {
            &Self::ASCENT_LOW
        };
        let mut notes = Vec::new();
        for (index, frequency) in motif.iter().take(count as usize).enumerate() {
            notes.push(DebugCueNote {
                frequency_hz: Some(*frequency),
                duration_ms: Self::UNIT_MS,
            });
            if i64::try_from(index + 1).unwrap_or(0) < count {
                notes.push(DebugCueNote {
                    frequency_hz: None,
                    duration_ms: Self::GAP_MS,
                });
            }
        }
        notes
    }

    /// 曲线总时长（毫秒）。
    #[must_use]
    pub fn duration_ms(notes: &[DebugCueNote]) -> i64 {
        notes.iter().map(|note| note.duration_ms).sum()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn step_cues_match_dart_shape() {
        assert_eq!(DebugCues::step(1).len(), 1);
        assert_eq!(DebugCues::step(1)[0].frequency_hz, Some(DebugCues::NOTE_C6));
        assert_eq!(DebugCues::step(5).len(), 9);
        assert_eq!(DebugCues::duration_ms(&DebugCues::step(2)), 2 * 220 + 140);
        assert_eq!(DebugCues::step(6)[0].frequency_hz, Some(DebugCues::NOTE_C7));
    }
}

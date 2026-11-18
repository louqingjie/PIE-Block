//! 音乐时间轴：重叠裁决、发声区间、重叠计数、tick→微秒换算与蜂鸣器片段。
//!
//! 与 `packages/pieblock_core/lib/src/music.dart` 对齐；后续 MIDI 导入与五线谱
//! 固件生成也复用这里的结果。

use crate::model::{MusicConfig, MusicNote, MusicOverlapMode};

/// 单声部发声区间 `[startTick, endTick)`；重叠音符会被裁决，可能只保留一部分。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MusicSoundingSpan {
    pub note_id: String,
    pub pitch: i64,
    pub start_tick: i64,
    pub end_tick: i64,
}

impl MusicSoundingSpan {
    #[must_use]
    pub fn duration_ticks(&self) -> i64 {
        self.end_tick - self.start_tick
    }
}

/// 蜂鸣器片段：音高为 `None` 表示静音。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MusicSegment {
    pub pitch: Option<i64>,
    pub duration_ms: i64,
}

/// 音乐时间轴计算。
pub struct MusicTimeline;

impl MusicTimeline {
    /// 按重叠策略把合法音符裁决为单声部发声区间。
    #[must_use]
    pub fn sounding_spans(config: &MusicConfig) -> Vec<MusicSoundingSpan> {
        let notes = playable_notes(config);
        let mut spans: Vec<MusicSoundingSpan> = Vec::new();
        let mut sounding: Option<usize> = None; // 在 notes 中的索引
        let mut effective_pitch: Option<i64> = None;
        let mut index = 0;
        while index < notes.len() {
            let tick = notes[index].start_tick;
            let mut group: Vec<usize> = Vec::new();
            while index < notes.len() && notes[index].start_tick == tick {
                group.push(index);
                index += 1;
            }
            if let Some(current) = sounding {
                if tick >= end_tick(&notes[current]) {
                    sounding = None;
                }
            }
            let reference = sounding
                .map(|current| notes[current].pitch)
                .or(effective_pitch);
            let pick = Self::pick(&notes, &group, config.overlap_mode, reference);
            let mut winner: Option<usize> = None;
            match (sounding, pick) {
                (None, Some(pick)) => winner = Some(pick),
                (Some(_), Some(pick)) => {
                    if config.new_note_interrupts {
                        winner = Some(pick);
                    } else if let Some(current) = sounding {
                        if Self::beats(
                            &notes[pick],
                            &notes[current],
                            config.overlap_mode,
                            effective_pitch.unwrap_or(notes[current].pitch),
                        ) {
                            winner = Some(pick);
                        }
                    }
                }
                (_, None) => {}
            }
            let Some(winner) = winner else {
                continue;
            };
            if let Some(current) = sounding {
                if !spans.is_empty() {
                    let last = spans.pop().expect("span exists");
                    if tick > last.start_tick {
                        spans.push(MusicSoundingSpan {
                            note_id: last.note_id,
                            pitch: last.pitch,
                            start_tick: last.start_tick,
                            end_tick: tick,
                        });
                    }
                    let _ = current;
                }
            }
            spans.push(MusicSoundingSpan {
                note_id: notes[winner].id.clone(),
                pitch: notes[winner].pitch,
                start_tick: tick,
                end_tick: end_tick(&notes[winner]),
            });
            sounding = Some(winner);
            effective_pitch = Some(notes[winner].pitch);
        }
        spans
    }

    /// 重叠处数：同时活动音符数 ≥ 2 的极大 tick 区间个数。
    #[must_use]
    pub fn overlap_count(config: &MusicConfig) -> i64 {
        let notes = playable_notes(config);
        if notes.len() < 2 {
            return 0;
        }
        let mut events: Vec<(i64, i64)> = Vec::new();
        for note in &notes {
            events.push((note.start_tick, 1));
            events.push((end_tick(note), -1));
        }
        events.sort_by(|a, b| a.0.cmp(&b.0).then(a.1.cmp(&b.1)));
        let mut active = 0;
        let mut count = 0;
        let mut overlapping = false;
        let mut index = 0;
        while index < events.len() {
            let tick = events[index].0;
            while index < events.len() && events[index].0 == tick {
                active += events[index].1;
                index += 1;
            }
            if active >= 2 {
                if !overlapping {
                    count += 1;
                    overlapping = true;
                }
            } else {
                overlapping = false;
            }
        }
        count
    }

    /// 某 tick 对应的微秒数（考虑速度事件）。
    #[must_use]
    pub fn microseconds_at_tick(config: &MusicConfig, tick: i64) -> i64 {
        let mut events = config.tempo_events.clone();
        events.sort_by_key(|event| event.tick);
        let mut cursor = 0;
        let mut tempo = events
            .first()
            .map_or(500_000, |event| event.microseconds_per_quarter);
        let mut total = 0.0;
        for event in &events {
            if event.tick <= 0 {
                tempo = event.microseconds_per_quarter;
                continue;
            }
            if event.tick >= tick {
                break;
            }
            total += (event.tick - cursor) as f64 * tempo as f64 / config.ticks_per_quarter as f64;
            cursor = event.tick;
            tempo = event.microseconds_per_quarter;
        }
        total +=
            (tick - cursor).clamp(0, tick) as f64 * tempo as f64 / config.ticks_per_quarter as f64;
        total.round() as i64
    }

    /// 匹配固件播放的蜂鸣器片段序列（相邻同音高自动合并）。
    #[must_use]
    pub fn segments(config: &MusicConfig) -> Vec<MusicSegment> {
        let mut result: Vec<MusicSegment> = Vec::new();
        let mut cursor_tick = 0;
        for span in Self::sounding_spans(config) {
            if span.start_tick > cursor_tick {
                append(
                    &mut result,
                    None,
                    Self::microseconds_at_tick(config, span.start_tick)
                        - Self::microseconds_at_tick(config, cursor_tick),
                );
            }
            append(
                &mut result,
                Some(span.pitch),
                Self::microseconds_at_tick(config, span.end_tick)
                    - Self::microseconds_at_tick(config, span.start_tick),
            );
            cursor_tick = span.end_tick;
        }
        result
    }

    fn pick(
        notes: &[MusicNote],
        group: &[usize],
        mode: MusicOverlapMode,
        reference: Option<i64>,
    ) -> Option<usize> {
        let mut best = *group.first()?;
        for candidate in &group[1..] {
            best = match mode {
                MusicOverlapMode::Highest => preferred_higher(notes, best, *candidate),
                MusicOverlapMode::Lowest => preferred_lower(notes, best, *candidate),
                MusicOverlapMode::Nearest => reference.map_or_else(
                    || preferred_higher(notes, best, *candidate),
                    |reference| preferred_nearer(notes, best, *candidate, reference),
                ),
            };
        }
        Some(best)
    }

    fn beats(
        candidate: &MusicNote,
        current: &MusicNote,
        mode: MusicOverlapMode,
        reference: i64,
    ) -> bool {
        match mode {
            MusicOverlapMode::Highest => candidate.pitch > current.pitch,
            MusicOverlapMode::Lowest => candidate.pitch < current.pitch,
            MusicOverlapMode::Nearest => {
                (candidate.pitch - reference).abs() < (current.pitch - reference).abs()
            }
        }
    }
}

fn end_tick(note: &MusicNote) -> i64 {
    note.start_tick + note.duration_ticks
}

fn playable_notes(config: &MusicConfig) -> Vec<MusicNote> {
    let mut notes: Vec<MusicNote> = config
        .notes
        .iter()
        .filter(|note| {
            note.start_tick >= 0 && note.duration_ticks > 0 && (1..=127).contains(&note.pitch)
        })
        .cloned()
        .collect();
    notes.sort_by(|a, b| {
        a.start_tick
            .cmp(&b.start_tick)
            .then(b.pitch.cmp(&a.pitch))
            .then(a.id.cmp(&b.id))
    });
    notes
}

fn preferred_higher(notes: &[MusicNote], a: usize, b: usize) -> usize {
    if notes[a].pitch != notes[b].pitch {
        return if notes[a].pitch > notes[b].pitch {
            a
        } else {
            b
        };
    }
    preferred_longer(notes, a, b)
}

fn preferred_lower(notes: &[MusicNote], a: usize, b: usize) -> usize {
    if notes[a].pitch != notes[b].pitch {
        return if notes[a].pitch < notes[b].pitch {
            a
        } else {
            b
        };
    }
    preferred_longer(notes, a, b)
}

fn preferred_nearer(notes: &[MusicNote], a: usize, b: usize, reference: i64) -> usize {
    let distance_a = (notes[a].pitch - reference).abs();
    let distance_b = (notes[b].pitch - reference).abs();
    if distance_a != distance_b {
        return if distance_a < distance_b { a } else { b };
    }
    preferred_higher(notes, a, b)
}

fn preferred_longer(notes: &[MusicNote], a: usize, b: usize) -> usize {
    if notes[a].duration_ticks != notes[b].duration_ticks {
        return if notes[a].duration_ticks > notes[b].duration_ticks {
            a
        } else {
            b
        };
    }
    if notes[a].id <= notes[b].id { a } else { b }
}

fn append(target: &mut Vec<MusicSegment>, pitch: Option<i64>, micros: i64) {
    let millis = (micros as f64 / 1000.0).round() as i64;
    let millis = millis.clamp(1, 0x7fff_ffff);
    if let Some(last) = target.last_mut() {
        if last.pitch == pitch {
            last.duration_ms += millis;
            return;
        }
    }
    target.push(MusicSegment {
        pitch,
        duration_ms: millis,
    });
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::model::MusicNote;

    fn note(id: &str, pitch: i64, start: i64, duration: i64) -> MusicNote {
        MusicNote {
            id: id.to_owned(),
            pitch,
            start_tick: start,
            duration_ticks: duration,
        }
    }

    fn config(notes: Vec<MusicNote>) -> MusicConfig {
        MusicConfig {
            notes,
            ..MusicConfig::default()
        }
    }

    #[test]
    fn overlap_count_groups_chords() {
        let config = config(vec![
            note("a", 60, 0, 100),
            note("b", 64, 0, 100),
            note("c", 67, 0, 100),
        ]);
        assert_eq!(MusicTimeline::overlap_count(&config), 1);
    }

    #[test]
    fn highest_wins_on_same_tick() {
        let mut config = config(vec![note("a", 60, 0, 100), note("b", 64, 0, 100)]);
        config.overlap_mode = MusicOverlapMode::Highest;
        assert_eq!(MusicTimeline::sounding_spans(&config).len(), 1);
        assert_eq!(MusicTimeline::sounding_spans(&config)[0].pitch, 64);
    }
}

//! MIDI 导入/导出（与 `midi_codec.dart` 对齐）。
//!
//! 支持 Format 0/1（不支持 Format 2 与 SMPTE）、running status、变速/拍号/调号
//! meta 事件；写出的文件固定为 Format 0 单轨道，供音乐工程导入与往返保存。

use std::collections::HashMap;

use crate::model::{MusicConfig, MusicNote, MusicOverlapMode, TempoEvent, TimeSignatureEvent};

/// MIDI 解析/选择错误；文案与 Dart `FormatException` 一致。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MidiError {
    pub message: String,
}

impl MidiError {
    fn new(message: &str) -> Self {
        Self {
            message: message.to_owned(),
        }
    }
}

impl std::fmt::Display for MidiError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for MidiError {}

/// MIDI 源音符（导入阶段的原始音高/通道/时值）。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct MidiSourceNote {
    pub pitch: i64,
    pub channel: i64,
    pub start_tick: i64,
    pub duration_ticks: i64,
}

impl MidiSourceNote {
    #[must_use]
    pub fn end_tick(&self) -> i64 {
        self.start_tick + self.duration_ticks
    }
}

/// 单个 MIDI 轨道。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MidiTrackData {
    pub name: String,
    pub notes: Vec<MidiSourceNote>,
}

impl MidiTrackData {
    #[must_use]
    pub fn melodic_note_count(&self) -> usize {
        self.notes.iter().filter(|note| note.channel != 9).count()
    }

    #[must_use]
    pub fn playable(&self) -> bool {
        self.melodic_note_count() > 0
    }

    #[must_use]
    pub fn polyphonic(&self) -> bool {
        let mut melodic: Vec<&MidiSourceNote> =
            self.notes.iter().filter(|note| note.channel != 9).collect();
        melodic.sort_by_key(|note| note.start_tick);
        let mut end = -1;
        for note in melodic {
            if note.start_tick < end {
                return true;
            }
            end = end.max(note.end_tick());
        }
        false
    }

    #[must_use]
    pub fn end_tick(&self) -> i64 {
        self.notes
            .iter()
            .map(MidiSourceNote::end_tick)
            .max()
            .unwrap_or(0)
    }
}

/// 解析后的 MIDI 文件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MidiFileData {
    pub format: i64,
    pub ticks_per_quarter: i64,
    pub key_signature_fifths: i64,
    pub tracks: Vec<MidiTrackData>,
    pub tempo_events: Vec<TempoEvent>,
    pub time_signature_events: Vec<TimeSignatureEvent>,
}

impl MidiFileData {
    /// 选择一条可播放轨道并生成音乐工程配置。
    pub fn select_track(
        &self,
        index: usize,
        source_name: Option<String>,
        overlap_mode: MusicOverlapMode,
        new_note_interrupts: bool,
    ) -> Result<MusicConfig, MidiError> {
        let Some(track) = self.tracks.get(index) else {
            return Err(MidiError::new("请选择包含旋律音符的 MIDI 轨道"));
        };
        if !track.playable() {
            return Err(MidiError::new("请选择包含旋律音符的 MIDI 轨道"));
        }
        let mut source: Vec<&MidiSourceNote> = track
            .notes
            .iter()
            .filter(|note| note.channel != 9)
            .collect();
        source.sort_by(|a, b| a.start_tick.cmp(&b.start_tick).then(b.pitch.cmp(&a.pitch)));
        let notes = source
            .iter()
            .enumerate()
            .map(|(serial, note)| MusicNote {
                id: format!("m{serial}"),
                pitch: note.pitch,
                start_tick: note.start_tick,
                duration_ticks: note.duration_ticks,
            })
            .collect();
        Ok(MusicConfig {
            ticks_per_quarter: self.ticks_per_quarter,
            source_name,
            track_name: Some(track.name.clone()),
            notes,
            overlap_mode,
            new_note_interrupts,
            tempo_events: if self.tempo_events.is_empty() {
                vec![TempoEvent {
                    tick: 0,
                    microseconds_per_quarter: 500_000,
                }]
            } else {
                self.tempo_events.clone()
            },
            key_signature_fifths: self.key_signature_fifths,
            time_signature_events: if self.time_signature_events.is_empty() {
                vec![TimeSignatureEvent {
                    tick: 0,
                    numerator: 4,
                    denominator: 4,
                }]
            } else {
                self.time_signature_events.clone()
            },
        })
    }
}

/// MIDI 编解码。
pub struct MidiCodec;

impl MidiCodec {
    pub fn parse(bytes: &[u8]) -> Result<MidiFileData, MidiError> {
        let mut reader = Reader::new(bytes);
        if reader.ascii(4)? != "MThd" {
            return Err(MidiError::new("不是标准 MIDI 文件"));
        }
        let header_length = reader.u32()?;
        if header_length < 6 {
            return Err(MidiError::new("MIDI 文件头损坏"));
        }
        let format = reader.u16()?;
        let track_count = reader.u16()?;
        let division = reader.u16()?;
        if format > 1 {
            return Err(MidiError::new("不支持 MIDI Format 2"));
        }
        if (division & 0x8000) != 0 {
            return Err(MidiError::new("不支持 SMPTE 时间格式"));
        }
        if division == 0 {
            return Err(MidiError::new("MIDI PPQ 不能为 0"));
        }
        reader.skip(header_length - 6)?;
        let mut tracks = Vec::new();
        let mut tempos: Vec<TempoEvent> = Vec::new();
        let mut meters: Vec<TimeSignatureEvent> = Vec::new();
        let mut key_signature_fifths = 0;
        let mut key_signature_found = false;
        for track_index in 0..track_count {
            if reader.ascii(4)? != "MTrk" {
                return Err(MidiError::new("MIDI 轨道块损坏"));
            }
            let track_length = reader.u32()?;
            let end = reader
                .position
                .saturating_add(usize::try_from(track_length).unwrap_or(usize::MAX));
            if end > reader.bytes.len() {
                return Err(MidiError::new("MIDI 轨道长度越界"));
            }
            let mut tick = 0;
            let mut running_status = 0_u8;
            let mut name = format!("轨道 {}", track_index + 1);
            let mut active: HashMap<u32, Vec<i64>> = HashMap::new();
            let mut notes: Vec<MidiSourceNote> = Vec::new();
            while reader.position < end {
                tick += reader.vlq()?;
                let mut status = reader.u8()?;
                if status < 0x80 {
                    if running_status == 0 {
                        return Err(MidiError::new("无效的 running status"));
                    }
                    reader.position -= 1;
                    status = running_status;
                } else if status < 0xf0 {
                    running_status = status;
                }
                if status == 0xff {
                    let meta_type = reader.u8()?;
                    let length = reader.vlq()?;
                    let data = reader.take(length as usize)?;
                    if meta_type == 0x03 {
                        name = String::from_utf8_lossy(&data).into_owned();
                    }
                    if meta_type == 0x51 && data.len() == 3 {
                        tempos.push(TempoEvent {
                            tick,
                            microseconds_per_quarter: (i64::from(data[0]) << 16)
                                | (i64::from(data[1]) << 8)
                                | i64::from(data[2]),
                        });
                    }
                    if meta_type == 0x59 && !data.is_empty() && !key_signature_found {
                        key_signature_fifths = if data[0] > 127 {
                            i64::from(data[0]) - 256
                        } else {
                            i64::from(data[0])
                        };
                        key_signature_found = true;
                    }
                    if meta_type == 0x58 && data.len() >= 2 {
                        meters.push(TimeSignatureEvent {
                            tick,
                            numerator: i64::from(data[0]),
                            denominator: 1_i64 << data[1],
                        });
                    }
                    continue;
                }
                if status == 0xf0 || status == 0xf7 {
                    let length = reader.vlq()?;
                    reader.skip(length)?;
                    continue;
                }
                if status >= 0xf0 {
                    let skip = match status {
                        0xf1 | 0xf3 => 1,
                        0xf2 => 2,
                        _ => 0,
                    };
                    reader.skip(skip)?;
                    continue;
                }
                let command = status & 0xf0;
                let channel = status & 0x0f;
                let a = reader.u8()?;
                let b = if command == 0xc0 || command == 0xd0 {
                    0
                } else {
                    reader.u8()?
                };
                if command == 0x90 && b > 0 {
                    active
                        .entry((u32::from(channel) << 8) | u32::from(a))
                        .or_default()
                        .push(tick);
                } else if command == 0x80 || (command == 0x90 && b == 0) {
                    let key = (u32::from(channel) << 8) | u32::from(a);
                    if let Some(starts) = active.get_mut(&key) {
                        if !starts.is_empty() {
                            let start = starts.remove(0);
                            if tick > start {
                                notes.push(MidiSourceNote {
                                    pitch: i64::from(a),
                                    channel: i64::from(channel),
                                    start_tick: start,
                                    duration_ticks: tick - start,
                                });
                            }
                        }
                    }
                }
            }
            reader.position = end;
            tracks.push(MidiTrackData { name, notes });
        }
        Ok(MidiFileData {
            format,
            ticks_per_quarter: division,
            key_signature_fifths,
            tempo_events: dedupe_tempo(tempos),
            time_signature_events: dedupe_meter(meters),
            tracks,
        })
    }

    #[must_use]
    pub fn write(config: &MusicConfig) -> Vec<u8> {
        let mut events: Vec<WriteEvent> = Vec::new();
        let name = config
            .track_name
            .clone()
            .unwrap_or_else(|| "PIE-Block Music".to_owned());
        let name_bytes = name.as_bytes();
        let mut name_event = vec![0xff, 0x03];
        name_event.extend(vlq(i64::try_from(name_bytes.len()).unwrap_or(0)));
        name_event.extend_from_slice(name_bytes);
        events.push(WriteEvent {
            tick: 0,
            priority: 0,
            bytes: name_event,
        });
        let key_fifths = config.key_signature_fifths.clamp(-7, 7);
        events.push(WriteEvent {
            tick: 0,
            priority: 0,
            bytes: vec![0xff, 0x59, 0x02, (key_fifths & 0xff) as u8, 0x00],
        });
        for tempo in &config.tempo_events {
            let value = tempo.microseconds_per_quarter;
            events.push(WriteEvent {
                tick: tempo.tick,
                priority: 0,
                bytes: vec![
                    0xff,
                    0x51,
                    0x03,
                    ((value >> 16) & 0xff) as u8,
                    ((value >> 8) & 0xff) as u8,
                    (value & 0xff) as u8,
                ],
            });
        }
        for meter in &config.time_signature_events {
            let mut exponent = 0_i64;
            let mut denominator = meter.denominator;
            while denominator > 1 && exponent < 30 {
                denominator >>= 1;
                exponent += 1;
            }
            events.push(WriteEvent {
                tick: meter.tick,
                priority: 0,
                bytes: vec![
                    0xff,
                    0x58,
                    0x04,
                    meter.numerator as u8,
                    exponent as u8,
                    24,
                    8,
                ],
            });
        }
        for note in &config.notes {
            events.push(WriteEvent {
                tick: note.start_tick,
                priority: 2,
                bytes: vec![0x90, note.pitch as u8, 100],
            });
            events.push(WriteEvent {
                tick: note.start_tick + note.duration_ticks,
                priority: 1,
                bytes: vec![0x80, note.pitch as u8, 0],
            });
        }
        events.sort_by_key(|event| (event.tick, event.priority));
        let mut track: Vec<u8> = Vec::new();
        let mut previous_tick = 0;
        for event in &events {
            track.extend(vlq(event.tick - previous_tick));
            track.extend_from_slice(&event.bytes);
            previous_tick = event.tick;
        }
        track.extend_from_slice(&[0, 0xff, 0x2f, 0]);
        let mut output = Vec::new();
        output.extend_from_slice(b"MThd");
        output.extend(u32_bytes(6));
        output.extend_from_slice(&[0, 0, 0, 1]);
        output.extend_from_slice(&[
            ((config.ticks_per_quarter >> 8) & 0xff) as u8,
            (config.ticks_per_quarter & 0xff) as u8,
        ]);
        output.extend_from_slice(b"MTrk");
        output.extend(u32_bytes(i64::try_from(track.len()).unwrap_or(0)));
        output.extend(track);
        output
    }
}

struct WriteEvent {
    tick: i64,
    priority: i64,
    bytes: Vec<u8>,
}

fn dedupe_tempo(source: Vec<TempoEvent>) -> Vec<TempoEvent> {
    let mut values: std::collections::BTreeMap<i64, TempoEvent> = std::collections::BTreeMap::new();
    for event in source {
        values.insert(event.tick, event);
    }
    values.into_values().collect()
}

fn dedupe_meter(source: Vec<TimeSignatureEvent>) -> Vec<TimeSignatureEvent> {
    let mut values: std::collections::BTreeMap<i64, TimeSignatureEvent> =
        std::collections::BTreeMap::new();
    for event in source {
        values.insert(event.tick, event);
    }
    values.into_values().collect()
}

fn u32_bytes(value: i64) -> [u8; 4] {
    [
        ((value >> 24) & 0xff) as u8,
        ((value >> 16) & 0xff) as u8,
        ((value >> 8) & 0xff) as u8,
        (value & 0xff) as u8,
    ]
}

fn vlq(mut value: i64) -> Vec<u8> {
    let mut buffer = value & 0x7f;
    let mut bytes = Vec::new();
    while {
        value >>= 7;
        value > 0
    } {
        buffer <<= 8;
        buffer |= (value & 0x7f) | 0x80;
    }
    loop {
        bytes.push((buffer & 0xff) as u8);
        if (buffer & 0x80) == 0 {
            break;
        }
        buffer >>= 8;
    }
    bytes
}

struct Reader<'a> {
    bytes: &'a [u8],
    position: usize,
}

impl<'a> Reader<'a> {
    fn new(bytes: &'a [u8]) -> Self {
        Self { bytes, position: 0 }
    }

    fn u8(&mut self) -> Result<u8, MidiError> {
        if self.position >= self.bytes.len() {
            return Err(MidiError::new("MIDI 文件意外结束"));
        }
        let value = self.bytes[self.position];
        self.position += 1;
        Ok(value)
    }

    fn u16(&mut self) -> Result<i64, MidiError> {
        Ok((i64::from(self.u8()?) << 8) | i64::from(self.u8()?))
    }

    fn u32(&mut self) -> Result<i64, MidiError> {
        Ok((i64::from(self.u8()?) << 24)
            | (i64::from(self.u8()?) << 16)
            | (i64::from(self.u8()?) << 8)
            | i64::from(self.u8()?))
    }

    fn ascii(&mut self, count: usize) -> Result<String, MidiError> {
        let data = self.take(count)?;
        Ok(String::from_utf8_lossy(&data).into_owned())
    }

    fn take(&mut self, count: usize) -> Result<Vec<u8>, MidiError> {
        if self.position + count > self.bytes.len() {
            return Err(MidiError::new("MIDI 数据长度越界"));
        }
        let value = self.bytes[self.position..self.position + count].to_vec();
        self.position += count;
        Ok(value)
    }

    fn skip(&mut self, count: i64) -> Result<(), MidiError> {
        let count = usize::try_from(count).map_err(|_| MidiError::new("MIDI 数据长度越界"))?;
        self.take(count).map(|_| ())
    }

    fn vlq(&mut self) -> Result<i64, MidiError> {
        let mut value = 0_i64;
        for _ in 0..4 {
            let byte = self.u8()?;
            value = (value << 7) | i64::from(byte & 0x7f);
            if (byte & 0x80) == 0 {
                return Ok(value);
            }
        }
        Err(MidiError::new("MIDI VLQ 超过四字节"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn vlq_roundtrip_small_numbers() {
        assert_eq!(vlq(0), vec![0]);
        assert_eq!(vlq(127), vec![0x7f]);
        assert_eq!(vlq(128), vec![0x81, 0x00]);
    }

    #[test]
    fn header_errors_match_dart() {
        let error = MidiCodec::parse(b"nope").expect_err("bad header");
        assert_eq!(error.message, "不是标准 MIDI 文件");
    }
}

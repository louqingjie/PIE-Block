//! MIDI golden：写出字节逐字节、解析结构、错误文案与 Dart 一致。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::ProjectDocument;
use pieblock_core::midi::{MidiCodec, MidiFileData};
use pieblock_core::model::{MusicConfig, MusicOverlapMode, ProjectConfig};
use serde_json::{Map, Value, json};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/midi/midi.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("midi golden json")
}

fn decode_hex(text: &str) -> Vec<u8> {
    (0..text.len())
        .step_by(2)
        .map(|index| u8::from_str_radix(&text[index..index + 2], 16).expect("hex"))
        .collect()
}

fn encode_hex(bytes: &[u8]) -> String {
    bytes.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[test]
fn midi_write_matches_dart_byte_for_byte() {
    let golden = golden();
    let cases = golden["writeCases"].as_array().expect("writeCases");
    assert_eq!(cases.len(), 3);
    for case in cases {
        let name = case["name"].as_str().unwrap_or("?");
        let document = ProjectDocument::from_json(&case["document"])
            .unwrap_or_else(|error| panic!("{name}: document: {error}"));
        let ProjectConfig::Music(config) = &document.config else {
            panic!("{name}: not music config");
        };
        assert_eq!(
            encode_hex(&MidiCodec::write(config)),
            case["hex"].as_str().expect("hex"),
            "{name}: write bytes mismatch"
        );
    }
}

#[test]
fn midi_parse_matches_dart() {
    let golden = golden();
    let cases = golden["parseCases"].as_array().expect("parseCases");
    let mut checked = 0;
    for case in cases {
        let name = case["name"].as_str().unwrap_or("?");
        let bytes = decode_hex(case["hex"].as_str().expect("hex"));
        let result = MidiCodec::parse(&bytes);
        if let Some(expected_error) = case["error"].as_str() {
            let error = result.expect_err("expected parse error");
            assert_eq!(error.message, expected_error, "{name}: error message");
            checked += 1;
            continue;
        }
        let parsed = result.unwrap_or_else(|error| panic!("{name}: {error}"));
        assert_eq!(
            parse_result_json(&parsed),
            case_without(case, &["name", "hex"]),
            "{name}: parsed structure mismatch"
        );
        checked += 1;
    }
    assert_eq!(checked, cases.len());
}

fn parse_result_json(parsed: &MidiFileData) -> Value {
    let mut selected_track: Option<Value> = None;
    for (index, track) in parsed.tracks.iter().enumerate() {
        if track.playable() {
            let config = parsed
                .select_track(index, None, MusicOverlapMode::Nearest, true)
                .expect("select playable track");
            selected_track = Some(config.to_json());
            break;
        }
    }
    let mut map = Map::new();
    map.insert("format".to_owned(), Value::from(parsed.format));
    map.insert(
        "ticksPerQuarter".to_owned(),
        Value::from(parsed.ticks_per_quarter),
    );
    map.insert(
        "keySignatureFifths".to_owned(),
        Value::from(parsed.key_signature_fifths),
    );
    map.insert(
        "tracks".to_owned(),
        Value::Array(
            parsed
                .tracks
                .iter()
                .map(|track| {
                    json!({
                        "name": track.name,
                        "melodicNoteCount": track.melodic_note_count(),
                        "playable": track.playable(),
                        "polyphonic": track.polyphonic(),
                        "endTick": track.end_tick(),
                        "notes": track.notes.iter().map(|note| json!({
                            "pitch": note.pitch,
                            "channel": note.channel,
                            "startTick": note.start_tick,
                            "durationTicks": note.duration_ticks,
                        })).collect::<Vec<_>>(),
                    })
                })
                .collect(),
        ),
    );
    map.insert(
        "tempoEvents".to_owned(),
        Value::Array(
            parsed
                .tempo_events
                .iter()
                .map(|event| {
                    json!({
                        "tick": event.tick,
                        "microsecondsPerQuarter": event.microseconds_per_quarter,
                    })
                })
                .collect(),
        ),
    );
    map.insert(
        "timeSignatureEvents".to_owned(),
        Value::Array(
            parsed
                .time_signature_events
                .iter()
                .map(|event| {
                    json!({
                        "tick": event.tick,
                        "numerator": event.numerator,
                        "denominator": event.denominator,
                    })
                })
                .collect(),
        ),
    );
    if let Some(selected_track) = selected_track {
        map.insert("selectedTrack".to_owned(), selected_track);
    }
    Value::Object(map)
}

fn case_without(case: &Value, keys: &[&str]) -> Value {
    let mut map = case.as_object().expect("case object").clone();
    for key in keys {
        map.remove(*key);
    }
    Value::Object(map)
}

#[test]
fn midi_helpers_behave_like_dart() {
    let golden = golden();
    let case = golden["writeCases"]
        .as_array()
        .expect("writeCases")
        .iter()
        .find(|case| case["name"] == "music_synthetic")
        .expect("synthetic case");
    let document = ProjectDocument::from_json(&case["document"]).expect("document");
    let ProjectConfig::Music(config) = &document.config else {
        panic!("music");
    };
    let local: &MusicConfig = config;
    assert_eq!(local.overlap_mode, MusicOverlapMode::Highest);
    assert!(!local.new_note_interrupts);
    assert_eq!(local.key_signature_fifths, -3);
}

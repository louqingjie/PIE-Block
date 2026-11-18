//! HID golden：帧/报告/块映射固定向量 + 脚本化假设备下的烧录事件序列。

use std::collections::VecDeque;
use std::fs;
use std::path::{Path, PathBuf};

use pieblock_hid::HidFlasher;
use pieblock_hid::flasher::{FlashEvent, FlashOptions};
use pieblock_hid::protocol::HidProtocol;
use pieblock_hid::transport::{HidTransport, TransportError};
use pieblock_toolchain::HexImage;
use serde_json::{Value, json};

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/m2/m2.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("m2 golden json")
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
fn protocol_packets_and_blocks_match_dart() {
    let golden = golden();
    for case in golden["packets"].as_array().expect("packets") {
        let payload: Vec<u8> = case["payload"]
            .as_array()
            .expect("payload")
            .iter()
            .map(|value| u8::try_from(value.as_i64().expect("byte")).expect("byte"))
            .collect();
        let packet = HidProtocol::build_packet(&payload);
        assert_eq!(
            encode_hex(&packet),
            case["packet"].as_str().expect("packet"),
            "packet mismatch"
        );
        let reports: Vec<String> = HidProtocol::split_reports(&packet)
            .iter()
            .map(|report| encode_hex(report))
            .collect();
        let expected: Vec<&str> = case["reports"]
            .as_array()
            .expect("reports")
            .iter()
            .map(|value| value.as_str().expect("report"))
            .collect();
        assert_eq!(reports, expected, "reports mismatch");
    }
    for case in golden["blocks"].as_array().expect("blocks") {
        let mut image = HexImage::default();
        for entry in case["bytes"].as_array().expect("bytes") {
            let pair = entry.as_array().expect("pair");
            image.bytes.insert(
                pair[0].as_i64().expect("address"),
                u8::try_from(pair[1].as_i64().expect("byte")).expect("byte"),
            );
        }
        let blocks = HidProtocol::build_write_blocks(&image).expect("blocks");
        let actual: Vec<Value> = blocks
            .iter()
            .map(|block| {
                json!({
                    "address": block.address,
                    "command": block.command,
                    "data": encode_hex(&block.data),
                })
            })
            .collect();
        assert_eq!(Value::Array(actual), case["blocks"], "block plan mismatch");
    }
}

struct ScriptedTransport {
    devices: i64,
    script: VecDeque<Option<Vec<u8>>>,
    writes: Vec<Vec<u8>>,
    fail_write_from: Option<usize>,
    closed: bool,
}

impl HidTransport for ScriptedTransport {
    fn count_devices(&mut self) -> Result<i64, TransportError> {
        Ok(self.devices)
    }

    fn open(&mut self) -> bool {
        true
    }

    fn write(&mut self, report: &[u8]) -> bool {
        self.writes.push(report.to_vec());
        !self
            .fail_write_from
            .is_some_and(|limit| self.writes.len() > limit)
    }

    fn read(&mut self, _timeout_milliseconds: i64) -> Vec<u8> {
        self.script.pop_front().flatten().unwrap_or_default()
    }

    fn cancel(&mut self) {}

    fn close(&mut self) {
        self.closed = true;
    }
}

#[test]
fn flasher_scenarios_match_dart() {
    let golden = golden();
    for case in golden["flasher"].as_array().expect("flasher") {
        let name = case["name"].as_str().unwrap_or("?");
        let mut image = HexImage::default();
        for entry in case["image"].as_array().expect("image") {
            let pair = entry.as_array().expect("pair");
            image.bytes.insert(
                pair[0].as_i64().expect("address"),
                u8::try_from(pair[1].as_i64().expect("byte")).expect("byte"),
            );
        }
        let responses: VecDeque<Option<Vec<u8>>> = case["responses"]
            .as_array()
            .expect("responses")
            .iter()
            .map(|value| value.as_str().map(decode_hex))
            .collect();
        let mut transport = ScriptedTransport {
            devices: case["devices"].as_i64().expect("devices"),
            script: responses,
            writes: Vec::new(),
            fail_write_from: case["failWriteFrom"]
                .as_i64()
                .map(|value| usize::try_from(value).unwrap_or(0)),
            closed: false,
        };
        let mut events: Vec<FlashEvent> = Vec::new();
        let result = HidFlasher::flash_with_transport(
            &image,
            &mut transport,
            &mut |event| events.push(event),
            &FlashOptions {
                report_gap_ms: 0,
                write_attempts: 3,
                retry_backoff_ms: 0,
                probe_timeout_ms: 10,
            },
            &|_| {},
        );
        let actual_events: Vec<Value> = events
            .iter()
            .map(|event| {
                json!({
                    "stage": event.stage.as_str(),
                    "message": event.message,
                    "current": event.current,
                    "total": event.total,
                })
            })
            .collect();
        assert_eq!(
            Value::Array(actual_events),
            case["events"],
            "{name}: events mismatch"
        );
        let expected_result = &case["result"];
        assert_eq!(
            result.success,
            expected_result["success"].as_bool().expect("success"),
            "{name}: success"
        );
        assert_eq!(
            result.stage.as_str(),
            expected_result["stage"].as_str().expect("stage"),
            "{name}: stage"
        );
        assert_eq!(
            result.message,
            expected_result["message"].as_str().expect("message"),
            "{name}: message"
        );
        assert_eq!(
            result.canceled,
            expected_result["canceled"].as_bool().expect("canceled"),
            "{name}: canceled"
        );
        let writes: Vec<String> = transport
            .writes
            .iter()
            .map(|write| encode_hex(write))
            .collect();
        let expected_writes: Vec<&str> = case["writes"]
            .as_array()
            .expect("writes")
            .iter()
            .map(|value| value.as_str().expect("write"))
            .collect();
        assert_eq!(writes, expected_writes, "{name}: writes mismatch");
        assert_eq!(
            transport.closed,
            case["closed"].as_bool().expect("closed"),
            "{name}: closed"
        );
    }
}

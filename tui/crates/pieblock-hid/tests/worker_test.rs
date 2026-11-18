//! 烧录 worker 测试：正常完成、90 秒超时（缩短）、取消、HEX 哈希不匹配。

use std::collections::VecDeque;
use std::path::{Path, PathBuf};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};

use pieblock_hid::worker::start_flash_with_timeout;
use pieblock_hid::{FlashOptions, HidTransport, TransportError};

fn unique_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!("hid-worker-{name}-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn record(record_type: u8, address: u16, data: &[u8]) -> String {
    let mut values = vec![
        data.len() as u8,
        (address >> 8) as u8,
        address as u8,
        record_type,
    ];
    values.extend_from_slice(data);
    let sum: u32 = values.iter().map(|value| u32::from(*value)).sum();
    let checksum = ((0x100 - (sum & 0xff)) & 0xff) as u8;
    let mut text = String::from(":");
    for value in values {
        text.push_str(&format!("{value:02X}"));
    }
    text.push_str(&format!("{checksum:02X}"));
    text
}

fn valid_hex() -> String {
    [
        record(4, 0x0000, &[0x00, 0xfe]),
        record(0, 0x0000, &[1, 2, 3, 4]),
        record(4, 0x0000, &[0x00, 0xff]),
        record(0, 0x0000, &[0x02, 0x00, 0x00, 0x10, 0x20]),
        record(1, 0x0000, &[]),
    ]
    .join("\r\n")
}

fn normalized_sha(text: &str) -> String {
    pieblock_core::sha256_hex(text.replace("\r\n", "\n").as_bytes())
}

fn ack(command: u8, rest: &[u8]) -> Vec<u8> {
    let mut response = vec![0x46, 0xb9, 0x68, 0, (rest.len() + 3) as u8, command];
    response.extend_from_slice(rest);
    response.extend_from_slice(&[0, 0]);
    response
}

struct ScriptedTransport {
    script: VecDeque<Option<Vec<u8>>>,
    cancel: Option<Arc<AtomicBool>>,
    writes: Vec<Vec<u8>>,
    block_reads: bool,
}

impl HidTransport for ScriptedTransport {
    fn count_devices(&mut self) -> Result<i64, TransportError> {
        Ok(1)
    }

    fn open(&mut self) -> bool {
        true
    }

    fn write(&mut self, report: &[u8]) -> bool {
        self.writes.push(report.to_vec());
        true
    }

    fn read(&mut self, timeout_milliseconds: i64) -> Vec<u8> {
        if self.block_reads {
            let mut waited = 0_i64;
            while waited < timeout_milliseconds.max(500) {
                if self
                    .cancel
                    .as_ref()
                    .is_some_and(|flag| flag.load(Ordering::SeqCst))
                {
                    return Vec::new();
                }
                std::thread::sleep(std::time::Duration::from_millis(5));
                waited += 5;
            }
            return Vec::new();
        }
        self.script.pop_front().flatten().unwrap_or_default()
    }

    fn cancel(&mut self) {}

    fn close(&mut self) {}
}

#[test]
fn worker_successes_and_reports_events() {
    let dir = unique_dir("success");
    let hex_path = dir.join("firmware.hex");
    let content = valid_hex();
    std::fs::write(&hex_path, &content).expect("hex");
    let script = vec![
        Some(ack(0x01, &[])),
        Some(ack(0x05, &[])),
        Some(ack(0x03, &[])),
        Some(ack(0x02, &[0x54])),
        Some(ack(0x02, &[0x54])),
    ];
    let expected = normalized_sha(&content);
    let operation = start_flash_with_timeout(
        hex_path,
        expected,
        move |_flag| {
            Ok(ScriptedTransport {
                script: script.into_iter().collect(),
                cancel: None,
                writes: Vec::new(),
                block_reads: false,
            })
        },
        FlashOptions::default(),
        std::time::Duration::from_secs(5),
    );
    let result = operation.wait();
    assert!(result.success, "result: {result:?}");
    assert_eq!(result.stage.as_str(), "done");
}

#[test]
fn worker_times_out_with_canceled_message() {
    let dir = unique_dir("timeout");
    let hex_path = dir.join("firmware.hex");
    let content = valid_hex();
    std::fs::write(&hex_path, &content).expect("hex");
    let expected = normalized_sha(&content);
    let operation = start_flash_with_timeout(
        hex_path,
        expected,
        move |flag| {
            Ok(ScriptedTransport {
                script: VecDeque::new(),
                cancel: Some(flag),
                writes: Vec::new(),
                block_reads: true,
            })
        },
        FlashOptions::default(),
        std::time::Duration::from_millis(150),
    );
    let result = operation.wait();
    assert!(!result.success);
    assert!(result.canceled);
    assert_eq!(result.message, "烧录超过 90 秒，已自动取消");
    assert_eq!(result.stage.as_str(), "canceled");
}

#[test]
fn worker_hash_mismatch_fails_before_opening_device() {
    let dir = unique_dir("hash");
    let hex_path = dir.join("firmware.hex");
    std::fs::write(&hex_path, valid_hex()).expect("hex");
    let operation = start_flash_with_timeout(
        hex_path,
        "deadbeef".to_owned(),
        move |_flag| {
            Ok(ScriptedTransport {
                script: VecDeque::new(),
                cancel: None,
                writes: Vec::new(),
                block_reads: false,
            })
        },
        FlashOptions::default(),
        std::time::Duration::from_secs(5),
    );
    let result = operation.wait();
    assert!(!result.success);
    assert_eq!(result.stage.as_str(), "preparing");
    assert_eq!(result.message, "HEX 已丢失或内容发生变化，请重新编译");
}

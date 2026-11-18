//! HEX/MAP 校验 golden：解析字节、应用区布局、SDCC 链接布局与错误文案。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_toolchain::IntelHexValidator;
use serde_json::Value;

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

fn temp_dir() -> PathBuf {
    use std::sync::atomic::{AtomicUsize, Ordering};
    static COUNTER: AtomicUsize = AtomicUsize::new(0);
    let id = COUNTER.fetch_add(1, Ordering::Relaxed);
    let dir = Path::new(env!("CARGO_MANIFEST_DIR")).join(format!("../../target/m2-hex-test-{id}"));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn write_temp(dir: &Path, name: &str, content: &str) -> PathBuf {
    let path = dir.join(format!("{name}.hex"));
    fs::write(&path, content).expect("write hex");
    path
}

#[test]
fn hex_parse_matches_dart() {
    let golden = golden();
    let dir = temp_dir();
    for case in golden["hexParse"].as_array().expect("hexParse") {
        let name = case["name"].as_str().unwrap_or("?");
        let content = case["content"].as_str().expect("content");
        let path = write_temp(&dir, name, content);
        let result = IntelHexValidator::parse(&path);
        assert_eq!(result.ok, case["ok"].as_bool().expect("ok"), "{name}: ok");
        assert_eq!(
            result.message,
            case["message"].as_str().expect("message"),
            "{name}: message"
        );
        if result.ok {
            let expected: Vec<(i64, u8)> = case["bytes"]
                .as_array()
                .expect("bytes")
                .iter()
                .map(|entry| {
                    let pair = entry.as_array().expect("pair");
                    (
                        pair[0].as_i64().expect("address"),
                        u8::try_from(pair[1].as_i64().expect("byte")).expect("byte"),
                    )
                })
                .collect();
            let actual: Vec<(i64, u8)> = result
                .image
                .expect("image")
                .bytes
                .iter()
                .map(|(address, byte)| (*address, *byte))
                .collect();
            assert_eq!(actual, expected, "{name}: bytes");
        }
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn hex_application_validation_matches_dart() {
    let golden = golden();
    let dir = temp_dir();
    for case in golden["hexValidate"].as_array().expect("hexValidate") {
        let name = case["name"].as_str().unwrap_or("?");
        let content = golden["hexParse"]
            .as_array()
            .expect("hexParse")
            .iter()
            .find(|item| item["name"] == name)
            .and_then(|item| item["content"].as_str())
            .unwrap_or("");
        let path = write_temp(&dir, name, content);
        let result = IntelHexValidator::validate_application(&path);
        assert_eq!(result.ok, case["ok"].as_bool().expect("ok"), "{name}: ok");
        assert_eq!(
            result.message,
            case["message"].as_str().expect("message"),
            "{name}: message"
        );
    }
    let _ = fs::remove_dir_all(&dir);
}

#[test]
fn hex_map_validation_matches_dart() {
    let golden = golden();
    let dir = temp_dir();
    let valid_hex = golden["hexParse"]
        .as_array()
        .expect("hexParse")
        .iter()
        .find(|item| item["name"] == "valid_application")
        .and_then(|item| item["content"].as_str())
        .expect("valid hex");
    for case in golden["mapValidate"].as_array().expect("mapValidate") {
        let name = case["name"].as_str().unwrap_or("?");
        let hex = case["hex"].as_str().unwrap_or(valid_hex);
        let hex_path = write_temp(&dir, &format!("{name}-hex"), hex);
        let map_path = dir.join(format!("{name}.map"));
        match case["map"].as_str() {
            Some(map) => fs::write(&map_path, map).expect("write map"),
            None => {
                let _ = fs::remove_file(&map_path);
            }
        }
        let result = IntelHexValidator::validate_sdcc_layout(&hex_path, &map_path);
        assert_eq!(result.ok, case["ok"].as_bool().expect("ok"), "{name}: ok");
        assert_eq!(
            result.message,
            case["message"].as_str().expect("message"),
            "{name}: message"
        );
    }
    let _ = fs::remove_dir_all(&dir);
}

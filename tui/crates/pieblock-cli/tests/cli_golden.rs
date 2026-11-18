//! CLI golden：validate/codegen 的退出码、stdout、stderr 与 Dart 逐字节一致。
//!
//! 音乐工程校验/生成与工程代码生成尚未移植，先跳过对应用例；其余用例要求
//! 完全一致（含版本不兼容与校验失败路径）。

use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/cli/cli.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("cli golden json")
}

fn supported(case: &Value) -> bool {
    let kind = case["kind"].as_str().unwrap_or("unknown");
    if kind == "music" {
        return false;
    }
    if case["command"].as_str() == Some("codegen") {
        let exit = case["exitCode"].as_i64().unwrap_or(-1);
        // 工程/音乐代码生成尚未移植：只对拍会因校验被拒绝的用例。
        if kind == "engineer" && exit == 0 {
            return false;
        }
    }
    true
}

#[test]
fn cli_matches_dart_byte_for_byte() {
    let golden = golden();
    let cases = golden["cases"].as_array().expect("cases");
    let mut checked = 0;
    let mut expected = 0;
    for case in cases {
        if !supported(case) {
            continue;
        }
        expected += 1;
        let name = case["name"].as_str().unwrap_or("?");
        let args: Vec<&str> = case["args"]
            .as_array()
            .expect("args")
            .iter()
            .map(|value| value.as_str().expect("arg"))
            .collect();
        let output = Command::new(env!("CARGO_BIN_EXE_pieblock-cli"))
            .args(&args)
            .current_dir(repo_root())
            .output()
            .unwrap_or_else(|error| panic!("{name}: spawn: {error}"));
        assert_eq!(
            i64::from(output.status.code().unwrap_or(-1)),
            case["exitCode"].as_i64().expect("exitCode"),
            "{name}: exit code"
        );
        assert_eq!(
            String::from_utf8_lossy(&output.stdout),
            case["stdout"].as_str().expect("stdout"),
            "{name}: stdout"
        );
        assert_eq!(
            String::from_utf8_lossy(&output.stderr),
            case["stderr"].as_str().expect("stderr"),
            "{name}: stderr"
        );
        checked += 1;
    }
    assert_eq!(checked, expected, "golden case filter sanity");
    assert!(checked >= 20, "too few CLI cases checked: {checked}");
}

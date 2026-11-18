//! CLI propose golden：退出码、stderr、stdout 与 `.proposed` 文件（忽略时间戳）。

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
    let path = repo_root().join("tui/parity/golden/cli/cli_propose.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("cli propose golden json")
}

fn normalize_created_at(text: &str) -> String {
    let mut output = text.to_owned();
    if let Some(start) = output.find("\"createdAt\"") {
        if let Some(quote_start) = output[start..].find(':').map(|offset| start + offset) {
            if let Some(open) = output[quote_start..]
                .find('"')
                .map(|offset| quote_start + offset)
            {
                if let Some(close) = output[open + 1..].find('"').map(|offset| open + 1 + offset) {
                    output.replace_range(open + 1..close, "<iso>");
                }
            }
        }
    }
    output
}

#[test]
fn cli_propose_matches_dart() {
    let golden = golden();
    let cases = golden["cases"].as_array().expect("cases");
    let proposal_path =
        repo_root().join("tui/parity/cli/projects/infantry_template.pieproj.proposed");
    let mut checked = 0;
    for case in cases {
        let name = case["name"].as_str().unwrap_or("?");
        let args: Vec<&str> = case["args"]
            .as_array()
            .expect("args")
            .iter()
            .map(|value| value.as_str().expect("arg"))
            .collect();
        if proposal_path.exists() {
            fs::remove_file(&proposal_path).expect("cleanup proposal");
        }
        if case["preCreateProposal"].as_bool() == Some(true) {
            fs::write(&proposal_path, "stale\n").expect("pre-create proposal");
        }
        let output = Command::new(env!("CARGO_BIN_EXE_pieblock-cli"))
            .args(&args)
            .current_dir(repo_root())
            .output()
            .unwrap_or_else(|error| panic!("{name}: spawn: {error}"));
        let proposal = if proposal_path.exists() {
            Some(
                fs::read_to_string(&proposal_path)
                    .unwrap_or_else(|error| panic!("{name}: read proposal: {error}")),
            )
        } else {
            None
        };
        if proposal_path.exists() {
            fs::remove_file(&proposal_path).expect("cleanup proposal");
        }
        assert_eq!(
            i64::from(output.status.code().unwrap_or(-1)),
            case["exitCode"].as_i64().expect("exitCode"),
            "{name}: exit code (stderr={})",
            String::from_utf8_lossy(&output.stderr)
        );
        assert_eq!(
            String::from_utf8_lossy(&output.stderr),
            case["stderr"].as_str().expect("stderr"),
            "{name}: stderr"
        );
        assert_eq!(
            normalize_created_at(&String::from_utf8_lossy(&output.stdout)),
            case["stdout"].as_str().expect("stdout"),
            "{name}: stdout"
        );
        match (&proposal, case["proposal"].as_str()) {
            (Some(actual), Some(expected)) => assert_eq!(
                normalize_created_at(actual),
                expected,
                "{name}: proposal file"
            ),
            (None, None) => {}
            (actual, expected) => panic!(
                "{name}: proposal presence mismatch: actual={actual:?} expected={expected:?}"
            ),
        }
        checked += 1;
    }
    assert_eq!(checked, cases.len());
    assert_eq!(checked, 7);
}

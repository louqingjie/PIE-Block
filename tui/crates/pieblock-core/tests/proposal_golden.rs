//! 提案 golden：编码文本逐字节、错误码/文案/字段、fromJson 校验与往返。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::proposal::is_valid_proposal_json;
use pieblock_core::{ProjectDocument, ProjectProposal, encode_proposal, proposal_path_for};
use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/proposal/proposal.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("proposal golden json")
}

#[test]
fn proposal_create_matches_dart() {
    let golden = golden();
    let cases = golden["cases"].as_array().expect("cases");
    assert_eq!(cases.len(), 9);
    for case in cases {
        let name = case["name"].as_str().unwrap_or("?");
        let base = ProjectDocument::from_json(&case["base"])
            .unwrap_or_else(|error| panic!("{name}: base: {error}"));
        let candidate = &case["candidate"];
        let result = ProjectProposal::create(
            &base,
            candidate,
            &"a".repeat(64),
            Some("pieblock-cli/1.0.0".to_owned()),
            "2026-01-01T00:00:00.000Z".to_owned(),
        );
        if case["ok"].as_bool() == Some(true) {
            let proposal = result.unwrap_or_else(|error| panic!("{name}: {error:?}"));
            assert_eq!(
                encode_proposal(&proposal),
                case["encoded"].as_str().expect("encoded"),
                "{name}: encoded proposal mismatch"
            );
        } else {
            let error = result.expect_err("expected proposal error");
            assert_eq!(
                error.code,
                case["code"].as_str().expect("code"),
                "{name}: code"
            );
            assert_eq!(
                error.message,
                case["message"].as_str().expect("message"),
                "{name}: message"
            );
            let expected_fields: Vec<&str> = case["fields"]
                .as_array()
                .expect("fields")
                .iter()
                .map(|value| value.as_str().expect("field"))
                .collect();
            assert_eq!(error.fields, expected_fields, "{name}: fields");
        }
    }
}

#[test]
fn proposal_roundtrip_matches_dart() {
    let golden = golden();
    for case in golden["roundtrip"].as_array().expect("roundtrip") {
        let name = case["name"].as_str().unwrap_or("?");
        let json = &case["json"];
        assert_eq!(
            is_valid_proposal_json(json),
            case["isValid"].as_bool().expect("isValid"),
            "{name}: isValid"
        );
        match ProjectProposal::from_json(json) {
            Ok(proposal) => {
                assert_eq!(
                    encode_proposal(&proposal),
                    case["encoded"].as_str().expect("encoded"),
                    "{name}: re-encoded mismatch"
                );
                assert_eq!(
                    proposal.base_sha256,
                    case["baseSha256"].as_str().expect("baseSha256")
                );
                let expected_paths: Vec<&str> = case["changedPaths"]
                    .as_array()
                    .expect("changedPaths")
                    .iter()
                    .map(|value| value.as_str().expect("path"))
                    .collect();
                assert_eq!(proposal.changed_paths, expected_paths, "{name}: paths");
            }
            Err(error) => {
                assert_eq!(
                    error.code,
                    case["code"].as_str().expect("code"),
                    "{name}: code"
                );
                assert_eq!(
                    error.message,
                    case["message"].as_str().expect("message"),
                    "{name}: message"
                );
            }
        }
    }
}

#[test]
fn proposal_paths_match_dart() {
    assert_eq!(proposal_path_for("robot.pieproj"), "robot.pieproj.proposed");
}

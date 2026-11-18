//! 校验器 golden：debug 工程对比完整 issues；infantry/engineer 先对拍公共
//! 机器人规则（stepId=remote），专属规则移植后会把对比扩展到完整列表。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::ProjectDocument;
use pieblock_core::validation::{ValidationIssue, validate};
use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden_dir() -> PathBuf {
    repo_root().join("tui/parity/golden/validation")
}

fn issue_values(issues: &[ValidationIssue]) -> Value {
    Value::Array(issues.iter().map(ValidationIssue::to_json).collect())
}

fn load_cases() -> Vec<(PathBuf, Value)> {
    let dir = golden_dir();
    let mut files: Vec<PathBuf> = fs::read_dir(&dir)
        .unwrap_or_else(|error| panic!("read {}: {error}", dir.display()))
        .map(|entry| entry.expect("dir entry").path())
        .filter(|path| path.extension().and_then(|ext| ext.to_str()) == Some("json"))
        .collect();
    files.sort();
    files
        .into_iter()
        .map(|path| {
            let text = fs::read_to_string(&path)
                .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
            let value: Value = serde_json::from_str(&text).expect("golden json");
            (path, value)
        })
        .collect()
}

fn document_of(golden: &Value) -> ProjectDocument {
    ProjectDocument::from_json(&golden["document"]).expect("golden document parses")
}

#[test]
fn debug_validation_matches_dart_fully() {
    let mut checked = 0;
    for (path, golden) in load_cases() {
        if golden["kind"].as_str() != Some("debug") {
            continue;
        }
        let document = document_of(&golden);
        let actual = issue_values(&validate(&document.config));
        assert_eq!(
            actual,
            golden["issues"],
            "{}: debug validation mismatch",
            path.display()
        );
        checked += 1;
    }
    assert_eq!(checked, 8, "expected 8 debug cases");
}

#[test]
fn common_robot_rules_match_dart() {
    let mut engineer_checked = 0;
    let mut infantry_checked = 0;
    for (path, golden) in load_cases() {
        let kind = golden["kind"].as_str().unwrap_or_default();
        if kind != "infantry" && kind != "engineer" {
            continue;
        }
        let document = document_of(&golden);
        let all = validate(&document.config);
        let actual: Vec<Value> = all
            .iter()
            .filter(|issue| issue.step_id == "remote")
            .map(ValidationIssue::to_json)
            .collect();
        let expected = golden["remoteIssues"]
            .as_array()
            .expect("remoteIssues array");
        if kind == "engineer" {
            // 工程专属规则不使用 remote step，remote 列表应完全等于公共规则输出。
            assert_eq!(
                Value::Array(actual),
                golden["remoteIssues"],
                "{}: common robot rule mismatch",
                path.display()
            );
            engineer_checked += 1;
        } else {
            // 步兵专属规则（PWMA 提示、引脚规划）也会追加 remote 问题；
            // 公共规则在前，因此我们的输出必须是 Dart remote 列表的前缀。
            assert!(
                actual.len() <= expected.len(),
                "{}: too many remote issues",
                path.display()
            );
            assert_eq!(
                &actual[..],
                &expected[..actual.len()],
                "{}: common robot prefix mismatch",
                path.display()
            );
            infantry_checked += 1;
        }
    }
    assert_eq!(engineer_checked, 3, "expected 3 engineer cases");
    assert_eq!(infantry_checked, 5, "expected 5 infantry cases");
}

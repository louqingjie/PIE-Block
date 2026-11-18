//! C 代码生成 golden：调试工程逐字节对拍 Dart；其余工程类型待移植后扩展。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::ProjectDocument;
use pieblock_core::codegen::{GenerationError, generate_program};
use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/codegen/codegen.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("codegen golden json")
}

fn first_diff(expected: &str, actual: &str) -> String {
    for (index, (want, got)) in expected.lines().zip(actual.lines()).enumerate() {
        if want != got {
            return format!("第 {} 行不同:\n  Dart: {want}\n  Rust: {got}", index + 1);
        }
    }
    format!(
        "行数不同: Dart {} 行，Rust {} 行",
        expected.lines().count(),
        actual.lines().count()
    )
}

#[test]
fn debug_and_infantry_codegen_match_dart_byte_for_byte() {
    let golden = golden();
    let cases = golden["cases"].as_array().expect("cases");
    assert!(cases.len() >= 17, "unexpected case count");
    let mut checked = 0;
    for case in cases {
        let kind = case["kind"].as_str().unwrap_or_default();
        if kind != "debug" && kind != "infantry" && kind != "engineer" && kind != "music" {
            continue;
        }
        let name = case["name"].as_str().unwrap_or("?");
        let document = ProjectDocument::from_json(&case["document"])
            .unwrap_or_else(|error| panic!("{name}: document: {error}"));
        let result = generate_program(&document.config);
        if let Some(expected_error) = case["error"].as_str() {
            match result {
                Err(GenerationError::InvalidConfig { message }) => {
                    let actual = format!("配置尚未完成，不能生成代码：{message}");
                    assert_eq!(actual, expected_error, "{name}: error message");
                }
                other => panic!("{name}: expected validation error, got {other:?}"),
            }
            checked += 1;
            continue;
        }
        let program = result.unwrap_or_else(|error| panic!("{name}: {error:?}"));
        let expected_source = case["source"].as_str().expect("source");
        assert!(
            program.source == expected_source,
            "{name}: source mismatch\n{}",
            first_diff(expected_source, &program.source)
        );
        let expected_fields: serde_json::Map<String, Value> = case["expressionLineFields"]
            .as_object()
            .expect("expressionLineFields")
            .clone();
        let actual_fields: serde_json::Map<String, Value> = program
            .expression_line_fields
            .iter()
            .map(|(line, field)| (line.to_string(), Value::String(field.clone())))
            .collect();
        assert_eq!(
            Value::Object(actual_fields),
            Value::Object(expected_fields),
            "{name}: expression line fields mismatch"
        );
        checked += 1;
    }
    assert_eq!(checked, 17, "expected 17 codegen cases");
}

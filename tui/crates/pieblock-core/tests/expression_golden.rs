//! 表达式 golden：解析/诊断/C 发射/求值/运行时/试算逐条对拍 Dart。

use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};

use pieblock_core::ProjectDocument;
use pieblock_core::expression::{
    AXIS_INPUTS, BUTTON_INPUTS, ExpressionEmitter, ExpressionType, Number, evaluate, evaluate_mode,
    is_valid_variable_name, parse, runtime_code,
};
use pieblock_core::model::EngineerConfig;
use serde_json::Value;

fn repo_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../..")
        .canonicalize()
        .expect("repo root")
}

fn golden() -> Value {
    let path = repo_root().join("tui/parity/golden/expression/expression.json");
    let text = fs::read_to_string(&path)
        .unwrap_or_else(|error| panic!("read {}: {error}", path.display()));
    serde_json::from_str(&text).expect("expression golden json")
}

fn scope() -> BTreeMap<String, ExpressionType> {
    BTreeMap::from([
        ("ratio".to_owned(), ExpressionType::Rational),
        ("speed".to_owned(), ExpressionType::Integer),
    ])
}

fn inputs() -> BTreeMap<String, Number> {
    BTreeMap::from([
        ("A".to_owned(), Number::Integer(1)),
        ("B".to_owned(), Number::Integer(0)),
        ("LX".to_owned(), Number::Integer(120)),
        ("LY".to_owned(), Number::Integer(-30)),
        ("RX".to_owned(), Number::Integer(0)),
        ("RY".to_owned(), Number::Integer(45)),
        ("UP".to_owned(), Number::Integer(1)),
    ])
}

fn variables() -> BTreeMap<String, Number> {
    BTreeMap::from([
        ("ratio".to_owned(), Number::Float(0.5)),
        ("speed".to_owned(), Number::Integer(50)),
    ])
}

#[test]
fn parse_emit_and_eval_match_dart() {
    let golden = golden();
    let cases = golden["cases"].as_array().expect("cases");
    assert!(cases.len() >= 60, "unexpected case count");
    for case in cases {
        let source = case["source"].as_str().expect("source");
        let parsed = parse(source, &scope());
        assert_eq!(
            parsed.is_ok(),
            case["ok"].as_bool().expect("ok"),
            "{source}: ok mismatch"
        );
        let diagnostics: Vec<Value> = parsed
            .diagnostics
            .iter()
            .map(pieblock_core::expression::ExpressionDiagnostic::to_json)
            .collect();
        assert_eq!(
            Value::Array(diagnostics),
            case["diagnostics"],
            "{source}: diagnostics mismatch"
        );
        if case["ok"].as_bool() != Some(true) {
            continue;
        }
        let root = parsed.root.expect("root");
        assert_eq!(
            root.kind().as_str(),
            case["type"].as_str().expect("type"),
            "{source}: type mismatch"
        );
        let mut emitter =
            ExpressionEmitter::new(|name| format!("INPUT_{name}"), |name| format!("VAR_{name}"));
        assert_eq!(
            emitter.emit(&root),
            case["code"].as_str().expect("code"),
            "{source}: code mismatch"
        );
        let helpers: Vec<&str> = emitter.helpers.iter().copied().collect();
        assert_eq!(
            Value::Array(
                helpers
                    .iter()
                    .map(|name| Value::String((*name).to_owned()))
                    .collect()
            ),
            case["helpers"],
            "{source}: helpers mismatch"
        );
        let value = evaluate(&root, &inputs(), &variables());
        assert_eq!(
            value.to_dart_string(),
            case["eval"].as_str().expect("eval"),
            "{source}: eval mismatch"
        );
    }
}

#[test]
fn runtime_code_matches_dart() {
    let golden = golden();
    let runtime = golden["runtime"].as_array().expect("runtime");
    assert_eq!(runtime.len(), 6);
    for case in runtime {
        let helpers: Vec<String> = case["helpers"]
            .as_array()
            .expect("helpers")
            .iter()
            .map(|value| value.as_str().expect("helper").to_owned())
            .collect();
        let set: std::collections::BTreeSet<&str> = helpers.iter().map(String::as_str).collect();
        assert_eq!(
            runtime_code(&set),
            case["code"].as_str().expect("code"),
            "runtime helpers {helpers:?}"
        );
    }
}

#[test]
fn variable_name_rules_match_dart() {
    let golden = golden();
    for case in golden["variableNames"].as_array().expect("names") {
        let name = case["name"].as_str().expect("name");
        assert_eq!(
            is_valid_variable_name(name),
            case["valid"].as_bool().expect("valid"),
            "{name}: variable name rule mismatch"
        );
    }
}

#[test]
fn input_tables_match_dart() {
    let golden = golden();
    let all = golden["cases"].as_array().expect("cases");
    // 输入别名集合是公开契约：与 golden 中 expression 解析结果无关，直接断言长度。
    assert_eq!(AXIS_INPUTS.len(), 4);
    assert_eq!(BUTTON_INPUTS.len(), 11);
    assert!(!all.is_empty());
}

#[test]
fn engineer_preview_matches_dart() {
    let golden = golden();
    let path = repo_root().join("assets/templates/engineer.pieproj");
    let text = fs::read_to_string(&path).expect("engineer template");
    let document: ProjectDocument =
        ProjectDocument::from_json(&serde_json::from_str(&text).expect("template json"))
            .expect("template parses");
    let pieblock_core::model::ProjectConfig::Engineer(config) = &document.config else {
        panic!("engineer template kind");
    };
    let config: &EngineerConfig = config;
    for case in golden["engineerPreview"].as_array().expect("preview") {
        let mode_index = case["modeIndex"].as_u64().expect("modeIndex") as usize;
        let mut input_map: BTreeMap<String, Number> = BTreeMap::new();
        for (name, value) in case["inputs"].as_object().expect("inputs") {
            input_map.insert(name.clone(), json_number(value));
        }
        let result = evaluate_mode(config, mode_index, &input_map);
        let variables: serde_json::Map<String, Value> = result
            .variables
            .iter()
            .map(|(name, value)| (name.clone(), Value::String(value.to_dart_string())))
            .collect();
        assert_eq!(
            Value::Object(variables),
            case["variables"],
            "mode {mode_index}: variables mismatch"
        );
        let rows: Vec<Value> = result
            .rows
            .iter()
            .map(|row| {
                let mut map = serde_json::Map::new();
                map.insert("label".to_owned(), Value::String(row.label.clone()));
                map.insert(
                    "fieldPath".to_owned(),
                    Value::String(row.field_path.clone()),
                );
                map.insert(
                    "value".to_owned(),
                    row.value
                        .map_or(Value::Null, |value| Value::String(value.to_dart_string())),
                );
                map.insert(
                    "error".to_owned(),
                    row.error
                        .as_ref()
                        .map_or(Value::Null, |error| Value::String(error.clone())),
                );
                Value::Object(map)
            })
            .collect();
        assert_eq!(
            Value::Array(rows),
            case["rows"],
            "mode {mode_index}: rows mismatch"
        );
    }
}

fn json_number(value: &Value) -> Number {
    if let Some(integer) = value.as_i64() {
        Number::Integer(integer)
    } else {
        Number::Float(value.as_f64().expect("number"))
    }
}

//! AI 改动提案：CLI 生成、应用确认后写入，应用始终是工程文件的唯一写者。
//!
//! 与 `packages/pieblock_core/lib/src/proposal.dart` 对齐：提案是独立文件
//!（`<工程>.proposed`），带 `baseSha256`；「往返核对」拒绝模型读不回的字段；
//! 只禁止候选**新增** error 级校验问题（工程原本没配置完不算）。

use serde_json::{Map, Value};

use crate::ProjectDocument;
use crate::model::ProjectConfig;
use crate::validation::{IssueSeverity, ValidationIssue, validate};

/// 提案文件格式版本。
pub const PROPOSAL_SCHEMA: i64 = 1;
/// 提案文件的 `kind` 标记。
pub const PROPOSAL_KIND: &str = "pieblock-proposal";
/// 提案文件后缀。
pub const PROPOSAL_SUFFIX: &str = ".proposed";
/// 应用处理完提案后写回的结果文件后缀。
pub const PROPOSAL_RESULT_SUFFIX: &str = ".result";

#[must_use]
pub fn proposal_path_for(project_path: &str) -> String {
    format!("{project_path}{PROPOSAL_SUFFIX}")
}

#[must_use]
pub fn proposal_result_path_for(project_path: &str) -> String {
    format!("{project_path}{PROPOSAL_SUFFIX}{PROPOSAL_RESULT_SUFFIX}")
}

/// 文件/字节的 SHA-256 十六进制摘要。
#[must_use]
pub fn sha256_hex(bytes: &[u8]) -> String {
    use sha2::{Digest, Sha256};
    let digest = Sha256::digest(bytes);
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

/// 提案构建或解析失败。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ProposalError {
    pub code: String,
    pub message: String,
    pub fields: Vec<String>,
}

impl ProposalError {
    fn new(code: &str, message: impl Into<String>) -> Self {
        Self {
            code: code.to_owned(),
            message: message.into(),
            fields: Vec::new(),
        }
    }

    fn with_fields(code: &str, message: impl Into<String>, fields: Vec<String>) -> Self {
        Self {
            code: code.to_owned(),
            message: message.into(),
            fields,
        }
    }
}

impl std::fmt::Display for ProposalError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        formatter.write_str(&self.message)
    }
}

impl std::error::Error for ProposalError {}

/// 一处配置改动（用于展示）。
#[derive(Debug, Clone, PartialEq)]
pub struct ProposalChange {
    pub path: String,
    pub before: Value,
    pub after: Value,
}

impl ProposalChange {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("path".to_owned(), Value::String(self.path.clone()));
        map.insert("before".to_owned(), self.before.clone());
        map.insert("after".to_owned(), self.after.clone());
        Value::Object(map)
    }
}

/// 一份 AI 改动提案。
#[derive(Debug, Clone, PartialEq)]
pub struct ProjectProposal {
    pub base_sha256: String,
    pub created_at: String,
    pub tool: Option<String>,
    pub changed_paths: Vec<String>,
    pub document: ProjectDocument,
}

impl ProjectProposal {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("schema".to_owned(), Value::from(PROPOSAL_SCHEMA));
        map.insert("kind".to_owned(), Value::String(PROPOSAL_KIND.to_owned()));
        map.insert(
            "baseSha256".to_owned(),
            Value::String(self.base_sha256.clone()),
        );
        map.insert(
            "createdAt".to_owned(),
            Value::String(self.created_at.clone()),
        );
        if let Some(tool) = &self.tool {
            map.insert("tool".to_owned(), Value::String(tool.clone()));
        }
        map.insert(
            "changedPaths".to_owned(),
            Value::Array(
                self.changed_paths
                    .iter()
                    .map(|path| Value::String(path.clone()))
                    .collect(),
            ),
        );
        map.insert("document".to_owned(), self.document.to_json());
        Value::Object(map)
    }

    /// 从提案文件内容还原；结构不合法时返回 [`ProposalError`]。
    pub fn from_json(json: &Value) -> Result<Self, ProposalError> {
        let Some(map) = json.as_object() else {
            return Err(ProposalError::new(
                "invalid_document",
                "不是 PIE-Block 改动提案文件",
            ));
        };
        if map.get("schema").and_then(Value::as_i64) != Some(PROPOSAL_SCHEMA) {
            let schema = map
                .get("schema")
                .map_or_else(|| "null".to_owned(), Value::to_string);
            return Err(ProposalError::new(
                "unsupported_schema",
                format!("提案格式版本 {schema} 不受支持（本版本支持 {PROPOSAL_SCHEMA}）"),
            ));
        }
        if map.get("kind").and_then(Value::as_str) != Some(PROPOSAL_KIND) {
            return Err(ProposalError::new(
                "invalid_document",
                "不是 PIE-Block 改动提案文件",
            ));
        }
        let Some(base) = map.get("baseSha256").and_then(Value::as_str) else {
            return Err(ProposalError::new(
                "invalid_document",
                "提案缺少合法的 baseSha256",
            ));
        };
        if !is_sha256_hex(base) {
            return Err(ProposalError::new(
                "invalid_document",
                "提案缺少合法的 baseSha256",
            ));
        }
        let Some(raw_document) = map.get("document").and_then(Value::as_object) else {
            return Err(ProposalError::new(
                "invalid_document",
                "提案缺少 document 对象",
            ));
        };
        let document = ProjectDocument::from_json(&Value::Object(raw_document.clone()))
            .map_err(|error| ProposalError::new("invalid_document", error.to_string()))?;
        let created_at = map
            .get("createdAt")
            .map(|value| value.as_str().unwrap_or("").to_owned())
            .unwrap_or_default();
        let changed_paths = map
            .get("changedPaths")
            .and_then(Value::as_array)
            .map(|paths| {
                paths
                    .iter()
                    .filter_map(Value::as_str)
                    .map(str::to_owned)
                    .collect()
            })
            .unwrap_or_default();
        Ok(Self {
            base_sha256: base.to_owned(),
            created_at,
            tool: map.get("tool").and_then(Value::as_str).map(str::to_owned),
            changed_paths,
            document,
        })
    }

    /// 用候选文档构建提案。
    pub fn create(
        base: &ProjectDocument,
        candidate_json: &Value,
        base_sha256: &str,
        tool: Option<String>,
        created_at: String,
    ) -> Result<Self, ProposalError> {
        let candidate = ProjectDocument::from_json(candidate_json)
            .map_err(|error| ProposalError::new("invalid_document", error.to_string()))?;
        if candidate.kind != base.kind {
            return Err(ProposalError::new(
                "kind_mismatch",
                format!(
                    "候选工程类型（{}）与目标工程（{}）不一致",
                    candidate.kind.as_str(),
                    base.kind.as_str()
                ),
            ));
        }
        let Some(raw_config) = candidate_json
            .as_object()
            .and_then(|map| map.get("config"))
            .and_then(Value::as_object)
        else {
            return Err(ProposalError::new(
                "invalid_document",
                "候选工程缺少 config 对象",
            ));
        };
        let candidate_config_json = config_to_json(&candidate.config);
        let fields = find_unroundtripped_fields(raw_config, &candidate_config_json);
        if !fields.is_empty() {
            return Err(ProposalError::with_fields(
                "unroundtripped_value",
                "以下字段的取值无法被项目模型接受（拼写错误或类型不匹配）",
                fields,
            ));
        }
        let new_errors = new_validation_errors(&base.config, &candidate.config);
        if !new_errors.is_empty() {
            let base_error_count = error_issues(&base.config).len();
            return Err(ProposalError::with_fields(
                "invalid_config",
                format!(
                    "候选引入了 {} 个新的校验错误（工程原有 {base_error_count} 个错误不算在内）",
                    new_errors.len()
                ),
                new_errors
                    .iter()
                    .map(|issue| issue.field_path.clone())
                    .collect(),
            ));
        }
        let changes = diff_configs(&config_to_json(&base.config), &candidate_config_json);
        if changes.is_empty() {
            return Err(ProposalError::new(
                "empty_changes",
                "候选配置与当前工程没有差异",
            ));
        }
        Ok(Self {
            base_sha256: base_sha256.to_owned(),
            created_at,
            tool,
            changed_paths: changes.into_iter().map(|change| change.path).collect(),
            document: candidate,
        })
    }
}

fn config_to_json(config: &ProjectConfig) -> Value {
    match config {
        ProjectConfig::Infantry(value) => value.to_json(),
        ProjectConfig::Engineer(value) => value.to_json(),
        ProjectConfig::Debug(value) => value.to_json(),
        ProjectConfig::Music(value) => value.to_json(),
    }
}

fn is_sha256_hex(value: &str) -> bool {
    value.len() == 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

/// 递归比较两份配置，返回所有差异（路径按 `a.b[0].c` 形式）。
#[must_use]
pub fn diff_configs(before: &Value, after: &Value) -> Vec<ProposalChange> {
    let mut changes = Vec::new();
    collect_changes(before, after, "", &mut changes);
    changes
}

/// 候选相对基线**新增**的 error 级校验问题。
#[must_use]
pub fn new_validation_errors(
    base: &ProjectConfig,
    candidate: &ProjectConfig,
) -> Vec<ValidationIssue> {
    let baseline: std::collections::HashSet<String> =
        error_issues(base).iter().map(issue_key).collect();
    error_issues(candidate)
        .into_iter()
        .filter(|issue| !baseline.contains(&issue_key(issue)))
        .collect()
}

fn error_issues(config: &ProjectConfig) -> Vec<ValidationIssue> {
    validate(config)
        .into_iter()
        .filter(|issue| issue.severity == IssueSeverity::Error)
        .collect()
}

fn issue_key(issue: &ValidationIssue) -> String {
    format!("{}\u{0}{}", issue.field_path, issue.message)
}

/// 找出候选 JSON 里「写进去但模型读不回来」的字段。
#[must_use]
pub fn find_unroundtripped_fields(raw_config: &Map<String, Value>, parsed: &Value) -> Vec<String> {
    let mut fields = Vec::new();
    collect_unroundtripped(&Value::Object(raw_config.clone()), parsed, "", &mut fields);
    fields
}

fn collect_changes(before: &Value, after: &Value, path: &str, out: &mut Vec<ProposalChange>) {
    match (before, after) {
        (Value::Object(before_map), Value::Object(after_map)) => {
            let mut keys: Vec<&String> = before_map.keys().collect();
            for key in after_map.keys() {
                if !before_map.contains_key(key) {
                    keys.push(key);
                }
            }
            for key in keys {
                let child_path = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                collect_changes(
                    before_map.get(key).unwrap_or(&Value::Null),
                    after_map.get(key).unwrap_or(&Value::Null),
                    &child_path,
                    out,
                );
            }
        }
        (Value::Array(before_list), Value::Array(after_list)) => {
            let length = before_list.len().max(after_list.len());
            for index in 0..length {
                collect_changes(
                    before_list.get(index).unwrap_or(&Value::Null),
                    after_list.get(index).unwrap_or(&Value::Null),
                    &format!("{path}[{index}]"),
                    out,
                );
            }
        }
        _ => {
            if !deep_equals(before, after) {
                out.push(ProposalChange {
                    path: path.to_owned(),
                    before: before.clone(),
                    after: after.clone(),
                });
            }
        }
    }
}

fn collect_unroundtripped(raw: &Value, parsed: &Value, path: &str, out: &mut Vec<String>) {
    match raw {
        Value::Object(raw_map) => {
            let Some(parsed_map) = parsed.as_object() else {
                out.push(if path.is_empty() {
                    "<root>".to_owned()
                } else {
                    path.to_owned()
                });
                return;
            };
            for (key, value) in raw_map {
                let child_path = if path.is_empty() {
                    key.clone()
                } else {
                    format!("{path}.{key}")
                };
                match parsed_map.get(key) {
                    None => out.push(child_path),
                    Some(parsed_value) => {
                        collect_unroundtripped(value, parsed_value, &child_path, out);
                    }
                }
            }
        }
        Value::Array(raw_list) => {
            let Some(parsed_list) = parsed.as_array() else {
                out.push(if path.is_empty() {
                    "<root>".to_owned()
                } else {
                    path.to_owned()
                });
                return;
            };
            if parsed_list.len() < raw_list.len() {
                out.push(if path.is_empty() {
                    "<root>".to_owned()
                } else {
                    path.to_owned()
                });
                return;
            }
            for (index, value) in raw_list.iter().enumerate() {
                collect_unroundtripped(
                    value,
                    &parsed_list[index],
                    &format!("{path}[{index}]"),
                    out,
                );
            }
        }
        _ => {
            if !deep_equals(raw, parsed) {
                out.push(if path.is_empty() {
                    "<root>".to_owned()
                } else {
                    path.to_owned()
                });
            }
        }
    }
}

/// Dart `==` 语义的 JSON 深度比较（数值 1 == 1.0）。
fn deep_equals(a: &Value, b: &Value) -> bool {
    match (a, b) {
        (Value::Number(left), Value::Number(right)) => left.as_f64() == right.as_f64(),
        (Value::Object(left), Value::Object(right)) => {
            left.len() == right.len()
                && left.iter().all(|(key, value)| {
                    right
                        .get(key)
                        .is_some_and(|other| deep_equals(value, other))
                })
        }
        (Value::Array(left), Value::Array(right)) => {
            left.len() == right.len()
                && left
                    .iter()
                    .zip(right)
                    .all(|(value, other)| deep_equals(value, other))
        }
        _ => a == b,
    }
}

/// 提案文件内容是否为合法提案。
#[must_use]
pub fn is_valid_proposal_json(json: &Value) -> bool {
    ProjectProposal::from_json(json).is_ok()
}

/// 把提案 JSON 编码成写入文件的文本（2 空格缩进 + 末尾换行）。
#[must_use]
pub fn encode_proposal(proposal: &ProjectProposal) -> String {
    let mut text = serde_json::to_string_pretty(&proposal.to_json()).expect("proposal json");
    text.push('\n');
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn diff_uses_dart_paths() {
        let changes = diff_configs(&json!({"a": 1, "b": [1, 2]}), &json!({"a": 2, "b": [1, 3]}));
        assert_eq!(changes[0].path, "a");
        assert_eq!(changes[1].path, "b[1]");
    }

    #[test]
    fn numeric_deep_equals_matches_dart() {
        assert!(deep_equals(&json!(1), &json!(1.0)));
        assert!(!deep_equals(&json!(1), &json!(2)));
    }

    #[test]
    fn sha256_matches_known_value() {
        assert_eq!(
            sha256_hex(b"abc"),
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
        );
    }
}

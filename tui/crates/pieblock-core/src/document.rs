//! 项目文档：`.pieproj` 信封、向导进度、格式版本门禁与迁移入口。
//!
//! 读取语义与 Dart `ProjectDocument.fromJson` 一致：格式 17–23 可读，打开后
//! 由调用方按格式 23 写回；JSON 键序与 Dart `toJson` 相同，保存文本目标为逐字节
//! 一致（2 空格缩进 + 末尾换行）。

use serde_json::{Map, Value};

use crate::ids::now_iso8601;
use crate::json::{JsonMap, as_map, child_map, field, int_of, string_field, to_dart_string};
use crate::model::{DebugConfig, EngineerConfig, InfantryConfig, MusicConfig, ProjectConfig};
use crate::{FORMAT_VERSION, OLDEST_SUPPORTED_FORMAT_VERSION, ProjectKind};

/// 读取/版本校验错误。文案与 Flutter 版逐字一致。
#[derive(Debug, thiserror::Error, PartialEq, Eq)]
pub enum DocumentError {
    #[error("项目文件不是有效的 JSON 对象")]
    NotAnObject,
    #[error("工程格式版本 {0} 过旧，请使用 PIE-Block 1.7 或更新版本打开（本版本支持 17–23）")]
    TooOld(String),
    #[error(
        "工程由更新版本的 PIE-Block 创建（格式 {version}），请升级后再打开（本版本支持 17–23）"
    )]
    TooNew { version: i64 },
}

/// 向导进度：稳定步骤 ID 与已访问步骤。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GuideProgress {
    pub current_step_id: String,
    pub visited_step_ids: Vec<String>,
}

impl GuideProgress {
    #[must_use]
    pub fn initial(kind: ProjectKind) -> Self {
        let first = first_step_id(kind);
        Self {
            current_step_id: first.to_owned(),
            visited_step_ids: vec![first.to_owned()],
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert(
            "current_step_id".to_owned(),
            Value::String(self.current_step_id.clone()),
        );
        map.insert(
            "visited_step_ids".to_owned(),
            Value::Array(
                self.visited_step_ids
                    .iter()
                    .map(|step| Value::String(step.clone()))
                    .collect(),
            ),
        );
        Value::Object(map)
    }

    #[must_use]
    pub fn from_json(map: &JsonMap, kind: ProjectKind) -> Self {
        let first = first_step_id(kind);
        let current_step_id =
            string_field(map, "current_step_id").unwrap_or_else(|| first.to_owned());
        let visited_step_ids = match field(map, "visited_step_ids") {
            Some(Value::Array(items)) => items.iter().map(to_dart_string).collect(),
            _ => vec![first.to_owned()],
        };
        Self {
            current_step_id,
            visited_step_ids,
        }
    }
}

fn first_step_id(kind: ProjectKind) -> &'static str {
    match kind {
        ProjectKind::Debug => "tests",
        ProjectKind::Music => "music",
        ProjectKind::Infantry | ProjectKind::Engineer => "remote",
    }
}

/// `.pieproj` 文档。
#[derive(Debug, Clone, PartialEq)]
pub struct ProjectDocument {
    pub kind: ProjectKind,
    pub created_at: String,
    pub updated_at: String,
    pub config: ProjectConfig,
    pub guide_progress: GuideProgress,
    /// 读入时文件里的 `format_version`；只用于判断是否需要自动升版写回。
    pub source_format_version: i64,
}

impl ProjectDocument {
    #[must_use]
    pub fn create(kind: ProjectKind) -> Self {
        let now = now_iso8601();
        Self {
            kind,
            created_at: now.clone(),
            updated_at: now,
            config: default_config(kind),
            guide_progress: GuideProgress::initial(kind),
            source_format_version: i64::from(FORMAT_VERSION),
        }
    }

    #[must_use]
    pub fn copy_with(
        &self,
        config: Option<ProjectConfig>,
        guide_progress: Option<GuideProgress>,
    ) -> Self {
        Self {
            kind: self.kind,
            created_at: self.created_at.clone(),
            updated_at: now_iso8601(),
            config: config.unwrap_or_else(|| self.config.clone()),
            guide_progress: guide_progress.unwrap_or_else(|| self.guide_progress.clone()),
            source_format_version: self.source_format_version,
        }
    }

    /// 与 Dart `toJson()` 相同的键序。
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("format_version".to_owned(), Value::from(FORMAT_VERSION));
        map.insert(
            "project_kind".to_owned(),
            Value::String(self.kind.as_str().to_owned()),
        );
        map.insert(
            "created_at".to_owned(),
            Value::String(self.created_at.clone()),
        );
        map.insert(
            "updated_at".to_owned(),
            Value::String(self.updated_at.clone()),
        );
        map.insert("guide_progress".to_owned(), self.guide_progress.to_json());
        map.insert("config".to_owned(), self.config.to_json());
        Value::Object(map)
    }

    /// 与 `JsonEncoder.withIndent('  ')` + 末尾换行等价的保存文本。
    #[must_use]
    pub fn to_pretty_string(&self) -> String {
        let mut text =
            serde_json::to_string_pretty(&self.to_json()).unwrap_or_else(|_| "{}".to_owned());
        text.push('\n');
        text
    }

    /// 读取并校验版本；字段宽松解析与 Dart 版一致。
    ///
    /// # Errors
    ///
    /// 非对象、格式早于 17 或晚于 23 时返回 [`DocumentError`]。
    pub fn from_json(value: &Value) -> Result<Self, DocumentError> {
        let map = as_map(Some(value)).ok_or(DocumentError::NotAnObject)?;
        let version = int_of(field(map, "format_version"));
        let version = match version {
            Some(version) if version >= i64::from(OLDEST_SUPPORTED_FORMAT_VERSION) => version,
            Some(version) => return Err(DocumentError::TooOld(version.to_string())),
            None => return Err(DocumentError::TooOld("缺失".to_owned())),
        };
        if version > i64::from(FORMAT_VERSION) {
            return Err(DocumentError::TooNew { version });
        }

        let kind = ProjectKind::from_value_or(field(map, "project_kind"), ProjectKind::Infantry);
        let created_at = string_field(map, "created_at")
            .filter(|text| !text.is_empty())
            .unwrap_or_else(now_iso8601);
        let updated_at = string_field(map, "updated_at")
            .filter(|text| !text.is_empty())
            .unwrap_or_else(|| created_at.clone());
        let empty = JsonMap::new();
        let guide_progress =
            GuideProgress::from_json(child_map(map, "guide_progress").unwrap_or(&empty), kind);
        let config_map = child_map(map, "config").unwrap_or(&empty);
        let config = match kind {
            ProjectKind::Infantry => ProjectConfig::Infantry(InfantryConfig::from_json(config_map)),
            ProjectKind::Engineer => ProjectConfig::Engineer(EngineerConfig::from_json(config_map)),
            ProjectKind::Debug => ProjectConfig::Debug(DebugConfig::from_json(config_map)),
            ProjectKind::Music => ProjectConfig::Music(MusicConfig::from_json(config_map)),
        };
        Ok(Self {
            kind,
            created_at,
            updated_at,
            config,
            guide_progress,
            source_format_version: version,
        })
    }
}

fn default_config(kind: ProjectKind) -> ProjectConfig {
    match kind {
        ProjectKind::Infantry => ProjectConfig::Infantry(InfantryConfig::default()),
        ProjectKind::Engineer => ProjectConfig::Engineer(EngineerConfig::default()),
        ProjectKind::Debug => ProjectConfig::Debug(DebugConfig::default()),
        ProjectKind::Music => ProjectConfig::Music(MusicConfig::default()),
    }
}

/// 供 golden 生成/测试复用：把文档包成 `{source,kind,sourceFormatVersion,document}`。
#[must_use]
pub fn golden_wrapper(source: &str, document: &ProjectDocument) -> Value {
    let mut map = Map::new();
    map.insert("source".to_owned(), Value::String(source.to_owned()));
    map.insert(
        "kind".to_owned(),
        Value::String(document.kind.as_str().to_owned()),
    );
    map.insert(
        "sourceFormatVersion".to_owned(),
        Value::from(document.source_format_version),
    );
    map.insert("document".to_owned(), document.to_json());
    Value::Object(map)
}

#[cfg(test)]
mod tests {
    use serde_json::json;

    use super::*;
    use crate::model::ChassisConfig;

    #[test]
    fn rejects_missing_old_and_new_versions_with_exact_messages() {
        let error = ProjectDocument::from_json(&json!({})).unwrap_err();
        assert_eq!(
            error.to_string(),
            "工程格式版本 缺失 过旧，请使用 PIE-Block 1.7 或更新版本打开（本版本支持 17–23）"
        );
        let error = ProjectDocument::from_json(&json!({"format_version": 16})).unwrap_err();
        assert_eq!(
            error.to_string(),
            "工程格式版本 16 过旧，请使用 PIE-Block 1.7 或更新版本打开（本版本支持 17–23）"
        );
        let error = ProjectDocument::from_json(&json!({"format_version": 24})).unwrap_err();
        assert_eq!(
            error.to_string(),
            "工程由更新版本的 PIE-Block 创建（格式 24），请升级后再打开（本版本支持 17–23）"
        );
    }

    #[test]
    fn missing_kind_falls_back_to_infantry() {
        let document = ProjectDocument::from_json(&json!({"format_version": 23})).unwrap();
        assert_eq!(document.kind, ProjectKind::Infantry);
        let ProjectConfig::Infantry(config) = &document.config else {
            panic!("expected infantry config");
        };
        // Dart `InfantryConfig.fromJson` 传入空 config：轴执行器列表为空，
        // 不会回退到构造函数的“默认 1 个空执行器”。
        assert!(config.yaw.is_empty());
        assert!(config.pitch.is_empty());
        assert_eq!(config.chassis, ChassisConfig::default());
    }

    #[test]
    fn guide_progress_defaults_follow_kind() {
        let debug = ProjectDocument::from_json(&json!({
            "format_version": 23,
            "project_kind": "debug"
        }))
        .unwrap();
        assert_eq!(debug.guide_progress.current_step_id, "tests");
        let music = ProjectDocument::from_json(&json!({
            "format_version": 23,
            "project_kind": "music"
        }))
        .unwrap();
        assert_eq!(music.guide_progress.current_step_id, "music");
    }

    #[test]
    fn created_document_is_current_format() {
        for kind in ProjectKind::ALL {
            let document = ProjectDocument::create(kind);
            assert_eq!(document.kind, kind);
            assert_eq!(document.source_format_version, i64::from(FORMAT_VERSION));
            assert!(document.created_at.ends_with('Z'));
            assert!(document.to_pretty_string().ends_with("}\n"));
        }
    }
}

//! 构建领域模型（与 `models.dart` 对齐）。

use serde_json::{Map, Value};

/// 编译器种类。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum CompilerKind {
    Sdcc,
    Keil,
}

impl CompilerKind {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Sdcc => "sdcc",
            Self::Keil => "keil",
        }
    }

    #[must_use]
    pub fn from_str_lenient(text: &str) -> Option<Self> {
        match text {
            "sdcc" => Some(Self::Sdcc),
            "keil" => Some(Self::Keil),
            _ => None,
        }
    }
}

/// 构建阶段。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildStage {
    Preparing,
    Compiling,
    Linking,
    Validating,
    Done,
}

impl BuildStage {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Preparing => "preparing",
            Self::Compiling => "compiling",
            Self::Linking => "linking",
            Self::Validating => "validating",
            Self::Done => "done",
        }
    }
}

/// 构建事件级别。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BuildEventLevel {
    Info,
    Warning,
    Error,
}

impl BuildEventLevel {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Info => "info",
            Self::Warning => "warning",
            Self::Error => "error",
        }
    }
}

/// 一次构建请求。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildRequest {
    pub project_kind: pieblock_core::ProjectKind,
    pub source_code: String,
    pub compiler: CompilerKind,
    pub compiler_fingerprint: String,
    pub keil_root: Option<String>,
}

/// 一条构建进度事件。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildEvent {
    pub stage: BuildStage,
    pub level: BuildEventLevel,
    pub message: String,
    pub current: Option<i64>,
    pub total: Option<i64>,
}

/// 构建指纹。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildFingerprint {
    pub value: String,
    pub source_hash: String,
}

/// 构建产物元数据（持久化到 `.json`）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildArtifact {
    pub hex_path: String,
    pub hex_sha256: String,
    pub fingerprint: String,
    pub source_sha256: String,
    pub compiler: CompilerKind,
    pub compiler_fingerprint: String,
    pub template_version: String,
    pub built_at: String,
    pub byte_count: i64,
    pub warning_count: i64,
    pub last_flashed_at: Option<String>,
}

impl BuildArtifact {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("hex_path".to_owned(), Value::String(self.hex_path.clone()));
        map.insert(
            "hex_sha256".to_owned(),
            Value::String(self.hex_sha256.clone()),
        );
        map.insert(
            "fingerprint".to_owned(),
            Value::String(self.fingerprint.clone()),
        );
        map.insert(
            "source_sha256".to_owned(),
            Value::String(self.source_sha256.clone()),
        );
        map.insert(
            "compiler".to_owned(),
            Value::String(self.compiler.as_str().to_owned()),
        );
        map.insert(
            "compiler_fingerprint".to_owned(),
            Value::String(self.compiler_fingerprint.clone()),
        );
        map.insert(
            "template_version".to_owned(),
            Value::String(self.template_version.clone()),
        );
        map.insert("built_at".to_owned(), Value::String(self.built_at.clone()));
        map.insert("byte_count".to_owned(), Value::from(self.byte_count));
        map.insert("warning_count".to_owned(), Value::from(self.warning_count));
        if let Some(last) = &self.last_flashed_at {
            map.insert("last_flashed_at".to_owned(), Value::String(last.clone()));
        }
        Value::Object(map)
    }

    /// 解析产物元数据；缺字段或类型错误返回错误文案。
    pub fn from_json(json: &Value) -> Result<Self, String> {
        let map = json
            .as_object()
            .ok_or_else(|| "产物元数据不是对象".to_owned())?;
        let string = |key: &str| -> Result<String, String> {
            map.get(key)
                .and_then(Value::as_str)
                .map(str::to_owned)
                .ok_or_else(|| format!("产物元数据缺少 {key}"))
        };
        let compiler = CompilerKind::from_str_lenient(&string("compiler")?)
            .ok_or_else(|| "产物元数据编译器类型未知".to_owned())?;
        Ok(Self {
            hex_path: string("hex_path")?,
            hex_sha256: string("hex_sha256")?,
            fingerprint: string("fingerprint")?,
            source_sha256: string("source_sha256")?,
            compiler,
            compiler_fingerprint: string("compiler_fingerprint")?,
            template_version: string("template_version")?,
            built_at: string("built_at")?,
            byte_count: map
                .get("byte_count")
                .and_then(Value::as_i64)
                .ok_or_else(|| "产物元数据缺少 byte_count".to_owned())?,
            warning_count: map
                .get("warning_count")
                .and_then(Value::as_i64)
                .ok_or_else(|| "产物元数据缺少 warning_count".to_owned())?,
            last_flashed_at: map
                .get("last_flashed_at")
                .and_then(Value::as_str)
                .map(str::to_owned),
        })
    }

    #[must_use]
    pub fn with_last_flashed_at(&self, last_flashed_at: Option<String>) -> Self {
        let mut copy = self.clone();
        if last_flashed_at.is_some() {
            copy.last_flashed_at = last_flashed_at;
        }
        copy
    }
}

/// 一次构建的结果。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BuildResult {
    pub success: bool,
    pub artifact: Option<BuildArtifact>,
    pub log: String,
    pub exit_code: Option<i64>,
    pub canceled: bool,
    pub license_failure: bool,
    /// 链接后产出的 `main_<序号>.rst` 列表文件原文。
    pub listing: Option<String>,
}

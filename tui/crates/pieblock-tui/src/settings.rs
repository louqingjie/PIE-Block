//! 应用设置：主题、最近项目、编译器与引导开关。
//!
//! 与 Flutter 版 `settings.json` 字段对齐（`theme` / `recent` / `compiler` /
//! `keil_path` / `suppress_flash_guide` / `suppress_template_guide`）；TUI 使用
//! 自己的应用数据目录，不与 Flutter 版共享文件。

use std::path::{Path, PathBuf};

use pieblock_core::ProjectKind;
use pieblock_toolchain::models::CompilerKind;
use serde_json::{Map, Value};

/// 主题偏好。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ThemePreference {
    #[default]
    System,
    Light,
    Dark,
}

impl ThemePreference {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::System => "system",
            Self::Light => "light",
            Self::Dark => "dark",
        }
    }

    #[must_use]
    pub fn from_str_lenient(text: &str) -> Self {
        match text {
            "light" => Self::Light,
            "dark" => Self::Dark,
            _ => Self::System,
        }
    }

    #[must_use]
    pub const fn next(self) -> Self {
        match self {
            Self::System => Self::Light,
            Self::Light => Self::Dark,
            Self::Dark => Self::System,
        }
    }
}

/// 最近项目条目。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecentProject {
    pub path: String,
    pub kind: Option<ProjectKind>,
}

impl RecentProject {
    /// 解析一条设置记录：新格式 `{path, kind}`，旧格式纯路径字符串。
    #[must_use]
    pub fn from_setting(value: &Value) -> Option<Self> {
        if let Some(path) = value.as_str() {
            let path = path.trim();
            if path.is_empty() {
                return None;
            }
            return Some(Self {
                path: path.to_owned(),
                kind: None,
            });
        }
        let map = value.as_object()?;
        let path = map.get("path")?.as_str()?.trim();
        if path.is_empty() {
            return None;
        }
        let kind = map
            .get("kind")
            .and_then(Value::as_str)
            .and_then(ProjectKind::from_str_lenient);
        Some(Self {
            path: path.to_owned(),
            kind,
        })
    }

    #[must_use]
    pub fn to_setting(&self) -> Value {
        let mut map = Map::new();
        map.insert("path".to_owned(), Value::String(self.path.clone()));
        if let Some(kind) = self.kind {
            map.insert("kind".to_owned(), Value::String(kind.as_str().to_owned()));
        }
        Value::Object(map)
    }
}

/// 应用设置。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AppSettings {
    pub theme: ThemePreference,
    pub recent: Vec<RecentProject>,
    pub compiler: CompilerKind,
    pub keil_path: Option<String>,
    pub suppress_flash_guide: bool,
    pub suppress_template_guide: bool,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            theme: ThemePreference::System,
            recent: Vec::new(),
            compiler: CompilerKind::Sdcc,
            keil_path: None,
            suppress_flash_guide: false,
            suppress_template_guide: false,
        }
    }
}

impl AppSettings {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert(
            "theme".to_owned(),
            Value::String(self.theme.as_str().to_owned()),
        );
        map.insert(
            "recent".to_owned(),
            Value::Array(self.recent.iter().map(RecentProject::to_setting).collect()),
        );
        map.insert(
            "compiler".to_owned(),
            Value::String(self.compiler.as_str().to_owned()),
        );
        if let Some(path) = &self.keil_path {
            map.insert("keil_path".to_owned(), Value::String(path.clone()));
        }
        map.insert(
            "suppress_flash_guide".to_owned(),
            Value::Bool(self.suppress_flash_guide),
        );
        map.insert(
            "suppress_template_guide".to_owned(),
            Value::Bool(self.suppress_template_guide),
        );
        Value::Object(map)
    }

    /// 解析设置；缺省/非法字段回退默认值。
    #[must_use]
    pub fn from_json(json: &Value) -> Self {
        let mut settings = Self::default();
        let Some(map) = json.as_object() else {
            return settings;
        };
        if let Some(theme) = map.get("theme").and_then(Value::as_str) {
            settings.theme = ThemePreference::from_str_lenient(theme);
        }
        if let Some(recent) = map.get("recent").and_then(Value::as_array) {
            for entry in recent.iter().take(8) {
                if let Some(project) = RecentProject::from_setting(entry) {
                    settings.recent.push(project);
                }
            }
        }
        if let Some(compiler) = map.get("compiler").and_then(Value::as_str) {
            settings.compiler =
                CompilerKind::from_str_lenient(compiler).unwrap_or(CompilerKind::Sdcc);
        }
        settings.keil_path = map
            .get("keil_path")
            .and_then(Value::as_str)
            .map(str::to_owned);
        settings.suppress_flash_guide = map
            .get("suppress_flash_guide")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        settings.suppress_template_guide = map
            .get("suppress_template_guide")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        settings
    }

    /// 合并最近项目：当前在前、按路径去重、最多 8 条。
    #[must_use]
    pub fn merge_recent(current: &[RecentProject], loaded: &[RecentProject]) -> Vec<RecentProject> {
        let mut seen: Vec<&str> = Vec::new();
        let mut merged = Vec::new();
        for project in current.iter().chain(loaded) {
            if seen.contains(&project.path.as_str()) {
                continue;
            }
            seen.push(&project.path);
            merged.push(project.clone());
            if merged.len() >= 8 {
                break;
            }
        }
        merged
    }

    /// 把项目提到最近列表首位（打开/新建时）。
    pub fn adopt_recent(&mut self, path: &str, kind: ProjectKind) {
        self.recent.retain(|project| project.path != path);
        self.recent.insert(
            0,
            RecentProject {
                path: path.to_owned(),
                kind: Some(kind),
            },
        );
        self.recent.truncate(8);
    }
}

/// 设置存储。
pub struct SettingsStore {
    pub path: PathBuf,
}

impl SettingsStore {
    #[must_use]
    pub fn new(path: impl Into<PathBuf>) -> Self {
        Self { path: path.into() }
    }

    /// 读取设置；文件缺失、损坏或不可读均返回默认值。
    #[must_use]
    pub fn load(&self) -> AppSettings {
        let Ok(text) = std::fs::read_to_string(&self.path) else {
            return AppSettings::default();
        };
        match serde_json::from_str::<Value>(&text) {
            Ok(Value::Object(map)) => AppSettings::from_json(&Value::Object(map)),
            _ => AppSettings::default(),
        }
    }

    /// 同步保存；目录不可写等错误交由调用方决定是否提示。
    pub fn save(&self, settings: &AppSettings) -> std::io::Result<()> {
        if let Some(parent) = self.path.parent() {
            std::fs::create_dir_all(parent)?;
        }
        let text = serde_json::to_string(&settings.to_json())
            .map_err(|error| std::io::Error::new(std::io::ErrorKind::InvalidData, error))?;
        atomic_write(&self.path, text.as_bytes())
    }

    /// 加载后清理已不存在的桌面项目，并尝试补全缺失的类型。
    pub fn load_cleaned<F>(&self, mut read_kind: F) -> AppSettings
    where
        F: FnMut(&str) -> Option<ProjectKind>,
    {
        let mut settings = self.load();
        settings
            .recent
            .retain(|project| Path::new(&project.path).exists());
        for project in &mut settings.recent {
            if project.kind.is_none() {
                project.kind = read_kind(&project.path);
            }
        }
        settings
    }
}

/// 同目录临时文件 + rename 原子写。
pub fn atomic_write(path: &Path, bytes: &[u8]) -> std::io::Result<()> {
    if let Some(parent) = path.parent() {
        std::fs::create_dir_all(parent)?;
    }
    let micros = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .map_or(0, |duration| duration.as_micros());
    let temporary = path.with_file_name(format!(
        "{}.tmp-{micros}",
        path.file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("file")
    ));
    let result = (|| {
        use std::io::Write;
        let mut file = std::fs::File::create(&temporary)?;
        file.write_all(bytes)?;
        file.flush()?;
        file.sync_all()?;
        drop(file);
        std::fs::rename(&temporary, path)?;
        Ok(())
    })();
    if result.is_err() && temporary.exists() {
        let _ = std::fs::remove_file(&temporary);
    }
    result
}

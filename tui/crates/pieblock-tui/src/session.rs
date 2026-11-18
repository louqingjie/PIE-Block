//! 打开/保存工程会话：真实 `.pieproj` 读写、旧格式自动升版、原子保存。

use std::path::{Path, PathBuf};

use pieblock_core::model::ProjectConfig;
use pieblock_core::{FORMAT_VERSION, ProjectDocument, ProjectKind};

use crate::settings::atomic_write;

/// 保存状态（用于状态栏徽标）。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum SaveStatus {
    #[default]
    Saved,
    Saving,
    Failed,
}

impl SaveStatus {
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Saved => "已保存",
            Self::Saving => "保存中…",
            Self::Failed => "保存失败",
        }
    }
}

/// 会话错误（文案已可直接展示）。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SessionError {
    Io(String),
    Json(String),
    Document(String),
}

impl std::fmt::Display for SessionError {
    fn fmt(&self, formatter: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Io(message) | Self::Json(message) | Self::Document(message) => {
                formatter.write_str(message)
            }
        }
    }
}

impl std::error::Error for SessionError {}

/// 一个已打开的工程。
#[derive(Debug, Clone)]
pub struct ProjectSession {
    pub document: ProjectDocument,
    pub path: PathBuf,
    pub save_status: SaveStatus,
    /// 打开旧格式并自动写回失败时的提示（打开本身仍成功）。
    pub upgrade_warning: Option<String>,
}

impl ProjectSession {
    /// 新建工程并立即落盘。
    ///
    /// `template` 只替换配置；时间戳与引导进度按本次创建生成，不留模板痕迹。
    pub fn create(
        path: impl AsRef<Path>,
        kind: ProjectKind,
        template: Option<ProjectConfig>,
    ) -> Result<Self, SessionError> {
        let path = normalized_project_path(path.as_ref());
        let mut document = ProjectDocument::create(kind);
        if let Some(template) = template {
            document = document.copy_with(Some(template), None);
        }
        let mut session = Self {
            document,
            path,
            save_status: SaveStatus::Saved,
            upgrade_warning: None,
        };
        session.save_now()?;
        Ok(session)
    }

    /// 打开工程；`format 17–22` 自动迁移并在写回成功时保存为当前格式。
    pub fn open(path: impl AsRef<Path>) -> Result<Self, SessionError> {
        let path = path.as_ref().to_path_buf();
        let bytes = std::fs::read(&path)
            .map_err(|error| SessionError::Io(format!("读取工程失败：{error}")))?;
        let text = String::from_utf8_lossy(&bytes);
        let json: serde_json::Value = serde_json::from_str(&text)
            .map_err(|error| SessionError::Json(format!("工程文件不是合法 JSON：{error}")))?;
        let document = ProjectDocument::from_json(&json)
            .map_err(|error| SessionError::Document(error.to_string()))?;
        let needs_upgrade = document.source_format_version < i64::from(FORMAT_VERSION);
        let mut session = Self {
            document,
            path,
            save_status: SaveStatus::Saved,
            upgrade_warning: None,
        };
        if needs_upgrade {
            if let Err(error) = session.save_now() {
                session.save_status = SaveStatus::Failed;
                session.upgrade_warning = Some(format!(
                    "项目已打开，但自动升级到格式 {FORMAT_VERSION} 失败：{error}"
                ));
            }
        }
        Ok(session)
    }

    /// 记录配置编辑（时间戳更新，状态置为保存中；调用方做 500ms 防抖）。
    pub fn update_config(&mut self, config: ProjectConfig) {
        self.document = self.document.copy_with(Some(config), None);
        self.save_status = SaveStatus::Saving;
    }

    /// 立即保存；成功返回 `UpdatedAt` 文档文本长度不需要，调用方可只关心状态。
    pub fn save_now(&mut self) -> Result<(), SessionError> {
        self.save_status = SaveStatus::Saving;
        let text = self.document.to_pretty_string();
        match atomic_write(&self.path, text.as_bytes()) {
            Ok(()) => {
                self.save_status = SaveStatus::Saved;
                self.upgrade_warning = None;
                Ok(())
            }
            Err(error) => {
                self.save_status = SaveStatus::Failed;
                Err(SessionError::Io(format!(
                    "保存工程失败（{}）：{error}",
                    self.path.display()
                )))
            }
        }
    }

    /// 显示名（文件名去掉 `.pieproj`）。
    #[must_use]
    pub fn display_name(&self) -> String {
        project_display_name(&self.path.display().to_string())
    }

    /// 文件是否可再次读取（最近项目校验）。
    #[must_use]
    pub fn exists(path: &Path) -> bool {
        path.is_file()
    }
}

/// 文件名去掉 `.pieproj` 的显示名；空名回退「未命名项目」。
#[must_use]
pub fn project_display_name(path: &str) -> String {
    const SUFFIX: &str = ".pieproj";
    let file_name = path.rsplit(['/', '\\']).next().unwrap_or(path);
    let name = if file_name.to_lowercase().ends_with(SUFFIX) {
        &file_name[..file_name.len() - SUFFIX.len()]
    } else {
        file_name
    };
    if name.is_empty() {
        "未命名项目".to_owned()
    } else {
        name.to_owned()
    }
}

fn normalized_project_path(path: &Path) -> PathBuf {
    let text = path.display().to_string();
    if text.to_lowercase().ends_with(".pieproj") {
        path.to_path_buf()
    } else {
        PathBuf::from(format!("{text}.pieproj"))
    }
}

/// 读取项目类型（最近项目旧数据补全图标）。
#[must_use]
pub fn read_project_kind(path: &str) -> Option<ProjectKind> {
    let bytes = std::fs::read(path).ok()?;
    let text = String::from_utf8_lossy(&bytes);
    let json: serde_json::Value = serde_json::from_str(&text).ok()?;
    ProjectDocument::from_json(&json)
        .ok()
        .map(|document| document.kind)
}

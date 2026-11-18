//! PIE-Block TUI 应用层：可测试的设置、路径与工程会话。
//!
//! 终端界面与交互仍在 `pieblock-tui` 二进制（`app.rs`/`ui.rs`）；本库把
//! 文件/设置/会话等非界面逻辑独立出来，便于单元测试与后续页面接线。

pub mod paths;
pub mod session;
pub mod settings;
pub mod workspace;

pub use paths::{app_data_dir, settings_path, state_dir};
pub use session::{
    ProjectSession, SaveStatus, SessionError, project_display_name, read_project_kind,
};
pub use settings::{AppSettings, RecentProject, SettingsStore, ThemePreference, atomic_write};
pub use workspace::{AUTOSAVE_DELAY, Autosave, Workspace};

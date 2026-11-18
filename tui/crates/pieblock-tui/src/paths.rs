//! TUI 应用数据路径（设置、会话）。

use std::path::PathBuf;

/// 应用数据目录。
///
/// - Windows：`%APPDATA%\PIE-Block`
/// - Linux：`$XDG_CONFIG_HOME/pie-block`，缺省 `~/.config/pie-block`
/// - 其它/无法判定：当前目录下 `.pie-block`
#[must_use]
pub fn app_data_dir() -> PathBuf {
    if cfg!(windows) {
        if let Some(base) = std::env::var_os("APPDATA") {
            return PathBuf::from(base).join("PIE-Block");
        }
    } else if let Some(base) = std::env::var_os("XDG_CONFIG_HOME") {
        return PathBuf::from(base).join("pie-block");
    } else if let Some(home) = std::env::var_os("HOME") {
        return PathBuf::from(home).join(".config").join("pie-block");
    }
    PathBuf::from(".pie-block")
}

/// 设置文件路径。
#[must_use]
pub fn settings_path(data_dir: &std::path::Path) -> PathBuf {
    data_dir.join("settings.json")
}

/// 界面状态/日志目录（后续自动保存恢复文件也放这里）。
#[must_use]
pub fn state_dir(data_dir: &std::path::Path) -> PathBuf {
    data_dir.join("state")
}

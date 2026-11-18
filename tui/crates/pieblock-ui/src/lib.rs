//! PIE-Block TUI 的可复用界面层。

pub mod form;
pub mod pages;
pub mod screens;
pub mod theme;

pub use form::{FieldKind, FieldValue, FormAction, FormField, FormPage, FormState};
pub use pages::{
    debug_tests_page, infantry_controls_page, infantry_mechanism_page, remote_page, wizard_pages,
};
pub use screens::{
    BrowserAction, BrowserEntry, FileBrowser, HomeView, RecentItem, SettingRow, draw_browser,
    draw_dialog, draw_home, draw_settings, draw_status,
};
pub use theme::{Palette, ThemeMode};

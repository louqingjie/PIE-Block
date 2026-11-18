//! PIE-Block TUI 的可复用界面层。

pub mod asm_glossary;
pub mod asm_glossary_data;
pub mod code_view;
pub mod flash;
pub mod form;
pub mod pages;
pub mod piano_roll;
pub mod playback;
pub mod screens;
pub mod staff_view;
pub mod theme;

pub use asm_glossary::GlossaryState;
pub use code_view::CodeView;
pub use flash::{FlashAction, FlashState};
pub use form::{FieldKind, FieldValue, FormAction, FormField, FormPage, FormState};
pub use pages::{
    debug_tests_page, engineer_mappings_page, engineer_pins, engineer_pwm_page,
    engineer_strategy_page, engineer_tables_page, infantry_controls_page, infantry_mechanism_page,
    music_page, remote_page, wizard_pages,
};
pub use piano_roll::{PianoAction, PianoRoll};
pub use playback::{Playback, PlaybackAction};
pub use screens::{
    BrowserAction, BrowserEntry, FileBrowser, HomeView, RecentItem, SettingRow, draw_browser,
    draw_dialog, draw_home, draw_settings, draw_status,
};
pub use staff_view::{staff_header, staff_legend, staff_text};
pub use theme::{Palette, ThemeMode};

//! PIE-Block TUI 的视觉基座：主题、语义色与基础样式。
//!
//! TUI 采用自身风格（见 `docs/design/TUI复刻实现计划.md` §5.0），本模块只定义
//! 稳定的语义 token，不追求与 Flutter Material 3 一一对应。

use ratatui::style::{Color, Modifier, Style};

/// 主题模式。终端无法可靠读取系统主题，因此由用户显式切换并记忆。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum ThemeMode {
    #[default]
    Dark,
    Light,
}

impl ThemeMode {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Dark => "深色",
            Self::Light => "浅色",
        }
    }

    #[must_use]
    pub const fn toggled(self) -> Self {
        match self {
            Self::Dark => Self::Light,
            Self::Light => Self::Dark,
        }
    }
}

/// 语义色板。颜色只用于强调，错误/警告同时配合 `✖`/`⚠` 文本。
#[derive(Debug, Clone, Copy)]
pub struct Palette {
    pub mode: ThemeMode,
    pub brand: Color,
    pub accent: Color,
    pub text: Color,
    pub muted: Color,
    pub border: Color,
    pub border_focused: Color,
    pub ok: Color,
    pub warn: Color,
    pub error: Color,
    pub info: Color,
    pub selection_fg: Color,
    pub selection_bg: Color,
    pub status_fg: Color,
    pub status_bg: Color,
}

impl Palette {
    /// 深色主题：接近终端默认背景，品牌青蓝作强调。
    #[must_use]
    pub const fn dark() -> Self {
        Self {
            mode: ThemeMode::Dark,
            brand: Color::Rgb(2, 172, 192),
            accent: Color::Rgb(239, 104, 93),
            text: Color::Rgb(215, 225, 227),
            muted: Color::Rgb(120, 144, 148),
            border: Color::Rgb(58, 78, 82),
            border_focused: Color::Rgb(2, 172, 192),
            ok: Color::Rgb(100, 200, 140),
            warn: Color::Rgb(240, 190, 90),
            error: Color::Rgb(240, 110, 110),
            info: Color::Rgb(120, 180, 240),
            selection_fg: Color::Rgb(9, 16, 18),
            selection_bg: Color::Rgb(2, 172, 192),
            status_fg: Color::Rgb(215, 225, 227),
            status_bg: Color::Rgb(24, 32, 36),
        }
    }

    /// 浅色主题：面向浅色终端背景。
    #[must_use]
    pub const fn light() -> Self {
        Self {
            mode: ThemeMode::Light,
            brand: Color::Rgb(2, 130, 146),
            accent: Color::Rgb(200, 70, 60),
            text: Color::Rgb(38, 50, 56),
            muted: Color::Rgb(96, 119, 123),
            border: Color::Rgb(170, 183, 186),
            border_focused: Color::Rgb(2, 130, 146),
            ok: Color::Rgb(40, 130, 80),
            warn: Color::Rgb(160, 100, 0),
            error: Color::Rgb(180, 40, 40),
            info: Color::Rgb(40, 100, 180),
            selection_fg: Color::Rgb(255, 255, 255),
            selection_bg: Color::Rgb(2, 130, 146),
            status_fg: Color::Rgb(38, 50, 56),
            status_bg: Color::Rgb(230, 235, 236),
        }
    }

    #[must_use]
    pub const fn for_mode(mode: ThemeMode) -> Self {
        match mode {
            ThemeMode::Dark => Self::dark(),
            ThemeMode::Light => Self::light(),
        }
    }

    #[must_use]
    pub fn title(&self) -> Style {
        Style::default().fg(self.brand).add_modifier(Modifier::BOLD)
    }

    #[must_use]
    pub fn text(&self) -> Style {
        Style::default().fg(self.text)
    }

    #[must_use]
    pub fn muted(&self) -> Style {
        Style::default().fg(self.muted)
    }

    #[must_use]
    pub fn border(&self) -> Style {
        Style::default().fg(self.border)
    }

    #[must_use]
    pub fn border_focused(&self) -> Style {
        Style::default().fg(self.border_focused)
    }

    #[must_use]
    pub fn selection(&self) -> Style {
        Style::default()
            .fg(self.selection_fg)
            .bg(self.selection_bg)
            .add_modifier(Modifier::BOLD)
    }

    #[must_use]
    pub fn status_bar(&self) -> Style {
        Style::default().fg(self.status_fg).bg(self.status_bg)
    }

    #[must_use]
    pub fn ok(&self) -> Style {
        Style::default().fg(self.ok)
    }

    #[must_use]
    pub fn warn(&self) -> Style {
        Style::default().fg(self.warn)
    }

    #[must_use]
    pub fn error(&self) -> Style {
        Style::default().fg(self.error)
    }

    #[must_use]
    pub fn info(&self) -> Style {
        Style::default().fg(self.info)
    }

    #[must_use]
    pub fn accent(&self) -> Style {
        Style::default()
            .fg(self.accent)
            .add_modifier(Modifier::BOLD)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn palettes_are_distinct() {
        let dark = Palette::dark();
        let light = Palette::light();
        assert_eq!(dark.mode, ThemeMode::Dark);
        assert_eq!(light.mode, ThemeMode::Light);
        assert_ne!(dark.selection_bg, light.selection_bg);
        assert_eq!(ThemeMode::Dark.toggled(), ThemeMode::Light);
        assert_eq!(ThemeMode::Light.toggled(), ThemeMode::Dark);
    }

    #[test]
    fn palette_for_mode_matches() {
        assert_eq!(Palette::for_mode(ThemeMode::Dark).mode, ThemeMode::Dark);
        assert_eq!(Palette::for_mode(ThemeMode::Light).mode, ThemeMode::Light);
    }
}

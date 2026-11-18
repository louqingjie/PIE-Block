//! M5 代码/汇编预览：带行号与滚动、关键字高亮的只读视图。

use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::Modifier;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};

use crate::theme::Palette;

/// 代码视图状态。
#[derive(Debug, Clone, Default)]
pub struct CodeView {
    pub lines: Vec<String>,
    pub scroll: usize,
    pub title: String,
}

impl CodeView {
    #[must_use]
    pub fn new(title: impl Into<String>, source: &str) -> Self {
        Self {
            lines: source.lines().map(str::to_owned).collect(),
            scroll: 0,
            title: title.into(),
        }
    }

    pub fn scroll_by(&mut self, delta: i32, visible: usize) {
        let max = self.lines.len().saturating_sub(visible.max(1));
        let next = i64::try_from(self.scroll).unwrap_or(0) + i64::from(delta);
        self.scroll = usize::try_from(next.clamp(0, i64::try_from(max).unwrap_or(0))).unwrap_or(0);
    }

    pub fn scroll_to(&mut self, line: usize, visible: usize) {
        let max = self.lines.len().saturating_sub(visible.max(1));
        self.scroll = line.min(max);
    }

    #[must_use]
    pub fn len(&self) -> usize {
        self.lines.len()
    }

    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.lines.is_empty()
    }

    /// 渲染；`message` 显示在底部（保存/导出结果）。
    pub fn render(
        &mut self,
        frame: &mut Frame,
        area: Rect,
        show_line_numbers: bool,
        palette: &Palette,
        message: Option<&str>,
    ) {
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(palette.border_focused())
            .title(Span::styled(
                self.title.clone(),
                ratatui::style::Style::default().add_modifier(Modifier::BOLD),
            ))
            .title_bottom(Span::styled(
                format!(
                    " 行 {}/{} · ↑↓/PgUp/PgDn 滚动 · W 导出 · Esc 返回{} ",
                    (self.scroll + 1).min(self.lines.len().max(1)),
                    self.lines.len(),
                    message.map_or_else(String::new, |message| format!(" · {message}"))
                ),
                palette.muted(),
            ));
        let inner = block.inner(area);
        frame.render_widget(block, area);
        let visible = usize::from(inner.height);
        let lines: Vec<Line> = self
            .lines
            .iter()
            .enumerate()
            .skip(self.scroll)
            .take(visible)
            .map(|(index, text)| {
                let mut spans = Vec::new();
                if show_line_numbers {
                    spans.push(Span::styled(format!("{:>5} ", index + 1), palette.muted()));
                }
                spans.extend(highlight(text, palette));
                Line::from(spans)
            })
            .collect();
        frame.render_widget(Paragraph::new(lines), inner);
    }
}

/// 简单语法着色：注释/预处理/关键字/字符串/数字。
fn highlight(line: &str, palette: &Palette) -> Vec<Span<'static>> {
    let trimmed = line.trim_start();
    if trimmed.starts_with("//") || trimmed.starts_with("/*") || trimmed.starts_with('*') {
        return vec![Span::styled(
            line.to_owned(),
            palette.muted().add_modifier(Modifier::ITALIC),
        )];
    }
    if trimmed.starts_with('#') {
        return vec![Span::styled(line.to_owned(), palette.warn())];
    }
    let mut spans = Vec::new();
    let mut word = String::new();
    let flush_word = |spans: &mut Vec<Span<'static>>, word: &mut String| {
        if word.is_empty() {
            return;
        }
        let style = if is_keyword(word) {
            palette.info().add_modifier(Modifier::BOLD)
        } else if word.chars().all(|ch| ch.is_ascii_digit()) {
            palette.accent()
        } else {
            palette.text()
        };
        spans.push(Span::styled(std::mem::take(word), style));
    };
    for character in line.chars() {
        if character.is_alphanumeric() || character == '_' {
            word.push(character);
            continue;
        }
        flush_word(&mut spans, &mut word);
        spans.push(Span::styled(character.to_string(), palette.text()));
    }
    flush_word(&mut spans, &mut word);
    if spans.is_empty() {
        spans.push(Span::styled(String::new(), palette.text()));
    }
    spans
}

fn is_keyword(word: &str) -> bool {
    matches!(
        word,
        "if" | "else"
            | "for"
            | "while"
            | "switch"
            | "case"
            | "break"
            | "continue"
            | "return"
            | "void"
            | "int"
            | "unsigned"
            | "char"
            | "static"
            | "const"
            | "struct"
            | "typedef"
            | "include"
            | "define"
            | "__interrupt"
            | "main"
    )
}

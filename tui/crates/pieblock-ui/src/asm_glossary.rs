//! 汇编术语查询浮层：完整 AS251 词表（指令/寄存器/段/伪指令/记号/SFR/位）。

use crossterm::event::{KeyCode, KeyEvent};
use ratatui::Frame;
use ratatui::layout::Rect;
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph};

use crate::asm_glossary_data::{ASM_GLOSSARY, GlossaryEntry};
use crate::theme::Palette;

/// 术语表浮层状态。
#[derive(Debug, Clone, Default)]
pub struct GlossaryState {
    pub selected: usize,
    pub offset: usize,
}

impl GlossaryState {
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    #[must_use]
    pub fn count() -> usize {
        ASM_GLOSSARY.len()
    }

    #[must_use]
    pub fn entry(&self) -> Option<&'static GlossaryEntry> {
        ASM_GLOSSARY.get(self.selected)
    }

    /// 返回 true 表示关闭浮层。
    pub fn handle_key(&mut self, key: KeyEvent) -> bool {
        match key.code {
            KeyCode::Esc | KeyCode::Char('G') | KeyCode::Char('g') => return true,
            KeyCode::Up => self.selected = self.selected.saturating_sub(1),
            KeyCode::Down => {
                self.selected = (self.selected + 1).min(Self::count().saturating_sub(1))
            }
            KeyCode::PageUp => self.selected = self.selected.saturating_sub(12),
            KeyCode::PageDown => {
                self.selected = (self.selected + 12).min(Self::count().saturating_sub(1));
            }
            KeyCode::Home => self.selected = 0,
            KeyCode::End => self.selected = Self::count().saturating_sub(1),
            _ => {}
        }
        if self.selected < self.offset {
            self.offset = self.selected;
        }
        false
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect, palette: &Palette, visible: usize) {
        let width = area.width.saturating_sub(6).clamp(50, 110);
        let height = area.height.saturating_sub(4).clamp(12, 34);
        let popup = Rect {
            x: area.x + (area.width.saturating_sub(width)) / 2,
            y: area.y + (area.height.saturating_sub(height)) / 2,
            width,
            height,
        };
        frame.render_widget(Clear, popup);
        let visible = usize::from(popup.height.saturating_sub(2)).clamp(1, visible.max(1));
        if self.selected < self.offset {
            self.offset = self.selected;
        }
        if self.selected >= self.offset + visible {
            self.offset = self.selected + 1 - visible;
        }
        let items: Vec<ListItem> = ASM_GLOSSARY
            .iter()
            .enumerate()
            .skip(self.offset)
            .take(visible)
            .map(|(index, entry)| {
                let marker = if index == self.selected { "▶ " } else { "  " };
                ListItem::new(vec![
                    Line::from(vec![
                        Span::styled(marker, palette.accent()),
                        Span::styled(format!("{:<10} ", entry.key), palette.muted()),
                        Span::styled(entry.title, palette.text()),
                    ]),
                    Line::from(Span::styled(
                        format!("      {}", entry.description),
                        palette.muted(),
                    )),
                ])
            })
            .collect();
        let detail = self.entry().map_or_else(String::new, |entry| {
            entry
                .detail
                .map_or_else(|| entry.description.to_owned(), str::to_owned)
        });
        let list = List::new(items)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(palette.border_focused())
                    .title(Span::styled(
                        format!("汇编术语 · 共 {} 条", Self::count()),
                        Style::default().add_modifier(Modifier::BOLD),
                    ))
                    .title_bottom(Span::styled(
                        format!(
                            " {} · ↑↓/PgUp/PgDn 浏览 · G/Esc 关闭 · {} ",
                            self.entry().map_or("", |entry| entry.kind),
                            detail
                        ),
                        palette.muted(),
                    )),
            )
            .highlight_style(palette.selection());
        let mut state = ListState::default();
        state.select(Some(self.selected.saturating_sub(self.offset)));
        frame.render_stateful_widget(list, popup, &mut state);
        let _ = Paragraph::new("");
    }
}

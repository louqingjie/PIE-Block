//! M6 钢琴卷帘：音符网格浏览与编辑（音高/起点/时长/增删）。

use std::time::{SystemTime, UNIX_EPOCH};

use crossterm::event::{KeyCode, KeyEvent};
use pieblock_core::model::{MusicConfig, MusicNote, ProjectConfig};
use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Paragraph};

use crate::theme::Palette;

/// 钢琴卷帘动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PianoAction {
    None,
    Changed,
    Commit,
}

/// 钢琴卷帘状态。
#[derive(Debug, Clone, Default)]
pub struct PianoRoll {
    pub notes: Vec<MusicNote>,
    pub selected: usize,
    pub ticks_per_quarter: i64,
    pub scroll_tick: i64,
    pub status: Option<String>,
}

fn new_note_id() -> String {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_micros().to_string())
        .unwrap_or_default()
}

impl PianoRoll {
    #[must_use]
    pub fn new(config: &MusicConfig) -> Self {
        Self {
            notes: config.notes.clone(),
            selected: 0,
            ticks_per_quarter: config.ticks_per_quarter.max(96),
            scroll_tick: 0,
            status: None,
        }
    }

    /// 编辑网格：四分音符的 1/4。
    #[must_use]
    pub fn grid_step(&self) -> i64 {
        (self.ticks_per_quarter / 4).max(1)
    }

    /// 每拍（四分音符）的 tick 数，用于网格横轴。
    fn beat_ticks(&self) -> i64 {
        self.ticks_per_quarter.max(1)
    }

    /// 把音符写回工程配置。
    pub fn commit(&self, config: &mut ProjectConfig) {
        if let ProjectConfig::Music(music) = config {
            music.notes = self.notes.clone();
        }
    }

    fn with_note(&mut self, id: &str, mutate: impl FnOnce(&mut MusicNote)) {
        if let Some(note) = self.notes.iter_mut().find(|note| note.id == id) {
            mutate(note);
        }
        self.notes.sort_by_key(|note| (note.start_tick, note.pitch));
        self.selected = self
            .notes
            .iter()
            .position(|note| note.id == id)
            .unwrap_or(0);
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> PianoAction {
        let step = self.grid_step();
        if self.notes.is_empty() {
            return match key.code {
                KeyCode::Char('a') | KeyCode::Char('A') => {
                    self.notes.push(MusicNote {
                        id: new_note_id(),
                        pitch: 60,
                        start_tick: 0,
                        duration_ticks: step,
                    });
                    self.status = Some("已添加音符".to_owned());
                    PianoAction::Changed
                }
                KeyCode::Esc => PianoAction::Commit,
                _ => PianoAction::None,
            };
        }
        self.selected = self.selected.min(self.notes.len() - 1);
        let id = self.notes[self.selected].id.clone();
        match key.code {
            KeyCode::Up => {
                self.selected = self.selected.saturating_sub(1);
                PianoAction::None
            }
            KeyCode::Down => {
                if self.selected + 1 < self.notes.len() {
                    self.selected += 1;
                }
                PianoAction::None
            }
            KeyCode::Left => {
                self.with_note(&id, |note| {
                    let next = (note.start_tick - step).max(0);
                    note.start_tick = next / step * step;
                });
                PianoAction::Changed
            }
            KeyCode::Right => {
                self.with_note(&id, |note| {
                    note.start_tick = (note.start_tick + step) / step * step;
                });
                PianoAction::Changed
            }
            KeyCode::Char('+') | KeyCode::Char('=') => {
                self.with_note(&id, |note| {
                    note.duration_ticks = ((note.duration_ticks + step) / step * step).max(step);
                });
                self.status = Some(format!("时长已增加（网格 {step} tick）"));
                PianoAction::Changed
            }
            KeyCode::Char('-') | KeyCode::Char('_') => {
                self.with_note(&id, |note| {
                    note.duration_ticks = ((note.duration_ticks - step) / step * step).max(step);
                });
                self.status = Some(format!("时长已减少（网格 {step} tick）"));
                PianoAction::Changed
            }
            KeyCode::Char('K') => {
                self.with_note(&id, |note| note.pitch = (note.pitch + 1).min(127));
                PianoAction::Changed
            }
            KeyCode::Char('J') => {
                self.with_note(&id, |note| note.pitch = (note.pitch - 1).max(0));
                PianoAction::Changed
            }
            KeyCode::Char('a') | KeyCode::Char('A') => {
                let start = self
                    .notes
                    .iter()
                    .map(|note| note.start_tick + note.duration_ticks)
                    .max()
                    .unwrap_or(0);
                self.notes.push(MusicNote {
                    id: new_note_id(),
                    pitch: 60,
                    start_tick: start / step * step,
                    duration_ticks: step,
                });
                self.selected = self.notes.len() - 1;
                self.status = Some("已在末尾添加音符".to_owned());
                PianoAction::Changed
            }
            KeyCode::Char('d') | KeyCode::Char('D') => {
                self.notes.retain(|note| note.id != id);
                if self.selected >= self.notes.len() {
                    self.selected = self.notes.len().saturating_sub(1);
                }
                self.status = Some("已删除音符".to_owned());
                PianoAction::Changed
            }
            KeyCode::Esc => PianoAction::Commit,
            _ => PianoAction::None,
        }
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect, palette: &Palette) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(6), Constraint::Length(1)])
            .split(area);
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(palette.border_focused())
            .title(Span::styled(
                "钢琴卷帘",
                Style::default().add_modifier(Modifier::BOLD),
            ))
            .title_bottom(Span::styled(
                format!(
                    " {} 个音符 · ↑↓ 选择 · ←→ 起点 · +/- 时长 · K/J 音高 · A 添加 · D 删除 · Esc 保存返回 ",
                    self.notes.len()
                ),
                palette.muted(),
            ));
        let inner = block.inner(chunks[0]);
        frame.render_widget(block, chunks[0]);
        if self.notes.is_empty() {
            frame.render_widget(
                Paragraph::new(Line::from(Span::styled(
                    "还没有音符：按 A 在 0 tick 添加一个 C4 十六分音符。",
                    palette.muted(),
                ))),
                inner,
            );
        } else {
            let rows = usize::from(inner.height).max(1);
            let width = usize::from(inner.width).saturating_sub(5).max(1);
            let min_pitch = self.notes.iter().map(|note| note.pitch).min().unwrap_or(60);
            let max_pitch = self.notes.iter().map(|note| note.pitch).max().unwrap_or(60);
            let low = (min_pitch - 1).max(0);
            let high = (max_pitch + 1).min(low + i64::try_from(rows).unwrap_or(20) - 1);
            let beat = self.beat_ticks().max(1);
            let start = self.scroll_tick / beat * beat;
            let lines: Vec<Line> = (low..=high)
                .rev()
                .map(|pitch| {
                    let mut row = vec![' '; width];
                    for (index, note) in self.notes.iter().enumerate() {
                        if note.pitch != pitch {
                            continue;
                        }
                        let begin =
                            usize::try_from((note.start_tick - start).max(0) / beat).unwrap_or(0);
                        let length =
                            usize::try_from((note.duration_ticks / beat).max(1)).unwrap_or(1);
                        let end = (begin + length).min(width);
                        if begin < end {
                            row[begin..end].fill(if index == self.selected {
                                '█'
                            } else {
                                '▓'
                            });
                        }
                    }
                    Line::from(vec![
                        Span::styled(format!("{pitch:>3} "), palette.muted()),
                        Span::styled(row.into_iter().collect::<String>(), palette.accent()),
                    ])
                })
                .collect();
            frame.render_widget(Paragraph::new(lines), inner);
        }
        let selected_text = self.notes.get(self.selected).map_or_else(
            || "无选中音符".to_owned(),
            |note| {
                format!(
                    "选中：pitch {} · start {} tick · 时长 {} tick",
                    note.pitch, note.start_tick, note.duration_ticks
                )
            },
        );
        let message = self.status.clone().map_or(selected_text.clone(), |status| {
            format!("{selected_text} · {status}")
        });
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(message, palette.muted()))),
            chunks[1],
        );
    }
}

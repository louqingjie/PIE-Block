//! M6 播放预览：按 `MusicTimeline` 发声音符推进播放头并高亮当前音符。

use std::time::Instant;

use crossterm::event::{KeyCode, KeyEvent};
use pieblock_core::MusicTimeline;
use pieblock_core::model::MusicConfig;
use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Gauge, Paragraph};

use crate::theme::Palette;

/// 播放动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PlaybackAction {
    None,
    Changed,
    Close,
}

/// 播放预览状态。
#[derive(Debug, Clone)]
pub struct Playback {
    pub spans: Vec<pieblock_core::MusicSoundingSpan>,
    pub duration_tick: i64,
    pub position_tick: f64,
    pub ticks_per_second: f64,
    pub playing: bool,
    pub started: Option<Instant>,
    pub speed: f64,
}

impl Playback {
    #[must_use]
    pub fn new(config: &MusicConfig) -> Self {
        let spans = MusicTimeline::sounding_spans(config);
        let duration_tick = spans.iter().map(|span| span.end_tick).max().unwrap_or(0);
        let bpm = config.tempo_events.first().map_or(120.0, |event| {
            60_000_000.0
                / f64::from(i32::try_from(event.microseconds_per_quarter).unwrap_or(500_000))
        });
        Self {
            spans,
            duration_tick,
            position_tick: 0.0,
            ticks_per_second: config.ticks_per_quarter.max(1) as f64 * bpm / 60.0,
            playing: false,
            started: None,
            speed: 1.0,
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> PlaybackAction {
        match key.code {
            KeyCode::Char(' ') => {
                self.playing = !self.playing;
                self.started = if self.playing {
                    Some(Instant::now())
                } else {
                    None
                };
                PlaybackAction::Changed
            }
            KeyCode::Left => {
                self.seek(-self.ticks_per_second().max(1.0));
                PlaybackAction::Changed
            }
            KeyCode::Right => {
                self.seek(self.ticks_per_second().max(1.0));
                PlaybackAction::Changed
            }
            KeyCode::Home => {
                self.position_tick = 0.0;
                self.started = self.playing.then(Instant::now);
                PlaybackAction::Changed
            }
            KeyCode::End => {
                self.position_tick = self.duration_tick as f64;
                self.playing = false;
                self.started = None;
                PlaybackAction::Changed
            }
            KeyCode::Char('+') | KeyCode::Char('=') => {
                self.speed = (self.speed * 2.0).min(4.0);
                PlaybackAction::Changed
            }
            KeyCode::Char('-') => {
                self.speed = (self.speed / 2.0).max(0.25);
                PlaybackAction::Changed
            }
            KeyCode::Esc | KeyCode::Char('q') => PlaybackAction::Close,
            _ => PlaybackAction::None,
        }
    }

    fn ticks_per_second(&self) -> f64 {
        self.ticks_per_second.max(1.0)
    }

    fn seek(&mut self, delta: f64) {
        self.position_tick = (self.position_tick + delta).clamp(0.0, self.duration_tick as f64);
        self.started = self.playing.then(Instant::now);
    }

    /// 推进播放头（由主循环每帧调用）。
    pub fn tick(&mut self, now: Instant) {
        if !self.playing {
            return;
        }
        let Some(started) = self.started else {
            self.started = Some(now);
            return;
        };
        let elapsed = now.saturating_duration_since(started).as_secs_f64();
        self.position_tick += elapsed * self.ticks_per_second() * self.speed;
        self.started = Some(now);
        if self.position_tick >= self.duration_tick as f64 {
            self.position_tick = self.duration_tick as f64;
            self.playing = false;
            self.started = None;
        }
    }

    #[must_use]
    pub fn active_pitch(&self) -> Option<i64> {
        self.spans
            .iter()
            .find(|span| {
                self.position_tick >= span.start_tick as f64
                    && self.position_tick < span.end_tick as f64
            })
            .map(|span| span.pitch)
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect, palette: &Palette) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(4),
                Constraint::Length(2),
            ])
            .split(area);
        let ratio = if self.duration_tick > 0 {
            (self.position_tick / self.duration_tick as f64).clamp(0.0, 1.0)
        } else {
            0.0
        };
        let active = self.active_pitch();
        frame.render_widget(
            Gauge::default()
                .block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_style(palette.border_focused())
                        .title(Span::styled(
                            format!("播放预览{}", if self.playing { " ▶" } else { " ⏸" }),
                            Style::default().add_modifier(Modifier::BOLD),
                        )),
                )
                .gauge_style(palette.accent())
                .ratio(ratio),
            chunks[0],
        );
        let rows = usize::from(chunks[1].height).max(1);
        let low = self.spans.iter().map(|span| span.pitch).min().unwrap_or(60) - 1;
        let high = self.spans.iter().map(|span| span.pitch).max().unwrap_or(60) + 1;
        let visible = high - low + 1;
        let low = if visible > i64::try_from(rows).unwrap_or(20) {
            active.map_or(low, |pitch| pitch - i64::try_from(rows / 2).unwrap_or(10))
        } else {
            low
        };
        let window = i64::try_from(rows).unwrap_or(20);
        let mut lines = Vec::new();
        for row in 0..window {
            let pitch = low + window - 1 - row;
            let marker = if active == Some(pitch) { "▶" } else { " " };
            let label = format!("{marker}{pitch:>4} ");
            let mut spans = vec![Span::styled(
                label,
                if active == Some(pitch) {
                    palette.info()
                } else {
                    palette.muted()
                },
            )];
            let cell = if self.spans.iter().any(|span| {
                span.pitch == pitch
                    && self.position_tick >= span.start_tick as f64
                    && self.position_tick < span.end_tick as f64
            }) {
                "▮▮▮▮"
            } else {
                "    "
            };
            spans.push(Span::styled(cell, palette.accent()));
            lines.push(Line::from(spans));
        }
        frame.render_widget(Paragraph::new(lines), chunks[1]);
        let total = self.duration_tick as f64 / self.ticks_per_second();
        let current = self.position_tick / self.ticks_per_second();
        let status = format!(
            " {:>5.2}s / {total:>5.2}s · {:.0}% · {:.2}x · 空格 播放/暂停 · ←→ 快退/快进 · +/- 倍速 · Esc 返回 ",
            current,
            ratio * 100.0,
            self.speed
        );
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(status, palette.muted()))),
            chunks[2],
        );
    }
}

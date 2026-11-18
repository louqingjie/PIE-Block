//! M7 烧录页：设备探测、HEX 选择与烧录进度/日志。

use std::path::PathBuf;

use crossterm::event::{KeyCode, KeyEvent};
use pieblock_hid::{FlashEvent, FlashOptions, FlashResult};
use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Gauge, Paragraph};

use crate::theme::Palette;

/// 烧录页动作。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FlashAction {
    None,
    Close,
    Cancel,
    Start { hex_path: PathBuf, sha256: String },
}

/// 烧录页状态。
#[derive(Debug, Clone, Default)]
pub struct FlashState {
    pub device_count: i64,
    pub log: Vec<String>,
    pub progress: Option<(i64, i64, String)>,
    pub running: bool,
    pub result: Option<String>,
    pub hex_path: Option<PathBuf>,
    pub expected_sha256: Option<String>,
}

impl FlashState {
    /// 探测设备数量（无 hidapi 时按 0 处理）。
    #[must_use]
    pub fn with_probe(hex_path: Option<PathBuf>, expected_sha256: Option<String>) -> Self {
        #[cfg(any(windows, target_os = "linux"))]
        let device_count = pieblock_hid::NativeHidTransport::new()
            .map(|mut transport| pieblock_hid::HidFlasher::detect_device_count(&mut transport))
            .unwrap_or(0);
        #[cfg(not(any(windows, target_os = "linux")))]
        let device_count = 0;
        let mut state = Self {
            device_count,
            hex_path,
            expected_sha256,
            ..Self::default()
        };
        #[cfg(target_os = "linux")]
        {
            let installed = pieblock_hid::is_installed(pieblock_hid::udev::UDEV_RULE_TARGET_PATH);
            state.push_log(if installed {
                "udev 规则：已安装（可直接访问 USB 设备）".to_owned()
            } else {
                format!(
                    "udev 规则：未安装；否则需要在终端执行 sudo 安装到 {} 后重新插拔设备",
                    pieblock_hid::udev::UDEV_RULE_TARGET_PATH
                )
            });
        }
        #[cfg(not(target_os = "linux"))]
        state.push_log(
            "设备访问：Windows 无需 udev 规则；首次烧录如失败请以管理员身份运行".to_owned(),
        );
        state.push_log(if device_count > 0 {
            format!("已检测到 {device_count} 个 STC32G ISP 设备。")
        } else {
            "未检测到 STC32G ISP 设备：请连接主控板并进入 USB 下载模式。".to_owned()
        });
        state
    }

    pub fn push_log(&mut self, message: String) {
        self.log.push(message);
    }

    pub fn push_event(&mut self, event: FlashEvent) {
        self.push_log(format!(
            "[{}] {}{}",
            event.stage.as_str(),
            event.message,
            event
                .current
                .zip(event.total)
                .map_or_else(String::new, |(current, total)| {
                    format!("（{current}/{total}）")
                })
        ));
        if let Some((current, total)) = event.current.zip(event.total) {
            self.progress = Some((current, total, event.stage.as_str().to_owned()));
        }
    }

    pub fn finish(&mut self, result: FlashResult) {
        self.running = false;
        self.progress = None;
        self.result = Some(if result.success {
            "烧录成功，设备将自动复位。".to_owned()
        } else if result.canceled {
            "烧录已取消。".to_owned()
        } else {
            format!("烧录失败（{}）：{}", result.stage.as_str(), result.message)
        });
        if let Some(result) = self.result.clone() {
            self.push_log(result);
        }
    }

    pub fn handle_key(&mut self, key: KeyEvent) -> FlashAction {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') => FlashAction::Close,
            KeyCode::Char('c') => {
                if self.running {
                    FlashAction::Cancel
                } else {
                    FlashAction::None
                }
            }
            KeyCode::Char('r') => {
                #[cfg(any(windows, target_os = "linux"))]
                let count = pieblock_hid::NativeHidTransport::new()
                    .map(|mut transport| {
                        pieblock_hid::HidFlasher::detect_device_count(&mut transport)
                    })
                    .unwrap_or(0);
                #[cfg(not(any(windows, target_os = "linux")))]
                let count = 0;
                self.device_count = count;
                self.push_log(if count > 0 {
                    format!("重新探测：发现 {count} 个设备。")
                } else {
                    "重新探测：仍未发现设备。".to_owned()
                });
                FlashAction::None
            }
            KeyCode::Enter => {
                if self.running {
                    return FlashAction::None;
                }
                match (&self.hex_path, &self.expected_sha256) {
                    (Some(path), Some(sha256)) => FlashAction::Start {
                        hex_path: path.clone(),
                        sha256: sha256.clone(),
                    },
                    (Some(_), None) => {
                        self.push_log("缺少 HEX 校验指纹，请先构建一次。".to_owned());
                        FlashAction::None
                    }
                    _ => {
                        self.push_log(
                            "未找到 HEX：请先按 B 构建，或把 main.hex 放在工程目录。".to_owned(),
                        );
                        FlashAction::None
                    }
                }
            }
            _ => FlashAction::None,
        }
    }

    /// 烧录前的静态校验（HEX 是否存在）。
    pub fn options() -> FlashOptions {
        FlashOptions::default()
    }

    pub fn render(&mut self, frame: &mut Frame, area: Rect, palette: &Palette) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(4),
                Constraint::Length(3),
                Constraint::Min(4),
                Constraint::Length(1),
            ])
            .split(area);
        let state_text = if self.running {
            "烧录中…（C 取消）"
        } else if self.result.is_some() {
            "已完成"
        } else {
            "待开始（Enter 开始）"
        };
        let info = Paragraph::new(vec![
            Line::from(vec![
                Span::styled("设备：", palette.muted()),
                Span::styled(
                    if self.device_count > 0 {
                        format!("{} 个 STC32G ISP", self.device_count)
                    } else {
                        "未连接".to_owned()
                    },
                    if self.device_count > 0 {
                        palette.ok()
                    } else {
                        palette.warn()
                    },
                ),
                Span::styled("    状态：", palette.muted()),
                Span::styled(state_text.trim().to_owned(), palette.text()),
            ]),
            Line::from(vec![
                Span::styled("HEX：", palette.muted()),
                Span::styled(
                    self.hex_path.as_ref().map_or_else(
                        || "（未找到）".to_owned(),
                        |path| path.display().to_string(),
                    ),
                    palette.text(),
                ),
            ]),
        ])
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(palette.border_focused())
                .title(Span::styled(
                    "烧录主控板",
                    Style::default().add_modifier(Modifier::BOLD),
                )),
        );
        frame.render_widget(info, chunks[0]);
        let ratio = self.progress.as_ref().map_or(0.0, |(current, total, _)| {
            if *total > 0 {
                (*current as f64 / *total as f64).clamp(0.0, 1.0)
            } else {
                0.0
            }
        });
        let stage = self
            .progress
            .as_ref()
            .map_or_else(|| "等待开始".to_owned(), |(_, _, stage)| stage.clone());
        frame.render_widget(
            Gauge::default()
                .block(Block::default().borders(Borders::ALL).title(Span::styled(
                    "进度",
                    Style::default().add_modifier(Modifier::BOLD),
                )))
                .gauge_style(palette.accent())
                .ratio(ratio)
                .label(format!("{stage} {:.0}%", ratio * 100.0)),
            chunks[1],
        );
        let log_lines: Vec<Line> = self
            .log
            .iter()
            .rev()
            .take(usize::from(chunks[2].height).saturating_sub(2))
            .rev()
            .map(|line| Line::from(Span::styled(line.clone(), palette.text())))
            .collect();
        frame.render_widget(
            Paragraph::new(log_lines).block(
                Block::default()
                    .borders(Borders::ALL)
                    .title(Span::styled("日志", palette.muted())),
            ),
            chunks[2],
        );
        let hint = format!(
            " Enter 开始 · R 重新探测 · C 取消 · Esc 返回 · 设备 {}",
            if self.device_count > 0 {
                "已连接"
            } else {
                "未连接"
            }
        );
        frame.render_widget(
            Paragraph::new(Line::from(Span::styled(hint, palette.muted()))),
            chunks[3],
        );
    }
}

impl FlashAction {
    #[must_use]
    pub fn is_start(&self) -> bool {
        matches!(self, Self::Start { .. })
    }
}

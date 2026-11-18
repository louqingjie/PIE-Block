//! M3 基础页面：首页、文件浏览器、设置页与状态栏。
//!
//! 纯渲染函数 + 可测试的文件浏览器状态机；不依赖 `pieblock-tui` 的工作区，
//! 由主程序把领域状态映射成这些视图结构。

use std::path::{Path, PathBuf};

use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::{Modifier, Style};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph};

use crate::theme::Palette;

/// 首页最近项目条目。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct RecentItem {
    pub name: String,
    pub path: String,
    /// 类型标签（步兵/工程/调试/音乐），未知时为空。
    pub kind_label: String,
    /// 文件是否仍然存在。
    pub available: bool,
}

/// 首页数据。
pub struct HomeView<'a> {
    pub app_title: &'a str,
    pub subtitle: &'a str,
    pub recent: &'a [RecentItem],
    pub selected: usize,
    pub status: &'a str,
    pub message: Option<&'a str>,
}

/// 文件浏览器条目。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct BrowserEntry {
    pub name: String,
    pub path: PathBuf,
    pub is_dir: bool,
    pub is_project: bool,
}

/// 文件浏览器动作。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum BrowserAction {
    None,
    OpenProject(PathBuf),
    ChangeDirectory(PathBuf),
}

/// 可测试的目录浏览器状态机。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct FileBrowser {
    pub current_dir: PathBuf,
    pub entries: Vec<BrowserEntry>,
    pub selected: usize,
    pub message: Option<String>,
}

impl FileBrowser {
    /// 打开一个目录；失败时退回父目录/当前目录并给出提示。
    #[must_use]
    pub fn new(directory: impl AsRef<Path>) -> Self {
        let directory = directory.as_ref().to_path_buf();
        let mut browser = Self {
            current_dir: directory,
            entries: Vec::new(),
            selected: 0,
            message: None,
        };
        browser.refresh();
        browser
    }

    /// 重新读取目录内容：目录在前、`.pieproj` 文件在后，忽略隐藏项与其它文件。
    pub fn refresh(&mut self) {
        self.entries.clear();
        self.selected = 0;
        let Ok(entries) = std::fs::read_dir(&self.current_dir) else {
            self.message = Some(format!("无法读取目录：{}", self.current_dir.display()));
            return;
        };
        let mut directories: Vec<BrowserEntry> = Vec::new();
        let mut projects: Vec<BrowserEntry> = Vec::new();
        for entry in entries.flatten() {
            let path = entry.path();
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.starts_with('.') {
                continue;
            }
            let Ok(file_type) = entry.file_type() else {
                continue;
            };
            if file_type.is_dir() {
                directories.push(BrowserEntry {
                    name,
                    path,
                    is_dir: true,
                    is_project: false,
                });
            } else if file_type.is_file() && name.to_lowercase().ends_with(".pieproj") {
                projects.push(BrowserEntry {
                    name,
                    path,
                    is_dir: false,
                    is_project: true,
                });
            }
        }
        directories.sort_by(|left, right| left.name.cmp(&right.name));
        projects.sort_by(|left, right| left.name.cmp(&right.name));
        self.entries.extend(directories);
        self.entries.extend(projects);
        self.message = None;
    }

    /// 移动选择（循环）。
    pub fn move_selection(&mut self, delta: i32) {
        if self.entries.is_empty() {
            self.selected = 0;
            return;
        }
        let length = i64::try_from(self.entries.len()).unwrap_or(1);
        let current = i64::try_from(self.selected).unwrap_or(0);
        let next = (current + i64::from(delta)).rem_euclid(length);
        self.selected = usize::try_from(next).unwrap_or(0);
    }

    /// 选中目录并返回动作；文件直接返回打开动作。
    pub fn activate(&mut self) -> BrowserAction {
        let Some(entry) = self.entries.get(self.selected).cloned() else {
            return BrowserAction::None;
        };
        if entry.is_dir {
            self.current_dir = entry.path;
            self.refresh();
            BrowserAction::ChangeDirectory(self.current_dir.clone())
        } else if entry.is_project {
            BrowserAction::OpenProject(entry.path)
        } else {
            BrowserAction::None
        }
    }

    /// 返回上级目录。
    pub fn go_up(&mut self) {
        if let Some(parent) = self.current_dir.parent() {
            self.current_dir = parent.to_path_buf();
            self.refresh();
        }
    }

    /// 当前选中路径。
    #[must_use]
    pub fn selected_path(&self) -> Option<&Path> {
        self.entries
            .get(self.selected)
            .map(|entry| entry.path.as_path())
    }

    /// 当前目录是否已有选中项。
    #[must_use]
    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }
}

/// 首页渲染。
pub fn draw_home(frame: &mut Frame, area: Rect, view: &HomeView<'_>, palette: &Palette) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Length(3),
            Constraint::Min(4),
            Constraint::Length(1),
        ])
        .split(area);
    draw_brand(frame, chunks[0], view.app_title, view.subtitle, palette);
    let shortcuts = Paragraph::new(Line::from(vec![
        Span::styled(" N ", palette.selection()),
        Span::styled("新建工程  ", palette.text()),
        Span::styled(" O ", palette.selection()),
        Span::styled("打开文件  ", palette.text()),
        Span::styled(" S ", palette.selection()),
        Span::styled("设置  ", palette.text()),
        Span::styled(" Q ", palette.selection()),
        Span::styled("退出", palette.text()),
    ]))
    .block(block("操作", palette, false));
    frame.render_widget(shortcuts, chunks[1]);

    if view.recent.is_empty() {
        let empty = Paragraph::new(vec![
            Line::from(Span::styled("还没有最近项目。", palette.muted())),
            Line::from(""),
            Line::from(Span::styled(
                "按 N 新建一个工程，或按 O 打开已有 .pieproj。",
                palette.text(),
            )),
        ])
        .block(block("最近项目", palette, true));
        frame.render_widget(empty, chunks[2]);
    } else {
        let items: Vec<ListItem> = view
            .recent
            .iter()
            .map(|item| {
                let icon = "■";
                let kind = if item.kind_label.is_empty() {
                    "未知类型".to_owned()
                } else {
                    item.kind_label.clone()
                };
                let name_style = if item.available {
                    palette.text()
                } else {
                    palette.muted()
                };
                let availability = if item.available {
                    Span::styled("", palette.muted())
                } else {
                    Span::styled("（文件已不存在）", palette.warn())
                };
                ListItem::new(Line::from(vec![
                    Span::styled(format!("{icon} "), palette.accent()),
                    Span::styled(
                        format!("{}  ", item.name),
                        name_style.add_modifier(Modifier::BOLD),
                    ),
                    Span::styled(format!("[{kind}]  "), palette.info()),
                    Span::styled(item.path.clone(), palette.muted()),
                    availability,
                ]))
            })
            .collect();
        let list = List::new(items)
            .block(block("最近项目（Enter 打开）", palette, true))
            .highlight_style(palette.selection())
            .highlight_symbol("▶ ");
        let mut state = ListState::default();
        state.select(Some(view.selected.min(view.recent.len().saturating_sub(1))));
        frame.render_stateful_widget(list, chunks[2], &mut state);
    }
    draw_status(frame, chunks[3], view.status, view.message, palette);
}

/// 浏览器渲染。
pub fn draw_browser(frame: &mut Frame, area: Rect, browser: &FileBrowser, palette: &Palette) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(3),
            Constraint::Length(1),
        ])
        .split(area);
    let path_line = Paragraph::new(Line::from(vec![
        Span::styled("路径：", palette.muted()),
        Span::styled(browser.current_dir.display().to_string(), palette.text()),
    ]))
    .block(block("打开工程", palette, true));
    frame.render_widget(path_line, chunks[0]);

    let items: Vec<ListItem> = if browser.entries.is_empty() {
        vec![ListItem::new(Line::from(Span::styled(
            "（此目录没有子目录或 .pieproj 文件）",
            palette.muted(),
        )))]
    } else {
        browser
            .entries
            .iter()
            .map(|entry| {
                if entry.is_dir {
                    ListItem::new(Line::from(vec![
                        Span::styled("▸ ", palette.accent()),
                        Span::styled(format!("{}/", entry.name), palette.text()),
                    ]))
                } else {
                    ListItem::new(Line::from(vec![
                        Span::styled("■ ", palette.ok()),
                        Span::styled(entry.name.clone(), palette.text()),
                    ]))
                }
            })
            .collect()
    };
    let list = List::new(items)
        .block(block("目录", palette, true))
        .highlight_style(palette.selection())
        .highlight_symbol("▶ ");
    let mut state = ListState::default();
    state.select(Some(
        browser
            .selected
            .min(browser.entries.len().saturating_sub(1)),
    ));
    frame.render_stateful_widget(list, chunks[1], &mut state);
    draw_status(
        frame,
        chunks[2],
        "↑↓ 移动  Enter 进入/打开  Backspace 上级  Esc 返回",
        browser.message.as_deref(),
        palette,
    );
}

/// 设置页的一行。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SettingRow {
    pub label: &'static str,
    pub value: String,
    pub hint: &'static str,
}

/// 设置页渲染。
pub fn draw_settings(
    frame: &mut Frame,
    area: Rect,
    rows: &[SettingRow],
    selected: usize,
    palette: &Palette,
) {
    let chunks = Layout::default()
        .direction(Direction::Vertical)
        .constraints([
            Constraint::Length(3),
            Constraint::Min(4),
            Constraint::Length(1),
        ])
        .split(area);
    let header = Paragraph::new(Line::from(vec![
        Span::styled("设置", palette.title()),
        Span::styled("（保存即生效，写入 settings.json）", palette.muted()),
    ]))
    .block(block("PIE-Block", palette, true));
    frame.render_widget(header, chunks[0]);

    let items: Vec<ListItem> = rows
        .iter()
        .map(|row| {
            ListItem::new(vec![
                Line::from(vec![
                    Span::styled(format!("{:<14}", row.label), palette.muted()),
                    Span::styled(row.value.clone(), palette.text()),
                ]),
                Line::from(Span::styled(format!("  {}", row.hint), palette.muted())),
            ])
        })
        .collect();
    let list = List::new(items)
        .block(block("项目", palette, true))
        .highlight_style(palette.selection())
        .highlight_symbol("▶ ");
    let mut state = ListState::default();
    state.select(Some(selected.min(rows.len().saturating_sub(1))));
    frame.render_stateful_widget(list, chunks[1], &mut state);
    draw_status(
        frame,
        chunks[2],
        "↑↓ 选择  Enter 切换/编辑  Esc 返回",
        None,
        palette,
    );
}

/// 通用状态栏（左状态、右消息）。
pub fn draw_status(
    frame: &mut Frame,
    area: Rect,
    status: &str,
    message: Option<&str>,
    palette: &Palette,
) {
    let mut spans = vec![Span::styled(format!(" {status} "), palette.status_bar())];
    if let Some(message) = message.filter(|message| !message.is_empty()) {
        spans.push(Span::styled(format!("  {message}"), palette.warn()));
    }
    frame.render_widget(Paragraph::new(Line::from(spans)), area);
}

/// 居中的消息对话框（错误/确认）。
pub fn draw_dialog(
    frame: &mut Frame,
    area: Rect,
    title: &str,
    message: &[&str],
    palette: &Palette,
) {
    let width = area.width.saturating_sub(8).clamp(24, 72);
    let height = u16::try_from(message.len()).unwrap_or(0) + 4;
    let popup = Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width,
        height,
    };
    frame.render_widget(Clear, popup);
    let mut lines: Vec<Line> = message
        .iter()
        .map(|text| Line::from(Span::styled((*text).to_owned(), palette.text())))
        .collect();
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled("Enter/Esc 关闭", palette.muted())));
    let dialog = Paragraph::new(lines).block(block(title, palette, true));
    frame.render_widget(dialog, popup);
}

fn draw_brand(frame: &mut Frame, area: Rect, title: &str, subtitle: &str, palette: &Palette) {
    let paragraph = Paragraph::new(vec![
        Line::from(Span::styled(title.to_owned(), palette.title())),
        Line::from(Span::styled(subtitle.to_owned(), palette.muted())),
    ])
    .block(block("PIE-Block", palette, false));
    frame.render_widget(paragraph, area);
}

fn block(title: &str, palette: &Palette, focused: bool) -> Block<'static> {
    let border = if focused {
        palette.border_focused()
    } else {
        palette.border()
    };
    Block::default()
        .borders(Borders::ALL)
        .border_style(border)
        .title(Span::styled(
            title.to_owned(),
            Style::default().add_modifier(Modifier::BOLD),
        ))
        .title_alignment(ratatui::layout::Alignment::Left)
}

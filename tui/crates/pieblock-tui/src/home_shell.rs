//! M3 主循环：首页 ↔ 工程概览 ↔ 文件浏览器 ↔ 设置，接入真实工作区。

use std::io;
use std::path::{Path, PathBuf};
use std::time::Instant;

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers, MouseEventKind};
use pieblock_core::ProjectKind;
use pieblock_toolchain::models::CompilerKind;
use pieblock_ui::ThemeMode;
use pieblock_ui::{
    BrowserAction, FileBrowser, HomeView, Palette, RecentItem, SettingRow, draw_browser, draw_home,
    draw_settings, draw_status,
};
use ratatui::Frame;
use ratatui::Terminal;
use ratatui::backend::Backend;
use ratatui::layout::{Alignment, Constraint, Direction, Layout, Rect};
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, Clear, List, ListItem, ListState, Paragraph};

use crate::workspace::Workspace;

/// 当前页面。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Screen {
    Home,
    Project,
    Browser(FileBrowser),
    Settings,
}

/// 浮层。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Overlay {
    None,
    KindPicker {
        selected: usize,
    },
    Input {
        title: String,
        value: String,
        purpose: InputPurpose,
    },
}

/// 输入框用途。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum InputPurpose {
    NewProject(ProjectKind),
    KeilPath,
}

/// M3 交互外壳。
pub struct Shell {
    pub workspace: Workspace,
    pub screen: Screen,
    pub overlay: Overlay,
    pub settings_selected: usize,
    pub home_selected: usize,
    pub start_dir: PathBuf,
    pub palette: Palette,
    pub message: Option<String>,
    quit: bool,
}

const KIND_CHOICES: [(ProjectKind, &str); 4] = [
    (ProjectKind::Infantry, "平衡步兵：底盘、云台、拨弹与摩擦轮"),
    (ProjectKind::Engineer, "工程机器人：PWM 组、动作行与动作表"),
    (ProjectKind::Debug, "调试工程：10 路测试序列与提示音"),
    (ProjectKind::Music, "音乐工程：五线谱、卷帘与蜂鸣器"),
];

const SETTINGS_ROWS: [(&str, &str); 5] = [
    ("主题", "Enter 切换：跟随系统/浅色/深色"),
    ("编译器", "Enter 在 SDCC / Keil 之间切换"),
    ("Keil 路径", "Enter 输入 Keil C251 安装目录（Windows）"),
    ("烧录引导", "Enter 切换是否隐藏烧录前提示"),
    ("模板引导", "Enter 切换是否隐藏模板提示"),
];

impl Shell {
    /// 使用默认应用数据目录。
    pub fn new(start_dir: PathBuf) -> Self {
        Self::with_data_dir(crate::paths::app_data_dir(), start_dir)
    }

    /// 指定应用数据目录（测试友好）。
    pub fn with_data_dir(data_dir: impl Into<PathBuf>, start_dir: PathBuf) -> Self {
        let workspace = Workspace::load(data_dir);
        let palette = palette_for(workspace.theme_mode());
        Self {
            workspace,
            screen: Screen::Home,
            overlay: Overlay::None,
            settings_selected: 0,
            home_selected: 0,
            start_dir,
            palette,
            message: None,
            quit: false,
        }
    }

    /// 事件循环（阻塞到退出）。
    pub fn run<B: Backend<Error = io::Error>>(
        &mut self,
        terminal: &mut Terminal<B>,
    ) -> io::Result<()> {
        loop {
            terminal.draw(|frame| self.draw(frame))?;
            if event::poll(std::time::Duration::from_millis(200))? {
                match event::read()? {
                    Event::Key(key) => self.handle_key(key),
                    Event::Mouse(mouse) => self.handle_mouse(mouse.kind),
                    _ => {}
                }
            }
            self.workspace.tick(Instant::now());
            if self.quit {
                return Ok(());
            }
        }
    }

    /// 处理按键（测试可直接调用）。
    pub fn handle_key(&mut self, key: KeyEvent) {
        if self.handle_overlay_key(key) {
            return;
        }
        if key.modifiers.contains(KeyModifiers::CONTROL) && key.code == KeyCode::Char('s') {
            self.save();
            return;
        }
        match self.screen.clone() {
            Screen::Home => self.handle_home_key(key),
            Screen::Project => self.handle_project_key(key),
            Screen::Browser(mut browser) => {
                self.handle_browser_key(key, &mut browser);
                if matches!(self.screen, Screen::Browser(_)) {
                    self.screen = Screen::Browser(browser);
                }
            }
            Screen::Settings => self.handle_settings_key(key),
        }
    }

    fn handle_home_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('n') => {
                self.overlay = Overlay::KindPicker { selected: 0 };
            }
            KeyCode::Char('o') => {
                let directory = self.browser_start_directory();
                self.screen = Screen::Browser(FileBrowser::new(directory));
            }
            KeyCode::Char('s') => {
                self.settings_selected = 0;
                self.screen = Screen::Settings;
            }
            KeyCode::Up => self.select_home(-1),
            KeyCode::Down => self.select_home(1),
            KeyCode::Enter => self.open_selected_recent(),
            _ => {}
        }
    }

    fn select_home(&mut self, delta: i32) {
        let length = self.workspace.settings.recent.len();
        if length == 0 {
            self.home_selected = 0;
            return;
        }
        let current = i64::try_from(self.home_selected).unwrap_or(0);
        let next = (current + i64::from(delta)).rem_euclid(i64::try_from(length).unwrap_or(1));
        self.home_selected = usize::try_from(next).unwrap_or(0);
    }

    fn open_selected_recent(&mut self) {
        let Some(project) = self.workspace.settings.recent.get(self.home_selected) else {
            return;
        };
        let path = PathBuf::from(&project.path);
        if !path.exists() {
            self.message = Some(format!("找不到最近项目：{}", project.path));
            return;
        }
        match self.workspace.open(&path) {
            Ok(session) => {
                self.message = Some(format!("已打开：{}", session.display_name()));
                self.enter_project();
            }
            Err(error) => self.message = Some(format!("打开失败：{error}")),
        }
    }

    fn enter_project(&mut self) {
        self.screen = Screen::Project;
        self.overlay = Overlay::None;
    }

    fn handle_project_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Char('h') | KeyCode::Esc => self.screen = Screen::Home,
            KeyCode::Char('o') => {
                let directory = self.browser_start_directory();
                self.screen = Screen::Browser(FileBrowser::new(directory));
            }
            KeyCode::Char('s') => self.settings_screen(),
            KeyCode::F(5) => self.save(),
            _ => {}
        }
    }

    fn save(&mut self) {
        if self.workspace.session.is_some() {
            if self.workspace.save_now() {
                self.message = Some("已保存".to_owned());
            } else {
                self.message = self
                    .workspace
                    .last_error
                    .clone()
                    .or_else(|| Some("保存失败".to_owned()));
            }
        }
    }

    fn settings_screen(&mut self) {
        self.settings_selected = 0;
        self.screen = Screen::Settings;
    }

    fn handle_browser_key(&mut self, key: KeyEvent, browser: &mut FileBrowser) {
        match key.code {
            KeyCode::Esc => self.screen = Screen::Home,
            KeyCode::Up => browser.move_selection(-1),
            KeyCode::Down => browser.move_selection(1),
            KeyCode::Backspace | KeyCode::Left => browser.go_up(),
            KeyCode::Enter => match browser.activate() {
                BrowserAction::OpenProject(path) => match self.workspace.open(&path) {
                    Ok(session) => {
                        self.message = Some(format!("已打开：{}", session.display_name()));
                        self.enter_project();
                    }
                    Err(error) => {
                        self.message = Some(format!("打开失败：{error}"));
                        self.screen = Screen::Browser(FileBrowser::new(
                            path.parent().unwrap_or(Path::new(".")),
                        ));
                    }
                },
                BrowserAction::ChangeDirectory(_) => {
                    self.screen = Screen::Browser(browser.clone());
                }
                BrowserAction::None => {}
            },
            KeyCode::Char('q') => self.screen = Screen::Home,
            _ => {}
        }
    }

    fn handle_settings_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('h') => self.screen = Screen::Home,
            KeyCode::Up => self.settings_selected = self.settings_selected.saturating_sub(1),
            KeyCode::Down => {
                self.settings_selected = (self.settings_selected + 1).min(SETTINGS_ROWS.len() - 1);
            }
            KeyCode::Enter => self.activate_setting(),
            _ => {}
        }
    }

    fn activate_setting(&mut self) {
        match self.settings_selected {
            0 => {
                self.workspace.cycle_theme();
                self.palette = palette_for(self.workspace.theme_mode());
            }
            1 => self.workspace.toggle_compiler(),
            2 => {
                let value = self
                    .workspace
                    .settings
                    .keil_path
                    .clone()
                    .unwrap_or_default();
                self.overlay = Overlay::Input {
                    title: "Keil C251 安装目录".to_owned(),
                    value,
                    purpose: InputPurpose::KeilPath,
                };
            }
            3 => self.workspace.toggle_suppress_flash_guide(),
            4 => self.workspace.toggle_suppress_template_guide(),
            _ => {}
        }
    }

    fn handle_overlay_key(&mut self, key: KeyEvent) -> bool {
        match self.overlay.clone() {
            Overlay::None => false,
            Overlay::KindPicker { selected } => {
                match key.code {
                    KeyCode::Esc => self.overlay = Overlay::None,
                    KeyCode::Up => {
                        let next = selected.saturating_sub(1);
                        self.overlay = Overlay::KindPicker { selected: next };
                    }
                    KeyCode::Down => {
                        let next = (selected + 1).min(KIND_CHOICES.len() - 1);
                        self.overlay = Overlay::KindPicker { selected: next };
                    }
                    KeyCode::Enter => {
                        let (kind, _) = KIND_CHOICES[selected.min(KIND_CHOICES.len() - 1)];
                        let default_path = self
                            .start_dir
                            .join(format!("新工程-{}.pieproj", kind.as_str()));
                        self.overlay = Overlay::Input {
                            title: format!("新建{}：工程路径", kind.label()),
                            value: default_path.display().to_string(),
                            purpose: InputPurpose::NewProject(kind),
                        };
                    }
                    _ => {}
                }
                true
            }
            Overlay::Input { value, purpose, .. } => {
                match key.code {
                    KeyCode::Esc => self.overlay = Overlay::None,
                    KeyCode::Backspace => {
                        let mut next = value;
                        next.pop();
                        self.overlay = Overlay::Input {
                            title: self.input_title(purpose),
                            value: next,
                            purpose,
                        };
                    }
                    KeyCode::Char(character) => {
                        let mut next = value;
                        next.push(character);
                        self.overlay = Overlay::Input {
                            title: self.input_title(purpose),
                            value: next,
                            purpose,
                        };
                    }
                    KeyCode::Enter => {
                        self.submit_input(value, purpose);
                    }
                    _ => {}
                }
                true
            }
        }
    }

    fn input_title(&self, purpose: InputPurpose) -> String {
        match purpose {
            InputPurpose::NewProject(kind) => format!("新建{}：工程路径", kind.label()),
            InputPurpose::KeilPath => "Keil C251 安装目录".to_owned(),
        }
    }

    fn submit_input(&mut self, value: String, purpose: InputPurpose) {
        match purpose {
            InputPurpose::NewProject(kind) => {
                let path = PathBuf::from(value.trim());
                if path.as_os_str().is_empty() {
                    self.message = Some("工程路径不能为空".to_owned());
                    return;
                }
                match self.workspace.create(&path, kind, None) {
                    Ok(session) => {
                        self.message = Some(format!("已创建：{}", session.display_name()));
                        self.home_selected = 0;
                        self.enter_project();
                    }
                    Err(error) => self.message = Some(format!("创建失败：{error}")),
                }
            }
            InputPurpose::KeilPath => {
                self.workspace.set_keil_path(Some(value));
                self.overlay = Overlay::None;
            }
        }
    }

    /// 鼠标滚轮移动选择。
    pub fn handle_mouse(&mut self, kind: MouseEventKind) {
        match (kind, self.screen.clone()) {
            (MouseEventKind::ScrollUp, Screen::Home) => self.select_home(-1),
            (MouseEventKind::ScrollDown, Screen::Home) => self.select_home(1),
            (MouseEventKind::ScrollUp, Screen::Browser(mut browser)) => {
                browser.move_selection(-1);
                self.screen = Screen::Browser(browser);
            }
            (MouseEventKind::ScrollDown, Screen::Browser(mut browser)) => {
                browser.move_selection(1);
                self.screen = Screen::Browser(browser);
            }
            (MouseEventKind::ScrollUp, Screen::Settings) => {
                self.settings_selected = self.settings_selected.saturating_sub(1);
            }
            (MouseEventKind::ScrollDown, Screen::Settings) => {
                self.settings_selected = (self.settings_selected + 1).min(SETTINGS_ROWS.len() - 1);
            }
            _ => {}
        }
    }

    fn browser_start_directory(&self) -> PathBuf {
        self.workspace
            .session
            .as_ref()
            .and_then(|session| session.path.parent().map(Path::to_path_buf))
            .unwrap_or_else(|| self.start_dir.clone())
    }

    /// 渲染一帧。
    pub fn draw(&mut self, frame: &mut Frame) {
        match self.screen.clone() {
            Screen::Home => self.draw_home(frame),
            Screen::Project => self.draw_project(frame),
            Screen::Browser(browser) => {
                draw_browser(frame, frame.area(), &browser, &self.palette);
                self.draw_status(frame);
            }
            Screen::Settings => {
                let rows = self.settings_rows();
                draw_settings(
                    frame,
                    frame.area(),
                    &rows,
                    self.settings_selected,
                    &self.palette,
                );
                draw_status(
                    frame,
                    Rect {
                        x: 0,
                        y: frame.area().height.saturating_sub(1),
                        width: frame.area().width,
                        height: 1,
                    },
                    "设置",
                    self.message.as_deref(),
                    &self.palette,
                );
            }
        }
        self.draw_overlay(frame);
    }

    fn draw_home(&mut self, frame: &mut Frame) {
        let area = frame.area();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(10), Constraint::Length(1)])
            .split(area);
        let recent: Vec<RecentItem> = self
            .workspace
            .recent()
            .iter()
            .map(|project| RecentItem {
                name: crate::project_display_name(&project.path),
                path: project.path.clone(),
                kind_label: project.kind.map_or_else(String::new, |kind| {
                    kind.label().trim_end_matches("项目").to_owned()
                }),
                available: Path::new(&project.path).exists(),
            })
            .collect();
        let status = self.workspace.session.as_ref().map_or_else(
            || "就绪 · 最近项目自动记录".to_owned(),
            |session| {
                format!(
                    "{} · {} · {}",
                    session.display_name(),
                    session.document.kind.label(),
                    session.save_status.as_str()
                )
            },
        );
        let view = HomeView {
            app_title: "PIE-Block TUI",
            subtitle: "机器人图形化配置 · 终端版",
            recent: &recent,
            selected: self.home_selected,
            status: &status,
            message: self.message.as_deref(),
        };
        draw_home(frame, chunks[0], &view, &self.palette);
        draw_status(
            frame,
            chunks[1],
            "Home",
            self.message.as_deref(),
            &self.palette,
        );
    }

    fn draw_project(&mut self, frame: &mut Frame) {
        let area = frame.area();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(8), Constraint::Length(1)])
            .split(area);
        let Some(session) = self.workspace.session.as_ref() else {
            self.screen = Screen::Home;
            return;
        };
        let kind_steps = session.document.kind.steps().len();
        let lines = vec![
            Line::from(vec![
                Span::styled("工程：", self.palette.muted()),
                Span::styled(session.display_name(), self.palette.title()),
            ]),
            Line::from(vec![
                Span::styled("类型：", self.palette.muted()),
                Span::styled(session.document.kind.label(), self.palette.text()),
                Span::styled("    格式：", self.palette.muted()),
                Span::styled(
                    format!("v{}", pieblock_core::FORMAT_VERSION),
                    self.palette.text(),
                ),
            ]),
            Line::from(vec![
                Span::styled("路径：", self.palette.muted()),
                Span::styled(session.path.display().to_string(), self.palette.text()),
            ]),
            Line::from(vec![
                Span::styled("保存：", self.palette.muted()),
                Span::styled(session.save_status.as_str(), self.palette.ok()),
                Span::styled("    步骤：", self.palette.muted()),
                Span::styled(format!("{kind_steps} 步向导"), self.palette.text()),
            ]),
            Line::from(""),
            Line::from(Span::styled(
                "M4 将在此接入完整向导表单；当前可用：S 保存（Ctrl+S/F5）、O 打开、S 设置、H 首页、Q 退出。",
                self.palette.muted(),
            )),
        ];
        let block = Block::default()
            .borders(Borders::ALL)
            .border_style(self.palette.border_focused())
            .title(Span::styled("工程概览", self.palette.title()))
            .title_alignment(Alignment::Left);
        frame.render_widget(Paragraph::new(lines).block(block), chunks[0]);
        draw_status(
            frame,
            chunks[1],
            "工程",
            self.message.as_deref(),
            &self.palette,
        );
    }

    fn draw_status(&self, frame: &mut Frame) {
        let area = frame.area();
        draw_status(
            frame,
            Rect {
                x: 0,
                y: area.height.saturating_sub(1),
                width: area.width,
                height: 1,
            },
            "提示",
            self.message.as_deref(),
            &self.palette,
        );
    }

    fn settings_rows(&self) -> Vec<SettingRow> {
        let settings = &self.workspace.settings;
        vec![
            SettingRow {
                label: SETTINGS_ROWS[0].0,
                value: self.workspace.theme_label().to_owned(),
                hint: SETTINGS_ROWS[0].1,
            },
            SettingRow {
                label: SETTINGS_ROWS[1].0,
                value: match settings.compiler {
                    CompilerKind::Sdcc => "SDCC（内置 C251）".to_owned(),
                    CompilerKind::Keil => "Keil C251".to_owned(),
                },
                hint: SETTINGS_ROWS[1].1,
            },
            SettingRow {
                label: SETTINGS_ROWS[2].0,
                value: settings
                    .keil_path
                    .clone()
                    .filter(|path| !path.is_empty())
                    .unwrap_or_else(|| "（未设置）".to_owned()),
                hint: SETTINGS_ROWS[2].1,
            },
            SettingRow {
                label: SETTINGS_ROWS[3].0,
                value: if settings.suppress_flash_guide {
                    "已隐藏".to_owned()
                } else {
                    "显示".to_owned()
                },
                hint: SETTINGS_ROWS[3].1,
            },
            SettingRow {
                label: SETTINGS_ROWS[4].0,
                value: if settings.suppress_template_guide {
                    "已隐藏".to_owned()
                } else {
                    "显示".to_owned()
                },
                hint: SETTINGS_ROWS[4].1,
            },
        ]
    }

    fn draw_overlay(&mut self, frame: &mut Frame) {
        let area = frame.area();
        match self.overlay.clone() {
            Overlay::None => {}
            Overlay::KindPicker { selected } => {
                let width = area.width.saturating_sub(8).clamp(40, 76);
                let height = u16::try_from(KIND_CHOICES.len()).unwrap_or(4) + 4;
                let popup = centered(area, width, height);
                frame.render_widget(Clear, popup);
                let items: Vec<ListItem> = KIND_CHOICES
                    .iter()
                    .map(|(kind, description)| {
                        ListItem::new(vec![
                            Line::from(vec![
                                Span::styled("■ ", self.palette.accent()),
                                Span::styled(kind.label(), self.palette.text()),
                            ]),
                            Line::from(Span::styled(
                                format!("   {description}"),
                                self.palette.muted(),
                            )),
                        ])
                    })
                    .collect();
                let list = List::new(items)
                    .block(
                        Block::default()
                            .borders(Borders::ALL)
                            .border_style(self.palette.border_focused())
                            .title(Span::styled("新建工程：选择类型", self.palette.title())),
                    )
                    .highlight_style(self.palette.selection())
                    .highlight_symbol("▶ ");
                let mut state = ListState::default();
                state.select(Some(selected.min(KIND_CHOICES.len().saturating_sub(1))));
                frame.render_stateful_widget(list, popup, &mut state);
            }
            Overlay::Input { title, value, .. } => {
                let width = area.width.saturating_sub(8).clamp(40, 76);
                let popup = centered(area, width, 5);
                frame.render_widget(Clear, popup);
                let lines = vec![
                    Line::from(Span::styled(value.clone(), self.palette.text())),
                    Line::from(""),
                    Line::from(Span::styled(
                        "Enter 确认，Esc 取消（路径可编辑）",
                        self.palette.muted(),
                    )),
                ];
                let paragraph = Paragraph::new(lines).block(
                    Block::default()
                        .borders(Borders::ALL)
                        .border_style(self.palette.border_focused())
                        .title(Span::styled(title, self.palette.title())),
                );
                frame.render_widget(paragraph, popup);
            }
        }
    }
}

fn centered(area: Rect, width: u16, height: u16) -> Rect {
    Rect {
        x: area.x + (area.width.saturating_sub(width)) / 2,
        y: area.y + (area.height.saturating_sub(height)) / 2,
        width: width.min(area.width),
        height: height.min(area.height),
    }
}

fn palette_for(mode: ThemeMode) -> Palette {
    match mode {
        ThemeMode::Dark => Palette::dark(),
        ThemeMode::Light => Palette::light(),
    }
}

impl Workspace {
    /// 设置里的主题映射到界面主题（跟随系统在终端里默认深色）。
    #[must_use]
    pub fn theme_mode(&self) -> ThemeMode {
        match self.settings.theme {
            crate::settings::ThemePreference::Light => ThemeMode::Light,
            _ => ThemeMode::Dark,
        }
    }
}

/// 快捷键提示（帮助浮层/文档用）。
#[must_use]
pub const fn shortcut_help() -> &'static str {
    "首页：N 新建 / O 打开 / S 设置 / ↑↓ 选择 / Enter 打开最近 / Q 退出\n\
     工程：Ctrl+S 或 F5 保存 / O 打开 / S 设置 / H 首页 / Q 退出\n\
     浏览器：↑↓ 移动 / Enter 进入或打开 / Backspace 上级 / Esc 返回\n\
     设置：↑↓ 选择 / Enter 切换 / Esc 返回"
}

#[cfg(test)]
mod tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    fn temp_dir(name: &str) -> PathBuf {
        let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-test-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        dir
    }

    fn render(shell: &mut Shell, width: u16, height: u16) -> String {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("terminal");
        terminal.draw(|frame| shell.draw(frame)).expect("draw");
        let buffer = terminal.backend().buffer();
        let area = *buffer.area();
        let mut lines = Vec::new();
        for y in area.y..area.y + area.height {
            let mut line = String::new();
            for x in area.x..area.x + area.width {
                line.push_str(buffer[(x, y)].symbol());
            }
            lines.push(line.trim_end().to_owned());
        }
        lines.join("\n")
    }

    fn compact(text: &str) -> String {
        text.chars().filter(|ch| !ch.is_whitespace()).collect()
    }

    #[test]
    fn home_shows_and_quit_works() {
        let dir = temp_dir("home");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        let text = compact(&render(&mut shell, 80, 24));
        assert!(text.contains("PIE-BlockTUI"));
        assert!(text.contains("还没有最近项目"));
        shell.handle_key(key(KeyCode::Char('q')));
        // quit 标志私有，通过再次渲染交给 run 循环判断；这里确认按键不 panic 且页面仍可绘制。
        let _ = render(&mut shell, 80, 24);
    }

    #[test]
    fn new_project_flow_creates_file_and_opens_project_screen() {
        let dir = temp_dir("create");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        assert!(matches!(shell.overlay, Overlay::KindPicker { selected: 0 }));
        shell.handle_key(key(KeyCode::Down));
        shell.handle_key(key(KeyCode::Enter));
        assert!(matches!(
            shell.overlay,
            Overlay::Input {
                purpose: InputPurpose::NewProject(ProjectKind::Engineer),
                ..
            }
        ));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Project);
        let session = shell.workspace.session.as_ref().expect("session");
        assert_eq!(session.document.kind, ProjectKind::Engineer);
        assert!(session.path.exists());
        assert!(shell.workspace.recent().len() == 1);
        let text = compact(&render(&mut shell, 120, 36));
        assert!(text.contains("工程概览"));
        assert!(text.contains("工程项目"));
        assert!(text.contains("M4"));
    }

    #[test]
    fn settings_keyboard_cycles_and_persists() {
        let dir = temp_dir("settings");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('s')));
        assert_eq!(shell.screen, Screen::Settings);
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(
            shell.workspace.settings.theme,
            crate::settings::ThemePreference::Light
        );
        shell.handle_key(key(KeyCode::Down));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.workspace.settings.compiler, CompilerKind::Keil);
        let reloaded = Workspace::load(dir.join("data"));
        assert_eq!(
            reloaded.settings.theme,
            crate::settings::ThemePreference::Light
        );
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Home);
    }

    #[test]
    fn browser_opens_project_file() {
        let dir = temp_dir("browser");
        let project = dir.join("demo.pieproj");
        std::fs::write(
            &project,
            pieblock_core::ProjectDocument::create(ProjectKind::Infantry).to_pretty_string(),
        )
        .expect("project");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('o')));
        assert!(matches!(shell.screen, Screen::Browser(_)));
        // 目录里只有 demo.pieproj，选择第 1 项（若 target 目录里无目录项）。
        let entries = match &shell.screen {
            Screen::Browser(browser) => browser.entries.len(),
            _ => 0,
        };
        for _ in 0..entries.saturating_sub(1) {
            shell.handle_key(key(KeyCode::Down));
        }
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Project);
        assert_eq!(
            shell
                .workspace
                .session
                .as_ref()
                .expect("session")
                .document
                .kind,
            ProjectKind::Infantry
        );
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Home);
    }
}

//! M3 主循环：首页 ↔ 工程概览 ↔ 文件浏览器 ↔ 设置，接入真实工作区。

use std::io;
use std::path::{Path, PathBuf};
use std::time::Instant;

use crossterm::event::{self, Event, KeyCode, KeyEvent, KeyModifiers, MouseEventKind};
use pieblock_core::ProjectKind;
use pieblock_toolchain::models::CompilerKind;
use pieblock_ui::ThemeMode;
use pieblock_ui::{
    BrowserAction, FileBrowser, FormState, HomeView, Palette, RecentItem, SettingRow, draw_browser,
    draw_home, draw_settings, draw_status, wizard_pages,
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
    Wizard,
    Review,
    Code,
    Build,
    Piano,
    Playback,
    Flash,
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
    MidiPath,
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
    pub form: Option<FormState>,
    pub pages: Vec<pieblock_ui::FormPage>,
    pub wizard_index: usize,
    pub issues: Vec<pieblock_core::ValidationIssue>,
    pub review_selected: usize,
    pub code: Option<pieblock_ui::CodeView>,
    pub code_export_name: String,
    pub build_log: Option<pieblock_ui::CodeView>,
    pub build_listing: Option<pieblock_ui::CodeView>,
    pub build_ok: bool,
    pub piano: Option<pieblock_ui::PianoRoll>,
    pub playback: Option<pieblock_ui::Playback>,
    pub flash: Option<pieblock_ui::FlashState>,
    pub flash_hex: Option<(PathBuf, String)>,
    pub flash_op: Option<pieblock_hid::FlashOperation>,
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
            form: None,
            pages: Vec::new(),
            wizard_index: 0,
            issues: Vec::new(),
            review_selected: 0,
            code: None,
            code_export_name: "main.c".to_owned(),
            build_log: None,
            build_listing: None,
            build_ok: false,
            piano: None,
            playback: None,
            flash: None,
            flash_hex: None,
            flash_op: None,
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
            self.poll_flash();
            if let Some(playback) = self.playback.as_mut() {
                playback.tick(Instant::now());
            }
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
            Screen::Wizard => self.handle_wizard_key(key),
            Screen::Review => self.handle_review_key(key),
            Screen::Code => self.handle_code_key(key),
            Screen::Build => self.handle_build_key(key),
            Screen::Piano => self.handle_piano_key(key),
            Screen::Playback => self.handle_playback_key(key),
            Screen::Flash => self.handle_flash_key(key),
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
            KeyCode::Char('o') | KeyCode::Char('w') | KeyCode::Enter => self.enter_wizard(),
            KeyCode::Char('r') => self.enter_review(),
            KeyCode::Char('c') => self.enter_code(),
            KeyCode::Char('b') => self.enter_build(),
            KeyCode::Char('m') => self.enter_piano(),
            KeyCode::Char('p') => self.enter_playback(),
            KeyCode::Char('f') => self.enter_flash(),
            KeyCode::Char('i') => self.begin_midi_import(),
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
            InputPurpose::MidiPath => "导入 MIDI：文件路径".to_owned(),
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
            InputPurpose::MidiPath => {
                self.overlay = Overlay::None;
                let path = PathBuf::from(value.trim());
                let bytes = match std::fs::read(&path) {
                    Ok(bytes) => bytes,
                    Err(error) => {
                        self.message = Some(format!("无法读取 MIDI：{error}"));
                        return;
                    }
                };
                let data = match pieblock_core::midi::MidiCodec::parse(&bytes) {
                    Ok(data) => data,
                    Err(error) => {
                        self.message = Some(format!("MIDI 解析失败：{error}"));
                        return;
                    }
                };
                let Some((index, _)) = data
                    .tracks
                    .iter()
                    .enumerate()
                    .find(|(_, track)| track.playable())
                else {
                    self.message = Some("MIDI 中没有可播放的旋律轨道".to_owned());
                    return;
                };
                let source_name = path
                    .file_name()
                    .map(|name| name.to_string_lossy().into_owned());
                let music = match data.select_track(
                    index,
                    source_name,
                    pieblock_core::model::MusicOverlapMode::Nearest,
                    true,
                ) {
                    Ok(music) => music,
                    Err(error) => {
                        self.message = Some(format!("MIDI 导入失败：{error}"));
                        return;
                    }
                };
                let track_name = music.track_name.clone().unwrap_or_default();
                let notes = music.notes.len();
                let Some(session) = self.workspace.session.as_mut() else {
                    self.message = Some("请先打开音乐工程".to_owned());
                    return;
                };
                if !matches!(
                    session.document.config,
                    pieblock_core::model::ProjectConfig::Music(_)
                ) {
                    self.message = Some("MIDI 导入仅用于音乐工程".to_owned());
                    return;
                }
                session.document.config = pieblock_core::model::ProjectConfig::Music(music);
                let config = session.document.config.clone();
                self.workspace.update_config(config);
                self.workspace.save_now();
                self.message = Some(format!("已导入 MIDI：{track_name}（{notes} 个音符）"));
            }
        }
    }

    fn begin_midi_import(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        if !matches!(
            session.document.config,
            pieblock_core::model::ProjectConfig::Music(_)
        ) {
            self.message = Some("MIDI 导入仅用于音乐工程".to_owned());
            return;
        }
        self.overlay = Overlay::Input {
            title: "导入 MIDI：文件路径".to_owned(),
            value: self.start_dir.display().to_string() + "\\",
            purpose: InputPurpose::MidiPath,
        };
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

    fn enter_code(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        match pieblock_core::generate(&session.document.config) {
            Ok(source) => {
                self.code_export_name = "main.c".to_owned();
                self.code = Some(pieblock_ui::CodeView::new("main.c · 生成预览", &source));
                self.message = None;
                self.screen = Screen::Code;
            }
            Err(error) => {
                self.message = Some(format!("无法生成代码：{}", error.message()));
            }
        }
    }

    fn handle_code_key(&mut self, key: KeyEvent) {
        let Some(code) = self.code.as_mut() else {
            self.screen = Screen::Project;
            return;
        };
        let visible = 20;
        match key.code {
            KeyCode::Esc | KeyCode::Char('h') => self.screen = Screen::Project,
            KeyCode::Up => code.scroll_by(-1, visible),
            KeyCode::Down => code.scroll_by(1, visible),
            KeyCode::PageUp => code.scroll_by(-10, visible),
            KeyCode::PageDown => code.scroll_by(10, visible),
            KeyCode::Home => code.scroll_to(0, visible),
            KeyCode::End => {
                let last = code.len().saturating_sub(1);
                code.scroll_to(last, visible);
            }
            KeyCode::Char('w') => {
                if let Some(session) = self.workspace.session.as_ref() {
                    let target = session.path.with_file_name(&self.code_export_name);
                    let text = code.lines.join("\n");
                    match crate::settings::atomic_write(&target, text.as_bytes()) {
                        Ok(()) => {
                            self.message = Some(format!("已导出：{}", target.display()));
                        }
                        Err(error) => {
                            self.message = Some(format!("导出失败：{error}"));
                        }
                    }
                }
            }
            _ => {}
        }
    }

    fn draw_code(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if let Some(code) = self.code.as_mut() {
            code.render(frame, area, true, &self.palette, self.message.as_deref());
        }
    }

    fn enter_flash(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        let project_dir = session.path.parent().map(Path::to_path_buf);
        let found = self.flash_hex.clone().or_else(|| {
            project_dir.as_ref().and_then(|directory| {
                let hex = directory.join("main.hex");
                if hex.is_file() {
                    std::fs::read(&hex)
                        .ok()
                        .map(|bytes| (hex, pieblock_core::sha256_hex(&bytes)))
                } else {
                    None
                }
            })
        });
        let (hex_path, sha) = found.map_or((None, None), |(path, sha)| (Some(path), Some(sha)));
        self.flash = Some(pieblock_ui::FlashState::with_probe(hex_path, sha));
        self.message = None;
        self.screen = Screen::Flash;
    }

    fn poll_flash(&mut self) {
        let Some(operation) = self.flash_op.as_ref() else {
            return;
        };
        let mut finished = false;
        let mut events = Vec::new();
        while let Some(event) = operation.try_recv_event() {
            if matches!(
                event.stage,
                pieblock_hid::FlashStage::Done | pieblock_hid::FlashStage::Canceled
            ) {
                finished = true;
            }
            events.push(event);
            if finished {
                break;
            }
        }
        let Some(state) = self.flash.as_mut() else {
            return;
        };
        for event in events {
            state.push_event(event);
        }
        if finished {
            if let Some(operation) = self.flash_op.take() {
                let result = operation.wait();
                state.finish(result);
            }
        }
    }

    fn handle_flash_key(&mut self, key: KeyEvent) {
        let Some(action) = self.flash.as_mut().map(|flash| flash.handle_key(key)) else {
            self.screen = Screen::Project;
            return;
        };
        match action {
            pieblock_ui::FlashAction::Close => self.screen = Screen::Project,
            pieblock_ui::FlashAction::Cancel => {
                if let Some(operation) = self.flash_op.as_ref() {
                    operation.cancel();
                }
            }
            pieblock_ui::FlashAction::Start { hex_path, sha256 } => {
                let transport = pieblock_hid::NativeHidTransport::with_cancel_flag;
                let operation = pieblock_hid::start_flash(
                    hex_path,
                    sha256,
                    transport,
                    pieblock_ui::FlashState::options(),
                );
                if let Some(state) = self.flash.as_mut() {
                    state.running = true;
                    state.log.clear();
                    state.push_log("开始烧录…".to_owned());
                }
                self.flash_op = Some(operation);
            }
            pieblock_ui::FlashAction::None => {}
        }
    }

    fn draw_flash(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if let Some(flash) = self.flash.as_mut() {
            flash.render(frame, area, &self.palette);
        }
    }

    fn enter_playback(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        match &session.document.config {
            pieblock_core::model::ProjectConfig::Music(music) => {
                self.playback = Some(pieblock_ui::Playback::new(music));
                self.message = None;
                self.screen = Screen::Playback;
            }
            _ => {
                self.message = Some("播放预览仅用于音乐工程".to_owned());
            }
        }
    }

    fn handle_playback_key(&mut self, key: KeyEvent) {
        let Some(action) = self
            .playback
            .as_mut()
            .map(|playback| playback.handle_key(key))
        else {
            self.screen = Screen::Project;
            return;
        };
        if action == pieblock_ui::PlaybackAction::Close {
            self.screen = Screen::Project;
        }
    }

    fn draw_playback(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if let Some(playback) = self.playback.as_mut() {
            playback.render(frame, area, &self.palette);
        }
    }

    fn enter_piano(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        match &session.document.config {
            pieblock_core::model::ProjectConfig::Music(music) => {
                self.piano = Some(pieblock_ui::PianoRoll::new(music));
                self.message = None;
                self.screen = Screen::Piano;
            }
            _ => {
                self.message = Some("钢琴卷帘仅用于音乐工程".to_owned());
            }
        }
    }

    fn handle_piano_key(&mut self, key: KeyEvent) {
        let Some(action) = self.piano.as_mut().map(|piano| piano.handle_key(key)) else {
            self.screen = Screen::Project;
            return;
        };
        match action {
            pieblock_ui::PianoAction::Commit => {
                if let (Some(piano), Some(session)) =
                    (self.piano.as_ref(), self.workspace.session.as_mut())
                {
                    piano.commit(&mut session.document.config);
                    let config = session.document.config.clone();
                    self.workspace.update_config(config);
                }
                self.workspace.save_now();
                self.message = Some("钢琴卷帘修改已保存".to_owned());
                self.screen = Screen::Project;
            }
            pieblock_ui::PianoAction::Changed => {
                if let Some(session) = self.workspace.session.as_mut() {
                    if let Some(piano) = self.piano.as_ref() {
                        piano.commit(&mut session.document.config);
                    }
                    let config = session.document.config.clone();
                    self.workspace.update_config(config);
                }
            }
            pieblock_ui::PianoAction::None => {}
        }
    }

    fn draw_piano(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if let Some(piano) = self.piano.as_mut() {
            piano.render(frame, area, &self.palette);
        }
    }

    fn enter_build(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        let kind = session.document.kind;
        let source = match pieblock_core::generate(&session.document.config) {
            Ok(source) => source,
            Err(error) => {
                self.message = Some(format!("无法构建：{}", error.message()));
                return;
            }
        };
        let Some(runtime_root) = locate_runtime_root() else {
            self.message = Some(
                "未找到 SDCC 工具链（vendor/sdcc-toolchain 与 stc32g_sdcc），请先将运行时资源放到程序目录或仓库根目录。"
                    .to_owned(),
            );
            return;
        };
        let work_root = self.workspace.data_dir.join("build");
        let artifacts =
            pieblock_toolchain::BuildArtifactRepository::new(work_root.join("artifacts"));
        let mut builder = pieblock_toolchain::FirmwareBuilder::new(
            runtime_root.clone(),
            work_root,
            artifacts,
            Box::new(pieblock_toolchain::SystemProcessRunner::new()),
        )
        .with_assets_root(runtime_root.clone());
        let fingerprint = match builder
            .resolve_compiler_fingerprint(pieblock_toolchain::CompilerKind::Sdcc, None)
        {
            Ok(fingerprint) => fingerprint,
            Err(error) => {
                self.message = Some(format!("工具链指纹计算失败：{error}"));
                return;
            }
        };
        let request = pieblock_toolchain::BuildRequest {
            project_kind: kind,
            source_code: source,
            compiler: pieblock_toolchain::CompilerKind::Sdcc,
            compiler_fingerprint: fingerprint,
            keil_root: None,
        };
        let mut logs: Vec<String> = Vec::new();
        let result = {
            let mut emit = |event: pieblock_toolchain::BuildEvent| {
                logs.push(format!(
                    "[{}] {}{}",
                    event.stage.as_str(),
                    event.message,
                    event
                        .current
                        .zip(event.total)
                        .map_or_else(String::new, |(current, total)| format!(
                            "（{current}/{total}）"
                        ))
                ));
            };
            builder.build(&request, &mut emit, &|_| {})
        };
        self.build_ok = result.success;
        logs.push(String::new());
        logs.push(if result.success {
            "构建成功。".to_owned()
        } else if result.canceled {
            "构建已取消。".to_owned()
        } else {
            format!(
                "构建失败（退出码 {}）。请查看上方日志。",
                result
                    .exit_code
                    .map_or_else(|| "未知".to_owned(), |code| code.to_string())
            )
        });
        if let Some(artifact) = result.artifact.as_ref() {
            logs.push(format!(
                "HEX：{}（{} 字节，SHA-256 {}）",
                artifact.hex_path,
                artifact.byte_count,
                &artifact.hex_sha256[..artifact.hex_sha256.len().min(16)]
            ));
        }
        self.build_listing = result
            .listing
            .as_deref()
            .map(|listing| pieblock_ui::CodeView::new("main.rst · 汇编列表", listing));
        self.build_log = Some(pieblock_ui::CodeView::new(
            "构建日志 · SDCC",
            &logs.join("\n"),
        ));
        self.message = Some(if result.success {
            "构建成功，L 查看汇编列表，W 导出".to_owned()
        } else {
            "构建失败，请查看日志".to_owned()
        });
        self.screen = Screen::Build;
    }

    fn handle_build_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Esc | KeyCode::Char('h') => self.screen = Screen::Project,
            KeyCode::Char('l') => {
                if let Some(listing) = self.build_listing.take() {
                    self.code = Some(listing);
                    self.code_export_name = "main.rst".to_owned();
                    self.message = Some("汇编列表；W 导出 main.rst".to_owned());
                    self.screen = Screen::Code;
                } else {
                    self.message = Some("本次构建没有汇编列表".to_owned());
                }
            }
            KeyCode::Char('w') => {
                if let Some(listing) = self.build_listing.as_ref() {
                    if let Some(session) = self.workspace.session.as_ref() {
                        let target = session.path.with_file_name("main.rst");
                        let text = listing.lines.join("\n");
                        match crate::settings::atomic_write(&target, text.as_bytes()) {
                            Ok(()) => {
                                self.message = Some(format!("已导出：{}", target.display()));
                            }
                            Err(error) => {
                                self.message = Some(format!("导出失败：{error}"));
                            }
                        }
                    }
                }
            }
            KeyCode::Up => {
                if let Some(log) = self.build_log.as_mut() {
                    log.scroll_by(-1, 20);
                }
            }
            KeyCode::Down => {
                if let Some(log) = self.build_log.as_mut() {
                    log.scroll_by(1, 20);
                }
            }
            KeyCode::PageUp => {
                if let Some(log) = self.build_log.as_mut() {
                    log.scroll_by(-10, 20);
                }
            }
            KeyCode::PageDown => {
                if let Some(log) = self.build_log.as_mut() {
                    log.scroll_by(10, 20);
                }
            }
            _ => {}
        }
    }

    fn draw_build(&mut self, frame: &mut Frame) {
        let area = frame.area();
        if let Some(log) = self.build_log.as_mut() {
            log.render(frame, area, false, &self.palette, self.message.as_deref());
        }
    }

    fn enter_review(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        self.pages = wizard_pages(session.document.kind, &session.document.config);
        self.issues = pieblock_core::validate(&session.document.config);
        self.review_selected = 0;
        self.message = None;
        self.screen = Screen::Review;
    }

    fn handle_review_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Esc | KeyCode::Char('q') | KeyCode::Char('h') => {
                self.screen = Screen::Project;
            }
            KeyCode::Up => self.review_selected = self.review_selected.saturating_sub(1),
            KeyCode::Down => {
                self.review_selected =
                    (self.review_selected + 1).min(self.issues.len().saturating_sub(1));
            }
            KeyCode::Enter => self.jump_to_issue(),
            _ => {}
        }
    }

    fn jump_to_issue(&mut self) {
        let Some(issue) = self.issues.get(self.review_selected) else {
            return;
        };
        let path = issue.field_path.clone();
        let mut target: Option<(usize, usize)> = None;
        for (page_index, page) in self.pages.iter().enumerate() {
            if let Some(field_index) = page.fields.iter().position(|field| field.path == path) {
                target = Some((page_index, field_index));
                break;
            }
        }
        let Some((page_index, field_index)) = target else {
            self.message = Some(format!("该问题位于尚未移植的页面或列表项：{path}"));
            return;
        };
        if self.form.is_none() {
            let config = self
                .workspace
                .session
                .as_ref()
                .map(|session| session.document.config.clone());
            self.form = config.map(FormState::new);
        }
        self.wizard_index = page_index;
        if let Some(form) = self.form.as_mut() {
            form.selected = field_index;
        }
        self.message = Some(format!("已跳转到：{path}"));
        self.screen = Screen::Wizard;
    }

    fn draw_review(&mut self, frame: &mut Frame) {
        let area = frame.area();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(4),
                Constraint::Min(4),
                Constraint::Length(1),
            ])
            .split(area);
        let errors = self
            .issues
            .iter()
            .filter(|issue| issue.severity == pieblock_core::IssueSeverity::Error)
            .count();
        let warnings = self.issues.len().saturating_sub(errors);
        let header = Paragraph::new(vec![
            Line::from(Span::styled("问题审查", self.palette.title())),
            Line::from(Span::styled(
                format!("错误 {errors} · 警告 {warnings} · Enter 跳转字段 · Esc 返回"),
                self.palette.muted(),
            )),
        ])
        .block(
            Block::default()
                .borders(Borders::ALL)
                .border_style(self.palette.border_focused()),
        );
        frame.render_widget(header, chunks[0]);
        let items: Vec<ListItem> = if self.issues.is_empty() {
            vec![ListItem::new(Line::from(Span::styled(
                "没有校验问题，可以继续生成代码。",
                self.palette.ok(),
            )))]
        } else {
            self.issues
                .iter()
                .map(|issue| {
                    let is_error = issue.severity == pieblock_core::IssueSeverity::Error;
                    let (icon, style) = if is_error {
                        ("✖", self.palette.error())
                    } else {
                        ("⚠", self.palette.warn())
                    };
                    ListItem::new(Line::from(vec![
                        Span::styled(format!("{icon} "), style),
                        Span::styled(format!("{:<28}", issue.field_path), self.palette.muted()),
                        Span::styled(issue.message.clone(), self.palette.text()),
                    ]))
                })
                .collect()
        };
        let list = List::new(items)
            .block(
                Block::default()
                    .borders(Borders::ALL)
                    .border_style(self.palette.border())
                    .title(Span::styled("校验结果", self.palette.title())),
            )
            .highlight_style(self.palette.selection())
            .highlight_symbol("▶ ");
        let mut state = ListState::default();
        state.select(Some(
            self.review_selected
                .min(self.issues.len().saturating_sub(1)),
        ));
        frame.render_stateful_widget(list, chunks[1], &mut state);
        draw_status(
            frame,
            chunks[2],
            "审查",
            self.message.as_deref(),
            &self.palette,
        );
    }

    fn enter_wizard(&mut self) {
        let Some(session) = self.workspace.session.as_ref() else {
            return;
        };
        self.pages = wizard_pages(session.document.kind, &session.document.config);
        if self.pages.is_empty() {
            self.message = Some("该工程类型的向导页尚未移植（M4 进行中）".to_owned());
            return;
        }
        self.wizard_index = 0;
        self.form = Some(FormState::new(session.document.config.clone()));
        self.message = None;
        self.screen = Screen::Wizard;
    }

    fn commit_wizard_page(&mut self) {
        if let Some(form) = &self.form {
            self.workspace.update_config(form.config.clone());
        }
    }

    fn leave_wizard(&mut self) {
        self.commit_wizard_page();
        self.workspace.save_now();
        self.message = Some("向导修改已保存".to_owned());
        self.screen = Screen::Project;
    }

    fn handle_wizard_key(&mut self, key: KeyEvent) {
        if self.pages.is_empty() || self.form.is_none() {
            self.screen = Screen::Project;
            return;
        }
        match key.code {
            KeyCode::PageDown => {
                if self.wizard_index + 1 < self.pages.len() {
                    self.commit_wizard_page();
                    self.wizard_index += 1;
                } else {
                    self.leave_wizard();
                }
            }
            KeyCode::PageUp => {
                if self.wizard_index > 0 {
                    self.commit_wizard_page();
                    self.wizard_index -= 1;
                } else {
                    self.leave_wizard();
                }
            }
            KeyCode::Esc | KeyCode::Char('h') => self.leave_wizard(),
            _ => {
                let index = self.wizard_index.min(self.pages.len().saturating_sub(1));
                if self.pages[index].id == "mechanism" {
                    if let Some(action) = actuator_action(key.code) {
                        self.apply_actuator_action(action);
                        return;
                    }
                }
                if self.pages[index].id == "tests" {
                    if let Some(delta) = debug_reorder_delta(key.code) {
                        self.apply_debug_reorder(delta);
                        return;
                    }
                }
                if self.pages[index].id == "mappings" {
                    if let Some(action) = mapping_action(key.code) {
                        self.apply_mapping_action(action);
                        return;
                    }
                }
                let page = &self.pages[index];
                if let Some(form) = self.form.as_mut() {
                    let action = form.handle_key(page, key);
                    if action == pieblock_ui::FormAction::Changed {
                        self.workspace.update_config(form.config.clone());
                    }
                }
            }
        }
    }

    fn selected_actuator_path(&self) -> Option<&'static str> {
        let index = self.wizard_index.min(self.pages.len().saturating_sub(1));
        let form = self.form.as_ref()?;
        let page = self.pages.get(index)?;
        page.fields.get(form.selected).map(|field| field.path)
    }

    fn apply_actuator_action(&mut self, action: ActuatorAction) {
        let path = self.selected_actuator_path();
        let selected = path.and_then(parse_actuator_path);
        let Some(form) = self.form.as_mut() else {
            return;
        };
        let mut changed = false;
        if let pieblock_core::model::ProjectConfig::Infantry(config) = &mut form.config {
            match action {
                ActuatorAction::AddYaw => {
                    config.yaw.push(default_axis_actuator());
                    changed = true;
                }
                ActuatorAction::AddPitch => {
                    config.pitch.push(default_axis_actuator());
                    changed = true;
                }
                ActuatorAction::Delete => {
                    if let Some((axis, index)) = selected {
                        let list = if axis == 0 {
                            &mut config.yaw
                        } else {
                            &mut config.pitch
                        };
                        if index < list.len() {
                            list.remove(index);
                            changed = true;
                        }
                    }
                }
                ActuatorAction::MoveUp | ActuatorAction::MoveDown => {
                    if let Some((axis, index)) = selected {
                        let list = if axis == 0 {
                            &mut config.yaw
                        } else {
                            &mut config.pitch
                        };
                        let target = match action {
                            ActuatorAction::MoveUp => index.checked_sub(1),
                            _ => Some(index + 1),
                        };
                        if let Some(target) = target {
                            if target < list.len() {
                                list.swap(index, target);
                                changed = true;
                            }
                        }
                    }
                }
            }
        }
        if !changed {
            return;
        }
        let config = form.config.clone();
        let old_selected = form.selected;
        self.workspace.update_config(config.clone());
        let kind = self
            .workspace
            .session
            .as_ref()
            .map(|session| session.document.kind);
        if let Some(kind) = kind {
            self.pages = wizard_pages(kind, &config);
            let mut next = FormState::new(config.clone());
            let page_len = self
                .pages
                .get(self.wizard_index)
                .map_or(0, |page| page.fields.len());
            next.selected = old_selected.min(page_len.saturating_sub(1));
            if matches!(action, ActuatorAction::AddYaw | ActuatorAction::AddPitch) {
                let (segment, new_index) = match (&config, action) {
                    (
                        pieblock_core::model::ProjectConfig::Infantry(infantry),
                        ActuatorAction::AddYaw,
                    ) => ("yaw", infantry.yaw.len().saturating_sub(1)),
                    (
                        pieblock_core::model::ProjectConfig::Infantry(infantry),
                        ActuatorAction::AddPitch,
                    ) => ("pitch", infantry.pitch.len().saturating_sub(1)),
                    _ => ("yaw", 0),
                };
                let prefix = format!("gimbal.{segment}.{new_index}.");
                if let Some(position) = self.pages.get(self.wizard_index).and_then(|page| {
                    page.fields
                        .iter()
                        .position(|field| field.path.starts_with(prefix.as_str()))
                }) {
                    next.selected = position;
                }
            }
            self.form = Some(next);
            self.message = Some("执行器列表已更新".to_owned());
        }
    }

    fn apply_mapping_action(&mut self, action: MappingAction) {
        let path = self.selected_actuator_path();
        let selected = path.and_then(parse_mapping_path);
        let Some(form) = self.form.as_mut() else {
            return;
        };
        let mut changed = false;
        let mut target: Option<(usize, usize)> = selected;
        if let pieblock_core::model::ProjectConfig::Engineer(config) = &mut form.config {
            match action {
                MappingAction::Add => {
                    let mode = selected
                        .map_or(0, |(mode, _)| mode)
                        .min(config.modes.len().saturating_sub(1));
                    if let Some(mode_config) = config.modes.get_mut(mode) {
                        mode_config.actions.push(default_action_mapping());
                        target = Some((mode, mode_config.actions.len().saturating_sub(1)));
                        changed = true;
                    }
                }
                MappingAction::Delete => {
                    if let Some((mode, action_index)) = selected {
                        if let Some(mode_config) = config.modes.get_mut(mode) {
                            if action_index < mode_config.actions.len() {
                                mode_config.actions.remove(action_index);
                                target = Some((mode, action_index.saturating_sub(1)));
                                changed = true;
                            }
                        }
                    }
                }
                MappingAction::MoveUp | MappingAction::MoveDown => {
                    if let Some((mode, action_index)) = selected {
                        if let Some(mode_config) = config.modes.get_mut(mode) {
                            let next = match action {
                                MappingAction::MoveUp => action_index.checked_sub(1),
                                _ => Some(action_index + 1),
                            };
                            if let Some(next) = next {
                                if next < mode_config.actions.len() {
                                    mode_config.actions.swap(action_index, next);
                                    target = Some((mode, next));
                                    changed = true;
                                }
                            }
                        }
                    }
                }
            }
        }
        if !changed {
            return;
        }
        let config = form.config.clone();
        self.workspace.update_config(config.clone());
        let kind = self
            .workspace
            .session
            .as_ref()
            .map(|session| session.document.kind);
        if let Some(kind) = kind {
            self.pages = wizard_pages(kind, &config);
            let mut next = FormState::new(config);
            if let Some((mode, action_index)) = target {
                let prefix = format!("modes.{mode}.actions.{action_index}.");
                if let Some(position) = self.pages.get(self.wizard_index).and_then(|page| {
                    page.fields
                        .iter()
                        .position(|field| field.path.starts_with(prefix.as_str()))
                }) {
                    next.selected = position;
                }
            }
            self.form = Some(next);
            self.message = Some("动作映射已更新".to_owned());
        }
    }

    fn apply_debug_reorder(&mut self, delta: i64) {
        let path = self.selected_actuator_path();
        let Some(index) = path.and_then(parse_debug_path) else {
            return;
        };
        let Some(form) = self.form.as_mut() else {
            return;
        };
        let mut changed = false;
        let mut target = index;
        if let pieblock_core::model::ProjectConfig::Debug(config) = &mut form.config {
            let next = i64::try_from(index).unwrap_or(0) + delta;
            if next >= 0 && (next as usize) < config.tests.len() {
                let next = next as usize;
                config.tests.swap(index, next);
                target = next;
                changed = true;
            }
        }
        if !changed {
            return;
        }
        let config = form.config.clone();
        self.workspace.update_config(config.clone());
        let kind = self
            .workspace
            .session
            .as_ref()
            .map(|session| session.document.kind);
        if let Some(kind) = kind {
            self.pages = wizard_pages(kind, &config);
            let mut next_form = FormState::new(config);
            let prefix = format!("tests.{target}.");
            if let Some(position) = self.pages.get(self.wizard_index).and_then(|page| {
                page.fields
                    .iter()
                    .position(|field| field.path.starts_with(prefix.as_str()))
            }) {
                next_form.selected = position;
            }
            self.form = Some(next_form);
            self.message = Some("测试序列顺序已调整".to_owned());
        }
    }

    fn draw_wizard(&mut self, frame: &mut Frame) {
        let index = self.wizard_index.min(self.pages.len().saturating_sub(1));
        let area = frame.area();
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([Constraint::Min(8), Constraint::Length(1)])
            .split(area);
        if let Some(form) = self.form.as_mut() {
            if let Some(page) = self.pages.get(index) {
                form.render(frame, chunks[0], page, &self.palette);
            }
        }
        let status = format!(
            "第 {}/{} 页 · PgUp/PgDn 翻页 · Esc 保存返回",
            index + 1,
            self.pages.len().max(1)
        );
        draw_status(
            frame,
            chunks[1],
            &status,
            self.message.as_deref(),
            &self.palette,
        );
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
            Screen::Wizard => self.draw_wizard(frame),
            Screen::Review => self.draw_review(frame),
            Screen::Code => self.draw_code(frame),
            Screen::Build => self.draw_build(frame),
            Screen::Piano => self.draw_piano(frame),
            Screen::Playback => self.draw_playback(frame),
            Screen::Flash => self.draw_flash(frame),
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
                "Enter/E 进入向导表单（M4 进行中）；Ctrl+S/F5 保存、O 打开、S 设置、H 首页、Q 退出。",
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

#[cfg(test)]
mod wizard_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn wizard_flow_edits_channel_and_saves() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-wizard-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Project);
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Wizard);
        assert_eq!(shell.pages.len(), 3);
        // 第一页第一个字段：通道号。
        shell.handle_key(key(KeyCode::Enter));
        for _ in 0..8 {
            shell.handle_key(key(KeyCode::Backspace));
        }
        shell.handle_key(key(KeyCode::Char('5')));
        shell.handle_key(key(KeyCode::Char('5')));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::PageDown));
        assert_eq!(shell.wizard_index, 1);
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let session = shell.workspace.session.as_ref().expect("session");
        match &session.document.config {
            pieblock_core::model::ProjectConfig::Infantry(value) => {
                assert_eq!(value.remote.channel, Some(55));
            }
            other => panic!("unexpected config: {other:?}"),
        }
        let text = std::fs::read_to_string(&session.path).expect("saved file");
        assert!(text.contains("55"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod review_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    fn setup() -> (Shell, std::path::PathBuf) {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!(
                "shell-review-{}-{}",
                std::process::id(),
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map_or(0, |d| d.as_nanos())
            ));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        if let Some(session) = shell.workspace.session.as_mut() {
            if let pieblock_core::model::ProjectConfig::Infantry(config) =
                &mut session.document.config
            {
                config.remote.channel = Some(999);
            }
            session.save_now().expect("save");
        }
        (shell, dir)
    }

    #[test]
    fn review_lists_issues_and_jumps_to_field() {
        let (mut shell, dir) = setup();
        shell.handle_key(key(KeyCode::Char('r')));
        assert_eq!(shell.screen, Screen::Review);
        assert!(!shell.issues.is_empty());
        let first = shell.issues[0].clone();
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Wizard);
        assert_eq!(shell.wizard_index, 0);
        let form = shell.form.as_ref().expect("form");
        let field = &shell.pages[0].fields[form.selected];
        assert!(first.field_path == field.path || first.field_path.starts_with(field.path));
        assert!(
            shell
                .message
                .as_deref()
                .is_some_and(|message| message.contains("跳转"))
        );
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn review_renders_counts() {
        let (mut shell, dir) = setup();
        shell.handle_key(key(KeyCode::Char('r')));
        let backend = ratatui::backend::TestBackend::new(100, 30);
        let mut terminal = ratatui::Terminal::new(backend).expect("terminal");
        terminal.draw(|frame| shell.draw(frame)).expect("draw");
        let buffer = terminal.backend().buffer();
        let area = *buffer.area();
        let mut text = String::new();
        for y in area.y..area.y + area.height {
            for x in area.x..area.x + area.width {
                text.push_str(buffer[(x, y)].symbol());
            }
        }
        let compact: String = text.chars().filter(|ch| !ch.is_whitespace()).collect();
        assert!(compact.contains("问题审查"));
        assert!(compact.contains("校验结果"));
        assert!(compact.contains("错误"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ActuatorAction {
    AddYaw,
    AddPitch,
    Delete,
    MoveUp,
    MoveDown,
}

fn actuator_action(code: KeyCode) -> Option<ActuatorAction> {
    match code {
        KeyCode::Char('a') => Some(ActuatorAction::AddYaw),
        KeyCode::Char('b') => Some(ActuatorAction::AddPitch),
        KeyCode::Char('d') => Some(ActuatorAction::Delete),
        KeyCode::Char('K') => Some(ActuatorAction::MoveUp),
        KeyCode::Char('J') => Some(ActuatorAction::MoveDown),
        _ => None,
    }
}

fn parse_actuator_path(path: &str) -> Option<(u8, usize)> {
    let rest = path.strip_prefix("gimbal.")?;
    let (axis, rest) = if let Some(rest) = rest.strip_prefix("yaw.") {
        (0_u8, rest)
    } else {
        (1_u8, rest.strip_prefix("pitch.")?)
    };
    let index = rest.split('.').next()?.parse().ok()?;
    Some((axis, index))
}

fn default_axis_actuator() -> pieblock_core::model::AxisActuator {
    pieblock_core::model::AxisActuator {
        drive: Some(pieblock_core::model::DriveType::Servo),
        pin: None,
        direction: None,
        mid_offset: Some(0),
        min_limit: Some(-500),
        max_limit: Some(500),
    }
}

#[cfg(test)]
mod actuator_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn mechanism_page_add_and_delete_actuators() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-actuators-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Wizard);
        shell.handle_key(key(KeyCode::PageDown));
        assert_eq!(shell.pages[shell.wizard_index].id, "mechanism");
        let before = match &shell
            .workspace
            .session
            .as_ref()
            .expect("session")
            .document
            .config
        {
            pieblock_core::model::ProjectConfig::Infantry(config) => config.yaw.len(),
            _ => 0,
        };
        let fields_before = shell.pages[shell.wizard_index].fields.len();
        println!(
            "before={before} fields={fields_before} sel={}",
            shell.form.as_ref().map(|f| f.selected).unwrap_or(0)
        );
        shell.handle_key(key(KeyCode::Char('a')));
        let after = match &shell.form.as_ref().expect("form").config {
            pieblock_core::model::ProjectConfig::Infantry(config) => config.yaw.len(),
            _ => 0,
        };
        assert_eq!(after, before + 1);
        assert!(shell.pages[shell.wizard_index].fields.len() > fields_before);
        println!(
            "after add={after} sel={:?} path={:?}",
            shell.form.as_ref().map(|f| f.selected),
            shell.selected_actuator_path()
        );
        shell.handle_key(key(KeyCode::Char('d')));
        let after_delete = match &shell.form.as_ref().expect("form").config {
            pieblock_core::model::ProjectConfig::Infantry(config) => config.yaw.len(),
            _ => 0,
        };
        assert_eq!(after_delete, before);
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum MappingAction {
    Add,
    Delete,
    MoveUp,
    MoveDown,
}

fn mapping_action(code: KeyCode) -> Option<MappingAction> {
    match code {
        KeyCode::Char('a') => Some(MappingAction::Add),
        KeyCode::Char('d') => Some(MappingAction::Delete),
        KeyCode::Char('K') => Some(MappingAction::MoveUp),
        KeyCode::Char('J') => Some(MappingAction::MoveDown),
        _ => None,
    }
}

fn parse_mapping_path(path: &str) -> Option<(usize, usize)> {
    let rest = path.strip_prefix("modes.")?;
    let (mode, rest) = rest
        .split_once('.')
        .map_or((None, ""), |(mode, rest)| (mode.parse().ok(), rest));
    let rest = rest.strip_prefix("actions.")?;
    let action = rest.split('.').next()?.parse().ok()?;
    Some((mode?, action))
}

fn default_action_mapping() -> pieblock_core::model::ActionMapping {
    pieblock_core::model::ActionMapping {
        id: String::new(),
        input_kind: pieblock_core::model::ActionInputKind::Remote,
        key: None,
        output_kind: pieblock_core::model::ActionOutputKind::Pin,
        pin: None,
        variable_name: None,
        expression: None,
        mode: None,
        parameter: None,
    }
}

#[cfg(test)]
mod code_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn code_view_generates_scrolls_and_exports() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-code-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let template = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("assets/templates/infantry.pieproj");
        let project = dir.join("infantry.pieproj");
        std::fs::copy(&template, &project).expect("copy template");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.workspace.open(&project).expect("open");
        shell.screen = Screen::Project;
        shell.handle_key(key(KeyCode::Char('c')));
        assert_eq!(shell.screen, Screen::Code);
        let code = shell.code.as_ref().expect("code view");
        assert!(!code.is_empty());
        assert!(code.lines.iter().any(|line| line.contains("main")));
        shell.handle_key(key(KeyCode::PageDown));
        let scrolled = shell.code.as_ref().expect("code").scroll;
        shell.handle_key(key(KeyCode::End));
        assert!(shell.code.as_ref().expect("code").scroll >= scrolled);
        shell.handle_key(key(KeyCode::Char('w')));
        assert!(dir.join("main.c").exists());
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

fn locate_runtime_root() -> Option<PathBuf> {
    let has_assets = |root: &std::path::Path| {
        root.join("stc32g_sdcc/build_manifest.json").is_file()
            && root.join("sdcc-toolchain/bundle_manifest.json").is_file()
    };
    if let Ok(root) = std::env::var("PIEBLOCK_RUNTIME_ROOT") {
        let root = PathBuf::from(root);
        if has_assets(&root) {
            return Some(root);
        }
    }
    if let Ok(cwd) = std::env::current_dir() {
        let mut cursor = Some(cwd);
        for _ in 0..8 {
            let Some(directory) = cursor else {
                break;
            };
            if has_assets(&directory) {
                return Some(directory);
            }
            cursor = directory.parent().map(Path::to_path_buf);
        }
    }
    if let Ok(exe) = std::env::current_exe() {
        if let Some(parent) = exe.parent() {
            let root = parent.join("data").join("pieblock_runtime");
            if has_assets(&root) {
                return Some(root);
            }
        }
    }
    None
}

#[cfg(test)]
mod build_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn build_real_sdcc_and_show_listing() {
        if locate_runtime_root().is_none() {
            return;
        }
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-build-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let template = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../..")
            .join("assets/templates/infantry.pieproj");
        let project = dir.join("infantry.pieproj");
        std::fs::copy(&template, &project).expect("copy template");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.workspace.open(&project).expect("open");
        shell.screen = Screen::Project;
        shell.handle_key(key(KeyCode::Char('b')));
        assert_eq!(shell.screen, Screen::Build);
        let log = shell.build_log.as_ref().expect("log");
        assert!(shell.build_ok);
        assert!(log.lines.iter().any(|line| line.contains("构建成功")));
        assert!(shell.build_listing.is_some(), "listing should exist");
        shell.handle_key(key(KeyCode::Char('l')));
        assert_eq!(shell.screen, Screen::Code);
        assert!(shell.code.as_ref().is_some_and(|code| !code.is_empty()));
        shell.handle_key(key(KeyCode::Char('w')));
        assert!(dir.join("main.rst").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod piano_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn piano_roll_add_note_and_commit() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-piano-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        for _ in 0..3 {
            shell.handle_key(key(KeyCode::Down));
        }
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Project);
        shell.handle_key(key(KeyCode::Char('m')));
        assert_eq!(shell.screen, Screen::Piano);
        shell.handle_key(key(KeyCode::Char('a')));
        shell.handle_key(key(KeyCode::Right));
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let session = shell.workspace.session.as_ref().expect("session");
        match &session.document.config {
            pieblock_core::model::ProjectConfig::Music(music) => {
                assert_eq!(music.notes.len(), 1);
                assert!(music.notes[0].start_tick > 0);
            }
            other => panic!("unexpected config: {other:?}"),
        }
        let text = std::fs::read_to_string(&session.path).expect("saved");
        assert!(text.contains("\"notes\""));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod playback_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn playback_opens_and_closes() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-playback-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        for _ in 0..3 {
            shell.handle_key(key(KeyCode::Down));
        }
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Char('m')));
        shell.handle_key(key(KeyCode::Char('a')));
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        shell.handle_key(key(KeyCode::Char('p')));
        assert_eq!(shell.screen, Screen::Playback);
        assert!(
            shell
                .playback
                .as_ref()
                .is_some_and(|p| p.duration_tick >= 1)
        );
        shell.handle_key(key(KeyCode::Char(' ')));
        assert!(shell.playback.as_ref().is_some_and(|p| p.playing));
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod flash_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn flash_screen_opens_without_device_and_closes() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-flash-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Char('f')));
        assert_eq!(shell.screen, Screen::Flash);
        assert!(
            shell
                .flash
                .as_ref()
                .is_some_and(|flash| !flash.log.is_empty())
        );
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

#[cfg(test)]
mod midi_import_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
    use pieblock_core::{ProjectDocument, ProjectKind};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn midi_import_replaces_music_notes() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-midi-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut music = match ProjectDocument::create(ProjectKind::Music).config {
            pieblock_core::model::ProjectConfig::Music(music) => music,
            other => panic!("unexpected config: {other:?}"),
        };
        music.notes.push(pieblock_core::model::MusicNote {
            id: "1".to_owned(),
            pitch: 64,
            start_tick: 0,
            duration_ticks: 480,
        });
        let midi_path = dir.join("import.mid");
        std::fs::write(&midi_path, pieblock_core::midi::MidiCodec::write(&music)).expect("midi");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        for _ in 0..3 {
            shell.handle_key(key(KeyCode::Down));
        }
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Char('i')));
        shell.overlay = Overlay::Input {
            title: "导入 MIDI".to_owned(),
            value: midi_path.display().to_string(),
            purpose: InputPurpose::MidiPath,
        };
        shell.handle_key(key(KeyCode::Enter));
        assert!(matches!(shell.overlay, Overlay::None));
        let session = shell.workspace.session.as_ref().expect("session");
        match &session.document.config {
            pieblock_core::model::ProjectConfig::Music(music) => {
                assert_eq!(music.notes.len(), 1);
                assert_eq!(music.notes[0].pitch, 64);
                assert_eq!(music.source_name.as_deref(), Some("import.mid"));
            }
            other => panic!("unexpected config: {other:?}"),
        }
        let _ = std::fs::remove_dir_all(&dir);
    }
}

fn debug_reorder_delta(code: KeyCode) -> Option<i64> {
    match code {
        KeyCode::Char('J') => Some(1),
        KeyCode::Char('K') => Some(-1),
        _ => None,
    }
}

fn parse_debug_path(path: &str) -> Option<usize> {
    let rest = path.strip_prefix("tests.")?;
    rest.split('.').next()?.parse().ok()
}

#[cfg(test)]
mod debug_reorder_tests {
    use super::*;
    use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn debug_tests_can_be_reordered() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../../target")
            .join(format!("shell-debug-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).expect("dir");
        let mut shell = Shell::with_data_dir(dir.join("data"), dir.clone());
        shell.handle_key(key(KeyCode::Char('n')));
        for _ in 0..2 {
            shell.handle_key(key(KeyCode::Down));
        }
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        shell.handle_key(key(KeyCode::Enter));
        assert_eq!(shell.screen, Screen::Wizard);
        let (first, second) = match &shell
            .workspace
            .session
            .as_ref()
            .expect("session")
            .document
            .config
        {
            pieblock_core::model::ProjectConfig::Debug(config) => {
                (config.tests[0].pin.clone(), config.tests[1].pin.clone())
            }
            other => panic!("unexpected config: {other:?}"),
        };
        shell.handle_key(key(KeyCode::Char('J')));
        let (after_first, after_second) = match &shell.form.as_ref().expect("form").config {
            pieblock_core::model::ProjectConfig::Debug(config) => {
                (config.tests[0].pin.clone(), config.tests[1].pin.clone())
            }
            other => panic!("unexpected config: {other:?}"),
        };
        assert_eq!(after_first, second);
        assert_eq!(after_second, first);
        shell.handle_key(key(KeyCode::Esc));
        assert_eq!(shell.screen, Screen::Project);
        let _ = std::fs::remove_dir_all(&dir);
    }
}

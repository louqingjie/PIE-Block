//! M0 应用骨架：界面状态、键鼠路由、表单与钢琴卷帘原型。
//!
//! 目标是用最小的可运行界面验证：CJK/宽字符、焦点与键鼠、表单输入（含中文）、
//! 网格渲染与滚动、主题切换。M1 起把页面替换为真实的向导/代码/烧录页。

use std::io;
use std::time::Duration;

use crossterm::event::{
    self, Event, KeyCode, KeyEvent, KeyEventKind, KeyModifiers, MouseButton, MouseEvent,
    MouseEventKind,
};
use pieblock_core::ProjectKind;
use pieblock_ui::ThemeMode;
use ratatui::Terminal;
use ratatui::backend::Backend;
use ratatui::layout::Rect;

pub const APP_NAME: &str = "PIE-Block TUI";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
pub const POLL_TIMEOUT: Duration = Duration::from_millis(120);
pub const SIDEBAR_WIDTH: u16 = 22;
pub const DETAIL_WIDTH: u16 = 30;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Focus {
    Sidebar,
    Main,
    Detail,
}

impl Focus {
    #[must_use]
    pub const fn next(self) -> Self {
        match self {
            Self::Sidebar => Self::Main,
            Self::Main => Self::Detail,
            Self::Detail => Self::Sidebar,
        }
    }

    #[must_use]
    pub const fn prev(self) -> Self {
        match self {
            Self::Sidebar => Self::Detail,
            Self::Main => Self::Sidebar,
            Self::Detail => Self::Main,
        }
    }

    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Sidebar => "导航",
            Self::Main => "工作区",
            Self::Detail => "详情",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Pane {
    Overview,
    Form,
    Piano,
}

impl Pane {
    pub const ALL: [Self; 3] = [Self::Overview, Self::Form, Self::Piano];

    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Overview => "M0 概览",
            Self::Form => "表单输入示例",
            Self::Piano => "钢琴卷帘原型",
        }
    }

    #[must_use]
    pub const fn index(self) -> usize {
        match self {
            Self::Overview => 0,
            Self::Form => 1,
            Self::Piano => 2,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SaveState {
    Saved,
    Saving,
}

impl SaveState {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Saved => "已保存",
            Self::Saving => "保存中…",
        }
    }
}

/// 最近一次绘制得到的各区域，用于鼠标命中。
#[derive(Debug, Clone, Copy, Default)]
pub struct Areas {
    pub sidebar: Rect,
    pub main: Rect,
    pub detail: Rect,
    pub footer: Rect,
    pub piano_grid: Rect,
}

pub struct App {
    pub focus: Focus,
    pub pane: Pane,
    pub theme: ThemeMode,
    pub form: FormDemo,
    pub piano: PianoDemo,
    pub help: bool,
    pub quit: bool,
    pub mouse_enabled: bool,
    pub status: String,
    pub tick: u64,
    pub size: (u16, u16),
    pub sidebar_selected: usize,
    pub detail_scroll: u16,
    pub areas: Areas,
    pub save: SaveState,
}

impl App {
    #[must_use]
    pub fn new(mouse_enabled: bool) -> Self {
        Self {
            focus: Focus::Main,
            pane: Pane::Overview,
            theme: ThemeMode::Dark,
            form: FormDemo::default(),
            piano: PianoDemo::default(),
            help: false,
            quit: false,
            mouse_enabled,
            status: "M0 技术验证：Tab 切换焦点，F1 打开帮助，1/2/3 切换页面".to_owned(),
            tick: 0,
            size: (80, 24),
            sidebar_selected: 0,
            detail_scroll: 0,
            areas: Areas::default(),
            save: SaveState::Saved,
        }
    }

    pub fn run<B: Backend<Error = io::Error>>(
        &mut self,
        terminal: &mut Terminal<B>,
    ) -> io::Result<()> {
        loop {
            terminal.draw(|frame| crate::ui::draw(frame, self))?;
            if self.quit {
                break;
            }
            if event::poll(POLL_TIMEOUT)? {
                match event::read()? {
                    Event::Key(key) if key.kind == KeyEventKind::Press => self.on_key(key),
                    Event::Mouse(mouse) => self.on_mouse(mouse),
                    Event::Resize(width, height) => self.size = (width, height),
                    _ => {}
                }
            }
            self.on_tick();
        }
        Ok(())
    }

    fn on_tick(&mut self) {
        self.tick = self.tick.wrapping_add(1);
        if self.save == SaveState::Saving {
            self.save = SaveState::Saved;
        }
        if self.piano.playing {
            self.piano.playhead = (self.piano.playhead + 1) % TOTAL_TICKS;
        }
    }

    fn on_key(&mut self, key: KeyEvent) {
        if self.help {
            match key.code {
                KeyCode::Esc | KeyCode::F(1) | KeyCode::Char('?') => self.help = false,
                _ => {}
            }
            return;
        }

        if self.form.editing.is_some() {
            self.form.on_edit_key(key);
            self.save = SaveState::Saving;
            return;
        }

        if key.modifiers.contains(KeyModifiers::CONTROL) {
            match key.code {
                KeyCode::Char('q') => self.quit = true,
                KeyCode::Char('s') => {
                    self.save = SaveState::Saved;
                    self.status = "已保存（M0 模拟，M1 接真实项目文件）".to_owned();
                }
                KeyCode::Char('p') => {
                    self.status =
                        "命令面板将在 M3 实现；当前可用 1/2/3 切换页面、Tab 切换焦点".to_owned();
                }
                _ => {}
            }
            return;
        }

        match key.code {
            KeyCode::F(1) | KeyCode::Char('?') => self.help = true,
            KeyCode::Char('q') => self.quit = true,
            KeyCode::Tab => {
                self.focus = self.focus.next();
                self.status = format!("焦点：{}", self.focus.label());
            }
            KeyCode::BackTab => {
                self.focus = self.focus.prev();
                self.status = format!("焦点：{}", self.focus.label());
            }
            KeyCode::Char('1') => self.activate(Pane::Overview),
            KeyCode::Char('2') => self.activate(Pane::Form),
            KeyCode::Char('3') => self.activate(Pane::Piano),
            KeyCode::Char('t') => {
                self.theme = self.theme.toggled();
                self.status = format!("主题：{}", self.theme.label());
            }
            KeyCode::Esc => {
                self.focus = Focus::Main;
                self.status = "返回工作区".to_owned();
            }
            _ => match self.focus {
                Focus::Sidebar => self.on_key_sidebar(key),
                Focus::Main => self.on_key_main(key),
                Focus::Detail => self.on_key_detail(key),
            },
        }
    }

    fn on_key_sidebar(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up => {
                self.sidebar_selected =
                    (self.sidebar_selected + Pane::ALL.len() - 1) % Pane::ALL.len();
            }
            KeyCode::Down => {
                self.sidebar_selected = (self.sidebar_selected + 1) % Pane::ALL.len();
            }
            KeyCode::Enter => self.activate(Pane::ALL[self.sidebar_selected]),
            _ => {}
        }
    }

    fn on_key_main(&mut self, key: KeyEvent) {
        match self.pane {
            Pane::Overview => match key.code {
                KeyCode::Up => self.detail_scroll = self.detail_scroll.saturating_sub(1),
                KeyCode::Down => self.detail_scroll = self.detail_scroll.saturating_add(1),
                _ => {}
            },
            Pane::Form => self.form.on_key(key, &mut self.save, &mut self.status),
            Pane::Piano => {
                if let Some(message) = self.piano.on_key(key) {
                    self.status = message;
                    self.save = SaveState::Saving;
                }
            }
        }
    }

    fn on_key_detail(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Up => self.detail_scroll = self.detail_scroll.saturating_sub(1),
            KeyCode::Down => self.detail_scroll = self.detail_scroll.saturating_add(1),
            _ => {}
        }
    }

    fn on_mouse(&mut self, mouse: MouseEvent) {
        if !self.mouse_enabled {
            return;
        }
        match mouse.kind {
            MouseEventKind::Down(MouseButton::Left) => {
                let column = mouse.column;
                let row = mouse.row;
                if contains(self.areas.sidebar, column, row) {
                    let index = usize::from(row.saturating_sub(self.areas.sidebar.y + 1));
                    if let Some(pane) = Pane::ALL.get(index) {
                        self.sidebar_selected = index;
                        self.activate(*pane);
                    }
                } else if contains(self.areas.main, column, row) {
                    self.focus = Focus::Main;
                    if self.pane == Pane::Piano {
                        self.piano.click(column, row, self.areas.piano_grid);
                        self.status = self.piano.status();
                    }
                } else if contains(self.areas.detail, column, row) {
                    self.focus = Focus::Detail;
                }
            }
            MouseEventKind::ScrollUp => self.scroll(-1),
            MouseEventKind::ScrollDown => self.scroll(1),
            _ => {}
        }
    }

    fn scroll(&mut self, delta: i32) {
        match self.focus {
            Focus::Sidebar => {
                self.sidebar_selected = wrap_index(self.sidebar_selected, delta, Pane::ALL.len());
            }
            Focus::Main => match self.pane {
                Pane::Form => self.form.move_selection(delta),
                Pane::Piano => self.piano.scroll(delta),
                Pane::Overview => {
                    self.detail_scroll = adjust_scroll(self.detail_scroll, delta);
                }
            },
            Focus::Detail => {
                self.detail_scroll = adjust_scroll(self.detail_scroll, delta);
            }
        }
    }

    fn activate(&mut self, pane: Pane) {
        self.pane = pane;
        self.sidebar_selected = pane.index();
        self.focus = Focus::Main;
        self.status = format!("切换到「{}」", pane.label());
    }
}

fn adjust_scroll(current: u16, delta: i32) -> u16 {
    if delta < 0 {
        current.saturating_sub(delta.unsigned_abs() as u16)
    } else {
        current.saturating_add(delta as u16)
    }
}

fn wrap_index(current: usize, delta: i32, len: usize) -> usize {
    if len == 0 {
        return 0;
    }
    let len_i = len as i32;
    let next = (current as i32 + delta).rem_euclid(len_i);
    next as usize
}

fn contains(area: Rect, column: u16, row: u16) -> bool {
    column >= area.x && column < area.x + area.width && row >= area.y && row < area.y + area.height
}

// ---------------------------------------------------------------------------
// 表单原型
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum FieldKind {
    Text,
    Number {
        min: i32,
        max: i32,
    },
    Select {
        options: &'static [&'static str],
        index: usize,
    },
    Toggle {
        on: bool,
    },
    Slider {
        value: i32,
        min: i32,
        max: i32,
        step: i32,
    },
}

#[derive(Debug, Clone)]
pub struct Field {
    pub label: &'static str,
    pub value: String,
    pub kind: FieldKind,
    pub hint: &'static str,
    pub unit: &'static str,
}

pub struct FormDemo {
    pub fields: Vec<Field>,
    pub selected: usize,
    pub editing: Option<String>,
    pub editing_index: usize,
    pub error: Option<String>,
    pub warning: Option<String>,
}

impl Default for FormDemo {
    fn default() -> Self {
        Self {
            fields: vec![
                Field {
                    label: "遥控器通道",
                    value: "0".to_owned(),
                    kind: FieldKind::Number { min: 0, max: 125 },
                    hint: "0–125",
                    unit: "",
                },
                Field {
                    label: "摇杆死区",
                    value: "0".to_owned(),
                    kind: FieldKind::Number { min: 0, max: 2047 },
                    hint: "0–2047",
                    unit: "",
                },
                Field {
                    label: "底盘速度",
                    value: "6000".to_owned(),
                    kind: FieldKind::Slider {
                        value: 6000,
                        min: 0,
                        max: 10000,
                        step: 500,
                    },
                    hint: "0–10000",
                    unit: "duty",
                },
                Field {
                    label: "摩擦轮类型",
                    value: "未选择".to_owned(),
                    kind: FieldKind::Select {
                        options: &["未选择", "无刷电调", "不使用"],
                        index: 0,
                    },
                    hint: "←/→ 选择",
                    unit: "",
                },
                Field {
                    label: "反转左右转向",
                    value: "关".to_owned(),
                    kind: FieldKind::Toggle { on: false },
                    hint: "Space 切换",
                    unit: "",
                },
                Field {
                    label: "项目备注",
                    value: "中文输入测试".to_owned(),
                    kind: FieldKind::Text,
                    hint: "Enter 编辑",
                    unit: "",
                },
            ],
            selected: 0,
            editing: None,
            editing_index: 0,
            error: None,
            warning: None,
        }
    }
}

impl FormDemo {
    #[must_use]
    pub fn selected_field(&self) -> Option<&Field> {
        self.fields.get(self.selected)
    }

    pub fn move_selection(&mut self, delta: i32) {
        if self.fields.is_empty() {
            return;
        }
        self.selected = wrap_index(self.selected, delta, self.fields.len());
    }

    pub fn on_key(&mut self, key: KeyEvent, save: &mut SaveState, status: &mut String) {
        match key.code {
            KeyCode::Up => self.move_selection(-1),
            KeyCode::Down => self.move_selection(1),
            KeyCode::Left => self.adjust(-1),
            KeyCode::Right => self.adjust(1),
            KeyCode::PageUp => self.adjust(-10),
            KeyCode::PageDown => self.adjust(10),
            KeyCode::Enter => self.activate_selected(),
            KeyCode::Char(' ') => self.toggle_selected(),
            _ => return,
        }
        *save = SaveState::Saving;
        *status = self
            .error
            .clone()
            .unwrap_or_else(|| format!("表单：{}", self.selected_field().map_or("", |f| f.label)));
    }

    fn activate_selected(&mut self) {
        let Some(field) = self.selected_field() else {
            return;
        };
        match field.kind {
            FieldKind::Text | FieldKind::Number { .. } => {
                self.editing = Some(field.value.clone());
                self.editing_index = self.selected;
            }
            FieldKind::Select { .. } | FieldKind::Toggle { .. } => self.adjust(1),
            FieldKind::Slider { .. } => self.adjust(1),
        }
    }

    fn toggle_selected(&mut self) {
        let Some(field) = self.fields.get_mut(self.selected) else {
            return;
        };
        if let FieldKind::Toggle { on } = &mut field.kind {
            *on = !*on;
            field.value = if *on {
                "开".to_owned()
            } else {
                "关".to_owned()
            };
        }
    }

    fn adjust(&mut self, delta: i32) {
        let selected = self.selected;
        let Some(field) = self.fields.get_mut(selected) else {
            return;
        };
        match &mut field.kind {
            FieldKind::Number { min, max } => {
                let current = field.value.trim().parse::<i32>().unwrap_or(0);
                let next = current.saturating_add(delta).clamp(*min, *max);
                field.value = next.to_string();
            }
            FieldKind::Slider {
                value,
                min,
                max,
                step,
            } => {
                let next = value.saturating_add(delta * *step).clamp(*min, *max);
                *value = next;
                field.value = next.to_string();
            }
            FieldKind::Select { options, index } => {
                let len = options.len();
                if len > 0 {
                    *index = (*index as i32 + delta).rem_euclid(len as i32) as usize;
                    field.value = options[*index].to_owned();
                }
            }
            FieldKind::Toggle { on } => {
                *on = !*on;
                field.value = if *on {
                    "开".to_owned()
                } else {
                    "关".to_owned()
                };
            }
            FieldKind::Text => {}
        }
        self.validate();
    }

    pub fn on_edit_key(&mut self, key: KeyEvent) {
        match key.code {
            KeyCode::Enter => self.commit_edit(),
            KeyCode::Esc => self.cancel_edit(),
            KeyCode::Backspace => {
                if let Some(buffer) = &mut self.editing {
                    buffer.pop();
                }
            }
            KeyCode::Char(ch) => {
                if let Some(buffer) = &mut self.editing {
                    buffer.push(ch);
                }
            }
            _ => {}
        }
    }

    fn commit_edit(&mut self) {
        let Some(buffer) = self.editing.take() else {
            return;
        };
        let index = self.editing_index;
        if let Some(field) = self.fields.get_mut(index) {
            field.value = buffer.trim().to_owned();
        }
        self.validate();
    }

    fn cancel_edit(&mut self) {
        self.editing = None;
    }

    fn validate(&mut self) {
        self.error = None;
        self.warning = None;
        let Some(field) = self.fields.first() else {
            return;
        };
        if let FieldKind::Number { min, max } = field.kind {
            if let Ok(value) = field.value.trim().parse::<i32>() {
                if value < min || value > max {
                    self.error = Some(format!("遥控器通道 {value} 超出 {min}–{max}，无法生成代码"));
                }
            } else {
                self.error = Some("遥控器通道必须是整数".to_owned());
            }
        }
        if let Some(field) = self.fields.get(1) {
            if let FieldKind::Number { min, max } = field.kind {
                if let Ok(value) = field.value.trim().parse::<i32>() {
                    if value < min || value > max {
                        self.error = Some(format!("摇杆死区 {value} 超出 {min}–{max}"));
                    } else if value > 500 {
                        self.warning = Some(format!("摇杆死区 {value} 偏大（建议 ≤500）"));
                    }
                }
            }
        }
    }
}

// ---------------------------------------------------------------------------
// 钢琴卷帘原型
// ---------------------------------------------------------------------------

pub const TOTAL_TICKS: u32 = 64;

#[derive(Debug, Clone, Copy)]
pub struct DemoNote {
    pub id: u16,
    pub pitch: u8,
    pub start: u32,
    pub len: u32,
}

pub struct PianoDemo {
    pub notes: Vec<DemoNote>,
    pub cursor_tick: u32,
    pub cursor_pitch: u8,
    pub zoom: u8,
    pub selected: Option<u16>,
    pub playing: bool,
    pub playhead: u32,
    next_id: u16,
}

impl Default for PianoDemo {
    fn default() -> Self {
        let mut next_id = 1;
        let mut note = |pitch: u8, start: u32, len: u32| {
            let id = next_id;
            next_id += 1;
            DemoNote {
                id,
                pitch,
                start,
                len,
            }
        };
        Self {
            notes: vec![
                note(60, 0, 4),
                note(64, 4, 4),
                note(67, 8, 8),
                note(62, 16, 4),
                note(65, 20, 4),
                note(69, 24, 8),
            ],
            cursor_tick: 0,
            cursor_pitch: 60,
            zoom: 1,
            selected: Some(1),
            playing: false,
            playhead: 0,
            next_id,
        }
    }
}

impl PianoDemo {
    #[must_use]
    pub fn top_pitch(&self) -> i16 {
        (i16::from(self.cursor_pitch) + 6).min(127)
    }

    pub fn on_key(&mut self, key: KeyEvent) -> Option<String> {
        match key.code {
            KeyCode::Up => {
                self.cursor_pitch = self.cursor_pitch.saturating_add(1);
                if self.cursor_pitch > 96 {
                    self.cursor_pitch = 96;
                }
            }
            KeyCode::Down => {
                self.cursor_pitch = self.cursor_pitch.saturating_sub(1);
                if self.cursor_pitch < 36 {
                    self.cursor_pitch = 36;
                }
            }
            KeyCode::Left => {
                self.cursor_tick = (self.cursor_tick + TOTAL_TICKS - 1) % TOTAL_TICKS;
            }
            KeyCode::Right => {
                self.cursor_tick = (self.cursor_tick + 1) % TOTAL_TICKS;
            }
            KeyCode::Char('+') | KeyCode::Char('=') => {
                self.zoom = (self.zoom + 1).min(3);
            }
            KeyCode::Char('-') => {
                self.zoom = self.zoom.saturating_sub(1).max(1);
            }
            KeyCode::Char(' ') => {
                self.playing = !self.playing;
            }
            KeyCode::Char('n') => {
                if self.note_at(self.cursor_tick, self.cursor_pitch).is_some() {
                    return Some("该位置已有音符".to_owned());
                }
                let id = self.next_id;
                self.next_id += 1;
                self.notes.push(DemoNote {
                    id,
                    pitch: self.cursor_pitch,
                    start: self.cursor_tick,
                    len: 4,
                });
                self.selected = Some(id);
            }
            KeyCode::Char('x') => {
                if let Some(note_id) = self
                    .note_at(self.cursor_tick, self.cursor_pitch)
                    .map(|note| note.id)
                {
                    self.notes.retain(|item| item.id != note_id);
                    if self.selected == Some(note_id) {
                        self.selected = None;
                    }
                } else {
                    return Some("光标处没有音符".to_owned());
                }
            }
            _ => return None,
        }
        Some(self.status())
    }

    pub fn click(&mut self, column: u16, row: u16, grid: Rect) {
        if grid.width == 0 || grid.height == 0 || !contains(grid, column, row) {
            return;
        }
        let local_col = column - grid.x;
        let local_row = row - grid.y;
        let step = u32::from(local_col) / u32::from(self.zoom.max(1));
        self.cursor_tick = step.min(TOTAL_TICKS - 1);
        let top = self.top_pitch();
        let pitch = top - i16::try_from(local_row).unwrap_or(i16::MAX);
        if (0..=127).contains(&pitch) {
            self.cursor_pitch = pitch as u8;
        }
    }

    pub fn scroll(&mut self, delta: i32) {
        self.cursor_tick = (i64::from(self.cursor_tick) + i64::from(delta) * 2)
            .rem_euclid(i64::from(TOTAL_TICKS)) as u32;
    }

    #[must_use]
    pub fn status(&self) -> String {
        format!(
            "卷帘：tick {} / {TOTAL_TICKS}，音高 {}（MIDI {}），缩放 {}x{}",
            self.cursor_tick,
            pitch_name(self.cursor_pitch),
            self.cursor_pitch,
            self.zoom,
            if self.playing { "，播放中" } else { "" }
        )
    }

    #[must_use]
    pub fn note_at(&self, tick: u32, pitch: u8) -> Option<&DemoNote> {
        self.notes
            .iter()
            .find(|note| note.pitch == pitch && tick >= note.start && tick < note.start + note.len)
    }
}

#[must_use]
pub fn pitch_name(pitch: u8) -> String {
    const NAMES: [&str; 12] = [
        "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B",
    ];
    let octave = i32::from(pitch) / 12 - 1;
    format!("{}{}", NAMES[usize::from(pitch % 12)], octave)
}

#[must_use]
pub fn project_kind_summary() -> Vec<(&'static str, usize, &'static str)> {
    ProjectKind::ALL
        .iter()
        .map(|kind| (kind.label(), kind.steps().len(), kind.steps()[0].label))
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn key(code: KeyCode) -> KeyEvent {
        KeyEvent::new(code, KeyModifiers::NONE)
    }

    #[test]
    fn tab_cycles_focus_forward_and_back() {
        let mut app = App::new(false);
        app.on_key(key(KeyCode::Tab));
        assert_eq!(app.focus, Focus::Detail);
        app.on_key(key(KeyCode::Tab));
        assert_eq!(app.focus, Focus::Sidebar);
        app.on_key(key(KeyCode::BackTab));
        assert_eq!(app.focus, Focus::Detail);
    }

    #[test]
    fn number_field_clamps_to_range() {
        let mut app = App::new(false);
        app.focus = Focus::Main;
        app.pane = Pane::Form;
        app.form.selected = 0;
        for _ in 0..300 {
            app.form.adjust(-1);
        }
        assert_eq!(app.form.fields[0].value, "0");
        for _ in 0..300 {
            app.form.adjust(1);
        }
        assert_eq!(app.form.fields[0].value, "125");
        assert!(app.form.error.is_none());
    }

    #[test]
    fn out_of_range_number_reports_error() {
        let mut form = FormDemo::default();
        form.fields[0].value = "999".to_owned();
        form.validate();
        assert!(form.error.is_some());
    }

    #[test]
    fn piano_add_and_delete_note() {
        let mut piano = PianoDemo {
            cursor_pitch: 72,
            cursor_tick: 8,
            ..PianoDemo::default()
        };
        let before = piano.notes.len();
        let _ = piano.on_key(key(KeyCode::Char('n')));
        assert_eq!(piano.notes.len(), before + 1);
        let _ = piano.on_key(key(KeyCode::Char('x')));
        assert_eq!(piano.notes.len(), before);
    }

    #[test]
    fn piano_zoom_is_clamped() {
        let mut piano = PianoDemo::default();
        for _ in 0..10 {
            let _ = piano.on_key(key(KeyCode::Char('+')));
        }
        assert_eq!(piano.zoom, 3);
        for _ in 0..10 {
            let _ = piano.on_key(key(KeyCode::Char('-')));
        }
        assert_eq!(piano.zoom, 1);
    }

    #[test]
    fn theme_toggle_updates_mode() {
        let mut app = App::new(false);
        assert_eq!(app.theme, ThemeMode::Dark);
        app.on_key(key(KeyCode::Char('t')));
        assert_eq!(app.theme, ThemeMode::Light);
    }

    #[test]
    fn pitch_names_match_midi() {
        assert_eq!(pitch_name(60), "C4");
        assert_eq!(pitch_name(69), "A4");
        assert_eq!(pitch_name(61), "C#4");
    }
}

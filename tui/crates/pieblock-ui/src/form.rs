//! 数据驱动表单引擎：字段定义、键鼠编辑、校验与渲染。
//!
//! M4 向导页把 Flutter 的 `_NumberField`/`_Dropdown`/`SwitchListTile`/文本框
//! 等控件声明成 [`FormField`] 列表；引擎负责焦点、编辑、范围校验与写回
//! `ProjectConfig`。页面按导航键切换由调用方处理，这里只产出 [`FormAction`]。

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_core::model::ProjectConfig;
use ratatui::Frame;
use ratatui::layout::{Constraint, Direction, Layout, Rect};
use ratatui::style::Modifier;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Borders, List, ListItem, ListState, Paragraph};

use crate::theme::Palette;

/// 字段取值。
#[derive(Debug, Clone, PartialEq)]
pub enum FieldValue {
    Int(i64),
    Float(f64),
    Bool(bool),
    Text(String),
    /// 下拉选项的稳定值（空字符串表示未设置）。
    Choice(String),
}

impl FieldValue {
    #[must_use]
    pub fn display(&self) -> String {
        match self {
            Self::Int(value) => value.to_string(),
            Self::Float(value) => format!("{value}"),
            Self::Bool(value) => (if *value { "开启" } else { "关闭" }).to_owned(),
            Self::Text(value) | Self::Choice(value) => value.clone(),
        }
    }
}

/// 下拉选项。
#[derive(Debug, Clone, Copy)]
pub struct Choice {
    pub value: &'static str,
    pub label: &'static str,
}

/// 字段控件类型。
#[derive(Debug, Clone, Copy)]
pub enum FieldKind {
    Number {
        min: i64,
        max: i64,
        step: i64,
        unit: &'static str,
    },
    Decimal {
        min: f64,
        max: f64,
        step: f64,
    },
    Text {
        max_len: usize,
        placeholder: &'static str,
    },
    Choice(&'static [Choice]),
    Toggle,
}

/// 字段取值闭包。
pub type FieldGetter = Box<dyn Fn(&ProjectConfig) -> FieldValue>;
/// 字段写回闭包。
pub type FieldSetter = Box<dyn Fn(&mut ProjectConfig, FieldValue)>;

/// 一个表单字段。
pub struct FormField {
    pub id: &'static str,
    /// 校验错误里的字段路径（与 `ValidationIssue::field_path` 一致）。
    pub path: &'static str,
    pub label: String,
    pub help: &'static str,
    pub kind: FieldKind,
    pub get: FieldGetter,
    pub set: FieldSetter,
}

/// 一个向导页。
pub struct FormPage {
    pub id: &'static str,
    pub title: &'static str,
    pub subtitle: &'static str,
    pub fields: Vec<FormField>,
}

/// 表单动作。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum FormAction {
    None,
    Changed,
    PrevPage,
    NextPage,
}

/// 表单状态。
pub struct FormState {
    pub config: ProjectConfig,
    pub selected: usize,
    /// 正在编辑的文本缓冲；`Some` 时字符输入写入这里。
    pub editing: Option<String>,
    pub message: Option<String>,
    pub dirty: bool,
}

impl FormState {
    #[must_use]
    pub fn new(config: ProjectConfig) -> Self {
        Self {
            config,
            selected: 0,
            editing: None,
            message: None,
            dirty: false,
        }
    }

    #[must_use]
    pub fn value(&self, field: &FormField) -> FieldValue {
        (field.get)(&self.config)
    }

    fn set_value(&mut self, field: &FormField, value: FieldValue) {
        (field.set)(&mut self.config, value);
        self.dirty = true;
    }

    /// 处理按键；`page` 决定字段列表与范围。
    pub fn handle_key(&mut self, page: &FormPage, key: KeyEvent) -> FormAction {
        if let Some(buffer) = self.editing.clone() {
            return match key.code {
                KeyCode::Esc => {
                    self.editing = None;
                    self.message = None;
                    FormAction::None
                }
                KeyCode::Enter => self.commit_editing(page),
                KeyCode::Backspace => {
                    let mut next = buffer;
                    next.pop();
                    self.editing = Some(next);
                    FormAction::None
                }
                KeyCode::Char(character) if !key.modifiers.contains(KeyModifiers::CONTROL) => {
                    let mut next = buffer;
                    next.push(character);
                    self.editing = Some(next);
                    FormAction::None
                }
                _ => FormAction::None,
            };
        }
        match key.code {
            KeyCode::Up => {
                self.selected = self.selected.saturating_sub(1);
                FormAction::None
            }
            KeyCode::Down => {
                self.selected = (self.selected + 1).min(page.fields.len().saturating_sub(1));
                FormAction::None
            }
            KeyCode::Tab => self.move_focus(page, 1),
            KeyCode::BackTab => self.move_focus(page, -1),
            KeyCode::Left => self.adjust(page, -1),
            KeyCode::Right => self.adjust(page, 1),
            KeyCode::Enter => {
                let Some(field) = page.fields.get(self.selected) else {
                    return FormAction::None;
                };
                match field.kind {
                    FieldKind::Toggle | FieldKind::Choice(_) => self.adjust(page, 1),
                    FieldKind::Number { .. }
                    | FieldKind::Decimal { .. }
                    | FieldKind::Text { .. } => {
                        self.editing = Some(self.value(field).display());
                        FormAction::None
                    }
                }
            }
            KeyCode::Esc => {
                self.selected = 0;
                FormAction::PrevPage
            }
            KeyCode::PageUp => FormAction::PrevPage,
            KeyCode::PageDown => {
                // 最后一页由调用方判断；这里统一交给调用方。
                let _ = page;
                FormAction::NextPage
            }
            _ => FormAction::None,
        }
    }

    fn move_focus(&mut self, page: &FormPage, delta: i32) -> FormAction {
        let length = page.fields.len();
        if length == 0 {
            return FormAction::None;
        }
        let current = i64::try_from(self.selected).unwrap_or(0);
        let next = (current + i64::from(delta)).rem_euclid(i64::try_from(length).unwrap_or(1));
        self.selected = usize::try_from(next).unwrap_or(0);
        FormAction::None
    }

    /// 提交当前编辑缓冲（Enter 后由调用方调用，避免引擎与页面解耦问题）。
    pub fn commit_editing(&mut self, page: &FormPage) -> FormAction {
        let Some(buffer) = self.editing.clone() else {
            return FormAction::None;
        };
        let Some(field) = page.fields.get(self.selected) else {
            self.editing = None;
            return FormAction::None;
        };
        let parsed = match field.kind {
            FieldKind::Number { min, max, .. } => match buffer.trim().parse::<i64>() {
                Ok(value) if value >= min && value <= max => FieldValue::Int(value),
                Ok(value) => {
                    self.message = Some(format!("超出范围：{}（{}–{}）", value, min, max));
                    return FormAction::None;
                }
                Err(_) => {
                    self.message = Some("请输入整数".to_owned());
                    return FormAction::None;
                }
            },
            FieldKind::Decimal { min, max, .. } => match buffer.trim().parse::<f64>() {
                Ok(value) if value >= min && value <= max => FieldValue::Float(value),
                Ok(value) => {
                    self.message = Some(format!("超出范围：{value}（{min}–{max}）"));
                    return FormAction::None;
                }
                Err(_) => {
                    self.message = Some("请输入数字".to_owned());
                    return FormAction::None;
                }
            },
            FieldKind::Text { max_len, .. } => {
                if buffer.chars().count() > max_len {
                    self.message = Some(format!("最多 {max_len} 个字符"));
                    return FormAction::None;
                }
                FieldValue::Text(buffer)
            }
            FieldKind::Choice(_) | FieldKind::Toggle => {
                self.editing = None;
                return FormAction::None;
            }
        };
        self.set_value(field, parsed);
        self.editing = None;
        self.message = None;
        FormAction::Changed
    }

    fn adjust(&mut self, page: &FormPage, direction: i64) -> FormAction {
        let Some(field) = page.fields.get(self.selected) else {
            return FormAction::None;
        };
        let value = self.value(field);
        let next = match (field.kind, value) {
            (FieldKind::Number { min, max, step, .. }, FieldValue::Int(current)) => {
                FieldValue::Int((current + direction * step).clamp(min, max))
            }
            (FieldKind::Decimal { min, max, step }, FieldValue::Float(current)) => {
                FieldValue::Float((current + step * direction as f64).clamp(min, max))
            }
            (FieldKind::Toggle, FieldValue::Bool(current)) => FieldValue::Bool(!current),
            (FieldKind::Choice(options), FieldValue::Choice(current)) => {
                let index = options
                    .iter()
                    .position(|option| option.value == current)
                    .unwrap_or(0);
                let length = i64::try_from(options.len()).unwrap_or(1);
                let next = (i64::try_from(index).unwrap_or(0) + direction).rem_euclid(length);
                FieldValue::Choice(options[usize::try_from(next).unwrap_or(0)].value.to_owned())
            }
            _ => return FormAction::None,
        };
        if next == self.value(field) {
            return FormAction::None;
        }
        self.set_value(field, next);
        self.message = None;
        FormAction::Changed
    }

    /// 渲染页面。
    pub fn render(&mut self, frame: &mut Frame, area: Rect, page: &FormPage, palette: &Palette) {
        let chunks = Layout::default()
            .direction(Direction::Vertical)
            .constraints([
                Constraint::Length(3),
                Constraint::Min(4),
                Constraint::Length(2),
            ])
            .split(area);
        let header = Paragraph::new(vec![
            Line::from(Span::styled(page.title.to_owned(), palette.title())),
            Line::from(Span::styled(page.subtitle.to_owned(), palette.muted())),
        ])
        .block(block("PIE-Block 向导", palette));
        frame.render_widget(header, chunks[0]);

        let items: Vec<ListItem> = page
            .fields
            .iter()
            .enumerate()
            .map(|(index, field)| {
                let value = self.value(field);
                let display = if index == self.selected {
                    if let Some(buffer) = &self.editing {
                        format!("{buffer}_")
                    } else {
                        format_field(field, &value)
                    }
                } else {
                    format_field(field, &value)
                };
                ListItem::new(Line::from(vec![
                    Span::styled(format!("{:<12}", field.label), palette.muted()),
                    Span::styled(display, palette.text()),
                ]))
            })
            .collect();
        let list = List::new(items)
            .block(block(
                &format!("{}（{} 项）", page.id, page.fields.len()),
                palette,
            ))
            .highlight_style(palette.selection())
            .highlight_symbol("▶ ");
        let mut state = ListState::default();
        state.select(Some(self.selected.min(page.fields.len().saturating_sub(1))));
        frame.render_stateful_widget(list, chunks[1], &mut state);

        let field_help = page
            .fields
            .get(self.selected)
            .map_or("", |field| field.help);
        let mut lines = vec![Line::from(vec![
            Span::styled("提示：", palette.muted()),
            Span::styled(field_help.to_owned(), palette.muted()),
        ])];
        if let Some(message) = &self.message {
            lines.push(Line::from(Span::styled(message.clone(), palette.warn())));
        }
        lines.push(Line::from(Span::styled(
            "↑↓ 选择  Tab 切换  Enter 编辑/切换  PgUp/PgDn 翻页  Esc 保存返回",
            palette.muted(),
        )));
        frame.render_widget(Paragraph::new(lines), chunks[2]);
    }
}

fn format_field(field: &FormField, value: &FieldValue) -> String {
    match field.kind {
        FieldKind::Number { unit, .. } => {
            if unit.is_empty() {
                value.display()
            } else {
                format!("{} {}", value.display(), unit)
            }
        }
        FieldKind::Decimal { .. } => value.display(),
        FieldKind::Text { placeholder, .. } => {
            let text = value.display();
            if text.is_empty() {
                placeholder.to_owned()
            } else {
                text
            }
        }
        FieldKind::Choice(options) => {
            let current = value.display();
            options
                .iter()
                .find(|option| option.value == current)
                .map_or_else(|| "（未设置）".to_owned(), |option| option.label.to_owned())
        }
        FieldKind::Toggle => value.display(),
    }
}

fn block(title: &str, palette: &Palette) -> Block<'static> {
    Block::default()
        .borders(Borders::ALL)
        .border_style(palette.border())
        .title(Span::styled(
            title.to_owned(),
            ratatui::style::Style::default().add_modifier(Modifier::BOLD),
        ))
}

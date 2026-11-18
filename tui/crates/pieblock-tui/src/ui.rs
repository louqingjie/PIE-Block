//! M0 界面绘制：头部、导航、工作区、详情、状态栏与帮助浮层。

use pieblock_ui::Palette;
use ratatui::Frame;
use ratatui::layout::{Constraint, Layout, Rect};
use ratatui::style::Style;
use ratatui::text::{Line, Span};
use ratatui::widgets::{Block, Clear, List, ListItem, Paragraph, Wrap};
use unicode_width::UnicodeWidthStr;

use crate::app::{
    APP_NAME, App, DETAIL_WIDTH, Focus, Pane, SIDEBAR_WIDTH, TOTAL_TICKS, VERSION, pitch_name,
    project_kind_summary,
};

const LABEL_WIDTH: u16 = 9;
const PIANO_ROWS: u16 = 16;

pub fn draw(frame: &mut Frame, app: &mut App) {
    let area = frame.area();
    app.size = (area.width, area.height);
    let palette = Palette::for_mode(app.theme);

    let outer = Layout::vertical([
        Constraint::Length(3),
        Constraint::Min(6),
        Constraint::Length(2),
    ])
    .split(area);

    draw_header(frame, app, &palette, outer[0]);
    app.areas.footer = outer[2];
    draw_footer(frame, app, &palette, outer[2]);

    let body = outer[1];
    if body.width >= 100 {
        let chunks = Layout::horizontal([
            Constraint::Length(SIDEBAR_WIDTH),
            Constraint::Min(40),
            Constraint::Length(DETAIL_WIDTH),
        ])
        .split(body);
        app.areas.sidebar = chunks[0];
        app.areas.main = chunks[1];
        app.areas.detail = chunks[2];
        draw_sidebar(frame, app, &palette, chunks[0]);
        draw_main(frame, app, &palette, chunks[1]);
        draw_detail(frame, app, &palette, chunks[2]);
    } else if body.width >= 80 {
        let chunks = Layout::horizontal([Constraint::Length(20), Constraint::Min(30)]).split(body);
        app.areas.sidebar = chunks[0];
        app.areas.main = chunks[1];
        app.areas.detail = Rect::default();
        draw_sidebar(frame, app, &palette, chunks[0]);
        draw_main(frame, app, &palette, chunks[1]);
    } else {
        app.areas.sidebar = Rect::default();
        app.areas.detail = Rect::default();
        app.areas.main = body;
        draw_too_small(frame, &palette, body);
        if app.pane == Pane::Piano {
            app.areas.piano_grid = Rect::default();
        }
    }

    if app.help {
        draw_help(frame, app, &palette);
    }
}

fn draw_header(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let block = Block::bordered()
        .border_style(palette.border())
        .title(Line::from(vec![
            Span::styled(format!(" {APP_NAME} "), palette.title()),
            Span::styled(format!("M0 · v{VERSION} "), palette.muted()),
        ]))
        .title(
            Line::from(Span::styled(
                format!(
                    " {} · 焦点 {} · {} · {}×{} ",
                    app.theme.label(),
                    app.focus.label(),
                    app.save.label(),
                    app.size.0,
                    app.size.1
                ),
                palette.muted(),
            ))
            .right_aligned(),
        );
    frame.render_widget(block, area);
}

fn draw_footer(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let status = if app.status.is_empty() {
        " 就绪"
    } else {
        app.status.as_str()
    };
    let lines = vec![
        Line::from(Span::styled(format!(" {status} "), palette.status_bar())),
        Line::from(Span::styled(
            " F1 帮助 · Tab 焦点 · 1/2/3 页面 · t 主题 · Ctrl+S 保存 · Ctrl+Q 退出 · ↑↓←→ 移动 · Enter 确认"
                .to_owned(),
            palette.muted(),
        )),
    ];
    frame.render_widget(Paragraph::new(lines), area);
}

fn draw_sidebar(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let focused = app.focus == Focus::Sidebar;
    let block = Block::bordered()
        .border_style(if focused {
            palette.border_focused()
        } else {
            palette.border()
        })
        .title(Line::from(Span::styled(" 导航 ", palette.title())));
    let items = Pane::ALL.iter().enumerate().map(|(index, pane)| {
        let selected = index == app.sidebar_selected;
        let marker = if selected { "▶" } else { " " };
        let style = if selected {
            palette.selection()
        } else {
            palette.text()
        };
        ListItem::new(Line::from(vec![
            Span::styled(format!("{marker} {} ", index + 1), style),
            Span::styled(pane.label(), style),
        ]))
    });
    frame.render_widget(List::new(items).block(block), area);
}

fn draw_main(frame: &mut Frame, app: &mut App, palette: &Palette, area: Rect) {
    let focused = app.focus == Focus::Main;
    let block = Block::bordered()
        .border_style(if focused {
            palette.border_focused()
        } else {
            palette.border()
        })
        .title(Line::from(Span::styled(
            format!(" {} ", app.pane.label()),
            palette.title(),
        )));
    let inner = block.inner(area);
    frame.render_widget(block, area);

    match app.pane {
        Pane::Overview => draw_overview(frame, app, palette, inner),
        Pane::Form => draw_form(frame, app, palette, inner),
        Pane::Piano => draw_piano(frame, app, palette, inner),
    }
}

fn draw_overview(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let check = |done: bool, text: &str| {
        if done {
            Line::from(vec![
                Span::styled(" ✓ ", palette.ok()),
                Span::styled(text.to_owned(), palette.text()),
            ])
        } else {
            Line::from(vec![
                Span::styled(" … ", palette.warn()),
                Span::styled(text.to_owned(), palette.muted()),
            ])
        }
    };

    let mut lines = vec![
        Line::from(Span::styled(
            "M0 技术验证台（Rust + ratatui）",
            palette.title(),
        )),
        Line::from(""),
        check(true, "Rust workspace 与依赖编译通过"),
        check(true, "CJK / 宽字符 / 边框 / 主题切换"),
        check(app.size.0 >= 100, "宽屏三栏布局（≥100 列）"),
        check(false, "Windows Terminal 下的键鼠/IME 人工验证"),
        check(false, "hidapi 真机读写 info 帧"),
        check(false, "SDCC 构建 + HEX 与 Flutter 对拍"),
        Line::from(""),
        Line::from(Span::styled(
            "四类工程（来自 pieblock-core）",
            palette.title(),
        )),
    ];
    for (label, steps, first_step) in project_kind_summary() {
        lines.push(Line::from(vec![
            Span::styled(format!("  {label}"), palette.text()),
            Span::styled(
                format!(" · {steps} 步 · 首步 {first_step}"),
                palette.muted(),
            ),
        ]));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled("中文/宽字符示例", palette.title())));
    lines.push(Line::from(
        "  遥控器通道 摇杆死区 云台与拨弹 ≥ ≤ – ÷ ♯ ♭ ♮ 中文输入测试",
    ));
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        format!(
            "环境：{}×{} · 主题 {} · 鼠标 {} · 按 2 试表单，按 3 试卷帘",
            app.size.0,
            app.size.1,
            app.theme.label(),
            if app.mouse_enabled { "开" } else { "关" }
        ),
        palette.info(),
    )));
    let paragraph = Paragraph::new(lines)
        .wrap(Wrap { trim: false })
        .scroll((app.detail_scroll, 0));
    frame.render_widget(paragraph, area);
}

fn draw_form(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let mut lines = vec![
        Line::from(Span::styled(
            "表单原型：↑↓ 选择 · ←→ 调整 · Enter 编辑/切换 · Esc 取消 · Space 开关",
            palette.muted(),
        )),
        Line::from(""),
    ];
    for (index, field) in app.form.fields.iter().enumerate() {
        let selected = index == app.form.selected;
        let editing = app.form.editing.is_some() && app.form.editing_index == index;
        let marker = if selected { "▸" } else { " " };
        let value = if editing {
            let buffer = app.form.editing.as_deref().unwrap_or_default();
            format!("{buffer}▏")
        } else {
            field.value.clone()
        };
        let mut row_style = if selected {
            palette.selection()
        } else {
            palette.text()
        };
        if app.form.error.is_some() && selected {
            row_style = palette.error();
        }
        let mut spans = vec![
            Span::styled(format!("{marker} "), row_style),
            Span::styled(pad_display(field.label, 14), row_style),
            Span::styled(pad_display(&value, 14), row_style),
        ];
        if !field.unit.is_empty() {
            spans.push(Span::styled(format!("{} ", field.unit), palette.muted()));
        }
        spans.push(Span::styled(field.hint.to_owned(), palette.muted()));
        lines.push(Line::from(spans));
    }
    lines.push(Line::from(""));
    if let Some(error) = &app.form.error {
        lines.push(Line::from(Span::styled(
            format!(" ✖ {error}"),
            palette.error(),
        )));
    }
    if let Some(warning) = &app.form.warning {
        lines.push(Line::from(Span::styled(
            format!(" ⚠ {warning}"),
            palette.warn(),
        )));
    }
    if app.form.error.is_none() && app.form.warning.is_none() {
        lines.push(Line::from(Span::styled(
            " ✓ 本页没有错误（M0 示例，真实校验在 M1 接入）",
            palette.ok(),
        )));
    }
    lines.push(Line::from(""));
    lines.push(Line::from(Span::styled(
        format!(
            "状态：{} · 编辑中：{}",
            app.save.label(),
            app.form.editing.is_some()
        ),
        palette.info(),
    )));
    let paragraph = Paragraph::new(lines).wrap(Wrap { trim: false });
    frame.render_widget(paragraph, area);
}

fn draw_piano(frame: &mut Frame, app: &mut App, palette: &Palette, area: Rect) {
    let header = Line::from(vec![
        Span::styled("PPQ 480 · 120 BPM · 4/4 · ", palette.muted()),
        Span::styled(
            format!(
                "缩放 {}x · 光标 tick {} · {} · {}",
                app.piano.zoom,
                app.piano.cursor_tick,
                crate::app::pitch_name(app.piano.cursor_pitch),
                if app.piano.playing {
                    "播放中"
                } else {
                    "停止"
                }
            ),
            palette.text(),
        ),
    ]);
    let chunks = Layout::vertical([Constraint::Length(1), Constraint::Min(1)]).split(area);
    frame.render_widget(Paragraph::new(header), chunks[0]);

    let grid_area = chunks[1];
    let zoom = u16::from(app.piano.zoom.max(1));
    let usable_columns = grid_area.width.saturating_sub(LABEL_WIDTH);
    let columns =
        usable_columns.min(u16::try_from(TOTAL_TICKS * u32::from(zoom)).unwrap_or(u16::MAX));
    let rows = grid_area.height.clamp(1, PIANO_ROWS);
    let top = app.piano.top_pitch();

    let mut lines: Vec<Line> = Vec::with_capacity(usize::from(rows));
    for row in 0..rows {
        let pitch = top - i16::try_from(row).unwrap_or(i16::MAX);
        if pitch < 0 {
            break;
        }
        let pitch = u8::try_from(pitch).unwrap_or(0);
        let mut spans: Vec<Span> = Vec::with_capacity(usize::from(columns) + 1);
        spans.push(Span::styled(
            pad_display(
                &format!("{} {}", pitch_name(pitch), pitch),
                LABEL_WIDTH as usize,
            ),
            palette.muted(),
        ));
        for column in 0..columns {
            let tick = u32::from(column) / u32::from(zoom);
            let cursor = tick == app.piano.cursor_tick && pitch == app.piano.cursor_pitch;
            let (symbol, style) = if cursor {
                ("▮".to_owned(), palette.selection())
            } else if let Some(note) = app.piano.note_at(tick, pitch) {
                let selected = app.piano.selected == Some(note.id);
                let symbol = if selected {
                    "▓".to_owned()
                } else {
                    "█".to_owned()
                };
                let style = if selected {
                    palette.accent()
                } else {
                    palette.title()
                };
                (symbol, style)
            } else if app.piano.playing && app.piano.playhead == tick {
                ("│".to_owned(), palette.info())
            } else if tick % 4 == 0 {
                ("·".to_owned(), palette.muted())
            } else {
                (" ".to_owned(), Style::default())
            };
            spans.push(Span::styled(symbol, style));
        }
        lines.push(Line::from(spans));
    }

    let grid_x = grid_area.x + LABEL_WIDTH;
    let grid_height = u16::try_from(lines.len()).unwrap_or(0);
    app.areas.piano_grid = Rect {
        x: grid_x,
        y: grid_area.y,
        width: columns,
        height: grid_height,
    };

    let paragraph = Paragraph::new(lines);
    frame.render_widget(paragraph, grid_area);
}

fn draw_detail(frame: &mut Frame, app: &App, palette: &Palette, area: Rect) {
    let focused = app.focus == Focus::Detail;
    let block = Block::bordered()
        .border_style(if focused {
            palette.border_focused()
        } else {
            palette.border()
        })
        .title(Line::from(Span::styled(" 详情 / 帮助 ", palette.title())));
    let inner = block.inner(area);
    frame.render_widget(block, area);

    let mut lines = vec![
        Line::from(vec![
            Span::styled("焦点：", palette.muted()),
            Span::styled(app.focus.label().to_owned(), palette.text()),
        ]),
        Line::from(vec![
            Span::styled("页面：", palette.muted()),
            Span::styled(app.pane.label().to_owned(), palette.text()),
        ]),
        Line::from(""),
        Line::from(Span::styled(pane_help(app.pane), palette.text())),
        Line::from(""),
        Line::from(Span::styled("全局键位", palette.title())),
        Line::from("  F1/? 帮助"),
        Line::from("  Tab / Shift+Tab 焦点"),
        Line::from("  1/2/3 切换页面"),
        Line::from("  t 主题  Ctrl+S 保存"),
        Line::from("  Ctrl+Q 退出"),
        Line::from(""),
        Line::from(Span::styled(
            "M0 目标：验证终端渲染、宽字符、键鼠与两个高复杂度控件；真实业务页从 M3/M4 开始。",
            palette.muted(),
        )),
    ];
    if app.pane == Pane::Piano {
        lines.push(Line::from(""));
        lines.push(Line::from(Span::styled("卷帘键位", palette.title())));
        lines.push(Line::from("  ↑↓ 音高  ←→ tick"));
        lines.push(Line::from("  Space 播放/暂停"));
        lines.push(Line::from("  n 加音符  x 删除音符"));
        lines.push(Line::from("  +/- 缩放"));
    }
    let paragraph = Paragraph::new(lines)
        .wrap(Wrap { trim: false })
        .scroll((app.detail_scroll, 0));
    frame.render_widget(paragraph, inner);
}

fn pane_help(pane: Pane) -> String {
    match pane {
        Pane::Overview => {
            "M0 概览：检查项、四类工程步骤数与环境信息；按 2/3 试用交互原型。".to_owned()
        }
        Pane::Form => {
            "表单原型：模拟数字输入、下拉、开关与滑块；支持中文输入与错误提示，保存状态联动。"
                .to_owned()
        }
        Pane::Piano => {
            "钢琴卷帘原型：字符网格、音符绘制、光标、播放头与缩放；验证终端下的可读性与键鼠操作。"
                .to_owned()
        }
    }
}

fn draw_too_small(frame: &mut Frame, palette: &Palette, area: Rect) {
    let paragraph = Paragraph::new(vec![
        Line::from(Span::styled("终端太小", palette.error())),
        Line::from(Span::styled(
            "请调整到至少 80×24；推荐 120×36。",
            palette.muted(),
        )),
        Line::from(Span::styled("Ctrl+Q 退出。", palette.muted())),
    ])
    .block(Block::bordered().border_style(palette.border()));
    frame.render_widget(paragraph, area);
}

fn draw_help(frame: &mut Frame, app: &App, palette: &Palette) {
    let area = frame.area();
    let width = area.width.saturating_sub(6).clamp(40, 80);
    let height = area.height.saturating_sub(4).clamp(10, 20);
    let x = area.x + (area.width.saturating_sub(width)) / 2;
    let y = area.y + (area.height.saturating_sub(height)) / 2;
    let popup = Rect::new(x, y, width, height);
    frame.render_widget(Clear, popup);

    let block = Block::bordered()
        .border_style(palette.border_focused())
        .title(Line::from(Span::styled(
            " 帮助 · F1/Esc 关闭 ",
            palette.title(),
        )));
    let inner = block.inner(popup);
    frame.render_widget(block, popup);

    let lines = vec![
        Line::from(Span::styled("M0 键位与流程", palette.title())),
        Line::from("  Tab / Shift+Tab   在导航、工作区、详情间移动焦点"),
        Line::from("  1 / 2 / 3         切换 M0 概览 / 表单 / 钢琴卷帘"),
        Line::from("  ↑ ↓ ← →          移动/调整；表单内调整数值或选项"),
        Line::from("  Enter            编辑文本/数字，或切换开关/下拉"),
        Line::from("  Space            切换开关；卷帘中播放/暂停"),
        Line::from("  n / x            卷帘中在光标处新增/删除音符"),
        Line::from("  + / -            卷帘缩放"),
        Line::from("  t                切换深色/浅色主题"),
        Line::from("  Ctrl+S           模拟保存（M1 接真实 .pieproj）"),
        Line::from("  Ctrl+Q           退出"),
        Line::from(""),
        Line::from(Span::styled("鼠标", palette.title())),
        Line::from("  左键点击导航/工作表；滚轮滚动；--no-mouse 可关闭鼠标捕获。"),
        Line::from(""),
        Line::from(Span::styled(
            "M1 起：真实项目文件、校验器、代码生成；M2：SDCC 与 HID 烧录。",
            palette.muted(),
        )),
        Line::from(Span::styled(
            format!(
                "  当前终端 {}×{}，主题 {}",
                app.size.0,
                app.size.1,
                app.theme.label()
            ),
            palette.muted(),
        )),
    ];
    frame.render_widget(Paragraph::new(lines).wrap(Wrap { trim: false }), inner);
}

fn pad_display(text: &str, width: usize) -> String {
    let current = UnicodeWidthStr::width(text);
    if current >= width {
        text.to_owned()
    } else {
        let mut result = text.to_owned();
        result.push_str(&" ".repeat(width - current));
        result
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::app::App;
    use ratatui::Terminal;
    use ratatui::backend::TestBackend;

    fn render(app: &mut App, width: u16, height: u16) -> String {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("terminal");
        terminal
            .draw(|frame| draw(frame, app))
            .expect("draw should not panic");
        terminal
            .backend()
            .buffer()
            .content()
            .iter()
            .map(|cell| cell.symbol())
            .collect()
    }

    /// 宽字符在缓冲区里占两个 cell，拼接后会出现占位空格；断言中文时先去掉空白。
    fn compact(text: &str) -> String {
        text.chars().filter(|ch| !ch.is_whitespace()).collect()
    }

    #[test]
    fn renders_wide_shell() {
        let mut app = App::new(false);
        let content = render(&mut app, 120, 36);
        assert!(content.contains("PIE-Block TUI"));
        assert!(content.contains("M0"));
        assert!(compact(&content).contains("导航"));
        assert!(compact(&content).contains("详情"));
    }

    #[test]
    fn renders_form_and_piano_panes() {
        let mut app = App::new(false);
        app.pane = Pane::Form;
        let form = render(&mut app, 120, 36);
        assert!(compact(&form).contains("表单"));
        assert!(compact(&form).contains("遥控器通道"));
        app.pane = Pane::Piano;
        let piano = render(&mut app, 120, 36);
        assert!(piano.contains("PPQ"));
        assert!(compact(&piano).contains("缩放"));
    }

    #[test]
    fn renders_compact_layout_at_80x24() {
        let mut app = App::new(false);
        let content = render(&mut app, 80, 24);
        assert!(content.contains("M0"));
    }

    #[test]
    fn help_overlay_renders() {
        let mut app = App::new(false);
        app.help = true;
        let content = render(&mut app, 120, 36);
        assert!(compact(&content).contains("帮助"));
        assert!(content.contains("Ctrl+Q"));
    }
}

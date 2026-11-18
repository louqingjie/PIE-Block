//! 首页/文件浏览器/设置页渲染与浏览器状态机测试（80×24 与 120×36）。

use std::fs;
use std::path::{Path, PathBuf};

use pieblock_ui::{
    BrowserAction, FileBrowser, HomeView, Palette, RecentItem, SettingRow, draw_browser, draw_home,
    draw_settings,
};
use ratatui::Frame;
use ratatui::Terminal;
use ratatui::backend::TestBackend;

fn unique_dir(name: &str) -> PathBuf {
    let dir = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("../../target")
        .join(format!("ui-screens-{name}-{}", std::process::id()));
    let _ = fs::remove_dir_all(&dir);
    fs::create_dir_all(&dir).expect("temp dir");
    dir
}

fn render(width: u16, height: u16, draw: impl FnOnce(&mut Frame)) -> String {
    let backend = TestBackend::new(width, height);
    let mut terminal = Terminal::new(backend).expect("terminal");
    terminal.draw(|frame| draw(frame)).expect("draw");
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

/// 去掉宽字符占位空格，便于断言中文文案。
fn compact(text: &str) -> String {
    text.chars().filter(|ch| !ch.is_whitespace()).collect()
}

#[test]
fn home_renders_recent_projects_and_shortcuts() {
    let palette = Palette::dark();
    let recent = vec![
        RecentItem {
            name: "步兵一号".to_owned(),
            path: "C:/projects/infantry.pieproj".to_owned(),
            kind_label: "步兵".to_owned(),
            available: true,
        },
        RecentItem {
            name: "丢了".to_owned(),
            path: "C:/projects/gone.pieproj".to_owned(),
            kind_label: "工程".to_owned(),
            available: false,
        },
    ];
    let view = HomeView {
        app_title: "PIE-Block",
        subtitle: "机器人图形化配置终端版",
        recent: &recent,
        selected: 0,
        status: "就绪",
        message: None,
    };
    let wide = compact(&render(120, 36, |frame| {
        draw_home(frame, frame.area(), &view, &palette);
    }));
    assert!(wide.contains("PIE-Block"));
    assert!(wide.contains("最近项目"));
    assert!(wide.contains("步兵一号"));
    assert!(wide.contains("[步兵]"));
    assert!(wide.contains("文件已不存在"));
    assert!(wide.contains("打开文件"));
    let narrow = render(80, 24, |frame| {
        draw_home(frame, frame.area(), &view, &palette);
    });
    assert!(narrow.lines().count() <= 24);
    assert!(compact(&narrow).contains("最近项目"));
}

#[test]
fn home_renders_empty_state() {
    let palette = Palette::light();
    let view = HomeView {
        app_title: "PIE-Block",
        subtitle: "机器人图形化配置终端版",
        recent: &[],
        selected: 0,
        status: "就绪",
        message: Some("新建工程后会自动记录最近项目"),
    };
    let text = compact(&render(80, 24, |frame| {
        draw_home(frame, frame.area(), &view, &palette);
    }));
    assert!(text.contains("还没有最近项目"));
    assert!(text.contains("按N新建"));
    assert!(text.contains("新建工程后会自动记录最近项目"));
}

#[test]
fn file_browser_filters_and_navigates() {
    let dir = unique_dir("browser");
    fs::create_dir_all(dir.join("sub")).expect("subdir");
    fs::create_dir_all(dir.join(".hidden")).expect("hidden dir");
    fs::write(dir.join("robot.pieproj"), b"{}").expect("project");
    fs::write(dir.join("other.txt"), b"x").expect("text");
    fs::write(dir.join(".secret.pieproj"), b"{}").expect("hidden project");
    let mut browser = FileBrowser::new(&dir);
    let names: Vec<&str> = browser
        .entries
        .iter()
        .map(|entry| entry.name.as_str())
        .collect();
    assert_eq!(names, vec!["sub", "robot.pieproj"]);
    assert!(browser.entries[0].is_dir);
    assert!(browser.entries[1].is_project);

    browser.move_selection(1);
    assert_eq!(browser.selected, 1);
    browser.move_selection(1);
    assert_eq!(browser.selected, 0, "selection wraps");
    browser.move_selection(-1);
    assert_eq!(browser.selected, 1);

    browser.selected = 1;
    match browser.activate() {
        BrowserAction::OpenProject(path) => assert_eq!(path, dir.join("robot.pieproj")),
        other => panic!("unexpected action: {other:?}"),
    }

    browser.selected = 0;
    match browser.activate() {
        BrowserAction::ChangeDirectory(path) => {
            assert_eq!(
                path.canonicalize().expect("canonical"),
                dir.join("sub").canonicalize().expect("canonical")
            );
            assert!(browser.is_empty());
        }
        other => panic!("unexpected action: {other:?}"),
    }
    browser.go_up();
    assert_eq!(
        browser.current_dir.canonicalize().expect("canonical"),
        dir.canonicalize().expect("canonical")
    );
    assert!(!browser.is_empty());
}

#[test]
fn browser_renders_entries_and_controls() {
    let dir = unique_dir("browser-render");
    fs::create_dir_all(dir.join("sub")).expect("subdir");
    fs::write(dir.join("demo.pieproj"), b"{}").expect("project");
    let mut browser = FileBrowser::new(&dir);
    browser.move_selection(1);
    let palette = Palette::dark();
    let text = compact(&render(80, 24, |frame| {
        draw_browser(frame, frame.area(), &browser, &palette);
    }));
    assert!(text.contains("打开工程"));
    assert!(text.contains("sub/"));
    assert!(text.contains("demo.pieproj"));
    assert!(text.contains("Enter进入/打开"));
    assert!(text.contains("路径"));
}

#[test]
fn settings_renders_rows_and_selection() {
    let palette = Palette::dark();
    let rows = vec![
        SettingRow {
            label: "主题",
            value: "深色".to_owned(),
            hint: "Enter 切换：跟随系统/浅色/深色",
        },
        SettingRow {
            label: "编译器",
            value: "SDCC".to_owned(),
            hint: "Enter 在 SDCC / Keil 之间切换",
        },
        SettingRow {
            label: "Keil 路径",
            value: "（未设置）".to_owned(),
            hint: "Windows 下选择 Keil C251 安装目录",
        },
    ];
    let text = compact(&render(120, 36, |frame| {
        draw_settings(frame, frame.area(), &rows, 1, &palette);
    }));
    assert!(text.contains("设置"));
    assert!(text.contains("主题"));
    assert!(text.contains("深色"));
    assert!(text.contains("编译器"));
    assert!(text.contains("Keil路径"));
    assert!(text.contains("Enter在SDCC/Keil之间切换"));
}

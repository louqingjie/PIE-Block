mod app;
mod ui;

use std::io;

use crossterm::event::{DisableMouseCapture, EnableMouseCapture};
use crossterm::execute;

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
    if args.iter().any(|arg| arg == "--version" || arg == "-V") {
        println!("PIE-Block TUI {}", env!("CARGO_PKG_VERSION"));
        return Ok(());
    }
    if args.iter().any(|arg| arg == "--help" || arg == "-h") {
        println!(
            "PIE-Block TUI {}\\n\\n用法：pieblock-tui [选项]\\n\\n选项：\\n  --demo          启动 M0 演示壳\\n  --no-mouse      关闭鼠标捕获\\n  --diagnostics   打印环境诊断（发布验收用）\\n  --version/-V    打印版本\\n  --help/-h       打印本帮助",
            env!("CARGO_PKG_VERSION")
        );
        return Ok(());
    }
    if args.iter().any(|arg| arg == "--diagnostics") {
        for line in pieblock_tui::home_shell::diagnostics() {
            println!("{line}");
        }
        return Ok(());
    }
    let mouse_enabled = !args.iter().any(|arg| arg == "--no-mouse");

    let mut terminal = ratatui::init();
    if mouse_enabled {
        execute!(io::stdout(), EnableMouseCapture)?;
    }

    let demo = args.iter().any(|arg| arg == "--demo");
    let result = if demo {
        app::App::new(mouse_enabled).run(&mut terminal)
    } else {
        let start = std::env::current_dir().unwrap_or_default();
        let mut shell = pieblock_tui::home_shell::Shell::new(start);
        shell.run(&mut terminal)
    };

    if mouse_enabled {
        let _ = execute!(io::stdout(), DisableMouseCapture);
    }
    ratatui::restore();
    result
}

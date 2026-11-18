mod app;
mod ui;

use std::io;

use crossterm::event::{DisableMouseCapture, EnableMouseCapture};
use crossterm::execute;

fn main() -> io::Result<()> {
    let args: Vec<String> = std::env::args().collect();
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

//! 汇编术语表数据与浮层渲染测试。

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_ui::GlossaryState;

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

#[test]
fn glossary_has_full_entries_and_navigates() {
    assert!(GlossaryState::count() >= 280);
    let mut state = GlossaryState::new();
    assert!(state.entry().is_some());
    let first = state.entry().expect("first").key;
    state.handle_key(key(KeyCode::Down));
    assert_ne!(state.entry().expect("second").key, first);
    state.handle_key(key(KeyCode::End));
    assert_eq!(state.selected, GlossaryState::count() - 1);
    assert!(state.handle_key(key(KeyCode::Esc)));
}

#[test]
fn glossary_renders_titles() {
    let mut state = GlossaryState::new();
    let backend = ratatui::backend::TestBackend::new(110, 34);
    let mut terminal = ratatui::Terminal::new(backend).expect("terminal");
    terminal
        .draw(|frame| state.render(frame, frame.area(), &pieblock_ui::Palette::dark(), 20))
        .expect("draw");
    let buffer = terminal.backend().buffer();
    let area = *buffer.area();
    let mut text = String::new();
    for y in area.y..area.y + area.height {
        for x in area.x..area.x + area.width {
            text.push_str(buffer[(x, y)].symbol());
        }
    }
    let compact: String = text.chars().filter(|ch| !ch.is_whitespace()).collect();
    assert!(compact.contains("汇编术语"));
    assert!(compact.contains("ADD"));
}

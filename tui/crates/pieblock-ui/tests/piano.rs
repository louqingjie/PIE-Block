//! 钢琴卷帘编辑与渲染测试。

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_core::model::ProjectConfig;
use pieblock_core::{ProjectDocument, ProjectKind};
use pieblock_ui::{PianoAction, PianoRoll};

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

fn music_config() -> pieblock_core::model::MusicConfig {
    match ProjectDocument::create(ProjectKind::Music).config {
        ProjectConfig::Music(music) => music,
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn piano_roll_adds_moves_and_commits_notes() {
    let config = music_config();
    let mut roll = PianoRoll::new(&config);
    assert!(roll.notes.is_empty());
    assert_eq!(
        roll.handle_key(key(KeyCode::Char('a'))),
        PianoAction::Changed
    );
    assert_eq!(roll.notes.len(), 1);
    let start = roll.notes[0].start_tick;
    assert_eq!(roll.handle_key(key(KeyCode::Right)), PianoAction::Changed);
    assert!(roll.notes[0].start_tick > start);
    let duration = roll.notes[0].duration_ticks;
    assert_eq!(
        roll.handle_key(key(KeyCode::Char('+'))),
        PianoAction::Changed
    );
    assert!(roll.notes[0].duration_ticks > duration);
    assert_eq!(
        roll.handle_key(key(KeyCode::Char('K'))),
        PianoAction::Changed
    );
    assert_eq!(roll.notes[0].pitch, 61);
    assert_eq!(
        roll.handle_key(key(KeyCode::Char('d'))),
        PianoAction::Changed
    );
    assert!(roll.notes.is_empty());
    assert_eq!(
        roll.handle_key(key(KeyCode::Char('a'))),
        PianoAction::Changed
    );
    assert_eq!(roll.handle_key(key(KeyCode::Esc)), PianoAction::Commit);
    let mut config = ProjectConfig::Music(music_config());
    roll.commit(&mut config);
    match config {
        ProjectConfig::Music(music) => assert_eq!(music.notes.len(), 1),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn piano_roll_renders_grid_and_status() {
    let mut roll = PianoRoll::new(&music_config());
    roll.handle_key(key(KeyCode::Char('a')));
    let backend = ratatui::backend::TestBackend::new(100, 24);
    let mut terminal = ratatui::Terminal::new(backend).expect("terminal");
    terminal
        .draw(|frame| roll.render(frame, frame.area(), &pieblock_ui::Palette::dark()))
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
    assert!(compact.contains("钢琴卷帘"));
    assert!(compact.contains('█'));
}

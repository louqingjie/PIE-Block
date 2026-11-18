//! 播放预览推进/渲染测试。

use std::time::{Duration, Instant};

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_core::model::{MusicConfig, MusicNote, ProjectConfig};
use pieblock_core::{ProjectDocument, ProjectKind};
use pieblock_ui::{Playback, PlaybackAction};

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

fn music_with_note() -> MusicConfig {
    let mut config = match ProjectDocument::create(ProjectKind::Music).config {
        ProjectConfig::Music(music) => music,
        other => panic!("unexpected config: {other:?}"),
    };
    config.notes.push(MusicNote {
        id: "1".to_owned(),
        pitch: 60,
        start_tick: 0,
        duration_ticks: 480,
    });
    config
}

#[test]
fn playback_toggles_advances_and_seeks() {
    let mut playback = Playback::new(&music_with_note());
    assert!(playback.duration_tick >= 480);
    assert!(!playback.playing);
    assert_eq!(
        playback.handle_key(key(KeyCode::Char(' '))),
        PlaybackAction::Changed
    );
    assert!(playback.playing);
    let now = Instant::now();
    playback.tick(now);
    playback.tick(now + Duration::from_millis(500));
    assert!(playback.position_tick > 0.0);
    playback.position_tick = 100.0;
    assert_eq!(playback.active_pitch(), Some(60));
    assert_eq!(
        playback.handle_key(key(KeyCode::End)),
        PlaybackAction::Changed
    );
    assert!(!playback.playing);
    assert_eq!(
        playback.handle_key(key(KeyCode::Home)),
        PlaybackAction::Changed
    );
    assert_eq!(playback.position_tick, 0.0);
    assert_eq!(
        playback.handle_key(key(KeyCode::Char('+'))),
        PlaybackAction::Changed
    );
    assert!(playback.speed > 1.0);
    assert_eq!(
        playback.handle_key(key(KeyCode::Esc)),
        PlaybackAction::Close
    );
}

#[test]
fn playback_renders_progress_and_note() {
    let mut playback = Playback::new(&music_with_note());
    playback.handle_key(key(KeyCode::Char(' ')));
    playback.position_tick = 100.0;
    let backend = ratatui::backend::TestBackend::new(90, 20);
    let mut terminal = ratatui::Terminal::new(backend).expect("terminal");
    terminal
        .draw(|frame| playback.render(frame, frame.area(), &pieblock_ui::Palette::dark()))
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
    assert!(compact.contains("播放预览"));
    assert!(compact.contains('▶'));
}

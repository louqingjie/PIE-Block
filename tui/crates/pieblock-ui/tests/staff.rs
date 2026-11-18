//! 五线谱文本渲染测试。

use pieblock_core::model::{MusicConfig, MusicNote, ProjectConfig};
use pieblock_core::{ProjectDocument, ProjectKind};
use pieblock_ui::{staff_header, staff_legend, staff_text};

fn music_with_notes() -> MusicConfig {
    let mut music = match ProjectDocument::create(ProjectKind::Music).config {
        ProjectConfig::Music(music) => music,
        other => panic!("unexpected config: {other:?}"),
    };
    for (index, pitch) in [60, 64, 67].into_iter().enumerate() {
        music.notes.push(MusicNote {
            id: format!("n{index}"),
            pitch,
            start_tick: 480 * i64::try_from(index).unwrap_or(0),
            duration_ticks: 480,
        });
    }
    music
}

#[test]
fn staff_text_places_notes_on_rows() {
    let music = music_with_notes();
    let lines = staff_text(&music, 60, 0);
    assert_eq!(lines.len(), 13);
    assert!(lines.iter().any(|line| line.contains('─')));
    assert!(lines.iter().any(|line| line.contains('●')));
    assert!(staff_header(&music).contains("高音谱号"));
    assert!(staff_header(&music).contains("3 个音符"));
    let legend = staff_legend(&music);
    assert!(legend.contains("C4"));
    assert!(legend.contains("E4"));
    assert!(legend.contains("G4"));
    let bass = staff_text(&music, 60, 1);
    assert_eq!(bass.len(), 13);
}

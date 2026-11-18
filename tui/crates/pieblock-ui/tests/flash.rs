//! 烧录页状态/按键测试（无硬件）。

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_ui::{FlashAction, FlashState};

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

#[test]
fn flash_state_without_hex_and_device_reports_and_closes() {
    let mut state = FlashState::with_probe(None, None);
    assert!(!state.log.is_empty());
    assert!(state.device_count >= 0);
    assert_eq!(state.handle_key(key(KeyCode::Enter)), FlashAction::None);
    assert!(
        state
            .log
            .iter()
            .any(|line| line.contains("未找到 HEX") || line.contains("HEX"))
    );
    state.handle_key(key(KeyCode::Char('r')));
    assert!(!state.log.is_empty());
    assert_eq!(state.handle_key(key(KeyCode::Esc)), FlashAction::Close);
}

#[test]
fn flash_state_with_hex_builds_start_action() {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("../../target");
    std::fs::create_dir_all(&dir).expect("dir");
    let hex = dir.join(format!("flash-test-{}.hex", std::process::id()));
    std::fs::write(&hex, ":00000001FF\n").expect("hex");
    let mut state = FlashState::with_probe(Some(hex.clone()), Some("abc".to_owned()));
    let action = state.handle_key(key(KeyCode::Enter));
    match action {
        FlashAction::Start { hex_path, sha256 } => {
            assert_eq!(hex_path, hex);
            assert_eq!(sha256, "abc");
        }
        other => panic!("unexpected action: {other:?}"),
    }
    let _ = std::fs::remove_file(&hex);
}

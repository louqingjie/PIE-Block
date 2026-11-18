//! 表单引擎 + 「遥控器与底盘」页测试。

use crossterm::event::{KeyCode, KeyEvent, KeyModifiers};
use pieblock_core::ProjectDocument;
use pieblock_core::ProjectKind;
use pieblock_core::model::{Direction, ProjectConfig};
use pieblock_ui::{FieldValue, FormAction, FormState, Palette, remote_page};
use ratatui::Frame;
use ratatui::Terminal;
use ratatui::backend::TestBackend;

fn key(code: KeyCode) -> KeyEvent {
    KeyEvent::new(code, KeyModifiers::NONE)
}

fn infantry_config() -> ProjectConfig {
    ProjectDocument::create(ProjectKind::Infantry).config
}

fn engineer_config() -> ProjectConfig {
    ProjectDocument::create(ProjectKind::Engineer).config
}

fn field_index(page: &pieblock_ui::FormPage, id: &str) -> usize {
    page.fields
        .iter()
        .position(|field| field.id == id)
        .unwrap_or_else(|| panic!("field not found: {id}"))
}

fn clear_editing(state: &mut FormState, page: &pieblock_ui::FormPage, digits: &str) -> FormAction {
    state.handle_key(page, key(KeyCode::Enter));
    for _ in 0..8 {
        state.handle_key(page, key(KeyCode::Backspace));
    }
    for character in digits.chars() {
        state.handle_key(page, key(KeyCode::Char(character)));
    }
    state.handle_key(page, key(KeyCode::Enter))
}

#[test]
fn remote_page_has_expected_fields() {
    let page = remote_page(ProjectKind::Infantry);
    assert_eq!(page.id, "remote");
    assert_eq!(page.fields.len(), 15);
    assert_eq!(page.fields[0].id, "remote.channel");
    assert_eq!(page.fields[1].id, "remote.deadzone");
    assert!(
        page.fields
            .iter()
            .any(|field| field.id == "chassis.turn_reversed")
    );
    let engineer = remote_page(ProjectKind::Engineer);
    assert_eq!(engineer.fields.len(), 16, "engineer gets chassis enable");
    assert_eq!(engineer.fields[2].id, "chassis.enabled");
}

#[test]
fn number_edit_writes_config_and_validates_range() {
    let config = infantry_config();
    let page = remote_page(ProjectKind::Infantry);
    let mut state = FormState::new(config);
    assert_eq!(clear_editing(&mut state, &page, "42"), FormAction::Changed);
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.remote.channel, Some(42)),
        other => panic!("unexpected config: {other:?}"),
    }
    assert!(state.dirty);

    assert_eq!(clear_editing(&mut state, &page, "999"), FormAction::None);
    let message = state.message.clone().unwrap_or_default();
    assert!(message.contains("超出范围"), "message: {message}");
    assert!(state.editing.is_some(), "invalid input keeps editing");
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.remote.channel, Some(42)),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn toggles_and_choices_cycle() {
    let config = infantry_config();
    let page = remote_page(ProjectKind::Infantry);
    let mut state = FormState::new(config);
    state.user_navigate(&page, "chassis.sprint_enabled");
    state.handle_key(&page, key(KeyCode::Enter));
    match &state.config {
        ProjectConfig::Infantry(value) => assert!(value.chassis.sprint_enabled),
        other => panic!("unexpected config: {other:?}"),
    }
    state.handle_key(&page, key(KeyCode::Enter));
    match &state.config {
        ProjectConfig::Infantry(value) => assert!(!value.chassis.sprint_enabled),
        other => panic!("unexpected config: {other:?}"),
    }

    state.user_navigate(&page, "chassis.left_front.direction");
    state.handle_key(&page, key(KeyCode::Right));
    match &state.config {
        ProjectConfig::Infantry(value) => {
            assert_eq!(value.chassis.left_front.direction, Some(Direction::Forward));
        }
        other => panic!("unexpected config: {other:?}"),
    }
    state.handle_key(&page, key(KeyCode::Left));
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.chassis.left_front.direction, None),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn max_edit_clamps_and_page_actions() {
    let config = infantry_config();
    let page = remote_page(ProjectKind::Infantry);
    let mut state = FormState::new(config);
    // 通道号已到上限后再按右不越界。
    state.user_navigate(&page, "remote.channel");
    for _ in 0..200 {
        state.handle_key(&page, key(KeyCode::Right));
    }
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.remote.channel, Some(125)),
        other => panic!("unexpected config: {other:?}"),
    }
    assert_eq!(
        state.handle_key(&page, key(KeyCode::PageUp)),
        FormAction::PrevPage
    );
    assert_eq!(
        state.handle_key(&page, key(KeyCode::PageDown)),
        FormAction::NextPage
    );
}

#[test]
fn engineer_chassis_toggle_disables() {
    let config = engineer_config();
    let page = remote_page(ProjectKind::Engineer);
    let mut state = FormState::new(config);
    state.user_navigate(&page, "chassis.enabled");
    state.handle_key(&page, key(KeyCode::Enter));
    match &state.config {
        ProjectConfig::Engineer(value) => assert!(!value.chassis.enabled),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn renders_form_page_at_both_sizes() {
    let page = remote_page(ProjectKind::Infantry);
    let mut state = FormState::new(infantry_config());
    state.user_navigate(&page, "chassis.left_front.direction");
    let palette = Palette::dark();
    for (width, height) in [(80, 24), (120, 36)] {
        let backend = TestBackend::new(width, height);
        let mut terminal = Terminal::new(backend).expect("terminal");
        terminal
            .draw(|frame: &mut Frame| state.render(frame, frame.area(), &page, &palette))
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
        assert!(compact.contains("遥控器与底盘") || compact.contains("第1步"));
        assert!(compact.contains("通道号"));
        assert!(compact.contains("左前轮"));
        assert!(compact.contains("正转") || compact.contains("未设置"));
    }
}

#[test]
fn value_display_and_choice_labels() {
    assert_eq!(FieldValue::Int(12).display(), "12");
    assert_eq!(FieldValue::Bool(true).display(), "开启");
    assert_eq!(
        FieldValue::Choice("forward".to_owned()).display(),
        "forward"
    );
}

trait Navigate {
    fn user_navigate(&mut self, page: &pieblock_ui::FormPage, id: &str);
}

impl Navigate for FormState {
    fn user_navigate(&mut self, page: &pieblock_ui::FormPage, id: &str) {
        let index = field_index(page, id);
        while self.selected < index {
            self.selected += 1;
        }
        while self.selected > index {
            self.selected -= 1;
        }
    }
}

#[test]
fn infantry_pages_edit_scalar_fields() {
    use pieblock_ui::{infantry_controls_page, infantry_mechanism_page};

    let mechanism_config = infantry_config();
    let mechanism = infantry_mechanism_page(&mechanism_config);
    assert!(mechanism.fields.len() >= 4);
    assert_eq!(mechanism.fields[0].id, "mechanism.feeder_pin");
    let mut state = FormState::new(mechanism_config);
    state.selected = 2;
    assert_eq!(
        clear_editing(&mut state, &mechanism, "150"),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.yaw_sensitivity, 150),
        other => panic!("unexpected config: {other:?}"),
    }

    let controls = infantry_controls_page();
    assert_eq!(controls.fields.len(), 13);
    let trigger_speed = controls
        .fields
        .iter()
        .position(|field| field.id == "controls.trigger_speed")
        .expect("trigger speed");
    let mut state = FormState::new(infantry_config());
    state.selected = trigger_speed;
    assert_eq!(
        clear_editing(&mut state, &controls, "5000"),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Infantry(value) => assert_eq!(value.trigger_speed, Some(5000)),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn debug_page_toggles_and_edits_items() {
    use pieblock_core::model::DebugDriveType;
    use pieblock_ui::debug_tests_page;

    let page = debug_tests_page();
    assert_eq!(page.id, "tests");
    assert_eq!(page.fields.len(), 40, "10 pins × 4 fields");
    let config = ProjectDocument::create(ProjectKind::Debug).config;
    let mut state = FormState::new(config);
    // 第 1 项：启用开关。
    assert_eq!(
        state.handle_key(&page, key(KeyCode::Enter)),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Debug(value) => assert!(value.tests[0].enabled),
        other => panic!("unexpected config: {other:?}"),
    }
    // 驱动类型选择：下一项。
    state.selected = 1;
    assert_eq!(
        state.handle_key(&page, key(KeyCode::Right)),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Debug(value) => {
            assert_eq!(value.tests[0].drive_type, Some(DebugDriveType::Servo));
        }
        other => panic!("unexpected config: {other:?}"),
    }
    // 测试时长：第 4 项（索引 3）。
    state.selected = 3;
    assert_eq!(
        clear_editing(&mut state, &page, "4500"),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Debug(value) => assert_eq!(value.tests[0].duration_ms, 4500),
        other => panic!("unexpected config: {other:?}"),
    }
}

#[test]
fn engineer_pwm_page_edits_frequency_and_buzzer() {
    use pieblock_ui::engineer_pwm_page;

    let config = engineer_config();
    let page = engineer_pwm_page(&config);
    assert!(page.fields.len() >= 3);
    assert_eq!(page.fields[0].id, "pwma");
    let mut state = FormState::new(config);
    assert_eq!(
        state.handle_key(&page, key(KeyCode::Enter)),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Engineer(value) => {
            assert!(value.pwm.pwma.is_some());
        }
        other => panic!("unexpected config: {other:?}"),
    }
    state.selected = 2;
    assert_eq!(
        state.handle_key(&page, key(KeyCode::Enter)),
        FormAction::Changed
    );
    match &state.config {
        ProjectConfig::Engineer(value) => assert!(value.pwm.buzzer_disabled),
        other => panic!("unexpected config: {other:?}"),
    }
    let pins = pieblock_ui::engineer_pins(&state.config);
    if !pins.is_empty() {
        let path = format!("pwm.{}.role", pins[0]);
        assert!(page.fields.iter().any(|field| field.path == path.as_str()));
    }
}

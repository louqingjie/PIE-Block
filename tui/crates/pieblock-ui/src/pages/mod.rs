//! 向导页面集合：按工程类型返回步骤页。

use pieblock_core::ProjectKind;

use crate::form::FormPage;

mod debug;
mod engineer;
mod infantry;
mod music;
mod remote;

pub use debug::debug_tests_page;
pub use engineer::{
    engineer_mappings_page, engineer_pins, engineer_pwm_page, engineer_strategy_page,
};
pub use infantry::{infantry_advanced_fields, infantry_controls_page, infantry_mechanism_page};
pub use music::music_page;
pub use remote::{DIRECTION_CHOICES, remote_page};

/// 工程类型对应的全部已移植页面。
#[must_use]
pub fn wizard_pages(
    kind: ProjectKind,
    config: &pieblock_core::model::ProjectConfig,
) -> Vec<FormPage> {
    match kind {
        ProjectKind::Infantry => vec![
            remote_page(kind),
            infantry_mechanism_page(config),
            infantry_controls_page(),
        ],
        ProjectKind::Engineer => vec![
            remote_page(kind),
            engineer_pwm_page(config),
            engineer_strategy_page(config),
            engineer_mappings_page(config),
        ],
        ProjectKind::Debug => vec![debug_tests_page()],
        ProjectKind::Music => vec![music_page(config)],
    }
}

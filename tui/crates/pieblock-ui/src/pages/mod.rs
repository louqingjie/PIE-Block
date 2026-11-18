//! 向导页面集合：按工程类型返回步骤页。

use pieblock_core::ProjectKind;

use crate::form::FormPage;

mod debug;
mod infantry;
mod remote;

pub use debug::debug_tests_page;
pub use infantry::{infantry_advanced_fields, infantry_controls_page, infantry_mechanism_page};
pub use remote::{DIRECTION_CHOICES, remote_page};

/// 工程类型对应的全部已移植页面。
#[must_use]
pub fn wizard_pages(kind: ProjectKind) -> Vec<FormPage> {
    match kind {
        ProjectKind::Infantry => vec![
            remote_page(kind),
            infantry_mechanism_page(),
            infantry_controls_page(),
        ],
        ProjectKind::Engineer => vec![remote_page(kind)],
        ProjectKind::Debug => vec![debug_tests_page()],
        ProjectKind::Music => Vec::new(),
    }
}

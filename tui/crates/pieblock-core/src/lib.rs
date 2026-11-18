//! PIE-Block 领域核心（TUI 移植）。
//!
//! 与 Flutter 版 `packages/pieblock_core` 保持行为一致：模型/JSON/迁移在这里，
//! 不依赖终端与 I/O。校验器与代码生成在 M1 后续提交补齐。
//!
//! M0 已包含：格式常量、工程类型与向导步骤；M1 增加 `.pieproj` 模型与迁移。

#[macro_use]
mod json;

pub mod codegen;
pub mod debug_cues;
pub mod document;
pub mod expression;
mod ids;
pub mod midi;
pub mod model;
pub mod music;
pub mod staff_firmware_c;
pub mod staff_glyphs;
pub mod staff_notation;
pub mod validation;

use serde::{Deserialize, Serialize};

pub use codegen::{GeneratedProgram, GenerationError, generate, generate_program};
pub use document::{DocumentError, GuideProgress, ProjectDocument};
pub use expression::{Expr, ExpressionDiagnostic, ExpressionType, ParsedExpression, parse};
pub use midi::{MidiCodec, MidiError, MidiFileData, MidiTrackData};
pub use music::{MusicSegment, MusicSoundingSpan, MusicTimeline};
pub use validation::{IssueSeverity, ValidationIssue, ValidationIssueKind, validate};

/// 当前 `.pieproj` 格式版本（与 Flutter 版 `ProjectDocument.formatVersion` 对齐）。
pub const FORMAT_VERSION: u32 = 23;

/// 可读取的最旧格式版本。
pub const OLDEST_SUPPORTED_FORMAT_VERSION: u32 = 17;

/// 工程类型；存档中使用稳定英文小写值。
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum ProjectKind {
    Infantry,
    Engineer,
    Debug,
    Music,
}

/// 一个向导步骤的稳定 ID 与中文标题。
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Step {
    pub id: &'static str,
    pub label: &'static str,
}

impl ProjectKind {
    pub const ALL: [Self; 4] = [Self::Infantry, Self::Engineer, Self::Debug, Self::Music];

    /// 界面展示用的中文类型名。
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Infantry => "步兵项目",
            Self::Engineer => "工程项目",
            Self::Debug => "调试项目",
            Self::Music => "音乐项目",
        }
    }

    /// 存档中使用的稳定英文名。
    #[must_use]
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Infantry => "infantry",
            Self::Engineer => "engineer",
            Self::Debug => "debug",
            Self::Music => "music",
        }
    }

    /// Dart `enumValue(ProjectKind.values, raw, infantry)` 语义。
    #[must_use]
    pub fn from_str_lenient(text: &str) -> Option<Self> {
        match text {
            "infantry" => Some(Self::Infantry),
            "engineer" => Some(Self::Engineer),
            "debug" => Some(Self::Debug),
            "music" => Some(Self::Music),
            _ => None,
        }
    }

    #[must_use]
    pub fn from_value(value: Option<&serde_json::Value>) -> Option<Self> {
        value
            .and_then(serde_json::Value::as_str)
            .and_then(Self::from_str_lenient)
    }

    #[must_use]
    pub fn from_value_or(value: Option<&serde_json::Value>, fallback: Self) -> Self {
        Self::from_value(value).unwrap_or(fallback)
    }

    /// 该类型工程的向导步骤（顺序即界面顺序）。
    #[must_use]
    pub const fn steps(self) -> &'static [Step] {
        match self {
            Self::Infantry => INFANTRY_STEPS,
            Self::Engineer => ENGINEER_STEPS,
            Self::Debug => DEBUG_STEPS,
            Self::Music => MUSIC_STEPS,
        }
    }
}

const INFANTRY_STEPS: &[Step] = &[
    Step {
        id: "remote",
        label: "遥控器与底盘",
    },
    Step {
        id: "mechanism",
        label: "云台与拨弹",
    },
    Step {
        id: "controls",
        label: "控制与摩擦轮",
    },
    Step {
        id: "review",
        label: "检查与摘要",
    },
    Step {
        id: "code",
        label: "生成代码",
    },
    Step {
        id: "deploy",
        label: "烧录",
    },
];

const ENGINEER_STEPS: &[Step] = &[
    Step {
        id: "remote",
        label: "遥控器与底盘",
    },
    Step {
        id: "pwm",
        label: "PWM 与引脚",
    },
    Step {
        id: "strategy",
        label: "模式切换",
    },
    Step {
        id: "mappings",
        label: "动作映射",
    },
    Step {
        id: "review",
        label: "检查与摘要",
    },
    Step {
        id: "code",
        label: "生成代码",
    },
    Step {
        id: "deploy",
        label: "烧录",
    },
];

const DEBUG_STEPS: &[Step] = &[
    Step {
        id: "tests",
        label: "测试序列",
    },
    Step {
        id: "review",
        label: "检查与摘要",
    },
    Step {
        id: "code",
        label: "生成代码",
    },
    Step {
        id: "deploy",
        label: "烧录",
    },
];

const MUSIC_STEPS: &[Step] = &[
    Step {
        id: "music",
        label: "钢琴卷帘",
    },
    Step {
        id: "review",
        label: "检查与摘要",
    },
    Step {
        id: "code",
        label: "生成代码",
    },
    Step {
        id: "deploy",
        label: "烧录",
    },
];

#[cfg(test)]
mod tests {
    use super::*;

    const PROJECT_KIND_STEP_COUNTS: [usize; 4] = [6, 7, 4, 4];

    #[test]
    fn step_counts_match_flutter_controller() {
        for kind in ProjectKind::ALL {
            let expected = PROJECT_KIND_STEP_COUNTS[kind as usize];
            assert_eq!(kind.steps().len(), expected, "kind={kind:?}");
        }
    }

    #[test]
    fn step_ids_are_stable_and_unique() {
        for kind in ProjectKind::ALL {
            let mut ids: Vec<_> = kind.steps().iter().map(|step| step.id).collect();
            ids.sort_unstable();
            ids.dedup();
            assert_eq!(ids.len(), kind.steps().len(), "kind={kind:?}");
        }
        for kind in [ProjectKind::Infantry, ProjectKind::Engineer] {
            assert_eq!(kind.steps().last().map(|step| step.id), Some("deploy"));
        }
    }

    #[test]
    fn project_kind_serializes_as_stable_lowercase() {
        for (kind, json) in [
            (ProjectKind::Infantry, "\"infantry\""),
            (ProjectKind::Engineer, "\"engineer\""),
            (ProjectKind::Debug, "\"debug\""),
            (ProjectKind::Music, "\"music\""),
        ] {
            assert_eq!(serde_json::to_string(&kind).unwrap(), json);
            let back: ProjectKind = serde_json::from_str(json).unwrap();
            assert_eq!(back, kind);
            assert_eq!(kind.as_str(), json.trim_matches('"'));
        }
    }

    #[test]
    fn format_version_is_23_and_reads_from_17() {
        assert_eq!(FORMAT_VERSION, 23);
        assert_eq!(OLDEST_SUPPORTED_FORMAT_VERSION, 17);
    }
}

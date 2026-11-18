//! 调试工程向导页：10 路固定引脚的测试序列。

use pieblock_core::model::{DebugConfig, DebugDriveType, ProjectConfig};

use crate::form::{Choice, FieldKind, FieldValue, FormField, FormPage};

/// 固定测试引脚顺序（与 Flutter `DEBUG_PINS` 一致）。
pub const DEBUG_PINS: [&str; 10] = [
    "P00", "P01", "P02", "P03", "P04", "P05", "P06", "P07", "P20", "P21",
];

const DRIVE_CHOICES: [Choice; 3] = [
    Choice {
        value: "motor",
        label: "电机（PWM）",
    },
    Choice {
        value: "servo",
        label: "舵机",
    },
    Choice {
        value: "friction",
        label: "摩擦轮",
    },
];

fn debug_of(config: &ProjectConfig) -> Option<&DebugConfig> {
    match config {
        ProjectConfig::Debug(value) => Some(value),
        _ => None,
    }
}

fn debug_mut(config: &mut ProjectConfig) -> Option<&mut DebugConfig> {
    match config {
        ProjectConfig::Debug(value) => Some(value),
        _ => None,
    }
}

fn item_value(
    config: &ProjectConfig,
    index: usize,
) -> Option<&pieblock_core::model::DebugTestItem> {
    debug_of(config).and_then(|debug| debug.tests.get(index))
}

fn item_value_mut(
    config: &mut ProjectConfig,
    index: usize,
) -> Option<&mut pieblock_core::model::DebugTestItem> {
    debug_mut(config).and_then(|debug| debug.tests.get_mut(index))
}

fn toggle(index: usize, field_path: &'static str, label: String) -> FormField {
    FormField {
        id: field_path,
        path: field_path,
        label,
        help: "启用后该测试项才会进入测试序列；可拖动排序在列表编辑器提供。",
        kind: FieldKind::Toggle,
        get: Box::new(move |config| {
            FieldValue::Bool(item_value(config, index).is_some_and(|item| item.enabled))
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Bool(enabled) = value {
                if let Some(item) = item_value_mut(config, index) {
                    item.enabled = enabled;
                }
            }
        }),
    }
}

fn drive(index: usize, field_path: &'static str, label: String) -> FormField {
    FormField {
        id: field_path,
        path: field_path,
        label,
        help: "驱动类型决定输出方式；摩擦轮使用固定 PWM 输出。",
        kind: FieldKind::Choice(&DRIVE_CHOICES),
        get: Box::new(move |config| {
            FieldValue::Choice(
                item_value(config, index)
                    .and_then(|item| item.drive_type)
                    .map_or_else(String::new, |kind| kind.as_str().to_owned()),
            )
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Choice(choice) = value {
                if let Some(item) = item_value_mut(config, index) {
                    item.drive_type = DebugDriveType::from_str_lenient(&choice);
                }
            }
        }),
    }
}

#[allow(clippy::too_many_arguments)]
fn number(
    index: usize,
    field_path: &'static str,
    label: String,
    help: &'static str,
    unit: &'static str,
    min: i64,
    max: i64,
    step: i64,
    duration: bool,
) -> FormField {
    FormField {
        id: field_path,
        path: field_path,
        label,
        help,
        kind: FieldKind::Number {
            min,
            max,
            step,
            unit,
        },
        get: Box::new(move |config| {
            FieldValue::Int(item_value(config, index).map_or(0, |item| {
                if duration {
                    item.duration_ms
                } else {
                    item.value.unwrap_or(0)
                }
            }))
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Int(number) = value {
                if let Some(item) = item_value_mut(config, index) {
                    if duration {
                        item.duration_ms = number;
                    } else {
                        item.value = Some(number);
                    }
                }
            }
        }),
    }
}

/// 「调试测试序列」页。
#[must_use]
pub fn debug_tests_page() -> FormPage {
    let mut fields = Vec::new();
    for (index, pin) in DEBUG_PINS.iter().enumerate() {
        let base = format!("tests.{index}");
        let enabled_path: &'static str = Box::leak(format!("{base}.enabled").into_boxed_str());
        let drive_path: &'static str = Box::leak(format!("{base}.drive_type").into_boxed_str());
        let value_path: &'static str = Box::leak(format!("{base}.value").into_boxed_str());
        let duration_path: &'static str = Box::leak(format!("{base}.duration_ms").into_boxed_str());
        fields.push(toggle(index, enabled_path, format!("{pin} 启用")));
        fields.push(drive(index, drive_path, format!("{pin} 驱动")));
        fields.push(number(
            index,
            value_path,
            format!("{pin} 值"),
            "电机/舵机为占空比（-10000–10000），摩擦轮为固定输出值。",
            "",
            -10000,
            10000,
            100,
            false,
        ));
        fields.push(number(
            index,
            duration_path,
            format!("{pin} 时长"),
            "该测试项的持续时间（毫秒），范围 0–60000。",
            "ms",
            0,
            60000,
            100,
            true,
        ));
    }
    FormPage {
        id: "tests",
        title: "第 1 步：调试测试序列",
        subtitle: "10 路固定引脚的测试项；方向键选择，Enter 编辑/切换。",
        fields,
    }
}

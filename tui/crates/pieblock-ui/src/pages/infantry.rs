//! 步兵专属页面：云台与拨弹机构、控制与摩擦轮。

use pieblock_core::model::{ArrowBehavior, Direction, FeedMode, FrictionMode, ProjectConfig};

use crate::form::{Choice, FieldKind, FieldValue, FormField, FormPage};

const ARROW_CHOICES: [Choice; 3] = [
    Choice {
        value: "move",
        label: "移动",
    },
    Choice {
        value: "sprint",
        label: "冲刺",
    },
    Choice {
        value: "other",
        label: "其它",
    },
];

const FEED_MODE_CHOICES: [Choice; 2] = [
    Choice {
        value: "blockingOpenLoop",
        label: "开环堵转",
    },
    Choice {
        value: "visualClosedLoop",
        label: "视觉闭环",
    },
];

const FRICTION_MODE_CHOICES: [Choice; 2] = [
    Choice {
        value: "brushlessEsc",
        label: "无刷电调",
    },
    Choice {
        value: "disabled",
        label: "禁用摩擦轮",
    },
];

fn infantry_of(config: &ProjectConfig) -> Option<&pieblock_core::model::InfantryConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(value),
        _ => None,
    }
}

fn infantry_mut(config: &mut ProjectConfig) -> Option<&mut pieblock_core::model::InfantryConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(value),
        _ => None,
    }
}

#[allow(clippy::too_many_arguments)]
fn number(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    unit: &'static str,
    min: i64,
    max: i64,
    step: i64,
    get: impl Fn(&ProjectConfig) -> i64 + 'static,
    set: impl Fn(&mut ProjectConfig, i64) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Number {
            min,
            max,
            step,
            unit,
        },
        get: Box::new(move |config| FieldValue::Int(get(config))),
        set: Box::new(move |config, value| {
            if let FieldValue::Int(number) = value {
                set(config, number);
            }
        }),
    }
}

#[allow(clippy::too_many_arguments)]
fn text(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    get: impl Fn(&ProjectConfig) -> Option<String> + 'static,
    set: impl Fn(&mut ProjectConfig, Option<String>) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Text {
            max_len: 24,
            placeholder: "（未设置）",
        },
        get: Box::new(move |config| FieldValue::Text(get(config).unwrap_or_default())),
        set: Box::new(move |config, value| {
            if let FieldValue::Text(text) = value {
                let value = text.trim();
                set(
                    config,
                    if value.is_empty() {
                        None
                    } else {
                        Some(value.to_owned())
                    },
                );
            }
        }),
    }
}

#[allow(clippy::too_many_arguments)]
fn choice(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    options: &'static [Choice],
    get: impl Fn(&ProjectConfig) -> String + 'static,
    set: impl Fn(&mut ProjectConfig, String) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Choice(options),
        get: Box::new(move |config| FieldValue::Choice(get(config))),
        set: Box::new(move |config, value| {
            if let FieldValue::Choice(choice) = value {
                set(config, choice);
            }
        }),
    }
}

fn direction_choices() -> &'static [Choice] {
    &crate::pages::DIRECTION_CHOICES
}

/// 「云台与拨弹机构」页（步兵）。
#[must_use]
pub fn infantry_mechanism_page() -> FormPage {
    let fields = vec![
        text(
            "mechanism.feeder_pin",
            "mechanism.feeder_pin",
            "拨弹电机 IO",
            "扩展板 IO 名称；主控板 MP03/MP74 只能连接舵机。",
            |config| infantry_of(config).and_then(|value| value.feeder_pin.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.feeder_pin = value;
                }
            },
        ),
        choice(
            "mechanism.feeder_direction",
            "mechanism.feeder_direction",
            "拨弹方向",
            "方向与预期相反时改为「反转」。",
            direction_choices(),
            |config| {
                infantry_of(config)
                    .and_then(|value| value.feeder_direction)
                    .map_or_else(String::new, |value| value.as_str().to_owned())
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.feeder_direction = Direction::from_str_lenient(&value);
                }
            },
        ),
        number(
            "gimbal.yaw.sensitivity",
            "gimbal.yaw.sensitivity",
            "Yaw 灵敏度",
            "10–200%，步长 5；只缩放云台 Yaw 轴跟随速度。",
            "%",
            10,
            200,
            5,
            |config| infantry_of(config).map_or(100, |value| value.yaw_sensitivity),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.yaw_sensitivity = value;
                }
            },
        ),
        number(
            "gimbal.pitch.sensitivity",
            "gimbal.pitch.sensitivity",
            "Pitch 灵敏度",
            "10–200%，步长 5；只缩放云台 Pitch 轴跟随速度。",
            "%",
            10,
            200,
            5,
            |config| infantry_of(config).map_or(100, |value| value.pitch_sensitivity),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.pitch_sensitivity = value;
                }
            },
        ),
    ];
    FormPage {
        id: "mechanism",
        title: "第 2 步：云台与拨弹机构",
        subtitle: "配置固定执行机构。主控板 MP03/MP74 只能连接舵机。",
        fields,
    }
}

/// 「控制与摩擦轮」页（步兵）。
#[must_use]
pub fn infantry_controls_page() -> FormPage {
    let fields = vec![
        choice(
            "controls.arrow_behavior",
            "controls.arrow_behavior",
            "方向键用途",
            "方向键用于底盘移动还是冲刺。",
            &ARROW_CHOICES,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.arrow_behavior)
                    .map_or_else(String::new, |value| value.as_str().to_owned())
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.arrow_behavior = ArrowBehavior::from_str_lenient(&value);
                }
            },
        ),
        choice(
            "controls.feed_mode",
            "controls.feed_mode",
            "拨弹模式",
            "开环堵转按固定时长转拨弹电机；视觉闭环仅在检测到弹丸时转动。",
            &FEED_MODE_CHOICES,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.feed_mode)
                    .map_or_else(String::new, |value| value.as_str().to_owned())
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.feed_mode = FeedMode::from_str_lenient(&value);
                }
            },
        ),
        text(
            "controls.trigger_key",
            "controls.trigger_key",
            "拨弹按键",
            "输入按键名（如 mouse_left）；留空表示未分配。",
            |config| infantry_of(config).and_then(|value| value.trigger_key.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.trigger_key = value;
                }
            },
        ),
        text(
            "controls.reverse_feed_key",
            "controls.reverse_feed_key",
            "反转拨弹键",
            "按住时反转拨弹电机，用于退弹。",
            |config| infantry_of(config).and_then(|value| value.reverse_feed_key.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.reverse_feed_key = value;
                }
            },
        ),
        number(
            "controls.trigger_speed",
            "controls.trigger_speed",
            "拨弹速度",
            "速度单位 duty，范围 0–10000。",
            "duty",
            0,
            10000,
            100,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.trigger_speed)
                    .unwrap_or(0)
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.trigger_speed = Some(value);
                }
            },
        ),
        number(
            "controls.trigger_time_ms",
            "controls.trigger_time_ms",
            "单发时长",
            "开环模式每次拨弹持续时间（毫秒），范围 0–5000。",
            "ms",
            0,
            5000,
            50,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.trigger_time_ms)
                    .unwrap_or(0)
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.trigger_time_ms = Some(value);
                }
            },
        ),
        choice(
            "controls.friction_mode",
            "controls.friction_mode",
            "摩擦轮模式",
            "无刷电调使用 P64/P66；禁用后不再占用这两个引脚。",
            &FRICTION_MODE_CHOICES,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.friction_mode)
                    .map_or_else(String::new, |value| value.as_str().to_owned())
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_mode = FrictionMode::from_str_lenient(&value);
                }
            },
        ),
        text(
            "controls.friction_key",
            "controls.friction_key",
            "摩擦轮按键",
            "按住时启动或停止摩擦轮。",
            |config| infantry_of(config).and_then(|value| value.friction_key.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_key = value;
                }
            },
        ),
        text(
            "controls.friction_up_key",
            "controls.friction_up_key",
            "摩擦轮加速键",
            "每次按下按步长提高摩擦轮转速。",
            |config| infantry_of(config).and_then(|value| value.friction_up_key.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_up_key = value;
                }
            },
        ),
        text(
            "controls.friction_down_key",
            "controls.friction_down_key",
            "摩擦轮减速键",
            "每次按下按步长降低摩擦轮转速。",
            |config| infantry_of(config).and_then(|value| value.friction_down_key.clone()),
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_down_key = value;
                }
            },
        ),
        number(
            "controls.friction_p64_max_duty",
            "controls.friction_p64_max_duty",
            "P64 最大转速",
            "P64 最大转速 duty，范围 0–10000。",
            "duty",
            0,
            10000,
            100,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.friction_p64_max_duty)
                    .unwrap_or(0)
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_p64_max_duty = Some(value);
                }
            },
        ),
        number(
            "controls.friction_p66_max_duty",
            "controls.friction_p66_max_duty",
            "P66 最大转速",
            "P66 最大转速 duty，范围 0–10000。",
            "duty",
            0,
            10000,
            100,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.friction_p66_max_duty)
                    .unwrap_or(0)
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_p66_max_duty = Some(value);
                }
            },
        ),
        number(
            "controls.friction_level_step",
            "controls.friction_level_step",
            "油门步长",
            "每次按加速/减速键调整的 duty 步长，范围 1–1000。",
            "duty",
            1,
            1000,
            10,
            |config| {
                infantry_of(config)
                    .and_then(|value| value.friction_level_step)
                    .unwrap_or(100)
            },
            |config, value| {
                if let Some(infantry) = infantry_mut(config) {
                    infantry.friction_level_step = Some(value);
                }
            },
        ),
    ];
    FormPage {
        id: "controls",
        title: "第 3 步：控制与摩擦轮",
        subtitle: "为不同动作分配独立按键，并设置安全范围内的速度。",
        fields,
    }
}

/// 保留给后续高级设置页（零点校准/蜂鸣器）。
#[must_use]
pub fn infantry_advanced_fields() -> Vec<FormField> {
    Vec::new()
}

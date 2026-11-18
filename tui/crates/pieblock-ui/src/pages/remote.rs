//! M4 向导页面定义（数据驱动）：与 Flutter `wizard_pages_*.dart` 字段对齐。
//!
//! 当前已移植「遥控器与底盘」页；后续提交补步兵/工程/调试/审查页。

use pieblock_core::ProjectKind;
use pieblock_core::model::{ChassisConfig, Direction, ProjectConfig, RemoteConfig, WheelConfig};

use crate::form::{Choice, FieldKind, FieldValue, FormField, FormPage};

/// 下拉选项：未设置/正转/反转。
pub const DIRECTION_CHOICES: [Choice; 3] = [
    Choice {
        value: "",
        label: "（未设置）",
    },
    Choice {
        value: "forward",
        label: "正转",
    },
    Choice {
        value: "reverse",
        label: "反转",
    },
];

fn remote_of(config: &ProjectConfig) -> Option<&RemoteConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(&value.remote),
        ProjectConfig::Engineer(value) => Some(&value.remote),
        ProjectConfig::Debug(_) | ProjectConfig::Music(_) => None,
    }
}

fn remote_mut(config: &mut ProjectConfig) -> Option<&mut RemoteConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(&mut value.remote),
        ProjectConfig::Engineer(value) => Some(&mut value.remote),
        ProjectConfig::Debug(_) | ProjectConfig::Music(_) => None,
    }
}

fn chassis_of(config: &ProjectConfig) -> Option<&ChassisConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(&value.chassis),
        ProjectConfig::Engineer(value) => Some(&value.chassis),
        ProjectConfig::Debug(_) | ProjectConfig::Music(_) => None,
    }
}

fn chassis_mut(config: &mut ProjectConfig) -> Option<&mut ChassisConfig> {
    match config {
        ProjectConfig::Infantry(value) => Some(&mut value.chassis),
        ProjectConfig::Engineer(value) => Some(&mut value.chassis),
        ProjectConfig::Debug(_) | ProjectConfig::Music(_) => None,
    }
}

fn wheel_of(config: &ProjectConfig, index: usize) -> Option<&WheelConfig> {
    let chassis = chassis_of(config)?;
    Some(match index {
        0 => &chassis.left_front,
        1 => &chassis.left_rear,
        2 => &chassis.right_front,
        _ => &chassis.right_rear,
    })
}

fn wheel_mut(config: &mut ProjectConfig, index: usize) -> Option<&mut WheelConfig> {
    let chassis = chassis_mut(config)?;
    Some(match index {
        0 => &mut chassis.left_front,
        1 => &mut chassis.left_rear,
        2 => &mut chassis.right_front,
        _ => &mut chassis.right_rear,
    })
}

const WHEELS: [(&str, &str, &str, &str); 4] = [
    (
        "左前轮",
        "chassis.left_front.pin",
        "左前轮方向",
        "chassis.left_front.direction",
    ),
    (
        "左后轮",
        "chassis.left_rear.pin",
        "左后轮方向",
        "chassis.left_rear.direction",
    ),
    (
        "右前轮",
        "chassis.right_front.pin",
        "右前轮方向",
        "chassis.right_front.direction",
    ),
    (
        "右后轮",
        "chassis.right_rear.pin",
        "右后轮方向",
        "chassis.right_rear.direction",
    ),
];

#[allow(clippy::too_many_arguments)]
fn number_field(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    unit: &'static str,
    min: i64,
    max: i64,
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
            step: 1,
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
fn toggle_field(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    get: impl Fn(&ProjectConfig) -> bool + 'static,
    set: impl Fn(&mut ProjectConfig, bool) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Toggle,
        get: Box::new(move |config| FieldValue::Bool(get(config))),
        set: Box::new(move |config, value| {
            if let FieldValue::Bool(flag) = value {
                set(config, flag);
            }
        }),
    }
}

#[allow(clippy::too_many_arguments)]
fn text_field(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    placeholder: &'static str,
    get: impl Fn(&ProjectConfig) -> Option<String> + 'static,
    set: impl Fn(&mut ProjectConfig, Option<String>) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Text {
            max_len: 16,
            placeholder,
        },
        get: Box::new(move |config| FieldValue::Text(get(config).unwrap_or_default())),
        set: Box::new(move |config, value| {
            if let FieldValue::Text(text) = value {
                set(
                    config,
                    if text.trim().is_empty() {
                        None
                    } else {
                        Some(text.trim().to_owned())
                    },
                );
            }
        }),
    }
}

#[allow(clippy::too_many_arguments)]
fn direction_field(
    id: &'static str,
    path: &'static str,
    label: &'static str,
    help: &'static str,
    get: impl Fn(&ProjectConfig) -> Option<Direction> + 'static,
    set: impl Fn(&mut ProjectConfig, Option<Direction>) + 'static,
) -> FormField {
    FormField {
        id,
        path,
        label: label.to_owned(),
        help,
        kind: FieldKind::Choice(&DIRECTION_CHOICES),
        get: Box::new(move |config| {
            FieldValue::Choice(
                get(config).map_or_else(String::new, |direction| direction.as_str().to_owned()),
            )
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Choice(choice) = value {
                set(config, Direction::from_str_lenient(&choice));
            }
        }),
    }
}

/// 「遥控器与底盘」页（步兵/工程共用；工程多一个底盘启用开关）。
#[must_use]
pub fn remote_page(kind: ProjectKind) -> FormPage {
    let mut fields = Vec::new();
    fields.push(number_field(
        "remote.channel",
        "remote.channel",
        "通道号",
        "通道号范围 0–125，必须与遥控器一致。",
        "",
        0,
        125,
        |config| {
            remote_of(config)
                .and_then(|remote| remote.channel)
                .unwrap_or(0)
        },
        |config, value| {
            if let Some(remote) = remote_mut(config) {
                remote.channel = Some(value);
            }
        },
    ));
    fields.push(number_field(
        "remote.deadzone",
        "remote.deadzone",
        "摇杆死区",
        "摇杆死区范围 0–2047，建议不超过 500。",
        "",
        0,
        2047,
        |config| {
            remote_of(config)
                .and_then(|remote| remote.deadzone)
                .unwrap_or(0)
        },
        |config, value| {
            if let Some(remote) = remote_mut(config) {
                remote.deadzone = Some(value);
            }
        },
    ));
    if kind == ProjectKind::Engineer {
        fields.push(toggle_field(
            "chassis.enabled",
            "chassis.enabled",
            "启用底盘控制",
            "关闭后使用动作行/表达式自行控制底盘输出。",
            |config| chassis_of(config).is_none_or(|chassis| chassis.enabled),
            |config, value| {
                if let Some(chassis) = chassis_mut(config) {
                    chassis.enabled = value;
                }
            },
        ));
    }
    for (index, (name, pin_path, direction_label, direction_path)) in WHEELS.iter().enumerate() {
        fields.push(text_field(
            pin_path,
            pin_path,
            name,
            "IO 名称同时标明扩展板 PWM 与方向引脚；同侧前后轮可以共用一个 IO。",
            "（未接线）",
            move |config| wheel_of(config, index).and_then(|wheel| wheel.pin.clone()),
            move |config, value| {
                if let Some(wheel) = wheel_mut(config, index) {
                    wheel.pin = value;
                }
            },
        ));
        fields.push(direction_field(
            direction_path,
            direction_path,
            direction_label,
            "电机实际转向与预期相反时改为「反转」。",
            move |config| wheel_of(config, index).and_then(|wheel| wheel.direction),
            move |config, value| {
                if let Some(wheel) = wheel_mut(config, index) {
                    wheel.direction = value;
                }
            },
        ));
    }
    fields.push(number_field(
        "chassis.normal_speed",
        "chassis.normal_speed",
        "普通速度",
        "速度单位 duty，范围 0–10000；建议普通速度不低于 4000。",
        "duty",
        0,
        10000,
        |config| {
            chassis_of(config)
                .and_then(|chassis| chassis.normal_speed)
                .unwrap_or(0)
        },
        |config, value| {
            if let Some(chassis) = chassis_mut(config) {
                chassis.normal_speed = Some(value);
            }
        },
    ));
    fields.push(number_field(
        "chassis.sprint_speed",
        "chassis.sprint_speed",
        "冲刺速度",
        "冲刺速度范围 0–10000；建议不低于 9000，未启用冲刺时不参与控制。",
        "duty",
        0,
        10000,
        |config| {
            chassis_of(config)
                .and_then(|chassis| chassis.sprint_speed)
                .unwrap_or(0)
        },
        |config, value| {
            if let Some(chassis) = chassis_mut(config) {
                chassis.sprint_speed = Some(value);
            }
        },
    ));
    fields.push(number_field(
        "chassis.turn_sensitivity",
        "chassis.turn_sensitivity",
        "转向灵敏度",
        "10–200%，只缩放左右转向量；高于 150% 时可能与前后移动叠加超出上限。",
        "%",
        10,
        200,
        |config| chassis_of(config).map_or(100, |chassis| chassis.turn_sensitivity),
        |config, value| {
            if let Some(chassis) = chassis_mut(config) {
                chassis.turn_sensitivity = value;
            }
        },
    ));
    fields.push(toggle_field(
        "chassis.sprint_enabled",
        "chassis.sprint_enabled",
        "左摇杆冲刺",
        "按下左摇杆启用冲刺。",
        |config| chassis_of(config).is_some_and(|chassis| chassis.sprint_enabled),
        |config, value| {
            if let Some(chassis) = chassis_mut(config) {
                chassis.sprint_enabled = value;
            }
        },
    ));
    fields.push(toggle_field(
        "chassis.turn_reversed",
        "chassis.turn_reversed",
        "反转左右转向",
        "前后移动正常，但左右操控相反时启用。",
        |config| chassis_of(config).is_some_and(|chassis| chassis.turn_reversed),
        |config, value| {
            if let Some(chassis) = chassis_mut(config) {
                chassis.turn_reversed = value;
            }
        },
    ));
    FormPage {
        id: "remote",
        title: "第 1 步：遥控器与底盘",
        subtitle: "先确认通信参数和四轮接线，后续页面会据此检查 IO 冲突。",
        fields,
    }
}

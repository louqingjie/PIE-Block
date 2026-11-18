//! 工程机器人向导页：PWM 与引脚。

use pieblock_core::model::{PinRole, ProjectConfig, PwmFrequency, PwmGroupConfig};

use crate::form::{Choice, FieldKind, FieldValue, FormField, FormPage};

const PWM_FREQUENCY_CHOICES: [Choice; 2] = [
    Choice {
        value: "hz50",
        label: "50 Hz（舵机）",
    },
    Choice {
        value: "hz10000",
        label: "10 kHz（电机）",
    },
];

const PIN_ROLE_CHOICES: [Choice; 6] = [
    Choice {
        value: "servo",
        label: "舵机",
    },
    Choice {
        value: "motor",
        label: "电机",
    },
    Choice {
        value: "friction",
        label: "摩擦轮",
    },
    Choice {
        value: "jitterMotor",
        label: "抖动电机",
    },
    Choice {
        value: "unused",
        label: "未使用",
    },
    Choice {
        value: "",
        label: "（未设置）",
    },
];

fn engineer_pwm(config: &ProjectConfig) -> Option<&PwmGroupConfig> {
    match config {
        ProjectConfig::Engineer(value) => Some(&value.pwm),
        _ => None,
    }
}

fn engineer_pwm_mut(config: &mut ProjectConfig) -> Option<&mut PwmGroupConfig> {
    match config {
        ProjectConfig::Engineer(value) => Some(&mut value.pwm),
        _ => None,
    }
}

/// 配置里出现过的引脚（角色/中位/限幅/摩擦轮/备注），按字典序。
#[must_use]
pub fn engineer_pins(config: &ProjectConfig) -> Vec<String> {
    let Some(pwm) = engineer_pwm(config) else {
        return Vec::new();
    };
    let mut pins: Vec<String> = pwm
        .pin_roles
        .keys()
        .chain(pwm.servo_mids.keys())
        .chain(pwm.servo_min_limits.keys())
        .chain(pwm.servo_max_limits.keys())
        .chain(pwm.friction_max_duties.keys())
        .chain(pwm.pin_notes.keys())
        .cloned()
        .collect();
    pins.sort();
    pins.dedup();
    pins
}

fn leak(text: String) -> &'static str {
    Box::leak(text.into_boxed_str())
}

fn frequency_field(id: &'static str, label: &'static str, channel: u8) -> FormField {
    FormField {
        id,
        path: leak(format!("pwm.{id}")),
        label: label.to_owned(),
        help: "PWM 组频率：舵机通常 50 Hz，电机通常 10 kHz。",
        kind: FieldKind::Choice(&PWM_FREQUENCY_CHOICES),
        get: Box::new(move |config| {
            FieldValue::Choice(
                engineer_pwm(config)
                    .and_then(|pwm| if channel == 0 { pwm.pwma } else { pwm.pwmb })
                    .map_or_else(String::new, |frequency| frequency.as_str().to_owned()),
            )
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Choice(choice) = value {
                let frequency = PwmFrequency::from_str_lenient(&choice);
                if let Some(pwm) = engineer_pwm_mut(config) {
                    if channel == 0 {
                        pwm.pwma = frequency;
                    } else {
                        pwm.pwmb = frequency;
                    }
                }
            }
        }),
    }
}

fn pin_field(pin: &str, suffix: &str, label: &str, column: u8, kind: FieldKind) -> FormField {
    let pin_owned = pin.to_owned();
    let path = leak(format!("pwm.{pin}.{suffix}"));
    let id = path;
    let pin_get = pin_owned.clone();
    let pin_set = pin_owned.clone();
    FormField {
        id,
        path,
        label: label.to_owned(),
        help: "引脚角色与参数；范围 -1000–1000（电压偏移）或 0–10000（占空比）。",
        kind,
        get: Box::new(move |config| {
            let Some(pwm) = engineer_pwm(config) else {
                return FieldValue::Int(0);
            };
            match column {
                0 => FieldValue::Choice(
                    pwm.role_of(&pin_get)
                        .map_or_else(String::new, |role| role.as_str().to_owned()),
                ),
                1 => FieldValue::Int(*pwm.servo_mids.get(&pin_get).unwrap_or(&0)),
                2 => FieldValue::Int(*pwm.servo_min_limits.get(&pin_get).unwrap_or(&0)),
                3 => FieldValue::Int(*pwm.servo_max_limits.get(&pin_get).unwrap_or(&0)),
                4 => FieldValue::Int(*pwm.friction_max_duties.get(&pin_get).unwrap_or(&0)),
                _ => FieldValue::Text(pwm.pin_notes.get(&pin_get).cloned().unwrap_or_default()),
            }
        }),
        set: Box::new(move |config, value| {
            let Some(pwm) = engineer_pwm_mut(config) else {
                return;
            };
            match (column, value) {
                (0, FieldValue::Choice(choice)) => {
                    if let Some(role) = PinRole::from_str_lenient(&choice) {
                        pwm.pin_roles.insert(pin_set.clone(), role);
                    } else {
                        pwm.pin_roles.remove(&pin_set);
                    }
                }
                (1, FieldValue::Int(number)) => {
                    pwm.servo_mids.insert(pin_set.clone(), number);
                }
                (2, FieldValue::Int(number)) => {
                    pwm.servo_min_limits.insert(pin_set.clone(), number);
                }
                (3, FieldValue::Int(number)) => {
                    pwm.servo_max_limits.insert(pin_set.clone(), number);
                }
                (4, FieldValue::Int(number)) => {
                    pwm.friction_max_duties.insert(pin_set.clone(), number);
                }
                (5, FieldValue::Text(text)) => {
                    if text.trim().is_empty() {
                        pwm.pin_notes.remove(&pin_set);
                    } else {
                        pwm.pin_notes
                            .insert(pin_set.clone(), text.trim().to_owned());
                    }
                }
                _ => {}
            }
        }),
    }
}

/// 「PWM 与引脚」页（工程）。
#[must_use]
pub fn engineer_pwm_page(config: &ProjectConfig) -> FormPage {
    let mut fields = vec![
        frequency_field("pwma", "PWMA 组频率", 0),
        frequency_field("pwmb", "PWMB 组频率", 1),
        FormField {
            id: "pwm.buzzer_disabled",
            path: "pwm.buzzer_disabled",
            label: "蜂鸣器禁用".to_owned(),
            help: "禁用后 P33 蜂鸣器不参与提示音输出。",
            kind: FieldKind::Toggle,
            get: Box::new(|config| {
                FieldValue::Bool(engineer_pwm(config).is_some_and(|pwm| pwm.buzzer_disabled))
            }),
            set: Box::new(|config, value| {
                if let FieldValue::Bool(flag) = value {
                    if let Some(pwm) = engineer_pwm_mut(config) {
                        pwm.buzzer_disabled = flag;
                    }
                }
            }),
        },
    ];
    for pin in engineer_pins(config) {
        fields.push(pin_field(
            &pin,
            "role",
            &format!("{pin} 角色"),
            0,
            FieldKind::Choice(&PIN_ROLE_CHOICES),
        ));
        for (suffix, label, column, max, step) in [
            ("servo_mid", "舵机中位", 1_i64, 1000_i64, 10_i64),
            ("servo_min", "舵机下限", 2, 1000, 10),
            ("servo_max", "舵机上限", 3, 1000, 10),
            ("friction_max_duty", "摩擦轮最大 duty", 4, 10000, 100),
        ] {
            fields.push(pin_field(
                &pin,
                suffix,
                &format!("{pin} {label}"),
                u8::try_from(column).unwrap_or(0),
                FieldKind::Number {
                    min: if column == 4 { 0 } else { -max },
                    max,
                    step,
                    unit: if column == 4 { "duty" } else { "" },
                },
            ));
        }
        fields.push(pin_field(
            &pin,
            "note",
            &format!("{pin} 备注"),
            5,
            FieldKind::Text {
                max_len: 24,
                placeholder: "（无备注）",
            },
        ));
    }
    FormPage {
        id: "pwm",
        title: "第 3 步：PWM 与引脚",
        subtitle: "配置 PWM 组频率与每个引脚的输出角色、舵机中位/限幅与摩擦轮占空比。",
        fields,
    }
}

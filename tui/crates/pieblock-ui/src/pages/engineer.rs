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

const STRATEGY_CHOICES: [Choice; 2] = [
    Choice {
        value: "cycle",
        label: "循环切换",
    },
    Choice {
        value: "direct",
        label: "数字直选",
    },
];

fn engineer_mode_count(config: &ProjectConfig) -> usize {
    match config {
        ProjectConfig::Engineer(value) => value.modes.len(),
        _ => 0,
    }
}

/// 「策略与模式」页（工程）：模式数量、切换策略/按键、保留底盘开关。
#[must_use]
pub fn engineer_strategy_page(config: &ProjectConfig) -> FormPage {
    let mut fields: Vec<FormField> = Vec::new();
    fields.push(FormField {
        id: "modes.count",
        path: "modes.count",
        label: "模式数量".to_owned(),
        help: "工程模式数量，范围 1–4；新增模式在「动作映射」页配置。",
        kind: FieldKind::Number {
            min: 1,
            max: 4,
            step: 1,
            unit: "",
        },
        get: Box::new(|config| {
            FieldValue::Int(match config {
                ProjectConfig::Engineer(value) => value.mode_count.unwrap_or(2),
                _ => 1,
            })
        }),
        set: Box::new(|config, value| {
            if let (ProjectConfig::Engineer(engineer), FieldValue::Int(number)) = (config, value) {
                engineer.mode_count = Some(number);
            }
        }),
    });
    fields.push(FormField {
        id: "modes.switch_strategy",
        path: "modes.switch_strategy",
        label: "切换策略".to_owned(),
        help: "循环切换用一个按键轮换模式；数字直选为每个模式分配数字键。",
        kind: FieldKind::Choice(&STRATEGY_CHOICES),
        get: Box::new(|config| {
            FieldValue::Choice(match config {
                ProjectConfig::Engineer(value) => value
                    .switch_strategy
                    .map_or_else(String::new, |strategy| strategy.as_str().to_owned()),
                _ => String::new(),
            })
        }),
        set: Box::new(|config, value| {
            if let (ProjectConfig::Engineer(engineer), FieldValue::Choice(choice)) = (config, value)
            {
                engineer.switch_strategy =
                    pieblock_core::model::SwitchStrategy::from_str_lenient(&choice);
            }
        }),
    });
    fields.push(FormField {
        id: "modes.switch_key",
        path: "modes.switch_key",
        label: "循环切换键".to_owned(),
        help: "循环策略时使用的数字遥控按键，如 NUM_1。",
        kind: FieldKind::Text {
            max_len: 16,
            placeholder: "（未设置）",
        },
        get: Box::new(|config| {
            FieldValue::Text(match config {
                ProjectConfig::Engineer(value) => value.mode_switch_key.clone().unwrap_or_default(),
                _ => String::new(),
            })
        }),
        set: Box::new(|config, value| {
            if let (ProjectConfig::Engineer(engineer), FieldValue::Text(text)) = (config, value) {
                let text = text.trim();
                engineer.mode_switch_key = if text.is_empty() {
                    None
                } else {
                    Some(text.to_owned())
                };
            }
        }),
    });
    for index in 0..engineer_mode_count(config) {
        let key_path: &'static str = Box::leak(format!("modes.keys.{index}").into_boxed_str());
        let preserve_path: &'static str =
            Box::leak(format!("modes.{index}.preserve_chassis").into_boxed_str());
        fields.push(FormField {
            id: key_path,
            path: key_path,
            label: format!("模式 {} 按键", index + 1),
            help: "数字直选策略下该模式的数字按键，如 NUM_2。",
            kind: FieldKind::Text {
                max_len: 16,
                placeholder: "（未设置）",
            },
            get: Box::new(move |config| {
                FieldValue::Text(match config {
                    ProjectConfig::Engineer(value) => value
                        .mode_keys
                        .get(index)
                        .cloned()
                        .flatten()
                        .unwrap_or_default(),
                    _ => String::new(),
                })
            }),
            set: Box::new(move |config, value| {
                if let (ProjectConfig::Engineer(engineer), FieldValue::Text(text)) = (config, value)
                {
                    while engineer.mode_keys.len() <= index {
                        engineer.mode_keys.push(None);
                    }
                    let text = text.trim();
                    engineer.mode_keys[index] = if text.is_empty() {
                        None
                    } else {
                        Some(text.to_owned())
                    };
                }
            }),
        });
        fields.push(FormField {
            id: preserve_path,
            path: preserve_path,
            label: format!("模式 {} 保留底盘", index + 1),
            help: "启用后该模式沿用上一模式的底盘输出；未启用底盘控制时不能开启。",
            kind: FieldKind::Toggle,
            get: Box::new(move |config| {
                FieldValue::Bool(match config {
                    ProjectConfig::Engineer(value) => value
                        .modes
                        .get(index)
                        .is_some_and(|mode| mode.preserve_chassis),
                    _ => false,
                })
            }),
            set: Box::new(move |config, value| {
                if let (ProjectConfig::Engineer(engineer), FieldValue::Bool(flag)) = (config, value)
                {
                    if let Some(mode) = engineer.modes.get_mut(index) {
                        mode.preserve_chassis = flag;
                    }
                }
            }),
        });
    }
    FormPage {
        id: "strategy",
        title: "第 3 步：策略与模式",
        subtitle: "配置工程模式数量、切换策略与每个模式的切换键/底盘保留。",
        fields,
    }
}

const INPUT_CHOICES: [Choice; 2] = [
    Choice {
        value: "remote",
        label: "遥控输入",
    },
    Choice {
        value: "unspecified",
        label: "未指定",
    },
];

const OUTPUT_CHOICES: [Choice; 3] = [
    Choice {
        value: "pin",
        label: "引脚输出",
    },
    Choice {
        value: "integer",
        label: "整数变量",
    },
    Choice {
        value: "rational",
        label: "小数变量",
    },
];

const CONTROL_MODES: [Choice; 6] = [
    Choice {
        value: "direct",
        label: "直接",
    },
    Choice {
        value: "incremental",
        label: "增量",
    },
    Choice {
        value: "speed",
        label: "速度",
    },
    Choice {
        value: "accelerate",
        label: "加速",
    },
    Choice {
        value: "single",
        label: "单次",
    },
    Choice {
        value: "continuous",
        label: "连续",
    },
];

fn engineer_action(
    config: &ProjectConfig,
    mode: usize,
    action: usize,
) -> Option<&pieblock_core::model::ActionMapping> {
    match config {
        ProjectConfig::Engineer(value) => value
            .modes
            .get(mode)
            .and_then(|mode| mode.actions.get(action)),
        _ => None,
    }
}

fn engineer_action_mut(
    config: &mut ProjectConfig,
    mode: usize,
    action: usize,
) -> Option<&mut pieblock_core::model::ActionMapping> {
    match config {
        ProjectConfig::Engineer(value) => value
            .modes
            .get_mut(mode)
            .and_then(|mode| mode.actions.get_mut(action)),
        _ => None,
    }
}

fn action_text_field(
    mode: usize,
    action: usize,
    suffix: &str,
    label: String,
    help: &'static str,
    getter: fn(&pieblock_core::model::ActionMapping) -> Option<String>,
    setter: fn(&mut pieblock_core::model::ActionMapping, Option<String>),
) -> FormField {
    let path: &'static str =
        Box::leak(format!("modes.{mode}.actions.{action}.{suffix}").into_boxed_str());
    FormField {
        id: path,
        path,
        label,
        help,
        kind: FieldKind::Text {
            max_len: 64,
            placeholder: "（未设置）",
        },
        get: Box::new(move |config| {
            FieldValue::Text(
                engineer_action(config, mode, action)
                    .and_then(getter)
                    .unwrap_or_default(),
            )
        }),
        set: Box::new(move |config, value| {
            if let FieldValue::Text(text) = value {
                if let Some(mapping) = engineer_action_mut(config, mode, action) {
                    let text = text.trim();
                    setter(
                        mapping,
                        if text.is_empty() {
                            None
                        } else {
                            Some(text.to_owned())
                        },
                    );
                }
            }
        }),
    }
}

/// 「动作映射」页（工程）：每个模式的现有动作行字段编辑。
#[must_use]
pub fn engineer_mappings_page(config: &ProjectConfig) -> FormPage {
    let mut fields: Vec<FormField> = Vec::new();
    let mode_count = match config {
        ProjectConfig::Engineer(value) => value.modes.len(),
        _ => 0,
    };
    for mode in 0..mode_count {
        let action_count = match config {
            ProjectConfig::Engineer(value) => {
                value.modes.get(mode).map_or(0, |mode| mode.actions.len())
            }
            _ => 0,
        };
        for action in 0..action_count {
            fields.push(action_text_field(
                mode,
                action,
                "key",
                format!("模式{} 动作{} 按键", mode + 1, action + 1),
                "遥控数字按键名，如 NUM_1 / mouse_left。",
                |mapping| mapping.key.clone(),
                |mapping, value| mapping.key = value,
            ));
            let input_path: &'static str =
                Box::leak(format!("modes.{mode}.actions.{action}.input_kind").into_boxed_str());
            fields.push(FormField {
                id: input_path,
                path: input_path,
                label: format!("模式{} 动作{} 输入", mode + 1, action + 1),
                help: "遥控输入或未指定。",
                kind: FieldKind::Choice(&INPUT_CHOICES),
                get: Box::new(move |config| {
                    FieldValue::Choice(
                        engineer_action(config, mode, action).map_or_else(String::new, |mapping| {
                            mapping.input_kind.as_str().to_owned()
                        }),
                    )
                }),
                set: Box::new(move |config, value| {
                    if let FieldValue::Choice(choice) = value {
                        if let Some(mapping) = engineer_action_mut(config, mode, action) {
                            mapping.input_kind =
                                pieblock_core::model::ActionInputKind::from_str_lenient(&choice)
                                    .unwrap_or(pieblock_core::model::ActionInputKind::Remote);
                        }
                    }
                }),
            });
            let output_path: &'static str =
                Box::leak(format!("modes.{mode}.actions.{action}.output_kind").into_boxed_str());
            fields.push(FormField {
                id: output_path,
                path: output_path,
                label: format!("模式{} 动作{} 输出", mode + 1, action + 1),
                help: "引脚 / 整数变量 / 小数变量。",
                kind: FieldKind::Choice(&OUTPUT_CHOICES),
                get: Box::new(move |config| {
                    FieldValue::Choice(
                        engineer_action(config, mode, action).map_or_else(String::new, |mapping| {
                            mapping.output_kind.as_str().to_owned()
                        }),
                    )
                }),
                set: Box::new(move |config, value| {
                    if let FieldValue::Choice(choice) = value {
                        if let Some(mapping) = engineer_action_mut(config, mode, action) {
                            mapping.output_kind =
                                pieblock_core::model::ActionOutputKind::from_str_lenient(&choice)
                                    .unwrap_or(pieblock_core::model::ActionOutputKind::Pin);
                        }
                    }
                }),
            });
            fields.push(action_text_field(
                mode,
                action,
                "pin",
                format!("模式{} 动作{} 引脚", mode + 1, action + 1),
                "输出引脚名；输出类型为引脚时使用。",
                |mapping| mapping.pin.clone(),
                |mapping, value| mapping.pin = value,
            ));
            fields.push(action_text_field(
                mode,
                action,
                "variable",
                format!("模式{} 动作{} 变量", mode + 1, action + 1),
                "输出变量名（integer/rational 输出）。",
                |mapping| mapping.variable_name.clone(),
                |mapping, value| mapping.variable_name = value,
            ));
            fields.push(action_text_field(
                mode,
                action,
                "expression",
                format!("模式{} 动作{} 表达式", mode + 1, action + 1),
                "可选表达式（如 LX*100）；语法错误会在审查页提示。",
                |mapping| mapping.expression.clone(),
                |mapping, value| mapping.expression = value,
            ));
            let mode_path: &'static str =
                Box::leak(format!("modes.{mode}.actions.{action}.mode").into_boxed_str());
            fields.push(FormField {
                id: mode_path,
                path: mode_path,
                label: format!("模式{} 动作{} 控制方式", mode + 1, action + 1),
                help: "直接/增量/速度/加速/单次/连续。",
                kind: FieldKind::Choice(&CONTROL_MODES),
                get: Box::new(move |config| {
                    FieldValue::Choice(engineer_action(config, mode, action).map_or_else(
                        String::new,
                        |mapping| {
                            mapping
                                .mode
                                .map_or_else(String::new, |mode| mode.as_str().to_owned())
                        },
                    ))
                }),
                set: Box::new(move |config, value| {
                    if let FieldValue::Choice(choice) = value {
                        if let Some(mapping) = engineer_action_mut(config, mode, action) {
                            mapping.mode =
                                pieblock_core::model::ControlMode::from_str_lenient(&choice);
                        }
                    }
                }),
            });
        }
    }
    FormPage {
        id: "mappings",
        title: "第 4 步：动作映射",
        subtitle: "编辑每个模式的现有动作行（按键、输入/输出类型、引脚/变量/表达式、控制方式）。",
        fields,
    }
}

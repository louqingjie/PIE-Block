//! 校验器（M1 移植中）。
//!
//! 已移植：公共机器人规则（遥控器/底盘）、步兵专属规则（云台/拨弹/摩擦轮/
//! 按键冲突/引脚占用与 PWMA 提醒）、调试工程。校验顺序与文案与
//! `packages/pieblock_core/lib/src/validator.dart` 一致；工程专属规则（含表达式
//! 相关规则）与音乐规则在后续提交补齐（golden 已生成）。

use serde_json::{Map, Value};

use crate::model::{
    ArrowBehavior, ChassisConfig, DEBUG_PINS, DebugConfig, DebugDriveType, Direction, DriveType,
    EXPANSION_PINS, FeedMode, FrictionMode, InfantryConfig, LEGACY_FRICTION_PINS, MAIN_SERVO_PINS,
    ProjectConfig, RemoteConfig, WheelConfig,
};

/// 调试工程摩擦轮测试项的占空比范围（与 Dart `Friction` 常量一致）。
const FRICTION_MIN_DUTY: i64 = 500;
const FRICTION_MAX_DUTY: i64 = 800;
const FRICTION_LOW_DUTY_WARNING: i64 = 650;

/// 四轮底盘的合法 IO 组合（两脚一组）。
const CHASSIS_PINS: &[&str] = &[
    "P60 P61", "P62 P63", "P74 P24", "P75 P25", "P76 P26", "P77 P27",
];

crate::string_enum!(IssueSeverity { Error => "error", Warning => "warning" });
crate::string_enum!(ValidationIssueKind { Required => "required", Invalid => "invalid" });

/// 一条校验问题；字段顺序与 Dart `ValidationIssue` 语义一致。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ValidationIssue {
    pub severity: IssueSeverity,
    pub kind: ValidationIssueKind,
    pub field_path: String,
    pub message: String,
    pub step_id: String,
}

impl ValidationIssue {
    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut map = Map::new();
        map.insert("severity".to_owned(), self.severity.to_json());
        map.insert("kind".to_owned(), self.kind.to_json());
        map.insert(
            "fieldPath".to_owned(),
            Value::String(self.field_path.clone()),
        );
        map.insert("message".to_owned(), Value::String(self.message.clone()));
        map.insert("stepId".to_owned(), Value::String(self.step_id.clone()));
        Value::Object(map)
    }
}

type Issues = Vec<ValidationIssue>;

fn push(
    issues: &mut Issues,
    severity: IssueSeverity,
    path: impl Into<String>,
    message: impl Into<String>,
    step: &str,
) {
    issues.push(ValidationIssue {
        severity,
        kind: ValidationIssueKind::Invalid,
        field_path: path.into(),
        message: message.into(),
        step_id: step.to_owned(),
    });
}

fn push_required(
    issues: &mut Issues,
    severity: IssueSeverity,
    path: impl Into<String>,
    message: impl Into<String>,
    step: &str,
) {
    issues.push(ValidationIssue {
        severity,
        kind: ValidationIssueKind::Required,
        field_path: path.into(),
        message: message.into(),
        step_id: step.to_owned(),
    });
}

/// 校验入口：与 Dart `ProjectValidator.validate` 相同的分派顺序。
#[must_use]
pub fn validate(config: &ProjectConfig) -> Issues {
    let mut issues = Issues::new();
    match config {
        ProjectConfig::Infantry(infantry) => {
            robot(
                &infantry.remote,
                &infantry.chassis,
                true,
                false,
                &mut issues,
            );
            infantry_rules(infantry, &mut issues);
        }
        ProjectConfig::Engineer(engineer) => {
            robot(
                &engineer.remote,
                &engineer.chassis,
                false,
                true,
                &mut issues,
            );
            // TODO(M1): _engineer 专属规则。
        }
        ProjectConfig::Debug(debug) => debug_rules(debug, &mut issues),
        ProjectConfig::Music(_music) => {
            // TODO(M1): 音乐规则（依赖 MusicTimeline/staff_notation 移植）。
        }
    }
    issues
}

#[allow(clippy::too_many_arguments)]
fn range(
    issues: &mut Issues,
    value: Option<i64>,
    min: i64,
    max: i64,
    path: &str,
    label: &str,
    step: &str,
    required: bool,
) {
    match value {
        None => {
            if required {
                push_required(
                    issues,
                    IssueSeverity::Error,
                    path,
                    format!("{label}尚未填写"),
                    step,
                );
            }
        }
        Some(value) if value < min || value > max => push(
            issues,
            IssueSeverity::Error,
            path,
            format!("{label}必须在 {min}–{max} 之间"),
            step,
        ),
        Some(_) => {}
    }
}

fn choice(issues: &mut Issues, value: Option<&str>, path: &str, label: &str, step: &str) {
    if value.is_none_or(str::is_empty) {
        push_required(
            issues,
            IssueSeverity::Error,
            path,
            format!("{label}尚未选择"),
            step,
        );
    }
}

fn robot(
    remote: &RemoteConfig,
    chassis: &ChassisConfig,
    infantry: bool,
    engineer: bool,
    issues: &mut Issues,
) {
    range(
        issues,
        remote.channel,
        0,
        125,
        "remote.channel",
        "遥控器通道号",
        "remote",
        true,
    );
    range(
        issues,
        remote.deadzone,
        0,
        2047,
        "remote.deadzone",
        "摇杆死区",
        "remote",
        true,
    );
    if let Some(deadzone) = remote.deadzone {
        if deadzone > 500 && deadzone <= 2047 {
            push(
                issues,
                IssueSeverity::Warning,
                "remote.deadzone",
                "摇杆死区大于 500，可能影响操控灵敏度",
                "remote",
            );
        }
    }
    if infantry && !chassis.enabled {
        push(
            issues,
            IssueSeverity::Error,
            "chassis.enabled",
            "步兵项目必须启用底盘控制",
            "remote",
        );
    }
    let engineer_chassis_disabled = engineer && !chassis.enabled;
    if engineer_chassis_disabled {
        return;
    }
    range(
        issues,
        chassis.normal_speed,
        0,
        10000,
        "chassis.normal_speed",
        "普通速度",
        "remote",
        true,
    );
    range(
        issues,
        chassis.sprint_speed,
        0,
        10000,
        "chassis.sprint_speed",
        "冲刺速度",
        "remote",
        chassis.sprint_enabled,
    );
    if let Some(speed) = chassis.normal_speed {
        if (0..4000).contains(&speed) {
            push(
                issues,
                IssueSeverity::Warning,
                "chassis.normal_speed",
                "普通速度低于 4000，底盘移动速度可能变慢",
                "remote",
            );
        }
    }
    if let Some(speed) = chassis.sprint_speed {
        if (0..9000).contains(&speed) {
            push(
                issues,
                IssueSeverity::Warning,
                "chassis.sprint_speed",
                "冲刺速度低于 9000，底盘移动速度可能变慢",
                "remote",
            );
        }
    }
    if let (Some(normal), Some(sprint)) = (chassis.normal_speed, chassis.sprint_speed) {
        if sprint < normal {
            push(
                issues,
                IssueSeverity::Warning,
                "chassis.sprint_speed",
                "冲刺速度低于普通速度，冲刺将无法生效",
                "remote",
            );
        }
    }
    range(
        issues,
        Some(chassis.turn_sensitivity),
        10,
        200,
        "chassis.turn_sensitivity",
        "转向灵敏度",
        "remote",
        true,
    );
    if chassis.turn_sensitivity > 150 && chassis.turn_sensitivity <= 200 {
        push(
            issues,
            IssueSeverity::Warning,
            "chassis.turn_sensitivity",
            "转向灵敏度高于 150%，与前后移动叠加后轮速可能超出 duty 上限",
            "remote",
        );
    }
    chassis_rules(chassis, issues);
}

struct WheelEntry<'a> {
    path: &'static str,
    label: &'static str,
    wheel: &'a WheelConfig,
    side: &'static str,
}

struct PinGroupEntry {
    path: &'static str,
    label: &'static str,
    side: &'static str,
    direction: Option<Direction>,
}

fn chassis_rules(chassis: &ChassisConfig, issues: &mut Issues) {
    let wheels = [
        WheelEntry {
            path: "chassis.left_front",
            label: "左前轮",
            wheel: &chassis.left_front,
            side: "left",
        },
        WheelEntry {
            path: "chassis.left_rear",
            label: "左后轮",
            wheel: &chassis.left_rear,
            side: "left",
        },
        WheelEntry {
            path: "chassis.right_front",
            label: "右前轮",
            wheel: &chassis.right_front,
            side: "right",
        },
        WheelEntry {
            path: "chassis.right_rear",
            label: "右后轮",
            wheel: &chassis.right_rear,
            side: "right",
        },
    ];

    let mut by_pin: Vec<(String, Vec<PinGroupEntry>)> = Vec::new();
    for wheel in wheels {
        let pin_path = format!("{}.pin", wheel.path);
        let direction_path = format!("{}.direction", wheel.path);
        choice(
            issues,
            wheel.wheel.pin.as_deref(),
            &pin_path,
            &format!("{} IO", wheel.label),
            "remote",
        );
        choice(
            issues,
            wheel.wheel.direction.map(Direction::as_str),
            &direction_path,
            &format!("{}方向", wheel.label),
            "remote",
        );
        if let Some(pin) = &wheel.wheel.pin {
            if !CHASSIS_PINS.contains(&pin.as_str()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    &pin_path,
                    format!("{}使用了非法 IO", wheel.label),
                    "remote",
                );
            }
        }
        let normalized = normalize_pin(wheel.wheel.pin.as_deref());
        if !normalized.is_empty() {
            let entry = PinGroupEntry {
                path: wheel.path,
                label: wheel.label,
                side: wheel.side,
                direction: wheel.wheel.direction,
            };
            if let Some(group) = by_pin.iter_mut().find(|(pin, _)| *pin == normalized) {
                group.1.push(entry);
            } else {
                by_pin.push((normalized, vec![entry]));
            }
        }
    }

    for (_, entries) in by_pin.iter().filter(|(_, entries)| entries.len() > 1) {
        let same_side = entries.iter().all(|entry| entry.side == entries[0].side);
        if same_side {
            let directions: Vec<Direction> =
                entries.iter().filter_map(|entry| entry.direction).collect();
            let mut distinct: Vec<Direction> = Vec::new();
            for direction in directions {
                if !distinct.contains(&direction) {
                    distinct.push(direction);
                }
            }
            if distinct.len() > 1 {
                let side = if entries[0].side == "left" {
                    "左"
                } else {
                    "右"
                };
                for entry in entries {
                    push(
                        issues,
                        IssueSeverity::Warning,
                        format!("{}.direction", entry.path),
                        format!("{side}侧两轮共用 IO 但方向不同，实际只有最后写入的方向生效"),
                        "remote",
                    );
                }
            }
        } else {
            let labels = entries
                .iter()
                .map(|entry| entry.label)
                .collect::<Vec<_>>()
                .join("、");
            for entry in entries {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{}.pin", entry.path),
                    format!("{labels} 不能跨侧共用同一 IO"),
                    "remote",
                );
            }
        }
    }
}

fn normalize_pin(pin: Option<&str>) -> String {
    pin.and_then(|pin| pin.split(' ').next())
        .unwrap_or_default()
        .to_owned()
}

fn debug_rules(config: &DebugConfig, issues: &mut Issues) {
    if config.tests.is_empty() || !config.tests.iter().any(|item| item.enabled) {
        push_required(
            issues,
            IssueSeverity::Error,
            "tests",
            "至少启用一个调试项目",
            "tests",
        );
    }
    let mut seen: Vec<&str> = Vec::new();
    for (index, item) in config.tests.iter().enumerate() {
        let base = format!("tests.{index}");
        if !DEBUG_PINS.contains(&item.pin.as_str()) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{base}.pin"),
                "调试引脚无效",
                "tests",
            );
        }
        seen.push(item.pin.as_str());
        if !item.enabled {
            continue;
        }
        choice(
            issues,
            item.drive_type.map(DebugDriveType::as_str),
            &format!("{base}.drive_type"),
            &format!("{} 驱动类型", item.pin),
            "tests",
        );
        let drive = item.drive_type;
        if MAIN_SERVO_PINS.contains(&item.pin.as_str())
            && drive.is_some()
            && drive != Some(DebugDriveType::Servo)
        {
            push(
                issues,
                IssueSeverity::Error,
                format!("{base}.drive_type"),
                format!("{} 仅支持舵机", item.pin),
                "tests",
            );
        }
        if drive == Some(DebugDriveType::Friction) && !matches!(item.pin.as_str(), "P64" | "P66") {
            push(
                issues,
                IssueSeverity::Error,
                format!("{base}.drive_type"),
                "只有 P64/P66 支持摩擦轮",
                "tests",
            );
        }
        match drive {
            Some(DebugDriveType::Motor) => {
                range(
                    issues,
                    item.value,
                    -10000,
                    10000,
                    &format!("{base}.value"),
                    &format!("{} 电机速度", item.pin),
                    "tests",
                    true,
                );
                range(
                    issues,
                    Some(item.duration_ms),
                    1000,
                    30000,
                    &format!("{base}.duration_ms"),
                    &format!("{} 测试时长", item.pin),
                    "tests",
                    true,
                );
            }
            Some(DebugDriveType::Servo) => {
                range(
                    issues,
                    item.value,
                    -90,
                    90,
                    &format!("{base}.value"),
                    &format!("{} 舵机角度", item.pin),
                    "tests",
                    true,
                );
                range(
                    issues,
                    Some(item.duration_ms),
                    1000,
                    30000,
                    &format!("{base}.duration_ms"),
                    &format!("{} 测试时长", item.pin),
                    "tests",
                    true,
                );
            }
            Some(DebugDriveType::Friction) => {
                range(
                    issues,
                    item.value,
                    FRICTION_MIN_DUTY,
                    FRICTION_MAX_DUTY,
                    &format!("{base}.value"),
                    &format!("{} 摩擦轮目标转速", item.pin),
                    "tests",
                    true,
                );
                if let Some(value) = item.value {
                    if value < FRICTION_LOW_DUTY_WARNING {
                        push(
                            issues,
                            IssueSeverity::Warning,
                            format!("{base}.value"),
                            format!(
                                "{} 摩擦轮目标转速低于 {FRICTION_LOW_DUTY_WARNING}，可能带不动摩擦轮，观察不到有效结论",
                                item.pin
                            ),
                            "tests",
                        );
                    }
                }
            }
            None => {}
        }
    }
    if !DEBUG_PINS.iter().all(|pin| seen.contains(pin)) {
        push(
            issues,
            IssueSeverity::Error,
            "tests",
            "调试序列必须包含全部十个固定引脚",
            "tests",
        );
    }
}

// ---------------------------------------------------------------------------
// 步兵专属规则
// ---------------------------------------------------------------------------

const DIGITAL_REMOTE_KEYS: &[&str] = &["E", "↑", "↓", "←", "→", "A", "B", "C", "D", "LC", "RC"];
/// 步兵固定 50Hz 的 PWMA 引脚；电机落在这里会给“可能一卡一卡”提醒。
const PWMA_MOTOR_PINS: &[&str] = &["P60", "P62", "P64", "P66"];
/// 步兵舵机可选引脚（PWMA 四路 + 主控板舵机口）。
const INFANTRY_SERVO_PINS: &[&str] = &["P60", "P62", "P64", "P66", "MP03", "MP74"];

fn axis_path(yaw: bool, index: usize, field: &str) -> String {
    format!(
        "gimbal.{}.{index}.{field}",
        if yaw { "yaw" } else { "pitch" }
    )
}

fn axis_label(yaw: bool, index: usize) -> String {
    let name = if yaw { "Yaw" } else { "Pitch" };
    if index == 0 {
        format!("{name} 轴")
    } else {
        format!("{name} 轴 {}", index + 1)
    }
}

fn digital_key(issues: &mut Issues, key: Option<&str>, path: &str, label: &str) {
    if let Some(key) = key {
        if !DIGITAL_REMOTE_KEYS.contains(&key) {
            push(
                issues,
                IssueSeverity::Error,
                path,
                format!("{label}必须使用数字按键，不能使用摇杆轴"),
                "controls",
            );
        }
    }
}

#[allow(clippy::too_many_arguments)]
fn servo_travel_limits(
    issues: &mut Issues,
    mid: i64,
    min_limit: Option<i64>,
    max_limit: Option<i64>,
    min_path: &str,
    max_path: &str,
    ccw_label: &str,
    cw_label: &str,
    step: &str,
) {
    range(
        issues,
        max_limit,
        0,
        90 - mid,
        max_path,
        ccw_label,
        step,
        false,
    );
    range(
        issues,
        min_limit.map(|value| -value),
        0,
        90 + mid,
        min_path,
        cw_label,
        step,
        false,
    );
}

fn infantry_rules(config: &InfantryConfig, issues: &mut Issues) {
    choice(
        issues,
        config.feeder_pin.as_deref(),
        "mechanism.feeder_pin",
        "拨弹电机 IO",
        "mechanism",
    );
    choice(
        issues,
        config.feeder_direction.map(Direction::as_str),
        "mechanism.feeder_direction",
        "拨弹电机方向",
        "mechanism",
    );
    infantry_axis(config, true, issues);
    infantry_axis(config, false, issues);

    choice(
        issues,
        config.arrow_behavior.map(ArrowBehavior::as_str),
        "controls.arrow_behavior",
        "方向键用途",
        "controls",
    );
    choice(
        issues,
        config.feed_mode.map(FeedMode::as_str),
        "controls.feed_mode",
        "拨弹模式",
        "controls",
    );
    choice(
        issues,
        config.trigger_key.as_deref(),
        "controls.trigger_key",
        "扳机键",
        "controls",
    );
    range(
        issues,
        config.trigger_speed,
        0,
        10000,
        "controls.trigger_speed",
        "拨弹速度",
        "controls",
        true,
    );
    digital_key(
        issues,
        config.trigger_key.as_deref(),
        "controls.trigger_key",
        "扳机键",
    );
    if let Some(reverse) = config.reverse_feed_key.as_deref() {
        digital_key(
            issues,
            Some(reverse),
            "controls.reverse_feed_key",
            "反向拨弹键",
        );
    }
    if config.feed_mode == Some(FeedMode::BlockingOpenLoop) {
        range(
            issues,
            config.trigger_time_ms,
            0,
            65535,
            "controls.trigger_time_ms",
            "拨弹时长",
            "controls",
            true,
        );
        if config.trigger_time_ms.unwrap_or(0) > 1000 {
            push(
                issues,
                IssueSeverity::Warning,
                "controls.trigger_time_ms",
                "拨弹时间过长，单发期间底盘和云台会失去响应",
                "controls",
            );
        }
    }
    choice(
        issues,
        config.friction_mode.map(FrictionMode::as_str),
        "controls.friction_mode",
        "摩擦轮类型",
        "controls",
    );
    let friction_enabled = config.friction_mode == Some(FrictionMode::BrushlessEsc);
    if friction_enabled {
        for (path, label, key) in [
            (
                "controls.friction_key",
                "摩擦轮开关键",
                config.friction_key.as_deref(),
            ),
            (
                "controls.friction_up_key",
                "摩擦轮增速键",
                config.friction_up_key.as_deref(),
            ),
            (
                "controls.friction_down_key",
                "摩擦轮减速键",
                config.friction_down_key.as_deref(),
            ),
        ] {
            choice(issues, key, path, label, "controls");
            digital_key(issues, key, path, label);
        }
        for (path, label, max_duty) in [
            (
                "controls.friction_p64_max_duty",
                "P64 摩擦轮最大转速",
                config.friction_p64_max_duty,
            ),
            (
                "controls.friction_p66_max_duty",
                "P66 摩擦轮最大转速",
                config.friction_p66_max_duty,
            ),
        ] {
            range(
                issues,
                max_duty,
                FRICTION_MIN_DUTY,
                FRICTION_MAX_DUTY,
                path,
                label,
                "controls",
                true,
            );
        }
        range(
            issues,
            config.friction_level_step,
            1,
            100,
            "controls.friction_level_step",
            "摩擦轮油门步长",
            "controls",
            true,
        );
    }

    let mut key_entries: Vec<(&'static str, &'static str, Option<&str>)> = vec![(
        "controls.trigger_key",
        "扳机键",
        config.trigger_key.as_deref(),
    )];
    if config.reverse_feed_key.is_some() {
        key_entries.push((
            "controls.reverse_feed_key",
            "反向拨弹键",
            config.reverse_feed_key.as_deref(),
        ));
    }
    if friction_enabled {
        key_entries.extend([
            (
                "controls.friction_key",
                "摩擦轮开关键",
                config.friction_key.as_deref(),
            ),
            (
                "controls.friction_up_key",
                "摩擦轮增速键",
                config.friction_up_key.as_deref(),
            ),
            (
                "controls.friction_down_key",
                "摩擦轮减速键",
                config.friction_down_key.as_deref(),
            ),
        ]);
    }
    let mut by_key: Vec<(String, Vec<(&'static str, &'static str)>)> = Vec::new();
    for (path, label, key) in &key_entries {
        if let Some(key) = key {
            if let Some(group) = by_key.iter_mut().find(|(existing, _)| existing == key) {
                group.1.push((path, label));
            } else {
                by_key.push(((**key).to_owned(), vec![(path, label)]));
            }
        }
    }
    for (_, entries) in by_key.iter().filter(|(_, entries)| entries.len() > 1) {
        let labels = entries
            .iter()
            .map(|(_, label)| *label)
            .collect::<Vec<_>>()
            .join("、");
        for (path, _) in entries {
            push(
                issues,
                IssueSeverity::Error,
                *path,
                format!("{labels} 不能使用同一按键"),
                "controls",
            );
        }
    }
    if matches!(
        config.arrow_behavior,
        Some(ArrowBehavior::Move | ArrowBehavior::Sprint)
    ) {
        for (path, label, key) in &key_entries {
            if let Some(key) = key {
                if matches!(*key, "↑" | "↓" | "←" | "→") {
                    push(
                        issues,
                        IssueSeverity::Error,
                        *path,
                        format!("方向键已用于底盘，不能同时作为{label}"),
                        "controls",
                    );
                }
            }
        }
    }
    if config.chassis.sprint_enabled {
        for (path, label, key) in &key_entries {
            if *key == Some("LC") {
                push(
                    issues,
                    IssueSeverity::Error,
                    *path,
                    format!("LC 已用于底盘冲刺，不能同时作为{label}"),
                    "controls",
                );
            }
        }
    }
    if config.zero_enabled {
        for (path, label, key) in &key_entries {
            if *key == Some("RC") {
                push(
                    issues,
                    IssueSeverity::Error,
                    *path,
                    format!("RC 已用于云台归中，不能同时作为{label}"),
                    "controls",
                );
            }
        }
    }
    if config.arrow_behavior == Some(ArrowBehavior::Sprint) && config.chassis.sprint_speed.is_none()
    {
        push_required(
            issues,
            IssueSeverity::Error,
            "chassis.sprint_speed",
            "方向键用作冲刺时必须填写冲刺速度",
            "remote",
        );
    }
    infantry_pins(config, issues);
}

fn infantry_axis(config: &InfantryConfig, yaw: bool, issues: &mut Issues) {
    let name = if yaw { "Yaw" } else { "Pitch" };
    let sensitivity = if yaw {
        config.yaw_sensitivity
    } else {
        config.pitch_sensitivity
    };
    let sensitivity_path = format!("gimbal.{}.sensitivity", if yaw { "yaw" } else { "pitch" });
    range(
        issues,
        Some(sensitivity),
        10,
        200,
        &sensitivity_path,
        &format!("{name} 灵敏度"),
        "mechanism",
        true,
    );
    if sensitivity > 150 && sensitivity <= 200 {
        push(
            issues,
            IssueSeverity::Warning,
            &sensitivity_path,
            format!("{name} 灵敏度高于 150%，满杆时角度变化可能过快"),
            "mechanism",
        );
    }
    let actuators = if yaw { &config.yaw } else { &config.pitch };
    let servo_hints = INFANTRY_SERVO_PINS.join("/");
    for (index, actuator) in actuators.iter().enumerate() {
        let label = if actuators.len() == 1 {
            name.to_owned()
        } else {
            format!("{name} 执行器 {}", index + 1)
        };
        let path = |field: &str| axis_path(yaw, index, field);
        let drive_path = path("drive");
        let pin_path = path("pin");
        let direction_path = path("direction");
        choice(
            issues,
            actuator.drive.map(DriveType::as_str),
            &drive_path,
            &format!("{label} 驱动类型"),
            "mechanism",
        );
        choice(
            issues,
            actuator.pin.as_deref(),
            &pin_path,
            &format!("{label} IO"),
            "mechanism",
        );
        choice(
            issues,
            actuator.direction.map(Direction::as_str),
            &direction_path,
            &format!("{label} 方向"),
            "mechanism",
        );
        if actuator.drive == Some(DriveType::Servo) {
            let mid_path = path("mid_offset");
            range(
                issues,
                actuator.mid_offset,
                -90,
                90,
                &mid_path,
                &format!("{label} 归中偏移"),
                "mechanism",
                true,
            );
            if let Some(mid) = actuator.mid_offset {
                if (-90..=90).contains(&mid) {
                    servo_travel_limits(
                        issues,
                        mid,
                        actuator.min_limit,
                        actuator.max_limit,
                        &path("min_limit"),
                        &path("max_limit"),
                        &format!("{label} 逆时针限幅"),
                        &format!("{label} 顺时针限幅"),
                        "mechanism",
                    );
                }
            }
        }
        if let (Some(pin), Some(drive)) = (actuator.pin.as_deref(), actuator.drive) {
            let valid: &[&str] = if drive == DriveType::Servo {
                INFANTRY_SERVO_PINS
            } else {
                &EXPANSION_PINS
            };
            if !valid.contains(&pin) {
                let message = if drive == DriveType::Servo {
                    format!(
                        "{label} 不能使用 {pin}：P74~P77 固定 10000Hz 仅供电机，舵机请选 {servo_hints}"
                    )
                } else {
                    format!("{label} 不能使用 {pin}")
                };
                push(
                    issues,
                    IssueSeverity::Error,
                    &pin_path,
                    message,
                    "mechanism",
                );
            }
            if drive == DriveType::Motor && MAIN_SERVO_PINS.contains(&pin) {
                push(
                    issues,
                    IssueSeverity::Error,
                    &pin_path,
                    format!("{pin} 是主控板舵机口，不能驱动电机"),
                    "mechanism",
                );
            }
        }
    }
}

struct InfantryPinRef<'a> {
    path: String,
    label: String,
    pin: Option<&'a str>,
    group: &'static str,
    motor_role: bool,
}

/// (字段路径, 显示名, 分组)；分组与引脚共同决定“同侧共用/跨侧冲突”的判定。
type PinRef = (String, String, &'static str);

fn infantry_pins(config: &InfantryConfig, issues: &mut Issues) {
    let mut entries: Vec<InfantryPinRef> = vec![
        InfantryPinRef {
            path: "chassis.left_front.pin".to_owned(),
            label: "左前轮".to_owned(),
            pin: config.chassis.left_front.pin.as_deref(),
            group: "left",
            motor_role: true,
        },
        InfantryPinRef {
            path: "chassis.left_rear.pin".to_owned(),
            label: "左后轮".to_owned(),
            pin: config.chassis.left_rear.pin.as_deref(),
            group: "left",
            motor_role: true,
        },
        InfantryPinRef {
            path: "chassis.right_front.pin".to_owned(),
            label: "右前轮".to_owned(),
            pin: config.chassis.right_front.pin.as_deref(),
            group: "right",
            motor_role: true,
        },
        InfantryPinRef {
            path: "chassis.right_rear.pin".to_owned(),
            label: "右后轮".to_owned(),
            pin: config.chassis.right_rear.pin.as_deref(),
            group: "right",
            motor_role: true,
        },
        InfantryPinRef {
            path: "mechanism.feeder_pin".to_owned(),
            label: "拨弹电机".to_owned(),
            pin: config.feeder_pin.as_deref(),
            group: "feeder",
            motor_role: true,
        },
    ];
    for (yaw, actuators, group) in [(true, &config.yaw, "yaw"), (false, &config.pitch, "pitch")] {
        for (index, actuator) in actuators.iter().enumerate() {
            entries.push(InfantryPinRef {
                path: axis_path(yaw, index, "pin"),
                label: axis_label(yaw, index),
                pin: actuator.pin.as_deref(),
                group,
                motor_role: actuator.drive != Some(DriveType::Servo),
            });
        }
    }
    if config.friction_mode == Some(FrictionMode::BrushlessEsc) {
        for pin in LEGACY_FRICTION_PINS {
            entries.push(InfantryPinRef {
                path: "controls.friction_mode".to_owned(),
                label: "摩擦轮".to_owned(),
                pin: Some(pin),
                group: "friction",
                motor_role: false,
            });
        }
    }

    let mut by_pin: Vec<(String, Vec<PinRef>)> = Vec::new();
    for entry in &entries {
        let pin = normalize_pin(Some(entry.pin.unwrap_or_default()));
        if pin.is_empty() {
            continue;
        }
        if entry.motor_role && PWMA_MOTOR_PINS.contains(&pin.as_str()) {
            push(
                issues,
                IssueSeverity::Warning,
                &entry.path,
                format!("{}位于固定 50Hz 的 PWMA，电机可能一卡一卡", entry.label),
                if entry.path.starts_with("chassis.") {
                    "remote"
                } else {
                    "mechanism"
                },
            );
        }
        let value = (entry.path.clone(), entry.label.clone(), entry.group);
        if let Some(group) = by_pin.iter_mut().find(|(existing, _)| *existing == pin) {
            group.1.push(value);
        } else {
            by_pin.push((pin, vec![value]));
        }
    }
    for (pin, refs) in by_pin.iter().filter(|(_, refs)| refs.len() > 1) {
        let groups = refs.iter().map(|(_, _, group)| *group).collect::<Vec<_>>();
        let mut distinct: Vec<&str> = Vec::new();
        for group in groups {
            if !distinct.contains(&group) {
                distinct.push(group);
            }
        }
        if distinct.len() == 1 && matches!(distinct[0], "left" | "right") {
            continue;
        }
        if refs.iter().all(|(path, _, _)| path.starts_with("chassis.")) {
            continue;
        }
        let mut labels: Vec<&str> = Vec::new();
        for (_, label, _) in refs {
            if !labels.contains(&label.as_str()) {
                labels.push(label);
            }
        }
        let labels = labels.join("、");
        for (path, _, group) in refs {
            if *group == "friction" {
                continue;
            }
            push(
                issues,
                IssueSeverity::Error,
                path,
                format!("{pin} 同时被 {labels} 占用"),
                if path.starts_with("chassis.") {
                    "remote"
                } else if path.starts_with("controls.") {
                    "controls"
                } else {
                    "mechanism"
                },
            );
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn range_messages_match_dart() {
        let mut issues = Issues::new();
        range(
            &mut issues,
            None,
            0,
            125,
            "remote.channel",
            "遥控器通道号",
            "remote",
            true,
        );
        range(
            &mut issues,
            Some(999),
            0,
            125,
            "remote.channel",
            "遥控器通道号",
            "remote",
            true,
        );
        assert_eq!(issues[0].message, "遥控器通道号尚未填写");
        assert_eq!(issues[0].kind, ValidationIssueKind::Required);
        assert_eq!(issues[1].message, "遥控器通道号必须在 0–125 之间");
        assert_eq!(issues[1].kind, ValidationIssueKind::Invalid);
    }

    #[test]
    fn choice_treats_empty_string_as_missing() {
        let mut issues = Issues::new();
        choice(&mut issues, Some(""), "p", "左前轮 IO", "remote");
        assert_eq!(issues[0].message, "左前轮 IO尚未选择");
        assert_eq!(issues[0].kind, ValidationIssueKind::Required);
    }

    #[test]
    fn normalize_pin_takes_first_token() {
        assert_eq!(normalize_pin(Some("P60 P61")), "P60");
        assert_eq!(normalize_pin(Some("P60")), "P60");
        assert_eq!(normalize_pin(None), "");
    }
}

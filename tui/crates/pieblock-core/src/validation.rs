//! 校验器（M1 移植中）。
//!
//! 已移植：公共机器人规则（遥控器/底盘）、步兵专属规则（云台/拨弹/摩擦轮/
//! 按键冲突/引脚占用与 PWMA 提醒）、**工程专属规则（PWM 角色/频率/舵机限幅、
//! 模式策略、动作行矩阵、表达式与变量、按键动作表、摩擦轮安全控制）**、
//! 调试工程。校验顺序与文案与 `packages/pieblock_core/lib/src/validator.dart`
//! 一致；音乐规则（依赖 `music.dart` / `staff_notation.dart` 移植）在后续提交补齐。

use serde_json::{Map, Value};

use crate::expression::{ExpressionType, is_valid_variable_name, parse as parse_expression};
use crate::model::{
    ActionInputKind, ActionMapping, ActionOutputKind, ArrowBehavior, ChassisConfig, ControlMode,
    DEBUG_PINS, DebugConfig, DebugDriveType, Direction, DriveType, EXPANSION_PINS, EngineerConfig,
    EngineerModeConfig, EngineerPinCapabilities, FeedMode, Friction, FrictionMode, InfantryConfig,
    LEGACY_FRICTION_PINS, MAIN_SERVO_PINS, PinRole, ProjectConfig, PwmFrequency, RemoteConfig,
    SwitchStrategy, WheelConfig,
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
            engineer_rules(engineer, &mut issues);
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
const AXIS_REMOTE_INPUTS: &[&str] = &["LX", "LY", "RX", "RY"];
const REMOTE_KEYS: &[&str] = &[
    "E", "↑", "↓", "←", "→", "A", "B", "C", "D", "LC", "RC", "LX", "LY", "RX", "RY",
];
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

// ---------------------------------------------------------------------------
// 工程专属规则
// ---------------------------------------------------------------------------

fn engineer_role_label(role: PinRole) -> &'static str {
    match role {
        PinRole::Motor => "平滑电机",
        PinRole::Servo => "舵机",
        PinRole::Friction => "摩擦轮",
        PinRole::JitterMotor => "抖动电机",
        PinRole::Unused => "未使用",
    }
}

fn motor_role(role: PinRole) -> bool {
    matches!(
        role,
        PinRole::Motor | PinRole::Friction | PinRole::JitterMotor
    )
}

fn is_friction_mode(mode: Option<ControlMode>) -> bool {
    matches!(
        mode,
        Some(
            ControlMode::FrictionToggle
                | ControlMode::FrictionStep
                | ControlMode::FrictionContinuous
                | ControlMode::FrictionAxis
        )
    )
}

fn has_friction_control(config: &EngineerConfig) -> bool {
    let count = usize::try_from(config.mode_count.unwrap_or(0)).unwrap_or(0);
    config.modes.iter().take(count).any(|mode| {
        mode.actions
            .iter()
            .any(|action| is_friction_mode(action.mode))
    })
}

fn normalized_chassis_pins(chassis: &ChassisConfig) -> Vec<String> {
    [
        &chassis.left_front,
        &chassis.left_rear,
        &chassis.right_front,
        &chassis.right_rear,
    ]
    .into_iter()
    .map(|wheel| normalize_pin(wheel.pin.as_deref()))
    .collect()
}

fn engineer_rules(config: &EngineerConfig, issues: &mut Issues) {
    choice(
        issues,
        config.pwm.pwma.map(PwmFrequency::as_str),
        "pwm.pwma",
        "PWMA 初始化频率",
        "pwm",
    );
    choice(
        issues,
        config.pwm.pwmb.map(PwmFrequency::as_str),
        "pwm.pwmb",
        "PWMB 初始化频率",
        "pwm",
    );
    let chassis_enabled = config.chassis.enabled;
    let chassis_used: Vec<String> = if chassis_enabled {
        normalized_chassis_pins(&config.chassis)
    } else {
        Vec::new()
    };
    for (index, pin) in EXPANSION_PINS.iter().enumerate() {
        let role = config.pwm.pin_roles.get(*pin).copied();
        choice(
            issues,
            role.map(PinRole::as_str),
            &format!("pwm.pin_roles.{pin}"),
            &format!("{pin} 输出角色"),
            "pwm",
        );
        let role_supported =
            role.is_some_and(|role| EngineerPinCapabilities::supports_role(pin, role));
        if let Some(role) = role {
            if !role_supported {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("pwm.pin_roles.{pin}"),
                    format!("{pin} 不支持{}", engineer_role_label(role)),
                    "pwm",
                );
            }
            if chassis_used.iter().any(|used| used == pin) && !motor_role(role) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("pwm.pin_roles.{pin}"),
                    format!("{pin} 已用于底盘，输出角色必须是电机"),
                    "pwm",
                );
            }
        }
        let frequency = if index < 4 {
            config.pwm.pwma
        } else {
            config.pwm.pwmb
        };
        if role_supported {
            if let (Some(role), Some(frequency)) = (role, frequency) {
                let expected = if role == PinRole::Motor {
                    PwmFrequency::Hz10000
                } else {
                    PwmFrequency::Hz50
                };
                if role != PinRole::Unused && frequency != expected {
                    push(
                        issues,
                        IssueSeverity::Warning,
                        format!("pwm.pin_roles.{pin}"),
                        format!("{pin} 的输出角色与所在 PWM 组频率不匹配"),
                        "pwm",
                    );
                }
            }
        }
        if role == Some(PinRole::Servo) {
            range(
                issues,
                config.pwm.servo_mids.get(*pin).copied(),
                -90,
                90,
                &format!("pwm.servo_mids.{pin}"),
                &format!("{pin} 舵机中位偏移"),
                "pwm",
                true,
            );
            if let Some(mid) = config.pwm.servo_mids.get(*pin).copied() {
                if (-90..=90).contains(&mid) {
                    servo_travel_limits(
                        issues,
                        mid,
                        config.pwm.servo_min_limits.get(*pin).copied(),
                        config.pwm.servo_max_limits.get(*pin).copied(),
                        &format!("pwm.servo_min_limits.{pin}"),
                        &format!("pwm.servo_max_limits.{pin}"),
                        &format!("{pin} 舵机逆时针限幅"),
                        &format!("{pin} 舵机顺时针限幅"),
                        "pwm",
                    );
                }
            }
        }
    }
    for pin in MAIN_SERVO_PINS {
        let role = config.pwm.role_of(pin);
        if let Some(role) = role {
            if !EngineerPinCapabilities::supports_role(pin, role) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("pwm.pin_roles.{pin}"),
                    format!("{pin} 不支持{}", engineer_role_label(role)),
                    "pwm",
                );
            }
        }
        if role != Some(PinRole::Servo) {
            continue;
        }
        range(
            issues,
            config.pwm.servo_mids.get(pin).copied(),
            -90,
            90,
            &format!("pwm.servo_mids.{pin}"),
            &format!("{pin} 舵机中位偏移"),
            "pwm",
            true,
        );
        if let Some(mid) = config.pwm.servo_mids.get(pin).copied() {
            if (-90..=90).contains(&mid) {
                servo_travel_limits(
                    issues,
                    mid,
                    config.pwm.servo_min_limits.get(pin).copied(),
                    config.pwm.servo_max_limits.get(pin).copied(),
                    &format!("pwm.servo_min_limits.{pin}"),
                    &format!("pwm.servo_max_limits.{pin}"),
                    &format!("{pin} 舵机逆时针限幅"),
                    &format!("{pin} 舵机顺时针限幅"),
                    "pwm",
                );
            }
        }
    }

    for pin in EngineerPinCapabilities::ALL_OUTPUT_PINS {
        range(
            issues,
            config.pwm.friction_max_duties.get(pin).copied(),
            Friction::MIN_MAX_DUTY,
            Friction::MAX_MAX_DUTY,
            &format!("pwm.friction_max_duties.{pin}"),
            &format!("{pin} 摩擦轮满油转速"),
            "pwm",
            false,
        );
    }
    if has_friction_control(config) {
        let friction_pins: Vec<&str> = EngineerPinCapabilities::ALL_OUTPUT_PINS
            .iter()
            .copied()
            .filter(|pin| config.pwm.role_of(pin) == Some(PinRole::Friction))
            .collect();
        for pin in &friction_pins {
            if !config.pwm.friction_max_duties.contains_key(*pin) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("pwm.friction_max_duties.{pin}"),
                    format!("{pin} 摩擦轮满油转速尚未填写"),
                    "pwm",
                );
            }
        }
        let expansion_friction: Vec<&&str> = friction_pins
            .iter()
            .filter(|pin| EXPANSION_PINS.contains(*pin))
            .collect();
        if expansion_friction.iter().any(|pin| {
            EXPANSION_PINS
                .iter()
                .position(|item| item == *pin)
                .is_some_and(|index| index < 4)
        }) && config.pwm.pwma != Some(PwmFrequency::Hz50)
        {
            push(
                issues,
                IssueSeverity::Error,
                "pwm.pwma",
                "使用摩擦轮控制时 PWMA 必须为 50Hz",
                "pwm",
            );
        }
        if expansion_friction.iter().any(|pin| {
            EXPANSION_PINS
                .iter()
                .position(|item| item == *pin)
                .is_some_and(|index| index >= 4)
        }) && config.pwm.pwmb != Some(PwmFrequency::Hz50)
        {
            push(
                issues,
                IssueSeverity::Error,
                "pwm.pwmb",
                "使用摩擦轮控制时 PWMB 必须为 50Hz",
                "pwm",
            );
        }
    }

    range(
        issues,
        config.mode_count,
        1,
        4,
        "modes.count",
        "模式数量",
        "strategy",
        true,
    );
    let Some(count) = config.mode_count.filter(|count| (1..=4).contains(count)) else {
        return;
    };
    let count = usize::try_from(count).unwrap_or(0);
    if config.modes.len() < count {
        push(
            issues,
            IssueSeverity::Error,
            "modes",
            "模式配置数量不足",
            "mappings",
        );
        return;
    }
    if !chassis_enabled {
        for (index, mode) in config.modes.iter().take(count).enumerate() {
            if mode.preserve_chassis {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("modes.{index}.preserve_chassis"),
                    "未启用底盘控制时不能保留底盘控制",
                    "mappings",
                );
            }
        }
    }
    let mut switch_entries: Vec<(String, Option<String>)> = Vec::new();
    if count > 1 {
        choice(
            issues,
            config.switch_strategy.map(SwitchStrategy::as_str),
            "modes.switch_strategy",
            "模式切换策略",
            "strategy",
        );
        match config.switch_strategy {
            Some(SwitchStrategy::Cycle) => switch_entries.push((
                "modes.switch_key".to_owned(),
                config.mode_switch_key.clone(),
            )),
            Some(SwitchStrategy::Direct) => {
                for index in 0..count {
                    switch_entries.push((
                        format!("modes.keys.{index}"),
                        config.mode_keys.get(index).cloned().flatten(),
                    ));
                }
            }
            None => {}
        }
    }
    let mut switch_keys: std::collections::HashSet<String> = std::collections::HashSet::new();
    for (path, key) in &switch_entries {
        choice(issues, key.as_deref(), path, "模式切换按键", "strategy");
        if let Some(key) = key {
            if !DIGITAL_REMOTE_KEYS.contains(&key.as_str()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    "模式切换只能使用数字按键",
                    "strategy",
                );
            }
            if !switch_keys.insert(key.clone()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    "模式切换按键不能重复",
                    "strategy",
                );
            }
        }
    }
    let sprint_reserved = chassis_enabled && config.chassis.sprint_enabled;
    if sprint_reserved {
        for (path, key) in &switch_entries {
            if key.as_deref() == Some("LC") {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    "LC 已用于底盘冲刺，不能同时作为模式切换按键",
                    "strategy",
                );
            }
        }
    }

    let mut variable_types: std::collections::BTreeMap<String, ExpressionType> =
        std::collections::BTreeMap::new();
    let mut variable_modes: std::collections::BTreeMap<String, std::collections::BTreeSet<usize>> =
        std::collections::BTreeMap::new();
    for (mode_index, mode) in config.modes.iter().take(count).enumerate() {
        let mut seen_names: std::collections::HashSet<String> = std::collections::HashSet::new();
        for (action_index, action) in mode.actions.iter().enumerate() {
            if action.output_kind == ActionOutputKind::Pin {
                continue;
            }
            let name = action.variable_name.as_deref().map(str::trim).unwrap_or("");
            if name.is_empty()
                || !is_valid_variable_name(name)
                || !seen_names.insert(name.to_owned())
            {
                continue;
            }
            let kind = if action.output_kind == ActionOutputKind::Integer {
                ExpressionType::Integer
            } else {
                ExpressionType::Rational
            };
            match variable_types.get(name) {
                Some(existing) if *existing != kind => push(
                    issues,
                    IssueSeverity::Error,
                    format!("modes.{mode_index}.actions.{action_index}.variable"),
                    "同名变量在不同模式中的类型必须一致",
                    "mappings",
                ),
                Some(_) => {}
                None => {
                    variable_types.insert(name.to_owned(), kind);
                }
            }
            variable_modes
                .entry(name.to_owned())
                .or_default()
                .insert(mode_index);
        }
    }
    let global_variables: std::collections::BTreeMap<String, ExpressionType> = variable_types
        .iter()
        .filter(|(name, _)| {
            variable_modes
                .get(*name)
                .is_some_and(|modes| modes.len() >= 2)
        })
        .map(|(name, kind)| (name.clone(), *kind))
        .collect();
    for (mode_index, mode) in config.modes.iter().take(count).enumerate() {
        let mut seen: std::collections::HashMap<String, usize> = std::collections::HashMap::new();
        let mut seen_variables: std::collections::HashSet<String> =
            std::collections::HashSet::new();
        let mut mode_variables = global_variables.clone();
        let mut duty_pin_rows: Vec<(String, Vec<usize>)> = Vec::new();
        for (action_index, action) in mode.actions.iter().enumerate() {
            let path = format!("modes.{mode_index}.actions.{action_index}");
            if action.output_kind != ActionOutputKind::Pin {
                let name = action.variable_name.as_deref().map(str::trim).unwrap_or("");
                if !name.is_empty() && !seen_variables.insert(name.to_owned()) {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{path}.variable"),
                        "本模式内变量名不能重复",
                        "mappings",
                    );
                }
            }
            action_rules(
                config,
                mode,
                action,
                &path,
                &switch_keys,
                &mode_variables,
                issues,
            );
            if sprint_reserved && action.key.as_deref() == Some("LC") {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.key"),
                    "LC 已用于底盘冲刺，不能同时作为动作输入",
                    "mappings",
                );
            }
            if action.output_kind != ActionOutputKind::Pin {
                let name = action.variable_name.as_deref().map(str::trim).unwrap_or("");
                if is_valid_variable_name(name) {
                    mode_variables.insert(
                        name.to_owned(),
                        if action.output_kind == ActionOutputKind::Integer {
                            ExpressionType::Integer
                        } else {
                            ExpressionType::Rational
                        },
                    );
                }
            }
            if let Some(key) = &action.key {
                if let Some(previous) = seen.get(key) {
                    push(
                        issues,
                        IssueSeverity::Warning,
                        format!("{path}.key"),
                        format!(
                            "该按键已被本模式第 {} 行使用，两行动作会同时生效",
                            previous + 1
                        ),
                        "mappings",
                    );
                } else {
                    seen.insert(key.clone(), action_index);
                }
            }
            if action.output_kind == ActionOutputKind::Pin {
                if let Some(pin) = &action.pin {
                    if EXPANSION_PINS.contains(&pin.as_str())
                        || MAIN_SERVO_PINS.contains(&pin.as_str())
                    {
                        if let Some(group) = duty_pin_rows
                            .iter_mut()
                            .find(|(existing, _)| existing == pin)
                        {
                            group.1.push(action_index);
                        } else {
                            duty_pin_rows.push((pin.clone(), vec![action_index]));
                        }
                    }
                }
            }
        }
        for (pin, rows) in &duty_pin_rows {
            if rows.len() < 2 {
                continue;
            }
            let actions: Vec<&ActionMapping> =
                rows.iter().map(|index| &mode.actions[*index]).collect();
            let servo = config.pwm.is_servo_pin(pin);
            let (clobbers, message) = if servo {
                let clobbers = actions.iter().any(|action| {
                    action.input_kind == ActionInputKind::Unspecified
                        || action
                            .key
                            .as_deref()
                            .is_some_and(|key| AXIS_REMOTE_INPUTS.contains(&key))
                });
                (
                    clobbers,
                    format!("{pin} 在本模式被多行输出，摇杆行/表达式行每周期都会覆盖其他行的结果"),
                )
            } else {
                let all_direct = actions.iter().all(|action| {
                    action.mode == Some(ControlMode::Direct)
                        && action.input_kind == ActionInputKind::Remote
                });
                if all_direct {
                    continue;
                }
                let clobbers = actions.iter().any(|action| {
                    action.input_kind == ActionInputKind::Unspecified
                        || action.mode == Some(ControlMode::Direct)
                        || action.mode == Some(ControlMode::Speed)
                });
                (
                    clobbers,
                    format!("{pin} 在本模式被多行输出，行序在后的赋值会覆盖前面的结果"),
                )
            };
            if !clobbers {
                continue;
            }
            push(
                issues,
                IssueSeverity::Warning,
                format!("modes.{mode_index}.actions.{}.pin", rows[rows.len() - 1]),
                message,
                "mappings",
            );
        }
        action_tables_rules(config, mode, mode_index, &switch_keys, issues);
    }
}

fn action_tables_rules(
    config: &EngineerConfig,
    mode: &EngineerModeConfig,
    mode_index: usize,
    switch_keys: &std::collections::HashSet<String>,
    issues: &mut Issues,
) {
    if mode.action_tables.is_empty() {
        return;
    }
    let action_keys: std::collections::HashSet<&str> = mode
        .actions
        .iter()
        .filter_map(|action| action.key.as_deref())
        .collect();
    let action_pins: std::collections::HashSet<&str> = mode
        .actions
        .iter()
        .filter_map(|action| action.pin.as_deref())
        .collect();
    let mut used_keys: std::collections::HashSet<String> = std::collections::HashSet::new();
    let mut used_pins: std::collections::HashSet<String> = std::collections::HashSet::new();
    for (table_index, table) in mode.action_tables.iter().enumerate() {
        let base = format!("modes.{mode_index}.action_tables.{table_index}");
        range(
            issues,
            table.steps,
            2,
            8,
            &format!("{base}.steps"),
            "档位数",
            "mappings",
            true,
        );
        let mut check_key = |issues: &mut Issues, key: &str, path: &str, label: &str| {
            if !DIGITAL_REMOTE_KEYS.contains(&key) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    format!("{label}必须是数字按键"),
                    "mappings",
                );
                return;
            }
            if switch_keys.contains(key) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    format!("{label}与模式切换按键冲突"),
                    "mappings",
                );
            }
            if action_keys.contains(key) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    format!("按键 {key} 已被本模式动作行使用，不能同时作为{label}"),
                    "mappings",
                );
            }
            if !used_keys.insert(key.to_owned()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    path,
                    format!("按键 {key} 已被本模式其他动作表使用"),
                    "mappings",
                );
            }
        };
        if let Some(key) = &table.key {
            check_key(issues, key, &format!("{base}.key"), "下一档键");
        } else {
            push_required(
                issues,
                IssueSeverity::Error,
                format!("{base}.key"),
                "下一档键尚未选择",
                "mappings",
            );
        }
        if let Some(previous) = &table.previous_key {
            if Some(previous) == table.key.as_ref() {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{base}.prev_key"),
                    "上一档键不能与下一档键相同",
                    "mappings",
                );
            } else {
                check_key(issues, previous, &format!("{base}.prev_key"), "上一档键");
            }
        }
        if !table.wrap && table.previous_key.is_none() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{base}.wrap"),
                "只有下一档键时必须开启越界重复",
                "mappings",
            );
        }
        if table.rows.is_empty() {
            push_required(
                issues,
                IssueSeverity::Error,
                format!("{base}.rows"),
                "动作表至少需要一行输出",
                "mappings",
            );
        }
        for (row_index, row) in table.rows.iter().enumerate() {
            let row_path = format!("{base}.rows.{row_index}");
            choice(
                issues,
                row.pin.as_deref(),
                &format!("{row_path}.pin"),
                "引脚",
                "mappings",
            );
            let mut role = PinRole::Motor;
            if let Some(pin) = &row.pin {
                match config.pwm.role_of(pin) {
                    None => push(
                        issues,
                        IssueSeverity::Error,
                        format!("{row_path}.pin"),
                        format!("未知引脚 {pin}"),
                        "mappings",
                    ),
                    Some(PinRole::Unused) => push(
                        issues,
                        IssueSeverity::Error,
                        format!("{row_path}.pin"),
                        format!("{pin} 未启用，不能用于动作表"),
                        "mappings",
                    ),
                    Some(PinRole::Friction) => push(
                        issues,
                        IssueSeverity::Error,
                        format!("{row_path}.pin"),
                        format!("{pin} 是摩擦轮引脚，必须用摩擦轮控制方式，不能放进动作表"),
                        "mappings",
                    ),
                    Some(resolved) => role = resolved,
                }
                if action_pins.contains(pin.as_str()) {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{row_path}.pin"),
                        format!("引脚 {pin} 已被本模式动作行使用，不能再放进动作表"),
                        "mappings",
                    );
                }
                if !used_pins.insert(pin.clone()) {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{row_path}.pin"),
                        format!("引脚 {pin} 在本模式动作表里重复出现"),
                        "mappings",
                    );
                }
            }
            let Some(steps) = table.steps else {
                continue;
            };
            if i64::try_from(row.values.len()).unwrap_or(i64::MAX) != steps {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{row_path}.values"),
                    format!("每个引脚的档位值数量必须等于档位数（{steps}）"),
                    "mappings",
                );
            }
            let steps_usize = usize::try_from(steps.max(0)).unwrap_or(0);
            for (column, value) in row.values.iter().take(steps_usize).enumerate() {
                let value = *value;
                let value_path = format!("{row_path}.values.{column}");
                let label = format!("第 {} 档", column + 1);
                let Some(value) = value else {
                    push_required(
                        issues,
                        IssueSeverity::Error,
                        &value_path,
                        format!("{label}尚未填写"),
                        "mappings",
                    );
                    continue;
                };
                if role == PinRole::Servo {
                    range(
                        issues,
                        Some(value),
                        -90,
                        90,
                        &value_path,
                        &format!("{label}角度"),
                        "mappings",
                        true,
                    );
                } else {
                    range(
                        issues,
                        Some(value),
                        -10000,
                        10000,
                        &value_path,
                        &format!("{label} duty"),
                        "mappings",
                        true,
                    );
                }
            }
        }
    }
}

fn expression_or_variable_row(
    config: &EngineerConfig,
    parent: &EngineerModeConfig,
    action: &ActionMapping,
    path: &str,
    switch_keys: &std::collections::HashSet<String>,
    variables: &std::collections::BTreeMap<String, ExpressionType>,
    issues: &mut Issues,
) {
    let input_unspecified = action.input_kind == ActionInputKind::Unspecified;
    let pin_output = action.output_kind == ActionOutputKind::Pin;
    if input_unspecified {
        if action.key.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "输入为未指定时不能再选择按键",
                "mappings",
            );
        }
    } else {
        choice(
            issues,
            action.key.as_deref(),
            &format!("{path}.key"),
            "动作输入",
            "mappings",
        );
        if let Some(key) = &action.key {
            if !REMOTE_KEYS.contains(&key.as_str()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.key"),
                    "未知遥控器输入",
                    "mappings",
                );
            }
            if switch_keys.contains(key) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.key"),
                    "动作输入与模式切换按键冲突",
                    "mappings",
                );
            }
            if parent.preserve_chassis && (key == "LX" || key == "LY") {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.key"),
                    "当前模式保留底盘控制，LX/LY 不能用于动作",
                    "mappings",
                );
            }
        }
    }
    if pin_output {
        choice(
            issues,
            action.pin.as_deref(),
            &format!("{path}.pin"),
            "动作输出",
            "mappings",
        );
        if let Some(pin) = &action.pin {
            if !EXPANSION_PINS.contains(&pin.as_str()) && !MAIN_SERVO_PINS.contains(&pin.as_str()) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.pin"),
                    "动作输出无效",
                    "mappings",
                );
            }
        }
        if action.variable_name.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.variable"),
                "引脚输出不能填写变量名",
                "mappings",
            );
        }
    } else {
        if action.pin.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                "变量输出不能同时选择引脚",
                "mappings",
            );
        }
        choice(
            issues,
            action.variable_name.as_deref(),
            &format!("{path}.variable"),
            "变量名",
            "mappings",
        );
        let name = action.variable_name.as_deref().map(str::trim).unwrap_or("");
        if action
            .variable_name
            .as_deref()
            .is_some_and(|original| name != original)
        {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.variable"),
                "变量名首尾不能有空格",
                "mappings",
            );
        }
        if !name.is_empty() && !is_valid_variable_name(name) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.variable"),
                "变量名必须是合法 C 标识符，且不能使用内置输入/常量/函数/关键字",
                "mappings",
            );
        }
    }
    if !input_unspecified && action.expression.is_some() {
        push(
            issues,
            IssueSeverity::Error,
            format!("{path}.expression"),
            "只有输入为未指定时才能填写表达式",
            "mappings",
        );
    }
    if input_unspecified {
        choice(
            issues,
            action.expression.as_deref(),
            &format!("{path}.expression"),
            "表达式",
            "mappings",
        );
        if action.mode.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.mode"),
                "表达式行不使用控制方式",
                "mappings",
            );
        }
        if action.parameter.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.parameter"),
                "表达式行不使用参数",
                "mappings",
            );
        }
        if let Some(source) = &action.expression {
            if !source.trim().is_empty() {
                let parsed = parse_expression(source, variables);
                for diagnostic in &parsed.diagnostics {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{path}.expression"),
                        diagnostic.message.clone(),
                        "mappings",
                    );
                }
            }
        }
    } else {
        if action.mode.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.mode"),
                "变量赋值行不使用控制方式",
                "mappings",
            );
        }
        if action.parameter.is_some() {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.parameter"),
                "变量赋值行不使用参数",
                "mappings",
            );
        }
    }
    if pin_output && input_unspecified {
        if let Some(pin) = &action.pin {
            let role = config.pwm.role_of(pin);
            if role == Some(PinRole::Friction) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.pin"),
                    "摩擦轮脚不能使用表达式，请使用摩擦轮专用控制方式",
                    "mappings",
                );
            }
            if role == Some(PinRole::Unused) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.pin"),
                    format!("{pin} 已标记为未使用，不能作为动作输出"),
                    "mappings",
                );
            }
            let chassis_used = if config.chassis.enabled {
                normalized_chassis_pins(&config.chassis)
            } else {
                Vec::new()
            };
            if chassis_used.contains(pin) {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.pin"),
                    format!("{pin} 已被底盘电机占用"),
                    "mappings",
                );
            }
        }
    }
}

fn action_rules(
    config: &EngineerConfig,
    parent: &EngineerModeConfig,
    action: &ActionMapping,
    path: &str,
    switch_keys: &std::collections::HashSet<String>,
    variables: &std::collections::BTreeMap<String, ExpressionType>,
    issues: &mut Issues,
) {
    if action.output_kind != ActionOutputKind::Pin
        || action.input_kind == ActionInputKind::Unspecified
    {
        expression_or_variable_row(config, parent, action, path, switch_keys, variables, issues);
        return;
    }
    if action.expression.is_some() {
        push(
            issues,
            IssueSeverity::Error,
            format!("{path}.expression"),
            "只有输入为未指定时才能填写表达式",
            "mappings",
        );
    }
    if action.variable_name.is_some() {
        push(
            issues,
            IssueSeverity::Error,
            format!("{path}.variable"),
            "引脚输出不能填写变量名",
            "mappings",
        );
    }
    choice(
        issues,
        action.key.as_deref(),
        &format!("{path}.key"),
        "动作输入",
        "mappings",
    );
    let friction_mode = is_friction_mode(action.mode);
    choice(
        issues,
        action.mode.map(ControlMode::as_str),
        &format!("{path}.mode"),
        "控制方式",
        "mappings",
    );
    choice(
        issues,
        action.pin.as_deref(),
        &format!("{path}.pin"),
        "动作 IO",
        "mappings",
    );
    if let Some(key) = &action.key {
        if !REMOTE_KEYS.contains(&key.as_str()) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "未知遥控器输入",
                "mappings",
            );
        }
        if switch_keys.contains(key) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "动作输入与模式切换按键冲突",
                "mappings",
            );
        }
        if parent.preserve_chassis && (key == "LX" || key == "LY") {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "当前模式保留底盘控制，LX/LY 不能用于动作",
                "mappings",
            );
        }
    }
    let is_axis = action
        .key
        .as_deref()
        .is_some_and(|key| AXIS_REMOTE_INPUTS.contains(&key));
    let is_button = action
        .key
        .as_deref()
        .is_some_and(|key| DIGITAL_REMOTE_KEYS.contains(&key));
    if let Some(pin) = &action.pin {
        if !EXPANSION_PINS.contains(&pin.as_str()) && !MAIN_SERVO_PINS.contains(&pin.as_str()) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                "动作 IO 无效",
                "mappings",
            );
        }
    }
    let chassis_used = if config.chassis.enabled {
        normalized_chassis_pins(&config.chassis)
    } else {
        Vec::new()
    };
    if let Some(pin) = &action.pin {
        if chassis_used.contains(pin) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                format!("{pin} 已被底盘电机占用"),
                "mappings",
            );
        }
    }
    let role = action.pin.as_ref().and_then(|pin| config.pwm.role_of(pin));
    let motor = role.is_some_and(motor_role);
    let friction = role == Some(PinRole::Friction);
    let main_friction = friction
        && action
            .pin
            .as_deref()
            .is_some_and(|pin| MAIN_SERVO_PINS.contains(&pin));
    if role == Some(PinRole::Unused) {
        if let Some(pin) = &action.pin {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                format!("{pin} 已标记为未使用，不能作为动作输出"),
                "mappings",
            );
        }
    }
    if friction_mode {
        if role != Some(PinRole::Friction) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                "摩擦轮专用控制方式只能用于角色为摩擦轮的输出引脚",
                "mappings",
            );
        }
        if action.output_kind != ActionOutputKind::Pin
            || action.variable_name.is_some()
            || action.expression.is_some()
        {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.pin"),
                "摩擦轮专用控制方式必须输出到引脚",
                "mappings",
            );
        }
        if action.input_kind != ActionInputKind::Remote {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "摩擦轮专用控制方式需要遥控器输入",
                "mappings",
            );
        }
        if action.mode == Some(ControlMode::FrictionAxis) {
            if !is_axis {
                push(
                    issues,
                    IssueSeverity::Error,
                    format!("{path}.key"),
                    "摇杆油门只能使用摇杆轴输入",
                    "mappings",
                );
            }
        } else if !is_button {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.key"),
                "启停/单次/持续只能使用数字按键输入",
                "mappings",
            );
        }
    } else if friction {
        if has_friction_control(config) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.mode"),
                "同一配置中摩擦轮脚不能混用旧控制方式",
                "mappings",
            );
        } else {
            push(
                issues,
                IssueSeverity::Warning,
                format!("{path}.mode"),
                "摩擦轮脚上的旧控制方式直接写转速，不受安全斜坡保护",
                "mappings",
            );
        }
    }
    let allowed: Vec<ControlMode> = match role {
        None => Vec::new(),
        Some(PinRole::Friction) => {
            if main_friction {
                if is_axis {
                    vec![ControlMode::FrictionAxis]
                } else if is_button {
                    vec![
                        ControlMode::FrictionToggle,
                        ControlMode::FrictionStep,
                        ControlMode::FrictionContinuous,
                    ]
                } else {
                    Vec::new()
                }
            } else if is_axis {
                vec![
                    ControlMode::FrictionAxis,
                    ControlMode::Speed,
                    ControlMode::Accelerate,
                ]
            } else if is_button {
                vec![
                    ControlMode::FrictionToggle,
                    ControlMode::FrictionStep,
                    ControlMode::FrictionContinuous,
                    ControlMode::Direct,
                ]
            } else {
                Vec::new()
            }
        }
        Some(_) if motor => {
            if is_axis {
                vec![ControlMode::Speed, ControlMode::Accelerate]
            } else if is_button {
                vec![ControlMode::Direct]
            } else {
                Vec::new()
            }
        }
        Some(_) => {
            if is_axis {
                vec![ControlMode::Incremental, ControlMode::Direct]
            } else if is_button {
                vec![
                    ControlMode::Direct,
                    ControlMode::Single,
                    ControlMode::Continuous,
                ]
            } else {
                Vec::new()
            }
        }
    };
    if let Some(mode) = action.mode {
        if !allowed.contains(&mode) {
            push(
                issues,
                IssueSeverity::Error,
                format!("{path}.mode"),
                "控制方式与输入类型或 IO 输出角色不匹配",
                "mappings",
            );
        }
    }
    if let Some(mode) = action.mode {
        if !allowed.contains(&mode) {
            return;
        }
        match mode {
            ControlMode::Incremental => {
                action_integer_range(
                    issues,
                    action.parameter,
                    -90,
                    90,
                    &format!("{path}.parameter"),
                    "舵机增量",
                    "mappings",
                );
                if action.parameter.is_some_and(|value| value.to_f64() == 0.0) {
                    push(
                        issues,
                        IssueSeverity::Warning,
                        format!("{path}.parameter"),
                        "舵机增量为 0，该动作不会产生变化",
                        "mappings",
                    );
                }
                if action
                    .parameter
                    .is_some_and(|value| value.to_f64().abs() > 30.0)
                {
                    push(
                        issues,
                        IssueSeverity::Warning,
                        format!("{path}.parameter"),
                        "单次增量偏大，建议使用 −30–30°",
                        "mappings",
                    );
                }
            }
            ControlMode::Direct => {
                action_integer_range(
                    issues,
                    action.parameter,
                    if motor { -10000 } else { -90 },
                    if motor { 10000 } else { 90 },
                    &format!("{path}.parameter"),
                    if motor {
                        "电机速度"
                    } else {
                        "舵机角度"
                    },
                    "mappings",
                );
            }
            ControlMode::Speed | ControlMode::Accelerate => {
                action_integer_range(
                    issues,
                    action.parameter,
                    0,
                    10000,
                    &format!("{path}.parameter"),
                    "电机控制参数",
                    "mappings",
                );
            }
            ControlMode::Single | ControlMode::Continuous => {
                servo_button_sensitivity(issues, action.parameter, &format!("{path}.parameter"));
            }
            ControlMode::FrictionToggle => {
                action_integer_range(
                    issues,
                    action.parameter,
                    1,
                    100,
                    &format!("{path}.parameter"),
                    "目标油门 %",
                    "mappings",
                );
            }
            ControlMode::FrictionStep => {
                action_integer_range(
                    issues,
                    action.parameter,
                    -100,
                    100,
                    &format!("{path}.parameter"),
                    "单次油门 %",
                    "mappings",
                );
                if action.parameter.is_some_and(|value| value.to_f64() == 0.0) {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{path}.parameter"),
                        "单次油门不能为 0，用正负表示加/减",
                        "mappings",
                    );
                }
            }
            ControlMode::FrictionContinuous => {
                action_integer_range(
                    issues,
                    action.parameter,
                    -100,
                    100,
                    &format!("{path}.parameter"),
                    "持续油门 %/秒",
                    "mappings",
                );
                if action.parameter.is_some_and(|value| value.to_f64() == 0.0) {
                    push(
                        issues,
                        IssueSeverity::Error,
                        format!("{path}.parameter"),
                        "持续油门不能为 0，用正负表示加/减",
                        "mappings",
                    );
                }
            }
            ControlMode::FrictionAxis => {
                action_integer_range(
                    issues,
                    action.parameter,
                    1,
                    100,
                    &format!("{path}.parameter"),
                    "摇杆油门 %/秒",
                    "mappings",
                );
            }
        }
    } else {
        choice(
            issues,
            action.parameter.map(|_| "present"),
            &format!("{path}.parameter"),
            "动作参数",
            "mappings",
        );
    }
}

fn action_integer_range(
    issues: &mut Issues,
    value: Option<crate::json::ParamNum>,
    min: i64,
    max: i64,
    path: &str,
    label: &str,
    step: &str,
) {
    if let Some(value) = value {
        if !value.is_integral() {
            push(
                issues,
                IssueSeverity::Error,
                path,
                format!("{label}必须为整数"),
                step,
            );
            return;
        }
    }
    range(
        issues,
        value.map(crate::json::ParamNum::to_i64),
        min,
        max,
        path,
        label,
        step,
        true,
    );
}

fn servo_button_sensitivity(issues: &mut Issues, value: Option<crate::json::ParamNum>, path: &str) {
    let Some(value) = value else {
        push_required(
            issues,
            IssueSeverity::Error,
            path,
            "舵机灵敏度尚未填写",
            "mappings",
        );
        return;
    };
    let numeric = value.to_f64();
    if !numeric.is_finite() || numeric == 0.0 || numeric.abs() > 20.0 {
        push(
            issues,
            IssueSeverity::Error,
            path,
            "舵机灵敏度绝对值必须大于 0 且不超过 20，正负表示方向",
            "mappings",
        );
        return;
    }
    let hundredths = numeric * 100.0;
    if (hundredths - hundredths.round()).abs() > 1e-9 {
        push(
            issues,
            IssueSeverity::Error,
            path,
            "舵机灵敏度最多保留两位小数",
            "mappings",
        );
        return;
    }
    if numeric.abs() > 10.0 {
        push(
            issues,
            IssueSeverity::Warning,
            path,
            "舵机角度变化速度可能过快",
            "mappings",
        );
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

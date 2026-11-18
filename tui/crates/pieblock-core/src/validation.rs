//! 校验器（M1 移植中）。
//!
//! 已移植：公共机器人规则（遥控器/底盘）、调试工程、通用范围/枚举/底盘共用
//! IO 检查。校验顺序与文案与 `packages/pieblock_core/lib/src/validator.dart`
//! 一致；步兵/工程专属规则与音乐规则在后续提交补齐（golden 已生成）。

use serde_json::{Map, Value};

use crate::model::{
    ChassisConfig, DEBUG_PINS, DebugConfig, DebugDriveType, Direction, MAIN_SERVO_PINS,
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
            // TODO(M1): _infantry 专属规则。
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

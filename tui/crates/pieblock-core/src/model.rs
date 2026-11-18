//! `.pieproj` 领域模型与格式 17→23 迁移。
//!
//! 行为对齐 `packages/pieblock_core/lib/src/models.dart`：
//! - 读取宽容：数值 `toInt()` 截断、枚举未知回退、缺失 map/list 视为空；
//! - 写出固定字段顺序，可选字段按 Dart 的规则省略；
//! - 旧格式的方向字段在读取时折算为参数/数值正负（18→19）；
//! - `name`（≤20）忽略，项目名由文件名派生；
//! - 灵敏度（22→23）缺省 100，`wrap`（21→22）缺省 true。

use std::collections::BTreeMap;

use serde_json::{Map, Value};

use crate::ProjectKind;
use crate::ids;
use crate::json::{self, JsonMap, ParamNum};

crate::string_enum! {
    Direction { Forward => "forward", Reverse => "reverse" }
}
crate::string_enum! {
    DriveType { Servo => "servo", Motor => "motor" }
}
crate::string_enum! {
    DebugDriveType { Motor => "motor", Servo => "servo", Friction => "friction" }
}
crate::string_enum! {
    ArrowBehavior { Move => "move", Sprint => "sprint", Other => "other" }
}
crate::string_enum! {
    FeedMode { BlockingOpenLoop => "blockingOpenLoop", VisualClosedLoop => "visualClosedLoop" }
}
crate::string_enum! {
    FrictionMode { BrushlessEsc => "brushlessEsc", Disabled => "disabled" }
}
crate::string_enum! {
    PinRole { Motor => "motor", Servo => "servo", Friction => "friction", JitterMotor => "jitterMotor", Unused => "unused" }
}
crate::string_enum! {
    PwmFrequency { Hz50 => "hz50", Hz10000 => "hz10000" }
}
crate::string_enum! {
    SwitchStrategy { Cycle => "cycle", Direct => "direct" }
}
crate::string_enum! {
    ControlMode {
        Direct => "direct",
        Incremental => "incremental",
        Speed => "speed",
        Accelerate => "accelerate",
        Single => "single",
        Continuous => "continuous",
        FrictionToggle => "frictionToggle",
        FrictionStep => "frictionStep",
        FrictionContinuous => "frictionContinuous",
        FrictionAxis => "frictionAxis"
    }
}
crate::string_enum! {
    ActionInputKind { Remote => "remote", Unspecified => "unspecified" }
}
crate::string_enum! {
    ActionOutputKind { Pin => "pin", Integer => "integer", Rational => "rational" }
}
crate::string_enum! {
    MusicOverlapMode { Highest => "highest", Lowest => "lowest", Nearest => "nearest" }
}

impl MusicOverlapMode {
    #[must_use]
    pub const fn label(self) -> &'static str {
        match self {
            Self::Highest => "取高音",
            Self::Lowest => "取低音",
            Self::Nearest => "取最近音阶",
        }
    }
}

pub const EXPANSION_PINS: [&str; 8] = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"];
pub const MAIN_SERVO_PINS: [&str; 2] = ["MP03", "MP74"];
pub const PWM_PINS: [&str; 10] = [
    "P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74",
];
pub const DEBUG_PINS: [&str; 10] = [
    "P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74",
];
pub const LEGACY_FRICTION_PINS: [&str; 2] = ["P64", "P66"];

fn object(entries: Vec<(&str, Value)>) -> Value {
    let mut map = Map::new();
    for (key, value) in entries {
        map.insert(key.to_owned(), value);
    }
    Value::Object(map)
}

fn int_json(value: Option<i64>) -> Value {
    value.map_or(Value::Null, Value::from)
}

fn string_json(value: Option<&str>) -> Value {
    value.map_or(Value::Null, |text| Value::String(text.to_owned()))
}

fn enum_json<T: Copy + ToJsonEnum>(value: Option<T>) -> Value {
    value.map_or(Value::Null, |item| {
        Value::String(item.enum_name().to_owned())
    })
}

trait ToJsonEnum {
    fn enum_name(self) -> &'static str;
}

macro_rules! impl_to_json_enum {
    ($($name:ty),+ $(,)?) => {
        $(impl ToJsonEnum for $name {
            fn enum_name(self) -> &'static str {
                self.as_str()
            }
        })+
    };
}

impl_to_json_enum!(
    Direction,
    DriveType,
    DebugDriveType,
    ArrowBehavior,
    FeedMode,
    FrictionMode,
    PinRole,
    PwmFrequency,
    SwitchStrategy,
    ControlMode,
    ActionInputKind,
    ActionOutputKind,
    MusicOverlapMode
);

fn map_of(value: Option<&Value>) -> Option<&JsonMap> {
    value.and_then(Value::as_object)
}

fn array_of(value: Option<&Value>) -> &[Value] {
    value.and_then(Value::as_array).map_or(&[], Vec::as_slice)
}

fn int_map(map: &JsonMap, key: &str) -> BTreeMap<String, i64> {
    let mut result = BTreeMap::new();
    if let Some(entries) = map_of(map.get(key)) {
        for (pin, value) in entries {
            if let Some(number) = json::int_of(Some(value)) {
                result.insert(pin.clone(), number);
            }
        }
    }
    result
}

fn string_map(map: &JsonMap, key: &str) -> BTreeMap<String, String> {
    let mut result = BTreeMap::new();
    if let Some(entries) = map_of(map.get(key)) {
        for (pin, value) in entries {
            if let Some(text) = value.as_str() {
                result.insert(pin.clone(), text.to_owned());
            }
        }
    }
    result
}

fn normalize_pin_notes(notes: BTreeMap<String, String>) -> BTreeMap<String, String> {
    notes
        .into_iter()
        .filter_map(|(pin, text)| {
            let trimmed = text.trim();
            if trimmed.is_empty() {
                None
            } else {
                Some((pin, trimmed.to_owned()))
            }
        })
        .collect()
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct RemoteConfig {
    pub channel: Option<i64>,
    pub deadzone: Option<i64>,
}

impl RemoteConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            channel: json::int_field(map, "channel"),
            deadzone: json::int_field(map, "deadzone"),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("channel", int_json(self.channel)),
            ("deadzone", int_json(self.deadzone)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct WheelConfig {
    pub pin: Option<String>,
    pub direction: Option<Direction>,
}

impl WheelConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            pin: json::string_field(map, "pin"),
            direction: Direction::from_value(map.get("direction")),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("pin", string_json(self.pin.as_deref())),
            ("direction", enum_json(self.direction)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ChassisConfig {
    pub enabled: bool,
    pub left_front: WheelConfig,
    pub left_rear: WheelConfig,
    pub right_front: WheelConfig,
    pub right_rear: WheelConfig,
    pub normal_speed: Option<i64>,
    pub sprint_speed: Option<i64>,
    pub sprint_enabled: bool,
    pub turn_reversed: bool,
    pub turn_sensitivity: i64,
}

impl Default for ChassisConfig {
    fn default() -> Self {
        Self {
            enabled: true,
            left_front: WheelConfig::default(),
            left_rear: WheelConfig::default(),
            right_front: WheelConfig::default(),
            right_rear: WheelConfig::default(),
            normal_speed: None,
            sprint_speed: None,
            sprint_enabled: false,
            turn_reversed: false,
            turn_sensitivity: 100,
        }
    }
}

impl ChassisConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let wheel = |key: &str| {
            map_of(map.get(key)).map_or_else(WheelConfig::default, WheelConfig::from_json)
        };
        Self {
            enabled: json::bool_field(map, "enabled").unwrap_or(true),
            left_front: wheel("left_front"),
            left_rear: wheel("left_rear"),
            right_front: wheel("right_front"),
            right_rear: wheel("right_rear"),
            normal_speed: json::int_field(map, "normal_speed"),
            sprint_speed: json::int_field(map, "sprint_speed"),
            sprint_enabled: json::bool_field(map, "sprint_enabled").unwrap_or(false),
            turn_reversed: json::bool_field(map, "turn_reversed").unwrap_or(false),
            turn_sensitivity: json::int_field(map, "turn_sensitivity").unwrap_or(100),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("enabled", Value::Bool(self.enabled)),
            ("left_front", self.left_front.to_json()),
            ("left_rear", self.left_rear.to_json()),
            ("right_front", self.right_front.to_json()),
            ("right_rear", self.right_rear.to_json()),
            ("normal_speed", int_json(self.normal_speed)),
            ("sprint_speed", int_json(self.sprint_speed)),
            ("sprint_enabled", Value::Bool(self.sprint_enabled)),
            ("turn_reversed", Value::Bool(self.turn_reversed)),
            ("turn_sensitivity", Value::from(self.turn_sensitivity)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct PwmGroupConfig {
    pub pwma: Option<PwmFrequency>,
    pub pwmb: Option<PwmFrequency>,
    pub buzzer_disabled: bool,
    pub pin_roles: BTreeMap<String, PinRole>,
    pub servo_mids: BTreeMap<String, i64>,
    pub servo_min_limits: BTreeMap<String, i64>,
    pub servo_max_limits: BTreeMap<String, i64>,
    pub friction_max_duties: BTreeMap<String, i64>,
    pub pin_notes: BTreeMap<String, String>,
}

impl PwmGroupConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let mut roles = BTreeMap::new();
        if let Some(entries) = map_of(map.get("pin_roles")) {
            for (pin, value) in entries {
                if let Some(role) = PinRole::from_value(Some(value)) {
                    roles.insert(pin.clone(), role);
                }
            }
        }
        Self {
            pwma: PwmFrequency::from_value(map.get("pwma")),
            pwmb: PwmFrequency::from_value(map.get("pwmb")),
            buzzer_disabled: json::bool_field(map, "buzzer_disabled").unwrap_or(false),
            pin_roles: roles,
            servo_mids: int_map(map, "servo_mids"),
            servo_min_limits: int_map(map, "servo_min_limits"),
            servo_max_limits: int_map(map, "servo_max_limits"),
            friction_max_duties: int_map(map, "friction_max_duties"),
            pin_notes: normalize_pin_notes(string_map(map, "pin_notes")),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        let pin_roles = {
            let mut out = Map::new();
            for pin in PWM_PINS {
                out.insert(pin.to_owned(), enum_json(self.pin_roles.get(pin).copied()));
            }
            Value::Object(out)
        };
        let int_pins = |source: &BTreeMap<String, i64>| {
            let mut out = Map::new();
            for pin in PWM_PINS {
                out.insert(pin.to_owned(), int_json(source.get(pin).copied()));
            }
            Value::Object(out)
        };
        let friction = {
            let mut out = Map::new();
            for pin in PWM_PINS {
                if LEGACY_FRICTION_PINS.contains(&pin) || self.friction_max_duties.contains_key(pin)
                {
                    out.insert(
                        pin.to_owned(),
                        int_json(self.friction_max_duties.get(pin).copied()),
                    );
                }
            }
            Value::Object(out)
        };
        let notes = {
            let mut out = Map::new();
            for pin in PWM_PINS {
                if let Some(note) = self.pin_notes.get(pin) {
                    out.insert(pin.to_owned(), Value::String(note.clone()));
                }
            }
            Value::Object(out)
        };
        let mut entries = vec![
            ("pwma", enum_json(self.pwma)),
            ("pwmb", enum_json(self.pwmb)),
            ("buzzer_disabled", Value::Bool(self.buzzer_disabled)),
            ("pin_roles", pin_roles),
        ];
        if !notes.as_object().is_some_and(Map::is_empty) {
            entries.push(("pin_notes", notes));
        }
        entries.push(("servo_mids", int_pins(&self.servo_mids)));
        entries.push(("servo_min_limits", int_pins(&self.servo_min_limits)));
        entries.push(("servo_max_limits", int_pins(&self.servo_max_limits)));
        entries.push(("friction_max_duties", friction));
        object(entries)
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct AxisActuator {
    pub drive: Option<DriveType>,
    pub pin: Option<String>,
    pub direction: Option<Direction>,
    pub mid_offset: Option<i64>,
    pub min_limit: Option<i64>,
    pub max_limit: Option<i64>,
}

impl AxisActuator {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            drive: DriveType::from_value(map.get("drive")),
            pin: json::string_field(map, "pin"),
            direction: Direction::from_value(map.get("direction")),
            mid_offset: json::int_field(map, "mid_offset"),
            min_limit: json::int_field(map, "min_limit"),
            max_limit: json::int_field(map, "max_limit"),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("drive", enum_json(self.drive)),
            ("pin", string_json(self.pin.as_deref())),
            ("direction", enum_json(self.direction)),
            ("mid_offset", int_json(self.mid_offset)),
            ("min_limit", int_json(self.min_limit)),
            ("max_limit", int_json(self.max_limit)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct InfantryConfig {
    pub remote: RemoteConfig,
    pub chassis: ChassisConfig,
    pub feeder_pin: Option<String>,
    pub feeder_direction: Option<Direction>,
    pub yaw: Vec<AxisActuator>,
    pub pitch: Vec<AxisActuator>,
    pub yaw_sensitivity: i64,
    pub pitch_sensitivity: i64,
    pub arrow_behavior: Option<ArrowBehavior>,
    pub feed_mode: Option<FeedMode>,
    pub trigger_key: Option<String>,
    pub reverse_feed_key: Option<String>,
    pub trigger_speed: Option<i64>,
    pub trigger_time_ms: Option<i64>,
    pub friction_mode: Option<FrictionMode>,
    pub friction_key: Option<String>,
    pub friction_up_key: Option<String>,
    pub friction_down_key: Option<String>,
    pub friction_p64_max_duty: Option<i64>,
    pub friction_p66_max_duty: Option<i64>,
    pub friction_level_step: Option<i64>,
    pub zero_enabled: bool,
    pub buzzer_disabled: bool,
}

impl InfantryConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let actuators = |key: &str| {
            array_of(map.get(key))
                .iter()
                .filter_map(Value::as_object)
                .map(AxisActuator::from_json)
                .collect::<Vec<_>>()
        };
        Self {
            remote: map_of(map.get("remote"))
                .map_or_else(RemoteConfig::default, RemoteConfig::from_json),
            chassis: map_of(map.get("chassis"))
                .map_or_else(ChassisConfig::default, ChassisConfig::from_json),
            feeder_pin: json::string_field(map, "feeder_pin"),
            feeder_direction: Direction::from_value(map.get("feeder_direction")),
            yaw: actuators("yaw"),
            pitch: actuators("pitch"),
            yaw_sensitivity: json::int_field(map, "yaw_sensitivity").unwrap_or(100),
            pitch_sensitivity: json::int_field(map, "pitch_sensitivity").unwrap_or(100),
            arrow_behavior: ArrowBehavior::from_value(map.get("arrow_behavior")),
            feed_mode: FeedMode::from_value(map.get("feed_mode")),
            trigger_key: json::string_field(map, "trigger_key"),
            reverse_feed_key: json::string_field(map, "reverse_feed_key"),
            trigger_speed: json::int_field(map, "trigger_speed"),
            trigger_time_ms: json::int_field(map, "trigger_time_ms"),
            friction_mode: FrictionMode::from_value(map.get("friction_mode")),
            friction_key: json::string_field(map, "friction_key"),
            friction_up_key: json::string_field(map, "friction_up_key"),
            friction_down_key: json::string_field(map, "friction_down_key"),
            friction_p64_max_duty: json::int_field(map, "friction_p64_max_duty"),
            friction_p66_max_duty: json::int_field(map, "friction_p66_max_duty"),
            friction_level_step: json::int_field(map, "friction_level_step"),
            zero_enabled: json::bool_field(map, "zero_enabled").unwrap_or(false),
            buzzer_disabled: json::bool_field(map, "buzzer_disabled").unwrap_or(false),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("remote", self.remote.to_json()),
            ("chassis", self.chassis.to_json()),
            ("feeder_pin", string_json(self.feeder_pin.as_deref())),
            ("feeder_direction", enum_json(self.feeder_direction)),
            (
                "yaw",
                Value::Array(self.yaw.iter().map(AxisActuator::to_json).collect()),
            ),
            (
                "pitch",
                Value::Array(self.pitch.iter().map(AxisActuator::to_json).collect()),
            ),
            ("yaw_sensitivity", Value::from(self.yaw_sensitivity)),
            ("pitch_sensitivity", Value::from(self.pitch_sensitivity)),
            ("arrow_behavior", enum_json(self.arrow_behavior)),
            ("feed_mode", enum_json(self.feed_mode)),
            ("trigger_key", string_json(self.trigger_key.as_deref())),
            (
                "reverse_feed_key",
                string_json(self.reverse_feed_key.as_deref()),
            ),
            ("trigger_speed", int_json(self.trigger_speed)),
            ("trigger_time_ms", int_json(self.trigger_time_ms)),
            ("friction_mode", enum_json(self.friction_mode)),
            ("friction_key", string_json(self.friction_key.as_deref())),
            (
                "friction_up_key",
                string_json(self.friction_up_key.as_deref()),
            ),
            (
                "friction_down_key",
                string_json(self.friction_down_key.as_deref()),
            ),
            (
                "friction_p64_max_duty",
                int_json(self.friction_p64_max_duty),
            ),
            (
                "friction_p66_max_duty",
                int_json(self.friction_p66_max_duty),
            ),
            ("friction_level_step", int_json(self.friction_level_step)),
            ("zero_enabled", Value::Bool(self.zero_enabled)),
            ("buzzer_disabled", Value::Bool(self.buzzer_disabled)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DebugTestItem {
    pub id: Option<String>,
    pub pin: String,
    pub enabled: bool,
    pub drive_type: Option<DebugDriveType>,
    pub value: Option<i64>,
    pub duration_ms: i64,
}

impl DebugTestItem {
    #[must_use]
    pub fn default_for(pin: &str) -> Self {
        Self {
            id: None,
            pin: pin.to_owned(),
            enabled: false,
            drive_type: None,
            value: None,
            duration_ms: 3000,
        }
    }

    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let drive_type = DebugDriveType::from_value(map.get("drive_type"));
        let raw_value = json::int_field(map, "value");
        let legacy_direction = Direction::from_value(map.get("direction"));
        let signed_value = if drive_type != Some(DebugDriveType::Friction)
            && legacy_direction == Some(Direction::Reverse)
        {
            raw_value.map(|value| -value)
        } else {
            raw_value
        };
        Self {
            id: map
                .get("id")
                .filter(|value| !value.is_null())
                .map(json::to_dart_string),
            pin: json::string_field(map, "pin").unwrap_or_default(),
            enabled: json::bool_field(map, "enabled").unwrap_or(false),
            drive_type,
            value: signed_value,
            duration_ms: json::int_field(map, "duration_ms").unwrap_or(3000),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut entries = Vec::new();
        if let Some(id) = &self.id {
            entries.push(("id", Value::String(id.clone())));
        }
        entries.push(("pin", Value::String(self.pin.clone())));
        entries.push(("enabled", Value::Bool(self.enabled)));
        entries.push(("drive_type", enum_json(self.drive_type)));
        entries.push(("value", int_json(self.value)));
        if self.drive_type != Some(DebugDriveType::Friction) {
            entries.push(("duration_ms", Value::from(self.duration_ms)));
        }
        object(entries)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct DebugConfig {
    pub tests: Vec<DebugTestItem>,
}

impl Default for DebugConfig {
    fn default() -> Self {
        Self {
            tests: DEBUG_PINS
                .iter()
                .map(|pin| DebugTestItem::default_for(pin))
                .collect(),
        }
    }
}

impl DebugConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let mut tests = Vec::new();
        let mut seen = std::collections::HashSet::new();
        for raw in array_of(map.get("tests")) {
            let Some(object) = raw.as_object() else {
                continue;
            };
            let item = DebugTestItem::from_json(object);
            if DEBUG_PINS.contains(&item.pin.as_str()) {
                seen.insert(item.pin.clone());
                tests.push(item);
            }
        }
        for pin in DEBUG_PINS {
            if seen.insert(pin.to_owned()) {
                tests.push(DebugTestItem::default_for(pin));
            }
        }
        Self { tests }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![(
            "tests",
            Value::Array(self.tests.iter().map(DebugTestItem::to_json).collect()),
        )])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MusicNote {
    pub id: String,
    pub pitch: i64,
    pub start_tick: i64,
    pub duration_ticks: i64,
}

impl MusicNote {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            id: map.get("id").map_or_else(String::new, json::to_dart_string),
            pitch: json::int_field(map, "pitch").unwrap_or(60),
            start_tick: json::int_field(map, "start_tick").unwrap_or(0),
            duration_ticks: json::int_field(map, "duration_ticks").unwrap_or(1),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("id", Value::String(self.id.clone())),
            ("pitch", Value::from(self.pitch)),
            ("start_tick", Value::from(self.start_tick)),
            ("duration_ticks", Value::from(self.duration_ticks)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TempoEvent {
    pub tick: i64,
    pub microseconds_per_quarter: i64,
}

impl TempoEvent {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            tick: json::int_field(map, "tick").unwrap_or(0),
            microseconds_per_quarter: json::int_field(map, "microseconds_per_quarter")
                .unwrap_or(500_000),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("tick", Value::from(self.tick)),
            (
                "microseconds_per_quarter",
                Value::from(self.microseconds_per_quarter),
            ),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TimeSignatureEvent {
    pub tick: i64,
    pub numerator: i64,
    pub denominator: i64,
}

impl TimeSignatureEvent {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            tick: json::int_field(map, "tick").unwrap_or(0),
            numerator: json::int_field(map, "numerator").unwrap_or(4),
            denominator: json::int_field(map, "denominator").unwrap_or(4),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("tick", Value::from(self.tick)),
            ("numerator", Value::from(self.numerator)),
            ("denominator", Value::from(self.denominator)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MusicConfig {
    pub ticks_per_quarter: i64,
    pub source_name: Option<String>,
    pub track_name: Option<String>,
    pub notes: Vec<MusicNote>,
    pub overlap_mode: MusicOverlapMode,
    pub new_note_interrupts: bool,
    pub key_signature_fifths: i64,
    pub tempo_events: Vec<TempoEvent>,
    pub time_signature_events: Vec<TimeSignatureEvent>,
}

impl Default for MusicConfig {
    fn default() -> Self {
        Self {
            ticks_per_quarter: 480,
            source_name: None,
            track_name: None,
            notes: Vec::new(),
            overlap_mode: MusicOverlapMode::Nearest,
            new_note_interrupts: true,
            key_signature_fifths: 0,
            tempo_events: vec![TempoEvent {
                tick: 0,
                microseconds_per_quarter: 500_000,
            }],
            time_signature_events: vec![TimeSignatureEvent {
                tick: 0,
                numerator: 4,
                denominator: 4,
            }],
        }
    }
}

impl MusicConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        // 注意：Dart 的 fromJson 总是传入列表（缺失时是空列表），
        // 因此这里不能用默认事件兜底——空列表会原样保留。
        let tempo_events = array_of(map.get("tempo_events"))
            .iter()
            .filter_map(Value::as_object)
            .map(TempoEvent::from_json)
            .collect();
        let time_signature_events = array_of(map.get("time_signature_events"))
            .iter()
            .filter_map(Value::as_object)
            .map(TimeSignatureEvent::from_json)
            .collect();
        Self {
            ticks_per_quarter: json::int_field(map, "ticks_per_quarter").unwrap_or(480),
            source_name: json::string_field(map, "source_name"),
            track_name: json::string_field(map, "track_name"),
            notes: array_of(map.get("notes"))
                .iter()
                .filter_map(Value::as_object)
                .map(MusicNote::from_json)
                .collect(),
            overlap_mode: MusicOverlapMode::from_value(map.get("overlap_mode"))
                .unwrap_or(MusicOverlapMode::Nearest),
            new_note_interrupts: json::bool_field(map, "new_note_interrupts").unwrap_or(true),
            key_signature_fifths: json::int_field(map, "key_signature_fifths").unwrap_or(0),
            tempo_events,
            time_signature_events,
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("ticks_per_quarter", Value::from(self.ticks_per_quarter)),
            ("source_name", string_json(self.source_name.as_deref())),
            ("track_name", string_json(self.track_name.as_deref())),
            (
                "notes",
                Value::Array(self.notes.iter().map(MusicNote::to_json).collect()),
            ),
            (
                "overlap_mode",
                Value::String(self.overlap_mode.as_str().to_owned()),
            ),
            ("new_note_interrupts", Value::Bool(self.new_note_interrupts)),
            (
                "key_signature_fifths",
                Value::from(self.key_signature_fifths),
            ),
            (
                "tempo_events",
                Value::Array(self.tempo_events.iter().map(TempoEvent::to_json).collect()),
            ),
            (
                "time_signature_events",
                Value::Array(
                    self.time_signature_events
                        .iter()
                        .map(TimeSignatureEvent::to_json)
                        .collect(),
                ),
            ),
        ])
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ActionMapping {
    pub id: String,
    pub input_kind: ActionInputKind,
    pub key: Option<String>,
    pub output_kind: ActionOutputKind,
    pub pin: Option<String>,
    pub variable_name: Option<String>,
    pub expression: Option<String>,
    pub mode: Option<ControlMode>,
    pub parameter: Option<ParamNum>,
}

impl ActionMapping {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let mode = ControlMode::from_value(map.get("mode"));
        let parameter = ParamNum::from_value(map.get("parameter"));
        let legacy_direction = Direction::from_value(map.get("direction"));
        let signed_by_direction = legacy_direction == Some(Direction::Reverse)
            && matches!(
                mode,
                Some(
                    ControlMode::Direct
                        | ControlMode::Incremental
                        | ControlMode::Single
                        | ControlMode::Continuous
                        | ControlMode::FrictionStep
                        | ControlMode::FrictionContinuous
                )
            );
        Self {
            id: map
                .get("id")
                .filter(|value| !value.is_null())
                .map(json::to_dart_string)
                .unwrap_or_else(ids::new_id),
            input_kind: ActionInputKind::from_value(map.get("input_kind"))
                .unwrap_or(ActionInputKind::Remote),
            key: json::string_field(map, "key"),
            output_kind: ActionOutputKind::from_value(map.get("output_kind"))
                .unwrap_or(ActionOutputKind::Pin),
            pin: json::string_field(map, "pin"),
            variable_name: json::string_field(map, "variable"),
            expression: json::string_field(map, "expression"),
            mode,
            parameter: if signed_by_direction {
                parameter.map(ParamNum::negated)
            } else {
                parameter
            },
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("id", Value::String(self.id.clone())),
            (
                "input_kind",
                Value::String(self.input_kind.as_str().to_owned()),
            ),
            ("key", string_json(self.key.as_deref())),
            (
                "output_kind",
                Value::String(self.output_kind.as_str().to_owned()),
            ),
            ("pin", string_json(self.pin.as_deref())),
            ("variable", string_json(self.variable_name.as_deref())),
            ("expression", string_json(self.expression.as_deref())),
            ("mode", enum_json(self.mode)),
            (
                "parameter",
                self.parameter.map_or(Value::Null, ParamNum::to_json),
            ),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ActionTableRow {
    pub pin: Option<String>,
    pub values: Vec<Option<i64>>,
}

impl ActionTableRow {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            pin: json::string_field(map, "pin"),
            values: array_of(map.get("values"))
                .iter()
                .map(|value| json::int_of(Some(value)))
                .collect(),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("pin", string_json(self.pin.as_deref())),
            (
                "values",
                Value::Array(self.values.iter().map(|value| int_json(*value)).collect()),
            ),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ActionTable {
    pub id: String,
    pub key: Option<String>,
    pub previous_key: Option<String>,
    pub steps: Option<i64>,
    pub rows: Vec<ActionTableRow>,
    pub wrap: bool,
}

impl ActionTable {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            id: map
                .get("id")
                .filter(|value| !value.is_null())
                .map(json::to_dart_string)
                .unwrap_or_else(ids::new_id),
            key: json::string_field(map, "key"),
            previous_key: json::string_field(map, "prev_key"),
            steps: json::int_field(map, "steps"),
            rows: array_of(map.get("rows"))
                .iter()
                .filter_map(Value::as_object)
                .map(ActionTableRow::from_json)
                .collect(),
            wrap: json::bool_field(map, "wrap").unwrap_or(true),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("id", Value::String(self.id.clone())),
            ("key", string_json(self.key.as_deref())),
            ("prev_key", string_json(self.previous_key.as_deref())),
            ("steps", int_json(self.steps)),
            (
                "rows",
                Value::Array(self.rows.iter().map(ActionTableRow::to_json).collect()),
            ),
            ("wrap", Value::Bool(self.wrap)),
        ])
    }
}

#[derive(Debug, Clone, PartialEq, Default)]
pub struct EngineerModeConfig {
    pub id: String,
    pub preserve_chassis: bool,
    pub actions: Vec<ActionMapping>,
    pub action_tables: Vec<ActionTable>,
}

impl EngineerModeConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        Self {
            id: map
                .get("id")
                .filter(|value| !value.is_null())
                .map(json::to_dart_string)
                .unwrap_or_else(ids::new_id),
            preserve_chassis: json::bool_field(map, "preserve_chassis").unwrap_or(false),
            actions: array_of(map.get("actions"))
                .iter()
                .filter_map(Value::as_object)
                .map(ActionMapping::from_json)
                .collect(),
            action_tables: array_of(map.get("action_tables"))
                .iter()
                .filter_map(Value::as_object)
                .map(ActionTable::from_json)
                .collect(),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        let mut entries = vec![
            ("id", Value::String(self.id.clone())),
            ("preserve_chassis", Value::Bool(self.preserve_chassis)),
            (
                "actions",
                Value::Array(self.actions.iter().map(ActionMapping::to_json).collect()),
            ),
        ];
        if !self.action_tables.is_empty() {
            entries.push((
                "action_tables",
                Value::Array(
                    self.action_tables
                        .iter()
                        .map(ActionTable::to_json)
                        .collect(),
                ),
            ));
        }
        object(entries)
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct EngineerConfig {
    pub remote: RemoteConfig,
    pub chassis: ChassisConfig,
    pub pwm: PwmGroupConfig,
    pub mode_count: Option<i64>,
    pub switch_strategy: Option<SwitchStrategy>,
    pub mode_switch_key: Option<String>,
    pub mode_keys: Vec<Option<String>>,
    pub modes: Vec<EngineerModeConfig>,
}

impl Default for EngineerConfig {
    fn default() -> Self {
        Self {
            remote: RemoteConfig::default(),
            chassis: ChassisConfig::default(),
            pwm: PwmGroupConfig::default(),
            mode_count: None,
            switch_strategy: None,
            mode_switch_key: None,
            mode_keys: vec![None, None, None, None],
            modes: vec![EngineerModeConfig {
                id: ids::new_id(),
                preserve_chassis: true,
                actions: Vec::new(),
                action_tables: Vec::new(),
            }],
        }
    }
}

impl EngineerConfig {
    #[must_use]
    pub fn from_json(map: &JsonMap) -> Self {
        let raw_keys = array_of(map.get("mode_keys"));
        let mut mode_keys: Vec<Option<String>> = raw_keys
            .iter()
            .map(|value| {
                if value.is_null() {
                    None
                } else {
                    Some(json::to_dart_string(value))
                }
            })
            .collect();
        while mode_keys.len() < 4 {
            mode_keys.push(None);
        }
        mode_keys.truncate(4);
        Self {
            remote: map_of(map.get("remote"))
                .map_or_else(RemoteConfig::default, RemoteConfig::from_json),
            chassis: map_of(map.get("chassis"))
                .map_or_else(ChassisConfig::default, ChassisConfig::from_json),
            pwm: map_of(map.get("pwm"))
                .map_or_else(PwmGroupConfig::default, PwmGroupConfig::from_json),
            mode_count: json::int_field(map, "mode_count"),
            switch_strategy: SwitchStrategy::from_value(map.get("switch_strategy")),
            mode_switch_key: json::string_field(map, "mode_switch_key"),
            mode_keys,
            modes: array_of(map.get("modes"))
                .iter()
                .filter_map(Value::as_object)
                .map(EngineerModeConfig::from_json)
                .collect(),
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        object(vec![
            ("remote", self.remote.to_json()),
            ("chassis", self.chassis.to_json()),
            ("pwm", self.pwm.to_json()),
            ("mode_count", int_json(self.mode_count)),
            ("switch_strategy", enum_json(self.switch_strategy)),
            (
                "mode_switch_key",
                string_json(self.mode_switch_key.as_deref()),
            ),
            (
                "mode_keys",
                Value::Array(
                    self.mode_keys
                        .iter()
                        .map(|value| string_json(value.as_deref()))
                        .collect(),
                ),
            ),
            (
                "modes",
                Value::Array(self.modes.iter().map(EngineerModeConfig::to_json).collect()),
            ),
        ])
    }
}

impl Default for InfantryConfig {
    fn default() -> Self {
        Self {
            remote: RemoteConfig::default(),
            chassis: ChassisConfig::default(),
            feeder_pin: None,
            feeder_direction: None,
            yaw: vec![AxisActuator::default()],
            pitch: vec![AxisActuator::default()],
            yaw_sensitivity: 100,
            pitch_sensitivity: 100,
            arrow_behavior: None,
            feed_mode: None,
            trigger_key: None,
            reverse_feed_key: None,
            trigger_speed: None,
            trigger_time_ms: None,
            friction_mode: None,
            friction_key: None,
            friction_up_key: None,
            friction_down_key: None,
            friction_p64_max_duty: None,
            friction_p66_max_duty: None,
            friction_level_step: None,
            zero_enabled: false,
            buzzer_disabled: false,
        }
    }
}
#[derive(Debug, Clone, PartialEq)]
pub enum ProjectConfig {
    Infantry(InfantryConfig),
    Engineer(EngineerConfig),
    Debug(DebugConfig),
    Music(MusicConfig),
}

impl ProjectConfig {
    #[must_use]
    pub const fn kind(&self) -> ProjectKind {
        match self {
            Self::Infantry(_) => ProjectKind::Infantry,
            Self::Engineer(_) => ProjectKind::Engineer,
            Self::Debug(_) => ProjectKind::Debug,
            Self::Music(_) => ProjectKind::Music,
        }
    }

    #[must_use]
    pub fn to_json(&self) -> Value {
        match self {
            Self::Infantry(config) => config.to_json(),
            Self::Engineer(config) => config.to_json(),
            Self::Debug(config) => config.to_json(),
            Self::Music(config) => config.to_json(),
        }
    }
}

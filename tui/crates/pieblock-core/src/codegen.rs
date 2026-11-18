//! C 代码生成（M1 移植中）。
//!
//! 对齐 `packages/pieblock_core/lib/src/code_generator.dart`：生成前先用校验器
//! 拦截错误（首条错误文案逐字一致），再按工程类型拼接源码。当前已移植调试与
//! 步兵工程；工程/音乐在后续提交补齐。

use std::collections::BTreeMap;

use crate::model::{
    ArrowBehavior, AxisActuator, ChassisConfig, DebugConfig, DebugDriveType, Direction, DriveType,
    EXPANSION_PINS, FeedMode, Friction, FrictionMode, InfantryConfig, MAIN_SERVO_PINS,
    ProjectConfig, RemoteConfig,
};
use crate::validation::{IssueSeverity, validate};

/// 生成失败：配置未通过校验，或该工程类型尚未移植。
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GenerationError {
    /// 与 Dart `StateError` 相同的文案；`message` 为第一条 error。
    InvalidConfig { message: String },
    /// 尚未移植的工程类型（M1 收尾前会补齐）。
    NotPorted { kind: &'static str },
}

impl GenerationError {
    #[must_use]
    pub fn message(&self) -> String {
        match self {
            Self::InvalidConfig { message } => {
                format!("配置尚未完成，不能生成代码：{message}")
            }
            Self::NotPorted { kind } => format!("{kind}代码生成尚未移植"),
        }
    }
}

/// 生成结果：源码 + 表达式行在源码中的行号 → 字段路径映射。
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct GeneratedProgram {
    pub source: String,
    pub expression_line_fields: BTreeMap<usize, String>,
}

/// 生成源码；配置有校验错误时返回与 Dart 相同文案的错误。
pub fn generate(config: &ProjectConfig) -> Result<String, GenerationError> {
    let issues = validate(config);
    if let Some(first) = issues
        .iter()
        .find(|issue| issue.severity == IssueSeverity::Error)
    {
        return Err(GenerationError::InvalidConfig {
            message: first.message.clone(),
        });
    }
    match config {
        ProjectConfig::Debug(debug) => Ok(debug_code(debug)),
        ProjectConfig::Infantry(infantry) => Ok(infantry_code(infantry)),
        ProjectConfig::Engineer(_) => Err(GenerationError::NotPorted { kind: "工程" }),
        ProjectConfig::Music(_) => Err(GenerationError::NotPorted {
            kind: "音乐工程"
        }),
    }
}

/// 生成源码并扫描 `/*@expr:字段*/` 标记，得到编译器回填用的行号映射。
pub fn generate_program(config: &ProjectConfig) -> Result<GeneratedProgram, GenerationError> {
    let source = generate(config)?;
    let mut expression_line_fields = BTreeMap::new();
    for (index, line) in source.split('\n').enumerate() {
        if let Some(field) = expression_marker(line) {
            expression_line_fields.insert(index + 1, field);
        }
    }
    Ok(GeneratedProgram {
        source,
        expression_line_fields,
    })
}

fn expression_marker(line: &str) -> Option<String> {
    let start = line.find("/*@expr:")? + "/*@expr:".len();
    let rest = &line[start..];
    let length = rest.find('*')?;
    if length == 0 {
        return None;
    }
    Some(rest[..length].to_owned())
}

/// 舵机角度 → 占空比；与 Dart `_servoDuty` 相同（750±500，钳到 250..=1250）。
#[must_use]
pub fn servo_duty(degrees: Option<i64>) -> i64 {
    let value = 750.0 + (degrees.unwrap_or(0) as f64) * 1000.0 / 180.0;
    (value.round() as i64).clamp(250, 1250)
}

/// 角度对应的 duty 跨度（±90° = ±500 duty）。
#[must_use]
pub fn duty_span(degrees: i64) -> i64 {
    (degrees as f64 * 1000.0 / 180.0).round() as i64
}

fn dir(value: Direction) -> i64 {
    if value == Direction::Forward { 1 } else { 0 }
}

fn key_of(key: &str) -> String {
    match key {
        "E" => "KEY_OFFSET_1".to_owned(),
        "LC" => "KEY_OFFSET_Rocker11".to_owned(),
        "RC" => "KEY_OFFSET_Rocker21".to_owned(),
        "↑" => "KEY_OFFSET_UP".to_owned(),
        "↓" => "KEY_OFFSET_DOWN".to_owned(),
        "←" => "KEY_OFFSET_LEFT".to_owned(),
        "→" => "KEY_OFFSET_RIGHT".to_owned(),
        other => format!("KEY_OFFSET_{other}"),
    }
}

fn normalize_pin(pin: Option<&str>) -> String {
    pin.and_then(|pin| pin.split(' ').next())
        .unwrap_or_default()
        .to_owned()
}

fn slot(pin: Option<&str>) -> i64 {
    let normalized = normalize_pin(pin);
    EXPANSION_PINS
        .iter()
        .position(|item| *item == normalized)
        .map_or(-1, |index| i64::try_from(index).unwrap_or(-1))
}

fn uart1_tx_query() -> &'static str {
    "static void Uart1TxQuery(uint8_t dat)\n{\n    uint8_t uart1InterruptEnabled = ES;\n\n    ES = 0;\n    TI = 0;\n    SBUF = dat;\n    while (!TI) ;\n    TI = 0;\n    ES = uart1InterruptEnabled;\n}\n"
}

fn runtime_safety(buzzer_enabled: bool) -> String {
    let mut text = String::from(
        "static void remoteControlInitWithTimeout(void)\n{\n    uint8_t retry;\n    for (retry = 0; retry < 20; retry++) {\n        if (NRF24L01_Init()) { Ms_Delay(200); return; }\n        Ms_Delay(10);\n    }\n}\n\n",
    );
    text.push_str(uart1_tx_query());
    text.push_str("\n#define LED_PORT GPIO_P3\n#define LED1_PIN GPIO_Pin_5\n#define LED2_PIN GPIO_Pin_6\n#define LED3_PIN GPIO_Pin_7\n");
    if buzzer_enabled {
        text.push_str("#define BUZZER_CH PWMA_CH4N_P33\n");
    }
    text.push_str(
        "static void LedShow(uint8_t show)\n{\n    GPIO_Write_Bit(LED_PORT, LED1_PIN, (show & 0x01) ? 0 : 1);\n    GPIO_Write_Bit(LED_PORT, LED2_PIN, (show & 0x02) ? 0 : 1);\n    GPIO_Write_Bit(LED_PORT, LED3_PIN, (show & 0x04) ? 0 : 1);\n}\nstatic void StepBegin(uint8_t step) { LedShow(step & 0x07); }\n",
    );
    if buzzer_enabled {
        text.push_str(
            "static void Beep(uint16_t freq, uint16_t ms)\n{\n    PWM_SET_Frequency(BUZZER_CH, freq, 5000);\n    Ms_Delay(ms);\n    PWM_SET_Frequency(BUZZER_CH, freq, 0);\n}\nstatic void StepDone(uint8_t step) { Beep(500 + (uint16_t)(step % 8) * 60, 60); }\n",
        );
    } else {
        text.push_str("static void StepDone(uint8_t step) { (void)step; }\n");
    }
    // Dart 的 `_runtimeSafety` 插值后，头部模板还留有换行；补齐为与 golden 相同的 3 个空行。
    text.push_str("\n\n");
    text
}

fn header(
    remote: &RemoteConfig,
    chassis: &ChassisConfig,
    chassis_enabled: bool,
    title: &str,
    buzzer_disabled: bool,
) -> String {
    let chassis_constants = if chassis_enabled {
        format!(
            "uint16_t maxSpeed = {};\nuint16_t ultraSpeed = {};\n",
            chassis.normal_speed.unwrap_or(0),
            chassis
                .sprint_speed
                .unwrap_or(chassis.normal_speed.unwrap_or(0))
        )
    } else {
        String::new()
    };
    format!(
        "// {title}（由 PIE-Block Flutter 配置器自动生成）\n#include \"main.h\"\n#include <stdlib.h>\n\nuint8_t Channal = {};\n{chassis_constants}uint16_t deadBandOfLeft = {};\nuint16_t deadBandOfRight = {};\n\n#define COMM_HEADER_1 0xAB\n#define COMM_HEADER_2 0xBC\n#define COMM_END_1 0xCD\n#define COMM_END_2 0xDE\n#define Init_Order 0xAA\n#define Duty_Change_Order 0xBB\n#define Freq_Change_Order 0xCC\n#define Dir_Change_Order 0xDD\n#define EXPANSION_FRAME_GAP_MS 5\n\nuint8_t valueOfKey[3][4];\nint valueOfRoker[2][2];\nint dutyOfMotor[8];\nuint8_t control_frame_pack[21];\n\n{}\nvoid ExpansionBoradControl(uint8_t command,\n    uint16_t p60, uint16_t p62, uint16_t p64, uint16_t p66,\n    uint16_t p74, uint16_t p75, uint16_t p76, uint16_t p77)\n{{\n    uint8_t i;\n    control_frame_pack[0] = COMM_HEADER_1;\n    control_frame_pack[1] = COMM_HEADER_2;\n    control_frame_pack[2] = command;\n    /* 逐字展开落帧，与《RM电控指南》的参考实现一致：SDCC 对\n       \"values[] 数组 + 3+i*2 变址\" 的写法会取错字节（低字节位置被写成高字节，\n       即 10000 发成 0x2727、500 发成 0x0101），这里直接从形参取高/低字节。 */\n    control_frame_pack[3] = (uint8_t)((p60 >> 8) & 0xFF);\n    control_frame_pack[4] = (uint8_t)(p60 & 0xFF);\n    control_frame_pack[5] = (uint8_t)((p62 >> 8) & 0xFF);\n    control_frame_pack[6] = (uint8_t)(p62 & 0xFF);\n    control_frame_pack[7] = (uint8_t)((p64 >> 8) & 0xFF);\n    control_frame_pack[8] = (uint8_t)(p64 & 0xFF);\n    control_frame_pack[9] = (uint8_t)((p66 >> 8) & 0xFF);\n    control_frame_pack[10] = (uint8_t)(p66 & 0xFF);\n    control_frame_pack[11] = (uint8_t)((p74 >> 8) & 0xFF);\n    control_frame_pack[12] = (uint8_t)(p74 & 0xFF);\n    control_frame_pack[13] = (uint8_t)((p75 >> 8) & 0xFF);\n    control_frame_pack[14] = (uint8_t)(p75 & 0xFF);\n    control_frame_pack[15] = (uint8_t)((p76 >> 8) & 0xFF);\n    control_frame_pack[16] = (uint8_t)(p76 & 0xFF);\n    control_frame_pack[17] = (uint8_t)((p77 >> 8) & 0xFF);\n    control_frame_pack[18] = (uint8_t)(p77 & 0xFF);\n    control_frame_pack[19] = COMM_END_1;\n    control_frame_pack[20] = COMM_END_2;\n    for (i = 0; i < 21; i++) {{\n        Uart1TxQuery(control_frame_pack[i]);\n    }}\n}}\n\nvoid ReadControllerInputs(void)\n{{\n    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);\n    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);\n    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);\n    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);\n    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft) valueOfRoker[0][0] = 0;\n    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft) valueOfRoker[0][1] = 0;\n    if (abs(valueOfRoker[1][0]) <= deadBandOfRight) valueOfRoker[1][0] = 0;\n    if (abs(valueOfRoker[1][1]) <= deadBandOfRight) valueOfRoker[1][1] = 0;\n}}\n",
        remote.channel.unwrap_or(0),
        remote.deadzone.unwrap_or(0),
        remote.deadzone.unwrap_or(0),
        runtime_safety(!buzzer_disabled),
    )
}

fn chassis_code(chassis: &ChassisConfig) -> String {
    let sprint = if chassis.sprint_enabled {
        "\n    if (RcKeyValueRead(KEY_OFFSET_Rocker11)) speed = ultraSpeed;\n"
    } else {
        ""
    };
    let turn_scale = if chassis.turn_sensitivity == 100 {
        String::new()
    } else {
        format!(
            "    turnSpeed = (int)(((int32_t)turnSpeed * {}L) / 100L);\n",
            chassis.turn_sensitivity
        )
    };
    let turn_reverse = if chassis.turn_reversed {
        "    turnSpeed = -turnSpeed;\n"
    } else {
        ""
    };
    let wheel = |wheel: &crate::model::WheelConfig, is_right: bool| {
        let direction = dir(wheel.direction.unwrap_or(Direction::Forward));
        let base_sign = if is_right {
            if direction == 1 { "-" } else { "" }
        } else if direction == 1 {
            ""
        } else {
            "-"
        };
        let turn_sign = if direction == 1 { "-" } else { "+" };
        format!(
            "    dutyOfMotor[{}] = {base_sign}baseSpeed {turn_sign} turnSpeed;",
            slot(wheel.pin.as_deref())
        )
    };
    format!(
        "void CalculateChassis(void)\n{{\n    int speed = maxSpeed;\n    int baseSpeed;\n    int turnSpeed;{sprint}\n    baseSpeed = (int)(((int32_t)-valueOfRoker[0][1] * (int32_t)speed) / 2047L);\n    turnSpeed = (int)(((int32_t)-valueOfRoker[0][0] * (int32_t)speed) / 2047L);\n{turn_scale}{turn_reverse}{}\n{}\n{}\n{}\n}}\n",
        wheel(&chassis.left_front, false),
        wheel(&chassis.left_rear, false),
        wheel(&chassis.right_front, true),
        wheel(&chassis.right_rear, true),
    )
}

fn infantry_code(config: &InfantryConfig) -> String {
    let friction_enabled = config.friction_mode == Some(FrictionMode::BrushlessEsc);
    let feeder_slot = slot(config.feeder_pin.as_deref());
    let actuators =
        |yaw: bool| -> &[AxisActuator] { if yaw { &config.yaw } else { &config.pitch } };
    let actuator_at =
        |yaw: bool, index: usize| -> Option<&AxisActuator> { actuators(yaw).get(index) };
    let duty_name = |yaw: bool, index: usize| -> String {
        let axis = if yaw { "yaw" } else { "pitch" };
        if index == 0 {
            format!("{axis}Duty")
        } else {
            format!("{axis}Duty{}", index + 1)
        }
    };
    let mut servo_actuators: Vec<(bool, usize)> = Vec::new();
    for yaw in [true, false] {
        for (index, actuator) in actuators(yaw).iter().enumerate() {
            if actuator.drive == Some(DriveType::Servo) {
                servo_actuators.push((yaw, index));
            }
        }
    }
    let mut duty_variables: Vec<(String, i64)> = Vec::new();
    for yaw in [true, false] {
        if actuators(yaw).is_empty() {
            continue;
        }
        duty_variables.push((
            duty_name(yaw, 0),
            servo_duty(actuator_at(yaw, 0).and_then(|item| item.mid_offset)),
        ));
        for (item_yaw, index) in &servo_actuators {
            if *item_yaw == yaw && *index > 0 {
                duty_variables.push((
                    duty_name(*item_yaw, *index),
                    servo_duty(actuator_at(*item_yaw, *index).and_then(|item| item.mid_offset)),
                ));
            }
        }
    }
    let axis_limits = |yaw: bool| -> (i64, i64) {
        let (mut min, mut max) = (-180_i64, 180_i64);
        for actuator in actuators(yaw) {
            if actuator.drive != Some(DriveType::Servo) {
                continue;
            }
            let mid = actuator.mid_offset.unwrap_or(0);
            let lo = actuator.min_limit.unwrap_or(-(90 + mid));
            let hi = actuator.max_limit.unwrap_or(90 - mid);
            if lo > min {
                min = lo;
            }
            if hi < max {
                max = hi;
            }
        }
        (min, max)
    };
    let actuator_update = |yaw: bool, index: usize| -> String {
        let actuator = actuator_at(yaw, index).expect("actuator exists");
        let rocker = if yaw {
            "valueOfRoker[1][0]"
        } else {
            "valueOfRoker[1][1]"
        };
        let sensitivity = if yaw {
            config.yaw_sensitivity
        } else {
            config.pitch_sensitivity
        };
        if actuator.drive == Some(DriveType::Servo) {
            let variable = duty_name(yaw, index);
            let home = servo_duty(actuator.mid_offset);
            let (min, max) = axis_limits(yaw);
            let low = (home + duty_span(min)).clamp(250, 1250);
            let high = (home + duty_span(max)).clamp(250, 1250);
            let sign = if actuator.direction == Some(Direction::Reverse) {
                "-"
            } else {
                ""
            };
            let span = if sensitivity == 100 {
                "2.0f".to_owned()
            } else {
                format!("{:.2}f", 2.0 * (sensitivity as f64) / 100.0)
            };
            format!(
                "    {variable} += (int)((float){sign}{rocker} * {span} / 2047.0f * 5.555556f);\n    if ({variable} < {low}) {variable} = {low}; if ({variable} > {high}) {variable} = {high};"
            )
        } else {
            let sign = if actuator.direction == Some(Direction::Reverse) {
                "-"
            } else {
                ""
            };
            let duty = if sensitivity == 100 {
                10000
            } else {
                100 * sensitivity
            };
            format!(
                "    dutyOfMotor[{}] = {sign}(int)(((int32_t){rocker} * {duty}L) / 2047L);",
                slot(actuator.pin.as_deref())
            )
        }
    };
    let mut gimbal_blocks: Vec<String> = Vec::new();
    for yaw in [true, false] {
        for index in 0..actuators(yaw).len() {
            gimbal_blocks.push(actuator_update(yaw, index));
        }
    }
    let duty_declarations = duty_variables
        .iter()
        .map(|(name, home)| format!("uint16_t {name} = {home};"))
        .collect::<Vec<_>>()
        .join("\n");
    let duty_resets = duty_variables
        .iter()
        .map(|(name, home)| format!("{name} = {home};"))
        .collect::<Vec<_>>()
        .join(" ");
    let servo_slot = |index: i64| -> Option<(bool, usize)> {
        for (yaw, actuator_index) in &servo_actuators {
            let actuator = actuator_at(*yaw, *actuator_index).expect("actuator");
            if slot(actuator.pin.as_deref()) == index {
                return Some((*yaw, *actuator_index));
            }
        }
        None
    };
    let duty_value = |index: i64| -> String {
        if friction_enabled {
            if index == slot(Some("P64")) {
                return "frictionDutyP64".to_owned();
            }
            if index == slot(Some("P66")) {
                return "frictionDutyP66".to_owned();
            }
        }
        if let Some((yaw, actuator_index)) = servo_slot(index) {
            return duty_name(yaw, actuator_index);
        }
        format!("abs(dutyOfMotor[{index}])")
    };
    let direction_value = |index: i64| -> String {
        if friction_enabled && (index == slot(Some("P64")) || index == slot(Some("P66"))) {
            return "1".to_owned();
        }
        if servo_slot(index).is_some() {
            return "1".to_owned();
        }
        format!("dutyOfMotor[{index}]>=0")
    };
    let duty_args = (0..8).map(duty_value).collect::<Vec<_>>().join(",");
    let direction_args = (0..8).map(direction_value).collect::<Vec<_>>().join(",");
    let mut main_servo_init: Vec<String> = Vec::new();
    let mut main_servo_updates: Vec<String> = Vec::new();
    for (yaw, index) in &servo_actuators {
        let actuator = actuator_at(*yaw, *index).expect("actuator");
        let Some(pin) = actuator.pin.as_deref() else {
            continue;
        };
        if !MAIN_SERVO_PINS.contains(&pin) {
            continue;
        }
        let channel = if pin == "MP74" { "1_P74" } else { "4_P03" };
        let duty = duty_name(*yaw, *index);
        main_servo_init.push(format!(
            "    PWM_Init(PWMB_CH{channel}, 50, {});",
            servo_duty(actuator.mid_offset)
        ));
        main_servo_updates.push(format!(
            "        PWM_SET_Frequency(PWMB_CH{channel}, 50, {duty});"
        ));
    }
    let friction_defines = if friction_enabled {
        format!(
            "#define FRICTION_START_DUTY {}\n#define FRICTION_STEP_DUTY 1\n#define FRICTION_LEVEL_MAX {}\n#define FRICTION_MAX_DUTY_P64 {}\n#define FRICTION_MAX_DUTY_P66 {}\n#define FRICTION_LEVEL_STEP {}\n/* 主循环一圈约 FRICTION_LOOP_MS 毫秒（Ms_Delay(10) 加两次 5ms 帧间隔），\n   电调激活按整圈数折算，实际保持时间不会短于 FRICTION_ACTIVATE_MS。 */\n#define FRICTION_LOOP_MS 20\n#define FRICTION_ACTIVATE_MS 1000\n#define FRICTION_ACTIVATE_LOOPS ((FRICTION_ACTIVATE_MS + FRICTION_LOOP_MS - 1) / FRICTION_LOOP_MS)\n",
            Friction::START_DUTY,
            Friction::LEVEL_MAX,
            config.friction_p64_max_duty.unwrap_or(0),
            config.friction_p66_max_duty.unwrap_or(0),
            config.friction_level_step.unwrap_or(0),
        )
    } else {
        String::new()
    };
    let friction_globals = if friction_enabled {
        "uint8_t frictionLevel = 0;\nuint16_t frictionDutyP64 = 0;\nuint16_t frictionDutyP66 = 0;\nuint16_t frictionTargetDutyP64 = 0;\nuint16_t frictionTargetDutyP66 = 0;\nuint8_t frictionEnabled = 0;\nuint8_t frictionActivateLoops = 0;\n".to_owned()
    } else {
        String::new()
    };
    let friction_helpers = if friction_enabled {
        "static uint16_t FrictionDutyOfLevel(uint8_t level, uint16_t maxDuty) {\n    return (uint16_t)(FRICTION_START_DUTY\n        + ((uint16_t)level * (uint16_t)(maxDuty - FRICTION_START_DUTY)) / FRICTION_LEVEL_MAX);\n}\n"
            .to_owned()
    } else {
        String::new()
    };
    let friction_ramp = |pin: &str| -> String {
        format!(
            "    if (frictionTargetDuty{pin} >= FRICTION_START_DUTY && frictionDuty{pin} < FRICTION_START_DUTY)\n        frictionDuty{pin} = FRICTION_START_DUTY;\n    else if (frictionDuty{pin} < frictionTargetDuty{pin})\n        frictionDuty{pin} += FRICTION_STEP_DUTY;\n    else if (frictionDuty{pin} > frictionTargetDuty{pin}) {{\n        if (frictionTargetDuty{pin} == 0 && frictionDuty{pin} <= FRICTION_START_DUTY)\n            frictionDuty{pin} = 0;\n        else\n            frictionDuty{pin} -= FRICTION_STEP_DUTY;\n    }}"
        )
    };
    let friction_update = if friction_enabled {
        format!(
            "    static uint8_t lastFriction = 0;\n    static uint8_t lastFrictionUp = 0;\n    static uint8_t lastFrictionDown = 0;\n    uint8_t friction = RcKeyValueRead({});\n    uint8_t frictionUp = RcKeyValueRead({});\n    uint8_t frictionDown = RcKeyValueRead({});\n    if (friction && !lastFriction) {{\n        frictionEnabled = !frictionEnabled;\n        frictionLevel = frictionEnabled ? FRICTION_LEVEL_MAX : 0;\n        /* 关闭时立刻取消激活残留，马上走停机斜坡，不停在启动占空比上。 */\n        if (!frictionEnabled) frictionActivateLoops = 0;\n    }}\n    if (frictionEnabled && frictionUp && !lastFrictionUp && !frictionDown) {{\n        if (frictionLevel < FRICTION_LEVEL_MAX - FRICTION_LEVEL_STEP)\n            frictionLevel += FRICTION_LEVEL_STEP;\n        else frictionLevel = FRICTION_LEVEL_MAX;\n    }}\n    if (frictionEnabled && frictionDown && !lastFrictionDown && !frictionUp) {{\n        if (frictionLevel > FRICTION_LEVEL_STEP)\n            frictionLevel -= FRICTION_LEVEL_STEP;\n        else frictionLevel = 0;\n    }}\n    /* 目标占空比每周期由油门重新映射，避免按键跳档后残留旧目标。 */\n    frictionTargetDutyP64 = frictionEnabled\n        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P64) : 0;\n    frictionTargetDutyP66 = frictionEnabled\n        ? FrictionDutyOfLevel(frictionLevel, FRICTION_MAX_DUTY_P66) : 0;\n    /* 电调激活：摩擦轮从静止（占空比 0）启动时，先保持 FRICTION_START_DUTY\n       启动占空比 FRICTION_ACTIVATE_MS，让电调完成激活后再爬坡，\n       与调试工程的摩擦轮测试同一套激活流程。 */\n    if (frictionEnabled && frictionDutyP64 == 0\n        && frictionTargetDutyP64 >= FRICTION_START_DUTY)\n        frictionActivateLoops = FRICTION_ACTIVATE_LOOPS;\n    if (frictionActivateLoops > 0) {{\n        frictionActivateLoops--;\n        frictionDutyP64 = FRICTION_START_DUTY;\n        frictionDutyP66 = FRICTION_START_DUTY;\n    }} else {{\n        /* 指南：启停时 0~5% 区间可以跳过（电机 5% 才起转），\n           因此输出只取 0 或 500~各自上限，中间的 0~500 一律跳变。\n           斜坡跑在占空比上（两侧各自 ±1 duty/周期）， duty 变化率不超过 50/s。 */\n{}\n{}\n    }}\n    lastFriction = friction;\n    lastFrictionUp = frictionUp;\n    lastFrictionDown = frictionDown;\n",
            key_of(config.friction_key.as_deref().unwrap_or("")),
            key_of(config.friction_up_key.as_deref().unwrap_or("")),
            key_of(config.friction_down_key.as_deref().unwrap_or("")),
            friction_ramp("P64"),
            friction_ramp("P66"),
        )
    } else {
        String::new()
    };
    let feed_sign = if dir(config.feeder_direction.unwrap_or(Direction::Forward)) == 1 {
        ""
    } else {
        "-"
    };
    let reverse_feed_sign = if dir(config.feeder_direction.unwrap_or(Direction::Forward)) == 1 {
        "-"
    } else {
        ""
    };
    let forward_feed = if config.feed_mode == Some(FeedMode::VisualClosedLoop) {
        format!(
            "    dutyOfMotor[{feeder_slot}] = trigger ? {feed_sign}{} : 0;\n",
            config.trigger_speed.unwrap_or(0)
        )
    } else {
        format!(
            "    if (trigger && !lastTrigger) {{\n        dutyOfMotor[{feeder_slot}] = {feed_sign}{};\n        ExpansionBoradControl(Dir_Change_Order, {direction_args});\n        Ms_Delay(EXPANSION_FRAME_GAP_MS);\n        ExpansionBoradControl(Duty_Change_Order, {duty_args});\n        Ms_Delay({});\n        dutyOfMotor[{feeder_slot}] = 0;\n    }}\n",
            config.trigger_speed.unwrap_or(0),
            config.trigger_time_ms.unwrap_or(0),
        )
    };
    let reverse_feed_update = if config.feed_mode == Some(FeedMode::VisualClosedLoop) {
        format!(
            "    if (reverseFeed) {{\n        dutyOfMotor[{feeder_slot}] = {reverse_feed_sign}{};\n    }} else {{\n        dutyOfMotor[{feeder_slot}] = trigger ? {feed_sign}{} : 0;\n    }}\n",
            config.trigger_speed.unwrap_or(0),
            config.trigger_speed.unwrap_or(0),
        )
    } else {
        format!(
            "    if (reverseFeed) {{\n        dutyOfMotor[{feeder_slot}] = {reverse_feed_sign}{};\n    }} else {{\n        if (trigger && !lastTrigger) {{\n            dutyOfMotor[{feeder_slot}] = {feed_sign}{};\n            ExpansionBoradControl(Dir_Change_Order, {direction_args});\n            Ms_Delay(EXPANSION_FRAME_GAP_MS);\n            ExpansionBoradControl(Duty_Change_Order, {duty_args});\n            Ms_Delay({});\n        }}\n        dutyOfMotor[{feeder_slot}] = 0;\n    }}\n",
            config.trigger_speed.unwrap_or(0),
            config.trigger_speed.unwrap_or(0),
            config.trigger_time_ms.unwrap_or(0),
        )
    };
    let feed_update = if config.reverse_feed_key.is_none() {
        forward_feed
    } else {
        reverse_feed_update
    };
    let reverse_feed_declaration = if config.reverse_feed_key.is_none() {
        String::new()
    } else {
        format!(
            "    uint8_t reverseFeed = RcKeyValueRead({});\n",
            key_of(config.reverse_feed_key.as_deref().unwrap_or(""))
        )
    };
    let arrow_update = match config.arrow_behavior {
        Some(ArrowBehavior::Move) => {
            "        if (RcKeyValueRead(KEY_OFFSET_UP)) valueOfRoker[0][1] = -2047;\n        if (RcKeyValueRead(KEY_OFFSET_DOWN)) valueOfRoker[0][1] = 2047;\n        if (RcKeyValueRead(KEY_OFFSET_LEFT)) valueOfRoker[0][0] = 2047;\n        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) valueOfRoker[0][0] = -2047;\n".to_owned()
        }
        Some(ArrowBehavior::Sprint) => {
            let normal = config.chassis.normal_speed.unwrap_or(0);
            format!(
                "        maxSpeed = {normal};\n        if (RcKeyValueRead(KEY_OFFSET_UP)) {{ valueOfRoker[0][1] = -2047; maxSpeed = ultraSpeed; }}\n        if (RcKeyValueRead(KEY_OFFSET_DOWN)) {{ valueOfRoker[0][1] = 2047; maxSpeed = ultraSpeed; }}\n        if (RcKeyValueRead(KEY_OFFSET_LEFT)) {{ valueOfRoker[0][0] = 2047; maxSpeed = ultraSpeed; }}\n        if (RcKeyValueRead(KEY_OFFSET_RIGHT)) {{ valueOfRoker[0][0] = -2047; maxSpeed = ultraSpeed; }}\n"
            )
        }
        Some(ArrowBehavior::Other) | None => String::new(),
    };
    let servo_duties: Vec<String> = servo_actuators
        .iter()
        .map(|(yaw, index)| duty_name(*yaw, *index))
        .collect();
    let mut feedback_checks: Vec<String> = Vec::new();
    for (index, duty) in servo_duties.iter().enumerate() {
        feedback_checks.push(format!(
            "    if (feedbackInitialized && {duty} != lastFeedbackDuty[{index}]) {{ changed = 1; feedbackDuty = {duty}; }}\n    lastFeedbackDuty[{index}] = {duty};"
        ));
    }
    let buzzer_feedback = if config.buzzer_disabled
        || (servo_duties.is_empty() && !friction_enabled)
    {
        String::new()
    } else {
        let length = if servo_duties.is_empty() {
            1
        } else {
            servo_duties.len()
        };
        let friction_else = if friction_enabled {
            "    else if (frictionActivateLoops == 0 && (frictionDutyP64 != frictionTargetDutyP64 || frictionDutyP66 != frictionTargetDutyP66)) PWM_SET_Frequency(BUZZER_CH, frictionDutyP64, 5000);"
        } else {
            ""
        };
        format!(
            "static uint8_t feedbackInitialized = 0;\nstatic uint16_t lastFeedbackDuty[{length}] = {{0}};\nstatic void UpdateBuzzerFeedback(void)\n{{\n    uint8_t changed = 0;\n    uint16_t feedbackDuty = 0;\n{}\n    if (!feedbackInitialized) {{ feedbackInitialized = 1; changed = 0; }}\n    if (changed) PWM_SET_Frequency(BUZZER_CH, feedbackDuty, 5000);\n{friction_else}\n    else PWM_SET_Frequency(BUZZER_CH, 500, 0);\n}}\n",
            feedback_checks.join("\n")
        )
    };
    let buzzer_init_line = if config.buzzer_disabled {
        ""
    } else {
        "    PWM_Init(BUZZER_CH, 500, 0);\n"
    };
    let buzzer_beep_block = if config.buzzer_disabled {
        String::new()
    } else {
        "    Beep(523, 120);\n    Beep(659, 120);\n    Beep(784, 120);\n    Beep(1047, 240);"
            .to_owned()
    };
    let zero_reset = if config.zero_enabled {
        format!("    if (RcKeyValueRead(KEY_OFFSET_Rocker21)) {{ {duty_resets} }}")
    } else {
        String::new()
    };
    let buzzer_feedback_call = if buzzer_feedback.is_empty() {
        ""
    } else {
        "        UpdateBuzzerFeedback();"
    };
    let friction_globals_line = if friction_globals.is_empty() {
        String::new()
    } else {
        friction_globals
    };
    let friction_defines_line = if friction_defines.is_empty() {
        String::new()
    } else {
        friction_defines
    };
    let friction_helpers_line = if friction_helpers.is_empty() {
        String::new()
    } else {
        friction_helpers
    };
    let mut source = String::new();
    source.push_str(&header(
        &config.remote,
        &config.chassis,
        true,
        "步兵机器人控制代码",
        config.buzzer_disabled,
    ));
    source.push('\n');
    source.push_str(&friction_defines_line);
    source.push('\n');
    source.push_str(&duty_declarations);
    source.push('\n');
    source.push_str(&friction_globals_line);
    source.push('\n');
    source.push_str(&friction_helpers_line);
    source.push('\n');
    source.push_str(&buzzer_feedback);
    source.push_str("\n\n");
    source.push_str(&chassis_code(&config.chassis));
    source.push('\n');
    source.push_str("void All_Init(void)\n{\n    StepBegin(0);\n    Board_Init();\n    StepDone(0);\n    StepBegin(1);\n    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);\n    StepDone(1);\n    GPIO_Init(LED_PORT, (GPIO_Pin_enum)(LED1_PIN | LED2_PIN | LED3_PIN), GPIO_OUT_PP);\n");
    source.push_str(buzzer_init_line);
    source.push_str("    StepBegin(3);\n    EA = 0;\n    remoteControlInitWithTimeout();\n    P2INTE &= ~GPIO_Pin_6;\n    EA = 1;\n    StepDone(3);\n    ExpansionBoradControl(Init_Order, 50, 50, 50, 50, 10000, 10000, 10000, 10000);\n");
    if !main_servo_init.is_empty() {
        source.push_str(&main_servo_init.join("\n"));
        source.push('\n');
    }
    source.push_str("    Ms_Delay(1000);\n");
    if !buzzer_beep_block.is_empty() {
        source.push_str(&buzzer_beep_block);
        source.push('\n');
    }
    source.push_str("}\n\nvoid UpdateGimbal(void)\n{\n");
    source.push_str(&gimbal_blocks.join("\n"));
    source.push('\n');
    source.push_str("    ");
    if !zero_reset.is_empty() {
        source.push_str(&zero_reset);
    }
    source.push('\n');
    source.push_str("}\n\nvoid UpdateWeapons(void)\n{\n    static uint8_t lastTrigger = 0;\n    uint8_t trigger = RcKeyValueRead(");
    source.push_str(&key_of(config.trigger_key.as_deref().unwrap_or("")));
    source.push_str(");\n");
    source.push_str(&reverse_feed_declaration);
    source.push_str(&friction_update);
    source.push_str(&feed_update);
    source.push_str("\n    lastTrigger = trigger;\n}\n\nvoid main(void)\n{\n    All_Init();\n    while (1) {\n        nrf_handler(); // 轮询 NRF 接收（P2.6 中断已关）\n        ReadControllerInputs();\n");
    source.push_str(&arrow_update);
    source.push('\n');
    source.push_str("        CalculateChassis();\n        UpdateGimbal();\n        UpdateWeapons();\n        ExpansionBoradControl(Dir_Change_Order, ");
    source.push_str(&direction_args);
    source.push_str(");\n        Ms_Delay(EXPANSION_FRAME_GAP_MS);\n        ExpansionBoradControl(Duty_Change_Order, ");
    source.push_str(&duty_args);
    source.push_str(");\n        Ms_Delay(EXPANSION_FRAME_GAP_MS);\n");
    if !main_servo_updates.is_empty() {
        source.push_str(&main_servo_updates.join("\n"));
        source.push('\n');
    }
    if !buzzer_feedback_call.is_empty() {
        source.push_str(buzzer_feedback_call);
        source.push('\n');
    }
    source.push_str("        Ms_Delay(10);\n    }\n}\n");
    source
}

fn values(slot: usize, value: i64) -> String {
    (0..8)
        .map(|index| {
            if index == slot {
                value.to_string()
            } else {
                "0".to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn init_values(slot: usize, frequency: i64) -> String {
    let start = if slot < 4 { 0 } else { 4 };
    (0..8)
        .map(|index| {
            if (start..start + 4).contains(&index) {
                frequency.to_string()
            } else {
                "50".to_owned()
            }
        })
        .collect::<Vec<_>>()
        .join(", ")
}

fn debug_code(config: &DebugConfig) -> String {
    let mut commands: Vec<String> = Vec::new();
    let active: Vec<&crate::model::DebugTestItem> =
        config.tests.iter().filter(|item| item.enabled).collect();
    let mut group_frequencies = [50_i64, 50_i64];
    for (index, item) in active.iter().enumerate() {
        let friction = item.drive_type == Some(DebugDriveType::Friction);
        let frequency = if friction || item.drive_type == Some(DebugDriveType::Servo) {
            50
        } else {
            10000
        };
        let expansion_slot = EXPANSION_PINS.iter().position(|pin| *pin == item.pin);
        let mut need_init = false;
        if let Some(slot) = expansion_slot {
            let desired = if slot < 4 {
                [frequency, 50]
            } else {
                [50, frequency]
            };
            need_init = group_frequencies[0] != desired[0] || group_frequencies[1] != desired[1];
            if need_init {
                group_frequencies = desired;
            }
        }
        let mut lines: Vec<String> = vec![
            format!(
                "    /* {}. {} {} */",
                index + 1,
                item.pin,
                item.drive_type.map(DebugDriveType::as_str).unwrap_or("")
            ),
            format!("    StepCue({});", index + 1),
            "    Ms_Delay(CUE_SECTION_GAP_MS);".to_owned(),
        ];
        if need_init {
            lines.push(format!(
                "    ExpansionBoradControl(Init_Order, {});",
                init_values(expansion_slot.unwrap_or(0), frequency)
            ));
        }
        if expansion_slot.is_none() {
            let channel = if item.pin == "MP74" {
                "PWMB_CH1_P74"
            } else {
                "PWMB_CH4_P03"
            };
            let angle = item.value.unwrap_or(0);
            lines.push(format!(
                "    PWM_Init({channel}, 50, {});",
                servo_duty(Some(angle))
            ));
            lines.push(format!("    Ms_Delay({});", item.duration_ms));
            lines.push(format!("    PWM_SET_Frequency({channel}, 50, 0);"));
        } else if friction {
            let target_duty = item.value.unwrap_or(0);
            let slot = expansion_slot.unwrap_or(0);
            lines.push("    Ms_Delay(1000);".to_owned());
            lines.push(format!("    FrictionActivate({slot});"));
            lines.push(format!("    FrictionRampTo({slot}, {target_duty});"));
            lines.push("    Ms_Delay(FRICTION_STEP_MS);".to_owned());
            lines.push(format!("    FrictionRampTo({slot}, 0);"));
        } else {
            let slot = expansion_slot.unwrap_or(0);
            let servo = item.drive_type == Some(DebugDriveType::Servo);
            let value = item.value.unwrap_or(0);
            let duty = if servo {
                servo_duty(Some(value))
            } else {
                value.abs()
            };
            if need_init {
                lines.push("    Ms_Delay(20);".to_owned());
            }
            if !servo {
                lines.push(format!(
                    "    ExpansionBoradControl(Dir_Change_Order, {});",
                    values(slot, i64::from(value >= 0))
                ));
                lines.push("    Ms_Delay(EXPANSION_FRAME_GAP_MS);".to_owned());
            }
            lines.push(format!(
                "    ExpansionBoradControl(Duty_Change_Order, {});",
                values(slot, duty)
            ));
            lines.push(format!("    Ms_Delay({});", item.duration_ms));
            lines.push(format!(
                "    ExpansionBoradControl(Duty_Change_Order, {});",
                values(slot, 0)
            ));
        }
        lines.push("    Ms_Delay(TEST_GAP_MS);".to_owned());
        commands.push(lines.join("\n"));
    }
    let loop_body = commands
        .iter()
        .map(|command| {
            command
                .split('\n')
                .map(|line| format!("    {line}"))
                .collect::<Vec<_>>()
                .join("\n")
        })
        .collect::<Vec<_>>()
        .join("\n\n");
    DEBUG_TEMPLATE.replace("__LOOP_BODY__", &loop_body)
}

const DEBUG_TEMPLATE: &str = include_str!("codegen_debug_template.rs");

class_name PwmConfig
extends RefCounted

## PWM 组频率和输出角色的共享定义。
## 频率是 PWM 组级配置；角色是引脚级语义，两者不能互相覆盖。

const FREQ_LOW: int = 50
const FREQ_SMOOTH_MOTOR: int = 10000
const GROUP_PWMA: String = "PWMA"
const GROUP_PWMB: String = "PWMB"
const GROUP_PWMA_PINS: Array = ["P60", "P62", "P64", "P66"]
const GROUP_PWMB_PINS: Array = ["P74", "P75", "P76", "P77"]
const EXPANSION_PINS: Array = [
	"P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"
]
const ALL_ROLES: Array = ["舵机", "摩擦轮", "抖动电机", "平滑电机"]


static func normalize_role(value: Variant, fallback: String = "舵机") -> String:
	var role: String = str(value)
	if role == "电机":
		return "平滑电机"
	if role in ALL_ROLES:
		return role
	return fallback if fallback in ALL_ROLES else "舵机"


static func is_servo_role(role: Variant) -> bool:
	return normalize_role(role) == "舵机"


static func is_motor_role(role: Variant) -> bool:
	return normalize_role(role) != "舵机"


static func expected_frequency(role: Variant) -> int:
	var normalized: String = normalize_role(role)
	return FREQ_SMOOTH_MOTOR if normalized == "平滑电机" else FREQ_LOW


static func group_for_pin(pin: String) -> String:
	if pin in GROUP_PWMA_PINS:
		return GROUP_PWMA
	if pin in GROUP_PWMB_PINS:
		return GROUP_PWMB
	return ""


static func parse_frequency(value: Variant, fallback: int = FREQ_LOW) -> int:
	if value is int or value is float:
		var numeric: int = int(value)
		return numeric if numeric in [FREQ_LOW, FREQ_SMOOTH_MOTOR] else fallback
	var text: String = str(value).strip_edges()
	if text in ["50", "50Hz"]:
		return FREQ_LOW
	if text in ["10000", "10000Hz"]:
		return FREQ_SMOOTH_MOTOR
	return fallback


static func group_frequency(cfg: Dictionary, group: String, fallback: int = FREQ_LOW,
		force_infantry_pwma: bool = false) -> int:
	if force_infantry_pwma and group == GROUP_PWMA:
		return FREQ_LOW
	var raw: Variant = cfg.get("pwm_group_init", {})
	if raw is Dictionary:
		return parse_frequency((raw as Dictionary).get(group, fallback), fallback)
	return fallback


static func group_frequency_text(freq: int) -> String:
	return "10000Hz" if freq == FREQ_SMOOTH_MOTOR else "50Hz"


static func role_map_from_config(cfg: Dictionary, pins: Array) -> Dictionary:
	var out: Dictionary = {}
	var raw_roles: Variant = cfg.get("io_role", {})
	var raw_legacy: Variant = cfg.get("io_init", {})
	for pin in pins:
		var value: Variant = "舵机"
		if raw_roles is Dictionary and (raw_roles as Dictionary).has(pin):
			value = (raw_roles as Dictionary).get(pin)
		elif raw_legacy is Dictionary and (raw_legacy as Dictionary).has(pin):
			value = (raw_legacy as Dictionary).get(pin)
		out[pin] = normalize_role(value)
	return out

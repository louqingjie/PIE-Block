class_name CodeGenBase
extends RefCounted

## 代码生成器基类。
## 定义所有代码生成器共享的接口与工具函数。
## 子类必须重写 generate()，根据配置字典生成完整的 main.c 代码字符串。

## 生成 main.c 代码。子类必须重写此方法。
func generate(cfg: Dictionary) -> String:
	push_error("CodeGenBase.generate() 必须由子类重写")
	return ""


# ============================================================ 共享工具函数
## 从 IO 对字符串中提取通信脚（前半），如 "P77 P27" -> "P77"
func _parse_io_pair(text: String) -> String:
	var parts: PackedStringArray = text.split(" ")
	if parts.size() > 0:
		return parts[0]
	return text


## 取整数配置项：非法或越界时回退到默认值，保证生成的 C 代码总能编译
func _int_or_default(text: String, default_val: int, lo: int, hi: int) -> String:
	var s: String = text.strip_edges()
	if not s.is_valid_int():
		return str(default_val)
	return str(clampi(s.to_int(), lo, hi))


## IO 引脚名映射到拓展板槽位序号
## P60->0(拨弹), P62->1(空), P64->2(摩擦L), P66->3(摩擦R),
## P74->4(LF), P75->5(LR), P76->6(RF), P77->7(RR)
func _io_to_exp_slot(pin: String) -> int:
	var mapping: Dictionary = {
		"P60": 0, "P62": 1, "P64": 2, "P66": 3,
		"P74": 4, "P75": 5, "P76": 6, "P77": 7,
	}
	return mapping.get(pin, -1)


## 按键名称映射到 C 代码中的 KEY_OFFSET 宏名
## 注意：右方向键在不同界面里分别写作 "→"(U+2192) 和 "->"，两种写法都要覆盖
func _key_name_to_offset(name: String) -> String:
	var mapping: Dictionary = {
		"R": "KEY_OFFSET_1",
		"↑": "KEY_OFFSET_UP",
		"↓": "KEY_OFFSET_DOWN",
		"←": "KEY_OFFSET_LEFT",
		"→": "KEY_OFFSET_RIGHT",
		"->": "KEY_OFFSET_RIGHT",
		"A": "KEY_OFFSET_A",
		"B": "KEY_OFFSET_B",
		"C": "KEY_OFFSET_C",
		"D": "KEY_OFFSET_D",
	}
	if not mapping.has(name):
		push_warning("_key_name_to_offset: 未知按键名 %s，已回退到 R 键" % name)
	return mapping.get(name, "KEY_OFFSET_1")


## 方向文本映射到 C 代码中的整数值（Dir_Change_Order: 1=正, 0=负）
func _dir_to_int(text: String) -> int:
	if text == "正向":
		return 1
	return 0


## 主控板专用舵机引脚（只能驱动舵机，不在扩展板上）
const MAIN_BOARD_SERVO_PINS: Array = ["MP74", "MP03"]

## 舵机占空比范围（50Hz 下，万分比）：
## 500 = 1ms 脉宽 = 行程一端（-90°）
## 750 = 1.5ms = 中位（0°）
## 1000 = 2ms = 行程另一端（+90°）
const SERVO_DUTY_MIN: int = 500
const SERVO_DUTY_MID: int = 750
const SERVO_DUTY_MAX: int = 1000
## 所有舵机角度参数均为「相对中位的偏移角」，有效区间 [-90, +90]
const SERVO_MAX_OFFSET_DEG: int = 90


## 相对中位的偏移角（-90~90）映射到占空比，0° -> 750
func _servo_angle_to_duty(angle: int) -> int:
	# ±90° 共 180° 行程对应 500 duty
	var span: int = SERVO_DUTY_MAX - SERVO_DUTY_MIN
	var duty: int = SERVO_DUTY_MID + int(round(
		float(angle) * float(span) / float(SERVO_MAX_OFFSET_DEG * 2)))
	return clampi(duty, SERVO_DUTY_MIN, SERVO_DUTY_MAX)


## 角度差（度）换算成占空比差，不做中位偏移。用于限幅幅度、按键步长等
func _servo_deg_to_duty_delta(deg: float) -> int:
	var span: int = SERVO_DUTY_MAX - SERVO_DUTY_MIN
	return int(round(deg * float(span) / float(SERVO_MAX_OFFSET_DEG * 2)))


## IO 引脚名映射到 PWM 通道枚举
## MP74 / MP03 是主控板舵机端口，与扩展板 P74 不同
func _pin_to_pwm_channel(pin: String) -> String:
	var mapping: Dictionary = {
		"MP74": "PWMB_CH1_P74",
		"MP03": "PWMB_CH4_P03",
		"P24": "PWMA_CH3P_P24",
		"P25": "PWMA_CH3N_P25",
		"P26": "PWMA_CH4P_P26",
		"P27": "PWMA_CH4N_P27",
		"P74": "PWMB_CH1_P74",
		"P75": "PWMB_CH2_P75",
		"P76": "PWMB_CH3_P76",
		"P77": "PWMB_CH4_P77",
		"P03": "PWMB_CH4_P03",
		"P20": "PWMB_CH1_P20",
		"P21": "PWMB_CH2_P21",
		"P22": "PWMB_CH3_P22",
		"P23": "PWMB_CH4_P23",
		"P00": "PWMB_CH1_P00",
		"P01": "PWMB_CH2_P01",
		"P02": "PWMB_CH3_P02",
		"P17": "PWMB_CH1_P17",
		"P33": "PWMB_CH3_P33",
		"P34": "PWMB_CH4_P34",
		"P54": "PWMB_CH2_P54",
	}
	var ch: String = mapping.get(pin, "")
	if ch.is_empty():
		push_warning("_pin_to_pwm_channel: 未知引脚 %s，请确认是主控板舵机端口 MP74 或 MP03" % pin)
		return "PWMB_CH1_P74" # 兜底，实际应被静态检查拦截
	return ch

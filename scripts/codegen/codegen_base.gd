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
func _key_name_to_offset(name: String) -> String:
	var mapping: Dictionary = {
		"R": "KEY_OFFSET_1",
		"↑": "KEY_OFFSET_UP",
		"↓": "KEY_OFFSET_DOWN",
		"←": "KEY_OFFSET_LEFT",
		"->": "KEY_OFFSET_RIGHT",
		"A": "KEY_OFFSET_A",
		"B": "KEY_OFFSET_B",
		"C": "KEY_OFFSET_C",
		"D": "KEY_OFFSET_D",
	}
	return mapping.get(name, "KEY_OFFSET_1")


## 方向文本映射到 C 代码中的整数值（Dir_Change_Order: 1=正, 0=负）
func _dir_to_int(text: String) -> int:
	if text == "正向":
		return 1
	return 0

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

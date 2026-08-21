extends SceneTree

## 固件生成器舵机 Duty 蜂鸣反馈测试。
## 只检查生成文本，不依赖 C251 外部工具链：
## godot --headless --path . --script res://scripts/test_codegen_servo_buzzer.gd

const Infantry = preload("res://scripts/codegen/codegen_infantry.gd")
const Engineer = preload("res://scripts/codegen/codegen_engineer.gd")
const Debug = preload("res://scripts/codegen/codegen_debug.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _helper(code: String) -> String:
	var start: int = code.find("// 舵机 Duty 变化蜂鸣反馈")
	if start < 0:
		return ""
	var end: int = code.find("void main", start)
	return code.substr(start, end - start if end >= 0 else code.length() - start)


func _mode_controls(code: String) -> String:
	var start: int = code.find("void Calculate_Mode1_Controls()\n{")
	var end: int = code.find("void Main_Countrol()", start)
	return code.substr(start, end - start if start >= 0 and end > start else 0)


func _debug_row_section(code: String, pin: String) -> String:
	var start: int = code.find("// ===== 测试 %s" % pin)
	var end: int = code.find("Buzzer_Play(BUZZER_FREQ_DONE", start)
	return code.substr(start, end - start if start >= 0 and end > start else 0)


func _init_frequencies_are_valid(code: String) -> bool:
	var marker: String = "ExpansionBoradControl(Init_Order,"
	var cursor: int = 0
	var found: bool = false
	while true:
		var start: int = code.find(marker, cursor)
		if start < 0:
			break
		found = true
		var body_start: int = start + marker.length()
		var end: int = code.find(");", body_start)
		if end < 0:
			return false
		var values: PackedStringArray = code.substr(body_start, end - body_start).replace("\n", "").split(",")
		if values.size() != 8:
			return false
		for raw in values:
			var value: String = raw.strip_edges()
			if not value.is_valid_int() or not value.to_int() in [50, 10000]:
				return false
		cursor = end + 2
	return found


func _infantry_cfg(yaw: String = "舵机", pitch: String = "舵机",
		friction: String = "不使用") -> Dictionary:
	return {
		"friction_type": friction,
		"yaw_drive": yaw, "yaw_io": "MP74",
		"pitch_drive": pitch, "pitch_io": "MP03",
		"friction_max_duty": "800", "friction_speed_step": "100",
	}


func _engineer_cfg(with_servos: bool = true) -> Dictionary:
	var rows: Array = []
	if with_servos:
		# 故意按非物理顺序填写，生成器仍应按 P60、P62、MP03、MP74 排序。
		for io in ["MP74", "P62", "MP03", "P60"]:
			rows.append({"key": "A", "dir": "正", "mode": "增量",
				"param": "2", "io": io})
	return {
		"mode_count": 1,
		"l1_io": "P90 P91", "l2_io": "P92 P93",
		"r1_io": "P94 P95", "r2_io": "P96 P97",
		"io_init": {"P60": "舵机", "P62": "舵机", "MP03": "舵机", "MP74": "舵机"},
		"modes": [{"rows": rows}],
	}


func _initialize() -> void:
	var infantry = Infantry.new()
	var infantry_code: String = infantry.generate(_infantry_cfg())
	_check("步兵初始化频率不含 0", _init_frequencies_are_valid(infantry_code))
	var infantry_helper: String = _helper(infantry_code)
	_check("步兵生成舵机变化状态", infantry_helper.contains("lastServoBuzzerDuty[2]"))
	_check("步兵使用实际整数 Duty 比较", infantry_helper.contains("currentDuty = (uint16_t)(dutyOfServo[0]);")
		and infantry_helper.contains("currentDuty = (uint16_t)(dutyOfServo[1]);"))
	var infantry_friction_code: String = infantry.generate(_infantry_cfg("舵机", "舵机", "无刷电调"))
	var infantry_friction_helper: String = _helper(infantry_friction_code)
	_check("步兵舵机变化优先于摩擦轮", infantry_friction_helper.find("if (changed)") < infantry_friction_helper.find("else if (frictionBuzzerActive)"))
	_check("步兵稳定后停止蜂鸣", infantry_helper.contains("PWM_SET_Frequency(BUZZER_CH, 500, 0);"))
	_check("步兵发送后更新蜂鸣", infantry_code.find("Main_Countrol(dutyOfMotor, dutyOfServo);") < infantry_code.find("UpdateBuzzerFeedback();"))
	var infantry_no_servo: String = infantry.generate(_infantry_cfg("电机", "电机"))
	_check("步兵无舵机且无摩擦轮时不生成反馈", not infantry_no_servo.contains("UpdateBuzzerFeedback")
		and not infantry_no_servo.contains("lastServoBuzzerDuty"))

	var engineer_code: String = Engineer.new().generate(_engineer_cfg())
	_check("工程映射初始化频率不含 0", _init_frequencies_are_valid(engineer_code))
	var engineer_helper: String = _helper(engineer_code)
	_check("工程映射生成舵机反馈", engineer_helper.contains("lastServoBuzzerDuty[4]"))
	var order: Array = [
		engineer_helper.find("dutyOfAuxServo[0]"),
		engineer_helper.find("dutyOfAuxServo[1]"),
		engineer_helper.find("dutyOfAuxMainServo[0]"),
		engineer_helper.find("dutyOfAuxMainServo[1]"),
	]
	_check("工程映射按扩展板再主控板固定顺序检测", order[0] >= 0 and order[0] < order[1]
		and order[1] < order[2] and order[2] < order[3])
	_check("工程映射稳定后停止蜂鸣", engineer_helper.contains("PWM_SET_Frequency(BUZZER_CH, 500, 0);"))
	_check("工程映射发送后更新蜂鸣", engineer_code.find("Main_Countrol();") < engineer_code.find("UpdateBuzzerFeedback();"))
	var engineer_no_servo: String = Engineer.new().generate(_engineer_cfg(false))
	_check("工程映射无配置舵机时不生成反馈", not engineer_no_servo.contains("UpdateBuzzerFeedback")
		and not engineer_no_servo.contains("lastServoBuzzerDuty"))

	_check("工程反馈函数不引入阻塞延时", not engineer_helper.contains("Ms_Delay"))
	_check("工程首周期只建立比较基准", engineer_helper.contains("if (!servoBuzzerInitialized)")
		and engineer_helper.contains("changed = 0;"))

	var direct_positive_cfg: Dictionary = _engineer_cfg(false)
	direct_positive_cfg["modes"] = [{"rows": [{"key": "A", "dir": "正", "mode": "直接",
		"param": "30", "io": "P60"}]}]
	var direct_positive_code: String = Engineer.new().generate(direct_positive_cfg)
	var direct_positive_controls: String = _mode_controls(direct_positive_code)
	_check("工程舵机直接正向增加角度",
		direct_positive_controls.contains("dutyOfAuxServo[0] = 917.0f; // +30°"))
	_check("工程舵机映射不发送硬件方向帧",
		not direct_positive_controls.contains("Dir_Change_Order"))

	var direct_negative_cfg: Dictionary = direct_positive_cfg.duplicate(true)
	direct_negative_cfg["modes"][0]["rows"][0]["dir"] = "反"
	var direct_negative_code: String = Engineer.new().generate(direct_negative_cfg)
	_check("工程舵机直接反向减少角度",
		_mode_controls(direct_negative_code).contains("dutyOfAuxServo[0] = 583.0f; // -30°"))

	var debug_code: String = Debug.new().generate({
		"debug_rows": [{"pin": "P60", "drive_type": "电机", "dir": 1,
			"value": 1000, "enabled": true}],
	})
	_check("调试初始化频率不含 0", _init_frequencies_are_valid(debug_code))
	var debug_servo_code: String = Debug.new().generate({
		"debug_rows": [{"pin": "P60", "drive_type": "舵机", "dir": 0,
			"value": 30, "enabled": true}],
	})
	_check("调试舵机反向使用负角度占空比",
		debug_servo_code.contains("ExpansionBoradControl(Duty_Change_Order, 583, 0"))
	_check("调试舵机不发送硬件方向帧",
		not _debug_row_section(debug_servo_code, "P60").contains("Dir_Change_Order"))

	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

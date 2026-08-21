extends SceneTree

## 固件生成器舵机 Duty 蜂鸣反馈测试。
## 只检查生成文本，不依赖 C251 外部工具链：
## godot --headless --path . --script res://scripts/test_codegen_servo_buzzer.gd

const Infantry = preload("res://scripts/codegen/codegen_infantry.gd")
const Engineer = preload("res://scripts/codegen/codegen_engineer.gd")
const EngineerIK = preload("res://scripts/codegen/codegen_engineer_ik.gd")

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


func _ik_cfg() -> Dictionary:
	return {
		"joint_count": 2,
		"joints": [
			{"io": "P74", "axis": "Yaw", "len": "100", "zero": "0",
				"min": "-90", "max": "90", "dir": "正向"},
			{"io": "MP03", "axis": "Pitch", "len": "80", "zero": "0",
				"min": "-90", "max": "90", "dir": "正向"},
		],
		"gripper": {"enabled": true, "io": "P75", "open_angle": "45",
			"closed_angle": "-45", "initial_open": true, "key": "D"},
	}


func _initialize() -> void:
	var infantry = Infantry.new()
	var infantry_code: String = infantry.generate(_infantry_cfg())
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
	var engineer_helper: String = _helper(engineer_code)
	_check("工程正解生成舵机反馈", engineer_helper.contains("lastServoBuzzerDuty[4]"))
	var order: Array = [
		engineer_helper.find("dutyOfAuxServo[0]"),
		engineer_helper.find("dutyOfAuxServo[1]"),
		engineer_helper.find("dutyOfAuxMainServo[0]"),
		engineer_helper.find("dutyOfAuxMainServo[1]"),
	]
	_check("工程正解按扩展板再主控板固定顺序检测", order[0] >= 0 and order[0] < order[1]
		and order[1] < order[2] and order[2] < order[3])
	_check("工程正解稳定后停止蜂鸣", engineer_helper.contains("PWM_SET_Frequency(BUZZER_CH, 500, 0);"))
	_check("工程正解发送后更新蜂鸣", engineer_code.find("Main_Countrol();") < engineer_code.find("UpdateBuzzerFeedback();"))
	var engineer_no_servo: String = Engineer.new().generate(_engineer_cfg(false))
	_check("工程正解无配置舵机时不生成反馈", not engineer_no_servo.contains("UpdateBuzzerFeedback")
		and not engineer_no_servo.contains("lastServoBuzzerDuty"))

	var ik_code: String = EngineerIK.new().generate(_ik_cfg())
	var ik_helper: String = _helper(ik_code)
	_check("工程逆解生成关节与夹爪反馈", ik_helper.contains("lastServoBuzzerDuty[3]")
		and ik_helper.contains("dutyOfServo[0]") and ik_helper.contains("dutyOfServo[1]")
		and ik_helper.contains("dutyOfGripper"))
	_check("工程逆解应用舵机后更新蜂鸣", ik_code.find("ApplyServoControl();") < ik_code.find("UpdateBuzzerFeedback();"))
	_check("反馈函数不引入阻塞延时", not ik_helper.contains("Ms_Delay") and not engineer_helper.contains("Ms_Delay"))
	_check("首周期只建立比较基准", ik_helper.contains("if (!servoBuzzerInitialized)")
		and ik_helper.contains("changed = 0;"))

	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

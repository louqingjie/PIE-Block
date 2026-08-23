extends SceneTree

## PWM 分组初始化迁移回归测试。

const SC = preload("res://scripts/static_checker.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s%s" % [label, ("：" + detail) if not detail.is_empty() else ""])
		_fail += 1


func _has_issue(issues: Array, issue_type: String, text: String) -> bool:
	for issue in issues:
		if str(issue.get("type", "")) == issue_type \
				and str(issue.get("msg", "")).contains(text):
			return true
	return false


func _engineer_cfg(pwm_a: String, pwm_b: String) -> Dictionary:
	return {
		"pwm_group_init": {"PWMA": pwm_a, "PWMB": pwm_b},
		"io_role": {
			"P60": "平滑电机", "P62": "舵机", "P64": "舵机", "P66": "舵机",
			"P74": "平滑电机", "P75": "平滑电机", "P76": "平滑电机", "P77": "平滑电机",
			"MP03": "舵机", "MP74": "舵机",
		},
		"io_mid": {},
		"channel": "36", "deadzone": "10", "normal_speed": "4000", "sprint_speed": "8000",
		"l1_io": "P74 P24", "l2_io": "P75 P25", "r1_io": "P76 P26", "r2_io": "P77 P27",
		"l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
		"sprint_enabled": false, "mode_count": 1, "switch_strategy": "单击切换",
		"mode_switch_key": "E", "mode_keys": ["A", "B", "C", "D"],
		"modes": [{"rows": []}],
	}


func _infantry_cfg(pwm_b: String) -> Dictionary:
	return {
		"pwm_group_init": {"PWMA": "50Hz", "PWMB": pwm_b},
		"channel": "36", "deadzone": "10", "normal_speed": "4000", "sprint_speed": "8000",
		"sprint_enabled": false,
		"l1_io": "P74 P24", "l2_io": "P75 P25", "r1_io": "P76 P26", "r2_io": "P77 P27",
		"l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
		"booster_io": "P60 P61", "booster_dir": "正向",
		"yaw_drive": "舵机", "yaw_io": "MP74", "yaw_dir": "正向", "yaw_mid_offset": "0",
		"pitch_drive": "舵机", "pitch_io": "MP03", "pitch_dir": "正向", "pitch_mid_offset": "0",
		"friction_type": "不使用", "feed_mode": "阻塞开环", "trigger_key": "E",
		"trigger_speed": "4000", "trigger_time": "100", "arrow_key": "移动",
	}


func _initialize() -> void:
	var engineer_50: String = CodeGenEngineer.new().generate(_engineer_cfg("50Hz", "10000Hz"))
	_check("工程 PWMA=50/PWMB=10000 按组生成",
		engineer_50.contains("50, 50,\n                          50, 50")
		and engineer_50.contains("10000, 10000,\n                          10000, 10000"))
	var engineer_10k: String = CodeGenEngineer.new().generate(_engineer_cfg("10000Hz", "50Hz"))
	_check("工程 PWMA=10000/PWMB=50 按组生成",
		engineer_10k.contains("10000, 10000,\n                          10000, 10000")
		and engineer_10k.contains("50, 50,\n                          50, 50"))

	var infantry_10k: String = CodeGenInfantry.new().generate(_infantry_cfg("10000Hz"))
	var infantry_init_start: int = infantry_10k.find("ExpansionBoradControl(Init_Order,")
	var infantry_init: String = infantry_10k.substr(infantry_init_start, 260) \
		if infantry_init_start >= 0 else ""
	_check("步兵 PWMA 永远四路 50Hz",
		infantry_init.contains("50, 50,\n                          50, 50")
		and infantry_init.contains("10000, 10000,\n                          10000, 10000"))
	_check("步兵生成代码不在 PWMA 槽位写入 10000Hz",
		not infantry_init.contains("10000, 10000,\n                          50, 50"))

	var infantry_50: String = CodeGenInfantry.new().generate(_infantry_cfg("50Hz"))
	_check("步兵 PWMB=50 时八路统一 50Hz",
		infantry_50.contains("50, 50,\n                          50, 50,\n                          50, 50,\n                          50, 50"))

	var invalid_infantry: Dictionary = _infantry_cfg("10000Hz")
	invalid_infantry["pwm_group_init"]["PWMA"] = "10000Hz"
	var infantry_issues: Array = SC.check_infantry(invalid_infantry)
	_check("步兵 PWMA=10000Hz 报 Error",
		_has_issue(infantry_issues, "Error", "PWMA 组禁止初始化为 10000Hz"))
	var slow_motor_issues: Array = SC.check_infantry(_infantry_cfg("10000Hz"))
	_check("步兵平滑电机使用 50Hz 报 Warn",
		_has_issue(slow_motor_issues, "Warn", "P60 为平滑电机"))
	var engineer_issues: Array = SC.check_engineer(_engineer_cfg("50Hz", "10000Hz"))
	_check("工程平滑电机使用 50Hz 报 Warn",
		_has_issue(engineer_issues, "Warn", "P60 为平滑电机"))
	var friction_cfg: Dictionary = _engineer_cfg("10000Hz", "10000Hz")
	friction_cfg["io_role"]["P64"] = "摩擦轮"
	var friction_issues: Array = SC.check_engineer(friction_cfg)
	_check("工程摩擦轮使用 10000Hz 报 Warn",
		_has_issue(friction_issues, "Warn", "P64 为摩擦轮"))
	var jitter_cfg: Dictionary = _engineer_cfg("10000Hz", "10000Hz")
	jitter_cfg["io_role"]["P62"] = "抖动电机"
	var jitter_issues: Array = SC.check_engineer(jitter_cfg)
	_check("工程抖动电机使用 10000Hz 报 Warn",
		_has_issue(jitter_issues, "Warn", "P62 为抖动电机"))
	var invalid_role_cfg: Dictionary = _engineer_cfg("50Hz", "10000Hz")
	invalid_role_cfg["io_role"]["P60"] = "未知角色"
	var invalid_role_issues: Array = SC.check_engineer(invalid_role_cfg)
	_check("非法输出角色报 Error",
		_has_issue(invalid_role_issues, "Error", "io_role P60 输出角色"))
	var invalid_pin_cfg: Dictionary = _engineer_cfg("50Hz", "10000Hz")
	invalid_pin_cfg["io_role"]["P99"] = "舵机"
	var invalid_pin_issues: Array = SC.check_engineer(invalid_pin_cfg)
	_check("非法角色引脚报 Error",
		_has_issue(invalid_pin_issues, "Error", "io_role 使用了非法引脚"))

	if _fail > 0:
		print("失败 %d 项" % _fail)
		quit(1)
	else:
		print("全部通过")
		quit(0)

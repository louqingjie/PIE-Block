extends SceneTree

const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CODEGEN = preload("res://scripts/codegen/codegen_engineer_ik.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


func _has_issue(result: Dictionary, text: String) -> bool:
	for issue in result.get("issues", []):
		if str(issue.get("msg", "")).contains(text):
			return true
	return false


func _initialize() -> void:
	var config_source: String = FileAccess.get_file_as_string(
		"res://scripts/engineer_ik_config.gd")
	_check("configuration validation does not execute PC diagnosis or IK",
		not config_source.contains("arm_diagnosis.gd")
		and not config_source.contains("solve_ik_pose"))
	var defaults: Dictionary = IK_CONFIG.default_config()
	_check("default has canonical fields", defaults.has_all([
		"enabled", "joint_count", "mode_switch_key", "joints", "presets", "joy_x", "joy_y",
		"joy_z", "joy_scale", "keymove_speed", "orientation_key_speed",
		"rocker2_home_enabled", "keymove", "gripper"]))
	_check("fresh projects default to IK disabled", not defaults["enabled"])
	_check("absent enabled field normalizes to enabled (backward compat)",
		IK_CONFIG.normalize({}).get("enabled", false) == true)
	_check("explicit enabled=false survives normalize",
		not IK_CONFIG.normalize({"enabled": false}).get("enabled", true))
	_check("six endpoint key channels default unused", defaults["keymove"].size() == 6
		and defaults["keymove"][3]["plus"] == "不使用"
		and defaults["keymove"][5]["minus"] == "不使用")
	_check("orientation speed and ROCKER2 home have safe defaults",
		defaults["orientation_key_speed"] == "1"
		and not defaults["rocker2_home_enabled"])
	_check("gripper defaults to a disabled servo", defaults["gripper"] == {
		"enabled": false, "io": "MP03", "dir": "正向", "open_angle": "45",
		"closed_angle": "-45", "initial_open": true, "key": "D"})
	_check("default matches previous joint count", defaults["joint_count"] == 3)
	_check("default has four preset slots", defaults["presets"].size() == 4)
	_check("default generates code", not CODEGEN.new().generate(defaults).is_empty())

	for count in [2, 3, 4, 5, 6]:
		var raw: Dictionary = defaults.duplicate(true)
		raw["joint_count"] = count
		while raw["joints"].size() < count:
			raw["joints"].append(IK_CONFIG.default_joint(raw["joints"].size()))
		var normalized: Dictionary = IK_CONFIG.normalize(raw)
		_check("%d joints normalized" % count,
			normalized["joint_count"] == count and normalized["joints"].size() == count)

	var clipped: Dictionary = IK_CONFIG.normalize({"joint_count": 99, "joints": []})
	_check("joint count clamps to six", clipped["joint_count"] == 6 and clipped["joints"].size() == 6)
	var roundtrip: Dictionary = IK_CONFIG.normalize(JSON.parse_string(JSON.stringify(clipped)))
	_check("normalized config survives JSON roundtrip", roundtrip == clipped)
	var v6_like: Dictionary = IK_CONFIG.normalize({"keymove": [
		{"plus": "A", "minus": "B"}, {}, {}, {}]})
	_check("version 6 controls gain unused Roll/Yaw slots",
		v6_like["keymove"].size() == 6 and v6_like["keymove"][0]["plus"] == "A"
		and v6_like["keymove"][4]["plus"] == "不使用"
		and v6_like["orientation_key_speed"] == "1"
		and not v6_like["rocker2_home_enabled"])
	var no_joy: Dictionary = IK_CONFIG.normalize({
		"joy_x": "不使用", "joy_y": "不使用", "joy_z": "不使用"})
	_check("each endpoint axis may disable rocker input", no_joy["joy_x"] == "不使用"
		and no_joy["joy_y"] == "不使用" and no_joy["joy_z"] == "不使用")
	var no_joy_validation: Dictionary = IK_CONFIG.validate(no_joy, {})
	_check("disabled rocker axes do not conflict",
		not _has_issue(no_joy_validation, "不能使用同一摇杆轴")
		and not _has_issue(no_joy_validation, "共用摇杆轴"))
	var patch: Dictionary = IK_CONFIG.servo_init_patch({"joints": [
		{"io": "P74"}, {"io": "MP03"}, {"io": "P76"}],
		"gripper": {"enabled": true, "io": "P77"}})
	_check("servo patch contains expansion joints and gripper only",
		patch == {"P74": "舵机", "P76": "舵机", "P77": "舵机"}, str(patch))
	var blocked: Array[String] = IK_CONFIG.blocked_chassis_ios({
		"l1_io": "P60 P61", "l2_io": "P62 P63", "r1_io": "P64 P65", "r2_io": "P66 P67"})
	_check("chassis slots are blocked", blocked == ["P60", "P62", "P64", "P66"], str(blocked))

	var conflict: Dictionary = defaults.duplicate(true)
	conflict["joint_count"] = 2
	conflict["joints"] = [
		{"io": "P74", "dir": "正向", "axis": "Yaw", "len": "100",
			"offset": "0", "zero": "0", "min": "-90", "max": "90"},
		{"io": "P74", "dir": "正向", "axis": "Pitch", "len": "80",
			"offset": "0", "zero": "0", "min": "-90", "max": "90"},
	]
	var validation: Dictionary = IK_CONFIG.validate(conflict, {
		"l1_io": "P74 P24", "io_init": {"P74": "电机"}, "key_map": []})
	_check("validation reports duplicate joint IO", _has_issue(validation, "重复使用"))
	_check("validation reports chassis collision", _has_issue(validation, "与底盘电机冲突"))
	_check("validation requires expansion servo initialization", _has_issue(validation, "必须初始化为舵机"))

	var grip_conflict: Dictionary = conflict.duplicate(true)
	grip_conflict["joints"][1]["io"] = "P75"
	grip_conflict["gripper"] = {
		"enabled": true, "io": "P74", "dir": "正向", "open_angle": "20",
		"closed_angle": "20", "initial_open": true, "key": "E"}
	var grip_validation: Dictionary = IK_CONFIG.validate(grip_conflict, {
		"io_init": {"P74": "舵机", "P75": "舵机"},
		"modes": [{"rows": [{"key": "E", "io": "MP74"}]},
			{"rows": []}, {"rows": []}, {"rows": []}]})
	_check("gripper conflicts with joint IO", _has_issue(grip_validation, "夹爪 IO P74 与关节1"))
	_check("gripper open and closed angles differ", _has_issue(grip_validation, "张开角和闭合角不能相同"))
	_check("gripper key conflicts are validated", _has_issue(grip_validation, "夹爪 按键E"))

	var control_bad: Dictionary = conflict.duplicate(true)
	control_bad["joints"][1]["io"] = "P75"
	control_bad["orientation_key_speed"] = "0"
	control_bad["keymove"][0] = {"plus": "A", "minus": "不使用"}
	var control_validation: Dictionary = IK_CONFIG.validate(control_bad, {
		"io_init": {"P74": "舵机", "P75": "舵机"},
		"modes": [{"rows": [{"key": "A", "io": "MP03"}]},
			{"rows": []}, {"rows": []}, {"rows": []}]})
	_check("orientation speed must be positive",
		_has_issue(control_validation, "姿态按键步长必须是正数"))
	_check("inverse keys conflict with forward mappings",
		_has_issue(control_validation, "按键A与工程正解映射冲突"))
	var stale_pose_keys: Dictionary = conflict.duplicate(true)
	stale_pose_keys["joints"][1]["io"] = "P75"
	stale_pose_keys["keymove"][3] = {"plus": "A", "minus": "不使用"}
	stale_pose_keys["keymove"][4] = {"plus": "A", "minus": "不使用"}
	stale_pose_keys["keymove"][5] = {"plus": "A", "minus": "不使用"}
	var stale_pose_validation: Dictionary = IK_CONFIG.validate(stale_pose_keys, {
		"io_init": {"P74": "舵机", "P75": "舵机"}, "key_map": []})
	_check("stale uncontrollable pose keys do not block compilation",
		not _has_issue(stale_pose_validation, "按键A被多个末端方向重复使用")
		and not _has_issue(stale_pose_validation, "同一轴正负方向不能使用同一按键"))

	var preset_cfg: Dictionary = conflict.duplicate(true)
	preset_cfg["joints"][1]["io"] = "P75"
	preset_cfg["presets"][0] = {"enabled": true, "key": "B",
		"x": "99999", "y": "-99999", "z": "50000",
		"roll": "170", "pitch": "80", "yaw": "-170"}
	var preset_validation: Dictionary = IK_CONFIG.validate(preset_cfg, {
		"io_init": {"P74": "舵机", "P75": "舵机"}, "key_map": []})
	_check("configuration validation delegates diagnosis and reachability to MCU",
		str(preset_validation.get("diagnosis_source", "")) == "mcu"
		and not _has_issue(preset_validation, "无法从初始姿态收敛"))
	preset_cfg["presets"][0]["yaw"] = ""
	preset_validation = IK_CONFIG.validate(preset_cfg, {
		"io_init": {"P74": "舵机", "P75": "舵机"}, "key_map": []})
	_check("enabled presets require a complete six-dimensional pose",
		_has_issue(preset_validation, "预设1 yaw 不是数值"))

	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)

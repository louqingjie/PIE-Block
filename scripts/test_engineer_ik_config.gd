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
	var defaults: Dictionary = IK_CONFIG.default_config()
	_check("default has canonical fields", defaults.has_all([
		"joint_count", "mode_switch_key", "joints", "presets", "joy_x", "joy_y",
		"joy_z", "joy_scale", "keymove_speed", "keymove", "gripper"]))
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
		"closed_angle": "20", "initial_open": true, "key": "R"}
	var grip_validation: Dictionary = IK_CONFIG.validate(grip_conflict, {
		"io_init": {"P74": "舵机", "P75": "舵机"},
		"key_map": [{"input": "R", "target": "MP74"}]})
	_check("gripper conflicts with joint IO", _has_issue(grip_validation, "夹爪 IO P74 与关节1"))
	_check("gripper open and closed angles differ", _has_issue(grip_validation, "张开角和闭合角不能相同"))
	_check("gripper key conflicts are validated", _has_issue(grip_validation, "夹爪 按键R"))

	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)

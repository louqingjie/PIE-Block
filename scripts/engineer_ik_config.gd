class_name EngineerIKConfig
extends RefCounted

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const DIAG = preload("res://scripts/arm_diagnosis.gd")

const MIN_JOINTS: int = 2
const MAX_JOINTS: int = 6
const PRESET_COUNT: int = 4
const AXES: Array[String] = ["Pitch", "Roll", "Yaw"]
const IOS: Array[String] = [
	"P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74",
]
const EXPANSION_IOS: Array[String] = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
const KEYS: Array[String] = ["R", "↑", "↓", "←", "→", "A", "B", "C", "D"]
const MOVE_KEYS: Array[String] = ["不使用", "R", "↑", "↓", "←", "→", "A", "B", "C", "D"]


static func default_joint(index: int) -> Dictionary:
	return {
		"io": "P60",
		"dir": "正向",
		"axis": "Yaw" if index == 0 else "Pitch",
		"len": "",
		"offset": "",
		"zero": "",
		"min": "",
		"max": "",
	}


static func default_preset(index: int) -> Dictionary:
	return {
		"enabled": false,
		"key": ["A", "B", "C", "D"][index],
		"x": "", "y": "", "z": "", "roll": "", "pitch": "", "yaw": "",
	}


static func default_gripper() -> Dictionary:
	return {
		"enabled": false,
		"io": "MP03",
		"dir": "正向",
		"open_angle": "45",
		"closed_angle": "-45",
		"initial_open": true,
		"key": "D",
	}


static func default_config() -> Dictionary:
	var joints: Array = []
	for i in range(3):
		joints.append(default_joint(i))
	var presets: Array = []
	for i in range(PRESET_COUNT):
		presets.append(default_preset(i))
	var keymove: Array = []
	for _i in range(4):
		keymove.append({"plus": "不使用", "minus": "不使用"})
	return {
		"joint_count": 3,
		"mode_switch_key": "R",
		"joints": joints,
		"gripper": default_gripper(),
		"presets": presets,
		"joy_x": "右X->末端X",
		"joy_y": "右Y->末端Y",
		"joy_z": "右X->末端Z",
		"joy_scale": "5",
		"keymove_speed": "2",
		"keymove": keymove,
	}


static func normalize(raw: Variant) -> Dictionary:
	var src: Dictionary = raw if raw is Dictionary else {}
	var out: Dictionary = default_config()
	var jc: int = clampi(int(src.get("joint_count", out["joint_count"])), MIN_JOINTS, MAX_JOINTS)
	out["joint_count"] = jc
	out["mode_switch_key"] = _choice(src.get("mode_switch_key", "R"), KEYS, "R")
	out["joy_x"] = _choice(src.get("joy_x", out["joy_x"]),
		["不使用", "右X->末端X", "右Y->末端X"], out["joy_x"])
	out["joy_y"] = _choice(src.get("joy_y", out["joy_y"]),
		["不使用", "右X->末端Y", "右Y->末端Y"], out["joy_y"])
	out["joy_z"] = _choice(src.get("joy_z", out["joy_z"]),
		["不使用", "右X->末端Z", "右Y->末端Z"], out["joy_z"])
	out["joy_scale"] = str(src.get("joy_scale", out["joy_scale"]))
	out["keymove_speed"] = str(src.get("keymove_speed", out["keymove_speed"]))

	var raw_joints: Array = src.get("joints", []) if src.get("joints", []) is Array else []
	var joints: Array = []
	for i in range(jc):
		var base: Dictionary = default_joint(i)
		var item: Dictionary = raw_joints[i] if i < raw_joints.size() and raw_joints[i] is Dictionary else {}
		base["io"] = _choice(item.get("io", base["io"]), IOS, base["io"])
		base["dir"] = _choice(item.get("dir", base["dir"]), ["正向", "反向"], base["dir"])
		base["axis"] = _choice(item.get("axis", base["axis"]), AXES, base["axis"])
		for key in ["len", "offset", "zero", "min", "max"]:
			base[key] = str(item.get(key, base[key]))
		joints.append(base)
	out["joints"] = joints

	var raw_gripper: Dictionary = src.get("gripper", {}) if src.get("gripper", {}) is Dictionary else {}
	var gripper: Dictionary = default_gripper()
	gripper["enabled"] = bool(raw_gripper.get("enabled", gripper["enabled"]))
	gripper["io"] = _choice(raw_gripper.get("io", gripper["io"]), IOS, gripper["io"])
	gripper["dir"] = _choice(raw_gripper.get("dir", gripper["dir"]),
		["正向", "反向"], gripper["dir"])
	gripper["open_angle"] = str(raw_gripper.get("open_angle", gripper["open_angle"]))
	gripper["closed_angle"] = str(raw_gripper.get("closed_angle", gripper["closed_angle"]))
	gripper["initial_open"] = bool(raw_gripper.get("initial_open", gripper["initial_open"]))
	gripper["key"] = _choice(raw_gripper.get("key", gripper["key"]), KEYS, gripper["key"])
	out["gripper"] = gripper

	var raw_presets: Array = src.get("presets", []) if src.get("presets", []) is Array else []
	var cg := CG.new()
	var home_chain: Dictionary = cg.fk_chain(cg._joint_home_angles(joints), joints, jc)
	var home_rpy: Vector3 = cg.tip_rpy_deg(home_chain)
	var presets: Array = []
	for i in range(PRESET_COUNT):
		var base: Dictionary = default_preset(i)
		var item: Dictionary = raw_presets[i] if i < raw_presets.size() and raw_presets[i] is Dictionary else {}
		base["enabled"] = bool(item.get("enabled", false))
		base["key"] = _choice(item.get("key", base["key"]), KEYS, base["key"])
		for key in ["x", "y", "z"]:
			base[key] = str(item.get(key, ""))
		base["roll"] = str(item.get("roll", home_rpy.x))
		base["pitch"] = str(item.get("pitch", home_rpy.y))
		base["yaw"] = str(item.get("yaw", home_rpy.z))
		presets.append(base)
	out["presets"] = presets

	var raw_move: Array = src.get("keymove", []) if src.get("keymove", []) is Array else []
	var keymove: Array = []
	for i in range(4):
		var item: Dictionary = raw_move[i] if i < raw_move.size() and raw_move[i] is Dictionary else {}
		keymove.append({
			"plus": _choice(item.get("plus", "不使用"), MOVE_KEYS, "不使用"),
			"minus": _choice(item.get("minus", "不使用"), MOVE_KEYS, "不使用"),
		})
	out["keymove"] = keymove
	return out


static func _choice(value: Variant, choices: Array, fallback: String) -> String:
	var text: String = _normalize_key(str(value))
	return text if text in choices else fallback


static func _normalize_key(value: String) -> String:
	return "→" if value == "->" else value


static func blocked_chassis_ios(engineer: Dictionary) -> Array[String]:
	var blocked: Array[String] = []
	for key in ["l1_io", "l2_io", "r1_io", "r2_io"]:
		var pin: String = str(engineer.get(key, "")).split(" ")[0]
		if pin in EXPANSION_IOS and not pin in blocked:
			blocked.append(pin)
	return blocked


static func servo_init_patch(ik: Dictionary) -> Dictionary:
	var patch: Dictionary = {}
	for joint in ik.get("joints", []):
		var pin: String = str(joint.get("io", ""))
		if pin in EXPANSION_IOS:
			patch[pin] = "舵机"
	var gripper: Dictionary = ik.get("gripper", {}) if ik.get("gripper", {}) is Dictionary else {}
	if bool(gripper.get("enabled", false)):
		var gripper_pin: String = str(gripper.get("io", ""))
		if gripper_pin in EXPANSION_IOS:
			patch[gripper_pin] = "舵机"
	return patch


## 返回配置问题与完整位姿自由度诊断。只读取字典，不依赖场景节点。
static func validate(raw_ik: Dictionary, engineer: Dictionary = {}) -> Dictionary:
	var ik: Dictionary = normalize(raw_ik)
	var issues: Array = []
	var joints: Array = ik["joints"]
	var jc: int = ik["joint_count"]
	var total_len: float = 0.0
	var lengths_valid: bool = true
	for i in range(joints.size()):
		var joint: Dictionary = joints[i]
		var ls: String = str(joint["len"]).strip_edges()
		if ls.is_empty() or not ls.is_valid_float() or ls.to_float() < 0.0:
			lengths_valid = false
			issues.append({"type": "Error", "msg": "工程逆解算 关节%d 连杆长度无效" % (i + 1)})
		else:
			total_len += ls.to_float()
		_validate_joint_angles(issues, joint, i)
	if total_len <= 0.0:
		issues.append({"type": "Error", "msg": "工程逆解算 连杆总长必须大于 0"})

	var io_owner: Dictionary = {}
	var blocked: Array[String] = blocked_chassis_ios(engineer)
	for i in range(joints.size()):
		var pin: String = str(joints[i]["io"])
		if io_owner.has(pin):
			issues.append({"type": "Error", "msg": "工程逆解算 IO %s 被关节%d和关节%d重复使用"
				% [pin, io_owner[pin], i + 1]})
		else:
			io_owner[pin] = i + 1
		if pin in blocked:
			issues.append({"type": "Error", "msg": "工程逆解算 关节%d IO %s 与底盘电机冲突" % [i + 1, pin]})
		if pin in EXPANSION_IOS and str((engineer.get("io_init", {}) as Dictionary).get(pin, "")) != "舵机":
			issues.append({"type": "Error", "msg": "工程逆解算 关节%d IO %s 必须初始化为舵机" % [i + 1, pin]})
	_validate_gripper(issues, ik, engineer, io_owner, blocked)

	var orientation_mask: Dictionary = {"roll": false, "pitch": false, "yaw": false}
	var orientation_reason: Dictionary = {}
	var diagnosis: Dictionary = {}
	if lengths_valid and total_len > 0.0:
		diagnosis = DIAG.new().analyze(joints, jc)
		orientation_mask = (diagnosis.get("orientation_mask", orientation_mask) as Dictionary).duplicate(true)
		orientation_reason = (diagnosis.get("orientation_reason", {}) as Dictionary).duplicate(true)
		for item in diagnosis.get("issues", []):
			issues.append({"type": item.get("type", "Warn"),
				"msg": "机械臂构形：%s" % str(item.get("msg", ""))})
	_validate_presets(issues, ik, orientation_mask)
	_validate_controls(issues, ik, engineer, bool(orientation_mask.get("pitch", false)),
		str(orientation_reason.get("pitch", "")), total_len)
	return {"issues": issues, "orientation_mask": orientation_mask,
		"orientation_reason": orientation_reason,
		"position_dof": int(diagnosis.get("position_dof", 0)),
		"orientation_dof": int(diagnosis.get("orientation_dof", 0)),
		"pose_dof": int(diagnosis.get("pose_dof", 0))}


static func _validate_gripper(issues: Array, ik: Dictionary, engineer: Dictionary,
		io_owner: Dictionary, blocked: Array[String]) -> void:
	var gripper: Dictionary = ik["gripper"]
	if not bool(gripper["enabled"]):
		return
	var pin: String = str(gripper["io"])
	if io_owner.has(pin):
		issues.append({"type": "Error", "msg": "工程夹爪 IO %s 与关节%d重复使用"
			% [pin, int(io_owner[pin])]})
	if pin in blocked:
		issues.append({"type": "Error", "msg": "工程夹爪 IO %s 与底盘电机冲突" % pin})
	if pin in EXPANSION_IOS and str((engineer.get("io_init", {}) as Dictionary).get(pin, "")) != "舵机":
		issues.append({"type": "Error", "msg": "工程夹爪 IO %s 必须初始化为舵机" % pin})
	for row in engineer.get("key_map", []):
		if str(row.get("target", "")) == pin:
			issues.append({"type": "Error", "msg": "工程夹爪 IO %s 与工程正解映射重复使用" % pin})
			break
	var values: Dictionary = {}
	for field in ["open_angle", "closed_angle"]:
		var label: String = "张开角" if field == "open_angle" else "闭合角"
		var text: String = str(gripper[field]).strip_edges()
		if not text.is_valid_float():
			issues.append({"type": "Error", "msg": "工程夹爪 %s不是数值" % label})
			continue
		values[field] = text.to_float()
		if absf(values[field]) > 90.0:
			issues.append({"type": "Error", "msg": "工程夹爪 %s必须在 -90° 到 90° 之间" % label})
	if values.has("open_angle") and values.has("closed_angle") \
			and is_equal_approx(values["open_angle"], values["closed_angle"]):
		issues.append({"type": "Error", "msg": "工程夹爪 张开角和闭合角不能相同"})


static func _validate_joint_angles(issues: Array, joint: Dictionary, index: int) -> void:
	var values: Dictionary = {}
	for key in ["offset", "zero", "min", "max"]:
		var text: String = str(joint[key]).strip_edges()
		if text.is_empty() or not text.is_valid_float():
			issues.append({"type": "Error", "msg": "工程逆解算 关节%d %s 未设置或不是数值"
				% [index + 1, key]})
			return
		values[key] = text.to_float()
	if values["min"] >= values["max"]:
		issues.append({"type": "Error", "msg": "工程逆解算 关节%d 最小限位必须小于最大限位" % (index + 1)})
	if values["zero"] < values["min"] or values["zero"] > values["max"]:
		issues.append({"type": "Error", "msg": "工程逆解算 关节%d 初始角超出限位" % (index + 1)})
	var travel_lo: float = values["offset"] - 90.0
	var travel_hi: float = values["offset"] + 90.0
	if values["min"] < travel_lo or values["max"] > travel_hi:
		issues.append({"type": "Warn", "msg": "工程逆解算 关节%d 限位超出中位朝向 ±90° 舵机行程" % (index + 1)})


static func _validate_presets(issues: Array, ik: Dictionary, orientation_mask: Dictionary) -> void:
	var used: Dictionary = {}
	var cg = CG.new()
	for i in range((ik["presets"] as Array).size()):
		var preset: Dictionary = ik["presets"][i]
		if not preset["enabled"]:
			continue
		var key: String = preset["key"]
		if used.has(key):
			issues.append({"type": "Error", "msg": "工程逆解算 预设%d与预设%d重复使用按键%s"
				% [i + 1, used[key], key]})
		else:
			used[key] = i + 1
		var fields: Array = ["x", "y", "z"]
		for name in ["roll", "pitch", "yaw"]:
			if bool(orientation_mask.get(name, false)): fields.append(name)
		var valid: bool = true
		for field in fields:
			if not str(preset[field]).is_valid_float():
				valid = false
				issues.append({"type": "Error", "msg": "工程逆解算 预设%d %s 不是数值" % [i + 1, field]})
		if valid:
			var home_chain: Dictionary = cg.fk_chain(cg._joint_home_angles(ik["joints"]),
				ik["joints"], ik["joint_count"])
			var home_rpy: Vector3 = cg.tip_rpy_deg(home_chain)
			var target_rpy: Vector3 = Vector3(
				float(preset["roll"]) if bool(orientation_mask.get("roll", false)) else home_rpy.x,
				float(preset["pitch"]) if bool(orientation_mask.get("pitch", false)) else home_rpy.y,
				float(preset["yaw"]) if bool(orientation_mask.get("yaw", false)) else home_rpy.z)
			var result: Dictionary = cg.solve_ik_pose_converge(
				Vector3(float(preset["x"]), float(preset["y"]), float(preset["z"])),
				cg.basis_from_rpy_deg(target_rpy), orientation_mask,
				cg._joint_home_angles(ik["joints"]), ik["joints"], ik["joint_count"])
			var orientation_bad: bool = false
			for value in (result.get("orientation_err", {}) as Dictionary).values():
				orientation_bad = orientation_bad or absf(float(value)) >= 1.0
			if float(result["err"]) >= 2.0 or orientation_bad:
				issues.append({"type": "Warn", "msg": "工程逆解算 预设%d 无法从初始姿态收敛" % (i + 1)})


static func _validate_controls(issues: Array, ik: Dictionary, engineer: Dictionary,
		pitch_dof: bool, pitch_reason: String, total_len: float) -> void:
	var switch_key: String = _normalize_key(ik["mode_switch_key"])
	var used: Dictionary = {}
	for i in range((ik["keymove"] as Array).size()):
		var row: Dictionary = ik["keymove"][i]
		var unavailable: bool = i == 3 and not pitch_dof
		for side in ["plus", "minus"]:
			var key: String = _normalize_key(row[side])
			if key == "不使用":
				continue
			if unavailable:
				issues.append({"type": "Warn", "msg": "工程逆解算 Pitch不可控，已配置的姿态按键不会生效%s" %
					("（%s）" % pitch_reason if not pitch_reason.is_empty() else "")})
				continue
			if key == switch_key:
				issues.append({"type": "Error", "msg": "工程逆解算 切换键%s与末端移动按键冲突" % key})
			if used.has(key):
				issues.append({"type": "Error", "msg": "工程逆解算 按键%s被多个末端方向重复使用" % key})
			used[key] = true
		if row["plus"] != "不使用" and _normalize_key(row["plus"]) == _normalize_key(row["minus"]):
			issues.append({"type": "Error", "msg": "工程逆解算 同一轴正负方向不能使用同一按键"})
	for preset in ik["presets"]:
		if preset["enabled"]:
			var key: String = _normalize_key(preset["key"])
			if key == switch_key or used.has(key):
				issues.append({"type": "Error", "msg": "工程逆解算 预设按键%s与其他逆解功能冲突" % key})
			used[key] = true
	var gripper: Dictionary = ik["gripper"]
	var gripper_key: String = _normalize_key(str(gripper["key"]))
	if bool(gripper["enabled"]) and (gripper_key == switch_key or used.has(gripper_key)):
		issues.append({"type": "Error", "msg": "工程夹爪 按键%s与其他逆解功能冲突" % gripper_key})
	for row in engineer.get("key_map", []):
		var input_key: String = _normalize_key(str(row.get("input", "")))
		if str(row.get("target", "")).is_empty():
			continue
		if input_key == switch_key:
			issues.append({"type": "Error", "msg": "工程逆解算 切换键%s与工程正解映射冲突" % switch_key})
		if bool(gripper["enabled"]) and input_key == gripper_key:
			issues.append({"type": "Error", "msg": "工程夹爪 按键%s与工程正解映射冲突" % gripper_key})
	var jx: String = str(ik["joy_x"]).split("->")[0]
	var jy: String = str(ik["joy_y"]).split("->")[0]
	var jz: String = str(ik["joy_z"]).split("->")[0]
	if jx != "不使用" and jy != "不使用" and jx == jy:
		issues.append({"type": "Error", "msg": "工程逆解算 末端X和Y不能使用同一摇杆轴"})
	if jz != "不使用" and ((jx != "不使用" and jz == jx)
			or (jy != "不使用" and jz == jy)):
		issues.append({"type": "Warn", "msg": "工程逆解算 末端Z与其他方向共用摇杆轴"})
	for pair in [["joy_scale", "摇杆步长"], ["keymove_speed", "按键步长"]]:
		var value: String = str(ik[pair[0]]).strip_edges()
		if not value.is_valid_float() or value.to_float() <= 0.0:
			issues.append({"type": "Error", "msg": "工程逆解算 %s必须是正数" % pair[1]})
		elif pair[0] == "joy_scale" and total_len > 0.0 and value.to_float() > total_len * 0.2:
			issues.append({"type": "Warn", "msg": "工程逆解算 摇杆步长相对臂长过大"})

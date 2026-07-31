extends SceneTree

## 通用正运动学与配置契约验证。

var _cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s%s" % [label, ("  " + detail) if not detail.is_empty() else ""])
		_fail += 1


func _near(a: float, b: float, tol: float = 1.0e-4) -> bool:
	return absf(a - b) < tol


func _initialize() -> void:
	_test_axis_and_length_contract()
	_test_single_axes()
	_test_mixed_chain()
	_test_two_to_six_joints()
	_test_generated_code_has_only_jacobian_path()
	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)


func _test_axis_and_length_contract() -> void:
	var blank: Array = [{}, {}, {}]
	_check("axis defaults match UI",
		_cg.joint_axes(blank, 3) == ["Yaw", "Pitch", "Pitch"])
	_check("missing lengths are zero",
		_cg.joint_lengths(blank, 3) == [0.0, 0.0, 0.0])
	var custom: Array = [
		{"axis": "Roll", "len": "11"},
		{"axis": "Yaw", "len": "22"},
		{"axis": "Pitch", "len": "33"},
	]
	_check("explicit axes preserved",
		_cg.joint_axes(custom, 3) == ["Roll", "Yaw", "Pitch"])
	_check("explicit lengths preserved",
		_cg.joint_lengths(custom, 3) == [11.0, 22.0, 33.0])


func _test_single_axes() -> void:
	var roll: Array = [{"axis": "Roll", "len": "100"}]
	var r0: Vector3 = _cg.fk_chain([0.0], roll, 1)["points"][1]
	var r90: Vector3 = _cg.fk_chain([90.0], roll, 1)["points"][1]
	_check("Roll does not move its own link", r0.distance_to(r90) < 1.0e-4)

	var yaw: Array = [{"axis": "Yaw", "len": "100"}]
	var y90: Vector3 = _cg.fk_chain([90.0], yaw, 1)["points"][1]
	_check("Yaw 90 points +Y", _near(y90.x, 0.0) and _near(y90.y, 100.0)
		and _near(y90.z, 0.0), str(y90))

	var pitch: Array = [{"axis": "Pitch", "len": "100"}]
	var p90: Vector3 = _cg.fk_chain([90.0], pitch, 1)["points"][1]
	_check("Pitch 90 points +Z", _near(p90.z, 100.0), str(p90))


func _test_mixed_chain() -> void:
	var joints: Array = [
		{"axis": "Yaw", "len": "0"},
		{"axis": "Pitch", "len": "120"},
		{"axis": "Roll", "len": "90"},
		{"axis": "Pitch", "len": "40"},
	]
	var chain: Dictionary = _cg.fk_chain([20.0, 35.0, 60.0, -20.0], joints, 4)
	var points: Array = chain["points"]
	var axes: Array = chain["axes"]
	_check("point count is joints + 1", points.size() == 5)
	_check("axis count is joint count", axes.size() == 4)
	for i in range(4):
		_check("segment %d length" % i,
			_near((points[i] as Vector3).distance_to(points[i + 1]),
				float(_cg.joint_lengths(joints, 4)[i]), 1.0e-3))
		_check("axis %d unit length" % i,
			_near((axes[i] as Vector3).length(), 1.0, 1.0e-5))
	var basis: Basis = chain["tip_basis"]
	_check("tip basis orthogonal", absf(basis.x.dot(basis.y)) < 1.0e-5
		and absf(basis.y.dot(basis.z)) < 1.0e-5)
	var cols: Array = _cg.jacobian_columns(chain, 4)
	_check("Jacobian has one column per joint", cols.size() == 4)
	for col in cols:
		var c: Vector3 = col
		_check("Jacobian column finite", is_finite(c.x) and is_finite(c.y)
			and is_finite(c.z))


func _test_two_to_six_joints() -> void:
	for jc in range(2, 7):
		var joints: Array = []
		var angles: Array = []
		for i in range(jc):
			joints.append({
				"axis": ["Yaw", "Pitch", "Roll"][i % 3],
				"len": str(80.0 - i * 7.0),
				"zero": str(5.0 + i * 8.0),
			})
			angles.append(5.0 + i * 8.0)
		var chain: Dictionary = _cg.fk_chain(angles, joints, jc)
		var tip: Vector3 = chain["points"][jc]
		_check("%d joints point count" % jc, chain["points"].size() == jc + 1)
		_check("%d joints valid tip" % jc, is_finite(tip.x) and is_finite(tip.y)
			and is_finite(tip.z) and tip.length() > 1.0)
		_check("%d joints home not truncated" % jc,
			_cg._joint_home_angles(joints).size() == jc)


func _test_generated_code_has_only_jacobian_path() -> void:
	var joints: Array = []
	for i in range(6):
		joints.append({
			"io": ["P60", "P62", "P64", "P66", "P74", "P75"][i],
			"dir": "正向", "axis": ["Yaw", "Pitch", "Roll"][i % 3],
			"len": str(100 - i * 10), "offset": "0", "zero": "10",
			"min": "-90", "max": "90",
		})
	var code: String = _cg.generate({
		"joint_count": 6, "joints": joints, "presets": [],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y",
		"joy_z": "右X->末端Z", "joy_scale": "5",
		"keymove_speed": "2", "keymove": [],
	})
	_check("generated code has joint arrays", code.contains("jointAxis[6][3]")
		and code.contains("jointLen[6]"))
	_check("generated code has XYZ target", code.contains("targetZ")
		and code.contains("ik_solve(float x, float y, float z"))
	_check("generated code has no analytic cosine law", not code.contains("acos("))
	_check("generated code has no legacy length macros", not code.contains("#define L1")
		and not code.contains("#define L2") and not code.contains("#define L3"))
	_check("generated code uses expansion board API", code.contains("ExpansionBoradControl("))
	_check("generated code does not call PWM API", not code.contains("PWM_"))

extends SceneTree

const DIAG = preload("res://scripts/arm_diagnosis.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

var _diag = DIAG.new()
var _cg = CG.new()
var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if not ok:
		_fail += 1
		print("[FAIL] %s %s" % [label, detail])
	else:
		print("[PASS] %s" % label)


func _j(axes: Array, lens: Array) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({"axis": axes[i], "len": str(lens[i]), "zero": "10",
			"min": "-90", "max": "90"})
	return out


func _has_issue(result: Dictionary, text: String) -> bool:
	for issue in result.get("issues", []):
		if text in str(issue.get("msg", "")):
			return true
	return false


func _initialize() -> void:
	_test_valid_spatial_arm()
	_test_flat_and_dead_arms()
	_test_phi_control()
	_test_two_to_six_joint_safety()
	_test_zero_lengths()
	print("Result: %s" % ("PASS" if _fail == 0 else "%d failed" % _fail))
	quit(0 if _fail == 0 else 1)


func _test_valid_spatial_arm() -> void:
	var joints: Array = _j(["Yaw", "Pitch", "Pitch"], [0, 120, 90])
	var result: Dictionary = _diag.analyze(joints, 3)
	_check("spatial arm reaches 3 position DOF", int(result["dof"]) == 3, str(result))
	_check("spatial arm has no locked coordinate", result["locked"].is_empty(),
		str(result["locked"]))


func _test_flat_and_dead_arms() -> void:
	var flat: Dictionary = _diag.analyze(
		_j(["Pitch", "Pitch", "Pitch"], [100, 80, 60]), 3)
	_check("parallel Pitch arm diagnosed below 3 DOF", int(flat["dof"]) < 3, str(flat))
	var dead: Dictionary = _diag.analyze(
		_j(["Roll", "Roll", "Roll"], [100, 80, 60]), 3)
	_check("all Roll arm has zero position DOF", int(dead["dof"]) == 0, str(dead))
	_check("all Roll message is actionable", _has_issue(dead, "Roll"), str(dead))


func _test_phi_control() -> void:
	var four: Dictionary = _diag.analyze(
		_j(["Yaw", "Pitch", "Pitch", "Pitch"], [0, 120, 90, 40]), 4)
	_check("four joint spatial arm controls pitch", bool(four["pitch_dof"]), str(four))
	var three: Dictionary = _diag.analyze(
		_j(["Yaw", "Pitch", "Pitch"], [0, 120, 90]), 3)
	_check("three joints cannot independently control pitch",
		not bool(three["pitch_dof"]), str(three))


func _test_two_to_six_joint_safety() -> void:
	for jc in range(2, 7):
		var axes: Array = []
		var lens: Array = []
		for i in range(jc):
			axes.append(["Yaw", "Pitch", "Roll"][i % 3])
			lens.append(100 - i * 10)
		var joints: Array = _j(axes, lens)
		var result: Dictionary = _diag.analyze(joints, jc)
		_check("%d joint diagnosis returns finite DOF" % jc,
			int(result.get("dof", -1)) >= 0 and int(result.get("dof", -1)) <= 3,
			str(result))
		var chain: Dictionary = _cg.fk_chain(_cg._joint_home_angles(joints), joints, jc)
		var tip: Vector3 = chain["points"][jc]
		_check("%d joint diagnosis uses valid FK" % jc,
			is_finite(tip.x) and is_finite(tip.y) and is_finite(tip.z))


func _test_zero_lengths() -> void:
	var zero: Dictionary = _diag.analyze(_j(["Yaw", "Pitch"], [0, 0]), 2)
	_check("zero length arm rejected", int(zero["dof"]) == 0
		and _has_issue(zero, "所有连杆长度都是 0"), str(zero))

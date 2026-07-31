extends SceneTree

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const DIAG = preload("res://scripts/arm_diagnosis.gd")

var cg := CG.new()
var failures := 0

func _check(label: String, ok: bool, detail := "") -> void:
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", label, "  " + detail if not detail.is_empty() else ""])
	if not ok: failures += 1

func _joints(axes: Array, lengths: Array, lo := -180.0, hi := 180.0) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({"axis": axes[i], "len": str(lengths[i]), "zero": "0",
			"min": str(lo), "max": str(hi)})
	return out

func _zeros(n: int) -> Array:
	var out: Array = []
	for _i in range(n): out.append(0.0)
	return out

func _finite_angles(values: Array) -> bool:
	for value in values:
		if not is_finite(float(value)): return false
	return true

func _initialize() -> void:
	print("=== 六维末端运动学验证 ===")
	_test_rpy_roundtrip()
	_test_shortest_rotation()
	_test_pose_roundtrip()
	_test_underactuated_and_limits()
	print("=== %s ===" % ("全部通过" if failures == 0 else "%d 项失败" % failures))
	quit(0 if failures == 0 else 1)

func _test_rpy_roundtrip() -> void:
	for rpy in [Vector3(20, 30, -40), Vector3(179, 89.9, -179), Vector3(-170, -89.9, 170)]:
		var basis: Basis = cg.basis_from_rpy_deg(rpy)
		var chain := {"tip_basis": basis}
		var restored: Basis = cg.basis_from_rpy_deg(cg.tip_rpy_deg(chain))
		var error: Vector3 = cg.orientation_error_vector(basis, restored)
		_check("RPY 往返 %s" % rpy, error.length() < 1.0e-4, str(error))

func _test_shortest_rotation() -> void:
	var a: Basis = cg.basis_from_rpy_deg(Vector3(0, 0, 179))
	var b: Basis = cg.basis_from_rpy_deg(Vector3(0, 0, -179))
	var error: Vector3 = cg.orientation_error_vector(a, b)
	_check("Yaw 跨过 180 度走最短路径", absf(rad_to_deg(error.length()) - 2.0) < 0.01, str(error))
	var singular: Vector3 = cg.orientation_error_vector(Basis.IDENTITY,
		cg.basis_from_rpy_deg(Vector3(45, 90, 30)))
	_check("Pitch 90 度姿态误差有限", is_finite(singular.length()), str(singular))

func _test_pose_roundtrip() -> void:
	var cases := [
		{"axes": ["Yaw", "Pitch", "Pitch", "Roll", "Yaw", "Roll"],
		 "lens": [0, 120, 90, 0, 40, 0], "goal": [20.0, 25.0, -35.0, 30.0, 15.0, -20.0]},
		{"axes": ["Yaw", "Pitch", "Roll", "Pitch", "Yaw"],
		 "lens": [0, 100, 0, 80, 40], "goal": [-20.0, 35.0, 15.0, -25.0, 20.0]},
	]
	for item in cases:
		var joints: Array = _joints(item.axes, item.lens)
		var jc: int = joints.size()
		var goal_chain: Dictionary = cg.fk_chain(item.goal, joints, jc)
		var goal_position: Vector3 = goal_chain.points[-1]
		var mask: Dictionary = DIAG.new().analyze(joints, jc).orientation_mask
		var result: Dictionary = cg.solve_ik_pose_converge(goal_position, goal_chain.tip_basis,
			mask, _zeros(jc), joints, jc)
		var actual: Dictionary = cg.fk_chain(result.angles, joints, jc)
		var position_error: float = (actual.points[-1] as Vector3).distance_to(goal_position)
		_check("%d 关节 FK->位姿 IK" % jc, position_error < 2.0 and _finite_angles(result.angles),
			"位置误差 %.3f mask=%s" % [position_error, mask])

func _test_underactuated_and_limits() -> void:
	var joints: Array = _joints(["Yaw", "Pitch"], [100, 80], -30.0, 30.0)
	var diagnosis: Dictionary = DIAG.new().analyze(joints, 2)
	var result: Dictionary = cg.solve_ik_pose_converge(Vector3(5000, 20, 30),
		cg.basis_from_rpy_deg(Vector3(170, 80, -170)), diagnosis.orientation_mask,
		_zeros(2), joints, 2)
	var limited := true
	for angle in result.angles:
		limited = limited and float(angle) >= -30.001 and float(angle) <= 30.001
	_check("欠驱动不可达目标无 NaN", _finite_angles(result.angles), str(result.angles))
	_check("不可达目标稳定停在限位内", limited and not bool(result.reachable), str(result))

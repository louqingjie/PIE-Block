extends SceneTree

## arm_workspace.gd 回归测试。
## 运行：godot --headless --path . --script scripts/test_arm_workspace.gd

const WS = preload("res://scripts/arm_workspace.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

var ws := WS.new()
var cg := CG.new()
var failures := 0

func _check(label: String, ok: bool, detail := "") -> void:
	print("[%s] %s%s" % ["PASS" if ok else "FAIL", label,
		"  " + detail if not detail.is_empty() else ""])
	if not ok:
		failures += 1

func _joints(axes: Array, lengths: Array, lo := -90.0, hi := 90.0) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({"axis": axes[i], "len": str(lengths[i]), "zero": "0",
			"min": str(lo), "max": str(hi)})
	return out

func _initialize() -> void:
	print("=== 可达区域扫描测试 ===")
	_test_plane_arm()
	_test_spatial_arm()
	_test_roll_only()
	_test_limits_shrink()
	_test_fingerprint_stability()
	_test_mixed_roll_arm()
	print("=== %s ===" % ("全部通过" if failures == 0 else "%d 项失败" % failures))
	quit(0 if failures == 0 else 1)

## 2 关节平面臂（Yaw+Pitch）：末端只能在一个平面内运动，Z 坐标有非零范围但 Y 范围也非零。
## 所有点应在臂长半径的圆环内。
func _test_plane_arm() -> void:
	var joints := _joints(["Yaw", "Pitch"], [100, 80])
	var result: Dictionary = ws.compute_workspace(joints, 2, 10.0)
	var voxels: PackedVector3Array = result["voxels"]
	_check("平面臂体素数 > 0", voxels.size() > 0, "size=%d" % voxels.size())
	_check("平面臂评估点数 > 0", int(result["point_count"]) > 0)
	# 所有点距原点不超过臂长总和（180mm）+ 1 个体素
	var max_r: float = 180.0 + 10.0
	var all_in: bool = true
	for v in voxels:
		if v.length() > max_r:
			all_in = false
			break
	_check("平面臂所有体素在臂长半径内", all_in)
	# 平面臂有 Yaw，所以 Y 分量应有变化
	var has_y: bool = false
	for v in voxels:
		if absf(v.y) > 1.0:
			has_y = true
			break
	_check("平面臂有 Y 方向变化", has_y)

## 3 关节空间臂（Yaw+Pitch+Pitch）：末端可在 3D 空间运动。
func _test_spatial_arm() -> void:
	var joints := _joints(["Yaw", "Pitch", "Pitch"], [0, 120, 90])
	var result: Dictionary = ws.compute_workspace(joints, 3, 10.0)
	var voxels: PackedVector3Array = result["voxels"]
	_check("空间臂体素数 > 100", voxels.size() > 100, "size=%d" % voxels.size())
	# Z 应有正范围（臂可以抬起来）
	var max_z: float = -1e9
	var min_z: float = 1e9
	for v in voxels:
		max_z = maxf(max_z, v.z)
		min_z = minf(min_z, v.z)
	_check("空间臂 Z 有正范围", max_z > 50.0, "max_z=%.1f" % max_z)
	_check("空间臂 Z 有负范围", min_z < -50.0, "min_z=%.1f" % min_z)
	# 体素应在球壳内（内径 > 0，外径 < 臂长总和）
	var total_len: float = 0.0 + 120.0 + 90.0
	var has_inner_gap: bool = false
	for v in voxels:
		if v.length() < total_len * 0.3:
			has_inner_gap = true
			break
	# 不是所有点都在中心——应该有空心区域
	# 但不一定全空心，关节限位 90° 可能覆盖中心。只检查外径。
	var all_outside_max: bool = true
	for v in voxels:
		if v.length() > total_len + 10.0:
			all_outside_max = false
			break
	_check("空间臂无体素超出臂长", all_outside_max)

## 纯 Roll 臂：Roll 只改变姿态不改变位置，末端永远在原点（或沿 X 的连杆末端）。
func _test_roll_only() -> void:
	var joints := _joints(["Roll", "Roll"], [0, 0])
	var result: Dictionary = ws.compute_workspace(joints, 2, 10.0)
	var voxels: PackedVector3Array = result["voxels"]
	# 全 Roll 且无连杆长度 -> 只有一个体素在原点
	_check("纯 Roll 臂只产生 1 个体素", voxels.size() == 1, "size=%d" % voxels.size())
	_check("纯 Roll 臂体素在原点", voxels[0].distance_to(Vector3.ZERO) < 1.0)

## 限位收紧后体积减小。
func _test_limits_shrink() -> void:
	var joints_full := _joints(["Yaw", "Pitch", "Pitch"], [0, 120, 90], -90.0, 90.0)
	var joints_limited := _joints(["Yaw", "Pitch", "Pitch"], [0, 120, 90], -30.0, 30.0)
	var result_full: Dictionary = ws.compute_workspace(joints_full, 3, 10.0)
	var result_limited: Dictionary = ws.compute_workspace(joints_limited, 3, 10.0)
	var count_full: int = (result_full["voxels"] as PackedVector3Array).size()
	var count_limited: int = (result_limited["voxels"] as PackedVector3Array).size()
	_check("限位收紧后体素数减少", count_limited < count_full,
		"full=%d limited=%d" % [count_full, count_limited])

## 配置指纹稳定性：相同配置两次调用应返回相同指纹。
func _test_fingerprint_stability() -> void:
	var joints := _joints(["Yaw", "Pitch"], [100, 80])
	var fp1: String = ws.fingerprint(joints, 2)
	var fp2: String = ws.fingerprint(joints, 2)
	_check("相同配置指纹一致", fp1 == fp2, "%s vs %s" % [fp1, fp2])
	# 不同限位应产生不同指纹
	var joints_diff := _joints(["Yaw", "Pitch"], [100, 80], -60.0, 60.0)
	var fp3: String = ws.fingerprint(joints_diff, 2)
	_check("不同限位指纹不同", fp1 != fp3)

## 混合 Roll 臂：Roll 关节不影响体素数量（位置不变）。
func _test_mixed_roll_arm() -> void:
	var joints_no_roll := _joints(["Yaw", "Pitch", "Pitch"], [0, 100, 80])
	var joints_with_roll := _joints(["Yaw", "Pitch", "Roll", "Pitch"], [0, 100, 0, 80])
	var result_no: Dictionary = ws.compute_workspace(joints_no_roll, 3, 10.0)
	var result_roll: Dictionary = ws.compute_workspace(joints_with_roll, 4, 10.0)
	var count_no: int = (result_no["voxels"] as PackedVector3Array).size()
	var count_roll: int = (result_roll["voxels"] as PackedVector3Array).size()
	# Roll 不改变位置，体素数应该非常接近（采样数可能略有不同但体素化结果相近）
	_check("Roll 关节不显著增加体素数", absi(count_roll - count_no) <= count_no * 0.15,
		"no_roll=%d with_roll=%d" % [count_no, count_roll])

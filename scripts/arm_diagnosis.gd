extends RefCounted
## 任意 2~6 关节机械臂的位姿可控性诊断。
## 位置优先；姿态按 Pitch、Yaw、Roll 依次从位置雅可比零空间中选择。

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

const SINGULAR_EPS: float = 1.0
const DIR_EPS: float = 1.0
const ALL_ORIENTATION: Dictionary = {"roll": true, "pitch": true, "yaw": true}


## 返回 {position_dof, orientation_dof, pose_dof, orientation_mask,
## orientation_reason, issues, locked}。
func analyze(joints: Array, jc: int) -> Dictionary:
	var cg = CG.new()
	var issues: Array = []
	var axes_names: Array = cg.joint_axes(joints, jc)
	var lens: Array = cg.joint_lengths(joints, jc)
	var total_len: float = 0.0
	for value in lens:
		total_len += absf(float(value))
	if total_len < 1.0:
		issues.append({"type": "Error",
			"msg": "所有连杆长度都是 0，末端永远在底座位置。请填写各关节之后的连杆长度。"})
		return _result(0, {}, issues, ["X", "Y", "Z"], "连杆长度全为 0")

	var best_position_dof: int = 0
	var best_order: Array = []
	var best_dirs: Vector3 = Vector3.ZERO
	for sample in _sample_poses(joints, jc):
		var chain: Dictionary = cg.fk_chain(sample, joints, jc)
		var cols: Array = cg.jacobian_columns(chain, jc)
		var position_dof: int = _rank(cols)
		var task: Dictionary = cg.orientation_task_rows(chain, jc, ALL_ORIENTATION)
		var order: Array = task["order"]
		if position_dof > best_position_dof \
				or (position_dof == best_position_dof and order.size() > best_order.size()):
			best_position_dof = position_dof
			best_order = order.duplicate()
		var reach: Vector3 = _direction_reach(cols)
		best_dirs = Vector3(maxf(best_dirs.x, reach.x), maxf(best_dirs.y, reach.y),
			maxf(best_dirs.z, reach.z))

	var locked: Array = []
	if best_dirs.x < DIR_EPS: locked.append("X（前后）")
	if best_dirs.y < DIR_EPS: locked.append("Y（左右）")
	if best_dirs.z < DIR_EPS: locked.append("Z（上下）")
	_report_position(issues, best_position_dof, locked, axes_names)

	var mask: Dictionary = {"roll": false, "pitch": false, "yaw": false}
	for name in best_order:
		mask[name] = true
	var reason: Dictionary = {}
	for name in ["pitch", "yaw", "roll"]:
		if bool(mask[name]):
			continue
		if best_position_dof < 3:
			reason[name] = "末端位置还不能在空间中自由移动"
		elif jc <= best_position_dof:
			reason[name] = "关节全部用于控制位置，没有剩余自由度"
		else:
			reason[name] = "转轴搭配使该姿态方向与位置或更高优先级姿态耦合"
	_report_orientation(issues, mask, reason, jc, best_position_dof)
	issues.append_array(_check_useless_joints(cg, joints, jc))
	return {
		"position_dof": best_position_dof,
		"orientation_dof": best_order.size(),
		"pose_dof": best_position_dof + best_order.size(),
		"orientation_mask": mask,
		"orientation_reason": reason,
		"issues": issues,
		"locked": locked,
	}


func _result(position_dof: int, mask: Dictionary, issues: Array, locked: Array,
		reason_text: String) -> Dictionary:
	var full_mask: Dictionary = {"roll": false, "pitch": false, "yaw": false}
	for key in mask:
		full_mask[key] = bool(mask[key])
	var reasons: Dictionary = {}
	for key in full_mask:
		if not bool(full_mask[key]): reasons[key] = reason_text
	var orientation_dof: int = 0
	for value in full_mask.values():
		if bool(value): orientation_dof += 1
	return {"position_dof": position_dof, "orientation_dof": orientation_dof,
		"pose_dof": position_dof + orientation_dof, "orientation_mask": full_mask,
		"orientation_reason": reasons, "issues": issues, "locked": locked}


func _report_position(issues: Array, dof: int, locked: Array, axes_names: Array) -> void:
	if dof == 0:
		var all_roll: bool = _all_same(axes_names) and str(axes_names[0]) == CG.AXIS_ROLL
		issues.append({"type": "Error", "msg":
			("所有关节都是 Roll（绕连杆自身轴自转），末端位置完全动不了。"
			if all_roll else "这个构形没有任何关节能改变末端位置。")})
	elif dof == 1:
		issues.append({"type": "Error", "msg": "这个构形的末端只能沿一条线运动。"})
	elif dof == 2:
		issues.append({"type": "Warn", "msg": "这个构形的末端只能在一个曲面内运动。"})
	elif not locked.is_empty():
		issues.append({"type": "Warn", "msg": "末端无法沿 %s 移动。" % "、".join(locked)})


func _report_orientation(issues: Array, mask: Dictionary, reasons: Dictionary,
		jc: int, position_dof: int) -> void:
	var enabled: Array[String] = []
	for name in ["pitch", "yaw", "roll"]:
		if bool(mask[name]): enabled.append(name.capitalize())
	if not enabled.is_empty():
		issues.append({"type": "Info", "msg": "保持位置优先时可同时控制末端姿态：%s。"
			% "、".join(enabled)})
	if enabled.size() < 3 and position_dof >= 3:
		issues.append({"type": "Warn", "msg": "当前构形不能在保持 XYZ 的同时控制完整 Roll/Pitch/Yaw。"
			+ ("增加关节可以提供更多姿态自由度。" if jc < 6 else "请调整关节转轴搭配。")})
	for name in reasons:
		if not bool(mask.get(name, false)) and not str(reasons[name]).is_empty():
			# 具体理由由 UI 放在禁用控件的提示中，诊断区不重复刷三行。
			break


func _sample_poses(joints: Array, jc: int) -> Array:
	var home: Array = []
	for i in range(jc):
		var text: String = str(joints[i].get("zero", "")) if i < joints.size() else ""
		home.append(text.to_float() if text.is_valid_float() else 0.0)
	var out: Array = [home]
	for offsets in [[20.0, 30.0, -25.0, 15.0, 35.0, -10.0],
			[-35.0, 45.0, 20.0, -40.0, 15.0, 30.0],
			[60.0, -20.0, 50.0, 30.0, -45.0, 25.0]]:
		var pose: Array = []
		for i in range(jc): pose.append(home[i] + offsets[i])
		out.append(pose)
	return out


func _rank(cols: Array) -> int:
	var basis: Array[Vector3] = []
	for column in cols:
		var value: Vector3 = column
		for direction in basis: value -= direction * value.dot(direction)
		if value.length() > SINGULAR_EPS: basis.append(value.normalized())
		if basis.size() == 3: break
	return basis.size()


func _direction_reach(cols: Array) -> Vector3:
	var reach: Vector3 = Vector3.ZERO
	for column in cols:
		var value: Vector3 = column
		reach.x += value.x * value.x
		reach.y += value.y * value.y
		reach.z += value.z * value.z
	return Vector3(sqrt(reach.x), sqrt(reach.y), sqrt(reach.z))


func _all_same(values: Array) -> bool:
	if values.size() < 2: return false
	for value in values:
		if str(value) != str(values[0]): return false
	return true


func _check_useless_joints(cg, joints: Array, jc: int) -> Array:
	var issues: Array = []
	for i in range(jc):
		var useful: bool = false
		for sample in _sample_poses(joints, jc):
			var chain: Dictionary = cg.fk_chain(sample, joints, jc)
			var position_col: Vector3 = cg.jacobian_columns(chain, jc)[i]
			var angular_axis: Vector3 = chain["axes"][i]
			if position_col.length() > SINGULAR_EPS or angular_axis.length() > 0.5:
				useful = true
				break
		if not useful:
			issues.append({"type": "Warn", "msg": "关节%d对末端位姿没有贡献。" % (i + 1)})
	return issues

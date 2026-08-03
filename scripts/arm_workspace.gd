class_name ArmWorkspace
extends RefCounted
## 机械臂可达区域离线扫描器。
##
## 在 PC 侧用正运动学纯函数遍历关节空间，将所有末端位置离散化到 3D 体素网格。
## 不需要操作机械臂、不需要 MCU 连接。FK 是确定性数学运算，PC/MCU 结果等价。
##
## Roll 关节只改变姿态不改变位置，故扫描时固定为 0°，不参与采样。

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

## 默认体素边长（mm）。越大越粗但渲染量少，越小越精确但体素多。
const DEFAULT_VOXEL_SIZE: float = 10.0
## 目标总评估次数上限。超过则自动降低每关节采样数。
const TARGET_EVALUATIONS: int = 200000

## 配置指纹：关节轴+长度+限位变化时失效，未变则命中缓存。
func fingerprint(joints: Array, jc: int) -> String:
	var cg := CG.new()
	var axes: Array = cg.joint_axes(joints, jc)
	var lens: Array = cg.joint_lengths(joints, jc)
	var canonical: String = ""
	for i in range(jc):
		var lo: float = _joint_min(joints, i)
		var hi: float = _joint_max(joints, i)
		canonical += "%s,%.3f,%.3f,%.3f;" % [str(axes[i]), lens[i], lo, hi]
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(canonical.to_utf8_buffer())
	return ctx.finish().hex_encode().substr(0, 16)


## 计算机械臂所有可达的末端位置，返回体素化结果。
##
## 返回:
##   {
##     "voxels":  PackedVector3Array,  命中体素的中心坐标（机器人坐标 mm）
##     "bounds":  AABB,                包围所有体素的最小 AABB（机器人坐标 mm）
##     "voxel_size": float,            体素边长（mm）
##     "point_count": int,             实际评估的 FK 次数
##   }
func compute_workspace(joints: Array, jc: int, voxel_size: float = DEFAULT_VOXEL_SIZE) -> Dictionary:
	var cg := CG.new()
	var axes: Array = cg.joint_axes(joints, jc)
	var lens: Array = cg.joint_lengths(joints, jc)

	# 判断哪些关节需要采样（非 Roll），哪些固定为 0（Roll）
	var sample_indices: Array[int] = []
	for i in range(jc):
		if str(axes[i]) != CG.AXIS_ROLL:
			sample_indices.append(i)

	var n_sweep: int = sample_indices.size()
	if n_sweep == 0:
		# 全 Roll 臂：末端永远在原点
		return _empty_result(voxel_size)

	# 自适应采样数：每关节采样数取 floor(TARGET^(1/n_sweep))
	var per_joint: int = int(round(pow(float(TARGET_EVALUATIONS), 1.0 / float(n_sweep))))
	per_joint = maxi(per_joint, 3) # 至少 3 个点（两端+中间）

	# 构建每个待采样关节的角度列表
	var angle_lists: Array = [] # Array[Array[float]]
	for idx in sample_indices:
		var lo: float = _joint_min(joints, idx)
		var hi: float = _joint_max(joints, idx)
		var steps: Array = []
		if per_joint == 1:
			steps.append((lo + hi) * 0.5)
		else:
			for k in range(per_joint):
				var t: float = float(k) / float(per_joint - 1)
				steps.append(lerpf(lo, hi, t))
		angle_lists.append(steps)

	# 笛卡尔积遍历 + FK + 体素化
	var voxels: Dictionary = {} # Vector3i -> true（用 Dictionary 做 HashSet）
	var total: int = 1
	for lst in angle_lists:
		total *= (lst as Array).size()

	var iter: Array = []
	iter.resize(n_sweep)
	for i in range(n_sweep):
		iter[i] = 0

	var base_angles: Array = []
	base_angles.resize(jc)
	for i in range(jc):
		base_angles[i] = 0.0

	var count: int = 0
	while true:
		# 填入当前迭代的采样角度
		var angles: Array = base_angles.duplicate()
		for s in range(n_sweep):
			angles[sample_indices[s]] = (angle_lists[s] as Array)[iter[s]]

		# 正运动学
		var chain: Dictionary = cg.fk_chain(angles, joints, jc)
		var pts: Array = chain["points"]
		var tip: Vector3 = pts[pts.size() - 1]

		# 体素化
		var vi := _voxel_index(tip, voxel_size)
		voxels[vi] = true
		count += 1

		# 进位
		var carry: int = 1
		for s in range(n_sweep):
			iter[s] += carry
			if iter[s] < (angle_lists[s] as Array).size():
				carry = 0
				break
			iter[s] = 0
			carry = 1
		if carry == 1:
			break

	# 转为有序数组
	var voxel_list: PackedVector3Array = PackedVector3Array()
	voxel_list.resize(voxels.size())
	var bounds := AABB()
	var vi_idx: int = 0
	for key in voxels:
		var center := _voxel_center(key, voxel_size)
		voxel_list[vi_idx] = center
		vi_idx += 1
		if bounds.size == Vector3.ZERO:
			bounds = AABB(center, Vector3.ZERO)
		else:
			bounds = bounds.expand(center)

	# 向外扩展半个体素，使 bounds 覆盖完整体素
	var half_v: Vector3 = Vector3.ONE * (voxel_size * 0.5)
	bounds = AABB(bounds.position - half_v, bounds.size + half_v * 2.0)

	return {
		"voxels": voxel_list,
		"bounds": bounds,
		"voxel_size": voxel_size,
		"point_count": count,
	}


## 体素索引：把连续坐标离散化到整数网格。
func _voxel_index(pos: Vector3, voxel_size: float) -> Vector3i:
	return Vector3i(
		int(round(pos.x / voxel_size)),
		int(round(pos.y / voxel_size)),
		int(round(pos.z / voxel_size)),
	)


## 体素索引 -> 体素中心坐标（机器人坐标 mm）。
func _voxel_center(vi: Vector3i, voxel_size: float) -> Vector3:
	return Vector3(
		float(vi.x) * voxel_size,
		float(vi.y) * voxel_size,
		float(vi.z) * voxel_size,
	)


func _empty_result(voxel_size: float) -> Dictionary:
	return {
		"voxels": PackedVector3Array([Vector3.ZERO]),
		"bounds": AABB(Vector3.ZERO, Vector3.ONE * voxel_size),
		"voxel_size": voxel_size,
		"point_count": 1,
	}


func _joint_min(joints: Array, i: int) -> float:
	if i < joints.size():
		var s: String = str(joints[i].get("min", ""))
		s = s.strip_edges()
		if s.is_valid_float():
			return s.to_float()
	return CG.JOINT_ANGLE_MIN


func _joint_max(joints: Array, i: int) -> float:
	if i < joints.size():
		var s: String = str(joints[i].get("max", ""))
		s = s.strip_edges()
		if s.is_valid_float():
			return s.to_float()
	return CG.JOINT_ANGLE_MAX

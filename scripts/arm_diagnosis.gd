extends RefCounted
## 机械臂构形诊断。
##
## 用户是没有机械基础的大一学生，会造出各种构形的臂。本模块在生成代码之前
## 告诉他们「这个臂能干什么、不能干什么」，而不是等上板子才发现末端动不了。
##
## 判据基于雅可比矩阵的秩：J 的第 i 列 = a_i × (p_tip - o_i)，
## 描述关节 i 单位转动引起的末端线速度。这些列向量张成的空间就是
## 末端在当前姿态下能移动的方向集合，其维数即可控自由度。
##
## 注意：这是**局部**判据（依赖当前姿态）。奇异位形下秩会临时降低，
## 故对多个采样姿态取最大值，避免把「恰好这个姿态卡住」误报成「构形有缺陷」。

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")

## 奇异值视为 0 的阈值。单位是 mm/rad，取 1mm/rad：
## 关节转 1 弧度末端移动不到 1mm，实用上等于动不了。
const SINGULAR_EPS: float = 1.0
## 判定「某方向不可控」时，该方向上可达速度的阈值（mm/rad）
const DIR_EPS: float = 1.0


## 诊断入口。
## joints: 关节配置数组（含 axis / len / zero / min / max）
## 返回 {"dof": int, "issues": Array[{type, msg}], "locked": Array[String]}
func analyze(joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> Dictionary:
	var cg = CG.new()
	var issues: Array = []
	var axes_names: Array = cg.joint_axes(joints, jc, config_type)
	var lens: Array = cg.joint_lengths(joints, jc, config_type, l1, l2, l3)
	# --- 连杆长度合理性：全零臂末端恒在原点 ---
	var total_len: float = 0.0
	for v in lens:
		total_len += float(v)
	if total_len < 1.0:
		issues.append({"type": "Error",
			"msg": "所有连杆长度都是 0，末端永远在底座位置。请填写各关节之后的连杆长度。"})
		return {"dof": 0, "issues": issues, "locked": ["X", "Y", "Z"]}
	# --- 在多个采样姿态上求可控自由度，取最大值 ---
	var best_dof: int = 0
	var best_dirs: Vector3 = Vector3.ZERO # 各方向可达速度的最大值
	for sample in _sample_poses(joints, jc):
		var chain: Dictionary = cg.fk_chain(sample, joints, jc, config_type, l1, l2, l3)
		var cols: Array = _jacobian_columns(chain, jc)
		best_dof = max(best_dof, _rank(cols))
		var reach: Vector3 = _direction_reach(cols)
		best_dirs = Vector3(maxf(best_dirs.x, reach.x),
			maxf(best_dirs.y, reach.y), maxf(best_dirs.z, reach.z))
	var locked: Array = []
	if best_dirs.x < DIR_EPS:
		locked.append("X（前后）")
	if best_dirs.y < DIR_EPS:
		locked.append("Y（左右）")
	if best_dirs.z < DIR_EPS:
		locked.append("Z（上下）")
	# 面向无机械基础的学生：同一个毛病只说一次。
	# 末端整体动不了时，逐关节的「这个关节没贡献」是废话，直接给根因。
	if best_dof == 0:
		var all_roll: bool = _all_same(axes_names) and str(axes_names[0]) == CG.AXIS_ROLL
		if all_roll:
			issues.append({"type": "Error",
				"msg": "所有关节都是 Roll（绕连杆自身轴自转），末端完全动不了。"
					+ "至少需要一个 Pitch（上下俯仰）或 Yaw（左右摆动）关节。"})
		else:
			issues.append({"type": "Error",
				"msg": "这个构形的末端完全动不了：没有任何关节的转动能改变末端位置。"
					+ "检查各关节的转轴方向，以及关节之间的连杆长度是否都填了。"})
		return {"dof": 0, "issues": issues, "locked": locked}
	if best_dof == 1:
		issues.append({"type": "Error",
			"msg": "这个构形的末端只能沿一条线运动。"
				+ "想让末端在空间里自由移动，至少需要 3 个方向不同的转轴"
				+ "（例如 1 个 Yaw + 2 个 Pitch）。"})
	elif best_dof == 2:
		# 把「只能在平面内」与「哪个方向锁死」合并成一条
		var same: bool = _all_same(axes_names)
		var msg: String = "这个构形的末端只能在一个曲面内运动"
		if not locked.is_empty():
			msg += "，无法沿 %s 移动" % "、".join(locked)
		msg += "。"
		if same:
			msg += "因为所有关节都是 %s，转轴互相平行。" % str(axes_names[0])
		msg += "加一个方向不同的转轴即可让末端进入三维空间。"
		issues.append({"type": "Warn", "msg": msg})
	elif not locked.is_empty():
		# 自由度够但某个坐标方向仍到不了（罕见，构形很怪时可能出现）
		issues.append({"type": "Warn",
			"msg": "末端无法沿 %s 移动。" % "、".join(locked)})
	# 逐关节提示只在整体可动时才有意义
	issues.append_array(_check_useless_joints(cg, joints, jc, config_type, l1, l2, l3))
	return {"dof": best_dof, "issues": issues, "locked": locked}


## 是否所有转轴名都相同
func _all_same(axes_names: Array) -> bool:
	if axes_names.size() < 2:
		return false
	for n in axes_names:
		if str(n) != str(axes_names[0]):
			return false
	return true


## 采样姿态：初始角 + 几组偏置。
## 单一姿态可能恰好落在奇异位形上（例如全部关节角为 0 时多个轴共线），
## 只看那一个会把正常构形误判成有缺陷。
func _sample_poses(joints: Array, jc: int) -> Array:
	var home: Array = []
	for i in range(jc):
		var s: String = ""
		if i < joints.size():
			s = str(joints[i].get("zero", "")).strip_edges()
		home.append(s.to_float() if s.is_valid_float() else 0.0)
	var out: Array = [home]
	# 几组错开的偏置，尽量避开共线
	for offs in [[20.0, 30.0, -25.0, 15.0], [-35.0, 45.0, 20.0, -40.0],
			[60.0, -20.0, 50.0, 30.0]]:
		var p: Array = []
		for i in range(jc):
			p.append(home[i] + offs[i % offs.size()])
		out.append(p)
	return out


## 雅可比的列向量：第 i 列 = a_i × (p_tip - o_i)，单位 mm/rad
func _jacobian_columns(chain: Dictionary, jc: int) -> Array:
	var pts: Array = chain["points"]
	var axes: Array = chain["axes"]
	var tip: Vector3 = pts[pts.size() - 1]
	var cols: Array = []
	for i in range(jc):
		cols.append((axes[i] as Vector3).cross(tip - (pts[i] as Vector3)))
	return cols


## 列向量组的秩（Gram-Schmidt 正交化后数一数非零向量）。
## 只有 3 行，秩最多 3，手写比引入线代库简单可靠。
func _rank(cols: Array) -> int:
	var basis: Array = []
	for c in cols:
		var v: Vector3 = c
		# 减去已有正交基上的投影
		for b in basis:
			v -= (b as Vector3) * v.dot(b)
		if v.length() > SINGULAR_EPS:
			basis.append(v.normalized())
		if basis.size() == 3:
			break
	return basis.size()


## 各坐标方向上能达到的最大末端速度（mm/rad）。
## 用于判断「某个方向完全动不了」——比只看秩更能给出人话提示。
func _direction_reach(cols: Array) -> Vector3:
	# 对每个坐标轴，取所有列在该轴上分量绝对值的最大值。
	# 严格说应解最小二乘，但这里只需判断「是否恒为 0」，取最大分量足够。
	var r: Vector3 = Vector3.ZERO
	for c in cols:
		var v: Vector3 = c
		r.x = maxf(r.x, absf(v.x))
		r.y = maxf(r.y, absf(v.y))
		r.z = maxf(r.z, absf(v.z))
	return r


## 找出「转动完全不改变末端位置」的关节。
## 最典型的是末端那个 Roll：绕自身轴自转，末端位置纹丝不动。
## 这不算错（夹爪自转有用），但要告诉学生它不参与定位。
func _check_useless_joints(cg, joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> Array:
	var out: Array = []
	var axes_names: Array = cg.joint_axes(joints, jc, config_type)
	for i in range(jc):
		var moves: bool = false
		for sample in _sample_poses(joints, jc):
			var chain: Dictionary = cg.fk_chain(sample, joints, jc, config_type,
				l1, l2, l3)
			var cols: Array = _jacobian_columns(chain, jc)
			if (cols[i] as Vector3).length() > DIR_EPS:
				moves = true
				break
		if not moves:
			# 末端 Roll 是正常设计（夹爪自转），单独措辞
			if i == jc - 1 and axes_names[i] == cg.AXIS_ROLL:
				out.append({"type": "Info",
					"msg": "关节%d（Roll）绕末端自身轴自转，不改变末端位置——"
						% (i + 1) + "它的作用是转动夹爪朝向，这是正常的。"})
			else:
				out.append({"type": "Warn",
					"msg": "关节%d（%s）的转动不改变末端位置，对定位没有贡献。"
						% [i + 1, axes_names[i]]
						+ "检查它的转轴方向是否装错，或它之后的连杆长度是否为 0。"})
	return out


## 注：「全同轴」的提示已并入 analyze 的自由度判定分支，
## 避免同一个毛病输出两三条重叠的消息（学生看不过来）。

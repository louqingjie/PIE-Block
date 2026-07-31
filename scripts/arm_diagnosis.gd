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
## φ 梯度残差占 |g| 的比例阈值。相对量，故与 g 的整体缩放无关。
const PITCH_REL_EPS: float = 1.0e-3


## 诊断入口。
## joints: 关节配置数组（含 axis / len / zero / min / max）
## 返回 {
##   "dof": int,                   末端可控自由度（0~3）
##   "issues": Array[{type, msg}],
##   "locked": Array[String],      完全动不了的坐标方向
##   "pitch_dof": bool,            末端俯仰角能否在不动位置的前提下单独调
##   "pitch_reason": String,       pitch_dof 为假时的简短理由（供 UI 置灰提示）
## }
func analyze(joints: Array, jc: int) -> Dictionary:
	var cg = CG.new()
	var issues: Array = []
	var axes_names: Array = cg.joint_axes(joints, jc)
	var lens: Array = cg.joint_lengths(joints, jc)
	# --- 连杆长度合理性：全零臂末端恒在原点 ---
	var total_len: float = 0.0
	for v in lens:
		total_len += float(v)
	if total_len < 1.0:
		issues.append({"type": "Error",
			"msg": "所有连杆长度都是 0，末端永远在底座位置。请填写各关节之后的连杆长度。"})
		return {"dof": 0, "issues": issues, "locked": ["X", "Y", "Z"],
			"pitch_dof": false, "pitch_reason": "连杆长度全为 0"}
	# --- 在多个采样姿态上求可控自由度，取最大值 ---
	var best_dof: int = 0
	var best_dirs: Vector3 = Vector3.ZERO # 各方向可达速度的最大值
	# φ 解耦只需「存在某个姿态能做到」，故各采样姿态取或
	var pitch_ok: bool = false
	for sample in _sample_poses(joints, jc):
		var chain: Dictionary = cg.fk_chain(sample, joints, jc)
		var cols: Array = _jacobian_columns(chain, jc)
		best_dof = max(best_dof, _rank(cols))
		if _pitch_decoupled(chain, jc):
			pitch_ok = true
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
					+"至少需要一个 Pitch（上下俯仰）或 Yaw（左右摆动）关节。"})
		else:
			issues.append({"type": "Error",
				"msg": "这个构形的末端完全动不了：没有任何关节的转动能改变末端位置。"
					+"检查各关节的转轴方向，以及关节之间的连杆长度是否都填了。"})
		# 末端根本动不了时不再提 φ：先修位置，姿态无从谈起
		return {"dof": 0, "issues": issues, "locked": locked,
			"pitch_dof": false, "pitch_reason": "末端位置本身动不了"}
	if best_dof == 1:
		issues.append({"type": "Error",
			"msg": "这个构形的末端只能沿一条线运动。"
				+"想让末端在空间里自由移动，至少需要 3 个方向不同的转轴"
				+"（例如 1 个 Yaw + 2 个 Pitch）。"})
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
	# 末端俯仰角 φ 是否能在不动位置的前提下单独调
	var pitch_reason: String = _report_pitch(issues, pitch_ok, best_dof, jc, axes_names)
	# 逐关节提示只在整体可动时才有意义
	issues.append_array(_check_useless_joints(cg, joints, jc))
	return {"dof": best_dof, "issues": issues, "locked": locked,
		"pitch_dof": pitch_ok, "pitch_reason": pitch_reason}


## φ 可控性的三档报告。返回一句简短理由（供 UI 置灰提示用）。
##
## 不可控时必须说出原因：学生看到输入框置灰但不知道为什么，
## 等于又回到了「静默出错」。
func _report_pitch(issues: Array, pitch_ok: bool, dof: int, jc: int,
		axes_names: Array) -> String:
	if pitch_ok:
		issues.append({"type": "Info",
			"msg": "末端俯仰角可以单独调：保持夹爪位置不动、只改变抛下或抬起的角度。"
				+"抄桌面上的矿石需要向下扣，抽货架上的需要水平插，这个角度就是用来切换的。"})
		# 4 关节恰好把 3 位置 + 1 姿态填满，余量为零：
		# 任何一个关节撞上限位就失去解耦能力
		if jc == 4 and dof >= 3:
			issues.append({"type": "Info",
				"msg": "4 个关节正好够用，但没有余量：只要有一个关节转到限位，"
					+"俯仰角就不能再单独调了。加一个关节会宽裕很多。"})
		return ""
	# 位置本身都没控满，先修位置（上面已经报过了，不重复刷消息）
	if dof < 3:
		return "末端还不能在空间中自由移动"
	# 位置满秩但 φ 被绑死：区分关节数不够与转轴共面两种成因
	if jc < 4:
		var reason: String = "只有 %d 个关节，全部用于控制位置了" % jc
		issues.append({"type": "Warn",
			"msg": "末端俯仰角无法单独调：%s。" % reason
				+"现在夹爪杆到某个位置时，服开的角度就被确定了，不能另行改。"
				+"想要能控抄取角度，至少需要 4 个关节。"})
		return reason
	var all_same_axis: bool = _all_same(axes_names)
	var msg: String = "末端俯仰角无法单独调：关节数够，但转轴方向的搭配让它跟位置锁在了一起。"
	if all_same_axis:
		msg += "所有关节都是 %s，转轴互相平行。" % str(axes_names[0])
	msg += "把其中一个关节改成 Pitch（上下俯仰）往往就能解开。"
	issues.append({"type": "Warn", "msg": msg})
	return "转轴搭配让俯仰角与位置耦合"


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


## 雅可比的列向量。公式的唯一真相源在 codegen_engineer_ik，
## 这里只做转发（本模块的测试与反证仍通过这个名字调用）。
func _jacobian_columns(chain: Dictionary, jc: int) -> Array:
	return CG.new().jacobian_columns(chain, jc)


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


# ------------------------------------------------------------------ 通用向量运算
## 以下几个函数处理**关节空间**的 n 维行向量（n = 关节数），
## 与上面处理任务空间 Vector3 的那些不是一回事，勿混用。

## n 维点积
func _vdot(a: Array, b: Array) -> float:
	var s: float = 0.0
	for i in range(mini(a.size(), b.size())):
		s += float(a[i]) * float(b[i])
	return s


## n 维模长
func _vlen(a: Array) -> float:
	return sqrt(_vdot(a, a))


## a - k*b
func _vsub_scaled(a: Array, b: Array, k: float) -> Array:
	var out: Array = []
	for i in range(a.size()):
		out.append(float(a[i]) - k * float(b[i]))
	return out


## 对行向量组做 Gram-Schmidt，返回单位正交基（丢弃长度可忽略的行）。
## eps 是绝对阈值；调用方按各自量纲传入。
func _orthonormal_basis(rows: Array, eps: float) -> Array:
	var basis: Array = []
	for r in rows:
		var v: Array = []
		for x in r:
			v.append(float(x))
		for b in basis:
			v = _vsub_scaled(v, b, _vdot(v, b))
		var n: float = _vlen(v)
		if n > eps:
			var u: Array = []
			for x in v:
				u.append(float(x) / n)
			basis.append(u)
	return basis


# ------------------------------------------------------------------ 末端俯仰角 φ
## φ 的通用定义：末端朝向的仰角 `φ = asin(â_z)`，â = 末端 +X 方向。
##
## 旧的 `φ = θ1+θ2+θ3` 只在「三个共面 Pitch」时成立，任意构形下那个加法
## 不对应任何几何量。仰角定义对任何构形都成立，物理含义仍是抓取俯仰角。


## φ 对各关节角的梯度（1×n 行向量，单位 rad/rad）。
## 公式的唯一真相源在 codegen_engineer_ik（雅可比 IK 也要用同一份），
## 这里只做转发。返回空数组表示该姿态下 φ 参数化退化，应跳过。
func _pitch_gradient(chain: Dictionary, jc: int) -> Array:
	return CG.new().pitch_gradient(chain, jc)


## 末端俯仰角是否与位置解耦可控：
## 存在关节速度 q̇ 使 `J_v q̇ = 0` 且 `g·q̇ ≠ 0`（位置不动、φ 变化）。
##
## 数学上等价于 `g ∉ rowspace(J_v)`：
## 若 g 落在 J_v 的行空间里，它就与 J_v 的零空间正交，
## 任何不动末端位置的关节组合都必然让 φ 保持不变。
##
## 做法是把 g 投影到 J_v 三个行向量的正交基上，看残差是否显著。
## 阈值取相对量（占 |g| 的比例），因为 J_v 是 mm/rad 而 g 是无量纲，
## 两者不可比，只有「g 自己剩下多少」才有意义。
func _pitch_decoupled(chain: Dictionary, jc: int) -> bool:
	var g: Array = _pitch_gradient(chain, jc)
	if g.is_empty():
		return false
	var g_norm: float = _vlen(g)
	# φ 完全不受任何关节影响（例如末端朝向被构形锁死）
	if g_norm < PITCH_REL_EPS:
		return false
	# J_v 的三个行向量：把 Vector3 列转置成 x/y/z 三行
	var cols: Array = _jacobian_columns(chain, jc)
	var rows: Array = [[], [], []]
	for i in range(jc):
		var c: Vector3 = cols[i]
		rows[0].append(c.x)
		rows[1].append(c.y)
		rows[2].append(c.z)
	# 行向量量纲是 mm/rad，沿用位置侧的奇异阈值
	var basis: Array = _orthonormal_basis(rows, SINGULAR_EPS)
	# 位置必须在该姿态下被完全锁住（J_v 满秩），才谈得上「位置不动、只转 φ」。
	# 否则行空间变小，g 的残差自然非零，会把「位置本身失控」误判成「φ 解耦」。
	# 这是奇异姿态下的假阳性来源（踩过：3 关节满秩臂被误判为 φ 可控）。
	if basis.size() < 3:
		return false
	var resid: Array = g.duplicate()
	for b in basis:
		resid = _vsub_scaled(resid, b, _vdot(resid, b))
	return _vlen(resid) / g_norm > PITCH_REL_EPS


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
func _check_useless_joints(cg, joints: Array, jc: int) -> Array:
	var out: Array = []
	var axes_names: Array = cg.joint_axes(joints, jc)
	for i in range(jc):
		var moves: bool = false
		for sample in _sample_poses(joints, jc):
			var chain: Dictionary = cg.fk_chain(sample, joints, jc)
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
						+"检查它的转轴方向是否装错，或它之后的连杆长度是否为 0。"})
	return out


## 注：「全同轴」的提示已并入 analyze 的自由度判定分支，
## 避免同一个毛病输出两三条重叠的消息（学生看不过来）。

extends SceneTree

## 雅可比转置数值逆解验证。
##
## 唯一逆解路径必须证明三件事：
##   1. 它能收敛（误差单调下降，不振荡）
##   2. FK 目标与 IK 结果一致
##   3. φ 真的解耦可控（只改 φ 时末端位置不动）
##
## 运行：godot --headless --path . --script scripts/test_ik_jacobian.gd

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const DIAG = preload("res://scripts/arm_diagnosis.gd")

var _cg = CG.new()
var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


## 构造关节配置。限位默认放宽到 ±180，避免测收敛性时被限位干扰
func _mk(axes: Array, lens: Array, lo: float = -180.0, hi: float = 180.0) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({"axis": axes[i], "len": str(lens[i]), "zero": "0",
			"min": str(lo), "max": str(hi)})
	return out


func _zeros(n: int) -> Array:
	var a: Array = []
	for _i in range(n):
		a.append(0.0)
	return a


## 末端位置
func _tip(angles: Array, joints: Array, jc: int) -> Vector3:
	var chain: Dictionary = _cg.fk_chain(angles, joints, jc)
	var pts: Array = chain["points"]
	return pts[pts.size() - 1]


func _initialize() -> void:
	print("=== 雅可比数值逆解验证 ===\n")
	_test_convergence()
	_test_fk_ik_roundtrip()
	_test_phi_decoupled_in_practice()
	_test_unreachable()
	_test_limits_respected()
	_test_arbitrary_configs()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


## 收敛性：误差必须持续下降，不能振荡或发散
func _test_convergence() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch", "Pitch"], [0, 120, 90, 40])
	var target: Vector3 = Vector3(150.0, 40.0, 60.0)
	var ang: Array = [0.0, 20.0, -30.0, 10.0]
	var errs: Array = []
	for _n in range(60):
		var r: Dictionary = _cg.solve_ik_jacobian(target, NAN, ang, j, 4)
		ang = r["angles"]
		errs.append(float(r["err"]))
	_check("收敛：误差下降到 1mm 内", errs[errs.size() - 1] < 1.0,
		"最终误差 %.3f" % errs[errs.size() - 1])
	# 单调性：允许极小的回弹（限位钳位可能造成），但不能反复振荡
	var rises: int = 0
	for i in range(1, errs.size()):
		if errs[i] > errs[i - 1] + 1e-6:
			rises += 1
	_check("收敛：误差基本单调（回升 < 3 次）", rises < 3, "回升 %d 次" % rises)
	# 无 NaN
	var has_nan: bool = false
	for a in ang:
		if is_nan(float(a)):
			has_nan = true
	_check("收敛：结果无 NaN", not has_nan, str(ang))


## FK -> IK 自洽：拿 FK 算出的点当目标，应能解回到该位置
func _test_fk_ik_roundtrip() -> void:
	var cases: Array = [
		{"axes": ["Yaw", "Pitch", "Pitch"], "lens": [0, 120, 90],
			"ang": [30.0, -25.0, 40.0], "tag": "3关节"},
		{"axes": ["Yaw", "Pitch", "Pitch", "Pitch"], "lens": [0, 120, 90, 40],
			"ang": [-20.0, 35.0, -30.0, 15.0], "tag": "4关节"},
		{"axes": ["Yaw", "Pitch", "Pitch", "Roll", "Pitch"],
			"lens": [0, 120, 90, 0, 40], "ang": [15.0, 40.0, -35.0, 25.0, 20.0],
			"tag": "5关节含Roll"},
		{"axes": ["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"],
			"lens": [0, 120, 90, 0, 40, 25],
			"ang": [25.0, 30.0, -20.0, 40.0, 15.0, 30.0], "tag": "6关节"},
	]
	for c in cases:
		var jc: int = (c["axes"] as Array).size()
		var j: Array = _mk(c["axes"], c["lens"])
		var goal: Vector3 = _tip(c["ang"], j, jc)
		# 从零位起解，不给它原答案当初值
		var r: Dictionary = _cg.solve_ik_jacobian_converge(goal, NAN,
			_zeros(jc), j, jc)
		var got: Vector3 = _tip(r["angles"], j, jc)
		_check("%s FK→IK 自洽（<1mm）" % c["tag"], goal.distance_to(got) < 1.0,
			"目标 %s 实际 %s 差 %.3f" % [str(goal), str(got), goal.distance_to(got)])


## φ 解耦的实际兑现：诊断说可控，就必须真能只改 φ 而末端不动。
## Phase 1 只证明了「数学上存在这样的关节速度」，这里证明 IK 真的能找到它。
func _test_phi_decoupled_in_practice() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch", "Pitch"], [0, 120, 90, 40])
	var diag: Dictionary = DIAG.new().analyze(j, 4)
	_check("4关节 诊断判定 φ 可控（前提）", bool(diag["pitch_dof"]), str(diag))
	# 先解到一个位置 + 初始 φ
	var target: Vector3 = Vector3(150.0, 30.0, 50.0)
	var r0: Dictionary = _cg.solve_ik_jacobian_converge(target, -20.0,
		_zeros(4), j, 4)
	var ang0: Array = r0["angles"]
	var tip0: Vector3 = _tip(ang0, j, 4)
	var chain0: Dictionary = _cg.fk_chain(ang0, j, 4)
	var phi0: float = _cg.tip_pitch_deg(chain0)
	_check("φ 跟踪：初始 φ 达到 -20°", absf(phi0 - (-20.0)) < 2.0,
		"实际 %.2f" % phi0)
	# 只改 φ，位置目标不变
	var r1: Dictionary = _cg.solve_ik_jacobian_converge(target, -60.0,
		ang0, j, 4)
	var ang1: Array = r1["angles"]
	var tip1: Vector3 = _tip(ang1, j, 4)
	var chain1: Dictionary = _cg.fk_chain(ang1, j, 4)
	var phi1: float = _cg.tip_pitch_deg(chain1)
	_check("φ 跟踪：改到 -60°", absf(phi1 - (-60.0)) < 2.0, "实际 %.2f" % phi1)
	# 这是本测试的重点：位置不能漂
	_check("φ 变化时末端位置不漂（<1mm）", tip0.distance_to(tip1) < 1.0,
		"漂移 %.3f mm（%s -> %s）" % [tip0.distance_to(tip1), str(tip0), str(tip1)])
	# 关节角确实动了（否则"位置不漂"是因为什么都没做）
	var moved: bool = false
	for i in range(4):
		if absf(float(ang0[i]) - float(ang1[i])) > 1.0:
			moved = true
	_check("φ 变化时关节确实动了", moved, "%s -> %s" % [str(ang0), str(ang1)])


## 目标远超可达域：应停在最近点、不产生 NaN、且标记不可达
func _test_unreachable() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch"], [0, 100, 80])
	var far: Vector3 = Vector3(5000.0, 0.0, 0.0)
	var r: Dictionary = _cg.solve_ik_jacobian_converge(far, NAN, _zeros(3),
		j, 3)
	var tip: Vector3 = _tip(r["angles"], j, 3)
	var has_nan: bool = false
	for a in r["angles"]:
		if is_nan(float(a)):
			has_nan = true
	_check("超远目标 无 NaN", not has_nan, str(r["angles"]))
	_check("超远目标 标记不可达", not bool(r["reachable"]), str(r["reachable"]))
	# 停在臂展附近（总长 180）
	_check("超远目标 停在臂展边界附近", absf(tip.length() - 180.0) < 5.0,
		"末端半径 %.2f（臂展 180）" % tip.length())
	# 原点附近也不能炸（r 趋 0 时旧解析解要防除零，数值解应天然安全）
	var r0: Dictionary = _cg.solve_ik_jacobian_converge(Vector3.ZERO, NAN,
		_zeros(3), j, 3)
	var nan0: bool = false
	for a in r0["angles"]:
		if is_nan(float(a)):
			nan0 = true
	_check("目标在原点 无 NaN", not nan0, str(r0["angles"]))


## 限位必须被尊重：解出来的角不能超出 min/max
func _test_limits_respected() -> void:
	# 故意把限位收紧到 ±30，再要求一个需要大角度的目标
	var j: Array = _mk(["Yaw", "Pitch", "Pitch", "Pitch"], [0, 120, 90, 40],
		-30.0, 30.0)
	var r: Dictionary = _cg.solve_ik_jacobian_converge(Vector3(60.0, 90.0, 120.0),
		NAN, _zeros(4), j, 4)
	var bad: String = ""
	for i in range(4):
		var a: float = float(r["angles"][i])
		if a < -30.0 - 0.01 or a > 30.0 + 0.01:
			bad += "关节%d=%.2f " % [i + 1, a]
	_check("限位被尊重（±30）", bad.is_empty(), bad)


## 任意构形都不能崩：诊断报有问题的构形也要能安全跑完
func _test_arbitrary_configs() -> void:
	var configs: Array = [
		{"axes": ["Roll", "Roll", "Roll"], "lens": [50, 50, 50], "tag": "全Roll"},
		{"axes": ["Pitch", "Pitch", "Pitch"], "lens": [100, 80, 60], "tag": "全Pitch"},
		{"axes": ["Yaw", "Yaw", "Yaw"], "lens": [80, 60, 40], "tag": "全Yaw"},
		{"axes": ["Yaw", "Roll"], "lens": [0, 100], "tag": "2关节Yaw+Roll"},
		{"axes": ["Roll", "Pitch", "Roll", "Pitch", "Roll", "Pitch"],
			"lens": [30, 60, 30, 50, 20, 40], "tag": "6关节交替"},
	]
	for c in configs:
		var jc: int = (c["axes"] as Array).size()
		var j: Array = _mk(c["axes"], c["lens"])
		# 同时带 φ 目标，确保姿态项在退化构形下也不炸
		var r: Dictionary = _cg.solve_ik_jacobian_converge(
			Vector3(100.0, 50.0, 80.0), -45.0, _zeros(jc), j, jc)
		var bad: String = ""
		for i in range(jc):
			var a: float = float(r["angles"][i])
			if is_nan(a) or is_inf(a):
				bad += "关节%d=%s " % [i + 1, str(a)]
		_check("%s 不产生 NaN/Inf" % c["tag"], bad.is_empty(), bad)
		_check("%s 误差是有限值" % c["tag"],
			is_finite(float(r["err"])), str(r["err"]))

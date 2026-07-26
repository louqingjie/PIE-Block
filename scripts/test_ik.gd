extends SceneTree

## 数值核验脚本：直接调用 CodeGenEngineerIK.solve_ik 验证 IK 公式
## 运行方式：godot --headless --script scripts/test_ik.gd
## 注意：这里不再复制一份公式，而是核验生成器真正使用的那份，
##       否则公式改了测试却还通过，等于没测。

var _cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
var _fail: int = 0


## config_type: 0=2轴, 1=3轴, 2=4轴；elbow 为肘部分支符号
func _ik(config_type: int, jc: int, x: float, y: float, z: float, phi: float,
		l1: float, l2: float, l3: float = 0.0, elbow: float = 1.0) -> Array:
	return _cg.solve_ik(x, y, z, phi, l1, l2, l3, config_type, jc, elbow)


func _test(label: String, actual: Array, expected: Array, tol: float = 0.5) -> void:
	var ok: bool = actual.size() >= expected.size()
	if ok:
		for i in range(expected.size()):
			if abs(actual[i] - expected[i]) >= tol:
				ok = false
				break
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		print("      期望: %s" % str(expected))
		print("      实际: %s" % str(actual))
		_fail += 1


func _initialize() -> void:
	print("=== IK 公式数值核验 ===\n")
	# --- 2 轴 ---
	# r=141.42, θ2=acos(0)=90°, θ1=atan2(100,100)-atan2(100,0)=45-45=0°
	_test("2轴 (100,100) -> θ1=0°, θ2=90°",
		_ik(0, 2, 100, 100, 0, 0, 100, 100), [0.0, 90.0])
	# r=200 完全伸直
	_test("2轴 (200,0) -> θ1=0°, θ2=0°（完全伸直）",
		_ik(0, 2, 200, 0, 0, 0, 100, 100), [0.0, 0.0])
	_test("2轴 (0,200) -> θ1=90°, θ2=0°",
		_ik(0, 2, 0, 200, 0, 0, 100, 100), [90.0, 0.0])
	# 不等长连杆
	_test("2轴 L1=100,L2=50 (100,0) -> θ1≈-28.96°, θ2≈104.48°",
		_ik(0, 2, 100, 0, 0, 0, 100, 50), [-28.96, 104.48], 1.0)
	# 负肘部分支应得镜像解
	_test("2轴 负分支 (100,100) -> θ1=90°, θ2=-90°",
		_ik(0, 2, 100, 100, 0, 0, 100, 100, 0.0, -1.0), [90.0, -90.0])
	# --- 3 轴 ---
	_test("3轴 (100,0,100) -> θ0=0°, θ1=0°, θ2=90°",
		_ik(1, 3, 100, 0, 100, 0, 100, 100), [0.0, 0.0, 90.0])
	_test("3轴 (0,100,0) -> θ0=90°, θ1=-60°, θ2=120°",
		_ik(1, 3, 0, 100, 0, 0, 100, 100), [90.0, -60.0, 120.0], 1.0)
	# --- 4 轴：末端需沿 φ 回退 L3 得到腕心 ---
	# L3=0 时应退化为 3 轴 + θ3 补角
	_test("4轴 L3=0 (100,0,0,φ=90°) -> θ0=0°, θ1=-60°, θ2=120°, θ3=30°",
		_ik(2, 4, 100, 0, 0, 90, 100, 100, 0.0), [0.0, -60.0, 120.0, 30.0], 1.0)
	# L3=50, φ=0：腕心 = (100-50, 0) = (50, 0)，此时臂需大幅弯曲
	# c2=(2500-20000)/20000=-0.875 -> θ2=acos(-0.875)=151.05°
	# θ1=atan2(0,50)-atan2(100*sin151.05°,100+100*cos151.05°)=0-75.52°=-75.52°
	# θ3=0-(-75.52+151.05)=-75.52°
	_test("4轴 L3=50 (100,0,0,φ=0°) -> 腕心(50,0)",
		_ik(2, 4, 100, 0, 0, 0, 100, 100, 50.0), [0.0, -75.52, 151.05, -75.52], 1.0)
	# --- 正反解自洽：FK 起点反解回来应还原关节角 ---
	_test_round_trip()
	# --- joint_frames 末端必须与 forward_kinematics_angles 一致 ---
	_test_frames_consistency()
	# --- solve_ik_checked：可达性标志与钳位行为 ---
	_test_checked_reachability()
	# --- clamp_angles_to_limits ---
	_test_limit_clamp()
	# --- 可达性由 C 端 ik_solve 钳位，GDScript 端只夹紧 c2 ---
	# 目标(300,0) 超出 L1+L2=200，c2 被夹到 1 -> θ2=0，θ1=atan2(0,300)-0=0
	_test("2轴 越界 (300,0) -> c2 夹紧后 θ1=0°, θ2=0°",
		_ik(0, 2, 300, 0, 0, 0, 100, 100), [0.0, 0.0], 1.0)
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


## 正运动学 -> 逆解 -> 应还原原始关节角（验证两套公式一致）
func _test_round_trip() -> void:
	var cases: Array = [
		{"t": 0, "jc": 2, "ang": ["30", "60"], "elbow": 1.0},
		{"t": 0, "jc": 2, "ang": ["30", "-60"], "elbow": - 1.0},
		{"t": 1, "jc": 3, "ang": ["20", "40", "70"], "elbow": 1.0},
		{"t": 1, "jc": 3, "ang": ["20", "40", "-70"], "elbow": - 1.0},
		{"t": 2, "jc": 4, "ang": ["20", "30", "60", "25"], "elbow": 1.0},
		{"t": 2, "jc": 4, "ang": ["20", "30", "-60", "25"], "elbow": - 1.0},
	]
	for c in cases:
		var joints: Array = []
		for a in c["ang"]:
			joints.append({"zero": a})
		var home: Array = _cg._forward_kinematics(joints, 100.0, 80.0, 30.0, c["t"], c["jc"])
		var got: Array = _ik(c["t"], c["jc"], home[0], home[1], home[2], home[3],
			100.0, 80.0, 30.0, c["elbow"])
		var want: Array = []
		for a in c["ang"]:
			want.append(a.to_float())
		_test("%d轴 正反解自洽 %s" % [c["jc"], str(c["ang"])], got, want, 0.5)


## joint_frames 的末端点必须与 forward_kinematics_angles 返回的坐标一致，
## 否则 3D 里画出来的臂尖和数值读数会对不上
func _test_frames_consistency() -> void:
	var cases: Array = [
		{"t": 0, "ang": [30.0, 60.0]},
		{"t": 0, "ang": [-45.0, -30.0]},
		{"t": 1, "ang": [20.0, 40.0, 70.0]},
		{"t": 2, "ang": [20.0, 30.0, 60.0, 25.0]},
		{"t": 2, "ang": [-70.0, 10.0, -80.0, 45.0]},
	]
	for c in cases:
		var frames: Array = _cg.joint_frames(c["ang"], 100.0, 80.0, 30.0, c["t"])
		var fk: Array = _cg.forward_kinematics_angles(c["ang"], 100.0, 80.0, 30.0, c["t"])
		var tip: Vector3 = frames[frames.size() - 1]
		# 2 轴构型 z 恒 0，FK 的第三项也是 0
		var got: Array = [tip.x, tip.y, (0.0 if c["t"] == 0 else tip.z)]
		_test("构型%d joint_frames 末端 == FK %s" % [c["t"], str(c["ang"])],
			got, [fk[0], fk[1], fk[2]], 0.01)
		# 连杆段数：2轴=2段(3点)，3轴=2段(3点)，4轴=3段(4点)
		var want_pts: int = 4 if c["t"] >= 2 else 3
		_test("构型%d joint_frames 点数=%d" % [c["t"], want_pts],
			[float(frames.size())], [float(want_pts)], 0.01)
		# 各段长度必须等于对应连杆长度
		var seg_lens: Array = []
		for i in range(1, frames.size()):
			seg_lens.append(frames[i].distance_to(frames[i - 1]))
		var want_lens: Array = [100.0, 80.0]
		if c["t"] >= 2:
			want_lens.append(30.0)
		_test("构型%d 各段长度 == L %s" % [c["t"], str(c["ang"])], seg_lens, want_lens, 0.01)


## solve_ik_checked 必须复现 C 端的半径钳位与 ik_reachable 标志
func _test_checked_reachability() -> void:
	# 2 轴：目标在 [|L1-L2|, L1+L2] 内 -> 可达
	var r1: Dictionary = _cg.solve_ik_checked(150.0, 0.0, 0.0, 0.0, 100.0, 80.0, 0.0, 0, 2, 1.0)
	_test("checked 2轴 (150,0) 可达", [1.0 if r1["reachable"] else 0.0], [1.0])
	# 2 轴：超出外边界 180 -> 不可达，且钳到 r=180 上（θ2=0 完全伸直）
	var r2: Dictionary = _cg.solve_ik_checked(300.0, 0.0, 0.0, 0.0, 100.0, 80.0, 0.0, 0, 2, 1.0)
	_test("checked 2轴 (300,0) 越界 -> reachable=0", [1.0 if r2["reachable"] else 0.0], [0.0])
	_test("checked 2轴 (300,0) 钳位后完全伸直", r2["angles"], [0.0, 0.0], 0.01)
	# 2 轴：落在内边界 |100-80|=20 之内 -> 不可达
	var r3: Dictionary = _cg.solve_ik_checked(5.0, 0.0, 0.0, 0.0, 100.0, 80.0, 0.0, 0, 2, 1.0)
	_test("checked 2轴 (5,0) 内边界 -> reachable=0", [1.0 if r3["reachable"] else 0.0], [0.0])
	# 3 轴：超出外边界，钳位后末端应落在半径 L1+L2 的球面上
	var r4: Dictionary = _cg.solve_ik_checked(400.0, 0.0, 0.0, 0.0, 100.0, 80.0, 0.0, 1, 3, 1.0)
	_test("checked 3轴 (400,0,0) 越界 -> reachable=0", [1.0 if r4["reachable"] else 0.0], [0.0])
	var fk4: Array = _cg.forward_kinematics_angles(r4["angles"], 100.0, 80.0, 0.0, 1)
	_test("checked 3轴 钳位后末端半径 == L1+L2",
		[sqrt(fk4[0] * fk4[0] + fk4[1] * fk4[1] + fk4[2] * fk4[2])], [180.0], 0.01)
	# 3 轴：rz≈0（原点）必须不炸且标记不可达
	var r5: Dictionary = _cg.solve_ik_checked(0.0, 0.0, 0.0, 0.0, 100.0, 80.0, 0.0, 1, 3, 1.0)
	_test("checked 3轴 原点 -> reachable=0", [1.0 if r5["reachable"] else 0.0], [0.0])
	_test("checked 3轴 原点 角度有限（未 NaN）",
		[1.0 if is_finite(r5["angles"][1]) and is_finite(r5["angles"][2]) else 0.0], [1.0])
	# L1==L2 时内边界为 0，原点分支应退到外边界而非 0
	var r6: Dictionary = _cg.solve_ik_checked(0.0, 0.0, 0.0, 0.0, 100.0, 100.0, 0.0, 1, 3, 1.0)
	_test("checked 3轴 等长连杆原点 角度有限",
		[1.0 if is_finite(r6["angles"][1]) and is_finite(r6["angles"][2]) else 0.0], [1.0])
	# 可达范围内 checked 与旧 solve_ik 结果必须一致（钳位分支未触发）
	var r7: Dictionary = _cg.solve_ik_checked(100.0, 0.0, 50.0, 30.0, 100.0, 80.0, 30.0, 2, 4, 1.0)
	var old7: Array = _cg.solve_ik(100.0, 0.0, 50.0, 30.0, 100.0, 80.0, 30.0, 2, 4, 1.0)
	_test("checked 4轴 可达时与 solve_ik 一致", r7["angles"], old7, 0.01)


## clamp_angles_to_limits 必须复现 angle_to_duty 的限位夹紧
func _test_limit_clamp() -> void:
	var joints: Array = [
		{"min": "-30", "max": "30"},
		{"min": "0", "max": "90"},
	]
	var res: Dictionary = _cg.clamp_angles_to_limits([-50.0, 120.0], joints)
	_test("限位钳位 [-50,120] -> [-30,90]", res["angles"], [-30.0, 90.0], 0.01)
	_test("限位钳位标记两项都被钳",
		[1.0 if res["clamped"][0] else 0.0, 1.0 if res["clamped"][1] else 0.0], [1.0, 1.0])
	var res2: Dictionary = _cg.clamp_angles_to_limits([10.0, 45.0], joints)
	_test("限位内不钳位",
		[1.0 if res2["clamped"][0] else 0.0, 1.0 if res2["clamped"][1] else 0.0], [0.0, 0.0])
	# 限位缺失时回退到舵机行程 ±90
	var res3: Dictionary = _cg.clamp_angles_to_limits([-120.0, 150.0], [{}, {}])
	_test("限位缺失回退 ±90", res3["angles"], [-90.0, 90.0], 0.01)

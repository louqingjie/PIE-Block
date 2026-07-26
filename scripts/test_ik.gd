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

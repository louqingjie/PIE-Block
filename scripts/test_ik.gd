extends SceneTree

## 数值核验脚本：验证 IK 公式正确性
## 运行方式：godot --headless --script scripts/test_ik.gd

func _solve_ik_2axis(x: float, y: float, l1: float, l2: float) -> Array:
	var r: float = sqrt(x * x + y * y)
	var c2: float = (r * r - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
	c2 = clamp(c2, -1.0, 1.0)
	var t2: float = acos(c2)
	var t1: float = atan2(y, x) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
	return [rad_to_deg(t1), rad_to_deg(t2)]

func _solve_ik_3axis(x: float, y: float, z: float, l1: float, l2: float) -> Array:
	var t0: float = atan2(y, x)
	var r: float = sqrt(x * x + y * y)
	var c2: float = (r * r + z * z - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
	c2 = clamp(c2, -1.0, 1.0)
	var t2: float = acos(c2)
	var t1: float = atan2(z, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
	return [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2)]

func _solve_ik_4axis(x: float, y: float, z: float, phi: float, l1: float, l2: float) -> Array:
	var t0: float = atan2(y, x)
	var r: float = sqrt(x * x + y * y)
	var c2: float = (r * r + z * z - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
	c2 = clamp(c2, -1.0, 1.0)
	var t2: float = acos(c2)
	var t1: float = atan2(z, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
	var t3: float = deg_to_rad(phi) - (t1 + t2)
	return [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2), rad_to_deg(t3)]

func _approx(a: float, b: float, tol: float = 0.5) -> bool:
	return abs(a - b) < tol

func _test(name: String, actual: Array, expected: Array, tol: float = 0.5) -> bool:
	var ok: bool = true
	for i in range(min(actual.size(), expected.size())):
		if not _approx(actual[i], expected[i], tol):
			ok = false
			break
	var status: String = "✓ PASS" if ok else "✗ FAIL"
	print("[%s] %s" % [status, name])
	if not ok:
		print("  期望: %s" % str(expected))
		print("  实际: %s" % str(actual))
	return ok

func _initialize() -> void:
	print("=== IK 公式数值核验 ===\n")
	var all_pass: bool = true
	# 测试1：2轴，L1=100,L2=100，目标(100,100)
	# r=141.42, θ2=acos(0)=90°, θ1=atan2(100,100)-atan2(100,0)=45-45=0°
	all_pass = _test("2轴 (100,100) -> θ1=0°, θ2=90°",
		_solve_ik_2axis(100, 100, 100, 100), [0.0, 90.0]) and all_pass
	# 测试2：2轴，L1=100,L2=100，目标(200,0)
	# r=200, θ2=acos((40000-20000)/20000)=acos(1)=0°, θ1=atan2(0,200)-atan2(0,200)=0
	all_pass = _test("2轴 (200,0) -> θ1=0°, θ2=0° (完全伸直)",
		_solve_ik_2axis(200, 0, 100, 100), [0.0, 0.0]) and all_pass
	# 测试3：2轴，L1=100,L2=100，目标(0,200)
	# r=200, θ2=0°, θ1=atan2(200,0)-atan2(0,200)=90°-0°=90°
	all_pass = _test("2轴 (0,200) -> θ1=90°, θ2=0°",
		_solve_ik_2axis(0, 200, 100, 100), [90.0, 0.0]) and all_pass
	# 测试4：2轴，L1=100,L2=50，目标(100,0)
	# r=100, θ2=acos((10000-10000-2500)/(2*100*50))=acos(-0.25)=104.48°
	# θ1=atan2(0,100)-atan2(50*sin(104.48°),100+50*cos(104.48°))=0-atan2(48.4,87.5)=0-28.96°=-28.96°
	var t4: Array = _solve_ik_2axis(100, 0, 100, 50)
	all_pass = _test("2轴 L1=100,L2=50 (100,0) -> θ1≈-28.96°, θ2≈104.48°",
		t4, [-28.96, 104.48], 1.0) and all_pass
	# 测试5：3轴，L1=100,L2=100，目标(100,0,100)
	# θ0=atan2(0,100)=0°, r=100, θ2=acos((10000+10000-20000)/20000)=acos(0)=90°
	# θ1=atan2(100,100)-atan2(100,100)=45°-45°=0°
	all_pass = _test("3轴 (100,0,100) -> θ0=0°, θ1=0°, θ2=90°",
		_solve_ik_3axis(100, 0, 100, 100, 100), [0.0, 0.0, 90.0]) and all_pass
	# 测试6：3轴，L1=100,L2=100，目标(0,100,0)
	# θ0=atan2(100,0)=90°, r=100, c2=(10000+0-20000)/20000=-0.5
	# θ2=acos(-0.5)=120°, θ1=atan2(0,100)-atan2(100*sin120°,100+100*cos120°)=0-60°=-60°
	all_pass = _test("3轴 (0,100,0) -> θ0=90°, θ1=-60°, θ2=120°",
		_solve_ik_3axis(0, 100, 0, 100, 100), [90.0, -60.0, 120.0], 1.0) and all_pass
	# 测试7：4轴，L1=100,L2=100，目标(100,0,0), φ=90°
	# θ0=0°, θ2=acos((10000-20000)/20000)=acos(-0.5)=120°
	# θ1=atan2(0,100)-atan2(100*sin120°,100+100*cos120°)=0-atan2(86.6,50)=0-60°=-60°
	# θ3 = φ - (θ1+θ2) = 90° - (-60°+120°) = 90°-60° = 30°
	all_pass = _test("4轴 (100,0,0,φ=90°) -> θ0=0°, θ1=-60°, θ2=120°, θ3=30°",
		_solve_ik_4axis(100, 0, 0, 90, 100, 100), [0.0, -60.0, 120.0, 30.0], 1.0) and all_pass
	# 测试8：可达性边界 -- 目标超出 L1+L2
	# L1=100,L2=100, 目标(300,0)，r=300 > 200，应钳到 r=200
	# 钳后：θ2=acos((40000-20000)/20000)=acos(1)=0°, θ1=0°
	var t8: Array = _solve_ik_2axis(300, 0, 100, 100)
	all_pass = _test("2轴 越界 (300,0) -> 钳到 θ1=0°, θ2=0°",
		t8, [0.0, 0.0], 1.0) and all_pass
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if all_pass else "存在失败 ✗"))
	quit(0 if all_pass else 1)

extends SceneTree

## 通用正运动学（fk_chain）验证脚本。
## 核心是「退化验证」：轴类型按历史构型填写时，fk_chain 的末端必须与
## 现有 forward_kinematics_angles 逐位一致——这是保证不回归的关键断言。
## 运行方式：godot --headless --path . --script scripts/test_fk_chain.gd

var _cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _near(a: float, b: float, tol: float = 1e-4) -> bool:
	return abs(a - b) < tol


func _initialize() -> void:
	print("=== 通用正运动学 fk_chain 验证 ===\n")
	_test_axis_defaults()
	_test_length_defaults()
	_test_degeneracy()
	_test_roll_no_position_change()
	_test_yaw_swings_horizontally()
	_test_pitch_lifts()
	_test_axes_are_unit()
	_test_chain_segment_lengths()
	_test_up_to_max_joints()
	_test_legacy_link_lengths()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


## 未填 axis 时须按历史构型推断
func _test_axis_defaults() -> void:
	var blank: Array = [ {}, {}, {}, {}]
	_check("2轴默认轴 = [Yaw, Yaw]",
		_cg.joint_axes(blank, 2, 0) == ["Yaw", "Yaw"],
		str(_cg.joint_axes(blank, 2, 0)))
	_check("3轴默认轴 = [Yaw, Pitch, Pitch]",
		_cg.joint_axes(blank, 3, 1) == ["Yaw", "Pitch", "Pitch"],
		str(_cg.joint_axes(blank, 3, 1)))
	_check("4轴默认轴 = [Yaw, Pitch, Pitch, Pitch]",
		_cg.joint_axes(blank, 4, 2) == ["Yaw", "Pitch", "Pitch", "Pitch"],
		str(_cg.joint_axes(blank, 4, 2)))
	# 显式指定应覆盖推断
	var custom: Array = [ {"axis": "Roll"}, {"axis": "Yaw"}, {"axis": "Pitch"}]
	_check("显式 axis 覆盖默认",
		_cg.joint_axes(custom, 3, 1) == ["Roll", "Yaw", "Pitch"],
		str(_cg.joint_axes(custom, 3, 1)))
	# 非法值回退到推断，不应崩
	var bad: Array = [ {"axis": "香蕉"}, {"axis": ""}]
	_check("非法 axis 回退到推断",
		_cg.joint_axes(bad, 2, 0) == ["Yaw", "Yaw"],
		str(_cg.joint_axes(bad, 2, 0)))


## 未填 len 时须回退到 L1/L2/L3
func _test_length_defaults() -> void:
	var blank: Array = [ {}, {}, {}, {}]
	# 2 轴：每个关节后都有连杆
	_check("2轴默认连杆 = [L1, L2]",
		_cg.joint_lengths(blank, 2, 0, 100.0, 80.0, 30.0) == [100.0, 80.0],
		str(_cg.joint_lengths(blank, 2, 0, 100.0, 80.0, 30.0)))
	# 3/4 轴：底座 Yaw 与肩部 Pitch 同位，之间无连杆
	_check("3轴默认连杆 = [0, L1, L2]",
		_cg.joint_lengths(blank, 3, 1, 100.0, 80.0, 30.0) == [0.0, 100.0, 80.0],
		str(_cg.joint_lengths(blank, 3, 1, 100.0, 80.0, 30.0)))
	_check("4轴默认连杆 = [0, L1, L2, L3]",
		_cg.joint_lengths(blank, 4, 2, 100.0, 80.0, 30.0) == [0.0, 100.0, 80.0, 30.0],
		str(_cg.joint_lengths(blank, 4, 2, 100.0, 80.0, 30.0)))
	# 显式 len 覆盖
	var custom: Array = [ {"len": "11"}, {"len": "22"}]
	_check("显式 len 覆盖默认",
		_cg.joint_lengths(custom, 2, 0, 100.0, 80.0, 30.0) == [11.0, 22.0],
		str(_cg.joint_lengths(custom, 2, 0, 100.0, 80.0, 30.0)))


## 【核心】退化验证：老构型下 fk_chain 末端必须与现有 FK 逐位一致
func _test_degeneracy() -> void:
	var blank: Array = [ {}, {}, {}, {}]
	var cases: Array = [
		{"t": 0, "jc": 2, "ang": [0.0, 0.0]},
		{"t": 0, "jc": 2, "ang": [30.0, 60.0]},
		{"t": 0, "jc": 2, "ang": [-45.0, -30.0]},
		{"t": 0, "jc": 2, "ang": [90.0, -90.0]},
		{"t": 1, "jc": 3, "ang": [0.0, 0.0, 0.0]},
		{"t": 1, "jc": 3, "ang": [20.0, 40.0, 70.0]},
		{"t": 1, "jc": 3, "ang": [-70.0, 15.0, -50.0]},
		{"t": 1, "jc": 3, "ang": [90.0, -60.0, 120.0]},
		{"t": 2, "jc": 4, "ang": [0.0, 0.0, 0.0, 0.0]},
		{"t": 2, "jc": 4, "ang": [20.0, 30.0, 60.0, 25.0]},
		{"t": 2, "jc": 4, "ang": [-70.0, 10.0, -80.0, 45.0]},
		{"t": 2, "jc": 4, "ang": [45.0, -45.0, 90.0, -30.0]},
	]
	for c in cases:
		var t: int = c["t"]
		var jc: int = c["jc"]
		var ang: Array = c["ang"]
		var old_fk: Array = _cg.forward_kinematics_angles(ang, 100.0, 80.0, 30.0, t)
		var chain: Dictionary = _cg.fk_chain(ang, blank, jc, t, 100.0, 80.0, 30.0)
		var pts: Array = chain["points"]
		var tip: Vector3 = pts[pts.size() - 1]
		# 2 轴构型旧 FK 的第三项恒为 0（工作平面内），其余构型比对完整三维
		var ok: bool = _near(tip.x, old_fk[0]) and _near(tip.y, old_fk[1])
		if t != 0:
			ok = ok and _near(tip.z, old_fk[2])
		else:
			ok = ok and _near(tip.z, 0.0)
		_check("退化 构型%d %s 末端与旧 FK 一致" % [t, str(ang)], ok,
			"fk_chain=%s 旧FK=[%.4f, %.4f, %.4f]"
				% [str(tip), old_fk[0], old_fk[1], old_fk[2]])


## Roll 是绕连杆自身轴自转，不应改变末端位置
func _test_roll_no_position_change() -> void:
	# 单个 Roll 关节：无论转多少度，末端都在 +X 方向 len 处
	var joints: Array = [ {"axis": "Roll", "len": "100"}]
	var base: Vector3 = _cg.fk_chain([0.0], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
	for a in [30.0, 90.0, 180.0, -60.0]:
		var p: Vector3 = _cg.fk_chain([a], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
		_check("Roll %.0f° 不改变末端位置" % a, p.distance_to(base) < 1e-4,
			"实际 %s 期望 %s" % [str(p), str(base)])
	# Roll 在链中间：它会改变后续关节的转轴朝向，但自身不移动末端。
	# Roll=0 与 Roll=90 时，若后续是 Pitch，末端位置应当不同（证明 Roll 有效）
	var chain2: Array = [ {"axis": "Roll", "len": "0"}, {"axis": "Pitch", "len": "100"}]
	var p0: Vector3 = _cg.fk_chain([0.0, 45.0], chain2, 2, 1, 0.0, 0.0, 0.0)["points"][2]
	var p90: Vector3 = _cg.fk_chain([90.0, 45.0], chain2, 2, 1, 0.0, 0.0, 0.0)["points"][2]
	_check("Roll 改变后续关节的转动平面", p0.distance_to(p90) > 1.0,
		"Roll=0 -> %s, Roll=90 -> %s" % [str(p0), str(p90)])


## Yaw 绕竖直轴转，末端应在水平面内画圆（高度不变）
func _test_yaw_swings_horizontally() -> void:
	var joints: Array = [ {"axis": "Yaw", "len": "100"}]
	for a in [0.0, 45.0, 90.0, 180.0]:
		var p: Vector3 = _cg.fk_chain([a], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
		_check("Yaw %.0f° 高度不变" % a, _near(p.z, 0.0),
			"z=%.4f" % p.z)
		_check("Yaw %.0f° 水平半径为连杆长" % a, _near(sqrt(p.x * p.x + p.y * p.y), 100.0),
			"r=%.4f" % sqrt(p.x * p.x + p.y * p.y))
	# 90° 时应指向 +Y
	var p90: Vector3 = _cg.fk_chain([90.0], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
	_check("Yaw 90° 指向 +Y", _near(p90.x, 0.0) and _near(p90.y, 100.0), str(p90))


## Pitch 绕水平轴转，正角度应抬升末端（与历史构型一致）
func _test_pitch_lifts() -> void:
	var joints: Array = [ {"axis": "Pitch", "len": "100"}]
	var p90: Vector3 = _cg.fk_chain([90.0], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
	_check("Pitch +90° 末端朝上", _near(p90.z, 100.0), "z=%.4f（应为 +100）" % p90.z)
	var p45: Vector3 = _cg.fk_chain([45.0], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
	_check("Pitch +45° 抬升", p45.z > 0.0 and _near(p45.z, 70.7107, 0.01),
		"z=%.4f" % p45.z)
	var pn45: Vector3 = _cg.fk_chain([-45.0], joints, 1, 1, 0.0, 0.0, 0.0)["points"][1]
	_check("Pitch -45° 下压", pn45.z < 0.0, "z=%.4f" % pn45.z)


## 转轴必须是单位向量（雅可比依赖这点）
func _test_axes_are_unit() -> void:
	var joints: Array = [
		{"axis": "Yaw", "len": "0"}, {"axis": "Pitch", "len": "100"},
		{"axis": "Roll", "len": "50"}, {"axis": "Pitch", "len": "30"},
	]
	var chain: Dictionary = _cg.fk_chain([20.0, 35.0, 60.0, -20.0], joints, 4, 2,
		0.0, 0.0, 0.0)
	var axes: Array = chain["axes"]
	_check("转轴数量 == 关节数", axes.size() == 4, "实际 %d" % axes.size())
	var all_unit: bool = true
	for ax in axes:
		if abs(ax.length() - 1.0) > 1e-5:
			all_unit = false
	_check("所有转轴均为单位向量", all_unit, str(axes))
	# 点数 = 关节数 + 1
	_check("点数 == 关节数+1", chain["points"].size() == 5,
		"实际 %d" % chain["points"].size())
	# 末端姿态必须是正交基
	var tb: Basis = chain["tip_basis"]
	_check("末端姿态是正交基",
		abs(tb.x.dot(tb.y)) < 1e-5 and abs(tb.y.dot(tb.z)) < 1e-5
			and abs(tb.x.length() - 1.0) < 1e-5)


## 逐关节 len -> L1/L2/L3 的折算。
## 配置界面已删掉全局 L1/L2/L3，若下游仍读 cfg["L1"] 就会拿不到值、
## 静默回退到默认 100mm——用户填的长度不生效。这组断言守住这条链路。
func _test_legacy_link_lengths() -> void:
	# 2 关节：两段直接对应 L1/L2
	var c2: Dictionary = {"joint_count": 2, "joints": [
		{"len": "150"}, {"len": "90"}]}
	_check("折算 2关节 -> [150, 90, 0]",
		_cg.legacy_link_lengths(c2) == [150.0, 90.0, 0.0],
		str(_cg.legacy_link_lengths(c2)))
	# 3 关节：跳过底座那段（len[0]=0）
	var c3: Dictionary = {"joint_count": 3, "joints": [
		{"len": "0"}, {"len": "120"}, {"len": "80"}]}
	_check("折算 3关节 -> [120, 80, 0]",
		_cg.legacy_link_lengths(c3) == [120.0, 80.0, 0.0],
		str(_cg.legacy_link_lengths(c3)))
	# 4 关节：多一段腕部
	var c4: Dictionary = {"joint_count": 4, "joints": [
		{"len": "0"}, {"len": "120"}, {"len": "90"}, {"len": "40"}]}
	_check("折算 4关节 -> [120, 90, 40]",
		_cg.legacy_link_lengths(c4) == [120.0, 90.0, 40.0],
		str(_cg.legacy_link_lengths(c4)))
	# 与 joint_lengths 互为逆运算：折算出的 L 再喂回去应还原原始 len
	var packed: Array = _cg.legacy_link_lengths(c4)
	var back: Array = _cg.joint_lengths([ {}, {}, {}, {}], 4, 2,
		packed[0], packed[1], packed[2])
	_check("折算与 joint_lengths 互逆", back == [0.0, 120.0, 90.0, 40.0], str(back))
	# 一个 len 都没填时回退到旧的 L1/L2/L3 字段（保证老项目文件仍能打开）
	var old: Dictionary = {"joint_count": 3, "joints": [ {}, {}, {}],
		"L1": "111", "L2": "77", "L3": "22"}
	_check("无 len 时回退旧 L1/L2/L3",
		_cg.legacy_link_lengths(old) == [111.0, 77.0, 22.0],
		str(_cg.legacy_link_lengths(old)))
	# 两者都没有时给出可用默认值，不能返回 0（会导致余弦定理除零）
	var empty: Dictionary = {"joint_count": 3, "joints": [ {}, {}, {}]}
	var e: Array = _cg.legacy_link_lengths(empty)
	_check("全空时 L1/L2 为正", e[0] > 0.0 and e[1] > 0.0, str(e))
	# 6 关节：旧路径只取前几段，但不能崩
	var c6: Dictionary = {"joint_count": 6, "joints": [
		{"len": "0"}, {"len": "100"}, {"len": "80"}, {"len": "0"},
		{"len": "40"}, {"len": "25"}]}
	var r6: Array = _cg.legacy_link_lengths(c6)
	_check("折算 6关节 不崩且 L1/L2 为正",
		r6.size() == 3 and r6[0] > 0.0 and r6[1] > 0.0, str(r6))
	# generate() 必须真的用上逐关节 len。
	# 连杆长度现在由 jointLen[] 表提供（L1/L2/L3 宏已随旧解析解一起删除），
	# 故改断言这张表的内容会跟着 len 变。
	var cfg_a: Dictionary = _mk_gen_cfg(150.0)
	var cfg_b: Dictionary = _mk_gen_cfg(220.0)
	var code_a: String = _cg.generate(cfg_a)
	var code_b: String = _cg.generate(cfg_b)
	_check("generate 使用逐关节 len（150 进 jointLen）",
		code_a.contains("150.00f") and code_a.contains("const float jointLen["),
		"jointLen 表里没有 150")
	_check("generate 使用逐关节 len（220 进 jointLen）",
		code_b.contains("220.00f") and not code_b.contains("150.00f"),
		"jointLen 表未跟着改")


## 构造一份最小可生成的 3 轴配置，第 2 关节连杆长度为 first_len
func _mk_gen_cfg(first_len: float) -> Dictionary:
	return {
		"joint_count": 3, "config_type": 1,
		"joints": [
			{"io": "P74", "dir": "正向", "axis": "Yaw", "len": "0",
				"zero": "0", "min": "-90", "max": "90"},
			{"io": "P75", "dir": "正向", "axis": "Pitch", "len": "%.2f" % first_len,
				"zero": "20", "min": "-90", "max": "90"},
			{"io": "P76", "dir": "正向", "axis": "Pitch", "len": "80",
				"zero": "30", "min": "-90", "max": "90"},
		],
		"presets": [],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "5", "keymove_speed": "2", "keymove": [],
	}


## 5/6 关节（超出旧解析路径的 4 关节上限）必须正常工作。
## 旧代码里 _pad_angles / _joint_home_angles 硬编码了 4，多出来的关节会被静默丢弃。
func _test_up_to_max_joints() -> void:
	_check("MAX_JOINTS == 6", _cg.MAX_JOINTS == 6, "实际 %d" % _cg.MAX_JOINTS)
	for jc in [5, 6]:
		var axes: Array = []
		var lens: Array = []
		var joints: Array = []
		var ang: Array = []
		for i in range(jc):
			# 交替轴向，构造一个真正三维的臂
			var ax: String = ["Yaw", "Pitch", "Roll"][i % 3]
			axes.append(ax)
			lens.append(60.0 - i * 5.0)
			joints.append({"axis": ax, "len": str(60.0 - i * 5.0),
				"zero": str(10.0 + i * 5.0)})
			ang.append(10.0 + i * 5.0)
		var chain: Dictionary = _cg.fk_chain(ang, joints, jc, 2, 0.0, 0.0, 0.0)
		_check("%d 关节 点数 == jc+1" % jc, chain["points"].size() == jc + 1,
			"实际 %d" % chain["points"].size())
		_check("%d 关节 转轴数 == jc" % jc, chain["axes"].size() == jc,
			"实际 %d" % chain["axes"].size())
		# 各段长度必须与配置一致（证明没有关节被丢弃）
		var pts: Array = chain["points"]
		var ok_len: bool = true
		for i in range(jc):
			if not _near(pts[i + 1].distance_to(pts[i]), lens[i], 1e-3):
				ok_len = false
		_check("%d 关节 各段长度正确" % jc, ok_len)
		# 末端不应退化到原点，也不应出现 NaN
		var tip: Vector3 = pts[jc]
		_check("%d 关节 末端有效" % jc,
			tip.length() > 1.0 and is_finite(tip.x) and is_finite(tip.y)
				and is_finite(tip.z), str(tip))
		# 初始角提取不得截断：第 jc-1 个关节的初始角必须被读到
		var home: Array = _cg._joint_home_angles(joints)
		_check("%d 关节 初始角不被截断" % jc, home.size() >= jc,
			"home 长度 %d" % home.size())
		_check("%d 关节 末关节初始角正确" % jc,
			_near(float(home[jc - 1]), 10.0 + (jc - 1) * 5.0),
			"实际 %.2f 期望 %.2f" % [float(home[jc - 1]), 10.0 + (jc - 1) * 5.0])


## 各段长度必须等于配置的连杆长度（与转角无关）
func _test_chain_segment_lengths() -> void:
	var joints: Array = [
		{"axis": "Yaw", "len": "0"}, {"axis": "Pitch", "len": "120"},
		{"axis": "Roll", "len": "90"}, {"axis": "Pitch", "len": "40"},
	]
	var want: Array = [0.0, 120.0, 90.0, 40.0]
	for ang in [[0.0, 0.0, 0.0, 0.0], [20.0, 35.0, 60.0, -20.0],
			[-80.0, 70.0, -120.0, 45.0]]:
		var pts: Array = _cg.fk_chain(ang, joints, 4, 2, 0.0, 0.0, 0.0)["points"]
		var ok: bool = true
		for i in range(4):
			if not _near(pts[i + 1].distance_to(pts[i]), want[i], 1e-3):
				ok = false
		_check("各段长度 == 配置值 %s" % str(ang), ok)

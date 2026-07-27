extends SceneTree

## 构形诊断验证：故意构造病态构形，断言能报出对应问题。
## 运行方式：godot --headless --path . --script scripts/test_arm_diagnosis.gd

var _diag = preload("res://scripts/arm_diagnosis.gd").new()
var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


## 构造关节配置：axes 与 lens 一一对应
func _mk(axes: Array, lens: Array) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({"axis": axes[i], "len": str(lens[i]),
			"zero": "0", "min": "-90", "max": "90"})
	return out


## 诊断结果里是否含指定类型、且消息包含关键词的条目
func _has(res: Dictionary, type: String, keyword: String) -> bool:
	for it in res["issues"]:
		if str(it["type"]) == type and str(it["msg"]).contains(keyword):
			return true
	return false


func _dump(res: Dictionary) -> String:
	var parts: Array = ["dof=%d" % res["dof"]]
	for it in res["issues"]:
		parts.append("[%s] %s" % [it["type"], it["msg"]])
	return "\n      ".join(parts)


func _initialize() -> void:
	print("=== 机械臂构形诊断验证 ===\n")
	_test_healthy()
	_test_all_zero_length()
	_test_all_roll()
	_test_all_same_axis()
	_test_planar_arm_missing_yaw()
	_test_tip_roll_is_ok()
	_test_useless_middle_joint()
	_test_legacy_configs_are_healthy()
	_test_six_joints()
	_test_pitch_decoupled()
	_test_pitch_nullspace_proof()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


## 末端俯仰角能否在不移动末端位置的前提下单独调
func _test_pitch_decoupled() -> void:
	# 4 关节 Yaw + 3 Pitch：位置 3 自由度 + 俯仰角，正好够，应判可控
	var ok4: Array = _mk(["Yaw", "Pitch", "Pitch", "Pitch"], [0, 120, 90, 40])
	var r4: Dictionary = _diag.analyze(ok4, 4, 2, 0.0, 0.0, 0.0)
	_check("4关节 Yaw+3Pitch 俯仰角可控", r4["pitch_dof"] == true, _dump(r4))
	_check("4关节 可控时给 Info", _has(r4, "Info", "俯仰角可以单独调"), _dump(r4))
	# 恰好够用但无余量，应额外提示
	_check("4关节 提示无余量", _has(r4, "Info", "没有余量"), _dump(r4))
	# 3 关节：全部用于控位置，俯仰角必然被绑死
	var only3: Array = _mk(["Yaw", "Pitch", "Pitch"], [0, 120, 90])
	var r3: Dictionary = _diag.analyze(only3, 3, 1, 0.0, 0.0, 0.0)
	_check("3关节 俯仰角不可控", r3["pitch_dof"] == false, _dump(r3))
	_check("3关节 理由是关节数不足",
		str(r3["pitch_reason"]).contains("只有 3 个关节"), str(r3["pitch_reason"]))
	_check("3关节 报 Warn 说明原因", _has(r3, "Warn", "至少需要 4 个关节"), _dump(r3))
	# 5 关节有余量，同样可控
	var ok5: Array = _mk(["Yaw", "Pitch", "Pitch", "Pitch", "Pitch"],
		[0, 120, 90, 50, 30])
	var r5: Dictionary = _diag.analyze(ok5, 5, 2, 0.0, 0.0, 0.0)
	_check("5关节 俯仰角可控", r5["pitch_dof"] == true, _dump(r5))
	_check("5关节 不提无余量", not _has(r5, "Info", "没有余量"), _dump(r5))
	# 末端动不了时不该再唠叨俯仰角，先修位置
	var dead: Array = _mk(["Roll", "Roll", "Roll"], [50, 50, 50])
	var rd: Dictionary = _diag.analyze(dead, 3, 1, 0.0, 0.0, 0.0)
	_check("末端不可动时俯仰角不可控", rd["pitch_dof"] == false, _dump(rd))
	_check("末端不可动时不提俯仰角",
		not _has(rd, "Warn", "俯仰角") and not _has(rd, "Info", "俯仰角"), _dump(rd))
	# 4 关节全 Pitch：位置只有 2 自由度，属于「先修位置」那一档
	var flat: Array = _mk(["Pitch", "Pitch", "Pitch", "Pitch"], [100, 80, 60, 40])
	var rf: Dictionary = _diag.analyze(flat, 4, 2, 0.0, 0.0, 0.0)
	_check("4关节全Pitch 位置未满秩", rf["dof"] == 2, _dump(rf))
	_check("4关节全Pitch 理由指向位置",
		str(rf["pitch_reason"]).contains("自由移动"), str(rf["pitch_reason"]))


## 数值反证：秩判定说「可控」，就必须真能构造出
## 「位置不动、俯仰角变化」的关节速度。
## 这条比秩判定更硬——秩阈值取错时秩判定会说谎，这里不会。
func _test_pitch_nullspace_proof() -> void:
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	var cases: Array = [
		{"axes": ["Yaw", "Pitch", "Pitch", "Pitch"], "lens": [0, 120, 90, 40],
			"tag": "4关节 Yaw+3Pitch"},
		{"axes": ["Yaw", "Pitch", "Pitch", "Pitch", "Pitch"],
			"lens": [0, 120, 90, 50, 30], "tag": "5关节"},
	]
	for c in cases:
		var joints: Array = _mk(c["axes"], c["lens"])
		var jc: int = (c["axes"] as Array).size()
		var res: Dictionary = _diag.analyze(joints, jc, 2, 0.0, 0.0, 0.0)
		if not res["pitch_dof"]:
			_check("%s 判定可控（反证前提）" % c["tag"], false, _dump(res))
			continue
		# 在初始姿态上构造零空间方向
		var angles: Array = []
		for i in range(jc):
			angles.append(0.0)
		# 用一个非奇异姿态：全零时多轴共线，反证会落在退化点上
		for i in range(jc):
			angles[i] = [15.0, 25.0, -20.0, 30.0, 10.0][i % 5]
		var chain: Dictionary = cg.fk_chain(angles, joints, jc, 2, 0.0, 0.0, 0.0)
		var g: Array = _diag._pitch_gradient(chain, jc)
		if g.is_empty():
			_check("%s 该姿态 φ 非退化" % c["tag"], false, "梯度为空")
			continue
		# q̇ = g 在 J_v 行空间上的正交补分量。
		# 它天然满足 J_v q̇ = 0（正交于每一行），且 g·q̇ = |q̇|² > 0
		var cols: Array = _diag._jacobian_columns(chain, jc)
		var rows: Array = [[], [], []]
		for i in range(jc):
			var col: Vector3 = cols[i]
			rows[0].append(col.x)
			rows[1].append(col.y)
			rows[2].append(col.z)
		var basis: Array = _diag._orthonormal_basis(rows, _diag.SINGULAR_EPS)
		var qd: Array = g.duplicate()
		for b in basis:
			qd = _diag._vsub_scaled(qd, b, _diag._vdot(qd, b))
		var qd_len: float = _diag._vlen(qd)
		# GDScript 的 % 格式化不支持 %e，用 %.9f（否则断言失败时 detail 自己先崩）
		_check("%s 零空间方向非零" % c["tag"], qd_len > 1e-6, "|q̇|=%.9f" % qd_len)
		# 末端线速度 J_v q̇ 必须为零
		var vel: Vector3 = Vector3.ZERO
		for i in range(jc):
			vel += (cols[i] as Vector3) * float(qd[i])
		# 归一化后再比：|q̇| 本身量级不定
		var vel_rel: float = vel.length() / maxf(qd_len, 1e-12)
		_check("%s 该方向末端位置不动" % c["tag"], vel_rel < 1e-4,
			"|J_v q̇|/|q̇| = %.9f" % vel_rel)
		# 而俯仰角必须真的在变
		var dphi: float = _diag._vdot(g, qd) / maxf(qd_len, 1e-12)
		_check("%s 该方向俯仰角在变" % c["tag"], absf(dphi) > 1e-6,
			"dφ/dt = %.9f" % dphi)


## 健康构形：Yaw + 两个 Pitch，末端可在三维空间移动
func _test_healthy() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch"], [0, 120, 90])
	var r: Dictionary = _diag.analyze(j, 3, 1, 0.0, 0.0, 0.0)
	_check("健康 3 轴臂 dof == 3", r["dof"] == 3, _dump(r))
	_check("健康 3 轴臂 无 Error", not _has(r, "Error", ""), _dump(r))
	_check("健康 3 轴臂 无锁死方向", (r["locked"] as Array).is_empty(), _dump(r))


## 所有连杆长度为 0：末端恒在原点
func _test_all_zero_length() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch"], [0, 0, 0])
	var r: Dictionary = _diag.analyze(j, 3, 1, 0.0, 0.0, 0.0)
	_check("全零连杆 报 Error", _has(r, "Error", "连杆长度都是 0"), _dump(r))
	_check("全零连杆 dof == 0", r["dof"] == 0, _dump(r))


## 全 Roll：绕自身轴自转，末端无法移动
func _test_all_roll() -> void:
	var j: Array = _mk(["Roll", "Roll", "Roll"], [50, 50, 50])
	var r: Dictionary = _diag.analyze(j, 3, 1, 0.0, 0.0, 0.0)
	_check("全 Roll 报 Error", _has(r, "Error", "Roll"), _dump(r))
	_check("全 Roll dof == 0", r["dof"] == 0, _dump(r))
	# 末端根本动不了时，不应再说「关节3 的作用是转动夹爪朝向，这是正常的」
	_check("全 Roll 不输出误导的 Info",
		not _has(r, "Info", "这是正常的"), _dump(r))
	# 只给一条根因，不要逐关节刷 Warn
	_check("全 Roll 只报一条问题", (r["issues"] as Array).size() == 1,
		"共 %d 条\n      %s" % [(r["issues"] as Array).size(), _dump(r)])


## 全同轴（都是 Pitch）：转轴互相平行，末端只能在一个平面内动
func _test_all_same_axis() -> void:
	var j: Array = _mk(["Pitch", "Pitch", "Pitch"], [100, 80, 60])
	var r: Dictionary = _diag.analyze(j, 3, 1, 0.0, 0.0, 0.0)
	_check("全 Pitch 提示转轴平行", _has(r, "Warn", "转轴互相平行"), _dump(r))
	_check("全 Pitch dof == 2（平面内）", r["dof"] == 2, _dump(r))
	# 同一个毛病只说一次：不应既报「只能在曲面内」又单独报「无法沿 Y 移动」
	var warn_count: int = 0
	for it in r["issues"]:
		if str(it["type"]) == "Warn":
			warn_count += 1
	_check("全 Pitch 不重复报警（Warn 数 == 1）", warn_count == 1,
		"Warn 数 %d\n      %s" % [warn_count, _dump(r)])


## 缺 Yaw 的平面臂：末端无法左右移动
func _test_planar_arm_missing_yaw() -> void:
	var j: Array = _mk(["Pitch", "Pitch"], [120, 90])
	var r: Dictionary = _diag.analyze(j, 2, 1, 0.0, 0.0, 0.0)
	_check("缺 Yaw dof == 2", r["dof"] == 2, _dump(r))
	# Pitch 绕 -Y 转，末端在 XZ 平面内动，故 Y（左右）锁死
	var locked: Array = r["locked"]
	_check("缺 Yaw 报出 Y 方向锁死",
		locked.size() == 1 and str(locked[0]).contains("Y"), _dump(r))
	_check("缺 Yaw 有方向锁死警告", _has(r, "Warn", "无法沿"), _dump(r))


## 末端 Roll 是正常设计（夹爪自转），应给 Info 而非 Warn
func _test_tip_roll_is_ok() -> void:
	var j: Array = _mk(["Yaw", "Pitch", "Pitch", "Roll"], [0, 120, 90, 40])
	var r: Dictionary = _diag.analyze(j, 4, 2, 0.0, 0.0, 0.0)
	_check("末端 Roll 给 Info 而非 Warn",
		_has(r, "Info", "转动夹爪朝向"), _dump(r))
	_check("末端 Roll 不报 Warn 说它装错",
		not _has(r, "Warn", "转轴方向是否装错"), _dump(r))
	_check("末端 Roll 仍保有 dof 3", r["dof"] == 3, _dump(r))


## 中间关节之后连杆为 0 且轴向无效：应报「对定位没有贡献」
func _test_useless_middle_joint() -> void:
	# 关节2 是 Roll 且它之后的连杆与它共线，转动不改变末端位置
	var j: Array = _mk(["Yaw", "Roll", "Pitch"], [0, 0, 100])
	var r: Dictionary = _diag.analyze(j, 3, 1, 0.0, 0.0, 0.0)
	# 这个构形里 Roll 会改变后续 Pitch 的转动平面，故它其实有用；
	# 只断言诊断不崩、给出合理 dof
	_check("含中间 Roll 的构形能诊断", r["dof"] >= 1, _dump(r))
	_check("含中间 Roll 无 NaN", str(r["dof"]) != "nan", _dump(r))


## 6 关节（算力上限）的诊断必须正常工作，不能因关节数多而崩或误报
func _test_six_joints() -> void:
	# 典型 6 轴臂：Yaw + Pitch + Pitch + Roll + Pitch + Roll
	var j: Array = _mk(["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"],
		[0, 120, 90, 0, 40, 25])
	var r: Dictionary = _diag.analyze(j, 6, 2, 0.0, 0.0, 0.0)
	_check("6 关节臂 dof == 3", r["dof"] == 3, _dump(r))
	_check("6 关节臂 无 Error", not _has(r, "Error", ""), _dump(r))
	_check("6 关节臂 无锁死方向", (r["locked"] as Array).is_empty(), _dump(r))
	# 末端 Roll 应被识别为正常设计
	_check("6 关节臂 末端 Roll 给 Info", _has(r, "Info", "转动夹爪朝向"), _dump(r))
	# 病态 6 关节：全 Pitch，仍应只报一条平面内运动
	var flat: Array = _mk(["Pitch", "Pitch", "Pitch", "Pitch", "Pitch", "Pitch"],
		[50, 50, 50, 50, 50, 50])
	var rf: Dictionary = _diag.analyze(flat, 6, 2, 0.0, 0.0, 0.0)
	_check("6 关节全 Pitch dof == 2", rf["dof"] == 2, _dump(rf))
	var warns: int = 0
	for it in rf["issues"]:
		if str(it["type"]) == "Warn":
			warns += 1
	_check("6 关节全 Pitch 只报一条 Warn", warns == 1,
		"Warn 数 %d\n      %s" % [warns, _dump(rf)])


## 历史构型（axis/len 全部留空）必须被判为健康，否则老用户一进来就看到报错
func _test_legacy_configs_are_healthy() -> void:
	var blank: Array = [ {"zero": "0"}, {"zero": "0"}, {"zero": "0"}, {"zero": "0"}]
	# 3 轴：Yaw + 2 Pitch，健康
	var r3: Dictionary = _diag.analyze(blank, 3, 1, 100.0, 80.0, 30.0)
	_check("历史 3 轴构型 dof == 3", r3["dof"] == 3, _dump(r3))
	_check("历史 3 轴构型 无 Error", not _has(r3, "Error", ""), _dump(r3))
	# 4 轴：Yaw + 3 Pitch，仍然是 3 自由度（三个 Pitch 平行，冗余一个）
	var r4: Dictionary = _diag.analyze(blank, 4, 2, 100.0, 80.0, 30.0)
	_check("历史 4 轴构型 dof == 3", r4["dof"] == 3, _dump(r4))
	_check("历史 4 轴构型 无 Error", not _has(r4, "Error", ""), _dump(r4))
	# 2 轴：两个 Yaw 同轴，末端只能在水平面内动
	var r2: Dictionary = _diag.analyze(blank, 2, 0, 100.0, 80.0, 30.0)
	_check("历史 2 轴构型 dof == 2", r2["dof"] == 2, _dump(r2))
	_check("历史 2 轴构型 无 Error", not _has(r2, "Error", ""), _dump(r2))

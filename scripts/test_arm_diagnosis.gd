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
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


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
	var blank: Array = [{"zero": "0"}, {"zero": "0"}, {"zero": "0"}, {"zero": "0"}]
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

extends SceneTree

## 代码生成验证脚本：调用 CodeGenEngineerIK 生成 main.c 并做结构断言
## 运行方式：godot --headless --script scripts/test_codegen_ik.gd
## 最后一个构型的输出写入 res://test_ik_output.c 供 Keil 编译验证

var _fail: int = 0


func _initialize() -> void:
	print("=== 工程逆解算代码生成验证 ===")
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	_test_joy_axis(cg)
	_test_angle_clamp(cg)
	_test_no_preset(cg)
	_test_negative_elbow(cg)
	_test_joint_offset(cg)
	_test_config(cg, 0, 2, "2轴")
	_test_config(cg, 1, 3, "3轴")
	_test_config(cg, 2, 4, "4轴")
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


## 构造测试配置
func _make_cfg(config_type: int, jc: int, presets: Array) -> Dictionary:
	var joints: Array = []
	var io_list: Array = ["P74", "P75", "P76", "MP03"]
	for i in range(jc):
		joints.append({
			"io": io_list[i], "dir": "正向", "zero": "45",
			"min": "-90", "max": "90",
		})
	return {
		"config_type": config_type, "joint_count": jc,
		"L1": "100", "L2": "80", "L3": "30",
		"joints": joints,
		"presets": presets,
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "5",
		"keymove_speed": "2",
		"keymove": [
			{"plus": "↑", "minus": "↓"},
			{"plus": "←", "minus": "->"},
			{"plus": "B", "minus": "C"},
			{"plus": "D", "minus": "R"},
		],
	}


func _test_config(cg, config_type: int, jc: int, label: String) -> void:
	print("\n--- %s ---" % label)
	var presets: Array = [ {"key": "A", "x": "100", "y": "80", "z": "50", "phi": "90", "enabled": true}]
	var code: String = cg.generate(_make_cfg(config_type, jc, presets))
	_check("%s 生成非空" % label, not code.is_empty())
	# 必需的头文件与宏
	_check("%s 包含 main.h" % label, code.find("#include \"main.h\"") >= 0)
	_check("%s 包含 MATH.H" % label, code.find("#include \"MATH.H\"") >= 0)
	_check("%s 定义 L1/L2" % label, code.find("#define L1") >= 0 and code.find("#define L2") >= 0)
	_check("%s 定义 JOINT_COUNT %d" % [label, jc], code.find("#define JOINT_COUNT %d" % jc) >= 0)
	_check("%s 定义 ELBOW_SIGN" % label, code.find("#define ELBOW_SIGN") >= 0)
	# 必需的函数（定义签名须与前置声明一致）
	_check("%s 有 angle_to_duty" % label, code.find("uint16_t angle_to_duty(int joint, float angle)") >= 0)
	_check("%s 有 ik_solve" % label, code.find("void ik_solve(%s)" % _ik_sig(jc)) >= 0)
	_check("%s 有 CheckPresetKeys" % label, code.find("uint8_t CheckPresetKeys()") >= 0)
	_check("%s 有 CalculateIK" % label, code.find("void CalculateIK(uint8_t hit)") >= 0)
	_check("%s 有 ApplyServoControl" % label, code.find("void ApplyServoControl()") >= 0)
	_check("%s 有 ReadControllerInputs" % label, code.find("void ReadControllerInputs()") >= 0)
	_check("%s 有 All_Init" % label, code.find("void All_Init()") >= 0)
	_check("%s 有 main" % label, code.find("void main()") >= 0)
	_check("%s 有 ExpansionBoradControl" % label, code.find("void ExpansionBoradControl(") >= 0)
	_check("%s 定义 Channal" % label, code.find("uint8_t Channal =") >= 0)
	# 预设点位表用末端坐标而非关节角度
	_check("%s 有 presetPos 表" % label, code.find("const float presetPos[PRESET_COUNT][4]") >= 0)
	# 舵机方向不得再走 Dir_Change_Order（会与占空比镜像叠加抵消）
	_check("%s 不发 Dir_Change_Order" % label, code.find("ExpansionBoradControl(Dir_Change_Order") < 0)
	# 占空比系数：0~180° 必须映射满实测行程 250~1250（跨度 1000）
	_check("%s 占空比系数 5.5556" % label, code.find("#define SERVO_DUTY_PER_DEG  5.5556f") >= 0)
	# 舵机指令角以中位为 0°：先扣中位朝向，映射式不得再减 90°偏移
	_check("%s 映射以中位为 0°" % label,
		code.find("servo = angle - jointOffset[joint];") >= 0
		and code.find("SERVO_MID_DUTY + servo * SERVO_DUTY_PER_DEG") >= 0
		and code.find("angle - 90.0f") < 0)
	# 不应残留未被读取的 valueOfKey
	_check("%s 无死变量 valueOfKey" % label, code.find("valueOfKey") < 0)
	# 4 轴必须用 L3 做腕部补偿，且姿态角可由按键调整
	if jc >= 4:
		_check("4轴 定义 L3", code.find("#define L3") >= 0)
		_check("4轴 ik_solve 使用 L3", code.find("r = r - L3 * cos(phi_rad)") >= 0)
		_check("4轴 有 φ 按键增量", code.find("targetPhi += KEYMOVE_PHI_SPEED") >= 0)
	# 3/4 轴的钳位需防除零
	if jc >= 3:
		_check("%s ik_solve 防除零" % label, code.find("if (rz < IK_EPS)") >= 0)
	# C89：变量声明必须在可执行语句之前
	_check("%s 符合 C89 声明顺序" % label, _check_c89_decl_order(code))
	# 写入文件供 Keil 编译验证
	var f = FileAccess.open("res://test_ik_output.c", FileAccess.WRITE)
	if f:
		f.store_string(code)
		f.close()


## 预设点位为 0 时不得生成零长数组（C89 禁止）
func _test_no_preset(cg) -> void:
	print("\n--- 无预设点位 ---")
	var code: String = cg.generate(_make_cfg(1, 3, []))
	_check("PRESET_COUNT 为 0", code.find("#define PRESET_COUNT 0") >= 0)
	_check("不生成 presetKey 数组", code.find("const uint8_t presetKey[") < 0)
	_check("不生成 presetPos 数组", code.find("const float presetPos[") < 0)
	_check("不声明 CheckPresetKeys", code.find("uint8_t CheckPresetKeys();") < 0)
	_check("不调用 CheckPresetKeys", code.find("CheckPresetKeys()") < 0)
	_check("presetHit 置 0", code.find("presetHit = 0;") >= 0)


## 限位/初始角超出舵机行程 ±90° 时必须夹紧后写入常量数组
func _test_angle_clamp(cg) -> void:
	print("\n--- 角度夹紧 ±90° ---")
	var cfg: Dictionary = _make_cfg(1, 3, [])
	cfg["joints"][0]["min"] = "-180"
	cfg["joints"][0]["max"] = "180"
	cfg["joints"][1]["zero"] = "150"
	var code: String = cg.generate(cfg)
	_check("jointMin 夹到 -90", code.find("const float jointMin[3] = {-90.00f") >= 0)
	_check("jointMax 夹到 90", code.find("const float jointMax[3] = {90.00f") >= 0)
	_check("jointHome 夹到 90", code.find("90.00f") >= 0 and code.find("150.00f") < 0)


## 摇杆轴解析：不能被 "->" 右侧的 X/Y 干扰
func _test_joy_axis(cg) -> void:
	print("\n--- 摇杆轴解析 ---")
	_check("右X->末端X 取水平轴", cg.parse_joy_axis("右X->末端X") == [1, 0])
	_check("右Y->末端X 取竖直轴", cg.parse_joy_axis("右Y->末端X") == [1, 1])
	_check("右X->末端Z 取水平轴", cg.parse_joy_axis("右X->末端Z") == [1, 0])
	_check("右Y->末端Z 取竖直轴", cg.parse_joy_axis("右Y->末端Z") == [1, 1])


## 初始角为负的构型须取负肘部分支，保证正解起点与逆解自洽
func _test_negative_elbow(cg) -> void:
	print("\n--- 肘部分支自洽性 ---")
	# 正初始角：正分支
	var pos_cfg: Dictionary = _make_cfg(1, 3, [])
	var pos_code: String = cg.generate(pos_cfg)
	_check("正初始角 ELBOW_SIGN 为 +1", pos_code.find("#define ELBOW_SIGN  1.0f") >= 0)
	_check("正初始角 正反解自洽", _round_trip(cg, pos_cfg, 1.0))
	# 负初始角：负分支
	var neg_cfg: Dictionary = _make_cfg(1, 3, [])
	neg_cfg["joints"][2]["zero"] = "-60"
	var neg_code: String = cg.generate(neg_cfg)
	_check("负初始角 ELBOW_SIGN 为 -1", neg_code.find("#define ELBOW_SIGN  -1.0f") >= 0)
	_check("负初始角 正反解自洽", _round_trip(cg, neg_cfg, -1.0))


## 安装中位朝向：运动学角与舵机指令角分离
func _test_joint_offset(cg) -> void:
	print("\n--- 安装中位朝向 ---")
	# offset 缺失（老配置）：仍要生成数组，且全为 0，行为与以前一致
	var base_code: String = cg.generate(_make_cfg(1, 3, []))
	_check("offset 缺失时仍生成 jointOffset", base_code.find("const float jointOffset[3]") >= 0)
	_check("offset 缺失时全为 0",
		base_code.find("jointOffset[3] = {0.00f, 0.00f, 0.00f}") >= 0)
	# angle_to_duty 必须做减法，且符合 C89 声明靠前
	_check("angle_to_duty 扣掉中位朝向",
		base_code.find("servo = angle - jointOffset[joint];") >= 0)
	_check("angle_to_duty 用 servo 算占空比",
		base_code.find("SERVO_MID_DUTY + servo * SERVO_DUTY_PER_DEG") >= 0
			and base_code.find("SERVO_MID_DUTY - servo * SERVO_DUTY_PER_DEG") >= 0)
	_check("angle_to_duty 声明在块首(C89)", _decl_before_stmt(base_code, "float servo;"))
	# offset 不为 0：限位钳位区间跟着平移，不再是固定 ±90
	var cfg: Dictionary = _make_cfg(1, 3, [])
	for i in range(3):
		cfg["joints"][i]["offset"] = "30"
		cfg["joints"][i]["min"] = "-60"
		cfg["joints"][i]["max"] = "120"
	var code: String = cg.generate(cfg)
	_check("offset=30 写入 jointOffset",
		code.find("jointOffset[3] = {30.00f, 30.00f, 30.00f}") >= 0)
	# 行程 = 30±90 = [-60, 120]，故 min/max 应原值保留而非被钳到 ±90
	_check("offset=30 时 min=-60 未被误钳",
		code.find("jointMin[3] = {-60.00f, -60.00f, -60.00f}") >= 0)
	_check("offset=30 时 max=120 未被误钳（旧逻辑会钳到 90）",
		code.find("jointMax[3] = {120.00f, 120.00f, 120.00f}") >= 0)
	# 初始角 45 在 [-60,120] 内，不应被改
	_check("offset=30 时 jointHome 保持 45",
		code.find("jointHome[3] = {45.00f, 45.00f, 45.00f}") >= 0)
	# ik_solve 不应因 offset 而变（逆解本来就在运动学空间）
	_check("ik_solve 不引用 jointOffset",
		not _func_body(code, "void ik_solve(").contains("jointOffset"))


## 指定声明是否出现在所属函数体的可执行语句之前（C251 默认 C89）
func _decl_before_stmt(code: String, decl: String) -> bool:
	var body: String = _func_body(code, "uint16_t angle_to_duty(")
	var at: int = body.find(decl)
	if at < 0:
		return false
	# 声明前面只允许出现其他声明（含 int/float）与空白
	for line in body.substr(0, at).split("\n"):
		var t: String = line.strip_edges()
		if t.is_empty() or t == "{" or t.begins_with("//"):
			continue
		if not (t.begins_with("int ") or t.begins_with("float ") or t.begins_with("uint")):
			return false
	return true


## 取出以 signature 开头的函数体文本（到下一个顶层 } 为止）
func _func_body(code: String, signature: String) -> String:
	# 可能先命中前置声明（以 ; 结尾），逐个往后找带 { 的那个
	var from: int = 0
	while true:
		var at: int = code.find(signature, from)
		if at < 0:
			return ""
		var brace: int = code.find("{", at)
		var semi: int = code.find(";", at)
		if brace >= 0 and (semi < 0 or brace < semi):
			var end: int = code.find("\n}", brace)
			return code.substr(at, (end if end >= 0 else code.length()) - at)
		from = at + signature.length()
	return ""


## 把生成代码里的 target 初值（正运动学结果）反解回关节角，应还原各关节初始角
func _round_trip(cg, cfg: Dictionary, elbow: float) -> bool:
	var code: String = cg.generate(cfg)
	var home: Array = _parse_home(code)
	if home.is_empty():
		print("      未能解析 target 初值")
		return false
	var jc: int = cfg["joint_count"]
	var angles: Array = cg.solve_ik(home[0], home[1], home[2], home[3],
		cfg["L1"].to_float(), cfg["L2"].to_float(), cfg["L3"].to_float(),
		cfg["config_type"], jc, elbow)
	for i in range(jc):
		var want: float = cfg["joints"][i]["zero"].to_float()
		if abs(angles[i] - want) > 0.5:
			print("      关节%d 期望 %.1f 实得 %.1f" % [i + 1, want, angles[i]])
			return false
	return true


## ik_solve 的形参列表（随构型裁剪，需与生成器保持一致）
func _ik_sig(jc: int) -> String:
	var names: Array = ["float x", "float y"]
	if jc >= 3:
		names.append("float z")
	if jc >= 4:
		names.append("float phi")
	return ", ".join(names)


## 从生成代码里取回 target 初值，不足 4 个分量时补 0
func _parse_home(code: String) -> Array:
	var at: int = code.find("    targetX = ")
	if at < 0:
		return []
	var line: String = code.substr(at, code.find("\n", at) - at)
	var out: Array = []
	for seg in line.split(";"):
		var eq: int = seg.find("=")
		if eq < 0:
			continue
		var num: String = seg.substr(eq + 1).strip_edges().trim_suffix("f")
		out.append(num.to_float())
	if out.is_empty():
		return []
	while out.size() < 4:
		out.append(0.0)
	return out


## 粗查 C89 声明顺序：函数体内出现可执行语句后不应再有变量声明
## 逐字符跟踪花括号深度，避免被行内 { } 或宏续行搞乱层级
func _check_c89_decl_order(code: String) -> bool:
	var depth: int = 0
	var seen_stmt: bool = false
	for raw in code.split("\n"):
		var line: String = raw.strip_edges()
		if line.is_empty() or line.begins_with("//") or line.begins_with("#") or line.begins_with("/"):
			continue
		var opens: int = line.count("{")
		var closes: int = line.count("}")
		# 先按进入本行时的深度判定，再更新深度
		if depth > 0 and not line.begins_with("}") and not line.begins_with("{"):
			var is_decl: bool = (line.begins_with("float ") or line.begins_with("int ")
				or line.begins_with("uint8_t ") or line.begins_with("uint16_t "))
			if is_decl:
				if seen_stmt:
					print("      C89 违规行: %s" % line)
					return false
			else:
				seen_stmt = true
		if opens > closes:
			# 进入更深的块，块内重新允许声明
			seen_stmt = false
		depth += opens - closes
		if depth < 0:
			depth = 0
	return true

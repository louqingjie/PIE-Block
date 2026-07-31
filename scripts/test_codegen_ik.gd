extends SceneTree

## 代码生成验证脚本：调用 CodeGenEngineerIK 生成 main.c 并做结构断言
## 运行方式：godot --headless --script scripts/test_codegen_ik.gd
## 最后一个构型的输出写入 user://test_ik_output.c，避免测试产物污染仓库

var _fail: int = 0


func _initialize() -> void:
	print("=== 工程逆解算代码生成验证 ===")
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	_test_joy_axis(cg)
	_test_angle_clamp(cg)
	_test_no_preset(cg)
	_test_dual_mode(cg)
	_test_gripper(cg)
	_test_initial_target(cg)
	_test_joint_offset(cg)
	_test_config(cg, 2, "2关节")
	_test_config(cg, 3, "3关节")
	_test_config(cg, 4, "4关节")
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


## 构造测试配置
func _make_cfg(jc: int, presets: Array) -> Dictionary:
	var joints: Array = []
	var io_list: Array = ["P74", "P75", "P76", "MP03"]
	var lens: Array = [100.0, 80.0] if jc == 2 else [0.0, 100.0, 80.0, 30.0]
	for i in range(jc):
		joints.append({
			"io": io_list[i], "dir": "正向",
			"axis": "Yaw" if i == 0 else "Pitch", "len": str(lens[i]), "zero": "45",
			"min": "-90", "max": "90",
		})
	return {
		"joint_count": jc,
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


func _make_dual_cfg() -> Dictionary:
	var ik: Dictionary = _make_cfg(3, [])
	ik["mode_switch_key"] = "R"
	return {
		"engineer": {
			"channel": "42", "deadzone": "12", "normal_speed": "4000",
			"sprint_speed": "8000", "sprint_enabled": true,
			"l1_io": "P60 P61", "l2_io": "P62 P63",
			"r1_io": "P64 P65", "r2_io": "P66 P67",
			"l1_dir": "正向", "l2_dir": "正向",
			"r1_dir": "正向", "r2_dir": "正向",
			"key_map": [
				{"input": "A", "dir": "正", "mode": "增量", "param": "2", "target": "P74"},
				{"input": "B", "dir": "反", "mode": "增量", "param": "2", "target": "P74"},
				{"input": "C", "dir": "正", "mode": "直接", "param": "30", "target": "MP74"},
			],
		},
		"ik": ik,
	}


func _test_dual_mode(cg) -> void:
	print("\n--- 正解/逆解双模式 ---")
	var code: String = cg.generate(_make_dual_cfg())
	_check("上电默认逆解", code.contains("uint8_t   inverseMode = 1"))
	_check("R 键边沿锁存", code.contains("pressed = RcKeyValueRead(KEY_OFFSET_1)")
		and code.contains("pressed && !modeKeyHeld")
		and code.contains("else if (!pressed)"))
	_check("正逆解分支", code.contains("if (inverseMode)")
		and code.contains("CalculateForwardControl();"))
	_check("切回逆解同步 FK 目标", code.contains("SyncIKTargetFromJoints();")
		and code.contains("targetX = ikPts[JOINT_COUNT][0]"))
	_check("底盘两种模式常驻", code.contains("CalculateChassisControl();")
		and code.find("CalculateChassisControl();") < code.find("if (inverseMode)"))
	_check("读取工程通道和死区", code.contains("uint8_t Channal = 42;")
		and code.contains("deadBandOfLeft = 12;"))
	_check("底盘走扩展板统一输出", code.contains("dutyOfChassis[0]")
		and code.contains("ExpansionBoradControl(Dir_Change_Order"))
	_check("底盘冲刺和电机限幅", code.contains("KEY_OFFSET_Rocker11")
		and code.contains("dutyOfChassis[i] > speedLimit")
		and code.contains("dutyOfAuxMotor[i] > 10000"))
	_check("辅助主控板舵机复用工程映射", code.contains("dutyOfAuxMainServo[1] = 917.0f")
		and code.contains("PWM_SET_Frequency(PWMB_CH1_P74, 50, (uint16_t)dutyOfAuxMainServo[1])"))
	_check("只有一个 main", code.count("void main()") == 1)
	_check("只有一个扩展板函数定义", code.count("/// @brief 板间通信函数") == 1)
	_check("双模式符合 C89 声明顺序", _check_c89_decl_order(code))


func _test_gripper(cg) -> void:
	print("\n--- 独立夹爪舵机 ---")
	var cfg: Dictionary = _make_cfg(3, [])
	cfg["gripper"] = {
		"enabled": true, "io": "P77", "dir": "反向", "open_angle": "45",
		"closed_angle": "-45", "initial_open": true, "key": "D"}
	var code: String = cg.generate(cfg)
	_check("夹爪不增加关节数", code.contains("#define JOINT_COUNT 3"))
	_check("夹爪反向角预计算为占空比", code.contains("#define GRIPPER_OPEN_DUTY  500")
		and code.contains("#define GRIPPER_CLOSED_DUTY  1000"))
	_check("夹爪有独立状态与按键锁存", code.contains("uint8_t  gripperOpen = 1")
		and code.contains("pressed = RcKeyValueRead(KEY_OFFSET_D)")
		and code.contains("pressed && !gripperKeyHeld"))
	_check("夹爪更新位于模式分支之外", code.find("UpdateGripper();") < code.find("if (inverseMode)"))
	_check("扩展板夹爪合并统一输出", code.contains("dutyOfGripper")
		and code.contains("ExpansionBoradControl(Duty_Change_Order")
		and not code.contains("PWM_"))
	var main_cfg: Dictionary = _make_cfg(2, [])
	main_cfg["gripper"] = cfg["gripper"].duplicate(true)
	main_cfg["gripper"]["io"] = "MP74"
	main_cfg["gripper"]["initial_open"] = false
	var main_code: String = cg.generate(main_cfg)
	_check("主控夹爪按闭合状态初始化", main_code.contains("uint8_t  gripperOpen = 0")
		and main_code.contains("PWM_Init(PWMB_CH1_P74, 50, dutyOfGripper)"))
	_check("主控夹爪运行时使用 PWM", main_code.contains(
		"PWM_SET_Frequency(PWMB_CH1_P74, 50, dutyOfGripper)"))
	var disabled_code: String = cg.generate(_make_cfg(3, []))
	_check("禁用夹爪不生成控制状态", not disabled_code.contains("dutyOfGripper"))


func _test_config(cg, jc: int, label: String) -> void:
	print("\n--- %s ---" % label)
	var presets: Array = [ {"key": "A", "x": "100", "y": "80", "z": "50", "phi": "90", "enabled": true}]
	var code: String = cg.generate(_make_cfg(jc, presets))
	_check("%s 生成非空" % label, not code.is_empty())
	# 必需的头文件与宏
	_check("%s 包含 main.h" % label, code.find("#include \"main.h\"") >= 0)
	_check("%s 包含 MATH.H" % label, code.find("#include \"MATH.H\"") >= 0)
	# 连杆长度已改由 jointLen[] 表提供，L1/L2/L3 与 ELBOW_SIGN 已完全不参与计算。
	# 它们不能再出现在生成代码里：编译器不会为未使用的宏报警，
	# 但「参数区摆着 #define L1 120.00f、实际逆解读的是 jointLen[]」
	# 会让学生改错地方。
	_check("%s 不再定义 L1/L2/L3 死宏" % label,
		code.find("#define L1") < 0 and code.find("#define L2") < 0
		and code.find("#define L3") < 0)
	_check("%s 不再定义 ELBOW_SIGN 死宏" % label,
		code.find("ELBOW_SIGN") < 0)
	_check("%s 定义 JOINT_COUNT %d" % [label, jc], code.find("#define JOINT_COUNT %d" % jc) >= 0)

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
	# 逆解已换成雅可比转置数值解，取代 2/3/4 轴各一套的解析公式。
	# 转轴与连杆长度两张表是它的全部输入。
	_check("%s 有 jointAxis 表" % label, code.find("const float jointAxis[") >= 0)
	_check("%s 有 jointLen 表" % label, code.find("const float jointLen[") >= 0)
	_check("%s 有矩阵辅助函数" % label,
		code.find("void mat_vec(") >= 0 and code.find("void axis_rot(") >= 0
		and code.find("void mat_mul(") >= 0)
	# FK 中间结果必须在 xdata：C251 单函数局部变量段上限 128 字节
	_check("%s 中间结果在 xdata" % label,
		code.find("static float xdata ikPts[") >= 0
		and code.find("static float xdata ikBasis[") >= 0)
	# α 必须自适应（分子是关节空间的 |J^T e|²），不能是固定值
	_check("%s alpha 自适应" % label,
		code.find("num += ikJte[k] * ikJte[k]") >= 0
		and code.find("alpha = num / den") >= 0)
	_check("%s 有单步限幅" % label, code.find("IK_MAX_STEP_DEG / maxStep") >= 0)
	# 该测试构型从 4 关节起具备独立姿态自由度，姿态角应可由按键调整。
	if jc >= 4:
		_check("4轴 有 φ 按键增量", code.find("targetPhi += KEYMOVE_PHI_SPEED") >= 0)
		# 俯仰角纳入解算：权重宏 + asin 求仰角 + 梯度项
		_check("4轴 有 PHI_WEIGHT", code.find("#define PHI_WEIGHT") >= 0)
		_check("4轴 用 asin 求仰角", code.find("asin(az)") >= 0)
		_check("4轴 有 φ 梯度项", code.find("gk * PHI_WEIGHT") >= 0)
	# 可达性拦截不能再依赖 ik_reachable（雅可比法下它只表示「这步有没有靠近」）
	_check("%s 用臂展判超界" % label, code.find("ik_target_too_far(") >= 0)
	_check("%s 超界时允许目标朝内移动" % label,
		code.find("targetX * targetX + targetY * targetY + targetZ * targetZ") >= 0
		and code.find("lastX * lastX + lastY * lastY + lastZ * lastZ") >= 0)
	# C89：变量声明必须在可执行语句之前
	_check("%s 符合 C89 声明顺序" % label, _check_c89_decl_order(code))
	# 写入用户临时目录，仍可供开发期 Keil 编译验证
	var f = FileAccess.open("user://test_ik_output.c", FileAccess.WRITE)
	if f:
		f.store_string(code)
		f.close()


## 预设点位为 0 时不得生成零长数组（C89 禁止）
func _test_no_preset(cg) -> void:
	print("\n--- 无预设点位 ---")
	var code: String = cg.generate(_make_cfg(3, []))
	_check("PRESET_COUNT 为 0", code.find("#define PRESET_COUNT 0") >= 0)
	_check("不生成 presetKey 数组", code.find("const uint8_t presetKey[") < 0)
	_check("不生成 presetPos 数组", code.find("const float presetPos[") < 0)
	_check("不声明 CheckPresetKeys", code.find("uint8_t CheckPresetKeys();") < 0)
	_check("不调用 CheckPresetKeys", code.find("CheckPresetKeys()") < 0)
	_check("presetHit 置 0", code.find("presetHit = 0;") >= 0)


## 限位/初始角超出舵机行程 ±90° 时必须夹紧后写入常量数组
func _test_angle_clamp(cg) -> void:
	print("\n--- 角度夹紧 ±90° ---")
	var cfg: Dictionary = _make_cfg(3, [])
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
	_check("不使用不解析为摇杆轴", cg.parse_joy_axis("不使用").is_empty())
	var no_joy_cfg: Dictionary = _make_cfg(3, [])
	no_joy_cfg["joy_x"] = "不使用"
	no_joy_cfg["joy_y"] = "不使用"
	no_joy_cfg["joy_z"] = "不使用"
	var no_joy_code: String = cg.generate(no_joy_cfg)
	_check("全部禁用时不生成末端摇杆增量", not no_joy_code.contains(
		"targetX += (float)valueOfRoker") and not no_joy_code.contains(
		"targetY += (float)valueOfRoker") and not no_joy_code.contains(
		"targetZ += (float)valueOfRoker"))


## 上电起点自洽：main() 里 target 的初值必须等于初始角对应的实际末端。
##
## 原来这里测的是 ELBOW_SIGN（肘部分支）。那是解析解特有的概念——
## 余弦定理有两个解，得靠符号挑一个。雅可比法从当前姿态起解，
## 天然待在初始角所在的那一支，不需要也没有这个参数。
## 换成测「上电首帧不跳变」：target 初值与初始角末端不符会导致关节猛冲。
func _test_initial_target(cg) -> void:
	print("\n--- 上电起点自洽性 ---")
	for zero in ["45", "-60"]:
		var cfg: Dictionary = _make_cfg(3, [])
		cfg["joints"][2]["zero"] = zero
		var code: String = cg.generate(cfg)
		# 生成代码里的 target 初值
		var idx: int = code.find("targetX = ")
		_check("初始角%s 生成 target 初值" % zero, idx >= 0)
		if idx < 0:
			continue
		var line: String = code.substr(idx, code.find("\n", idx) - idx)
		# 与 GDScript 侧按初始角正推的末端比对
		var jc: int = cfg["joint_count"]
		var home_ang: Array = cg._joint_home_angles(cfg["joints"])
		var chain: Dictionary = cg.fk_chain(home_ang, cfg["joints"], jc)
		var pts: Array = chain["points"]
		var tip: Vector3 = pts[pts.size() - 1]
		var ok: bool = line.contains("%.2ff" % tip.x) and line.contains("%.2ff" % tip.y)
		if not ok:
			print("      生成 %s / 期望 x=%.2f y=%.2f" % [line, tip.x, tip.y])
		_check("初始角%s target 初值 == 初始姿态末端" % zero, ok)


## 安装中位朝向：运动学角与舵机指令角分离
func _test_joint_offset(cg) -> void:
	print("\n--- 安装中位朝向 ---")
	# offset 缺失（老配置）：仍要生成数组，且全为 0，行为与以前一致
	var base_code: String = cg.generate(_make_cfg(3, []))
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
	var cfg: Dictionary = _make_cfg(3, [])
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


## ik_solve 的形参列表（随构型裁剪，需与生成器保持一致）
func _ik_sig(jc: int) -> String:
	var names: Array = ["float x", "float y", "float z"]
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

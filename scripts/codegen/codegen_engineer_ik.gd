class_name CodeGenEngineerIK
extends CodeGenBase

## 工程机器人逆解算代码生成器。
## 根据配置字典生成工程机械臂逆解算 main.c 代码。
## 支持 2/3/4 轴全舵机构型，解析解（atan2 + 余弦定理）。
## 预设点位在 GDScript 端预计算为关节角度，写入 C const 数组（避免运行时重复算）；
## 摇杆实时模式则调用运行时 IK 函数。


# 舵机 50Hz 占空比参数（与步兵体系一致）
const SERVO_MID_DUTY: int = 750 # 90° 中位
const SERVO_MIN_DUTY: int = 500 # 0°
const SERVO_MAX_DUTY: int = 1000 # 180°
# duty/度 线性系数：(1000-500)/180
const SERVO_DUTY_PER_DEG: float = 250.0 / 180.0


# ------------------------------------------------------------------ 代码生成
## 基于配置字典生成完整的 main.c 代码字符串
func generate(cfg: Dictionary) -> String:
	var config_type: int = cfg.get("config_type", 0) # 0=2轴, 1=3轴, 2=4轴
	var jc: int = cfg.get("joint_count", 2)
	var l1: float = _to_float(cfg.get("L1", "100"), 100.0)
	var l2: float = _to_float(cfg.get("L2", "100"), 100.0)
	var l3: float = _to_float(cfg.get("L3", "0"), 0.0)
	var joints: Array = cfg.get("joints", [])
	var presets: Array = cfg.get("presets", [])
	var joy_scale: float = _to_float(cfg.get("joy_scale", "200"), 200.0)
	var keymove_speed: float = _to_float(cfg.get("keymove_speed", "2"), 2.0)

	var code: String = ""
	code += "// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "// ========================= 参数区 =========================\n"
	code += "// 机械臂构型：%s\n" % _config_type_name(config_type)
	code += "#define L1   %.2ff   // 大臂长度(mm)\n" % l1
	code += "#define L2   %.2ff   // 小臂长度(mm)\n" % l2
	if jc >= 4:
		code += "#define L3   %.2ff   // 腕部连杆长度(mm)\n" % l3
	code += "#define JOINT_COUNT %d\n" % jc
	code += "// 舵机占空比参数（50Hz）\n"
	code += "#define SERVO_MID_DUTY  750\n"
	code += "#define SERVO_MIN_DUTY  500\n"
	code += "#define SERVO_MAX_DUTY  1000\n"
	code += "#define SERVO_DUTY_PER_DEG  %.4ff\n" % SERVO_DUTY_PER_DEG
	code += "// 摇杆末端每周期位移缩放(mm)\n"
	code += "#define JOY_SCALE  %.2ff\n" % joy_scale
	code += "// 按键长按时末端每周期位移(mm)\n"
	code += "#define KEYMOVE_SPEED  %.2ff\n" % keymove_speed
	code += "#define LIMIT_VALUE(x, min, max) \\\n"
	code += "    do                           \\\n"
	code += "    {                            \\\n"
	code += "        if ((x) < (min))         \\\n"
	code += "            (x) = (min);         \\\n"
	code += "        else if ((x) > (max))    \\\n"
	code += "            (x) = (max);         \\\n"
	code += "    } while (0)\n"
	code += _build_protocol_macros()
	# NRF24L01 通信通道（nrf24l01.c 通过 extern 引用，必须在此定义）
	code += "uint8_t Channal = 36;                          // NRF24L01 通信通道（0-125），与遥控器一致\n"
	code += "// 自定义变量\n"
	code += "uint16_t dutyOfServo[%d];       // 各关节舵机占空比\n" % jc
	code += "float    jointAngle[%d];        // 各关节角度(度)\n" % jc
	code += "float    targetX, targetY, targetZ, targetPhi;\n"
	code += "uint8_t  ik_reachable;          // 逆解算可达性标志(1=可达,0=越界已钳位)\n"
	code += "uint8_t  presetHit;             // 本周期是否命中预设点位\n"
	code += "uint8_t  valueOfKey[3][4];\n"
	code += "int16_t  valueOfRoker[2][2];    // 左摇杆水平、竖直；右摇杆水平、竖直\n"
	code += "uint16_t deadBandOfLeft = 10;\n"
	code += "uint16_t deadBandOfRight = 10;\n"
	code += "uint8_t  i, j;\n"
	code += _build_key_offsets_table()
	# 关节配置常量数组（零点/限位/方向/IO 槽位）
	code += _build_joint_config_arrays(joints, jc)
	# 预设点位表（GDScript 端预计算关节角度）
	code += _build_preset_table(presets, jc, l1, l2, config_type)
	code += "\n"
	# 函数声明
	code += "void All_Init();\n"
	code += "void ReadControllerInputs();\n"
	code += "void CalculateIK(uint8_t presetHit);\n"
	code += "void ApplyServoControl();\n"
	code += "uint8_t CheckPresetKeys();\n"
	code += "uint16_t angle_to_duty(int joint, float angle);\n"
	code += "void ik_solve(float x, float y, float z, float phi);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	# --- main() ---
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	code += "    // 初始化各关节到零点角度\n"
	code += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	code += "        jointAngle[i] = jointZero[i];\n"
	# 增量模式：target 必须初始化为零点姿态对应的末端位置（正运动学预计算）
	var home: Array = _forward_kinematics(joints, l1, l2, config_type, jc)
	code += "    // 增量模式起点：零点姿态对应的末端位置（GUI 端正运动学预计算）\n"
	code += "    targetX = %.2ff; targetY = %.2ff; targetZ = %.2ff; targetPhi = %.2ff;\n" % [home[0], home[1], home[2], home[3]]
	code += "    ik_reachable = 1;\n"
	code += "    while (1)\n"
	code += "    {\n"
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n"
	code += "        ReadControllerInputs();\n"
	code += "        presetHit = CheckPresetKeys(); // 预设点位按键检测\n"
	code += "        CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算\n"
	code += "        ApplyServoControl();          // 应用舵机控制\n"
	code += "        Ms_Delay(10);\n"
	code += "    }\n"
	code += "}\n\n"

	# --- angle_to_duty ---
	code += _gen_angle_to_duty(jc, joints)
	# --- ik_solve ---
	code += _gen_ik_solve(config_type, jc)
	# --- ReadControllerInputs ---
	code += _gen_read_inputs(cfg)
	# --- CheckPresetKeys ---
	code += _gen_check_preset_keys(presets, jc)
	# --- CalculateIK ---
	code += _gen_calculate_ik(cfg)
	# --- ApplyServoControl ---
	code += _gen_apply_servo_control(joints, jc)
	# --- All_Init ---
	code += _gen_all_init(joints, jc)
	# --- ExpansionBoradControl ---
	code += _gen_expansion_board_func()
	return code


# ------------------------------------------------------------------ 协议宏
func _build_protocol_macros() -> String:
	var s: String = ""
	s += "/*帧头帧尾，内部调用，无需关心*/\n"
	s += "#define COMM_HEADER_1 0xAB\n#define COMM_HEADER_2 0xBC\n#define COMM_END_1 0xCD\n#define COMM_END_2 0xDE\n"
	s += "/*命令码*/\n"
	s += "#define Init_Order 0xAA        // 初始化模式\n"
	s += "#define Duty_Change_Order 0xBB // 修改占空比\n"
	s += "#define Freq_Change_Order 0xCC // 修改频率\n"
	s += "#define Dir_Change_Order 0xDD  // 修改方向 1为正 0为负 设置一次即可\n"
	s += "#define Zero_Order 0xEE        // 0命令\n"
	s += "/*内部调用变量，无需关心，请勿定义同名变量*/\n"
	s += "uint16_t control_data[8] = {0};\n"
	s += "uint16_t motor_dir[8] = {0};\n"
	s += "uint8_t control_command = 0x00;\n"
	return s


# ------------------------------------------------------------------ 按键偏移表
func _build_key_offsets_table() -> String:
	var s: String = ""
	s += "static const uint8_t keyOffsets[3][4] = {\n"
	s += "    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},\n"
	s += "    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},\n"
	s += "    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个\n"
	s += "};\n"
	return s


# ------------------------------------------------------------------ 关节配置数组
func _build_joint_config_arrays(joints: Array, jc: int) -> String:
	var s: String = ""
	s += "// 各关节零点角度(度)\n"
	s += "const float jointZero[%d] = {" % jc
	for i in range(jc):
		var zero: float = _to_float(joints[i].get("zero", "0"), 0.0)
		if i > 0:
			s += ", "
		s += "%.2ff" % zero
	s += "};\n"
	s += "// 各关节限位(度) [min, max]\n"
	s += "const float jointMin[%d] = {" % jc
	for i in range(jc):
		var mn: float = _to_float(joints[i].get("min", "-180"), -180.0)
		if i > 0:
			s += ", "
		s += "%.2ff" % mn
	s += "};\n"
	s += "const float jointMax[%d] = {" % jc
	for i in range(jc):
		var mx: float = _to_float(joints[i].get("max", "180"), 180.0)
		if i > 0:
			s += ", "
		s += "%.2ff" % mx
	s += "};\n"
	s += "// 各关节方向(1=正向, 0=反向)\n"
	s += "const uint8_t jointDir[%d] = {" % jc
	for i in range(jc):
		var d: int = 1 if joints[i].get("dir", "正向") == "正向" else 0
		if i > 0:
			s += ", "
		s += str(d)
	s += "};\n"
	return s


# ------------------------------------------------------------------ 预设点位表
# GDScript 端预计算每个预设点位对应的关节角度，写入 C const 数组
func _build_preset_table(presets: Array, jc: int, l1: float, l2: float, config_type: int) -> String:
	var s: String = ""
	# 统计启用的预设点位
	var active: Array = []
	for p in presets:
		if p.get("enabled", false):
			active.append(p)
	var count: int = active.size()
	s += "// 预设点位数量\n"
	s += "#define PRESET_COUNT %d\n" % count
	s += "// 预设点位：按键 KEY_OFFSET\n"
	s += "const uint8_t presetKey[PRESET_COUNT] = {"
	for i in range(count):
		var key_name: String = active[i].get("key", "A")
		var key_offset: String = _key_name_to_offset(key_name)
		if i > 0:
			s += ", "
		s += key_offset
	s += "};\n"
	# 存末端坐标而非关节角度：与增量模式统一走 ik_solve，避免两套状态冲突
	s += "// 预设点位末端坐标 {x, y, z, phi}\n"
	s += "const float presetPos[PRESET_COUNT][4] = {\n"
	for i in range(count):
		var p: Dictionary = active[i]
		var x: float = _to_float(p.get("x", "0"), 0.0)
		var y: float = _to_float(p.get("y", "0"), 0.0)
		var z: float = _to_float(p.get("z", "0"), 0.0)
		var phi: float = _to_float(p.get("phi", "0"), 0.0)
		s += "    {%.2ff, %.2ff, %.2ff, %.2ff}" % [x, y, z, phi]
		if i < count - 1:
			s += ","
		# 附上 GUI 端预计算的关节角度作为注释，便于人工核对
		var angles: Array = _solve_ik(x, y, z, phi, l1, l2, config_type, jc)
		var ang_str: String = ""
		for k in range(jc):
			if k > 0:
				ang_str += ", "
			ang_str += "%.1f" % angles[k]
		s += "  // P%d 关节角度: [%s]\n" % [i + 1, ang_str]
	s += "};\n"
	return s


# ------------------------------------------------------------------ GDScript 端 IK 预计算
# 与 C 端 ik_solve 公式保持一致，用于预计算预设点位角度
func _solve_ik(x: float, y: float, z: float, phi: float, l1: float, l2: float, config_type: int, jc: int) -> Array:
	var angles: Array = []
	if config_type == 0:
		# 2 轴平面
		var r: float = sqrt(x * x + y * y)
		var c2: float = (r * r - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = acos(c2)
		var t1: float = atan2(y, x) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t1), rad_to_deg(t2)]
	elif config_type == 1:
		# 3 轴：底座 + 2 连杆
		var t0: float = atan2(y, x)
		var r: float = sqrt(x * x + y * y)
		var c2: float = (r * r + z * z - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = acos(c2)
		var t1: float = atan2(z, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2)]
	else:
		# 4 轴：3 轴 + 腕部
		var t0: float = atan2(y, x)
		var r: float = sqrt(x * x + y * y)
		var c2: float = (r * r + z * z - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = acos(c2)
		var t1: float = atan2(z, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		var t3: float = deg_to_rad(phi) - (t1 + t2)
		angles = [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2), rad_to_deg(t3)]
	# 补齐到 jc 个元素
	while angles.size() < jc:
		angles.append(0.0)
	return angles


# ------------------------------------------------------------------ 正运动学（零点姿态末端位置）
## 由各关节零点角度算出末端位置，作为增量模式的起点
## 返回 [x, y, z, phi]
func _forward_kinematics(joints: Array, l1: float, l2: float, config_type: int, jc: int) -> Array:
	# 取各关节零点角度（度）
	var z0: float = 0.0
	var z1: float = 0.0
	var z2: float = 0.0
	var z3: float = 0.0
	if joints.size() > 0:
		z0 = _to_float(joints[0].get("zero", "0"), 0.0)
	if joints.size() > 1:
		z1 = _to_float(joints[1].get("zero", "0"), 0.0)
	if joints.size() > 2:
		z2 = _to_float(joints[2].get("zero", "0"), 0.0)
	if joints.size() > 3:
		z3 = _to_float(joints[3].get("zero", "0"), 0.0)
	if config_type == 0:
		# 2 轴平面：θ1=关节1, θ2=关节2
		var t1: float = deg_to_rad(z0)
		var t2: float = deg_to_rad(z1)
		var x: float = l1 * cos(t1) + l2 * cos(t1 + t2)
		var y: float = l1 * sin(t1) + l2 * sin(t1 + t2)
		return [x, y, 0.0, 0.0]
	elif config_type == 1:
		# 3 轴：θ0=底座, θ1/θ2=2连杆（在 (r,z) 平面）
		var t0: float = deg_to_rad(z0)
		var t1: float = deg_to_rad(z1)
		var t2: float = deg_to_rad(z2)
		var r: float = l1 * cos(t1) + l2 * cos(t1 + t2)
		var zz: float = l1 * sin(t1) + l2 * sin(t1 + t2)
		return [r * cos(t0), r * sin(t0), zz, 0.0]
	else:
		# 4 轴：3 轴 + 腕部，φ = θ1+θ2+θ3
		var t0: float = deg_to_rad(z0)
		var t1: float = deg_to_rad(z1)
		var t2: float = deg_to_rad(z2)
		var t3: float = deg_to_rad(z3)
		var r: float = l1 * cos(t1) + l2 * cos(t1 + t2)
		var zz: float = l1 * sin(t1) + l2 * sin(t1 + t2)
		return [r * cos(t0), r * sin(t0), zz, rad_to_deg(t1 + t2 + t3)]


# ------------------------------------------------------------------ angle_to_duty
func _gen_angle_to_duty(_jc: int, _joints: Array) -> String:
	var s: String = ""
	s += "/// @brief 关节角度(度) -> 舵机占空比\n"
	s += "/// @param joint 关节索引(0..JOINT_COUNT-1)\n"
	s += "/// @param angle 角度(度)\n"
	s += "/// @return 舵机占空比(SERVO_MIN_DUTY~SERVO_MAX_DUTY)\n"
	s += "uint16_t angle_to_duty(int joint, float angle)\n"
	s += "{\n"
	s += "    int duty;\n"
	s += "    // 限位夹紧\n"
	s += "    if (angle < jointMin[joint])\n"
	s += "        angle = jointMin[joint];\n"
	s += "    if (angle > jointMax[joint])\n"
	s += "        angle = jointMax[joint];\n"
	s += "    // 角度 -> 占空比（中位 750 = 90°）\n"
	s += "    duty = (int)(SERVO_MID_DUTY + (angle - 90.0f) * SERVO_DUTY_PER_DEG);\n"
	s += "    // 方向反向\n"
	s += "    if (!jointDir[joint])\n"
	s += "        duty = (int)(SERVO_MID_DUTY - (angle - 90.0f) * SERVO_DUTY_PER_DEG);\n"
	s += "    if (duty < SERVO_MIN_DUTY)\n"
	s += "        duty = SERVO_MIN_DUTY;\n"
	s += "    if (duty > SERVO_MAX_DUTY)\n"
	s += "        duty = SERVO_MAX_DUTY;\n"
	s += "    return (uint16_t)duty;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ik_solve
func _gen_ik_solve(config_type: int, _jc: int) -> String:
	var s: String = ""
	s += "/// @brief 逆解算：末端(x,y,z,φ) -> 各关节角度\n"
	s += "/// @param x 末端X(mm)\n"
	s += "/// @param y 末端Y(mm)\n"
	s += "/// @param z 末端Z(mm)\n"
	s += "/// @param phi 末端姿态角(度，仅4轴用)\n"
	s += "/// @note 结果写入 jointAngle[]，越界时钳到边界并设 ik_reachable=0\n"
	s += "void ik_solve(float x, float y, float z, float phi)\n"
	s += "{\n"
	# C89：所有变量声明在函数开头，可执行语句之后
	if config_type == 0:
		# 2 轴平面
		s += "    float r, c2, t1, t2;\n"
		s += "    ik_reachable = 1;\n"
		s += "    // === 2 轴平面逆解 ===\n"
		s += "    r = sqrt(x * x + y * y);\n"
		s += "    // 可达性检查\n"
		s += "    if (r < fabs(L1 - L2) || r > (L1 + L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        if (r < fabs(L1 - L2))\n"
		s += "            r = fabs(L1 - L2);\n"
		s += "        if (r > (L1 + L2))\n"
		s += "            r = L1 + L2;\n"
		s += "    }\n"
		s += "    c2 = (r * r - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);\n"
		s += "    if (c2 > 1.0f) c2 = 1.0f;\n"
		s += "    if (c2 < -1.0f) c2 = -1.0f;\n"
		s += "    t2 = acos(c2);\n"
		s += "    t1 = atan2(y, x) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));\n"
		s += "    jointAngle[0] = t1 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[1] = t2 * 180.0f / 3.14159265f;\n"
	elif config_type == 1:
		# 3 轴：底座 + 2 连杆
		s += "    float r, c2, t1, t2, t0, rz, scale;\n"
		s += "    ik_reachable = 1;\n"
		s += "    // === 3 轴逆解（底座旋转 + 2连杆平面）===\n"
		s += "    t0 = atan2(y, x);\n"
		s += "    r = sqrt(x * x + y * y);\n"
		s += "    rz = sqrt(r * r + z * z);\n"
		s += "    // (r, z) 平面可达性\n"
		s += "    if (rz < fabs(L1 - L2) || rz > (L1 + L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        if (rz < fabs(L1 - L2))\n"
		s += "        {\n"
		s += "            scale = fabs(L1 - L2) / rz;\n"
		s += "            r *= scale; z *= scale; rz = fabs(L1 - L2);\n"
		s += "        }\n"
		s += "        if (rz > (L1 + L2))\n"
		s += "        {\n"
		s += "            scale = (L1 + L2) / rz;\n"
		s += "            r *= scale; z *= scale; rz = L1 + L2;\n"
		s += "        }\n"
		s += "    }\n"
		s += "    c2 = (r * r + z * z - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);\n"
		s += "    if (c2 > 1.0f) c2 = 1.0f;\n"
		s += "    if (c2 < -1.0f) c2 = -1.0f;\n"
		s += "    t2 = acos(c2);\n"
		s += "    t1 = atan2(z, r) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));\n"
		s += "    jointAngle[0] = t0 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[1] = t1 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[2] = t2 * 180.0f / 3.14159265f;\n"
	else:
		# 4 轴：3 轴 + 腕部
		s += "    float r, c2, t1, t2, t0, t3, rz, scale, phi_rad;\n"
		s += "    ik_reachable = 1;\n"
		s += "    // === 4 轴逆解（底座 + 2连杆 + 腕部俯仰）===\n"
		s += "    t0 = atan2(y, x);\n"
		s += "    r = sqrt(x * x + y * y);\n"
		s += "    rz = sqrt(r * r + z * z);\n"
		s += "    if (rz < fabs(L1 - L2) || rz > (L1 + L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        if (rz < fabs(L1 - L2))\n"
		s += "        {\n"
		s += "            scale = fabs(L1 - L2) / rz;\n"
		s += "            r *= scale; z *= scale; rz = fabs(L1 - L2);\n"
		s += "        }\n"
		s += "        if (rz > (L1 + L2))\n"
		s += "        {\n"
		s += "            scale = (L1 + L2) / rz;\n"
		s += "            r *= scale; z *= scale; rz = L1 + L2;\n"
		s += "        }\n"
		s += "    }\n"
		s += "    c2 = (r * r + z * z - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);\n"
		s += "    if (c2 > 1.0f) c2 = 1.0f;\n"
		s += "    if (c2 < -1.0f) c2 = -1.0f;\n"
		s += "    t2 = acos(c2);\n"
		s += "    t1 = atan2(z, r) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));\n"
		s += "    // 腕部：保持末端姿态角 φ（度）\n"
		s += "    phi_rad = phi * 3.14159265f / 180.0f;\n"
		s += "    t3 = phi_rad - (t1 + t2);\n"
		s += "    jointAngle[0] = t0 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[1] = t1 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[2] = t2 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[3] = t3 * 180.0f / 3.14159265f;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ReadControllerInputs
func _gen_read_inputs(_cfg: Dictionary) -> String:
	var s: String = ""
	s += "void ReadControllerInputs()\n"
	s += "{\n"
	s += "    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);\n"
	s += "    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);\n"
	s += "    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);\n"
	s += "    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);\n"
	s += "    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)\n"
	s += "        valueOfRoker[0][0] = 0;\n"
	s += "    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)\n"
	s += "        valueOfRoker[0][1] = 0;\n"
	s += "    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)\n"
	s += "        valueOfRoker[1][0] = 0;\n"
	s += "    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)\n"
	s += "        valueOfRoker[1][1] = 0;\n"
	s += "    for (i = 0; i < 3; i++)\n"
	s += "    {\n"
	s += "        for (j = 0; j < 4; j++)\n"
	s += "        {\n"
	s += "            if (i == 2 && j >= 2)\n"
	s += "                break;\n"
	s += "            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);\n"
	s += "        }\n"
	s += "    }\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CheckPresetKeys
func _gen_check_preset_keys(_presets: Array, _jc: int) -> String:
	var s: String = ""
	s += "/// @brief 预设点位按键检测：按下时把末端目标设为该点位坐标\n"
	s += "/// @return 1=命中预设点位（本周期跳过摇杆/按键增量），0=未命中\n"
	s += "uint8_t CheckPresetKeys()\n"
	s += "{\n"
	s += "    for (i = 0; i < PRESET_COUNT; i++)\n"
	s += "    {\n"
	s += "        if (RcKeyValueRead(presetKey[i]))\n"
	s += "        {\n"
	s += "            targetX = presetPos[i][0];\n"
	s += "            targetY = presetPos[i][1];\n"
	s += "            targetZ = presetPos[i][2];\n"
	s += "            targetPhi = presetPos[i][3];\n"
	s += "            return 1;\n"
	s += "        }\n"
	s += "    }\n"
	s += "    return 0;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CalculateIK
func _gen_calculate_ik(cfg: Dictionary) -> String:
	var jc: int = cfg.get("joint_count", 2)
	var s: String = ""
	s += "/// @brief 摇杆/按键输入末端位置增量 -> 逆解算\n"
	s += "/// @param presetHit 1=本周期已由预设点位设定目标，跳过增量累加\n"
	s += "/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，\n"
	s += "///       松开后末端保持当前位置不动\n"
	s += "void CalculateIK(uint8_t presetHit)\n"
	s += "{\n"
	s += "    float lastX, lastY, lastZ;\n"
	s += "    // 备份上次目标，越界时回退（防止 target 无限增长导致松手后回不来）\n"
	s += "    lastX = targetX; lastY = targetY; lastZ = targetZ;\n"
	s += "    if (!presetHit)\n"
	s += "    {\n"
	s += _indent_block(_build_joy_mapping(cfg))
	s += _indent_block(_build_keymove_mapping(cfg, jc))
	s += "    }\n"
	s += "    ik_solve(targetX, targetY, targetZ, targetPhi);\n"
	s += "    // 越界则回退本周期增量，末端停在可达边界内\n"
	s += "    if (!ik_reachable && !presetHit)\n"
	s += "    {\n"
	s += "        targetX = lastX; targetY = lastY; targetZ = lastZ;\n"
	s += "        ik_solve(targetX, targetY, targetZ, targetPhi);\n"
	s += "    }\n"
	s += "}\n\n"
	return s


## 给生成的代码块每行加 4 空格缩进（用于嵌入 if 块内）
func _indent_block(block: String) -> String:
	if block.is_empty():
		return ""
	var out: String = ""
	for line in block.split("\n"):
		if line.is_empty():
			continue
		out += "    " + line + "\n"
	return out


## 摇杆映射代码生成（增量累积模式）
func _build_joy_mapping(cfg: Dictionary) -> String:
	var jc: int = cfg.get("joint_count", 2)
	var s: String = ""
	# joy_x/joy_y/joy_z 选项格式："右X->末端X" 等（左摇杆固定用于底盘移动）
	var joy_x: String = cfg.get("joy_x", "右X->末端X")
	var joy_y: String = cfg.get("joy_y", "右Y->末端Y")
	var joy_z: String = cfg.get("joy_z", "右X->末端Z")
	s += "    // 摇杆增量：摇杆值 -2047~2047 归一化后乘 JOY_SCALE 作为每周期位移\n"
	s += "    targetX += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % _parse_joy_axis(joy_x)
	s += "    targetY += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % _parse_joy_axis(joy_y)
	if jc >= 3:
		s += "    targetZ += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % _parse_joy_axis(joy_z)
	return s


## 按键控制末端移动代码生成（长按持续移动）
func _build_keymove_mapping(cfg: Dictionary, jc: int) -> String:
	var keymove: Array = cfg.get("keymove", [])
	if keymove.is_empty():
		return ""
	var target_names: Array = ["targetX", "targetY", "targetZ"]
	var axis_labels: Array = ["X", "Y", "Z"]
	var s: String = ""
	var has_any: bool = false
	for i in range(min(keymove.size(), 3)):
		# 2 轴构型无 Z 轴
		if jc < 3 and i == 2:
			continue
		var plus_key: String = keymove[i].get("plus", "不使用")
		var minus_key: String = keymove[i].get("minus", "不使用")
		if plus_key == "不使用" and minus_key == "不使用":
			continue
		if not has_any:
			s += "    // 按键增量：长按时每周期移动 KEYMOVE_SPEED mm\n"
			has_any = true
		if plus_key != "不使用":
			s += "    if (RcKeyValueRead(%s))\n" % _key_name_to_offset(plus_key)
			s += "        %s += KEYMOVE_SPEED; // 末端%s 正向（按键 %s）\n" % [target_names[i], axis_labels[i], plus_key]
		if minus_key != "不使用":
			s += "    if (RcKeyValueRead(%s))\n" % _key_name_to_offset(minus_key)
			s += "        %s -= KEYMOVE_SPEED; // 末端%s 负向（按键 %s）\n" % [target_names[i], axis_labels[i], minus_key]
	return s


## 解析摇杆选项文本 -> [rocker_idx, axis_idx]
## 左摇杆固定用于底盘移动，末端控制只用右摇杆（rocker_idx=1）
## "右X->末端X" -> [1, 0]; "右Y->末端X" -> [1, 1]
func _parse_joy_axis(text: String) -> Array:
	var rocker: int = 1 # 固定右摇杆（左摇杆用于底盘）
	var axis: int = 0
	if "X" in text:
		axis = 0
	elif "Y" in text:
		axis = 1
	return [rocker, axis]


# ------------------------------------------------------------------ ApplyServoControl
func _gen_apply_servo_control(joints: Array, jc: int) -> String:
	var s: String = ""
	s += "/// @brief 应用舵机控制：关节角度 -> 占空比 -> 发送\n"
	s += "void ApplyServoControl()\n"
	s += "{\n"
	s += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	s += "        dutyOfServo[i] = angle_to_duty(i, jointAngle[i]);\n"
	# 构建 ExpansionBoradControl 调用
	# 扩展板槽位（P60~P77）走 ExpansionBoradControl，主控板 MP03/MP74 走 PWM_SET_Frequency
	var exp_slots: Dictionary = {} # slot -> joint_idx
	var main_pwm: Array = [] # [{joint_idx, pwm_ch}]
	for i in range(jc):
		var pin: String = joints[i].get("io", "P60")
		var slot: int = _io_to_exp_slot(pin)
		if slot >= 0:
			exp_slots[slot] = i
		else:
			# 主控板 PWM（MP03/MP74）
			var pwm_ch: String = _pin_to_pwm_channel(pin)
			main_pwm.append({"joint": i, "ch": pwm_ch})
	# 扩展板控制
	if exp_slots.size() > 0:
		s += "    // 扩展板舵机控制（频率 50Hz）\n"
		# Duty_Change_Order：8 个槽位占空比
		var duty_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			duty_vals[slot] = "dutyOfServo[%d]" % exp_slots[slot]
		var duty_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [duty_vals[0], duty_vals[1], duty_vals[2], duty_vals[3], duty_vals[4], duty_vals[5], duty_vals[6], duty_vals[7]]
		s += "    ExpansionBoradControl(Duty_Change_Order,\n"
		s += "                          %s);\n" % duty_str
		s += "    Ms_Delay(5);\n"
	# 主控板 PWM 控制
	if main_pwm.size() > 0:
		s += "    // 主控板舵机控制（PWM）\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			s += "    PWM_SET_Frequency(%s, 50, dutyOfServo[%d]);\n" % [pwm_ch, ji]
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ All_Init
func _gen_all_init(joints: Array, jc: int) -> String:
	var s: String = ""
	s += "void All_Init()\n"
	s += "{\n"
	s += "    Board_Init();\n"
	s += "    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);\n"
	s += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);\n"
	s += "    remote_control_init();\n"
	s += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);\n"
	s += "    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);\n"
	# 扩展板初始化：各舵机槽位频率 50Hz
	var exp_slots: Array = []
	var main_pwm: Array = []
	for i in range(jc):
		var pin: String = joints[i].get("io", "P60")
		var slot: int = _io_to_exp_slot(pin)
		if slot >= 0:
			exp_slots.append(slot)
		else:
			main_pwm.append({"ch": _pin_to_pwm_channel(pin), "joint": i})
	if exp_slots.size() > 0:
		# 构建 Init_Order：舵机槽位频率 50，其余 0（维持原状）
		var init_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots:
			init_vals[slot] = "50"
		var init_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [init_vals[0], init_vals[1], init_vals[2], init_vals[3], init_vals[4], init_vals[5], init_vals[6], init_vals[7]]
		s += "    // 扩展板舵机初始化（频率 50Hz）\n"
		s += "    ExpansionBoradControl(Init_Order,\n"
		s += "                          %s);\n" % init_str
		s += "    Ms_Delay(20);\n"
		# 方向初始化
		var dir_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		# 按关节方向填充对应槽位
		for i in range(jc):
			var pin: String = joints[i].get("io", "P60")
			var slot: int = _io_to_exp_slot(pin)
			if slot >= 0:
				var d: int = 1 if joints[i].get("dir", "正向") == "正向" else 0
				dir_vals[slot] = str(d)
		var dir_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [dir_vals[0], dir_vals[1], dir_vals[2], dir_vals[3], dir_vals[4], dir_vals[5], dir_vals[6], dir_vals[7]]
		s += "    // 扩展板方向初始化\n"
		s += "    ExpansionBoradControl(Dir_Change_Order,\n"
		s += "                          %s);\n" % dir_str
		s += "    Ms_Delay(5);\n"
	# 主控板 PWM 初始化
	if main_pwm.size() > 0:
		s += "    // 主控板舵机 PWM 初始化\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			# 初始占空比 = 零点角度对应的占空比
			s += "    PWM_Init(%s, 50, angle_to_duty(%d, jointZero[%d]));\n" % [pwm_ch, ji, ji]
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ExpansionBoradControl
func _gen_expansion_board_func() -> String:
	var s: String = ""
	s += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	s += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	s += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	s += "                           uint16_t data_p77)\n"
	s += "{\n"
	s += "    uint8_t i = 0;\n"
	s += "    uint8_t control_frame_pack[21] = {0};\n"
	s += "    control_frame_pack[0] = COMM_HEADER_1;\n"
	s += "    control_frame_pack[1] = COMM_HEADER_2;\n"
	s += "    control_frame_pack[19] = COMM_END_1;\n"
	s += "    control_frame_pack[20] = COMM_END_2;\n"
	s += "    control_frame_pack[2] = control_cmd;\n"
	s += "    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);\n"
	s += "    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);\n"
	s += "    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);\n"
	s += "    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);\n"
	s += "    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);\n"
	s += "    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);\n"
	s += "    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);\n"
	s += "    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);\n"
	s += "    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);\n"
	s += "    for (i = 0; i < 21; i++)\n"
	s += "        UART_PutChar(UART_1, control_frame_pack[i]);\n"
	s += "}\n"
	return s


# ------------------------------------------------------------------ 工具
func _config_type_name(t: int) -> String:
	match t:
		0: return "2轴平面（大臂+小臂）"
		1: return "3轴（底座旋转+2连杆）"
		2: return "4轴（3轴+腕部俯仰）"
	return "未知"


func _to_float(s: String, default: float) -> float:
	s = s.strip_edges()
	if s.is_empty():
		return default
	if s.is_valid_float():
		return s.to_float()
	return default

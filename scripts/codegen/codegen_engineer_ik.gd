class_name CodeGenEngineerIK
extends CodeGenBase

## 工程机器人逆解算代码生成器。
## 根据配置字典生成工程机械臂逆解算 main.c 代码。
## 支持 2/3/4 轴全舵机构型，解析解（atan2 + 余弦定理）。
## 预设点位在 GDScript 端预计算为关节角度，写入 C const 数组（避免运行时重复算）；
## 摇杆实时模式则调用运行时 IK 函数。


# 舵机 50Hz 占空比参数继承自 CodeGenBase（SERVO_DUTY_MIN/MID/MAX）
# 角度约定：以舵机中位为 0°，行程 ±90°（对应物理 0~180°）
# duty/度 线性系数：整个 duty 跨度对应 180°
const SERVO_DUTY_PER_DEG: float = float(SERVO_DUTY_MAX - SERVO_DUTY_MIN) \
	/ float(SERVO_MAX_OFFSET_DEG * 2)
# 关节角可表达边界（度）
const JOINT_ANGLE_MIN: float = -90.0
const JOINT_ANGLE_MAX: float = 90.0
# 逆解可达性判定的最小半径，避免除零（与生成的 C 宏 IK_EPS 同值）
const IK_EPS: float = 0.001
# 关节数上限 = 6。
#
# 注意：瓶颈不是算力。真机实测（STC32G @33.1776MHz）雅可比 IK 单次耗时
# 2 关节 54.7μs / 4 关节 116.7μs / 6 关节 196.8μs，线性拟合约 13μs + 30.6μs×n。
# 主循环 10ms 减去扩展板发送 5ms，留给逆解约 4ms，理论可撑上百个关节，
# 6 关节仅占预算 5%。（早先按 8051 软浮点估的 0.2~0.3ms/关节错了一个数量级。）
#
# 6 这个上限的真实依据：
#   1. 舵机口只有 10 个（扩展板 P60/P62/P64/P66/P74~P77 + 主控板 MP03/MP74），
#      6 关节 + 1 夹爪才装得下
#   2. 手动遥控 6 个自由度已经很难操作
#   3. C251 单函数局部变量段上限 128 字节：FK 中间结果必须声明成
#      static xdata，否则 4 关节就报 "segment too big (act=287, max=128)"
const MAX_JOINTS: int = 6
# 主循环周期(ms)：ExpansionBoradControl 之后的延时也计入其中
const LOOP_PERIOD_MS: int = 10
# 发送板间指令后必须留给硬件的响应延时(ms)
const EXP_SEND_DELAY_MS: int = 5


# ------------------------------------------------------------------ 代码生成
## 基于配置字典生成完整的 main.c 代码字符串
func generate(cfg: Dictionary) -> String:
	var config_type: int = cfg.get("config_type", 0) # 0=2轴, 1=3轴, 2=4轴
	var jc: int = cfg.get("joint_count", 2)
	var joints: Array = cfg.get("joints", [])
	# 连杆长度：配置界面已迁移为逐关节 len，这里折算回旧解析路径要用的 L1/L2/L3。
	# 阶段二换成雅可比 IK 后旧路径连同 L1/L2/L3 一起去掉。
	var lens_pack: Array = legacy_link_lengths(cfg)
	var l1: float = lens_pack[0]
	var l2: float = lens_pack[1]
	var l3: float = lens_pack[2]
	var presets: Array = cfg.get("presets", [])
	var joy_scale: float = _to_float(cfg.get("joy_scale", "5"), 5.0)
	var keymove_speed: float = _to_float(cfg.get("keymove_speed", "2"), 2.0)
	# 姿态角按键步长：沿用位移步长的数值，单位改为度
	var keymove_phi_speed: float = keymove_speed
	# 肘部分支：由「弯曲关节」的初始角正负决定，保证正解起点与逆解自洽
	var elbow_sign: float = _elbow_sign(joints, config_type)
	# 启用的预设点位数量（0 时不生成预设相关数组与查询循环）
	var preset_count: int = _active_presets(presets).size()
	# 逐关节转轴与连杆长度：雅可比逆解算的全部输入
	var kin_lens: Array = joint_lengths(joints, jc, config_type, l1, l2, l3)
	# 末端俯仰角是否作为控制量。判据是构形能否「位置不动、只转 φ」，
	# 不是关节数 —— 四个关节全 Pitch 时 φ 同样不可控。
	# φ 不可控时整条 φ 链路（目标变量、形参、按键映射）都不生成，
	# 否则 C251 会报未引用参数警告，学生也会以为这个输入有效。
	var use_phi: bool = _phi_controllable(joints, jc, config_type, l1, l2, l3)
	var tvars: Array = _target_vars_for(jc, use_phi)

	var code: String = ""
	code += "// 工程机器人逆解算代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "// ========================= 参数区 =========================\n"
	code += "// 关节数：%d。各关节的转轴与连杆长度见下方 jointAxis / jointLen 两张表。\n" % jc
	code += "// 逆解算是通用的雅可比法，不假定任何特定构型。\n"
	code += "#define JOINT_COUNT %d\n" % jc
	code += "// 逆解算除零保护阈值\n"
	code += "#define IK_EPS  0.001f\n"
	code += "// 弧度与度的换算\n"
	code += "#define DEG_TO_RAD  0.0174532925f\n"
	code += "#define RAD_TO_DEG  57.29577951f\n"
	code += "// 逆解单步最大转动量(度)：防大误差时末端猛冲，也避免线性近似失效\n"
	code += "#define IK_MAX_STEP_DEG  %.1ff\n" % JACOBI_MAX_STEP_DEG
	if use_phi:
		code += "// 姿态误差权重(mm/rad)，取连杆总长：\n"
		code += "// 让 1 弧度的俯仰角误差与一个臂长的位置误差等重，两者才能相加\n"
		code += "#define PHI_WEIGHT  %.2ff\n" % _pitch_weight(kin_lens)
	code += "// 舵机占空比参数（50Hz）\n"
	code += "// 关节角以舵机中位为 0°，行程 ±90°（对应物理 0~180°）\n"
	code += "#define SERVO_MID_DUTY  %d   // 0°\n" % SERVO_DUTY_MID
	code += "#define SERVO_MIN_DUTY  %d   // -%d°\n" % [SERVO_DUTY_MIN, SERVO_MAX_OFFSET_DEG]
	code += "#define SERVO_MAX_DUTY  %d  // +%d°\n" % [SERVO_DUTY_MAX, SERVO_MAX_OFFSET_DEG]
	code += "#define SERVO_DUTY_PER_DEG  %.4ff\n" % SERVO_DUTY_PER_DEG
	code += "// 摇杆推到满偏时末端每周期位移(mm)\n"
	code += "#define JOY_SCALE  %.2ff\n" % joy_scale
	code += "// 按键长按时末端每周期位移(mm)\n"
	code += "#define KEYMOVE_SPEED  %.2ff\n" % keymove_speed
	if use_phi:
		code += "// 按键长按时末端俯仰角每周期变化(度)\n"
		code += "#define KEYMOVE_PHI_SPEED  %.2ff\n" % keymove_phi_speed
	# 注：关节限位夹紧在 angle_to_duty 内直接比较，无需 LIMIT_VALUE 宏
	code += _build_protocol_macros()
	# NRF24L01 通信通道（nrf24l01.c 通过 extern 引用，必须在此定义）
	code += "uint8_t Channal = 36;                          // NRF24L01 通信通道（0-125），与遥控器一致\n"
	code += "// 自定义变量\n"
	code += "uint16_t dutyOfServo[%d];       // 各关节舵机占空比\n" % jc
	code += "float    jointAngle[%d];        // 各关节角度(度)\n" % jc
	code += "float    %s;\n" % ", ".join(tvars)
	code += "uint8_t  ik_reachable;          // 逆解算可达性标志(1=本步在靠近目标,0=已贴到极限)\n"
	code += "uint8_t  presetHit;             // 本周期是否命中预设点位\n"
	code += "int16_t  valueOfRoker[2][2];    // 左摇杆水平、竖直；右摇杆水平、竖直\n"
	code += "uint16_t deadBandOfLeft = 10;\n"
	code += "uint16_t deadBandOfRight = 10;\n"
	code += "uint8_t  i;\n"
	# 关节配置常量数组（初始角/限位/IO 槽位）
	code += _build_joint_config_arrays(joints, jc)
	# 运动学常量表：逆解算完全由转轴与连杆长度两张表驱动
	code += _build_kinematics_arrays(joints, jc, config_type, l1, l2, l3)
	# 逆解算中间结果（必须在 xdata，见函数内注释）
	code += _gen_ik_workspace(jc)
	# 预设点位表（末端坐标，附 GUI 端预计算的关节角度注释）
	code += _build_preset_table(presets, jc, l1, l2, l3, config_type, elbow_sign,
		joints)
	code += "\n"
	# 函数声明
	code += "void All_Init();\n"
	code += "void ReadControllerInputs();\n"
	code += "void CalculateIK(uint8_t hit);\n"
	code += "void ApplyServoControl();\n"
	if preset_count > 0:
		code += "uint8_t CheckPresetKeys();\n"
	code += "uint16_t angle_to_duty(int joint, float angle);\n"
	code += "void mat_vec(float m[3][3], float v[3], float out[3]);\n"
	code += "void axis_rot(float a[3], float ang, float m[3][3]);\n"
	code += "void mat_mul(float x[3][3], float y[3][3], float out[3][3]);\n"
	code += "void ik_fk();\n"
	code += "void ik_solve(%s);\n" % _ik_params_for(jc, use_phi)
	if jc >= 3:
		code += "uint8_t ik_target_too_far(float x, float y, float z);\n"
	else:
		code += "uint8_t ik_target_too_far(float x, float y);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	# --- main() ---
	# 增量模式：target 必须初始化为初始姿态对应的末端位置（正运动学预计算）。
	# 用通用 fk_chain 而非旧的 _forward_kinematics：φ 的定义已改为末端仰角，
	# 旧函数算的是 θ1+θ2+θ3，两者在混合转轴构形下不是一回事。
	var home: Array = _home_targets(joints, jc, config_type, l1, l2, l3, use_phi)
	# 主控板舵机发送耗时可忽略，扩展板每次发送后需 EXP_SEND_DELAY_MS 延时
	var has_exp: bool = _has_exp_slot(joints, jc)
	var tail_delay: int = LOOP_PERIOD_MS - (EXP_SEND_DELAY_MS if has_exp else 0)
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	code += "    // 初始化各关节到初始角度\n"
	code += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	code += "        jointAngle[i] = jointHome[i];\n"
	code += "    // 增量模式起点：初始姿态对应的末端位置（GUI 端正运动学预计算）\n"
	var home_inits: Array = []
	for k in range(tvars.size()):
		home_inits.append("%s = %.2ff;" % [tvars[k], home[k]])
	code += "    %s\n" % " ".join(home_inits)
	code += "    ik_reachable = 1;\n"
	code += "    while (1)\n"
	code += "    {\n"
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n"
	code += "        ReadControllerInputs();\n"
	if preset_count > 0:
		code += "        presetHit = CheckPresetKeys(); // 预设点位按键检测\n"
	else:
		code += "        presetHit = 0;                 // 未配置预设点位\n"
	code += "        CalculateIK(presetHit);        // 摇杆/按键增量 + 逆解算\n"
	code += "        ApplyServoControl();           // 应用舵机控制\n"
	code += "        Ms_Delay(%d);                   // 与舵机发送延时合计 %dms/周期\n" % [tail_delay, LOOP_PERIOD_MS]
	code += "    }\n"
	code += "}\n\n"

	# --- angle_to_duty ---
	code += _gen_angle_to_duty()
	# --- 运动学辅助函数与雅可比逆解 ---
	code += _gen_kinematics_helpers()
	code += _gen_ik_fk()
	code += _gen_ik_solve_jacobian(jc, use_phi, kin_lens)
	# --- ReadControllerInputs ---
	code += _gen_read_inputs()
	# --- CheckPresetKeys ---
	if preset_count > 0:
		code += _gen_check_preset_keys(jc, use_phi)
	# --- CalculateIK ---
	code += _gen_target_too_far(jc, kin_lens)
	code += _gen_calculate_ik(cfg, use_phi)
	# --- ApplyServoControl ---
	code += _gen_apply_servo_control(joints, jc, has_exp)
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


# ------------------------------------------------------------------ 关节配置数组
func _build_joint_config_arrays(joints: Array, jc: int) -> String:
	var offsets: Array = joint_offsets(joints, jc)
	var s: String = ""
	s += "// 各关节安装中位朝向(度，运动学角)：舵机处于中位时该关节的实际朝向。\n"
	s += "// 舵机盘装歪时填这里，逆解算不受影响，只在 angle_to_duty 里换算掉。\n"
	s += "const float jointOffset[%d] = {" % jc
	for i in range(jc):
		if i > 0:
			s += ", "
		s += "%.2ff" % offsets[i]
	s += "};\n"
	s += "// 各关节初始角度(度，运动学角)\n"
	s += "const float jointHome[%d] = {" % jc
	for i in range(jc):
		var zero: float = _to_float(joints[i].get("zero", "0"), 0.0)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(zero, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "// 各关节限位(度，运动学角) [min, max]，可表达范围 = 中位朝向 ±%d°\n" \
		% SERVO_MAX_OFFSET_DEG
	s += "const float jointMin[%d] = {" % jc
	for i in range(jc):
		var mn: float = _to_float(joints[i].get("min", str(JOINT_ANGLE_MIN)), JOINT_ANGLE_MIN)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(mn, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "const float jointMax[%d] = {" % jc
	for i in range(jc):
		var mx: float = _to_float(joints[i].get("max", str(JOINT_ANGLE_MAX)), JOINT_ANGLE_MAX)
		if i > 0:
			s += ", "
		s += "%.2ff" % clampf(mx, offsets[i] + JOINT_ANGLE_MIN, offsets[i] + JOINT_ANGLE_MAX)
	s += "};\n"
	s += "// 各关节方向(1=正向, 0=反向)，仅在 angle_to_duty 中生效\n"
	s += "const uint8_t jointDir[%d] = {" % jc
	for i in range(jc):
		var d: int = 1 if joints[i].get("dir", "正向") == "正向" else 0
		if i > 0:
			s += ", "
		s += str(d)
	s += "};\n"
	return s


# ------------------------------------------------------------------ 运动学常量表
## 转轴与连杆长度表。逆解算完全由这两张表驱动，
## 关节数与转轴搭配的差异全部落在数据里，代码本身不变。
func _build_kinematics_arrays(joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> String:
	var axis_names: Array = joint_axes(joints, jc, config_type)
	var lens: Array = joint_lengths(joints, jc, config_type, l1, l2, l3)
	var s: String = ""
	s += "// 各关节转轴（关节局部坐标系，连杆沿局部 +X 伸出）：\n"
	s += "//   Yaw=(0,0,1) 左右摆 / Pitch=(0,-1,0) 上下俯仰 / Roll=(1,0,0) 绕自身轴自转\n"
	s += "const float jointAxis[%d][3] = {\n" % jc
	for i in range(jc):
		var v: Vector3 = AXIS_VECTORS[axis_names[i]]
		s += "    {%.1ff, %.1ff, %.1ff}" % [v.x, v.y, v.z]
		if i < jc - 1:
			s += ","
		s += "   // 关节%d %s\n" % [i + 1, axis_names[i]]
	s += "};\n"
	s += "// 各关节之后的连杆长度(mm)。最后一个是末端到夹爪的距离。\n"
	s += "const float jointLen[%d] = {" % jc
	for i in range(jc):
		if i > 0:
			s += ", "
		s += "%.2ff" % 100.0
	s += "};\n"
	return s


# ------------------------------------------------------------------ 预设点位
## 过滤出启用的预设点位
func _active_presets(presets: Array) -> Array:
	var active: Array = []
	for p in presets:
		if p.get("enabled", false):
			active.append(p)
	return active


## 预设点位表：存末端坐标，附 GUI 端预计算的关节角度注释便于人工核对
func _build_preset_table(presets: Array, jc: int, l1: float, l2: float, l3: float,
		config_type: int, elbow_sign: float, joints: Array = []) -> String:
	var active: Array = _active_presets(presets)
	var count: int = active.size()
	var s: String = ""
	s += "// 预设点位数量\n"
	s += "#define PRESET_COUNT %d\n" % count
	if count == 0:
		# C89 不允许零长数组，未配置预设点位时不生成任何相关数组
		s += "// 未配置预设点位，故不生成 presetKey / presetPos 数组\n"
		return s
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
		# 附上 GUI 端预计算的关节角度作为注释，便于人工核对。
		# 用雅可比数值解并从初始角起解，与真机上电后的收敛过程一致。
		var conv: Dictionary = solve_ik_jacobian_converge(Vector3(x, y, z), phi,
			_joint_home_angles(joints), joints, jc, config_type, l1, l2, l3)
		var angles: Array = conv["angles"]
		var ang_str: String = ""
		for k in range(jc):
			if k > 0:
				ang_str += ", "
			ang_str += "%.1f" % float(angles[k])
		s += "  // P%d 关节角度: [%s] 误差 %.1fmm\n" \
			% [i + 1, ang_str, float(conv["err"])]
	s += "};\n"
	return s


# ------------------------------------------------------------------ GDScript 端 IK 预计算
## 与 C 端 ik_solve 公式保持一致，用于预计算预设点位角度与静态检查
## 返回各关节角度（度），长度补齐到 jc
func solve_ik(x: float, y: float, z: float, phi: float, l1: float, l2: float, l3: float,
		config_type: int, jc: int, elbow_sign: float) -> Array:
	var angles: Array = []
	if config_type == 0:
		# 2 轴平面
		var r: float = sqrt(x * x + y * y)
		var c2: float = (r * r - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = elbow_sign * acos(c2)
		var t1: float = atan2(y, x) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t1), rad_to_deg(t2)]
	elif config_type == 1:
		# 3 轴：底座 + 2 连杆
		var t0: float = atan2(y, x)
		var r: float = sqrt(x * x + y * y)
		var c2: float = (r * r + z * z - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = elbow_sign * acos(c2)
		var t1: float = atan2(z, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2)]
	else:
		# 4 轴：先沿末端姿态角 φ 回退 L3 得到腕心，再对腕心做 3 轴逆解
		var t0: float = atan2(y, x)
		var phi_rad: float = deg_to_rad(phi)
		var r_end: float = sqrt(x * x + y * y)
		var r: float = r_end - l3 * cos(phi_rad)
		var zw: float = z - l3 * sin(phi_rad)
		var c2: float = (r * r + zw * zw - l1 * l1 - l2 * l2) / (2.0 * l1 * l2)
		c2 = clamp(c2, -1.0, 1.0)
		var t2: float = elbow_sign * acos(c2)
		var t1: float = atan2(zw, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		var t3: float = phi_rad - (t1 + t2)
		angles = [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2), rad_to_deg(t3)]
	# 补齐到 jc 个元素
	while angles.size() < jc:
		angles.append(0.0)
	return angles


# ------------------------------------------------------------------ 逆解（复现 C 端钳位）
## 与 C 端 ik_solve 逐行对应的版本：包含半径钳位、IK_EPS 除零保护与可达性标志。
## 上面的 solve_ik 只夹紧 c2（用于预设点位注释，保持历史产物字节一致），
## 3D 仿真必须用这一版才能复现真机行为。
## 返回 {"angles": Array[float], "reachable": bool}
func solve_ik_checked(x: float, y: float, z: float, phi: float, l1: float, l2: float, l3: float,
		config_type: int, jc: int, elbow_sign: float) -> Dictionary:
	var reachable: bool = true
	var reach_min: float = abs(l1 - l2)
	var reach_max: float = l1 + l2
	var angles: Array = []
	if config_type == 0:
		# === 2 轴平面逆解 ===
		var r: float = sqrt(x * x + y * y)
		if r < reach_min:
			reachable = false
			r = reach_min
		elif r > reach_max:
			reachable = false
			r = reach_max
		var c2: float = clamp((r * r - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0)
		var t2: float = elbow_sign * acos(c2)
		var t1: float = atan2(y, x) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t1), rad_to_deg(t2)]
	else:
		# === 3 轴（底座 + 2 连杆）/ 4 轴（再加腕部俯仰）逆解 ===
		var is4: bool = config_type >= 2
		var t0: float = atan2(y, x)
		var r: float = sqrt(x * x + y * y)
		var zw: float = z
		var phi_rad: float = 0.0
		if is4:
			# 腕心 = 末端沿姿态角 φ 回退 L3
			phi_rad = deg_to_rad(phi)
			r -= l3 * cos(phi_rad)
			zw -= l3 * sin(phi_rad)
		var rz: float = sqrt(r * r + zw * zw)
		if rz < IK_EPS:
			# rz 过小时无方向可依，退到内边界正前方（与 C 端一致）
			reachable = false
			r = reach_min
			zw = 0.0
			if r < IK_EPS:
				r = reach_max
		elif rz < reach_min:
			reachable = false
			var scale: float = reach_min / rz
			r *= scale
			zw *= scale
		elif rz > reach_max:
			reachable = false
			var scale2: float = reach_max / rz
			r *= scale2
			zw *= scale2
		var c2: float = clamp((r * r + zw * zw - l1 * l1 - l2 * l2) / (2.0 * l1 * l2), -1.0, 1.0)
		var t2: float = elbow_sign * acos(c2)
		var t1: float = atan2(zw, r) - atan2(l2 * sin(t2), l1 + l2 * cos(t2))
		angles = [rad_to_deg(t0), rad_to_deg(t1), rad_to_deg(t2)]
		if is4:
			angles.append(rad_to_deg(phi_rad - (t1 + t2)))
	while angles.size() < jc:
		angles.append(0.0)
	return {"angles": angles, "reachable": reachable}


# ------------------------------------------------------------------ 雅可比转置数值逆解
## 单步步长上限（度）。一个 10ms 周期内单关节最多转这么多，
## 防止大误差时末端猛冲，也避免线性近似在大角度下失效。
const JACOBI_MAX_STEP_DEG: float = 4.0
## 目标可达域的余量系数：只拦「超出臂展 × 该系数」的目标。
## 留余量是为了避免在边界处反复拖拽/回退造成拖影。
const IK_REACH_MARGIN: float = 0.98
## 认为已经收敛的位置误差（mm）。到这个量级就不再动，避免在噪声上抖。
const JACOBI_POS_TOL: float = 0.05
## 判定不可达所需的「误差不下降」连续次数
const JACOBI_STALL_COUNT: int = 3


## 雅可比转置增量逆解：一次调用走一步，靠连续周期收敛。
##
## Δθ = α·Jᵀe，J 第 i 列 = a_i × (p_tip − o_i)。
## 转轴类型只改变 a_i 这个单位向量，公式本身不变 —— 这是它能支持
## 任意 Pitch/Roll/Yaw 搭配的根本原因，也是换掉解析解的理由。
##
## 末端俯仰角 φ 作为第 4 行一起解算（target_phi 传 NAN 表示不控 φ）。
## 姿态误差要乘权重换算成与位置可比的量纲，见 _pitch_weight。
##
## angles: 当前关节角（度，运动学角），会被读取但不修改
## 返回 {
##   "angles": Array[float]  走一步之后的关节角（已按限位钳位）
##   "err": float            走一步之后的位置误差(mm)
##   "phi_err": float        本步之前的 φ 误差(度)，不控 φ 时为 0
##   "reachable": bool       总误差（位置+姿态）是否还在下降，false = 已贴到极限
## }
func solve_ik_jacobian(target: Vector3, target_phi: float, angles: Array,
		joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> Dictionary:
	var cur: Array = []
	for i in range(jc):
		cur.append(float(angles[i]) if i < angles.size() else 0.0)
	var lens: Array = joint_lengths(joints, jc, config_type, l1, l2, l3)
	var use_phi: bool = not is_nan(target_phi)
	var w: float = _pitch_weight(lens)
	var chain: Dictionary = fk_chain(cur, joints, jc, config_type, l1, l2, l3)
	var pts: Array = chain["points"]
	var tip: Vector3 = pts[pts.size() - 1]
	var e: Vector3 = target - tip
	var pos_err: float = e.length()
	var phi_err_deg: float = 0.0
	var g: Array = []
	if use_phi:
		g = pitch_gradient(chain, jc)
		# 梯度退化（末端竖直）时本周期只管位置，下个周期姿态变了自然恢复
		if not g.is_empty():
			phi_err_deg = target_phi - tip_pitch_deg(chain)
	# 已经到位就不动，省得在数值噪声上抖
	if pos_err < JACOBI_POS_TOL and absf(phi_err_deg) < 0.01:
		return {"angles": cur, "err": pos_err, "phi_err": phi_err_deg,
			"reachable": true}
	# Jᵀe：位置三行 + 姿态一行
	var cols: Array = jacobian_columns(chain, jc)
	var phi_err_rad: float = deg_to_rad(phi_err_deg)
	var jte: Array = []
	for i in range(jc):
		var v: float = (cols[i] as Vector3).dot(e)
		if use_phi and not g.is_empty():
			# 两项量纲统一到 mm：g 是 rad/rad，乘 w(mm/rad) 后与位置项可加
			v += float(g[i]) * w * (phi_err_rad * w)
		jte.append(v)
	# α 自适应（最速下降的精确步长）：
	# 沿 Δθ = αJᵀe 走一步后残差是 |e − αJJᵀe|²，对 α 求极小得
	#   α = (e·JJᵀe) / |JJᵀe|² = |Jᵀe|² / |JJᵀe|²
	# 分子是**关节空间**的 |Jᵀe|²，不是任务空间的 |e|²（差好几个数量级，踩过）。
	# 固定 α 不可行：不同臂长/姿态下合适的步长差几个数量级
	# （bench 里那个 0.00002f 只对那一组臂长成立）。
	var jjte: Vector3 = Vector3.ZERO
	var g_dot: float = 0.0
	for i in range(jc):
		jjte += (cols[i] as Vector3) * float(jte[i])
		if use_phi and not g.is_empty():
			g_dot += float(g[i]) * w * float(jte[i])
	var denom: float = jjte.length_squared() + g_dot * g_dot
	var alpha: float = 0.0
	if denom > IK_EPS:
		var num: float = 0.0
		for i in range(jc):
			num += float(jte[i]) * float(jte[i])
		alpha = num / denom
	# 步长限幅：换算成度之后不超过 JACOBI_MAX_STEP_DEG
	var max_step: float = 0.0
	for i in range(jc):
		max_step = maxf(max_step, absf(rad_to_deg(alpha * float(jte[i]))))
	if max_step > JACOBI_MAX_STEP_DEG:
		alpha *= JACOBI_MAX_STEP_DEG / max_step
	var next: Array = []
	for i in range(jc):
		next.append(cur[i] + rad_to_deg(alpha * float(jte[i])))
	# 限位钳位：与 C 端 angle_to_duty 内的夹紧一致
	var clamped: Dictionary = clamp_angles_to_limits(next, joints)
	var out: Array = clamped["angles"]
	# 走完这一步的实际误差，用于判断是否还在靠近目标。
	# 必须把姿态误差一起算进「总误差」：只看位置的话，
	# 那些纯粹在调 φ 的步会被误判成停滞（位置本来就不该变）。
	var chain2: Dictionary = fk_chain(out, joints, jc, config_type, l1, l2, l3)
	var pts2: Array = chain2["points"]
	var new_pos_err: float = (target - (pts2[pts2.size() - 1] as Vector3)).length()
	var before: float = pos_err
	var after: float = new_pos_err
	if use_phi and not g.is_empty():
		# 姿态误差按 w 换算成 mm，与位置误差同量纲后合成
		before = sqrt(pos_err * pos_err + pow(phi_err_rad * w, 2.0))
		var pe2: float = deg_to_rad(target_phi - tip_pitch_deg(chain2))
		after = sqrt(new_pos_err * new_pos_err + pow(pe2 * w, 2.0))
	return {"angles": out, "err": new_pos_err, "phi_err": phi_err_deg,
		"reachable": after < before - 1.0e-4}


## 姿态误差的权重（mm/rad）：取臂总长。
##
## 这样 1 rad 的姿态误差与「一个臂长的位置误差」等重，两者可以相加。
## 不做成用户可调：学生没有量纲直觉，多一个参数就是多一个出错点。
func _pitch_weight(lens: Array) -> float:
	var total: float = 0.0
	for v in lens:
		total += absf(float(v))
	return maxf(total, 1.0)


## 迭代到收敛（GUI 侧预计算预设点位、仿真显示用；真机是每周期走一步）。
## max_iter 上限存在的意义是防止奇异位形附近原地打转。
func solve_ik_jacobian_converge(target: Vector3, target_phi: float,
		angles: Array, joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float, max_iter: int = 200) -> Dictionary:
	var cur: Array = angles.duplicate()
	var last: Dictionary = {}
	var stall: int = 0
	var use_phi: bool = not is_nan(target_phi)
	for _n in range(max_iter):
		last = solve_ik_jacobian(target, target_phi, cur, joints, jc,
			config_type, l1, l2, l3)
		cur = last["angles"]
		# 收敛判据必须同时看位置与姿态。只看位置会在位置一到位就退出，
		# 而此时 φ 往往还差得远（踩过：φ 停在 -53° 而目标 -60°，位置反倒漂了 55mm）
		var done: bool = float(last["err"]) < JACOBI_POS_TOL
		if use_phi:
			done = done and absf(float(last["phi_err"])) < 0.1
		if done:
			break
		# 连续多次不再靠近 => 已经贴到可达域边界或卡在奇异点
		if not bool(last["reachable"]):
			stall += 1
			if stall >= JACOBI_STALL_COUNT:
				break
		else:
			stall = 0
	# 用最终姿态重算一次误差，返回的是「停在哪」而非「上一步之前的误差」
	var chain: Dictionary = fk_chain(cur, joints, jc, config_type, l1, l2, l3)
	var pts: Array = chain["points"]
	var final_err: float = (target - (pts[pts.size() - 1] as Vector3)).length()
	var final_phi_err: float = 0.0
	if not is_nan(target_phi):
		final_phi_err = target_phi - tip_pitch_deg(chain)
	return {"angles": cur, "err": final_err, "phi_err": final_phi_err,
		"reachable": final_err < 1.0}


# ------------------------------------------------------------------ 关节限位钳位
## 复现 C 端 angle_to_duty 内的 jointMin/jointMax 夹紧。
## 钳位发生在逆解之后，故钳位后实际末端 ≠ 目标末端。
## 返回 {"angles": Array[float], "clamped": Array[bool]}
func clamp_angles_to_limits(angles: Array, joints: Array) -> Dictionary:
	var out: Array = []
	var clamped: Array = []
	for i in range(angles.size()):
		var a: float = angles[i]
		var lo: float = JOINT_ANGLE_MIN
		var hi: float = JOINT_ANGLE_MAX
		if i < joints.size():
			lo = _to_float(joints[i].get("min", ""), JOINT_ANGLE_MIN)
			hi = _to_float(joints[i].get("max", ""), JOINT_ANGLE_MAX)
		var c: float = clamp(a, lo, hi)
		out.append(c)
		clamped.append(not is_equal_approx(c, a))
	return {"angles": out, "clamped": clamped}


# ------------------------------------------------------------------ 安装中位朝向
## 各关节的安装中位朝向（度，运动学角）：舵机处于中位时该关节的实际朝向。
## 舵机盘装歪时靠它修正，逆解算本身不受影响。
func joint_offsets(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		if i < joints.size():
			out.append(_to_float(joints[i].get("offset", "0"), 0.0))
		else:
			out.append(0.0)
	return out


## 运动学角 -> 舵机指令角（复现 C 端 angle_to_duty 里的减法）。
## 返回 {"angles": Array[float], "over_travel": Array[bool]}，
## over_travel 标记该关节超出舵机 ±90° 行程（装歪导致够不到）。
func servo_angles(angles: Array, joints: Array) -> Dictionary:
	var offsets: Array = joint_offsets(joints, angles.size())
	var out: Array = []
	var over: Array = []
	for i in range(angles.size()):
		var s: float = float(angles[i]) - offsets[i]
		out.append(s)
		over.append(s < JOINT_ANGLE_MIN or s > JOINT_ANGLE_MAX)
	return {"angles": out, "over_travel": over}


# ------------------------------------------------------------------ 肘部分支
## 弯曲关节（2轴=关节2，3/4轴=关节3）的初始角为负时，逆解取负分支，
## 否则正运动学起点反解回来会得到镜像姿态，上电首帧关节跳变。
func _elbow_sign(joints: Array, config_type: int) -> float:
	var idx: int = 1 if config_type == 0 else 2
	if joints.size() <= idx:
		return 1.0
	var zero: float = _to_float(joints[idx].get("zero", "0"), 0.0)
	return -1.0 if zero < 0.0 else 1.0


# ------------------------------------------------------------------ 正运动学（初始姿态末端位置）
## 由各关节初始角度算出末端位置，作为增量模式的起点
## 返回 [x, y, z, phi]
func _forward_kinematics(joints: Array, l1: float, l2: float, l3: float, config_type: int, _jc: int) -> Array:
	return forward_kinematics_angles(_joint_home_angles(joints), l1, l2, l3, config_type)


## 从关节配置数组里取出初始角度（度）。
## 长度跟随实际关节数（至少 4，便于旧解析路径直接索引 a[3]），缺失补 0
func _joint_home_angles(joints: Array) -> Array:
	var n: int = maxi(min(joints.size(), MAX_JOINTS), 4)
	var out: Array = []
	out.resize(n)
	out.fill(0.0)
	for i in range(min(joints.size(), n)):
		out[i] = _to_float(joints[i].get("zero", "0"), 0.0)
	return out


## 正运动学：关节角度（度，长度≥构型所需）-> 末端 [x, y, z, phi]
## 与 joint_frames 共用同一套连杆链，末端点必然一致
func forward_kinematics_angles(angles: Array, l1: float, l2: float, l3: float,
		config_type: int) -> Array:
	var frames: Array = joint_frames(angles, l1, l2, l3, config_type)
	var tip: Vector3 = frames[frames.size() - 1]
	var a: Array = _pad_angles(angles)
	if config_type == 0:
		# 2 轴平面：末端在 XY 竖直平面内，无姿态角
		return [tip.x, tip.y, 0.0, 0.0]
	elif config_type == 1:
		return [tip.x, tip.y, tip.z, 0.0]
	# 4 轴：φ = θ1+θ2+θ3
	return [tip.x, tip.y, tip.z, a[1] + a[2] + a[3]]


## 关节点链：base -> 肩 -> 肘 -> (腕) -> 末端，机器人坐标系（mm）
## 2 轴构型 (x, y) 是竖直平面、z 恒 0；3/4 轴 (x, y) 是水平面、z 是高度。
## 3D 仿真据此逐段绘制连杆，无需自己再推公式。
func joint_frames(angles: Array, l1: float, l2: float, l3: float, config_type: int) -> Array:
	var a: Array = _pad_angles(angles)
	if config_type == 0:
		# 2 轴平面：θ1=关节1（相对 +X），θ2=关节2（相对大臂）
		var t1: float = deg_to_rad(a[0])
		var t12: float = t1 + deg_to_rad(a[1])
		var p1: Vector3 = Vector3(l1 * cos(t1), l1 * sin(t1), 0.0)
		var p2: Vector3 = p1 + Vector3(l2 * cos(t12), l2 * sin(t12), 0.0)
		return [Vector3.ZERO, p1, p2]
	# 3/4 轴：底座绕 Z 转 θ0，臂在 (r, z) 平面内展开
	var t0: float = deg_to_rad(a[0])
	var t1b: float = deg_to_rad(a[1])
	var t12b: float = t1b + deg_to_rad(a[2])
	var chain: Array = [Vector2.ZERO] # (r, z) 平面内的点链
	chain.append(chain[0] + Vector2(l1 * cos(t1b), l1 * sin(t1b)))
	chain.append(chain[1] + Vector2(l2 * cos(t12b), l2 * sin(t12b)))
	if config_type >= 2:
		# 腕部：φ = θ1+θ2+θ3，末端在腕心外沿 φ 延伸 L3
		var phi: float = t12b + deg_to_rad(a[3])
		chain.append(chain[2] + Vector2(l3 * cos(phi), l3 * sin(phi)))
	# (r, z) -> (x, y, z)：绕底座旋转
	var out: Array = []
	for p in chain:
		out.append(Vector3(p.x * cos(t0), p.x * sin(t0), p.y))
	return out


## 角度数组补齐到 4 个元素（float），便于统一索引
func _pad_angles(angles: Array) -> Array:
	var out: Array = [0.0, 0.0, 0.0, 0.0]
	for i in range(min(angles.size(), 4)):
		out[i] = float(angles[i])
	return out


# ============================================================ 通用正运动学
# 支持每个关节独立选择 Pitch / Roll / Yaw 转轴，不再假定「底座 Yaw + 共面 Pitch」。
# 用户是没有机械基础的大一学生，会造出任意构形的臂，写死构形会导致
# 生成的 C 代码按错误假设算角度却编译通过（静默出错）。
#
# 轴向约定（关节局部坐标系，连杆沿局部 +X 伸出）：
#   Yaw   = 绕局部 Z（竖直轴）  —— 左右摆
#   Pitch = 绕局部 -Y          —— 上下俯仰；取负号才能让正角度抬升连杆，
#                                 与历史构型的 zz = L·sin(θ) 一致
#   Roll  = 绕局部 X（连杆自身轴线）—— 自转，不改变末端位置
const AXIS_YAW: String = "Yaw"
const AXIS_PITCH: String = "Pitch"
const AXIS_ROLL: String = "Roll"
## 转轴名 -> 局部单位向量
const AXIS_VECTORS: Dictionary = {
	AXIS_YAW: Vector3(0.0, 0.0, 1.0),
	AXIS_PITCH: Vector3(0.0, -1.0, 0.0),
	AXIS_ROLL: Vector3(1.0, 0.0, 0.0),
}
## φ = asin(â_z) 的参数化在末端竖直（|â_z|→1）时退化，此时 asin 导数发散。
## 判据用 1 - â_z² 与该阈值比较。
const PITCH_DEGEN_EPS: float = 1.0e-4


## 各关节转轴名。缺失 axis 字段时按历史构型推断，保证老配置行为不变：
##   2 轴 = [Yaw, Yaw]（平面臂，两关节同轴）
##   3 轴 = [Yaw, Pitch, Pitch]
##   4 轴 = [Yaw, Pitch, Pitch, Pitch]
func joint_axes(joints: Array, jc: int, config_type: int) -> Array:
	var out: Array = []
	for i in range(jc):
		var name: String = ""
		if i < joints.size():
			name = str(joints[i].get("axis", "")).strip_edges()
		if not AXIS_VECTORS.has(name):
			# 未指定：按历史构型推断
			if config_type == 0:
				name = AXIS_YAW
			else:
				name = AXIS_YAW if i == 0 else AXIS_PITCH
		out.append(name)
	return out


## 各关节之后的连杆长度（mm）。缺失 len 字段时回退到历史的 L1/L2/L3：
##   2 轴：[L1, L2]（每个关节后都有连杆）
##   3/4 轴：[0, L1, L2(, L3)]（底座 Yaw 与肩部 Pitch 同位，之间无连杆）
func joint_lengths(joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> Array:
	var out: Array = []
	var fallback: Array = ([l1, l2] if config_type == 0 else [0.0, l1, l2, l3])
	for i in range(jc):
		var s: String = ""
		if i < joints.size():
			s = str(joints[i].get("len", "")).strip_edges()
		if s.is_valid_float():
			out.append(s.to_float())
		else:
			out.append(fallback[i] if i < fallback.size() else 0.0)
	return out


## 把逐关节 len 折算回旧解析路径要用的 [L1, L2, L3]。
##
## 配置界面已经从「全局 L1/L2/L3」迁移到「逐关节 len」，但旧的 2/3/4 轴
## 解析解（solve_ik / _gen_ik_solve）深度依赖 L1/L2/L3 这三个量。
## 这里做一次折算，让新配置能喂给旧路径，避免用户填的长度不生效。
## 阶段二换成雅可比 IK 后，旧路径连同这个函数一起删掉。
##
## 折算规则与 joint_lengths 的 fallback 互为逆运算：
##   2 轴（关节数 2）：L1=len[0], L2=len[1]
##   3/4 轴：底座 Yaw 与肩部同位（len[0] 通常为 0），故 L1=len[1], L2=len[2], L3=len[3]
## 关节数超过 4 时旧路径本就不适用，取前几段即可（阶段二会接管）。
func legacy_link_lengths(cfg: Dictionary) -> Array:
	var jc: int = int(cfg.get("joint_count", 2))
	var joints: Array = cfg.get("joints", [])
	# 先看有没有逐关节 len；一个都没填才回退到旧的 L1/L2/L3 字段
	var has_len: bool = false
	for i in range(min(joints.size(), jc)):
		if str(joints[i].get("len", "")).strip_edges().is_valid_float():
			has_len = true
			break
	if not has_len:
		return [
			_to_float(cfg.get("L1", "100"), 100.0),
			_to_float(cfg.get("L2", "100"), 100.0),
			_to_float(cfg.get("L3", "0"), 0.0),
		]
	# 逐关节 len -> L1/L2/L3
	var lens: Array = []
	for i in range(jc):
		var s: String = ""
		if i < joints.size():
			s = str(joints[i].get("len", "")).strip_edges()
		lens.append(s.to_float() if s.is_valid_float() else 0.0)
	if jc <= 2:
		# 2 关节：两段连杆直接对应 L1/L2
		return [
			lens[0] if lens.size() > 0 and lens[0] > 0.0 else 100.0,
			lens[1] if lens.size() > 1 and lens[1] > 0.0 else 100.0,
			0.0,
		]
	# 3 关节以上：跳过底座那一段（通常为 0）
	var out: Array = [100.0, 100.0, 0.0]
	if lens.size() > 1 and lens[1] > 0.0:
		out[0] = lens[1]
	if lens.size() > 2 and lens[2] > 0.0:
		out[1] = lens[2]
	if lens.size() > 3:
		out[2] = lens[3]
	return out


## 通用正运动学链。逐关节累乘旋转，返回世界系（机器人坐标，mm）下的：
##   points: 长度 jc+1，各关节位置 + 末端位置
##   axes:   长度 jc，各关节转轴的世界方向（单位向量），雅可比要用
##   tip_basis: 末端姿态（局部 +X 即末端朝向），夹爪渲染要用
## 注意 points 里可能出现重合点（len=0 的关节，如底座 Yaw 与肩部 Pitch 同位）。
func fk_chain(angles: Array, joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> Dictionary:
	var axis_names: Array = joint_axes(joints, jc, config_type)
	var lens: Array = joint_lengths(joints, jc, config_type, l1, l2, l3)
	var basis: Basis = Basis.IDENTITY
	var pos: Vector3 = Vector3.ZERO
	var points: Array = []
	var axes: Array = []
	for i in range(jc):
		var local_axis: Vector3 = AXIS_VECTORS[axis_names[i]]
		# 关节 i 的世界转轴：由「该关节之前」的姿态决定。
		# 绕自身轴旋转不改变该轴方向，故用旋转前后的 basis 结果相同。
		var world_axis: Vector3 = (basis * local_axis).normalized()
		axes.append(world_axis)
		# 关节位置记录在施加自身旋转之前的落点
		points.append(pos)
		var ang: float = deg_to_rad(float(angles[i]) if i < angles.size() else 0.0)
		basis = basis * Basis(local_axis, ang)
		# 沿旋转后的局部 +X 伸出该关节之后的连杆
		pos += basis * Vector3(lens[i], 0.0, 0.0)
	points.append(pos)
	return {"points": points, "axes": axes, "tip_basis": basis}


# ------------------------------------------------------------------ 雅可比与末端俯仰角
## 末端朝向（approach）：末段连杆指向，即 tip_basis 的局部 +X。
## 夹爪朝这个方向抓取。
func tip_approach(chain: Dictionary) -> Vector3:
	return ((chain["tip_basis"] as Basis) * Vector3(1.0, 0.0, 0.0)).normalized()


## 末端俯仰角 φ（度）：末端朝向的仰角。
##
## 这是 φ 在任意构形下的通用定义。旧的 `φ = θ1+θ2+θ3` 只在
## 「若干共面 Pitch」时成立，转轴一旦混搭那个加法就不对应任何几何量。
## 仰角定义对任何构形都成立，物理含义仍是抓取俯仰角：
## 0° = 水平前伸（插进货架），-90° = 竖直向下（扣桌面上的矿石）。
func tip_pitch_deg(chain: Dictionary) -> float:
	return rad_to_deg(asin(clampf(tip_approach(chain).z, -1.0, 1.0)))


## 位置雅可比的列向量：第 i 列 = a_i × (p_tip - o_i)，单位 mm/rad。
## 描述关节 i 单位角速度引起的末端线速度。
func jacobian_columns(chain: Dictionary, jc: int) -> Array:
	var pts: Array = chain["points"]
	var axes: Array = chain["axes"]
	var tip: Vector3 = pts[pts.size() - 1]
	var cols: Array = []
	for i in range(jc):
		cols.append((axes[i] as Vector3).cross(tip - (pts[i] as Vector3)))
	return cols


## φ 对各关节角的梯度（1×n 行向量，单位 rad/rad）。
##
## dâ/dθ_i = a_i × â，而 φ = asin(â_z)，故
##   dφ/dθ_i = (a_i × â)_z / sqrt(1 - â_z²)
##
## 返回空数组表示当前姿态下 φ 的参数化退化（末端竖直朝上或朝下）：
## 此时 asin 的导数发散，且 φ 本身也不再能区分朝向，调用方应跳过该姿态。
func pitch_gradient(chain: Dictionary, jc: int) -> Array:
	var approach: Vector3 = tip_approach(chain)
	var denom_sq: float = 1.0 - approach.z * approach.z
	if denom_sq < PITCH_DEGEN_EPS:
		return []
	var denom: float = sqrt(denom_sq)
	var axes: Array = chain["axes"]
	var g: Array = []
	for i in range(jc):
		g.append(((axes[i] as Vector3).cross(approach)).z / denom)
	return g


# ------------------------------------------------------------------ 目标状态变量
## 当前构型实际用到的末端目标变量。只声明用得到的，避免 C251 报未引用参数警告。
## 2 轴只有 XY；3 轴加 Z；4 轴再加姿态角 φ。
func _target_vars(jc: int) -> Array:
	var out: Array = ["targetX", "targetY"]
	if jc >= 3:
		out.append("targetZ")
	if jc >= 4:
		out.append("targetPhi")
	return out


## ik_solve 的形参列表，与 _target_vars 一一对应
func _ik_params(jc: int) -> String:
	var names: Array = ["float x", "float y"]
	if jc >= 3:
		names.append("float z")
	if jc >= 4:
		names.append("float phi")
	return ", ".join(names)


## 末端俯仰角 φ 是否值得作为控制量：需要构形上真的能「位置不动、只转 φ」。
##
## 判据来自构形诊断而非关节数：4 个关节全是 Pitch 时 φ 同样不可控。
## 生成器自己调诊断而不依赖外部传值，这样测试直接调 generate() 也能拿到正确结果。
func _phi_controllable(joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float) -> bool:
	var diag = load("res://scripts/arm_diagnosis.gd").new()
	var res: Dictionary = diag.analyze(joints, jc, config_type, l1, l2, l3)
	return bool(res.get("pitch_dof", false))


## 当前构型实际用到的末端目标变量（雅可比版）。
## φ 不可控时不声明 targetPhi，否则 C251 会报未引用参数警告。
func _target_vars_for(jc: int, use_phi: bool) -> Array:
	var out: Array = ["targetX", "targetY"]
	if jc >= 3:
		out.append("targetZ")
	if use_phi:
		out.append("targetPhi")
	return out


## ik_solve 的形参列表（雅可比版），与 _target_vars_for 一一对应
func _ik_params_for(jc: int, use_phi: bool) -> String:
	var names: Array = ["float x", "float y"]
	if jc >= 3:
		names.append("float z")
	if use_phi:
		names.append("float phi")
	return ", ".join(names)


## 初始姿态对应的末端目标值，顺序与 _target_vars_for 一致。
## 增量模式必须从这里起步，否则上电首帧 target 与实际末端不符会导致关节跳变。
func _home_targets(joints: Array, jc: int, config_type: int,
		l1: float, l2: float, l3: float, use_phi: bool) -> Array:
	var home_ang: Array = _joint_home_angles(joints)
	var chain: Dictionary = fk_chain(home_ang, joints, jc, config_type, l1, l2, l3)
	var pts: Array = chain["points"]
	var tip: Vector3 = pts[pts.size() - 1]
	var out: Array = [tip.x, tip.y]
	if jc >= 3:
		out.append(tip.z)
	if use_phi:
		out.append(tip_pitch_deg(chain))
	return out


# ------------------------------------------------------------------ 槽位判定
## 是否有任一关节挂在扩展板上（决定发送后是否需要额外延时）
func _has_exp_slot(joints: Array, jc: int) -> bool:
	for i in range(jc):
		if _io_to_exp_slot(joints[i].get("io", "P60")) >= 0:
			return true
	return false


# ------------------------------------------------------------------ angle_to_duty
func _gen_angle_to_duty() -> String:
	var s: String = ""
	s += "/// @brief 关节角度(运动学角，度) -> 舵机占空比\n"
	s += "/// @param joint 关节索引(0..JOINT_COUNT-1)\n"
	s += "/// @param angle 运动学角(度)，即连杆的实际朝向\n"
	s += "/// @return 舵机占空比(SERVO_MIN_DUTY~SERVO_MAX_DUTY)\n"
	s += "/// @note 两个角度空间：运动学角是连杆朝向（逆解算的输出），\n"
	s += "///       舵机指令角 = 运动学角 - jointOffset[joint]，行程 ±%d°：\n" \
		% SERVO_MAX_OFFSET_DEG
	s += "///       -%d°=%d, 0°=%d, +%d°=%d。\n" \
		% [SERVO_MAX_OFFSET_DEG, SERVO_DUTY_MIN,
			SERVO_DUTY_MID, SERVO_MAX_OFFSET_DEG, SERVO_DUTY_MAX]
	s += "///       反向关节沿中位镜像；舵机方向只由占空比决定，\n"
	s += "///       故不再向扩展板发 Dir_Change_Order。\n"
	s += "uint16_t angle_to_duty(int joint, float angle)\n"
	s += "{\n"
	s += "    int duty;\n"
	s += "    float servo;\n"
	s += "    // 限位夹紧（限位也是运动学角）\n"
	s += "    if (angle < jointMin[joint])\n"
	s += "        angle = jointMin[joint];\n"
	s += "    if (angle > jointMax[joint])\n"
	s += "        angle = jointMax[joint];\n"
	s += "    // 运动学角 -> 舵机指令角：扣掉安装中位朝向\n"
	s += "    servo = angle - jointOffset[joint];\n"
	s += "    // 舵机指令角 -> 占空比（0° 即中位 %d），反向关节沿中位镜像\n" % SERVO_DUTY_MID
	s += "    if (jointDir[joint])\n"
	s += "        duty = (int)(SERVO_MID_DUTY + servo * SERVO_DUTY_PER_DEG);\n"
	s += "    else\n"
	s += "        duty = (int)(SERVO_MID_DUTY - servo * SERVO_DUTY_PER_DEG);\n"
	s += "    if (duty < SERVO_MIN_DUTY)\n"
	s += "        duty = SERVO_MIN_DUTY;\n"
	s += "    if (duty > SERVO_MAX_DUTY)\n"
	s += "        duty = SERVO_MAX_DUTY;\n"
	s += "    return (uint16_t)duty;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ 运动学辅助函数
## 3x3 矩阵运算。逆解算每周期都要用，独立成函数避免 ik_solve 局部变量
## 撑爆 C251 的 128 字节函数段上限。
func _gen_kinematics_helpers() -> String:
	var s: String = ""
	s += "/// @brief 矩阵乘向量 out = m * v\n"
	s += "void mat_vec(float m[3][3], float v[3], float out[3])\n"
	s += "{\n"
	s += "    out[0] = m[0][0] * v[0] + m[0][1] * v[1] + m[0][2] * v[2];\n"
	s += "    out[1] = m[1][0] * v[0] + m[1][1] * v[1] + m[1][2] * v[2];\n"
	s += "    out[2] = m[2][0] * v[0] + m[2][1] * v[1] + m[2][2] * v[2];\n"
	s += "}\n\n"
	s += "/// @brief 绕任意单位轴 a 转 ang 弧度的旋转矩阵（罗德里格斯公式）\n"
	s += "/// @note 转轴是 Pitch/Roll/Yaw 只影响传进来的 a，公式本身通用\n"
	s += "void axis_rot(float a[3], float ang, float m[3][3])\n"
	s += "{\n"
	s += "    float c, s, t;\n"
	s += "    c = cos(ang);\n"
	s += "    s = sin(ang);\n"
	s += "    t = 1.0f - c;\n"
	s += "    m[0][0] = t * a[0] * a[0] + c;\n"
	s += "    m[0][1] = t * a[0] * a[1] - s * a[2];\n"
	s += "    m[0][2] = t * a[0] * a[2] + s * a[1];\n"
	s += "    m[1][0] = t * a[0] * a[1] + s * a[2];\n"
	s += "    m[1][1] = t * a[1] * a[1] + c;\n"
	s += "    m[1][2] = t * a[1] * a[2] - s * a[0];\n"
	s += "    m[2][0] = t * a[0] * a[2] - s * a[1];\n"
	s += "    m[2][1] = t * a[1] * a[2] + s * a[0];\n"
	s += "    m[2][2] = t * a[2] * a[2] + c;\n"
	s += "}\n\n"
	s += "/// @brief 矩阵乘矩阵 out = x * y\n"
	s += "void mat_mul(float x[3][3], float y[3][3], float out[3][3])\n"
	s += "{\n"
	s += "    uint8_t r, c;\n"
	s += "    for (r = 0; r < 3; r++)\n"
	s += "        for (c = 0; c < 3; c++)\n"
	s += "            out[r][c] = x[r][0] * y[0][c] + x[r][1] * y[1][c] + x[r][2] * y[2][c];\n"
	s += "}\n\n"
	return s


## 逆解算的中间结果。必须放 xdata：C251 单函数局部变量段上限 128 字节，
## 这些数组放栈上会直接编译失败（ERROR C172: segment too big）。
func _gen_ik_workspace(jc: int) -> String:
	var s: String = ""
	s += "// 逆解算中间结果。放 xdata 而非栈上：C251 单函数局部变量段上限 128 字节，\n"
	s += "// 这几个数组加起来远超上限，声明成局部变量会报 segment too big。\n"
	s += "static float xdata ikBasis[3][3], ikRot[3][3], ikTmp[3][3];\n"
	s += "static float xdata ikPts[%d][3];      // 各关节位置 + 末端位置\n" % (jc + 1)
	s += "static float xdata ikAxes[%d][3];     // 各关节转轴的世界方向\n" % jc
	s += "static float xdata ikCols[%d][3];     // 雅可比各列 a_i x (tip - o_i)\n" % jc
	s += "static float xdata ikJte[%d];         // J^T e\n" % jc
	s += "static float xdata ikLa[3], ikLv[3], ikWv[3], ikEv[3];\n"
	return s


# ------------------------------------------------------------------ ik_solve（雅可比）
## 雅可比转置数值逆解。取代 2/3/4 轴各一套的解析公式。
##
## Δθ = α·Jᵀe，J 第 i 列 = a_i × (p_tip − o_i)。
## 转轴类型只改变 a_i 这个单位向量，公式本身不变 —— 这是它能支持
## 任意关节数与任意 Pitch/Roll/Yaw 搭配的根本原因。
##
## 与 GDScript 侧 solve_ik_jacobian 逐行对应，改动必须同步两边。
func _gen_ik_solve_jacobian(jc: int, use_phi: bool, lens: Array) -> String:
	var w: float = _pitch_weight(lens)
	var s: String = ""
	s += "/// @brief 逆解算：末端目标 -> 各关节角度（雅可比转置增量法）\n"
	s += "/// @param x 末端X(mm)\n"
	s += "/// @param y 末端Y(mm)\n"
	if jc >= 3:
		s += "/// @param z 末端Z(mm)\n"
	if use_phi:
		s += "/// @param phi 末端俯仰角(度)，末端朝向的仰角\n"
	s += "/// @note 每次调用只走一步，靠 %dms 主循环连续收敛。\n" % LOOP_PERIOD_MS
	s += "///       结果写入 jointAngle[]，已按 jointMin/jointMax 钳位。\n"
	s += "///       ik_reachable=0 表示这一步没能靠近目标（已贴到可达域边界）。\n"
	s += "void ik_solve(%s)\n" % _ik_params_for(jc, use_phi)
	s += "{\n"
	# C89：所有声明必须在块首
	s += "    uint8_t k;\n"
	s += "    float alpha, num, den, step, maxStep, errBefore, errAfter;\n"
	if use_phi:
		s += "    float az, denom, phiErr, gk, gDot;\n"
	s += "    // === 正运动学：得到各关节位置、世界转轴、末端姿态 ===\n"
	s += "    ik_fk();\n"
	# 位置误差
	s += "    // === 位置误差 ===\n"
	s += "    ikEv[0] = x - ikPts[JOINT_COUNT][0];\n"
	s += "    ikEv[1] = y - ikPts[JOINT_COUNT][1];\n"
	if jc >= 3:
		s += "    ikEv[2] = z - ikPts[JOINT_COUNT][2];\n"
	else:
		s += "    ikEv[2] = 0.0f;   // 2 关节构型无 Z 目标\n"
	if use_phi:
		s += "    // === 末端俯仰角误差 ===\n"
		s += "    // phi = asin(a_z)，a = 末端朝向（tip_basis 的局部 +X）\n"
		s += "    az = ikBasis[2][0];\n"
		s += "    if (az > 1.0f) az = 1.0f;\n"
		s += "    if (az < -1.0f) az = -1.0f;\n"
		s += "    denom = 1.0f - az * az;\n"
		s += "    phiErr = 0.0f;\n"
		s += "    // 末端竖直时 asin 导数发散、phi 也不再区分朝向，本周期只管位置\n"
		s += "    if (denom > %.6ff)\n" % PITCH_DEGEN_EPS
		s += "    {\n"
		s += "        denom = sqrt(denom);\n"
		s += "        phiErr = (phi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;\n"
		s += "    }\n"
		s += "    else\n"
		s += "        denom = 0.0f;   // 0 表示本周期不参与姿态解算\n"
	# 雅可比列与 Jᵀe
	s += "    // === 雅可比各列与 J^T e ===\n"
	if use_phi:
		s += "    gDot = 0.0f;\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        ikLv[0] = ikPts[JOINT_COUNT][0] - ikPts[k][0];\n"
	s += "        ikLv[1] = ikPts[JOINT_COUNT][1] - ikPts[k][1];\n"
	s += "        ikLv[2] = ikPts[JOINT_COUNT][2] - ikPts[k][2];\n"
	s += "        ikCols[k][0] = ikAxes[k][1] * ikLv[2] - ikAxes[k][2] * ikLv[1];\n"
	s += "        ikCols[k][1] = ikAxes[k][2] * ikLv[0] - ikAxes[k][0] * ikLv[2];\n"
	s += "        ikCols[k][2] = ikAxes[k][0] * ikLv[1] - ikAxes[k][1] * ikLv[0];\n"
	s += "        ikJte[k] = ikCols[k][0] * ikEv[0] + ikCols[k][1] * ikEv[1]\n"
	s += "                 + ikCols[k][2] * ikEv[2];\n"
	if use_phi:
		s += "        if (denom > 0.0f)\n"
		s += "        {\n"
		s += "            // phi 梯度 g_k = (a_k x approach)_z / sqrt(1 - a_z^2)\n"
		s += "            gk = (ikAxes[k][0] * ikBasis[1][0]\n"
		s += "                - ikAxes[k][1] * ikBasis[0][0]) / denom;\n"
		s += "            // 两项量纲统一到 mm：g 是 rad/rad，乘权重后与位置项可加\n"
		s += "            ikJte[k] += gk * PHI_WEIGHT * (phiErr * PHI_WEIGHT);\n"
		s += "            gDot += gk * PHI_WEIGHT * ikJte[k];\n"
		s += "        }\n"
	s += "    }\n"
	# α 自适应
	s += "    // === 步长 alpha（最速下降的精确解）===\n"
	s += "    // alpha = |J^T e|^2 / |J J^T e|^2。分子是**关节空间**的模长，\n"
	s += "    // 用任务空间的 |e|^2 会小好几个数量级，末端几乎不动。\n"
	s += "    num = 0.0f;\n"
	s += "    ikWv[0] = 0.0f; ikWv[1] = 0.0f; ikWv[2] = 0.0f;\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        num += ikJte[k] * ikJte[k];\n"
	s += "        ikWv[0] += ikCols[k][0] * ikJte[k];\n"
	s += "        ikWv[1] += ikCols[k][1] * ikJte[k];\n"
	s += "        ikWv[2] += ikCols[k][2] * ikJte[k];\n"
	s += "    }\n"
	s += "    den = ikWv[0] * ikWv[0] + ikWv[1] * ikWv[1] + ikWv[2] * ikWv[2];\n"
	if use_phi:
		s += "    den += gDot * gDot;\n"
	s += "    alpha = 0.0f;\n"
	s += "    if (den > IK_EPS)\n"
	s += "        alpha = num / den;\n"
	# 步长限幅
	s += "    // 单步限幅：防止大误差时末端猛冲，也避免线性近似在大角度下失效\n"
	s += "    maxStep = 0.0f;\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        step = alpha * ikJte[k] * RAD_TO_DEG;\n"
	s += "        if (step < 0.0f) step = -step;\n"
	s += "        if (step > maxStep) maxStep = step;\n"
	s += "    }\n"
	s += "    if (maxStep > IK_MAX_STEP_DEG)\n"
	s += "        alpha *= IK_MAX_STEP_DEG / maxStep;\n"
	# 记录本步之前的误差，走一步，再判断是否靠近
	s += "    // === 走一步并按限位钳位 ===\n"
	s += "    errBefore = ikEv[0] * ikEv[0] + ikEv[1] * ikEv[1] + ikEv[2] * ikEv[2];\n"
	if use_phi:
		s += "    errBefore += (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        jointAngle[k] += alpha * ikJte[k] * RAD_TO_DEG;\n"
	s += "        if (jointAngle[k] < jointMin[k]) jointAngle[k] = jointMin[k];\n"
	s += "        if (jointAngle[k] > jointMax[k]) jointAngle[k] = jointMax[k];\n"
	s += "    }\n"
	# 走完后重算误差判断可达性
	s += "    // === 可达性：这一步有没有真的靠近目标 ===\n"
	s += "    // 姿态误差要一起算进总误差，否则纯粹在调 phi 的步会被误判成停滞\n"
	s += "    ik_fk();\n"
	s += "    ikEv[0] = x - ikPts[JOINT_COUNT][0];\n"
	s += "    ikEv[1] = y - ikPts[JOINT_COUNT][1];\n"
	if jc >= 3:
		s += "    ikEv[2] = z - ikPts[JOINT_COUNT][2];\n"
	else:
		s += "    ikEv[2] = 0.0f;\n"
	s += "    errAfter = ikEv[0] * ikEv[0] + ikEv[1] * ikEv[1] + ikEv[2] * ikEv[2];\n"
	if use_phi:
		s += "    az = ikBasis[2][0];\n"
		s += "    if (az > 1.0f) az = 1.0f;\n"
		s += "    if (az < -1.0f) az = -1.0f;\n"
		s += "    phiErr = (phi - asin(az) * RAD_TO_DEG) * DEG_TO_RAD;\n"
		s += "    errAfter += (phiErr * PHI_WEIGHT) * (phiErr * PHI_WEIGHT);\n"
	s += "    ik_reachable = (errAfter < errBefore) ? 1 : 0;\n"
	s += "}\n\n"
	return s


## 正运动学链。逐关节累乘旋转，同时记下雅可比要用的世界转轴。
##
## ik_solve 走一步前后都要算一次（后一次用于判断误差是否下降），
## 故抽成单独函数；同时也避开了 C251 的函数段大小限制。
func _gen_ik_fk() -> String:
	var s: String = ""
	s += "/// @brief 按当前 jointAngle[] 算正运动学链\n"
	s += "/// @note 结果写入：ikPts[]=各关节位置+末端，ikAxes[]=各关节世界转轴，\n"
	s += "///       ikBasis=末端姿态（第一列即末端朝向）\n"
	s += "void ik_fk()\n"
	s += "{\n"
	s += "    uint8_t k, r, c;\n"
	s += "    float ang;\n"
	s += "    for (r = 0; r < 3; r++)\n"
	s += "        for (c = 0; c < 3; c++)\n"
	s += "            ikBasis[r][c] = (r == c) ? 1.0f : 0.0f;\n"
	s += "    ikPts[0][0] = 0.0f; ikPts[0][1] = 0.0f; ikPts[0][2] = 0.0f;\n"
	s += "    for (k = 0; k < JOINT_COUNT; k++)\n"
	s += "    {\n"
	s += "        ikLa[0] = jointAxis[k][0];\n"
	s += "        ikLa[1] = jointAxis[k][1];\n"
	s += "        ikLa[2] = jointAxis[k][2];\n"
	s += "        // 关节 k 的世界转轴由它之前的姿态决定\n"
	s += "        // （绕自身轴转不改变该轴方向，故用旋转前的 basis）\n"
	s += "        mat_vec(ikBasis, ikLa, ikWv);\n"
	s += "        ikAxes[k][0] = ikWv[0]; ikAxes[k][1] = ikWv[1]; ikAxes[k][2] = ikWv[2];\n"
	s += "        ang = jointAngle[k] * DEG_TO_RAD;\n"
	s += "        axis_rot(ikLa, ang, ikRot);\n"
	s += "        mat_mul(ikBasis, ikRot, ikTmp);\n"
	s += "        for (r = 0; r < 3; r++)\n"
	s += "            for (c = 0; c < 3; c++)\n"
	s += "                ikBasis[r][c] = ikTmp[r][c];\n"
	s += "        // 沿旋转后的局部 +X 伸出该关节之后的连杆\n"
	s += "        ikLv[0] = jointLen[k]; ikLv[1] = 0.0f; ikLv[2] = 0.0f;\n"
	s += "        mat_vec(ikBasis, ikLv, ikWv);\n"
	s += "        ikPts[k + 1][0] = ikPts[k][0] + ikWv[0];\n"
	s += "        ikPts[k + 1][1] = ikPts[k][1] + ikWv[1];\n"
	s += "        ikPts[k + 1][2] = ikPts[k][2] + ikWv[2];\n"
	s += "    }\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ik_solve（旧解析解）
## 保留至 Phase 2.4：真机验证雅可比版通过后连同 L1/L2/L3 一起删除
func _gen_ik_solve(config_type: int, jc: int) -> String:
	var s: String = ""
	s += "/// @brief 逆解算：末端位置 -> 各关节角度\n"
	s += "/// @param x 末端X(mm)\n"
	s += "/// @param y 末端Y(mm)\n"
	if jc >= 3:
		s += "/// @param z 末端Z(mm)\n"
	if jc >= 4:
		s += "/// @param phi 末端姿态角(度)\n"
	s += "/// @note 结果写入 jointAngle[]，越界时钳到边界并设 ik_reachable=0\n"
	s += "void ik_solve(%s)\n" % _ik_params(jc)
	s += "{\n"
	# C89：所有变量声明必须在函数块开头，位于可执行语句之前
	if config_type == 0:
		# 2 轴平面：末端就在小臂末端
		s += "    float r, c2, t1, t2;\n"
		s += "    ik_reachable = 1;\n"
		s += "    // === 2 轴平面逆解 ===\n"
		s += "    r = sqrt(x * x + y * y);\n"
		s += "    // 可达性检查：半径需落在 [|L1-L2|, L1+L2] 内\n"
		s += "    if (r < fabs(L1 - L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        r = fabs(L1 - L2);\n"
		s += "    }\n"
		s += "    else if (r > (L1 + L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        r = L1 + L2;\n"
		s += "    }\n"
		s += "    c2 = (r * r - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);\n"
		s += "    if (c2 > 1.0f) c2 = 1.0f;\n"
		s += "    if (c2 < -1.0f) c2 = -1.0f;\n"
		s += "    t2 = ELBOW_SIGN * acos(c2);\n"
		s += "    t1 = atan2(y, x) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));\n"
		s += "    jointAngle[0] = t1 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[1] = t2 * 180.0f / 3.14159265f;\n"
	else:
		# 3 轴：底座旋转 + 2 连杆；4 轴额外把末端沿 φ 回退 L3 得到腕心
		var is4: bool = config_type >= 2
		if is4:
			s += "    float r, c2, t1, t2, t0, t3, rz, scale, phi_rad;\n"
		else:
			s += "    float r, c2, t1, t2, t0, rz, scale;\n"
		s += "    ik_reachable = 1;\n"
		if is4:
			s += "    // === 4 轴逆解（底座 + 2连杆 + 腕部俯仰）===\n"
		else:
			s += "    // === 3 轴逆解（底座旋转 + 2连杆平面）===\n"
		s += "    t0 = atan2(y, x);\n"
		s += "    r = sqrt(x * x + y * y);\n"
		if is4:
			s += "    // 腕心 = 末端沿姿态角 φ 回退 L3，逆解针对腕心而非末端\n"
			s += "    phi_rad = phi * 3.14159265f / 180.0f;\n"
			s += "    r = r - L3 * cos(phi_rad);\n"
			s += "    z = z - L3 * sin(phi_rad);\n"
		s += "    rz = sqrt(r * r + z * z);\n"
		s += "    // (r, z) 平面可达性；rz 过小时无方向可依，直接退到内边界正上方\n"
		s += "    if (rz < IK_EPS)\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        r = fabs(L1 - L2);\n"
		s += "        z = 0.0f;\n"
		s += "        if (r < IK_EPS)\n"
		s += "            r = L1 + L2;\n"
		s += "    }\n"
		s += "    else if (rz < fabs(L1 - L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        scale = fabs(L1 - L2) / rz;\n"
		s += "        r *= scale; z *= scale;\n"
		s += "    }\n"
		s += "    else if (rz > (L1 + L2))\n"
		s += "    {\n"
		s += "        ik_reachable = 0;\n"
		s += "        scale = (L1 + L2) / rz;\n"
		s += "        r *= scale; z *= scale;\n"
		s += "    }\n"
		s += "    c2 = (r * r + z * z - L1 * L1 - L2 * L2) / (2.0f * L1 * L2);\n"
		s += "    if (c2 > 1.0f) c2 = 1.0f;\n"
		s += "    if (c2 < -1.0f) c2 = -1.0f;\n"
		s += "    t2 = ELBOW_SIGN * acos(c2);\n"
		s += "    t1 = atan2(z, r) - atan2(L2 * sin(t2), L1 + L2 * cos(t2));\n"
		s += "    jointAngle[0] = t0 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[1] = t1 * 180.0f / 3.14159265f;\n"
		s += "    jointAngle[2] = t2 * 180.0f / 3.14159265f;\n"
		if is4:
			s += "    // 腕部：补足剩余角度以保持末端姿态角 φ\n"
			s += "    t3 = phi_rad - (t1 + t2);\n"
			s += "    jointAngle[3] = t3 * 180.0f / 3.14159265f;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ ReadControllerInputs
func _gen_read_inputs() -> String:
	var s: String = ""
	s += "/// @brief 读取摇杆并做死区过滤（按键在使用处直接 RcKeyValueRead 读取）\n"
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
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CheckPresetKeys
func _gen_check_preset_keys(jc: int, use_phi: bool = false) -> String:
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
	if jc >= 3:
		s += "            targetZ = presetPos[i][2];\n"
	if use_phi:
		s += "            targetPhi = presetPos[i][3];\n"
	s += "            return 1;\n"
	s += "        }\n"
	s += "    }\n"
	s += "    return 0;\n"
	s += "}\n\n"
	return s


# ------------------------------------------------------------------ CalculateIK
func _gen_calculate_ik(cfg: Dictionary, use_phi: bool = false) -> String:
	var jc: int = cfg.get("joint_count", 2)
	var s: String = ""
	s += "/// @brief 摇杆/按键输入末端位置增量 -> 逆解算\n"
	s += "/// @param hit 1=本周期已由预设点位设定目标，跳过增量累加\n"
	s += "/// @note 采用增量累积模式：摇杆偏移量和长按按键都对 target 做累加，\n"
	s += "///       松开后末端保持当前位置不动。\n"
	s += "///       逆解是雅可比增量法，每周期走一步，连续多个周期逼近目标。\n"
	# 备份变量与 ik_solve 实参都随构型裁剪，避免未使用变量
	var tvars: Array = _target_vars_for(jc, use_phi)
	var backups: Array = []
	var save_stmts: Array = []
	var restore_stmts: Array = []
	for v in tvars:
		var b: String = "last" + v.substr(6) # targetX -> lastX
		backups.append(b)
		save_stmts.append("%s = %s;" % [b, v])
		restore_stmts.append("%s = %s;" % [v, b])
	var call_args: String = ", ".join(tvars)
	s += "void CalculateIK(uint8_t hit)\n"
	s += "{\n"
	s += "    float %s;\n" % ", ".join(backups)
	s += "    // 备份上次目标：目标跑到臂展外时要把这一步的增量撤掉，\n"
	s += "    // 否则长推摇杆会让 target 一直飘远，松手后末端要等很久才追回来\n"
	s += "    %s\n" % " ".join(save_stmts)
	s += "    if (!hit)\n"
	s += "    {\n"
	s += _indent_block(_build_joy_mapping(cfg))
	s += _indent_block(_build_keymove_mapping(cfg, jc, use_phi))
	s += "    }\n"
	s += "    ik_solve(%s);\n" % call_args
	s += "    // 目标是否落在可达范围内：拿末端到底座的距离与连杆总长比。\n"
	s += "    // 注意不能用 ik_reachable 判断——雅可比法下它表示\n"
	s += "    // 「这一步有没有靠近目标」，正常收敛途中也会因步长限幅而为 0。\n"
	s += "    if (!hit && ik_target_too_far(%s))\n" % ", ".join(tvars.slice(0, 3 if jc >= 3 else 2))
	s += "    {\n"
	s += "        // 撤回本周期增量，target 停在上一个够得着的位置\n"
	s += "        %s\n" % " ".join(restore_stmts)
	s += "    }\n"
	s += "}\n\n"
	return s


## 目标是否超出臂展。雅可比法本身不需要可达性判断（够不着自然停在最近点），
## 但摇杆是增量累加的：若不拦住，长推摇杆会让 target 无限飘远，
## 松手后末端得花很久才追回来，手感上像是「卡住了」。
func _gen_target_too_far(jc: int, lens: Array) -> String:
	var reach: float = 0.0
	for v in lens:
		reach += absf(float(v))
	var s: String = ""
	s += "/// @brief 目标点是否超出臂展（连杆总长）\n"
	s += "/// @note 只拦「明显够不着」，留 %d%% 余量避免边界处反复抖动\n" \
		% int(round((1.0 - IK_REACH_MARGIN) * 100.0))
	if jc >= 3:
		s += "uint8_t ik_target_too_far(float x, float y, float z)\n"
	else:
		s += "uint8_t ik_target_too_far(float x, float y)\n"
	s += "{\n"
	s += "    float d2;\n"
	if jc >= 3:
		s += "    d2 = x * x + y * y + z * z;\n"
	else:
		s += "    d2 = x * x + y * y;\n"
	# 比较平方值省一次 sqrt
	var limit: float = reach * IK_REACH_MARGIN
	s += "    // 与 (臂展 * %.2f)^2 比，省一次开方\n" % IK_REACH_MARGIN
	s += "    return (d2 > %.2ff) ? 1 : 0;\n" % (limit * limit)
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
	s += "    targetX += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % parse_joy_axis(joy_x)
	s += "    targetY += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % parse_joy_axis(joy_y)
	if jc >= 3:
		s += "    targetZ += (float)valueOfRoker[%d][%d] * JOY_SCALE / 2047.0f;\n" % parse_joy_axis(joy_z)
	return s


## 按键控制末端移动代码生成（长按持续移动）
## keymove 索引：0=末端X, 1=末端Y, 2=末端Z, 3=末端姿态角φ
func _build_keymove_mapping(cfg: Dictionary, jc: int, use_phi: bool = false) -> String:
	var keymove: Array = cfg.get("keymove", [])
	if keymove.is_empty():
		return ""
	var target_names: Array = ["targetX", "targetY", "targetZ", "targetPhi"]
	var axis_labels: Array = ["X", "Y", "Z", "俯仰角"]
	var step_macros: Array = ["KEYMOVE_SPEED", "KEYMOVE_SPEED", "KEYMOVE_SPEED", "KEYMOVE_PHI_SPEED"]
	var s: String = ""
	var has_any: bool = false
	for i in range(min(keymove.size(), 4)):
		# 2 轴构型无 Z 轴；俯仰角只在构形上真的能单独控时才生成
		if jc < 3 and i == 2:
			continue
		if i == 3 and not use_phi:
			continue
		var plus_key: String = keymove[i].get("plus", "不使用")
		var minus_key: String = keymove[i].get("minus", "不使用")
		if plus_key == "不使用" and minus_key == "不使用":
			continue
		if not has_any:
			s += "    // 按键增量：长按时每周期移动 KEYMOVE_SPEED mm / KEYMOVE_PHI_SPEED 度\n"
			has_any = true
		if plus_key != "不使用":
			s += "    if (RcKeyValueRead(%s))\n" % _key_name_to_offset(plus_key)
			s += "        %s += %s; // 末端%s 正向（按键 %s）\n" % [target_names[i], step_macros[i], axis_labels[i], plus_key]
		if minus_key != "不使用":
			s += "    if (RcKeyValueRead(%s))\n" % _key_name_to_offset(minus_key)
			s += "        %s -= %s; // 末端%s 负向（按键 %s）\n" % [target_names[i], step_macros[i], axis_labels[i], minus_key]
	return s


## 解析摇杆选项文本 -> [rocker_idx, axis_idx]
## 左摇杆固定用于底盘移动，末端控制只用右摇杆（rocker_idx=1）
## 只看 "->" 左侧的源轴，否则 "右Y->末端X" 会被右侧的 X 误判成水平轴
## "右X->末端X" -> [1, 0]; "右Y->末端X" -> [1, 1]
func parse_joy_axis(text: String) -> Array:
	var rocker: int = 1 # 固定右摇杆（左摇杆用于底盘）
	var src: String = text
	var arrow: int = text.find("->")
	if arrow >= 0:
		src = text.substr(0, arrow)
	var axis: int = 1 if "Y" in src else 0
	return [rocker, axis]


# ------------------------------------------------------------------ ApplyServoControl
func _gen_apply_servo_control(joints: Array, jc: int, has_exp: bool) -> String:
	var s: String = ""
	s += "/// @brief 应用舵机控制：关节角度 -> 占空比 -> 发送\n"
	s += "void ApplyServoControl()\n"
	s += "{\n"
	s += "    for (i = 0; i < JOINT_COUNT; i++)\n"
	s += "        dutyOfServo[i] = angle_to_duty(i, jointAngle[i]);\n"
	# 扩展板槽位（P60~P77）走 ExpansionBoradControl，主控板 MP03/MP74 走 PWM_SET_Frequency
	var exp_slots: Dictionary = _exp_slot_map(joints, jc)
	var main_pwm: Array = _main_pwm_list(joints, jc)
	# 扩展板控制
	if has_exp:
		s += "    // 扩展板舵机控制（频率 50Hz），未占用槽位传 0 表示维持原状\n"
		# Duty_Change_Order：8 个槽位占空比
		var duty_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			duty_vals[slot] = "dutyOfServo[%d]" % exp_slots[slot]
		s += "    ExpansionBoradControl(Duty_Change_Order,\n"
		s += "                          %s);\n" % _exp_args(duty_vals)
		s += "    Ms_Delay(%d);\n" % EXP_SEND_DELAY_MS
	# 主控板 PWM 控制
	if main_pwm.size() > 0:
		s += "    // 主控板舵机控制（PWM）\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			s += "    PWM_SET_Frequency(%s, 50, dutyOfServo[%d]);\n" % [pwm_ch, ji]
	s += "}\n\n"
	return s


## 扩展板槽位 -> 关节索引
func _exp_slot_map(joints: Array, jc: int) -> Dictionary:
	var m: Dictionary = {}
	for i in range(jc):
		var slot: int = _io_to_exp_slot(joints[i].get("io", "P60"))
		if slot >= 0:
			m[slot] = i
	return m


## 挂在主控板 PWM 引脚上的关节列表 [{joint, ch}]
func _main_pwm_list(joints: Array, jc: int) -> Array:
	var out: Array = []
	for i in range(jc):
		var pin: String = joints[i].get("io", "P60")
		if _io_to_exp_slot(pin) < 0:
			out.append({"joint": i, "ch": _pin_to_pwm_channel(pin)})
	return out


## 把 8 个槽位参数格式化为 ExpansionBoradControl 的实参列表（每行两个，对齐续行）
func _exp_args(vals: Array) -> String:
	return "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [
		vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]]


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
	# 扩展板槽位（P60~P77）走 ExpansionBoradControl，主控板 MP03/MP74 走 PWM_Init
	var exp_slots: Dictionary = _exp_slot_map(joints, jc)
	var main_pwm: Array = _main_pwm_list(joints, jc)
	if exp_slots.size() > 0:
		# 构建 Init_Order：舵机槽位频率 50，其余 0（维持原状）
		var init_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			init_vals[slot] = "50"
		s += "    // 扩展板舵机初始化（频率 50Hz），未占用槽位传 0 表示维持原状\n"
		s += "    ExpansionBoradControl(Init_Order,\n"
		s += "                          %s);\n" % _exp_args(init_vals)
		s += "    Ms_Delay(20);\n"
		# 舵机转向已由 angle_to_duty 的占空比镜像实现，
		# 若此处再发 Dir_Change_Order 会与之叠加抵消，故不发送。
		s += "    // 舵机转向已在 angle_to_duty 中以占空比镜像实现，无需 Dir_Change_Order\n"
		# 上电即推到初始角度，避免舵机停在上次断电位置
		var home_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
		for slot in exp_slots.keys():
			var idx: int = exp_slots[slot]
			home_vals[slot] = "angle_to_duty(%d, jointHome[%d])" % [idx, idx]
		s += "    // 上电先把各关节推到初始角度\n"
		s += "    ExpansionBoradControl(Duty_Change_Order,\n"
		s += "                          %s);\n" % _exp_args(home_vals)
		s += "    Ms_Delay(20);\n"
	# 主控板 PWM 初始化
	if main_pwm.size() > 0:
		s += "    // 主控板舵机 PWM 初始化，初始占空比 = 初始角度对应值\n"
		for entry in main_pwm:
			var pwm_ch: String = entry["ch"]
			var ji: int = entry["joint"]
			s += "    PWM_Init(%s, 50, angle_to_duty(%d, jointHome[%d]));\n" % [pwm_ch, ji, ji]
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

class_name CodeGenEngineer
extends CodeGenBase

## 工程机器人代码生成器。
## 根据配置字典生成完整的工程机器人 main.c 代码。
## 左摇杆固定控制底盘 4 电机（L1-L4 来自 FirstRow），
## 右摇杆 X/Y 和各按键（A/B/C/D/↑↓←->/R）通过按键映射区分配到任意 IO。
## 控制模式：增量（仅舵机）、直接（舵机/电机）、速度（仅电机）、增速（仅电机）。

# 舵机占空比参数（SERVO_DUTY_MIN/MID/MAX 与 SERVO_MAX_OFFSET_DEG 继承自 CodeGenBase）
# 电机速度上限
const MOTOR_SPEED_MAX: int = 10000


# 扩展板引脚名（按槽位顺序）
const EXP_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]


# ============================================================ 代码生成
func generate(cfg: Dictionary) -> String:
	# --- 解析 FirstRow 共享参数 ---
	# 一律走 _int_or_default：非法/越界值回退到默认，保证生成的 C 代码总能编译
	var ch: String = _int_or_default(cfg.get("channel", ""), 36, 0, 125)
	var dz: String = _int_or_default(cfg.get("deadzone", ""), 10, 0, 2047)
	var normal_spd: String = _int_or_default(cfg.get("normal_speed", ""), 4000, 0, MOTOR_SPEED_MAX)
	var sprint_spd: String = _int_or_default(cfg.get("sprint_speed", ""), 8000, 0, MOTOR_SPEED_MAX)
	var sprint_enabled: bool = cfg.get("sprint_enabled", false) is bool \
		and cfg.get("sprint_enabled", false) == true

	# --- 底盘 IO 槽位 ---
	var l1_pin: String = _parse_io_pair(cfg.get("l1_io", "P74 P24"))
	var l2_pin: String = _parse_io_pair(cfg.get("l2_io", "P75 P25"))
	var r1_pin: String = _parse_io_pair(cfg.get("r1_io", "P76 P26"))
	var r2_pin: String = _parse_io_pair(cfg.get("r2_io", "P77 P27"))
	var l1_slot: int = _io_to_exp_slot(l1_pin)
	var l2_slot: int = _io_to_exp_slot(l2_pin)
	var r1_slot: int = _io_to_exp_slot(r1_pin)
	var r2_slot: int = _io_to_exp_slot(r2_pin)
	var l1_dir: int = _dir_to_int(cfg.get("l1_dir", "正向"))
	var l2_dir: int = _dir_to_int(cfg.get("l2_dir", "正向"))
	var r1_dir: int = _dir_to_int(cfg.get("r1_dir", "正向"))
	var r2_dir: int = _dir_to_int(cfg.get("r2_dir", "正向"))

	# --- 解析 IO 初始化区 ---
	# io_init: { "P60": "舵机", "P64": "电机", ... }
	var io_init: Dictionary = cfg.get("io_init", {})
	# slot_type[0..7]：每个扩展板槽位的类型 "电机" 或 "舵机"
	var slot_type: Array = []
	for i in range(8):
		var pin_name: String = EXP_PINS[i]
		var t: String = io_init.get(pin_name, "舵机")
		# 缺失或空值统一按舵机处理（与 ui.gd 静态检查的回退保持一致）
		if t.is_empty():
			t = "舵机"
		slot_type.append(t)
	# 底盘占用的槽位必须按电机初始化，否则该轮永远不动。
	# 与 IO 初始化区不一致时由静态检查报 Error，此处强制以底盘为准保证代码自洽。
	for cs in [l1_slot, l2_slot, r1_slot, r2_slot]:
		if cs >= 0:
			slot_type[cs] = "电机"

	# --- 解析按键映射区 ---
	# key_map: Array[Dictionary]，每项 {input, dir, mode, param, target}
	var key_map: Array = cfg.get("key_map", [])

	# --- 统计实际被引用的扩展板槽位 ---
	# 未被底盘或按键映射引用的槽位一律按「未使用」处理：
	# Init_Order 发 0（维持原状）、Duty_Change_Order 发 0。
	# 否则没配任何输入的舵机口会在上电时被强制打到中位，可能撞坏机构。
	var chassis_slots: Array = [l1_slot, l2_slot, r1_slot, r2_slot]
	var used_slots: Dictionary = {}
	for cs2 in chassis_slots:
		if cs2 >= 0:
			used_slots[cs2] = true
	for row0 in key_map:
		var t_pin: String = row0.get("target", "")
		if t_pin.is_empty() or t_pin in MAIN_BOARD_SERVO_PINS:
			continue
		var t_slot: int = _io_to_exp_slot(t_pin)
		if t_slot >= 0:
			used_slots[t_slot] = true

	# --- 分配舵机索引（扩展板，仅被引用的槽位）---
	# slot_servo_idx: slot -> servo_idx
	var slot_servo_idx: Dictionary = {}
	var servo_count: int = 0
	for i in range(8):
		if slot_type[i] == "舵机" and used_slots.has(i):
			slot_servo_idx[i] = servo_count
			servo_count += 1
	# 至少 1 个避免零长数组（C89 禁止零长数组）
	var servo_array_size: int = max(servo_count, 1)

	# --- 分配电机索引 ---
	# slot_motor_idx: slot -> motor_idx
	# 底盘 4 个固定索引 0-3
	var slot_motor_idx: Dictionary = {}
	for ci in range(4):
		if chassis_slots[ci] >= 0:
			slot_motor_idx[chassis_slots[ci]] = ci
	var next_motor_idx: int = 4

	# 为按键映射中涉及的电机槽位分配索引
	var processed_rows: Array = []
	# 主控板舵机是否被引用（未引用则不生成 PWM 初始化，避免无谓占用 PWMB 通道）
	var use_main_servo: Array = [false, false]
	for row in key_map:
		var target_pin: String = row.get("target", "")
		if target_pin.is_empty():
			continue # 跳过未配置的行
		var target_slot: int = _io_to_exp_slot(target_pin)
		var is_main_servo: bool = target_pin in MAIN_BOARD_SERVO_PINS
		# 既不在扩展板也不是 MP03/MP74 的引脚无法输出，直接跳过而不是当成主控板舵机
		if target_slot < 0 and not is_main_servo:
			push_warning("工程代码生成：未知目标引脚 %s，已忽略该行" % target_pin)
			continue
		var target_type: String = ""
		var motor_idx: int = -1
		var servo_idx: int = -1
		var main_servo_idx: int = -1

		if is_main_servo:
			# 主控板舵机（MP03/MP74）
			target_type = "舵机"
			main_servo_idx = 0 if target_pin == "MP03" else 1
			use_main_servo[main_servo_idx] = true
		else:
			target_type = slot_type[target_slot]
			if target_type == "电机":
				if slot_motor_idx.has(target_slot):
					motor_idx = slot_motor_idx[target_slot]
				else:
					motor_idx = next_motor_idx
					slot_motor_idx[target_slot] = next_motor_idx
					next_motor_idx += 1
			else:
				servo_idx = slot_servo_idx.get(target_slot, 0)

		processed_rows.append({
			"input": row.get("input", ""),
			"dir": row.get("dir", "正"),
			"mode": row.get("mode", "增量"),
			"param": row.get("param", "0"),
			"target_pin": target_pin,
			"target_slot": target_slot,
			"is_main_servo": is_main_servo,
			"target_type": target_type,
			"motor_idx": motor_idx,
			"servo_idx": servo_idx,
			"main_servo_idx": main_servo_idx,
		})

	var motor_array_size: int = next_motor_idx

	# --- 构建 Init_Order 频率参数 ---
	# 未被任何角色引用的槽位发 0，表示维持原状，不把它配成动力输出
	var init_vals: Array = []
	for i in range(8):
		if not used_slots.has(i):
			init_vals.append(0)
		elif slot_type[i] == "电机":
			init_vals.append(10000)
		else:
			init_vals.append(50)

	# --- 构建 Dir_Change_Order 方向表达式 ---
	var dir_exprs: Array = []
	for i in range(8):
		if slot_type[i] == "电机" and slot_motor_idx.has(i):
			dir_exprs.append("Get_Dir(dutyOfMotor[%d])" % slot_motor_idx[i])
		else:
			dir_exprs.append("1")

	# --- 构建 Duty_Change_Order 占空比表达式 ---
	var duty_vals: Array = []
	for i in range(8):
		if not used_slots.has(i):
			duty_vals.append("0")
		elif slot_type[i] == "电机":
			if slot_motor_idx.has(i):
				duty_vals.append("(uint16_t)abs(dutyOfMotor[%d])" % slot_motor_idx[i])
			else:
				duty_vals.append("0")
		elif slot_servo_idx.has(i):
			duty_vals.append("dutyOfServo[%d]" % slot_servo_idx[i])
		else:
			duty_vals.append("0")

	# --- 底盘电机公式 ---
	var l1_formula: String = "-baseSpeed - turnSpeed" if l1_dir == 1 else "baseSpeed + turnSpeed"
	var l2_formula: String = "-baseSpeed - turnSpeed" if l2_dir == 1 else "baseSpeed + turnSpeed"
	var r1_formula: String = "baseSpeed - turnSpeed" if r1_dir == 1 else "-baseSpeed + turnSpeed"
	var r2_formula: String = "baseSpeed - turnSpeed" if r2_dir == 1 else "-baseSpeed + turnSpeed"

	# --- 冲刺逻辑 ---
	# 符号约定：baseSpeed > 0 = 前进，turnSpeed > 0 = 向右转，与步兵生成器一致
	var sprint_code: String = ""
	if sprint_enabled:
		sprint_code = "    // 冲刺模式：按下左摇杆时使用冲刺速度\n" \
			+"    if (valueOfKey[2][0])\n" \
			+"    {\n" \
			+"        baseSpeed = (int)((float)valueOfRoker[0][1] * ultraSpeed / 2047);\n" \
			+"        turnSpeed = (int)((float)valueOfRoker[0][0] * ultraSpeed / 2047);\n" \
			+"    }\n" \
			+"    else\n" \
			+"    {\n" \
			+"        baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n" \
			+"        turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n" \
			+"    }\n"
	else:
		sprint_code = "    baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n" \
			+"    turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n"

	# --- 生成字符串 ---
	var init_str: String = "%d, %d,\n                          %d, %d,\n                          %d, %d,\n                          %d, %d" % [init_vals[0], init_vals[1], init_vals[2], init_vals[3], init_vals[4], init_vals[5], init_vals[6], init_vals[7]]
	var dir_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [dir_exprs[0], dir_exprs[1], dir_exprs[2], dir_exprs[3], dir_exprs[4], dir_exprs[5], dir_exprs[6], dir_exprs[7]]
	var duty_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [duty_vals[0], duty_vals[1], duty_vals[2], duty_vals[3], duty_vals[4], duty_vals[5], duty_vals[6], duty_vals[7]]

	# --- 生成按键映射控制代码 ---
	var motor_calc_code: String = _gen_motor_calc_code(processed_rows)
	var servo_calc_code: String = _gen_servo_calc_code(processed_rows)

	# --- PWM 初始化/设置行（主控板舵机，仅在被按键映射引用时生成）---
	# MP03 = PWMB_CH4_P03，MP74 = PWMB_CH1_P74（与扩展板 P74 是不同的 IO）
	var main_servo_chn: Array = ["PWMB_CH4_P03", "PWMB_CH1_P74"]
	var main_servo_name: Array = ["MP03", "MP74"]
	var pwm_init_lines: String = ""
	var pwm_set_lines: String = ""
	for si in range(2):
		if not use_main_servo[si]:
			continue
		pwm_init_lines += "    PWM_Init(%s, 50, %d); // %s 舵机归中\n" \
			% [main_servo_chn[si], SERVO_DUTY_MID, main_servo_name[si]]
		pwm_set_lines += "    PWM_SET_Frequency(%s, 50, dutyOfMainServo%d);\n" \
			% [main_servo_chn[si], si]

	# --- 限幅代码 ---
	var motor_limit_code: String = ""
	for mi in range(motor_array_size):
		motor_limit_code += "        LIMIT_VALUE(dutyOfMotor[%d], -10000, 10000);\n" % mi
	var servo_limit_code: String = ""
	if servo_count > 0:
		servo_limit_code += "        for (i = 0; i < %d; i++)\n" % servo_count \
			+"            LIMIT_VALUE(floatDutyOfServo[i], %d, %d);\n" % [SERVO_DUTY_MIN, SERVO_DUTY_MAX]
	for si in range(2):
		if use_main_servo[si]:
			servo_limit_code += "        LIMIT_VALUE(floatDutyOfMainServo%d, %d, %d);\n" \
				% [si, SERVO_DUTY_MIN, SERVO_DUTY_MAX]

	# --- 舵机 float->uint16 拷贝 ---
	var servo_copy_code: String = ""
	if servo_count > 0:
		servo_copy_code += "        for (i = 0; i < %d; i++)\n" % servo_count \
			+"            dutyOfServo[i] = (uint16_t)floatDutyOfServo[i];\n"
	for si in range(2):
		if use_main_servo[si]:
			servo_copy_code += "        dutyOfMainServo%d = (uint16_t)floatDutyOfMainServo%d;\n" % [si, si]

	# --- 舵机初始化代码 ---
	var servo_init_code: String = ""
	if servo_count > 0:
		servo_init_code += "    for (i = 0; i < %d; i++)\n" % servo_count \
			+"    {\n" \
			+"        dutyOfServo[i] = %d;\n" % SERVO_DUTY_MID \
			+"        floatDutyOfServo[i] = %d.0f;\n" % SERVO_DUTY_MID \
			+"    }\n"
	for si in range(2):
		if use_main_servo[si]:
			servo_init_code += "    floatDutyOfMainServo%d = %d.0f;\n" % [si, SERVO_DUTY_MID]

	# --- 主控板舵机变量声明 ---
	var main_servo_decl: String = ""
	for si in range(2):
		if use_main_servo[si]:
			main_servo_decl += "float floatDutyOfMainServo%d; // 主控板舵机 %s\n" % [si, main_servo_name[si]]
			main_servo_decl += "uint16_t dutyOfMainServo%d;\n" % si

	# ================================================================
	# 组装完整 main.c
	# ================================================================
	var code: String = ""
	code += "// 工程机器人操作代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "// ========================= 参数区 =========================\n"
	code += "uint8_t Channal = %s;                          // NRF24L01 通信通道（0-125），与遥控器一致\n" % ch
	code += "uint16_t maxSpeed = %s;                         // 底盘普通速度\n" % normal_spd
	code += "uint16_t ultraSpeed = %s;                       // 底盘冲刺速度\n" % sprint_spd
	code += "uint16_t deadBandOfLeft = %s;                   // 左摇杆中心死区\n" % dz
	code += "uint16_t deadBandOfRight = %s;                  // 右摇杆中心死区\n" % dz
	code += "#define LIMIT_VALUE(x, min, max) \\\n"
	code += "    do                           \\\n"
	code += "    {                            \\\n"
	code += "        if ((x) < (min))         \\\n"
	code += "            (x) = (min);         \\\n"
	code += "        else if ((x) > (max))    \\\n"
	code += "            (x) = (max);         \\\n"
	code += "    } while (0)\n"
	code += "/*帧头帧尾，内部调用，无需关心*/\n"
	code += "#define COMM_HEADER_1 0xAB\n#define COMM_HEADER_2 0xBC\n#define COMM_END_1 0xCD\n#define COMM_END_2 0xDE\n"
	code += "/*命令码*/\n"
	code += "#define Init_Order 0xAA        // 初始化模式\n"
	code += "#define Duty_Change_Order 0xBB // 修改占空比\n"
	code += "#define Freq_Change_Order 0xCC // 修改频率\n"
	code += "#define Dir_Change_Order 0xDD  // 修改方向 1为正 0为负 设置一次即可\n"
	code += "#define Zero_Order 0xEE        // 0命令\n"
	code += "/*内部调用变量，无需关心，请勿定义同名变量*/\n"
	code += "uint16_t control_data[8] = {0};\n"
	code += "uint16_t motor_dir[8] = {0};\n"
	code += "uint8_t control_command = 0x00;\n"
	code += "// 自定义变量\n"
	code += "float floatDutyOfServo[%d];   // 扩展板舵机浮点占空比\n" % servo_array_size
	code += "uint16_t dutyOfServo[%d];      // 扩展板舵机占空比\n" % servo_array_size
	code += "int dutyOfMotor[%d];          // 电机控制值（底盘+其他）\n" % motor_array_size
	code += main_servo_decl
	code += "uint8_t valueOfKey[3][4];\n"
	code += "uint8_t valueOfRKey;\n"
	code += "uint8_t i, j;\n"
	code += "int valueOfRoker[2][2] // 左摇杆水平、竖直；右摇杆水平、竖直\n"
	code += "    ,\n"
	code += "    baseSpeed, turnSpeed;\n"
	code += "static const uint8_t keyOffsets[3][4] = {\n"
	code += "    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},\n"
	code += "    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},\n"
	code += "    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个\n"
	code += "};\n\n"
	# 函数声明
	code += "void All_Init();\n"
	code += "void Read_Controller_Inputs();\n"
	code += "void Calculate_Motor_Controls();\n"
	code += "void Calculate_Servo_Controls();\n"
	code += "uint8_t Get_Dir(int rawdata);\n"
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	# ISP 自烧录监听代码
	code += _gen_isp_monitor()
	# 烧录模式（P06+P07 进入蓝牙 OTA）：共享代码 + 构型停机/重初始化函数
	code += _gen_burn_mode_shared()
	code += "void burnSafeStop(void)\n{\n"
	code += "    uint8_t k;\n"
	code += "    for (k = 0; k < %d; k++)\n" % motor_array_size
	code += "        dutyOfMotor[k] = 0;\n"
	if servo_count > 0:
		code += "    for (k = 0; k < %d; k++)\n" % servo_count
		code += "    {\n"
		code += "        floatDutyOfServo[k] = %d.0f;\n" % SERVO_DUTY_MID
		code += "        dutyOfServo[k] = %d;\n" % SERVO_DUTY_MID
		code += "    }\n"
	for si in range(2):
		if use_main_servo[si]:
			code += "    floatDutyOfMainServo%d = %d.0f;\n" % [si, SERVO_DUTY_MID]
			code += "    dutyOfMainServo%d = %d;\n" % [si, SERVO_DUTY_MID]
	code += "    Main_Countrol(dutyOfMotor, dutyOfServo);\n"
	code += "}\n\n"
	code += "void burnExtReinit(void)\n{\n"
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          %s); // p60,p62,p64,p66,p74,p75,p76,p77\n" % init_str
	code += "    Ms_Delay(20);\n"
	code += "}\n\n"
	code += CodeGenBase.REMOTE_CONTROL_INIT_CODE

	# --- main() ---
	code += "void main()\n"
	code += "{\n"
	code += "    All_Init();\n"
	code += servo_init_code
	code += "    while (1)\n"
	code += "    {\n"
	code += _gen_isp_check_call()
	code += _gen_burn_mode_loop()
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n\n"
	code += "        Read_Controller_Inputs();\n"
	code += "        Calculate_Motor_Controls();\n"
	code += "        Calculate_Servo_Controls();\n"
	code += motor_limit_code
	code += servo_limit_code
	code += "\n"
	code += servo_copy_code
	code += "\n"
	code += "        Main_Countrol(dutyOfMotor, dutyOfServo);\n"
	code += "        Ms_Delay(10);\n"
	code += "    }\n"
	code += "}\n\n"

	# --- Get_Dir ---
	code += "uint8_t Get_Dir(int rawdata)\n"
	code += "{\n"
	code += "    if (rawdata >= 0)\n"
	code += "        return 1;\n"
	code += "    else\n"
	code += "        return 0;\n"
	code += "}\n\n"

	# 注：偏移角 -> 占空比的换算全部在生成期完成（见基类 _servo_angle_to_duty）。
	# 不在 C 侧算 `角度 * duty跨度 / 角度跨度`：C251 的 int 是 16 位
	# （common.h: int16_t = signed int），实测编译出 `MUL WR6,WR2` 为 16 位乘法，
	# 结果不提升到 32 位。duty 跨度 1000 时 angle > 32° 即溢出，且编译器不报警。

	# --- All_Init ---
	code += "void All_Init()\n"
	code += "{\n"
	code += "    Board_Init();\n"
	code += _gen_uart_init_first()
	code += "    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);\n"
	code += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);\n"
	code += "    remoteControlInitWithTimeout();\n"
	code += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);\n"
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          %s); // p60,p62,p64,p66,p74,p75,p76,p77\n" % init_str
	code += "    Ms_Delay(20);\n"
	code += pwm_init_lines
	code += _gen_burn_mode_init()
	code += "}\n\n"

	# --- Read_Controller_Inputs ---
	code += "void Read_Controller_Inputs()\n"
	code += "{\n"
	code += "    // 摇杆读数读取\n"
	code += "    valueOfRoker[0][0] = RcRockerValueRead(ROCKER_LEFT_HORIZONTAL);\n"
	code += "    valueOfRoker[0][1] = RcRockerValueRead(ROCKER_LEFT_VERTICAL);\n"
	code += "    valueOfRoker[1][0] = RcRockerValueRead(ROCKER_RIGHT_HORIZONTAL);\n"
	code += "    valueOfRoker[1][1] = RcRockerValueRead(ROCKER_RIGHT_VERTICAL);\n"
	code += "    // 死区过滤\n"
	code += "    if (abs(valueOfRoker[0][0]) <= deadBandOfLeft)\n"
	code += "        valueOfRoker[0][0] = 0;\n"
	code += "    if (abs(valueOfRoker[0][1]) <= deadBandOfLeft)\n"
	code += "        valueOfRoker[0][1] = 0;\n"
	code += "    if (abs(valueOfRoker[1][0]) <= deadBandOfRight)\n"
	code += "        valueOfRoker[1][0] = 0;\n"
	code += "    if (abs(valueOfRoker[1][1]) <= deadBandOfRight)\n"
	code += "        valueOfRoker[1][1] = 0;\n\n"
	code += "    for (i = 0; i < 3; i++)\n"
	code += "    {\n"
	code += "        for (j = 0; j < 4; j++)\n"
	code += "        {\n"
	code += "            if (i == 2 && j >= 2)\n"
	code += "                break;\n"
	code += "            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);\n"
	code += "        }\n"
	code += "    }\n"
	code += "    valueOfRKey = RcKeyValueRead(KEY_OFFSET_1);\n"
	code += "}\n\n"

	# --- Calculate_Motor_Controls ---
	code += "void Calculate_Motor_Controls()\n"
	code += "{\n"
	code += sprint_code
	code += "\n"
	code += "    dutyOfMotor[0] = %s;\n" % l1_formula
	code += "    dutyOfMotor[1] = %s;\n" % l2_formula
	code += "    dutyOfMotor[2] = %s;\n" % r1_formula
	code += "    dutyOfMotor[3] = %s;\n" % r2_formula
	if not motor_calc_code.is_empty():
		code += "\n    // 按键映射：电机控制\n"
		code += motor_calc_code
	code += "}\n\n"

	# --- Calculate_Servo_Controls ---
	code += "void Calculate_Servo_Controls()\n"
	code += "{\n"
	if not servo_calc_code.is_empty():
		code += "    // 按键映射：舵机控制\n"
		code += servo_calc_code
		code += "\n"
	code += "}\n\n"

	# --- Main_Countrol ---
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo)\n"
	code += "{\n"
	code += "    ExpansionBoradControl(Dir_Change_Order,\n"
	code += "                          %s);\n" % dir_str
	code += "    Ms_Delay(5);\n"
	code += "    ExpansionBoradControl(Duty_Change_Order,\n"
	code += "                          %s);\n" % duty_str
	code += "    Ms_Delay(5);\n"
	code += pwm_set_lines
	code += "}\n\n"

	# --- ExpansionBoradControl ---
	code += _gen_expansion_board_control()

	return code


# ============================================================ 辅助函数

## 生成按键映射中电机控制代码（速度/增速/直接 模式）
## 同一电机可被多行驱动：摇杆行先算出基础值，按键「直接」行再按 if / else if 链覆盖。
## 仅当该电机全部由「直接」行驱动时，才在链尾补 else 归零；
## 否则归零会把摇杆算出的值抹掉。
func _gen_motor_calc_code(rows: Array) -> String:
	# 按 motor_idx 分组，保留行顺序
	var order: Array = []
	var groups: Dictionary = {}
	for row in rows:
		if row.target_type != "电机":
			continue
		var mi: int = row.motor_idx
		if not groups.has(mi):
			groups[mi] = []
			order.append(mi)
		groups[mi].append(row)

	var code: String = ""
	for mi in order:
		var group: Array = groups[mi]
		# 该电机是否存在摇杆驱动行（速度/增速）
		var has_joystick: bool = false
		for row in group:
			if _input_to_c_expr(row.input).get("is_joystick", false):
				has_joystick = true
				break
		# 先生成摇杆行：「速度」是赋值，必须全部排在「增速」（+=）之前，
		# 否则按 UI 行序输出时速度行会把先前的增速结果整个抹掉
		for pass_mode in ["速度", "增速"]:
			for row in group:
				var info: Dictionary = _input_to_c_expr(row.input)
				if not info.get("is_joystick", false):
					continue
				if row.mode != pass_mode:
					continue
				var sign_j: String = "" if row.dir == "正" else "-"
				var p_j: int = _parse_param(row.param, 0, MOTOR_SPEED_MAX)
				var r: int = info["rocker_row"]
				var c: int = info["rocker_col"]
				var op: String = "=" if pass_mode == "速度" else "+="
				code += "    dutyOfMotor[%d] %s %s(int)((float)valueOfRoker[%d][%d] * %d / 2047);\n" \
					% [mi, op, sign_j, r, c, p_j]
		# 再生成按键「直接」行，串成 if / else if 链
		var direct_rows: Array = []
		for row in group:
			if _input_to_c_expr(row.input).get("is_joystick", false):
				continue
			if row.mode == "直接":
				direct_rows.append(row)
		for idx in range(direct_rows.size()):
			var drow: Dictionary = direct_rows[idx]
			var sign_d: String = "" if drow.dir == "正" else "-"
			var p_d: int = _parse_param(drow.param, 0, MOTOR_SPEED_MAX)
			var key_expr: String = _key_expr(_input_to_c_expr(drow.input))
			var kw: String = "if" if idx == 0 else "else if"
			code += "    %s (%s)\n" % [kw, key_expr]
			code += "        dutyOfMotor[%d] = %s%d;\n" % [mi, sign_d, p_d]
		# 仅在没有摇杆基础值时才归零（松开按键停转）
		if not direct_rows.is_empty() and not has_joystick:
			code += "    else\n"
			code += "        dutyOfMotor[%d] = 0;\n" % mi
	return code


## 生成按键映射中舵机控制代码（增量/直接 模式）
func _gen_servo_calc_code(rows: Array) -> String:
	var code: String = ""
	for row in rows:
		if row.target_type != "舵机":
			continue
		var mode: String = row.mode
		var dir_sign: int = 1 if row.dir == "正" else -1
		var sign_str: String = "" if dir_sign == 1 else "-"
		var input_info: Dictionary = _input_to_c_expr(row.input)
		var is_joystick: bool = input_info.get("is_joystick", false)

		# 目标变量名
		var target_var: String = ""
		if row.is_main_servo:
			target_var = "floatDutyOfMainServo%d" % row.main_servo_idx
		else:
			target_var = "floatDutyOfServo[%d]" % row.servo_idx

		match mode:
			"增量":
				# 步长取正值，方向由「正/反」决定，故限幅到 [0, 90]
				var step_deg: int = _parse_param(row.param, 0, SERVO_MAX_OFFSET_DEG)
				# 角度增量 -> 占空比增量（生成期换算，避免 C251 16 位 int 溢出）
				var duty_inc: int = _servo_deg_to_duty_delta(float(step_deg))
				if is_joystick:
					var r: int = input_info["rocker_row"]
					var c: int = input_info["rocker_col"]
					code += "    %s += %s(float)valueOfRoker[%d][%d] * %d / 2047.0f;\n" % [target_var, sign_str, r, c, duty_inc]
				else:
					var key_expr: String = _key_expr(input_info)
					code += "    if (%s)\n" % key_expr
					code += "        %s += %s%d;\n" % [target_var, sign_str, duty_inc]
			"直接":
				if not is_joystick:
					# 目标偏移角本身带符号，方向选项对该模式无意义（静态检查会提示）
					var angle: int = _parse_param(row.param,
						- SERVO_MAX_OFFSET_DEG, SERVO_MAX_OFFSET_DEG)
					var target_duty: int = _servo_angle_to_duty(angle)
					var key_expr2: String = _key_expr(input_info)
					code += "    if (%s)\n" % key_expr2
					code += "        %s = %d.0f; // %+d°\n" % [target_var, target_duty, angle]
	return code


## 输入名 -> C 表达式信息
func _input_to_c_expr(input_name: String) -> Dictionary:
	match input_name:
		"右摇杆X":
			return {"is_joystick": true, "rocker_row": 1, "rocker_col": 0}
		"右摇杆Y":
			return {"is_joystick": true, "rocker_row": 1, "rocker_col": 1}
		"A":
			return {"is_joystick": false, "key_row": 1, "key_col": 0}
		"B":
			return {"is_joystick": false, "key_row": 1, "key_col": 1}
		"C":
			return {"is_joystick": false, "key_row": 1, "key_col": 2}
		"D":
			return {"is_joystick": false, "key_row": 1, "key_col": 3}
		"↑":
			return {"is_joystick": false, "key_row": 0, "key_col": 0}
		"↓":
			return {"is_joystick": false, "key_row": 0, "key_col": 1}
		"←":
			return {"is_joystick": false, "key_row": 0, "key_col": 2}
		"->":
			return {"is_joystick": false, "key_row": 0, "key_col": 3}
		"R":
			return {"is_joystick": false, "is_r_key": true}
		_:
			return {"is_joystick": false, "key_row": 0, "key_col": 0}


## 从输入信息生成按键条件表达式
func _key_expr(input_info: Dictionary) -> String:
	if input_info.get("is_r_key", false):
		return "valueOfRKey"
	var kr: int = input_info.get("key_row", 0)
	var kc: int = input_info.get("key_col", 0)
	return "valueOfKey[%d][%d]" % [kr, kc]


## 解析参数字符串为整数，并限制到 [lo, hi]。
## 限幅必需：C251 的 int 是 16 位，未限幅的大参数会在 C 侧溢出。
func _parse_param(param_str: String, lo: int, hi: int) -> int:
	var s: String = param_str.strip_edges()
	if not s.is_valid_int():
		return 0
	return clampi(s.to_int(), lo, hi)


## 生成 ExpansionBoradControl 函数
func _gen_expansion_board_control() -> String:
	var code: String = ""
	code += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	code += "/// @param control_cmd\n"
	code += "/// @param data_p60\n"
	code += "/// @param data_p62\n"
	code += "/// @param data_p64\n"
	code += "/// @param data_p66\n"
	code += "/// @param data_p74\n"
	code += "/// @param data_p75\n"
	code += "/// @param data_p76\n"
	code += "/// @param data_p77\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77)\n"
	code += "{\n"
	code += "    uint8_t i = 0;\n"
	code += "    uint8_t control_frame_pack[21] = {0};\n"
	code += "    control_frame_pack[0] = COMM_HEADER_1;\n"
	code += "    control_frame_pack[1] = COMM_HEADER_2;\n"
	code += "    control_frame_pack[19] = COMM_END_1;\n"
	code += "    control_frame_pack[20] = COMM_END_2;\n"
	code += "    control_frame_pack[2] = control_cmd;\n"
	code += "    control_frame_pack[3] = (uint8_t)((data_p60 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[4] = (uint8_t)(data_p60 & 0xFF);\n"
	code += "    control_frame_pack[5] = (uint8_t)((data_p62 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[6] = (uint8_t)(data_p62 & 0xFF);\n"
	code += "    control_frame_pack[7] = (uint8_t)((data_p64 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[8] = (uint8_t)(data_p64 & 0xFF);\n"
	code += "    control_frame_pack[9] = (uint8_t)((data_p66 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[10] = (uint8_t)(data_p66 & 0xFF);\n"
	code += "    control_frame_pack[11] = (uint8_t)((data_p74 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[12] = (uint8_t)(data_p74 & 0xFF);\n"
	code += "    control_frame_pack[13] = (uint8_t)((data_p75 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[14] = (uint8_t)(data_p75 & 0xFF);\n"
	code += "    control_frame_pack[15] = (uint8_t)((data_p76 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[16] = (uint8_t)(data_p76 & 0xFF);\n"
	code += "    control_frame_pack[17] = (uint8_t)((data_p77 >> 8) & 0xFF);\n"
	code += "    control_frame_pack[18] = (uint8_t)(data_p77 & 0xFF);\n"
	code += "    for (i = 0; i < 21; i++)\n"
	code += "        UART_PutChar(UART_1, control_frame_pack[i]);\n"
	code += "}\n"
	return code

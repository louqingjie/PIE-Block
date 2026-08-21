class_name CodeGenEngineer
extends CodeGenBase

## 工程机器人多模式代码生成器。
## 根据配置字典生成完整的工程机器人 main.c 代码。
## 新配置模型：
##   - FirstRow 共享参数（通道/死区/底盘/速度）不变
##   - io_init / io_mid：全局 IO 初始化区（10 引脚的类型 + 舵机初始角）
##   - 模式配置：mode_count(1~4)、切换方式（单击切换 / 一一对应）、模式键
##   - modes[1..4]：每模式一组动态按键映射行
## 行模型：{key, dir, mode, param, io}
##   key ∈ E/↑/↓/←/→/A/B/C/D/LC/RC（按键） 或 LX/LY/RX/RY（摇杆轴）
##   mode ∈ 增量/直接（舵机），直接/速度/增速（电机），增量/速度/增速（摇杆行）

# 舵机占空比参数（SERVO_DUTY_MIN/MID/MAX 与 SERVO_MAX_OFFSET_DEG 继承自 CodeGenBase）
# 电机速度上限（MOTOR_SPEED_MAX 继承自 CodeGenBase）
# 扩展板引脚名（按槽位顺序）
const EXP_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
# 主控板舵机引脚（固定舵机，与扩展板 P74 不同）
const MAIN_PINS: Array = ["MP03", "MP74"]
# 模式数上限
const MODE_MAX: int = 4


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
	var chassis_slots: Array = [l1_slot, l2_slot, r1_slot, r2_slot]
	var l1_dir: int = _dir_to_int(cfg.get("l1_dir", "正向"))
	var l2_dir: int = _dir_to_int(cfg.get("l2_dir", "正向"))
	var r1_dir: int = _dir_to_int(cfg.get("r1_dir", "正向"))
	var r2_dir: int = _dir_to_int(cfg.get("r2_dir", "正向"))

	# --- IO 初始化区（10 引脚全局配置）---
	# io_init: {pin: "舵机"/"电机"}；底盘槽位必须按电机初始化
	var io_init: Dictionary = {}
	for pin in EXP_PINS + MAIN_PINS:
		var t: String = str((cfg.get("io_init", {}) as Dictionary).get(pin, "舵机"))
		io_init[pin] = "电机" if t == "电机" else "舵机"
	for cs in chassis_slots:
		if cs >= 0:
			io_init[EXP_PINS[cs]] = "电机"
	var io_mid: Dictionary = cfg.get("io_mid", {})

	# --- 模式配置 ---
	var mode_count: int = clampi(int(cfg.get("mode_count", 1)), 1, MODE_MAX)
	var switch_strategy: String = str(cfg.get("switch_strategy", "单击切换"))
	var switch_key: String = str(cfg.get("mode_switch_key", "E"))
	var mode_keys: Array = cfg.get("mode_keys", [])
	var modes: Array = cfg.get("modes", [])

	# --- 统计被引用的槽位与主控板舵机 ---
	# aux_servo_slots / aux_motor_slots：行指向的扩展板槽位（底盘槽位除外）
	var aux_servo_slots: Array = []
	var aux_motor_slots: Array = []
	var use_main_servo: Array = [false, false]
	for mi in range(mini(mode_count, modes.size())):
		for row in (modes[mi].get("rows", []) as Array):
			var io: String = str(row.get("io", ""))
			var slot: int = _io_to_exp_slot(io)
			if slot >= 0:
				if slot in chassis_slots:
					continue
				if io_init.get(io, "舵机") == "电机":
					if not slot in aux_motor_slots:
						aux_motor_slots.append(slot)
				elif not slot in aux_servo_slots:
					aux_servo_slots.append(slot)
			elif io == "MP03":
				use_main_servo[0] = true
			elif io == "MP74":
				use_main_servo[1] = true

	# 舵机蜂鸣反馈固定按物理通道顺序检查：扩展板 P60~P77，再检查 MP03、MP74。
	# 只纳入实际被模式配置使用的舵机，避免生成无效数组访问。
	var servo_buzzer_exprs: Array = []
	for slot in range(EXP_PINS.size()):
		if slot in aux_servo_slots:
			servo_buzzer_exprs.append("(uint16_t)dutyOfAuxServo[%d]" % slot)
	if use_main_servo[0]:
		servo_buzzer_exprs.append("(uint16_t)dutyOfAuxMainServo[0]")
	if use_main_servo[1]:
		servo_buzzer_exprs.append("(uint16_t)dutyOfAuxMainServo[1]")

	# --- 底盘电机公式 ---
	var l1_formula: String = "-baseSpeed - turnSpeed" if l1_dir == 1 else "baseSpeed + turnSpeed"
	var l2_formula: String = "-baseSpeed - turnSpeed" if l2_dir == 1 else "baseSpeed + turnSpeed"
	var r1_formula: String = "baseSpeed - turnSpeed" if r1_dir == 1 else "-baseSpeed + turnSpeed"
	var r2_formula: String = "baseSpeed - turnSpeed" if r2_dir == 1 else "-baseSpeed + turnSpeed"

	# --- 冲刺逻辑 ---
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

	# --- 每模式控制函数 ---
	var mode_funcs: String = ""
	for mi in range(mode_count):
		var rows: Array = modes[mi].get("rows", []) if mi < modes.size() else []
		mode_funcs += _gen_mode_rows(rows, io_init, "Mode%d" % (mi + 1))

	# --- 限幅代码（主循环内）---
	var limit_code: String = ""
	for i in range(4):
		if chassis_slots[i] >= 0:
			limit_code += "        LIMIT_VALUE(dutyOfChassis[%d], -10000, 10000);\n" % i
	for slot in aux_motor_slots:
		limit_code += "        LIMIT_VALUE(dutyOfAuxMotor[%d], -10000, 10000);\n" % slot
	for slot in aux_servo_slots:
		limit_code += "        LIMIT_VALUE(dutyOfAuxServo[%d], %d, %d);\n" % [slot, SERVO_DUTY_MIN, SERVO_DUTY_MAX]
	for si in range(2):
		if use_main_servo[si]:
			limit_code += "        LIMIT_VALUE(dutyOfAuxMainServo[%d], %d, %d);\n" % [si, SERVO_DUTY_MIN, SERVO_DUTY_MAX]

	# --- 舵机初始占空比（生成期按 io_mid 换算，避免 C251 16 位 int 溢出）---
	var servo_home: Dictionary = {}
	for slot in aux_servo_slots:
		servo_home[slot] = _io_mid_duty(io_mid, EXP_PINS[slot])
	var main_home: Array = [
		_io_mid_duty(io_mid, "MP03") if use_main_servo[0] else SERVO_DUTY_MID,
		_io_mid_duty(io_mid, "MP74") if use_main_servo[1] else SERVO_DUTY_MID,
	]

	# --- 组装完整 main.c ---
	var code: String = ""
	code += "// 工程机器人多模式操作代码（由 Pie-Block 配置生成器自动生成）\n"
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
	code += "int dutyOfChassis[4];          // 底盘四个电机控制值\n"
	code += "int dutyOfAuxMotor[8];          // 映射模式下的其他扩展板电机（按槽位）\n"
	code += "float dutyOfAuxServo[8];        // 映射模式下的其他扩展板舵机（按槽位）\n"
	code += "float dutyOfAuxMainServo[2];    // 映射模式下的 MP03/MP74 舵机\n"
	code += "uint8_t currentMode = 1;        // 当前模式（1~%d），开机固定模式1\n" % mode_count
	code += "uint8_t modeKeyHeld = 0;        // 单击切换键锁存\n"
	if mode_count > 1 and not aux_motor_slots.is_empty():
		code += "uint8_t prevMode = 1;        // 上一次模式，切换后未映射的辅助电机下电\n"
	if switch_strategy == "一一对应" and mode_count > 1:
		code += "uint8_t modeKeyLast[4] = {0};  // 一一对应各模式键锁存\n"
	code += "uint8_t valueOfKey[3][4];\n"
	code += "uint8_t valueOfEKey;\n"
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
	code += "void UpdateMode();\n"
	code += "void Calculate_Chassis_Control();\n"
	for mi in range(mode_count):
		code += "void Calculate_Mode%d_Controls();\n" % (mi + 1)
	code += "void Main_Countrol();\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	code += CodeGenBase.REMOTE_CONTROL_INIT_CODE
	# 初始化诊断工具（LED + 蜂鸣器）与 UART1 查询发送（修复 UART 死锁）
	code += _gen_led_diag_tools()
	if mode_count > 1:
		code += _gen_mode_switch_feedback()
	code += CodeGenBase.UART_TX_QUERY_CODE
	code += _gen_servo_buzzer_tools(servo_buzzer_exprs)

	# --- main() ---
	code += "void main()\n"
	code += "{\n"
	code += "    All_Init();\n"
	code += "    // 舵机初始占空比（按 IO 初始化区的初始角，生成期换算）\n"
	for slot in aux_servo_slots:
		code += "    dutyOfAuxServo[%d] = %d.0f;\n" % [slot, servo_home[slot]]
	for si in range(2):
		if use_main_servo[si]:
			code += "    dutyOfAuxMainServo[%d] = %d.0f;\n" % [si, main_home[si]]
	code += "    while (1)\n"
	code += "    {\n"
	code += _gen_nrf_poll()
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n\n"
	code += "        Read_Controller_Inputs();\n"
	code += "        UpdateMode();\n"
	code += "        Calculate_Chassis_Control();\n"
	code += "        switch (currentMode)\n"
	code += "        {\n"
	for mi in range(mode_count):
		code += "            case %d:\n" % (mi + 1)
		code += "                Calculate_Mode%d_Controls();\n" % (mi + 1)
		code += "                break;\n"
	code += "            default:\n"
	code += "                break;\n"
	code += "        }\n"
	code += limit_code
	code += "\n"
	code += "        Main_Countrol();\n"
	if not servo_buzzer_exprs.is_empty():
		code += "        UpdateBuzzerFeedback();\n"
	code += "        Ms_Delay(10);\n"
	code += "    }\n"
	code += "}\n\n"

	# --- All_Init ---
	code += "void All_Init()\n"
	code += "{\n"
	code += "    // 初始化诊断分步：卡在哪步，LED 就停在对应编码（P37 P36 P35 二进制）\n"
	code += "    //   000 上电   001 Board_Init   010 UART1   011 LED 自检\n"
	code += "    //   100 NRF遥控 101 拓展板 Init 110 PWM/舵机 111 完成\n"
	code += "    StepBegin(0);\n"
	code += "    Board_Init();\n"
	code += "    StepDone(0);\n"
	code += "    StepBegin(1);\n"
	code += _gen_uart_init_first()
	code += "    StepDone(1);\n"
	code += "    StepBegin(2);\n"
	code += _gen_led_diag_init()
	code += "    StepDone(2);\n"
	code += "    StepBegin(3);\n"
	code += _gen_nrf_init_safe()
	code += "    StepDone(3);\n"
	code += "    StepBegin(4);\n"
	# Init_Order 频率参数：每个扩展板槽位都必须是有效 PWM 频率，不能传 0。
	var init_vals: Array = []
	for pin in EXP_PINS:
		init_vals.append("10000" if str(io_init.get(pin, "舵机")) == "电机" else "50")
	var duty_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
	for slot in aux_servo_slots:
		init_vals[slot] = "50"
		duty_vals[slot] = "%d" % servo_home[slot]
	for i in range(4):
		if chassis_slots[i] >= 0:
			init_vals[chassis_slots[i]] = "10000"
	for slot in aux_motor_slots:
		init_vals[slot] = "10000"
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          %s); // p60,p62,p64,p66,p74,p75,p76,p77\n" % _exp_args(init_vals)
	code += "    Ms_Delay(20);\n"
	code += "    // 上电先推到初始状态（舵机初始角 / 电机停转）\n"
	code += "    ExpansionBoradControl(Duty_Change_Order,\n"
	code += "                          %s);\n" % _exp_args(duty_vals)
	code += "    Ms_Delay(20);\n"
	code += "    StepDone(4);\n"
	code += "    StepBegin(5);\n"
	# 主控板舵机 PWM 初始化（初始占空比 = 初始角对应值）
	var main_chn: Array = ["PWMB_CH4_P03", "PWMB_CH1_P74"]
	for si in range(2):
		if use_main_servo[si]:
			code += "    PWM_Init(%s, 50, %d); // %s 舵机初始角\n" % [main_chn[si], main_home[si], MAIN_PINS[si]]
	code += "    StepDone(5);\n"
	code += _gen_init_done("Beep")
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
	code += "    valueOfEKey = RcKeyValueRead(KEY_OFFSET_1);\n"
	code += "}\n\n"

	# --- UpdateMode ---
	code += _gen_update_mode(mode_count, switch_strategy, switch_key, mode_keys, aux_motor_slots)

	# --- Calculate_Chassis_Control ---
	code += "void Calculate_Chassis_Control()\n"
	code += "{\n"
	code += sprint_code
	code += "\n"
	code += "    dutyOfChassis[0] = %s;\n" % l1_formula
	code += "    dutyOfChassis[1] = %s;\n" % l2_formula
	code += "    dutyOfChassis[2] = %s;\n" % r1_formula
	code += "    dutyOfChassis[3] = %s;\n" % r2_formula
	code += "}\n\n"

	# --- 每模式控制函数 ---
	code += mode_funcs

	# --- Main_Countrol ---
	var send_duty: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
	var send_dir: Array = ["1", "1", "1", "1", "1", "1", "1", "1"]
	for slot in aux_servo_slots:
		send_duty[slot] = "(uint16_t)dutyOfAuxServo[%d]" % slot
	for i in range(4):
		if chassis_slots[i] >= 0:
			send_duty[chassis_slots[i]] = "(uint16_t)abs(dutyOfChassis[%d])" % i
			send_dir[chassis_slots[i]] = "(dutyOfChassis[%d] >= 0 ? 1 : 0)" % i
	for slot in aux_motor_slots:
		send_duty[slot] = "(uint16_t)abs(dutyOfAuxMotor[%d])" % slot
		send_dir[slot] = "(dutyOfAuxMotor[%d] >= 0 ? 1 : 0)" % slot
	code += "void Main_Countrol()\n"
	code += "{\n"
	code += "    ExpansionBoradControl(Dir_Change_Order,\n"
	code += "                          %s);\n" % _exp_args(send_dir)
	code += "    Ms_Delay(5);\n"
	code += "    ExpansionBoradControl(Duty_Change_Order,\n"
	code += "                          %s);\n" % _exp_args(send_duty)
	code += "    Ms_Delay(5);\n"
	for si in range(2):
		if use_main_servo[si]:
			code += "    PWM_SET_Frequency(%s, 50, (uint16_t)dutyOfAuxMainServo[%d]);\n" % [main_chn[si], si]
	code += "}\n\n"

	# --- ExpansionBoradControl ---
	code += _gen_expansion_board_control()

	return code


# ============================================================ 辅助函数

## 把 8 个槽位参数格式化为 ExpansionBoradControl 的实参列表


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
	code += "        Uart1TxQuery(control_frame_pack[i]); // 查询发送，不依赖 TX 中断\n"
	code += "}\n"
	return code

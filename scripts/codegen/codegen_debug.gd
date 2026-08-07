class_name CodeGenDebug
extends CodeGenBase

## 调试模式代码生成器。
## 根据调试界面配置生成调试用 main.c 代码。
## 逐行执行各引脚的测试命令，每个命令持续 3S（摩擦轮除外），间隔 1S，
## 每个命令开始前蜂鸣器播放 500Hz，完成后播放 700Hz。


# 调试界面引脚名（与 DEBUG_ROWS 一一对应）
const DEBUG_PINS: Array = [
	"P60", "P62", "P64", "P66", "P74",
	"P75", "P76", "P77", "MP03", "MP74",
]

# 蜂鸣器引脚：主控板 P33，通过 PWM 产生不同频率
const BUZZER_PWM_CH: String = "PWMB_CH3_P33"

# 调试时各驱动类型对应的频率
const FREQ_MOTOR: int = 10000 # 电机模式频率
const FREQ_SERVO: int = 50 # 舵机模式频率
const FREQ_FRICTION: int = 50 # 摩擦轮模式频率

# 舵机归中占空比（50Hz 下中位值，等于基类 SERVO_DUTY_MID）
# 舵机总行程 180°，占空比区间见 CodeGenBase.SERVO_DUTY_MIN/MID/MAX
const SERVO_MID_DUTY: int = SERVO_DUTY_MID

# 摩擦轮渐变参数（参考 RM电控指南）
const FRICTION_STEP: int = 100 # 每步增加 100 占空比
const FRICTION_STEP_DELAY: int = 1500 # 每步间隔 1500ms
const FRICTION_MAX: int = 1100 # 摩擦轮最大占空比


## 生成 main.c 代码。
func generate(cfg: Dictionary) -> String:
	# --- 解析调试界面各行配置 ---
	# cfg["debug_rows"] = Array[Dictionary]，每项 {pin, drive_type, dir, value, enabled}
	var rows: Array = cfg.get("debug_rows", [])
	var active_rows: Array = []
	for row in rows:
		if row.get("enabled", false):
			active_rows.append(row)

	var code: String = ""
	code += "// 调试模式代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "// ========================= 参数区 =========================\n"
	# 调试复用步兵模板，会链接 nrf24l01.c；它通过 extern 引用 Channal，
	# 必须在此定义，否则链接报 ERROR L127/L128（undefined Channal）。
	code += "// NRF24L01 通信通道（0-125），与遥控器一致\n"
	code += "uint8_t Channal = %s;\n" % _int_or_default(cfg.get("channel", "36"), 36, 0, 125)
	code += "// 蜂鸣器频率定义\n"
	code += "#define BUZZER_FREQ_READY  500   // 命令开始：准备执行\n"
	code += "#define BUZZER_FREQ_DONE   700   // 命令完成\n"
	code += "#define TEST_DURATION_MS   3000  // 每个命令持续时间（摩擦轮除外）\n"
	code += "#define GAP_DURATION_MS    1000  // 命令间隔时间\n"
	code += "// 舵机占空比（50Hz）：%d=-90°，%d=中位(0°)，%d=+90°，总行程 180°\n" \
		% [SERVO_DUTY_MIN, SERVO_DUTY_MID, SERVO_DUTY_MAX]
	code += "#define SERVO_MID_DUTY     %d\n" % SERVO_MID_DUTY
	code += "// 摩擦轮渐变参数\n"
	code += "#define FRICTION_STEP       100\n"
	code += "#define FRICTION_STEP_MS   1500\n"
	code += "#define FRICTION_MAX       1100\n"
	code += "\n"
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
	code += "uint8_t i;\n"
	code += "\n"
	code += "void All_Init();\n"
	code += "void Buzzer_Play(uint32_t freq, uint16_t duration_ms);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n"
	code += "\n"

	# 初始化诊断工具（LED + 蜂鸣器）与 UART1 查询发送（修复 UART 死锁）
	code += _gen_led_diag_tools()
	code += CodeGenBase.UART_TX_QUERY_CODE

	# --- main() ---
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	code += "\n"

	# 逐行生成测试命令
	for row_idx in range(active_rows.size()):
		var row: Dictionary = active_rows[row_idx]
		var pin: String = row.get("pin", "")
		var drive_type: String = row.get("drive_type", "电机")
		var dir: int = int(row.get("dir", 1))
		var value: int = int(row.get("value", 0))
		var slot: int = _io_to_exp_slot(pin)
		var is_main_board: bool = slot < 0 # MP03 / MP74 在主控板

		code += "    // ===== 测试 %s（%s，%s）=====\n" % [pin, drive_type, "正" if dir == 1 else "反"]
		code += "    Buzzer_Play(BUZZER_FREQ_READY, 200); // 准备执行\n"
		code += "    Ms_Delay(200);\n"

		if is_main_board:
			# 主控板 PWM 引脚（MP03/MP74），只有舵机模式
			var pwm_ch: String = _pin_to_pwm_channel(pin)
			code += "    PWM_Init(%s, 50, %d); // %s 舵机归中\n" % [pwm_ch, SERVO_MID_DUTY, pin]
			code += "    Ms_Delay(TEST_DURATION_MS); // 持续 3S\n"
			code += "    PWM_SET_Duty(%s, 0); // 停止\n" % pwm_ch
		elif drive_type == "摩擦轮":
			# 摩擦轮：按 RM 电控指南要求逐步增减
			code += _generate_friction_test(slot, dir)
		else:
			# 扩展板电机/舵机
			var freq: int = FREQ_MOTOR if drive_type == "电机" else FREQ_SERVO
			var test_duty: int = value
			if drive_type == "舵机":
				test_duty = _servo_angle_to_duty(value)
			code += "    ExpansionBoradControl(Init_Order, %s); // 初始化 %s（频率 %d）\n" % [_slot_init_str(slot, freq), pin, freq]
			code += "    Ms_Delay(20);\n"
			code += "    ExpansionBoradControl(Dir_Change_Order, %s); // 方向：%s\n" % [_slot_dir_str(slot, dir), "正" if dir == 1 else "反"]
			code += "    Ms_Delay(5);\n"
			code += "    ExpansionBoradControl(Duty_Change_Order, %s); // 设置占空比 %d\n" % [_slot_duty_str(slot, test_duty), test_duty]
			code += "    Ms_Delay(TEST_DURATION_MS); // 持续 3S\n"
			code += "    ExpansionBoradControl(Duty_Change_Order, %s); // 停止\n" % [_slot_duty_str(slot, 0)]

		code += "    Buzzer_Play(BUZZER_FREQ_DONE, 200); // 执行完毕\n"
		if row_idx < active_rows.size() - 1:
			code += "    Ms_Delay(GAP_DURATION_MS); // 间隔 1S\n"
		code += "\n"

	code += "    // 全部测试完成\n"
	code += "    while (1)\n"
	code += "    {\n"
	code += "        Buzzer_Play(BUZZER_FREQ_DONE, 500);\n"
	code += "        Ms_Delay(2000);\n"
	code += "    }\n"
	code += "}\n\n"

	# --- All_Init() ---
	code += "void All_Init()\n{\n"
	code += "    // 初始化诊断分步：卡在哪步，LED 就停在对应编码（P37 P36 P35 二进制）\n"
	code += "    //   000 上电   001 Board_Init   010 UART1   011 LED 自检\n"
	code += "    //   100 蜂鸣器PWM 101 拓展板 Init 111 完成\n"
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
	# 蜂鸣器引脚初始化（PWM 模式）
	code += "    PWM_Init(%s, BUZZER_FREQ_READY, 0); // 蜂鸣器 P33\n" % BUZZER_PWM_CH
	code += "    StepDone(3);\n"
	code += "    StepBegin(4);\n"
	# 扩展板初始化（所有引脚先置零频率，后续按行重新初始化）
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          0, 0, 0, 0, 0, 0, 0, 0);\n"
	code += "    Ms_Delay(20);\n"
	code += "    StepDone(4);\n"
	code += _gen_init_done("Buzzer_Play")
	code += "}\n\n"

	# --- Buzzer_Play() ---
	code += "/// @brief 蜂鸣器播放指定频率，持续 duration_ms 毫秒\n"
	code += "/// @param freq 频率（Hz）\n"
	code += "/// @param duration_ms 持续时间（ms）\n"
	code += "void Buzzer_Play(uint32_t freq, uint16_t duration_ms)\n{\n"
	code += "    PWM_SET_Frequency(%s, freq, 5000); // 50%% 占空比驱动蜂鸣器\n" % BUZZER_PWM_CH
	code += "    Ms_Delay(duration_ms);\n"
	code += "    PWM_SET_Frequency(%s, freq, 0); // 停止蜂鸣\n" % BUZZER_PWM_CH
	code += "}\n\n"

	# --- ExpansionBoradControl() ---
	code += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	code += "/// @param control_cmd\n"
	code += "/// @param data_p60\n"
	code += "/// @param data_p62\n"
	code += "/// @param data_p64 摩擦轮L\n"
	code += "/// @param data_p66 摩擦轮R\n"
	code += "/// @param data_p74\n"
	code += "/// @param data_p75\n"
	code += "/// @param data_p76\n"
	code += "/// @param data_p77\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77)\n{\n"
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


## 生成摩擦轮渐变测试代码（参考 RM电控指南）
## 从 500 开始逐步增加到最大值，再逐步降至 0
func _generate_friction_test(slot: int, _dir: int) -> String:
	var code: String = ""
	# 摩擦轮固定 P64/P66（slot 2/3）
	var pin_name: String = "P64" if slot == 2 else "P66"
	code += "    ExpansionBoradControl(Init_Order, %s); // 初始化 %s 摩擦轮（频率 50）\n" % [_slot_init_str(slot, FREQ_FRICTION), pin_name]
	code += "    Ms_Delay(1000); // 初始化延迟（必须 >=1S，留给硬件反应时间）\n"
	code += "    // 逐步增加摩擦轮占空比\n"
	var duty: int = 500
	while duty <= FRICTION_MAX:
		code += "    ExpansionBoradControl(Duty_Change_Order, %s); // %s 占空比 %d\n" % [_slot_duty_str(slot, duty), pin_name, duty]
		code += "    Ms_Delay(FRICTION_STEP_MS);\n"
		duty += FRICTION_STEP
	# 逐步降低
	duty = FRICTION_MAX - FRICTION_STEP
	while duty >= 500:
		code += "    ExpansionBoradControl(Duty_Change_Order, %s); // %s 占空比 %d\n" % [_slot_duty_str(slot, duty), pin_name, duty]
		code += "    Ms_Delay(FRICTION_STEP_MS);\n"
		duty -= FRICTION_STEP
	# 降至 0
	code += "    ExpansionBoradControl(Duty_Change_Order, %s); // %s 占空比 0（停止）\n" % [_slot_duty_str(slot, 0), pin_name]
	code += "    Ms_Delay(FRICTION_STEP_MS);\n"
	return code


## 构建 Init_Order 参数字符串：仅指定 slot 的频率，其余为 0（维持原状）
func _slot_init_str(slot: int, freq: int) -> String:
	var vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
	if slot >= 0 and slot < 8:
		vals[slot] = str(freq)
	return "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]]


## 构建 Dir_Change_Order 参数字符串：仅指定 slot 的方向，其余为 0
func _slot_dir_str(slot: int, dir_val: int) -> String:
	var vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
	if slot >= 0 and slot < 8:
		vals[slot] = str(dir_val)
	return "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]]


## 构建 Duty_Change_Order 参数字符串：仅指定 slot 的占空比，其余为 0
func _slot_duty_str(slot: int, duty: int) -> String:
	var vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]
	if slot >= 0 and slot < 8:
		vals[slot] = str(duty)
	return "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [vals[0], vals[1], vals[2], vals[3], vals[4], vals[5], vals[6], vals[7]]

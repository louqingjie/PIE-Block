class_name CodeGenInfantry
extends CodeGenBase

## 步兵机器人代码生成器。
## 根据配置字典生成完整的步兵机器人 main.c 代码。
##
## 舵机角度约定（与 CodeGenBase 一致）：
## 舵机总行程 180°，所有角度参数都是「相对中位的偏移角」，区间 [-90, +90]。
## 占空比映射见 CodeGenBase.SERVO_DUTY_MIN/MID/MAX（实测 250 / 750 / 1250）。

# 云台摇杆可摆动的角度幅度（相对归中位置，单侧），须 <= SERVO_MAX_OFFSET_DEG
const SERVO_SWING_DEG: int = 60
# 摇杆推到底时云台每个主循环周期转过的角度
const SERVO_RATE_DEG_PER_LOOP: float = 2.0
# 摇杆 ADC 满量程读数
const ROCKER_FULL_SCALE: float = 2047.0


## 「每周期转过的角度」换算成 C 侧 changeRateOfServo 系数
## floatDutyOfServo += rocker * rate，rocker 满量程 2047 时增量应等于该角度对应的占空比
## 这里保留浮点精度，不走取整的 _servo_deg_to_duty_delta
func _servo_deg_per_loop_to_rate(deg_per_loop: float) -> float:
	var duty_per_deg: float = float(SERVO_DUTY_MAX - SERVO_DUTY_MIN) \
		/ float(SERVO_MAX_OFFSET_DEG * 2)
	return deg_per_loop * duty_per_deg / ROCKER_FULL_SCALE


# ------------------------------------------------------------------ 云台参数
## 云台舵机的归中占空比、限幅边界与每周期变化率。
##
## 这是云台数值语义的唯一真相源：generate() 与 3D 仿真都调用它，
## 不允许任何一侧另抄一份公式（历史上工程 IK 抄过一份舵机 duty 常量，
## 基类改了它不跟着变）。
##
## 返回键：
##   yaw_mid_deg / pitch_mid_deg  归中角（相对舵机中位的偏移角，已钳到 ±90）
##   yaw_mid / pitch_mid          归中角对应的占空比
##   yaw_lo / yaw_hi              Yaw 限幅边界（已同时收敛到摆动幅度与舵机行程）
##   pitch_lo / pitch_hi          Pitch 限幅边界
##   swing_deg                    摇杆可摆动幅度（度，单侧）
##   swing_duty                   摆动幅度对应的占空比跨度
##   rate                         摇杆读数 -> 每周期占空比增量的系数
##   duty_per_deg                 每度对应的占空比增量
func gimbal_params(cfg: Dictionary) -> Dictionary:
	# 归中角偏移（相对舵机中位的偏移角，用于消除静差）。
	# 舵机总行程 180°，UI 填的是相对中位的偏移角，有效区间 [-90, +90]
	var yaw_mid_str: String = str(cfg.get("yaw_mid_offset", "0"))
	if not yaw_mid_str.is_valid_int():
		yaw_mid_str = "0"
	var pitch_mid_str: String = str(cfg.get("pitch_mid_offset", "0"))
	if not pitch_mid_str.is_valid_int():
		pitch_mid_str = "0"
	var yaw_mid_deg: int = clampi(int(yaw_mid_str), -SERVO_MAX_OFFSET_DEG, SERVO_MAX_OFFSET_DEG)
	var pitch_mid_deg: int = clampi(int(pitch_mid_str), -SERVO_MAX_OFFSET_DEG, SERVO_MAX_OFFSET_DEG)
	var yaw_mid_val: int = _servo_angle_to_duty(yaw_mid_deg)
	var pitch_mid_val: int = _servo_angle_to_duty(pitch_mid_deg)
	# 云台摇杆可摆动的角度幅度（相对归中位置），再收敛到舵机物理行程内
	var servo_swing_deg: int = SERVO_SWING_DEG
	var servo_swing: int = _servo_deg_to_duty_delta(float(servo_swing_deg))
	return {
		"yaw_mid_deg": yaw_mid_deg,
		"pitch_mid_deg": pitch_mid_deg,
		"yaw_mid": yaw_mid_val,
		"pitch_mid": pitch_mid_val,
		"yaw_lo": maxi(SERVO_DUTY_MIN, yaw_mid_val - servo_swing),
		"yaw_hi": mini(SERVO_DUTY_MAX, yaw_mid_val + servo_swing),
		"pitch_lo": maxi(SERVO_DUTY_MIN, pitch_mid_val - servo_swing),
		"pitch_hi": mini(SERVO_DUTY_MAX, pitch_mid_val + servo_swing),
		"swing_deg": servo_swing_deg,
		"swing_duty": servo_swing,
		"rate": _servo_deg_per_loop_to_rate(SERVO_RATE_DEG_PER_LOOP),
		"duty_per_deg": float(SERVO_DUTY_MAX - SERVO_DUTY_MIN)
			/ float(SERVO_MAX_OFFSET_DEG * 2),
	}


# ------------------------------------------------------------------ 代码生成
## 基于配置字典生成完整的 main.c 代码字符串
func generate(cfg: Dictionary) -> String:
	# --- 解析参数（非法输入回退默认值并限幅，保证产物可编译）---
	var ch: String = _int_or_default(cfg.get("channel", ""), 36, 0, 125)
	var dz: String = _int_or_default(cfg.get("deadzone", ""), 10, 0, 2047)
	var normal_spd: String = _int_or_default(cfg.get("normal_speed", ""), 4000, 0, 10000)
	var sprint_spd: String = _int_or_default(cfg.get("sprint_speed", ""), 8000, 0, 10000)
	var trig_spd: String = _int_or_default(cfg.get("trigger_speed", ""), 10000, 0, 10000)
	# Ms_Delay 参数是 uint16_t，超过 65535 会被静默截断
	var trig_time: String = _int_or_default(cfg.get("trigger_time", ""), 250, 0, 65535)
	# 校内赛安全策略：500 duty 起步，每个 50Hz PWM 周期增减 1，硬上限 800。
	# 最大档位只接受 500~800 内的整百值；非法输入回退 800。
	var friction_max_text: String = str(cfg.get("friction_max_duty", "800")).strip_edges()
	var friction_max_duty: int = 800
	if friction_max_text.is_valid_int():
		var requested_friction_max: int = friction_max_text.to_int()
		if requested_friction_max >= 500 and requested_friction_max <= 800 \
				and requested_friction_max % 100 == 0:
			friction_max_duty = requested_friction_max

	# --- 按键映射 ---
	var trigger_key_offset: String = _key_name_to_offset(cfg.get("trigger_key", "E"))
	var booster_key_offset: String = _key_name_to_offset(cfg.get("booster_key", "A"))
	# --- 拨弹模式 ---
	# 目视闭环：按住扳机持续拨弹、松开即停（不阻塞主循环）
	# 阻塞开环：按一下扳机，拨弹电机转动 trigger_time ms 后停（阻塞主循环）
	var visual_feed: bool = str(cfg.get("feed_mode", "阻塞开环")) == "目视闭环"

	# --- IO 槽位映射 ---
	# 将功能角色映射到拓展板槽位（0-7 对应 p60,p62,p64,p66,p74,p75,p76,p77）
	var feeder_pin: String = _parse_io_pair(cfg.get("booster_io", "P60 P61"))
	var l1_pin: String = _parse_io_pair(cfg.get("l1_io", "P74 P24"))
	var l2_pin: String = _parse_io_pair(cfg.get("l2_io", "P75 P25"))
	var r1_pin: String = _parse_io_pair(cfg.get("r1_io", "P76 P26"))
	var r2_pin: String = _parse_io_pair(cfg.get("r2_io", "P77 P27"))
	# 实机接线：左摩擦轮 P66，右摩擦轮 P64
	var friction_l_pin: String = "P66"
	var friction_r_pin: String = "P64"

	var feeder_slot: int = _io_to_exp_slot(feeder_pin)
	var l1_slot: int = _io_to_exp_slot(l1_pin)
	var l2_slot: int = _io_to_exp_slot(l2_pin)
	var r1_slot: int = _io_to_exp_slot(r1_pin)
	var r2_slot: int = _io_to_exp_slot(r2_pin)
	var friction_l_slot: int = _io_to_exp_slot(friction_l_pin)
	var friction_r_slot: int = _io_to_exp_slot(friction_r_pin)

	# --- 方向 ---
	var l1_dir: int = _dir_to_int(cfg.get("l1_dir", "正向"))
	var l2_dir: int = _dir_to_int(cfg.get("l2_dir", "正向"))
	var r1_dir: int = _dir_to_int(cfg.get("r1_dir", "正向"))
	var r2_dir: int = _dir_to_int(cfg.get("r2_dir", "正向"))
	var booster_dir: int = _dir_to_int(cfg.get("booster_dir", "正向"))
	# 摩擦轮 Dir 硬编码 0：实测拓展板 Dir_Change_Order 里摩擦轮槽位发 1 时
	# ESC 无法解锁（摩擦轮不转），发 0 正常（2026-08 实机验证）。
	# 两侧轮子的实际旋向靠接线调整，不走协议方向位。

	# --- 归中角偏移与限幅（唯一真相源见 gimbal_params，3D 仿真共用同一份）---
	var gp: Dictionary = gimbal_params(cfg)
	var yaw_mid_deg: int = gp["yaw_mid_deg"]
	var pitch_mid_deg: int = gp["pitch_mid_deg"]
	var yaw_mid_val: int = gp["yaw_mid"]
	var pitch_mid_val: int = gp["pitch_mid"]
	var servo_swing_deg: int = gp["swing_deg"]
	var servo_swing: int = gp["swing_duty"]
	var yaw_lo: int = gp["yaw_lo"]
	var yaw_hi: int = gp["yaw_hi"]
	var pitch_lo: int = gp["pitch_lo"]
	var pitch_hi: int = gp["pitch_hi"]
	# --- 归中功能使能 ---
	var _ze: Variant = cfg.get("zero_enabled", false)
	var zero_enabled: bool = _ze is bool and _ze == true

	# --- Yaw/Pitch 驱动类型 ---
	var yaw_is_servo: bool = str(cfg.get("yaw_drive", "舵机")) == "舵机"
	var pitch_is_servo: bool = str(cfg.get("pitch_drive", "舵机")) == "舵机"
	var yaw_pin: String = _parse_io_pair(cfg.get("yaw_io", "MP74"))
	var pitch_pin: String = _parse_io_pair(cfg.get("pitch_io", "MP03"))
	# 扩展板槽位（-1 表示不在扩展板上，即主控板 PWM 引脚）
	var yaw_slot: int = _io_to_exp_slot(yaw_pin)
	var pitch_slot: int = _io_to_exp_slot(pitch_pin)
	# 舵机在主控板 PWM 引脚上（需要 PWM_Init），还是在扩展板上（走 ExpansionBoradControl）
	# 只有 MP74 / MP03 是主控板上可用的舵机口，其他非扩展板引脚一律不生成 PWM 代码
	var yaw_servo_on_main: bool = yaw_is_servo and yaw_pin in MAIN_BOARD_SERVO_PINS
	var pitch_servo_on_main: bool = pitch_is_servo and pitch_pin in MAIN_BOARD_SERVO_PINS

	# --- 槽位分配（先按 IO 设置区初始化，再按固定角色覆盖）---
	# 槽位 0-7 依次对应 p60,p62,p64,p66,p74,p75,p76,p77
	# UI 只提供「舵机 / 电机」两种状态，因此每个拓展板槽位都必须分别生成
	# 50Hz / 10000Hz。不能把“没有被模式控制行引用”暗中解释成 0Hz；官方
	# Init_Order 示例也没有定义 0Hz 为合法的“不初始化”值。
	# Duty_Change_Order 里未使用槽位固定给 0，避免误驱动
	var io_init_shared: Dictionary = cfg.get("io_init", {})
	var init_vals: Array = []
	for slot in range(8):
		var pin: String = _exp_pin(slot)
		init_vals.append(10000 if str(io_init_shared.get(pin, "舵机")) == "电机" else 50)
	var dir_exprs: Array = ["1", "1", "1", "1", "1", "1", "1", "1"]
	var duty_vals: Array = ["0", "0", "0", "0", "0", "0", "0", "0"]

	# 摩擦轮固定占用 P64 / P66，频率 50Hz；Dir 固定 0（见上方实测说明）
	init_vals[friction_l_slot] = 50
	init_vals[friction_r_slot] = 50
	dir_exprs[friction_l_slot] = "0"
	dir_exprs[friction_r_slot] = "0"
	duty_vals[friction_l_slot] = "dutyOfBooster"
	duty_vals[friction_r_slot] = "dutyOfBooster"

	# 拨弹电机 -> dutyOfMotor[4]
	if feeder_slot >= 0:
		init_vals[feeder_slot] = 10000
		dir_exprs[feeder_slot] = str(booster_dir)
		duty_vals[feeder_slot] = "dutyOfMotor[4]"

	# 底盘/云台电机槽位 -> dutyOfMotor 索引映射
	# 蓝本中: dutyOfMotor[0]=L1, [1]=L2, [2]=R1, [3]=R2, [4]=拨弹
	var yaw_motor_idx: int = 5
	var pitch_motor_idx: int = 6 if not yaw_is_servo else 5
	var motor_slots: Array = [[l1_slot, 0], [l2_slot, 1], [r1_slot, 2], [r2_slot, 3]]
	if not yaw_is_servo:
		motor_slots.append([yaw_slot, yaw_motor_idx])
	if not pitch_is_servo:
		motor_slots.append([pitch_slot, pitch_motor_idx])
	# 摩擦轮槽位受硬件保护规则约束，绝不允许被其他角色改写（见《RM电控指南》）
	var friction_slots: Array = [friction_l_slot, friction_r_slot]
	for pair in motor_slots:
		var s: int = pair[0]
		if s < 0:
			continue # 不在扩展板上（如主控板引脚），无法作为电机驱动
		if s in friction_slots:
			push_warning("步兵代码生成：槽位 %d 已被摩擦轮占用，忽略电机分配" % s)
			continue
		init_vals[s] = 10000
		dir_exprs[s] = "Get_Dir(dutyOfMotor[%d])" % pair[1]
		duty_vals[s] = "(uint16_t)abs(dutyOfMotor[%d])" % pair[1]

	# Yaw/Pitch 舵机在扩展板上时：50Hz + dutyOfServo
	if yaw_is_servo and yaw_slot >= 0 and not yaw_slot in friction_slots:
		init_vals[yaw_slot] = 50
		duty_vals[yaw_slot] = "dutyOfServo[0]"
	if pitch_is_servo and pitch_slot >= 0 and not pitch_slot in friction_slots:
		init_vals[pitch_slot] = 50
		duty_vals[pitch_slot] = "dutyOfServo[1]"

	# dutyOfMotor 数组长度按实际用到的最大下标计算，避免越界写
	var max_motor_idx: int = 4 # [0..3] 底盘 + [4] 拨弹
	if not yaw_is_servo:
		max_motor_idx = maxi(max_motor_idx, yaw_motor_idx)
	if not pitch_is_servo:
		max_motor_idx = maxi(max_motor_idx, pitch_motor_idx)
	var motor_array_size: int = max_motor_idx + 1

	# --- 底盘电机公式（反向时取反）---
	var l1_formula: String = "-baseSpeed - turnSpeed" if l1_dir == 1 else "baseSpeed + turnSpeed"
	var l2_formula: String = "-baseSpeed - turnSpeed" if l2_dir == 1 else "baseSpeed + turnSpeed"
	var r1_formula: String = "baseSpeed - turnSpeed" if r1_dir == 1 else "-baseSpeed + turnSpeed"
	var r2_formula: String = "baseSpeed - turnSpeed" if r2_dir == 1 else "-baseSpeed + turnSpeed"

	# --- 冲刺/移动速度逻辑 ---
	var arrow_key: String = str(cfg.get("arrow_key", "移动"))
	var _se: Variant = cfg.get("sprint_enabled", false)
	var sprint_enabled: bool = _se is bool and _se == true
	# sprint_check: 生成 baseSpeed/turnSpeed 的初始赋值代码块。
	# 符号约定：baseSpeed > 0 = 前进，turnSpeed > 0 = 向右转，
	# 与下面方向键的赋值保持一致（早期版本摇杆多了一个取反，
	# 导致推杆向右与按右方向键转向相反）
	var sprint_check: String = ""
	if sprint_enabled:
		sprint_check = "\n    // 冲刺模式：按下左摇杆时使用冲刺速度\n    if (valueOfKey[2][0])\n    {\n        baseSpeed = (int)((float)valueOfRoker[0][1] * ultraSpeed / 2047);\n        turnSpeed = (int)((float)valueOfRoker[0][0] * ultraSpeed / 2047);\n    }\n    else\n    {\n        baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n        turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n    }\n"
	else:
		sprint_check = "\n    // 冲刺模式不可用（未勾选），使用普通速度\n    baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n    turnSpeed = (int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n"
	# ArrowKey 选"冲刺"时方向键直接触发冲刺
	var arrow_sprint: String = ""
	if arrow_key == "冲刺":
		arrow_sprint = "\n    // 方向键设为冲刺\n    if (valueOfKey[0][0] == 1)\n        baseSpeed = ultraSpeed;\n    if (valueOfKey[0][1] == 1)\n        baseSpeed = -ultraSpeed;\n    if (valueOfKey[0][2] == 1)\n        turnSpeed = -ultraSpeed;\n    if (valueOfKey[0][3] == 1)\n        turnSpeed = ultraSpeed;"
	elif arrow_key == "移动":
		arrow_sprint = "\n    // 方向键设为移动\n    if (valueOfKey[0][0] == 1)\n        baseSpeed = maxSpeed;\n    if (valueOfKey[0][1] == 1)\n        baseSpeed = -maxSpeed;\n    if (valueOfKey[0][2] == 1)\n        turnSpeed = -maxSpeed;\n    if (valueOfKey[0][3] == 1)\n        turnSpeed = maxSpeed;"
	else:
		arrow_sprint = "\n    // 方向键设为其他功能，不参与移动\n"

	# --- PWM 配置（Yaw/Pitch 舵机模式）---
	var pwm_init_lines: String = ""
	var pwm_set_lines: String = ""
	# 仅当舵机使用主控板 PWM 引脚时才需要 PWM_Init / PWM_SET_Frequency
	# 扩展板上的舵机通过 ExpansionBoradControl 控制，不需要 PWM_Init
	if yaw_servo_on_main:
		pwm_init_lines += "    PWM_Init(%s, 50, midDutyOfServo[0]); // 云台水平舵机\n" % _pin_to_pwm_channel(yaw_pin)
		pwm_set_lines += "    PWM_SET_Frequency(%s, 50, dutyOfServo[0]);\n" % _pin_to_pwm_channel(yaw_pin)
	if pitch_servo_on_main:
		pwm_init_lines += "    PWM_Init(%s, 50, midDutyOfServo[1]); // 云台垂直舵机\n" % _pin_to_pwm_channel(pitch_pin)
		pwm_set_lines += "    PWM_SET_Frequency(%s, 50, dutyOfServo[1]);\n" % _pin_to_pwm_channel(pitch_pin)

	# --- 高级设置：共享多模式按键映射（步兵/工程共用同一份配置）---
	# 行不能指向固定子系统占用的引脚（静态检查已拦，这里防御性跳过）
	var io_mid: Dictionary = cfg.get("io_mid", {})
	var mode_count: int = clampi(int(float(str(cfg.get("mode_count", 1)))), 1, 4)
	var switch_strategy: String = str(cfg.get("switch_strategy", "单击切换"))
	var switch_key: String = str(cfg.get("mode_switch_key", "E"))
	var mode_keys: Array = cfg.get("mode_keys", [])
	var modes: Array = cfg.get("modes", []) if cfg.get("modes", []) is Array else []
	# 固定子系统占用的扩展板槽位（摩擦轮 / 拨弹 / 底盘 / 云台）
	var owned_slots: Array = []
	for s in [friction_l_slot, friction_r_slot, feeder_slot, yaw_slot, pitch_slot]:
		if s >= 0 and not s in owned_slots:
			owned_slots.append(s)
	for pair in motor_slots:
		if pair[0] >= 0 and not pair[0] in owned_slots:
			owned_slots.append(pair[0])
	# 辅助槽位（行指向的扩展板引脚，未被固定子系统占用）
	var aux_servo_slots: Array = []
	var aux_motor_slots: Array = []
	var use_aux_main: Array = [false, false]
	for mi in range(mini(mode_count, modes.size())):
		for row in (modes[mi].get("rows", []) as Array):
			var io: String = str(row.get("io", ""))
			var slot: int = _io_to_exp_slot(io)
			if slot >= 0:
				if slot in owned_slots:
					continue
				if str(io_init_shared.get(io, "舵机")) == "电机":
					if not slot in aux_motor_slots:
						aux_motor_slots.append(slot)
				elif not slot in aux_servo_slots:
					aux_servo_slots.append(slot)
			elif io == "MP03":
				use_aux_main[0] = true
			elif io == "MP74":
				use_aux_main[1] = true
	# 辅助槽位填充到 Init/Dir/Duty
	for slot in aux_servo_slots:
		init_vals[slot] = 50
		duty_vals[slot] = "(uint16_t)dutyOfAuxServo[%d]" % slot
	for slot in aux_motor_slots:
		init_vals[slot] = 10000
		dir_exprs[slot] = "(dutyOfAuxMotor[%d] >= 0 ? 1 : 0)" % slot
		duty_vals[slot] = "(uint16_t)abs(dutyOfAuxMotor[%d])" % slot
	# 步兵拓展板前四路 P60/P62/P64/P66 共用摩擦轮所在的 50Hz PWM 时基。
	# 官方 A.EXPAND_TEST、RM_playcar_example、RM_rub_wheel 均固定发送
	# 50,50,50,50；实机独立诊断也验证该组合可同时驱动 P64/P66。
	# P60 即使连接拨弹电机，仍通过 Duty/Dir 控制，但初始化频率必须留在 50Hz。
	for slot in range(4):
		init_vals[slot] = 50
	# 主控板辅助舵机 PWM（初始角按 IO 初始化区）
	for si in range(2):
		if use_aux_main[si]:
			var aux_pin: String = "MP03" if si == 0 else "MP74"
			pwm_init_lines += "    PWM_Init(%s, 50, %d); // %s 舵机初始角\n" \
				% [_pin_to_pwm_channel(aux_pin), _io_mid_duty(io_mid, aux_pin), aux_pin]
			pwm_set_lines += "    PWM_SET_Frequency(%s, 50, (uint16_t)dutyOfAuxMainServo[%d]);\n" \
				% [_pin_to_pwm_channel(aux_pin), si]

	# --- 生成 init_vals 字符串 ---
	var init_str: String = "%d, %d,\n                          %d, %d,\n                          %d, %d,\n                          %d, %d" % [init_vals[0], init_vals[1], init_vals[2], init_vals[3], init_vals[4], init_vals[5], init_vals[6], init_vals[7]]
	var dir_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [dir_exprs[0], dir_exprs[1], dir_exprs[2], dir_exprs[3], dir_exprs[4], dir_exprs[5], dir_exprs[6], dir_exprs[7]]
	var duty_str: String = "%s, %s,\n                          %s, %s,\n                          %s, %s,\n                          %s, %s" % [duty_vals[0], duty_vals[1], duty_vals[2], duty_vals[3], duty_vals[4], duty_vals[5], duty_vals[6], duty_vals[7]]

	# --- 组装完整 main.c ---
	var code: String = "// 步兵机器人操作代码（由 Pie-Block 配置生成器自动生成）\n"
	code += "#include \"main.h\"\n"
	code += "#include \"MATH.H\"\n"
	code += "// ========================= 参数区 =========================\n"
	code += "uint8_t Channal = %s;                          // NRF24L01 通信通道（0-125），与遥控器一致\n" % ch
	code += "uint16_t maxSpeed = %s;\n" % normal_spd
	code += "uint16_t ultraSpeed = %s;\n" % sprint_spd
	code += "uint16_t deadBandOfLeft = %s;                   // 左摇杆中心死区\n" % dz
	code += "uint16_t deadBandOfRight = %s;                  // 右摇杆中心死区\n" % dz
	code += "// 舵机占空比：%d=-%d°，%d=中位(0°)，%d=+%d°，总行程 %d°\n" \
		% [SERVO_DUTY_MIN, SERVO_MAX_OFFSET_DEG, SERVO_DUTY_MID,
			SERVO_DUTY_MAX, SERVO_MAX_OFFSET_DEG, SERVO_MAX_OFFSET_DEG * 2]
	code += "#define SERVO_DUTY_MIN     %d\n" % SERVO_DUTY_MIN
	code += "#define SERVO_DUTY_MID     %d\n" % SERVO_DUTY_MID
	code += "#define SERVO_DUTY_MAX     %d\n" % SERVO_DUTY_MAX
	code += "// 每度对应的占空比增量（%d duty / %d°）\n" \
		% [SERVO_DUTY_MAX - SERVO_DUTY_MIN, SERVO_MAX_OFFSET_DEG * 2]
	code += "#define SERVO_DUTY_PER_DEG %.6ff\n" % (
		float(SERVO_DUTY_MAX - SERVO_DUTY_MIN) / float(SERVO_MAX_OFFSET_DEG * 2))
	code += "uint16_t midDutyOfServo[2] = {%d, %d};        // 云台水平/垂直舵机中值（归中角 %+d° / %+d°）\n" \
		% [yaw_mid_val, pitch_mid_val, yaw_mid_deg, pitch_mid_deg]
	code += "// 摇杆可摆动幅度 ±%d°（相对归中位置）\n" % servo_swing_deg
	code += "uint16_t maxChangeDutyOfServo[2] = {%d, %d};\n" % [servo_swing, servo_swing]
	code += "#define FRICTION_START_DUTY 500  // 官方守则：摩擦轮启动占空比\n"
	code += "#define FRICTION_STEP_DUTY  1    // 平滑启停：每个主循环只变化 1 duty\n"
	code += "#define FRICTION_MAX_DUTY   %d   // 用户设定，校内赛安全硬上限 800\n" % friction_max_duty
	code += "uint16_t boosterDutyOfFeed = %s;             // 拨弹电机单发转动占空比\n" % trig_spd
	if not visual_feed:
		code += "uint16_t boosterFeedDelayMs = %s;              // 拨弹电机单发转动时长(ms)\n" % trig_time
	# 摇杆读数（±2047）乘以该系数得到每周期的占空比增量。
	# 摇杆推到底时每个主循环周期转过 SERVO_RATE_DEG_PER_LOOP 度。
	var servo_rate: float = gp["rate"]
	code += "// 摇杆推到底时云台每周期转过 %.1f°\n" % SERVO_RATE_DEG_PER_LOOP
	code += "float changeRateOfServo[2] = {%.6f, %.6f};\n\n" % [servo_rate, servo_rate]
	code += "#define LIMIT_VALUE(x, min, max) \\\n    do                           \\\n    {                            \\\n        if ((x) < (min))         \\\n            (x) = (min);         \\\n        else if ((x) > (max))    \\\n            (x) = (max);         \\\n    } while (0)\n"
	code += "/*帧头帧尾，内部调用，无需关心*/\n"
	code += "#define COMM_HEADER_1 0xAB\n#define COMM_HEADER_2 0xBC\n#define COMM_END_1 0xCD\n#define COMM_END_2 0xDE\n"
	code += "/*命令码*/\n"
	code += "#define Init_Order 0xAA        // 初始化模式\n"
	code += "#define Duty_Change_Order 0xBB // 修改占空比\n"
	code += "#define Freq_Change_Order 0xCC // 修改频率\n"
	code += "#define Dir_Change_Order 0xDD  // 修改方向：1为正、0为负，电机换向时需更新\n"
	code += "#define Zero_Order 0xEE        // 0命令\n"
	code += "// 拓展板需要帧间处理时间；连续命令之间不得删除此间隔\n"
	code += "#define EXPANSION_FRAME_GAP_MS 5\n"
	code += "/*内部调用变量，无需关心，请勿定义同名变量*/\n"
	code += "uint16_t control_data[8] = {0};\n"
	code += "uint16_t motor_dir[8] = {0};\n"
	code += "uint8_t control_command = 0x00;\n"
	code += "// 自定义变量\n"
	code += "float floatDutyOfServo[2]; // 云台舵机\n"
	code += "uint16_t dutyOfServo[2];\n"
	code += "int dutyOfMotor[%d]; // 底盘电机、供弹电机、云台电机（如有）\n" % motor_array_size
	code += "uint16_t dutyOfBooster = 0;       // 当前摩擦轮占空比\n"
	code += "uint16_t targetDutyOfBooster = 0; // 目标只允许 0 或 FRICTION_MAX_DUTY\n"
	code += "uint8_t frictionRampActive = 0;\n"
	code += "uint8_t valueOfKey[3][4];\n"
	code += "uint8_t valueOfEKey;\n"
	code += "uint8_t triggerKeyValue, lastTriggerKeyValue, boosterKeyValue, lastBoosterKeyValue;\n"
	code += "uint8_t statusOfBooster = 0;\n"
	# 高级设置：共享多模式按键映射的辅助执行器
	if not aux_servo_slots.is_empty() or not aux_motor_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		code += "int dutyOfAuxMotor[8];          // 高级设置辅助电机（按槽位）\n"
		code += "float dutyOfAuxServo[8];        // 高级设置辅助舵机（按槽位）\n"
		code += "float dutyOfAuxMainServo[2];    // 高级设置 MP03/MP74 舵机\n"
		code += "uint8_t currentMode = 1;        // 当前模式（1~%d），开机固定模式1\n" % mode_count
		code += "uint8_t modeKeyHeld = 0;        // 单击切换键锁存\n"
		if mode_count > 1 and not aux_motor_slots.is_empty():
			code += "uint8_t prevMode = 1;        // 上一次模式，切换后未映射的辅助电机下电\n"
		if switch_strategy == "一一对应" and mode_count > 1:
			code += "uint8_t modeKeyLast[4] = {0};  // 一一对应各模式键锁存\n"
	code += "uint8_t i, j;\n"
	code += "int valueOfRoker[2][2] // 左摇杆水平、竖直；右摇杆水平、竖直\n    ,\n    baseSpeed, turnSpeed;\n"
	code += "static const uint8_t keyOffsets[3][4] = {\n"
	code += "    {KEY_OFFSET_UP, KEY_OFFSET_DOWN, KEY_OFFSET_LEFT, KEY_OFFSET_RIGHT},\n"
	code += "    {KEY_OFFSET_A, KEY_OFFSET_B, KEY_OFFSET_C, KEY_OFFSET_D},\n"
	code += "    {KEY_OFFSET_Rocker11, KEY_OFFSET_Rocker21, 0, 0} // 实际只有2个\n};\n\n"
	code += "void All_Init();\n"
	code += "void ReadControllerInputs();\n"
	code += "void CalculateMotorControls();\n"
	code += "void CalculateGimbalControls();\n"
	code += "void CalculateBoosterControl();\n"
	if not aux_servo_slots.is_empty() or not aux_motor_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		code += "void UpdateMode();\n"
		for mi in range(mode_count):
			code += "void Calculate_Mode%d_Controls();\n" % (mi + 1)
	code += "uint8_t Get_Dir(int rawdata);\n"
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	code += CodeGenBase.REMOTE_CONTROL_INIT_CODE
	# 初始化诊断工具（LED + 蜂鸣器）与 UART1 查询发送（修复 UART 死锁）。
	# P33 改用 PWMA_CH4N，避免斜坡音调连续变频扰动主控舵机所在的 PWMB 时基。
	code += _gen_led_diag_tools("GPIO_P3", "GPIO_Pin_5", "GPIO_Pin_6", "GPIO_Pin_7", "PWMA_CH4N_P33")
	code += CodeGenBase.UART_TX_QUERY_CODE
	code += "// 摩擦轮斜坡蜂鸣器跟踪：音调 Hz 等于当前 duty；只在增减速期间发声。\n"
	code += "static void FrictionBuzzerTrace(uint16_t duty)\n{\n"
	code += "    PWM_SET_Frequency(BUZZER_CH, duty, 5000);\n"
	code += "}\n\n"
	code += "static void FrictionBuzzerOff(void)\n{\n"
	code += "    PWM_SET_Frequency(BUZZER_CH, 500, 0);\n"
	code += "}\n\n"

	# --- main() ---
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	if yaw_is_servo:
		code += "    floatDutyOfServo[0] = midDutyOfServo[0];\n"
	if pitch_is_servo:
		code += "    floatDutyOfServo[1] = midDutyOfServo[1];\n"
	if not aux_servo_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		for slot in aux_servo_slots:
			code += "    dutyOfAuxServo[%d] = %d.0f; // 高级设置初始角\n" % [slot, _io_mid_duty(io_mid, _exp_pin(slot))]
		for si in range(2):
			if use_aux_main[si]:
				var apin: String = "MP03" if si == 0 else "MP74"
				code += "    dutyOfAuxMainServo[%d] = %d.0f; // %s 初始角\n" % [si, _io_mid_duty(io_mid, apin), apin]
	code += "    while (1)\n"
	code += "    {\n"
	code += _gen_nrf_poll()
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n\n"
	code += "        ReadControllerInputs();    // 统一读取输入\n"
	code += "        CalculateMotorControls();  // 计算电机控制\n"
	code += "        CalculateGimbalControls(); // 计算云台控制\n"
	code += "        CalculateBoosterControl(); // 计算摩擦轮控制\n"
	if not aux_servo_slots.is_empty() or not aux_motor_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		code += "        UpdateMode();\n"
		code += "        // 高级设置：按当前模式执行按键映射\n"
		code += "        switch (currentMode)\n"
		code += "        {\n"
		for mi in range(mode_count):
			code += "            case %d:\n" % (mi + 1)
			code += "                Calculate_Mode%d_Controls();\n" % (mi + 1)
			code += "                break;\n"
		code += "            default:\n"
		code += "                break;\n"
		code += "        }\n"
		for slot in aux_motor_slots:
			code += "        LIMIT_VALUE(dutyOfAuxMotor[%d], -10000, 10000);\n" % slot
		for slot in aux_servo_slots:
			code += "        LIMIT_VALUE(dutyOfAuxServo[%d], %d, %d);\n" % [slot, SERVO_DUTY_MIN, SERVO_DUTY_MAX]
		for si in range(2):
			if use_aux_main[si]:
				code += "        LIMIT_VALUE(dutyOfAuxMainServo[%d], %d, %d);\n" % [si, SERVO_DUTY_MIN, SERVO_DUTY_MAX]
	code += "        LIMIT_VALUE(dutyOfMotor[0], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[1], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[2], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[3], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[4], 0, 10000);\n"
	if not yaw_is_servo:
		code += "        LIMIT_VALUE(dutyOfMotor[%d], -10000, 10000);\n" % yaw_motor_idx
	if not pitch_is_servo:
		code += "        LIMIT_VALUE(dutyOfMotor[%d], -10000, 10000);\n" % pitch_motor_idx
	# 舵机限幅用生成期算好的常量：midDutyOfServo 是 uint16_t，
	# 直接写 mid - maxChange 在偏移为负时会下溢，故不在 C 侧做减法。
	# 边界已同时收敛到「归中角 ±摆动幅度」和舵机物理行程（基类常量）之内。
	if yaw_is_servo:
		code += "        // Yaw 限幅 %d~%d（归中 %+d° ±%d°，已收敛到舵机行程内）\n" \
			% [yaw_lo, yaw_hi, yaw_mid_deg, servo_swing_deg]
		code += "        LIMIT_VALUE(floatDutyOfServo[0], %d, %d);\n" % [yaw_lo, yaw_hi]
	if pitch_is_servo:
		code += "        // Pitch 限幅 %d~%d（归中 %+d° ±%d°，已收敛到舵机行程内）\n" \
			% [pitch_lo, pitch_hi, pitch_mid_deg, servo_swing_deg]
		code += "        LIMIT_VALUE(floatDutyOfServo[1], %d, %d);\n" % [pitch_lo, pitch_hi]
	# 拨弹：两种模式二选一
	# 目视闭环：按住扳机持续拨弹，松开即停；不阻塞主循环，操作手目视到出弹后松手
	# 阻塞开环：按一下扳机，拨弹电机转动 boosterFeedDelayMs 后停，期间阻塞主线程
	if visual_feed:
		code += "        // 目视闭环拨弹：按住扳机键持续拨弹，松开即停（不阻塞主循环）\n"
		code += "        dutyOfMotor[4] = triggerKeyValue ? boosterDutyOfFeed : 0;\n"
		code += "        lastTriggerKeyValue = triggerKeyValue;\n\n"
	else:
		code += "        // 扳机键单发拨弹：上升沿触发，拨弹电机转动 boosterFeedDelayMs 后停转，期间阻塞主线程\n"
		code += "        if (triggerKeyValue && !lastTriggerKeyValue)\n"
		code += "        {\n"
		code += "            dutyOfMotor[4] = boosterDutyOfFeed;\n"
		code += "            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);\n"
		code += "            Ms_Delay(boosterFeedDelayMs);\n"
		code += "            dutyOfMotor[4] = 0;\n"
		code += "            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);\n"
		code += "        }\n"
		code += "        lastTriggerKeyValue = triggerKeyValue;\n\n"
	code += "        // 发送控制函数\n"
	code += "        Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);\n"
	code += "        Ms_Delay(10);\n"
	code += "    }\n}\n\n"

	# --- Get_Dir ---
	code += "uint8_t Get_Dir(int rawdata)\n{\n"
	code += "    if (rawdata >= 0)\n"
	code += "        return 1;\n"
	code += "    else\n"
	code += "        return 0;\n}\n\n"

	# --- All_Init ---
	code += "void All_Init()\n{\n"
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
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          %s); // p60,p62,p64,p66,p74,p75,p76,p77\n" % init_str
	code += "    // 摩擦轮初始化后必须留 >=1000ms 硬件反应时间（见《RM电控指南》），不得缩短\n"
	code += "    Ms_Delay(1000);\n"
	code += "    StepDone(4);\n"
	code += "    StepBegin(5);\n"
	code += pwm_init_lines
	code += "    StepDone(5);\n"
	code += _gen_init_done("Beep")
	code += "}\n\n"

	# --- ReadControllerInputs ---
	code += "void ReadControllerInputs()\n{\n"
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
	code += "                break; // 第三行只有2个按键\n"
	code += "            valueOfKey[i][j] = RcKeyValueRead(keyOffsets[i][j]);\n"
	code += "        }\n"
	code += "    }\n"
	code += "    // 读取扳机键和摩擦轮开关键\n"
	code += "    triggerKeyValue = RcKeyValueRead(%s);\n" % trigger_key_offset
	code += "    boosterKeyValue = RcKeyValueRead(%s);\n" % booster_key_offset
	if not aux_servo_slots.is_empty() or not aux_motor_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		code += "    valueOfEKey = RcKeyValueRead(KEY_OFFSET_1); // 高级设置模式切换键\n"
	code += "}\n\n"

	# --- CalculateMotorControls ---
	code += "void CalculateMotorControls()\n{\n"
	code += sprint_check
	code += arrow_sprint + "\n"
	code += "    dutyOfMotor[0] = %s;\n" % l1_formula
	code += "    dutyOfMotor[1] = %s;\n" % l2_formula
	code += "    dutyOfMotor[2] = %s;\n" % r1_formula
	code += "    dutyOfMotor[3] = %s;\n" % r2_formula
	code += "\n    // 供弹电机控制值计算\n"
	code += "    if (valueOfKey[1][3])\n"
	code += "        dutyOfMotor[4] = 0;\n"
	code += "}\n\n"

	# --- CalculateBoosterControl ---
	code += "void CalculateBoosterControl()\n{\n"
	code += "    // 非阻塞开关状态机：稳态只有 0/最大值，中间 duty 仅用于平滑斜坡。\n"
	code += "    // 将一次完整主循环视作原 Delay 间隔；每轮最多变化 1，不使用定时器中断。\n"
	code += "    // 摩擦轮开关由 %s 上升沿触发\n" % cfg.get("booster_key", "A")
	code += "    if (boosterKeyValue && !lastBoosterKeyValue)\n"
	code += "    {\n"
	code += "        statusOfBooster = !statusOfBooster;\n"
	code += "        targetDutyOfBooster = statusOfBooster ? FRICTION_MAX_DUTY : 0;\n"
	code += "        if (statusOfBooster && dutyOfBooster == 0)\n"
	code += "        {\n"
	code += "            dutyOfBooster = FRICTION_START_DUTY;\n"
	code += "        }\n"
	code += "        frictionRampActive = (dutyOfBooster != targetDutyOfBooster);\n"
	code += "        if (frictionRampActive)\n"
	code += "            FrictionBuzzerTrace(dutyOfBooster);\n"
	code += "        else\n"
	code += "            FrictionBuzzerOff();\n"
	code += "    }\n"
	code += "    else if (frictionRampActive)\n"
	code += "    {\n"
	code += "        if (targetDutyOfBooster > dutyOfBooster)\n"
	code += "            dutyOfBooster += FRICTION_STEP_DUTY;\n"
	code += "        else if (dutyOfBooster > FRICTION_START_DUTY)\n"
	code += "            dutyOfBooster -= FRICTION_STEP_DUTY;\n"
	code += "        else\n"
	code += "            dutyOfBooster = 0; // 跳过无有效转动的 0~5% 区间\n"
	code += "\n"
	code += "        if (dutyOfBooster == targetDutyOfBooster)\n"
	code += "        {\n"
	code += "            frictionRampActive = 0;\n"
	code += "            FrictionBuzzerOff();\n"
	code += "        }\n"
	code += "        else\n"
	code += "            FrictionBuzzerTrace(dutyOfBooster);\n"
	code += "    }\n"
	code += "    lastBoosterKeyValue = boosterKeyValue;\n"
	code += "}\n\n"

	# --- CalculateGimbalControls ---
	code += "void CalculateGimbalControls()\n{\n"
	if yaw_is_servo or pitch_is_servo:
		code += "    // 云台舵机控制值计算\n"
		if yaw_is_servo:
			code += "    floatDutyOfServo[0] += valueOfRoker[1][0] * changeRateOfServo[0];\n"
		if pitch_is_servo:
			code += "    floatDutyOfServo[1] += valueOfRoker[1][1] * changeRateOfServo[1];\n"
		# 归中功能：按下右摇杆时将舵机复位到中值
		if zero_enabled:
			code += "    // 按下右摇杆云台归中\n"
			code += "    if (valueOfKey[2][1])\n"
			code += "    {\n"
			if yaw_is_servo:
				code += "        floatDutyOfServo[0] = midDutyOfServo[0];\n"
			if pitch_is_servo:
				code += "        floatDutyOfServo[1] = midDutyOfServo[1];\n"
			code += "    }\n"
		if yaw_is_servo:
			code += "    dutyOfServo[0] = (uint16_t)floatDutyOfServo[0];\n"
		if pitch_is_servo:
			code += "    dutyOfServo[1] = (uint16_t)floatDutyOfServo[1];\n"
	if not yaw_is_servo:
		var yaw_dir_sign: int = _dir_to_int(cfg.get("yaw_dir", "正向"))
		var yaw_expr: String = "(int)((float)valueOfRoker[1][0] * ultraSpeed / 2047)"
		if yaw_dir_sign == 0:
			yaw_expr = "-" + yaw_expr
		code += "    // 云台 Yaw 电机控制值计算\n"
		code += "    dutyOfMotor[%d] = %s;\n" % [yaw_motor_idx, yaw_expr]
	if not pitch_is_servo:
		var pitch_dir_sign: int = _dir_to_int(cfg.get("pitch_dir", "正向"))
		var pitch_expr: String = "(int)((float)valueOfRoker[1][1] * ultraSpeed / 2047)"
		if pitch_dir_sign == 0:
			pitch_expr = "-" + pitch_expr
		code += "    // 云台 Pitch 电机控制值计算\n"
		code += "    dutyOfMotor[%d] = %s;\n" % [pitch_motor_idx, pitch_expr]
	code += "}\n\n"

	# --- 高级设置：模式切换与每模式按键映射 ---
	if not aux_servo_slots.is_empty() or not aux_motor_slots.is_empty() or use_aux_main[0] or use_aux_main[1]:
		code += _gen_update_mode(mode_count, switch_strategy, switch_key, mode_keys, aux_motor_slots)
		for mi in range(mode_count):
			var rows: Array = modes[mi].get("rows", []) if mi < modes.size() else []
			code += _gen_mode_rows(rows, io_init_shared, "Mode%d" % (mi + 1))

	# --- Main_Countrol ---
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster)\n{\n"
	code += "    // 底盘方向会随摇杆实时变化，必须先发方向帧；拓展板处理完成后再发占空比帧\n"
	code += "    ExpansionBoradControl(Dir_Change_Order,\n"
	code += "                          %s);\n" % dir_str
	code += "    Ms_Delay(EXPANSION_FRAME_GAP_MS);\n"
	code += "    ExpansionBoradControl(Duty_Change_Order, %s);\n" % duty_str
	code += "    Ms_Delay(EXPANSION_FRAME_GAP_MS);\n"
	code += pwm_set_lines
	code += "}\n\n"

	# --- ExpansionBoradControl ---
	code += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	code += "/// @param control_cmd\n"
	code += "/// @param data_p60 供弹电机\n"
	code += "/// @param data_p62 空\n"
	code += "/// @param data_p64 右摩擦轮\n"
	code += "/// @param data_p66 左摩擦轮\n"
	code += "/// @param data_p74 左前电机\n"
	code += "/// @param data_p75 左后电机\n"
	code += "/// @param data_p76 右前电机\n"
	code += "/// @param data_p77 右后电机\n"
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

class_name StaticChecker
extends RefCounted

## 静态检查规则。
## 从 ui.gd 抽出，不再直接读控件，而是接收已收集好的配置 Dictionary。
## ui.gd 的 _run_check() 负责收集数据 -> 调本检查器 -> 显示结果 + 生成代码。

const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")

# ------------------------------------------------------------------ 常量
# 扳机键 / 摩擦轮开关键的选项：0=R, 1=↑, 2=↓, 3=←, 4=->, 5..8=A/B/C/D
# 索引 1..4 属于方向键
const ARROW_KEY_INDICES: Array = [1, 2, 3, 4]
# 方向键文本（与 ARROW_KEY_INDICES 对应）
const ARROW_KEY_TEXTS: Array = ["↑", "↓", "←", "->"]
# 文档约束：P64/P66 固定用于两路摩擦轮
const FRICTION_PINS: Array = ["P64", "P66"]
# 扩展板引脚（通过 ExpansionBoradControl 控制）
# 文档明确写: 电机所有端口都可以作为舵机使用，初始化频率 50=舵机，10000=电机
const EXPANSION_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
# 主控板上仅有的两个舵机端口，只能驱动舵机，且与扩展板 P74 不是同一个 IO
const MAIN_SERVO_PINS: Array = ["MP74", "MP03"]
# 舵机相对中位的可用偏移角上限（与 CodeGenBase.SERVO_MAX_OFFSET_DEG 一致）
const SERVO_MAX_ANGLE: int = 90
# 单次增量超过此角度时提示过快（主循环 10ms 一轮）
const SERVO_STEP_WARN_DEG: int = 30
# 电机速度上限
const MOTOR_SPEED_MAX: int = 10000


# ------------------------------------------------------------------ 公开入口
## 步兵模式检查（含「高级设置」里的共享多模式按键映射）
static func check_infantry(cfg: Dictionary) -> Array:
	var issues: Array = []
	_check_channel(issues, cfg)
	_check_deadzone(issues, cfg)
	_check_speeds(issues, cfg)
	_check_trigger_params(issues, cfg)
	_check_friction_params(issues, cfg)
	_check_arrow_trigger_conflict(issues, cfg)
	_check_io_duplicate(issues, cfg)
	_check_gimbal_pin_conflict(issues, cfg)
	_check_infantry_shared(issues, cfg)
	return issues


## 工程多模式检查（工程页 + 逆解算页共同配置同一份固件）
## ik_cfg.enabled == false（或缺省视为 true）时跳过逆解算校验：
## 未启用逆解的用户不应看到任何逆解相关的报错/警告。
static func check_engineer(eng_cfg: Dictionary, ik_cfg: Dictionary) -> Array:
	var issues: Array = []
	_check_channel(issues, eng_cfg)
	_check_deadzone(issues, eng_cfg)
	_check_speeds(issues, eng_cfg)
	_check_engineer_io(issues, eng_cfg)
	_check_engineer_modes(issues, eng_cfg)
	if bool(ik_cfg.get("enabled", true)):
		_check_ik_params(issues, ik_cfg, eng_cfg)
	return issues


## 调试模式检查
static func check_debug(debug_rows: Array) -> Array:
	var issues: Array = []
	_check_debug_params(issues, debug_rows)
	return issues


# ------------------------------------------------------------------ 规则：通道号
# NRF24L01 通道号有效范围为 0-125（2.4GHz 频段）
static func _check_channel(issues: Array, cfg: Dictionary) -> void:
	var text: String = str(cfg.get("channel", "")).strip_edges()
	if text.is_empty():
		issues.append({"type": "Error", "msg": "通道号未设置（遥控器设置 -> 通道号）"})
		return
	if not text.is_valid_int():
		issues.append({"type": "Error",
			"msg": "通道号「%s」不是合法整数（应为 0-125）" % text})
		return
	var ch: int = text.to_int()
	if ch < 0 or ch > 125:
		issues.append({"type": "Error",
			"msg": "通道号 %d 超出范围（有效范围 0-125）" % ch})


# ------------------------------------------------------------------ 规则：整数范围通用校验
## 校验一个文本字段是否为指定范围内的整数。
## 留空时按 required 决定报 Error 还是跳过（沿用生成器默认值）。
static func _check_int_field(issues: Array, text: String, label: String,
		lo: int, hi: int, required: bool = false) -> void:
	text = text.strip_edges()
	if text.is_empty():
		if required:
			issues.append({"type": "Error", "msg": "%s 未设置" % label})
		return
	if not text.is_valid_int():
		issues.append({"type": "Error",
			"msg": "%s「%s」不是合法整数（有效范围 %d~%d）" % [label, text, lo, hi]})
		return
	var val: int = text.to_int()
	if val < lo or val > hi:
		issues.append({"type": "Error",
			"msg": "%s %d 超出范围（有效范围 %d~%d）" % [label, val, lo, hi]})


# ------------------------------------------------------------------ 规则：死区
# 摇杆 ADC 为 12bit（数值范围 -2047~2047），死区应在 0-2047 内
static func _check_deadzone(issues: Array, cfg: Dictionary) -> void:
	_check_int_field(issues, str(cfg.get("deadzone", "")), "死区", 0, 2047)


# ------------------------------------------------------------------ 规则：速度
static func _check_speeds(issues: Array, cfg: Dictionary) -> void:
	var normal_text: String = str(cfg.get("normal_speed", "")).strip_edges()
	var sprint_text: String = str(cfg.get("sprint_speed", "")).strip_edges()

	# 占空比上限 10000（拓展板电机满量程）
	_check_int_field(issues, normal_text, "普通速度", 0, 10000, true)
	_check_int_field(issues, sprint_text, "冲刺速度", 0, 10000)
	# 冲刺复选框被选中但未设置冲刺速度 -> Error
	# GDScript 的 == 是强类型："yes" == true 会崩（Invalid operands String/bool），
	# 必须先用 is bool 判类型。非 bool 输入一律视为 false，不崩。
	var _sp: Variant = cfg.get("sprint_enabled", false)
	var sprint_checked: bool = _sp is bool and _sp == true
	if sprint_checked and sprint_text.is_empty():
		issues.append({"type": "Error", "msg": "已勾选「按下左摇杆冲刺」但冲刺速度未设置"})

	# 冲刺速度小于普通速度 -> Warn（仅当两者均可解析时才比较）
	var n_val: float = normal_text.to_float()
	var s_val: float = sprint_text.to_float()
	if normal_text.is_valid_float() and sprint_text.is_valid_float() \
			and not normal_text.is_empty() and not sprint_text.is_empty():
		if s_val < n_val:
			issues.append({"type": "Warn",
				"msg": "冲刺速度(%d)小于普通速度(%d)，冲刺将无法生效" % [int(s_val), int(n_val)]})


# ------------------------------------------------------------------ 规则：扳机（拨弹）参数
static func _check_trigger_params(issues: Array, cfg: Dictionary) -> void:
	_check_int_field(issues, str(cfg.get("trigger_speed", "")), "拨弹速度", 0, 10000)
	# 目视闭环（按住持续拨弹）不生成时间参数，拨弹时间只对阻塞开环（单发）有效
	var visual_feed: bool = str(cfg.get("feed_mode", "阻塞开环")) == "目视闭环"
	if visual_feed:
		return
	# 生成的代码用 Ms_Delay(boosterFeedDelayMs)，参数是 uint16_t
	_check_int_field(issues, str(cfg.get("trigger_time", "")), "拨弹时间(ms)", 0, 65535)
	# 单发期间会阻塞主循环，时间过长会让整车失控
	var t_text: String = str(cfg.get("trigger_time", "")).strip_edges()
	if t_text.is_valid_int() and t_text.to_int() > 1000:
		issues.append({"type": "Warn",
			"msg": "拨弹时间 %s ms 过长，单发期间主循环阻塞，底盘和云台会失去响应" % t_text})


# ------------------------------------------------------------------ 规则：摩擦轮最大占空比
static func _check_friction_params(issues: Array, cfg: Dictionary) -> void:
	var text: String = str(cfg.get("friction_max_duty", "")).strip_edges()
	_check_int_field(issues, text, "摩擦轮最大占空比", 500, 800, true)
	if text.is_valid_int():
		var value: int = text.to_int()
		if value >= 500 and value <= 800 and value % 100 != 0:
			issues.append({"type": "Error",
				"msg": "摩擦轮最大占空比必须是 500~800 内的整百值；启停过程会以 1 duty/20ms 平滑变化"})


# ------------------------------------------------------------------ 规则：按键冲突
static func _check_arrow_trigger_conflict(issues: Array, cfg: Dictionary) -> void:
	var trig_key: String = str(cfg.get("trigger_key", ""))
	var boost_key: String = str(cfg.get("booster_key", ""))
	var arrow_key: String = str(cfg.get("arrow_key", "移动"))
	# 扳机键与摩擦轮开关键不能相同
	if trig_key == boost_key:
		issues.append({"type": "Error",
			"msg": "扳机键与摩擦轮开关键都设为「%s」，会同时触发单发拨弹和摩擦轮开关" % trig_key})
	# 方向键被设为「移动」或「冲刺」时，扳机键/开关键不能占用方向键
	var arrow_active: bool = arrow_key in ["移动", "冲刺"]
	if arrow_active:
		for pair in [[trig_key, "扳机键"], [boost_key, "摩擦轮开关键"]]:
			if pair[0] in ARROW_KEY_TEXTS:
				issues.append({"type": "Error",
					"msg": "方向键已被设为「%s」，但%s也使用了方向键「%s」，二者不能相同"
						% [arrow_key, pair[1], pair[0]]})


# ------------------------------------------------------------------ 规则：IO 重复引用
# 规则：底盘同一侧（左前/左后 或 右前/右后）允许共用一个 IO；
# 异侧之间、以及与云台各 IO 之间不能共用。
# 注意：底盘/拨弹的选项文本是引脚对（"P74 P24"），云台是单引脚（"P74"），
# 必须先归一化成通信脚再比较，否则同一物理引脚的冲突检测不出来。
static func _check_io_duplicate(issues: Array, cfg: Dictionary) -> void:
	# 为每个 IO 引用位置标注所属「组」；同组内允许共用，跨组则报错
	var io_entries: Array = [
		{"io": str(cfg.get("l1_io", "")), "label": "底盘-左前轮 IO", "group": "left"},
		{"io": str(cfg.get("l2_io", "")), "label": "底盘-左后轮 IO", "group": "left"},
		{"io": str(cfg.get("r1_io", "")), "label": "底盘-右前轮 IO", "group": "right"},
		{"io": str(cfg.get("r2_io", "")), "label": "底盘-右后轮 IO", "group": "right"},
		{"io": str(cfg.get("booster_io", "")), "label": "云台-拨弹电机 IO", "group": "booster"},
		{"io": str(cfg.get("yaw_io", "")), "label": "云台-Yaw 轴 IO", "group": "yaw"},
		{"io": str(cfg.get("pitch_io", "")), "label": "云台-Pitch 轴 IO", "group": "pitch"},
	]
	# pin -> Array[{label, group}]
	var io_map: Dictionary = {}
	for entry in io_entries:
		var pin: String = normalize_pin(entry["io"])
		if not io_map.has(pin):
			io_map[pin] = []
		io_map[pin].append({"label": entry["label"], "group": entry["group"]})
	# 摩擦轮固定占用 P64/P66，任何其他角色选到这两个引脚都是冲突
	for pin2 in FRICTION_PINS:
		if io_map.has(pin2):
			var occupants: Array = []
			for r2 in io_map[pin2]:
				occupants.append(r2["label"])
			issues.append({"type": "Error",
				"msg": "%s 已被摩擦轮固定占用，不能再分配给：%s" % [pin2, ", ".join(occupants)]})
	# 检查每个引脚的所有引用
	for pin3 in io_map.keys():
		var refs: Array = io_map[pin3]
		if refs.size() < 2:
			continue
		# 收集引用涉及的不同组
		var groups: Dictionary = {}
		for r in refs:
			groups[r["group"]] = true
		# 仅当所有引用都属于同一允许共用的底盘侧（left/right）时才放行
		if groups.size() == 1:
			var only_group: String = groups.keys()[0]
			if only_group == "left" or only_group == "right":
				_check_same_side_dir(issues, pin3, only_group, cfg)
				continue
		# 否则视为冲突，列出全部引用位置
		var locs: Array = []
		for r in refs:
			locs.append(r["label"])
		issues.append({"type": "Error",
			"msg": "IO %s 被多次引用：%s" % [pin3, ", ".join(locs)]})


## 同侧共用一个 IO 时，两轮方向必须一致，否则实际只会生效后写入的那一个
static func _check_same_side_dir(issues: Array, pin: String, side: String,
		cfg: Dictionary) -> void:
	var d1: String
	var d2: String
	if side == "left":
		d1 = str(cfg.get("l1_dir", ""))
		d2 = str(cfg.get("l2_dir", ""))
	else:
		d1 = str(cfg.get("r1_dir", ""))
		d2 = str(cfg.get("r2_dir", ""))
	if d1 != d2:
		issues.append({"type": "Warn",
			"msg": "%s 侧两轮共用 IO %s 但方向不同（%s / %s），实际只有一个方向生效"
				% ["左" if side == "left" else "右", pin, d1, d2]})


# ------------------------------------------------------------------ 规则：摩擦轮引脚 / 驱动类型
# 文档约束：P64/P66 固定用于两路摩擦轮
#   - Yaw/Pitch 若选 P64/P66 -> Error（与摩擦轮冲突）
static func _check_gimbal_pin_conflict(issues: Array, cfg: Dictionary) -> void:
	# Yaw/Pitch 轴的 (驱动类型, IO, 名称)
	var axes: Array = [
		{"drive": str(cfg.get("yaw_drive", "")), "io": str(cfg.get("yaw_io", "")), "name": "Yaw"},
		{"drive": str(cfg.get("pitch_drive", "")), "io": str(cfg.get("pitch_io", "")), "name": "Pitch"},
	]
	for ax in axes:
		var pin: String = normalize_pin(ax["io"])
		var drive: String = ax["drive"]
		# 摩擦轮引脚不可用于 Yaw/Pitch（与摩擦轮固定占用冲突）
		if pin in FRICTION_PINS:
			issues.append({"type": "Error",
				"msg": "%s 轴 IO 选用了 %s，该引脚已被摩擦轮占用" % [ax["name"], pin]})
			continue
		if pin in MAIN_SERVO_PINS:
			# 主控板舵机口不能驱动电机
			if drive == "电机":
				issues.append({"type": "Error",
					"msg": "%s 轴 IO 选用了主控板端口 %s，该端口只能驱动舵机，请改为「舵机」或换用拓展板引脚"
						% [ax["name"], pin]})
		elif not pin in EXPANSION_PINS:
			# 既不在拓展板上，也不是 MP74/MP03，无法控制
			issues.append({"type": "Error",
				"msg": "%s 轴 IO 选用了 %s，该引脚无法作为动力输出（拓展板可用 %s，主控板可用 MP74/MP03）"
					% [ax["name"], pin, "/".join(EXPANSION_PINS)]})
	# 两个轴不能使用同一个引脚（无论舵机还是电机）
	var yaw_io: String = normalize_pin(str(cfg.get("yaw_io", "")))
	var pitch_io: String = normalize_pin(str(cfg.get("pitch_io", "")))
	if yaw_io == pitch_io:
		issues.append({"type": "Error",
			"msg": "Yaw 和 Pitch 使用了相同的引脚 %s" % yaw_io})
	# 归中角是相对舵机中位的偏移角，行程 ±90°，仅在对应轴用舵机时有意义
	if str(cfg.get("yaw_drive", "")) == "舵机":
		_check_int_field(issues, str(cfg.get("yaw_mid_offset", "")), "Yaw 归中角",
			- SERVO_MAX_ANGLE, SERVO_MAX_ANGLE)
	if str(cfg.get("pitch_drive", "")) == "舵机":
		_check_int_field(issues, str(cfg.get("pitch_mid_offset", "")), "Pitch 归中角",
			- SERVO_MAX_ANGLE, SERVO_MAX_ANGLE)


# ------------------------------------------------------------------ 规则：工程 IO 初始化区
# IO 初始化区：10 个引脚各选 电机/舵机 + 初始角（相对舵机中位偏移 ±90°）。
# 底盘引脚必须为电机；主控板 MP03/MP74 只能驱动舵机。
static func _check_engineer_io(issues: Array, cfg: Dictionary) -> void:
	var io_init: Dictionary = cfg.get("io_init", {})
	var io_mid: Dictionary = cfg.get("io_mid", {})
	# 底盘引脚必须为电机（代码生成器强制以底盘为准，这里给出明确提示）
	var chassis: Array = _chassis_pins(cfg)
	for pin in chassis:
		if pin.begins_with("MP"):
			continue
		var t: String = str(io_init.get(pin, ""))
		if t.is_empty():
			issues.append({"type": "Error",
				"msg": "工程 底盘使用了 %s，但该引脚不在 IO 初始化区（可选 P60-P77）" % pin})
		elif t != "电机":
			issues.append({"type": "Error",
				"msg": "工程 底盘使用了 %s，但 IO 初始化区将其设为「%s」（底盘电机必须为电机模式）"
					% [pin, t]})
	# 主控板舵机口只能驱动舵机（硬件限制）
	for mp in ["MP03", "MP74"]:
		if str(io_init.get(mp, "舵机")) == "电机":
			issues.append({"type": "Error",
				"msg": "工程 %s 是主控板舵机口，只能驱动舵机，不能设为电机" % mp})
	# 初始角校验（相对中位，仅舵机有效）
	for pin in io_mid.keys():
		var text: String = str(io_mid[pin]).strip_edges()
		if text.is_empty():
			continue
		if not text.is_valid_float():
			issues.append({"type": "Error",
				"msg": "工程 %s 初始角「%s」不是合法数值（有效范围 -%d~%d，相对中位）"
					% [pin, text, SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
			continue
		var angle: float = text.to_float()
		if angle < -SERVO_MAX_ANGLE or angle > SERVO_MAX_ANGLE:
			issues.append({"type": "Error",
				"msg": "工程 %s 初始角 %d° 超出范围（有效范围 -%d~%d，相对中位）"
					% [pin, int(angle), SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
		if str(io_init.get(pin, "舵机")) == "电机":
			issues.append({"type": "Warn",
				"msg": "工程 %s 已设为电机，初始角不会生效" % pin})


# ------------------------------------------------------------------ 规则：工程多模式配置
# 模式数 1~4；切换方式「单击切换」（一个键轮换）或「一一对应」（每模式一个键）。
# 切换键/模式键不能与任何模式内的按键重复。
static func _check_engineer_modes(issues: Array, cfg: Dictionary) -> void:
	var mc_text: String = str(cfg.get("mode_count", "1")).strip_edges()
	var mode_count: int = 1
	if mc_text.is_empty():
		issues.append({"type": "Error", "msg": "工程 模式个数未设置（1~4）"})
	elif not mc_text.is_valid_float():
		issues.append({"type": "Error",
			"msg": "工程 模式个数「%s」不是合法整数（应为 1~4）" % mc_text})
	else:
		# JSON 数字在 Godot 里是 float（"2.0"），按数值取整
		var mc: int = int(mc_text.to_float())
		if mc < 1 or mc > 4:
			issues.append({"type": "Error",
				"msg": "工程 模式个数 %d 超出范围（支持 1~4）" % mc})
		else:
			mode_count = mc
	var strategy: String = str(cfg.get("switch_strategy", "单击切换"))
	var switch_key: String = str(cfg.get("mode_switch_key", "E"))
	var mode_keys: Array = cfg.get("mode_keys", [])
	# 一一对应：模式键互不重复
	if strategy == "一一对应":
		var used: Dictionary = {}
		for i in range(mode_count):
			var k: String = str(mode_keys[i]) if i < mode_keys.size() else ""
			if k.is_empty():
				continue
			if used.has(k):
				issues.append({"type": "Error",
					"msg": "工程 模式%d与模式%d使用了同一个模式键「%s」" % [used[k], i + 1, k]})
			else:
				used[k] = i + 1
	# 各模式行检查（含切换键冲突登记）
	var used_keys: Dictionary = {}
	var row_idx: int = 0
	var modes: Array = cfg.get("modes", []) if cfg.get("modes", []) is Array else []
	for mi in range(mode_count):
		var rows: Array = modes[mi].get("rows", []) if mi < modes.size() 			and modes[mi] is Dictionary else []
		for row in rows:
			row_idx += 1
			_check_eng_row(issues, row, mi + 1, row_idx, cfg, strategy,
				switch_key, mode_keys, used_keys)
	# 切换键与行按键冲突（单击切换：1 个切换键；一一对应：各模式键）
	var conflict_keys: Array = []
	if strategy == "一一对应":
		for i in range(mode_count):
			var k2: String = str(mode_keys[i]) if i < mode_keys.size() else ""
			if not k2.is_empty():
				conflict_keys.append(k2)
	else:
		conflict_keys.append(switch_key)
	for ck in conflict_keys:
		if used_keys.has(ck):
			issues.append({"type": "Error",
				"msg": "工程 切换键「%s」与模式%d第%d行的按键重复，会同时触发切换与动作"
					% [ck, used_keys[ck]["mode"], used_keys[ck]["row"]]})


# ------------------------------------------------------------------ 规则：工程单行按键映射
# 行模型 {key, dir, mode, param, io}
#   key ∈ E/↑/↓/←/→/A/B/C/D/LC/RC（按键）或 LX/LY/RX/RY（摇杆轴）
#   mode ∈ 增量/直接（舵机），直接/速度/增速（电机）；摇杆行只能用 增量/速度/增速
static func _check_eng_row(issues: Array, row: Dictionary, mode_no: int, row_idx: int,
		cfg: Dictionary, strategy: String, switch_key: String, mode_keys: Array,
		used_keys: Dictionary) -> void:
	var key: String = str(row.get("key", ""))
	var io: String = str(row.get("io", ""))
	var mode: String = str(row.get("mode", ""))
	var param: String = str(row.get("param", "")).strip_edges()
	var label: String = "工程 模式%d第%d行" % [mode_no, row_idx]
	if key.is_empty() or io.is_empty():
		issues.append({"type": "Error", "msg": "%s 未选择键位或 IO" % label})
		return
	var all_keys: Array = ["E", "↑", "↓", "←", "→", "A", "B", "C", "D", "LC", "RC",
		"LX", "LY", "RX", "RY"]
	if not key in all_keys:
		issues.append({"type": "Error", "msg": "%s 键位「%s」未知" % [label, key]})
		return
	var all_pins: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77",
		"MP03", "MP74"]
	if not io in all_pins:
		issues.append({"type": "Error", "msg": "%s IO「%s」未知" % [label, io]})
		return
	var is_axis: bool = key in ["LX", "LY", "RX", "RY"]
	var io_init: Dictionary = cfg.get("io_init", {})
	# 目标 IO 类型：MP 固定舵机；扩展板看 IO 初始化区
	var pin_type: String = "舵机" if io.begins_with("MP") else str(io_init.get(io, "舵机"))
	if pin_type.is_empty():
		pin_type = "舵机"
	# 与底盘冲突
	for cpin in _chassis_pins(cfg):
		if cpin == io:
			issues.append({"type": "Error", "msg": "%s IO %s 与底盘电机冲突" % [label, io]})
			return
	# 控制方式与 IO 类型匹配
	match mode:
		"增量":
			if pin_type != "舵机":
				issues.append({"type": "Error",
					"msg": "%s 增量模式只能用于舵机，但 %s 是%s" % [label, io, pin_type]})
		"直接":
			if is_axis:
				issues.append({"type": "Error",
					"msg": "%s 摇杆行不能用直接模式" % label})
		"速度", "增速":
			if pin_type != "电机":
				issues.append({"type": "Error",
					"msg": "%s %s模式只能用于电机，但 %s 是%s" % [label, mode, io, pin_type]})
			if not is_axis:
				issues.append({"type": "Error",
					"msg": "%s 按键行不能用%s模式（需要摇杆值）" % [label, mode]})
		_:
			issues.append({"type": "Error", "msg": "%s 控制方式「%s」未知" % [label, mode]})
	# 参数
	if param.is_empty():
		issues.append({"type": "Error", "msg": "%s 已选 IO %s，但参数未填写" % [label, io]})
		return
	if not param.is_valid_int():
		issues.append({"type": "Error", "msg": "%s 参数「%s」不是合法整数" % [label, param]})
		return
	var val: int = param.to_int()
	match mode:
		"增量":
			if val < 0 or val > SERVO_MAX_ANGLE:
				issues.append({"type": "Error",
					"msg": "%s 增量参数 %d 超出范围（0-%d）" % [label, val, SERVO_MAX_ANGLE]})
			elif val == 0:
				issues.append({"type": "Error",
					"msg": "%s 增量步长为 0，该行不会产生任何动作" % label})
			elif val > SERVO_STEP_WARN_DEG:
				issues.append({"type": "Warn",
					"msg": "%s 单次增量 %d° 偏大，舵机会几乎瞬间到位，建议 1-%d°"
						% [label, val, SERVO_STEP_WARN_DEG]})
		"直接":
			if pin_type == "舵机":
				if val < -SERVO_MAX_ANGLE or val > SERVO_MAX_ANGLE:
					issues.append({"type": "Error",
						"msg": "%s 舵机角度 %d 超出范围（-%d~%d，相对中位）"
							% [label, val, SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
			else:
				if val < 0 or val > 10000:
					issues.append({"type": "Error",
						"msg": "%s 电机速度 %d 超出范围（0-10000）" % [label, val]})
		"速度", "增速":
			if val < 0 or val > 10000:
				issues.append({"type": "Error",
					"msg": "%s %s参数 %d 超出范围（0-10000）" % [label, mode, val]})
	# 同模式内按键重复（+/- 双行常见，提示不拦截）
	if used_keys.has(key) and used_keys[key]["mode"] == mode_no:
		issues.append({"type": "Warn",
			"msg": "%s 按键「%s」在本模式已被第%d行使用，两行会同时生效"
				% [label, key, used_keys[key]["row"]]})
	used_keys[key] = {"mode": mode_no, "row": row_idx}


# ------------------------------------------------------------------ 规则：步兵高级设置（共享多模式按键映射）
# 步兵固定子系统占用：摩擦轮 P64/P66、拨弹电机、云台 Yaw/Pitch、底盘。
# 共享按键映射的行不能指向这些引脚；摩擦轮引脚在 IO 初始化区必须为舵机
# （摩擦轮与舵机同为 50Hz 初始化，10000 才是电机）。
static func _check_infantry_shared(issues: Array, cfg: Dictionary) -> void:
	var io_init: Dictionary = cfg.get("io_init", {})
	# 摩擦轮固定占用 P64/P66（硬件保护规则）
	for pin in FRICTION_PINS:
		if str(io_init.get(pin, "舵机")) != "舵机":
			issues.append({"type": "Error",
				"msg": "步兵 %s 已被摩擦轮固定占用，IO 初始化区必须设为舵机" % pin})
	# 预留引脚：底盘 + 摩擦轮 + 拨弹 + 云台
	var reserved: Array = _chassis_pins(cfg)
	reserved.append_array(FRICTION_PINS)
	for key in ["booster_io", "yaw_io", "pitch_io"]:
		var pin: String = str(cfg.get(key, "")).split(" ")[0]
		if not pin.is_empty():
			reserved.append(pin)
	# 行检查（复用工程行检查 + 预留引脚拦截）
	var used_keys: Dictionary = {}
	var row_idx: int = 0
	var mode_count: int = 1
	var mc_text: String = str(cfg.get("mode_count", "1")).strip_edges()
	if mc_text.is_valid_int():
		mode_count = clampi(mc_text.to_int(), 1, 4)
	var modes: Array = cfg.get("modes", []) if cfg.get("modes", []) is Array else []
	for mi in range(mode_count):
		var rows: Array = modes[mi].get("rows", []) if mi < modes.size() 			and modes[mi] is Dictionary else []
		for row in rows:
			row_idx += 1
			var io: String = str(row.get("io", ""))
			if io in reserved:
				var who: String = "摩擦轮" if io in FRICTION_PINS else "底盘/云台/拨弹"
				issues.append({"type": "Error",
					"msg": "步兵 模式%d第%d行 IO %s 与%s冲突，高级设置不能控制该引脚"
						% [mi + 1, row_idx, io, who]})
				continue
			_check_eng_row(issues, row, mi + 1, row_idx, cfg, "单击切换",
				str(cfg.get("mode_switch_key", "E")), cfg.get("mode_keys", []), used_keys)
	# 步兵云台/拨弹用到的引脚在 IO 初始化区必须与子系统类型一致（摩擦轮已查）
	for key in ["booster_io", "yaw_io", "pitch_io"]:
		var pin: String = str(cfg.get(key, "")).split(" ")[0]
		if pin.is_empty() or pin.begins_with("MP"):
			continue
		var t2: String = str(io_init.get(pin, ""))
		if t2.is_empty():
			continue
		var want: String = "电机"
		if key == "yaw_io" and str(cfg.get("yaw_drive", "舵机")) == "舵机":
			want = "舵机"
		if key == "pitch_io" and str(cfg.get("pitch_drive", "舵机")) == "舵机":
			want = "舵机"
		if t2 != want:
			var label: String = "拨弹电机" if key == "booster_io" 				else ("Yaw 轴" if key == "yaw_io" else "Pitch 轴")
			issues.append({"type": "Error",
				"msg": "步兵 %s 使用 %s，但 IO 初始化区将其设为「%s」（应为「%s」）"
					% [label, pin, t2, want]})


## 底盘四轮引脚（去重）
static func _chassis_pins(cfg: Dictionary) -> Array:
	var pins: Array = []
	for key in ["l1_io", "l2_io", "r1_io", "r2_io"]:
		var pin: String = str(cfg.get(key, "")).split(" ")[0]
		if not pin.is_empty() and not pin in pins:
			pins.append(pin)
	return pins

# ------------------------------------------------------------------ 规则：调试界面参数范围
# 舵机偏移角 ∈ [-90, 90]（相对中位），电机速度 ∈ [0, 10000]，摩擦轮速度 ∈ [0, 800]
static func _check_debug_params(issues: Array, debug_rows: Array) -> void:
	for row in debug_rows:
		# 先 is bool 判类型（enabled 可能是字符串/数字），非 bool 当 false，不崩
		var _en: Variant = row.get("enabled", false)
		if not (_en is bool and _en == true):
			continue # 留空时不报
		var pin_name: String = str(row.get("pin", "?"))
		var drive_type: String = str(row.get("drive_type", ""))
		var val: int = int(row.get("value", 0))
		var text: String = str(val)
		# 原始文本非整数时（_collect_debug_config 已用 to_int 兜底，但仍需检查）
		if not text.is_valid_int():
			issues.append({"type": "Error",
				"msg": "调试 %s 参数「%s」不是合法整数" % [pin_name, text]})
			continue
		match drive_type:
			"电机":
				if val < 0 or val > 10000:
					issues.append({"type": "Error",
						"msg": "调试 %s 电机速度 %d 超出范围（有效范围 0-10000）" % [pin_name, val]})
			"舵机":
				# 相对中位的偏移角，舵机总行程 180°，即 ±90°
				if val < -SERVO_MAX_ANGLE or val > SERVO_MAX_ANGLE:
					issues.append({"type": "Error",
						"msg": "调试 %s 舵机角度 %d 超出范围（有效范围 -%d~%d，相对中位）"
							% [pin_name, val, SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
			"摩擦轮":
				if val < 0 or val > 800:
					issues.append({"type": "Error",
						"msg": "调试 %s 摩擦轮速度 %d 超出范围（校内赛安全范围 0-800）" % [pin_name, val]})


# ------------------------------------------------------------------ 工程逆解算：静态检查
static func _check_ik_params(issues: Array, ik_cfg: Dictionary,
		eng_cfg: Dictionary) -> void:
	var result: Dictionary = IK_CONFIG.validate(ik_cfg, eng_cfg)
	issues.append_array(result.get("issues", []))


# ------------------------------------------------------------------ 工具
## 把 OptionButton 文本归一化为通信脚名："P74 P24" -> "P74"，"MP74" 保持原样
static func normalize_pin(text: String) -> String:
	var parts: PackedStringArray = text.strip_edges().split(" ", false)
	if parts.size() > 0:
		return parts[0]
	return text.strip_edges()


## 归一化按键名称（目前只处理 "->" 的特殊情况）
static func normalize_key_name(key_name: String) -> String:
	return "->" if key_name == "->" else key_name

class_name StaticChecker
extends RefCounted

## 静态检查规则。
## 从 ui.gd 抽出，不再直接读控件，而是接收已收集好的配置 Dictionary。
## ui.gd 的 _run_check() 负责收集数据 -> 调本检查器 -> 显示结果 + 生成代码。

const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")

# ------------------------------------------------------------------ 常量
# 扳机键 / 摩擦轮开关键的选项：0=R, 1=↑, 2=↓, 3=←, 4=->, 5..8=A/B/C/D
# 索引 1..4 属于方向键；索引 6/7（B/C）被摩擦轮档位微调固定占用
const ARROW_KEY_INDICES: Array = [1, 2, 3, 4]
const BOOSTER_LEVEL_KEY_INDICES: Array = [6, 7]
# 方向键文本（与 ARROW_KEY_INDICES 对应）
const ARROW_KEY_TEXTS: Array = ["↑", "↓", "←", "->"]
# 摩擦轮档位微调键文本（与 BOOSTER_LEVEL_KEY_INDICES 对应）
const BOOSTER_LEVEL_KEY_TEXTS: Array = ["B", "C"]
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
## 步兵模式检查
static func check_infantry(cfg: Dictionary) -> Array:
	var issues: Array = []
	_check_channel(issues, cfg)
	_check_deadzone(issues, cfg)
	_check_speeds(issues, cfg)
	_check_trigger_params(issues, cfg)
	_check_arrow_trigger_conflict(issues, cfg)
	_check_io_duplicate(issues, cfg)
	_check_gimbal_pin_conflict(issues, cfg)
	return issues


## 工程双模式检查（两页共同配置同一份固件）
static func check_engineer(eng_cfg: Dictionary, ik_cfg: Dictionary) -> Array:
	var issues: Array = []
	_check_channel(issues, eng_cfg)
	_check_deadzone(issues, eng_cfg)
	_check_speeds(issues, eng_cfg)
	_check_engineer_chassis_io(issues, eng_cfg)
	_check_engineer_keymap(issues, eng_cfg)
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
	# B/C 键固定用于摩擦轮档位微调，不能再被扳机键/开关键占用
	for pair2 in [[trig_key, "扳机键"], [boost_key, "摩擦轮开关键"]]:
		if pair2[0] in BOOSTER_LEVEL_KEY_TEXTS:
			issues.append({"type": "Warn",
				"msg": "%s使用了「%s」，该键已固定用于摩擦轮转速档位微调"
					% [pair2[1], pair2[0]]})


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


# ------------------------------------------------------------------ 规则：工程师底盘 IO 检查
# 底盘 L1-L4 之间：同侧（左前/左后 或 右前/右后）允许共用 IO，异侧不可
# 底盘 IO 与 IO 初始化区一致性：底盘选的槽位在 IO 初始化区必须为「电机」
static func _check_engineer_chassis_io(issues: Array, cfg: Dictionary) -> void:
	# --- 底盘 IO 重复检查 ---
	var io_entries: Array = [
		{"io": str(cfg.get("l1_io", "")), "label": "底盘-左前轮 IO", "group": "left"},
		{"io": str(cfg.get("l2_io", "")), "label": "底盘-左后轮 IO", "group": "left"},
		{"io": str(cfg.get("r1_io", "")), "label": "底盘-右前轮 IO", "group": "right"},
		{"io": str(cfg.get("r2_io", "")), "label": "底盘-右后轮 IO", "group": "right"},
	]
	var io_map: Dictionary = {}
	for entry in io_entries:
		var io_text: String = entry["io"]
		var pin: String = io_text.split(" ")[0] if io_text.contains(" ") else io_text
		if not io_map.has(pin):
			io_map[pin] = []
		io_map[pin].append({"label": entry["label"], "group": entry["group"]})
	for pin in io_map.keys():
		var refs: Array = io_map[pin]
		if refs.size() < 2:
			continue
		var groups: Dictionary = {}
		for r in refs:
			groups[r["group"]] = true
		# 同侧（left 或 right）允许共用
		if groups.size() == 1:
			var only_group: String = groups.keys()[0]
			if only_group == "left" or only_group == "right":
				continue
		var locs: Array = []
		for r in refs:
			locs.append(r["label"])
		issues.append({"type": "Error",
			"msg": "工程底盘 IO %s 被多次引用：%s" % [pin, ", ".join(locs)]})
	# --- 底盘 IO 与 IO 初始化区一致性 ---
	var io_init: Dictionary = cfg.get("io_init", {})
	for entry in io_entries:
		var io_text2: String = entry["io"]
		var pin2: String = io_text2.split(" ")[0] if io_text2.contains(" ") else io_text2
		# MP03/MP74 不是底盘电机 IO，跳过
		if pin2.begins_with("MP"):
			continue
		if not io_init.has(pin2):
			issues.append({"type": "Error",
				"msg": "工程 %s 选了 %s，但该引脚不在 IO 初始化区（可选 P60-P77）"
					% [entry["label"], pin2]})
			continue
		var init_type: String = io_init.get(pin2, "")
		if init_type != "电机":
			issues.append({"type": "Error",
				"msg": "工程 %s 选了 %s，但 IO 初始化区将其设为「%s」（底盘电机必须为电机模式）"
					% [entry["label"], pin2, init_type]})


# ------------------------------------------------------------------ 规则：工程师按键映射检查
static func _check_engineer_keymap(issues: Array, cfg: Dictionary) -> void:
	var io_init: Dictionary = cfg.get("io_init", {})
	var key_map: Array = cfg.get("key_map", [])
	# IO 类型映射（MP03/MP74 -> 舵机，P60-P77 -> io_init 中的类型）
	var slot_type: Dictionary = {}
	for pin in ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]:
		slot_type[pin] = io_init.get(pin, "舵机")
	slot_type["MP03"] = "舵机"
	slot_type["MP74"] = "舵机"
	# 底盘占用的引脚（按键映射不可重复使用）
	var chassis_pins: Array = []
	for key in ["l1_io", "l2_io", "r1_io", "r2_io"]:
		var io_text: String = str(cfg.get(key, ""))
		if io_text.is_empty():
			continue
		chassis_pins.append(io_text.split(" ")[0] if io_text.contains(" ") else io_text)
	# 按目标 IO 分组，用于跨行写冲突判定
	var groups: Dictionary = {}
	# 至少要有一行配了目标，否则生成的代码只有底盘能动
	var configured_rows: int = 0
	for row0 in key_map:
		if not String(row0.get("target", "")).is_empty():
			configured_rows += 1
	if configured_rows == 0:
		issues.append({"type": "Warn",
			"msg": "工程 按键映射区没有任何一行配置目标 IO，生成的代码只有底盘可动"})
	# --- 逐行检查 ---
	for row in key_map:
		var target: String = str(row.get("target", ""))
		if target.is_empty():
			continue
		# 标签取自行自身的 input，避免 key_map 有行被跳过时索引错位
		var label: String = str(row.get("input", "?"))
		var mode: String = str(row.get("mode", "增量"))
		var t_type: String = slot_type.get(target, "舵机")
		if t_type.is_empty():
			t_type = "舵机"
		if not groups.has(target):
			groups[target] = []
		groups[target].append({"label": label, "mode": mode, "dir": str(row.get("dir", "正")),
			"type": t_type})
		# 目标 IO 与底盘电机冲突
		if not target.begins_with("MP") and target in chassis_pins:
			issues.append({"type": "Error",
				"msg": "工程 %s 目标 IO %s 与底盘电机 IO 冲突" % [label, target]})
		# IO 初始化区未包含该 IO
		if not target.begins_with("MP") and not io_init.has(target):
			issues.append({"type": "Warn",
				"msg": "工程 %s 目标 IO %s 未在 IO 初始化区配置" % [label, target]})
		# 控制模式与 IO 类型匹配
		match mode:
			"增量":
				if t_type != "舵机":
					issues.append({"type": "Error",
						"msg": "工程 %s 增量模式只能用于舵机，但 %s 是%s" % [label, target, t_type]})
			"速度", "增速":
				if t_type != "电机":
					issues.append({"type": "Error",
						"msg": "工程 %s %s模式只能用于电机，但 %s 是%s" % [label, mode, target, t_type]})
			"直接":
				# 舵机「直接」模式的参数已经是带符号的目标角，方向选项不参与生成
				if t_type == "舵机" and str(row.get("dir", "正")) == "反":
					issues.append({"type": "Warn",
						"msg": "工程 %s 舵机直接模式的方向选「反」不会生效，请直接填负角度" % label})
		# 摇杆行不能用「直接」模式
		var is_joystick: bool = label in ["右摇杆X", "右摇杆Y"]
		if is_joystick and mode == "直接":
			issues.append({"type": "Error",
				"msg": "工程 %s 摇杆行不能用直接模式" % label})
		# 按键行不能用「速度/增速」模式
		if not is_joystick and mode in ["速度", "增速"]:
			issues.append({"type": "Error",
				"msg": "工程 %s 按键行不能用%s模式（需要摇杆值）" % [label, mode]})
		# --- 参数检查 ---
		var param: String = str(row.get("param", ""))
		if param.is_empty():
			# 配置了目标却没填参数 -> 生成出的语句是 += 0 / = 0，等于没配
			issues.append({"type": "Error",
				"msg": "工程 %s 已选目标 IO %s，但参数未填写" % [label, target]})
			continue
		if not param.is_valid_int():
			issues.append({"type": "Error",
				"msg": "工程 %s 参数「%s」不是合法整数" % [label, param]})
			continue
		var val: int = param.to_int()
		match mode:
			"增量":
				if val < 0 or val > SERVO_MAX_ANGLE:
					issues.append({"type": "Error",
						"msg": "工程 %s 增量参数 %d 超出范围（0-%d）" % [label, val, SERVO_MAX_ANGLE]})
				elif val == 0:
					issues.append({"type": "Error",
						"msg": "工程 %s 增量步长为 0，该行不会产生任何动作" % label})
				elif val > SERVO_STEP_WARN_DEG:
					# 单次增量按角度折算成占空比，主循环 10ms 一轮，过大会瞬间打到行程端点
					issues.append({"type": "Warn",
						"msg": "工程 %s 单次增量 %d° 偏大，舵机会几乎瞬间到位，建议 1-%d°"
							% [label, val, SERVO_STEP_WARN_DEG]})
			"直接":
				if t_type == "舵机":
					if val < -SERVO_MAX_ANGLE or val > SERVO_MAX_ANGLE:
						issues.append({"type": "Error",
							"msg": "工程 %s 舵机角度 %d 超出范围（-%d~%d）"
								% [label, val, SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
				else:
					if val < 0 or val > 10000:
						issues.append({"type": "Error",
							"msg": "工程 %s 电机速度 %d 超出范围（0-10000）" % [label, val]})
			"速度", "增速":
				if val < 0 or val > 10000:
					issues.append({"type": "Error",
						"msg": "工程 %s %s参数 %d 超出范围（0-10000）" % [label, mode, val]})
	# --- 跨行写冲突检查（同一目标 IO 被多行驱动）---
	# 允许：同一舵机多行「增量」（双向控制的常见用法）、同一电机多行「直接」（if/else if 链）、
	#       同一电机「摇杆速度/增速」+「按键直接」（按键覆盖摇杆）
	# 禁止：同一舵机混用「增量」和「直接」、同一电机多行「速度」（后者覆盖前者）
	for target in groups.keys():
		var rows: Array = groups[target]
		if rows.size() < 2:
			continue
		var t_type: String = rows[0]["type"]
		var mode_labels: Dictionary = {}
		for r in rows:
			if not mode_labels.has(r["mode"]):
				mode_labels[r["mode"]] = []
			mode_labels[r["mode"]].append(r["label"])
		if t_type == "舵机":
			if mode_labels.has("增量") and mode_labels.has("直接"):
				issues.append({"type": "Error",
					"msg": "工程 IO %s 同时被增量（%s）和直接（%s）驱动，两种语义会互相覆盖"
						% [target, ", ".join(mode_labels["增量"]), ", ".join(mode_labels["直接"])]})
			# 多行「直接」写同一舵机时生成的是并列 if，同时按下时后一行赢
			if mode_labels.has("直接") and mode_labels["直接"].size() > 1:
				issues.append({"type": "Warn",
					"msg": "工程 IO %s 被多行直接模式驱动（%s），同时按下时以靠后的一行为准"
						% [target, ", ".join(mode_labels["直接"])]})
		else:
			if mode_labels.has("速度") and mode_labels["速度"].size() > 1:
				issues.append({"type": "Error",
					"msg": "工程 IO %s 被多行速度模式驱动（%s），后一行会覆盖前一行"
						% [target, ", ".join(mode_labels["速度"])]})
			# 电机无摇杆行时才会在 if/else if 链尾补 else 归零；
			# "增速 + 直接"组合没有归零，松开按键后值会被增速持续累加
			if mode_labels.has("增速") and mode_labels.has("直接"):
				issues.append({"type": "Warn",
					"msg": "工程 IO %s 同时被增速（%s）和直接（%s）驱动，按键松开后不会归零"
						% [target, ", ".join(mode_labels["增速"]), ", ".join(mode_labels["直接"])]})

	# --- IO 初始化区配了但无任何输入驱动的槽位 ---
	# 生成器会把这些槽位按「未使用」处理（Init 发 0），在界面上提醒以免误以为已生效
	var unused_pins: Array = []
	for pin2 in EXPANSION_PINS:
		if pin2 in chassis_pins or groups.has(pin2):
			continue
		unused_pins.append(pin2)
	if not unused_pins.is_empty():
		issues.append({"type": "Info",
			"msg": "工程 以下引脚未被底盘或按键映射使用，不会被初始化：%s"
				% ", ".join(unused_pins)})


# ------------------------------------------------------------------ 规则：调试界面参数范围
# 舵机偏移角 ∈ [-90, 90]（相对中位），电机速度 ∈ [0, 10000]，摩擦轮速度 ∈ [0, 1100]
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
				if val < 0 or val > 1100:
					issues.append({"type": "Error",
						"msg": "调试 %s 摩擦轮速度 %d 超出范围（有效范围 0-1100）" % [pin_name, val]})


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

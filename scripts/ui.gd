extends Control
## 主界面脚本。
## 负责收集各个配置控件的当前值并执行静态检查，把结果输出到 Output 代码框。
## 检查规则：
##   - 通道号未设置 / 范围非法       -> Error（有效范围 0-125）
##   - 普通速度未设置                 -> Error
##   - 冲刺复选框选中但未设冲刺速度   -> Error
##   - 同一 IO 被多次引用（跨侧/跨云台）-> Error（列出引用位置）
##   - 方向键设为冲刺/移动但扳机键相同 -> Error
##   - 摩擦轮引脚 P64/P66 被 Yaw/Pitch 占用 -> Error
##   - Yaw/Pitch 选「电机」却用了摩擦轮引脚 -> Error
##   - 冲刺速度 < 普通速度            -> Warn
##   - 死区超出 0-2047                -> Warn


# ------------------------------------------------------------------ 节点路径
# 遥控器
const P_CHANNEL: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/RemoteSetting/Channel/LineEdit"
const P_DEADZONE: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/RemoteSetting/DeadZone/LineEdit"
# 底盘
const P_L1_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/L1/OptionButton"
const P_L2_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/L2/OptionButton"
const P_R1_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/R1/OptionButton"
const P_R2_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/R2/OptionButton"
const P_NORMAL_SPEED: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/Speed/LineEdit"
const P_SPRINT_SPEED: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/SprintSpeed/LineEdit"
# 云台（步兵）
const GIMBAL: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Infantry/GimbalSetting"
const P_BOOSTER_IO: NodePath = GIMBAL + "/Booster/OptionButton"
const P_YAW_DRIVE: NodePath = GIMBAL + "/Yaw/OptionButton"
const P_YAW_IO: NodePath = GIMBAL + "/Yaw/OptionButton2"
const P_PITCH_DRIVE: NodePath = GIMBAL + "/Pitch/OptionButton"
const P_PITCH_IO: NodePath = GIMBAL + "/Pitch/OptionButton2"
# 按键映射
const KEYSET: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Infantry/KeySetting"
const P_SPRINT_CB: NodePath = KEYSET + "/Sprint/CheckBox"
const P_ARROW_KEY: NodePath = KEYSET + "/ArrowKey/CheckBox"
const P_TRIGGER: NodePath = KEYSET + "/Trigger/OptionButton"
# 输出
const P_OUTPUT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output"


# ------------------------------------------------------------------ 生命周期
func _ready() -> void:
	# 初始执行一次检查，并在控件变化时实时检查
	_run_check()
	_connect_signals()


# ------------------------------------------------------------------ 信号连接
func _connect_signals() -> void:
	# LineEdit 文本变化
	for p in [P_CHANNEL, P_DEADZONE, P_NORMAL_SPEED, P_SPRINT_SPEED]:
		var node: Node = get_node_or_null(p)
		if node is LineEdit:
			node.text_changed.connect(_run_check)
	# OptionButton 选项变化
	for p in [P_L1_IO, P_L2_IO, P_R1_IO, P_R2_IO,
			P_BOOSTER_IO, P_YAW_DRIVE, P_YAW_IO,
			P_PITCH_DRIVE, P_PITCH_IO, P_TRIGGER]:
		var node2: Node = get_node_or_null(p)
		if node2 is OptionButton:
			node2.item_selected.connect(_run_check)
	# ArrowKey 是 OptionButton（移动/冲刺/其他）
	var arrow: Node = get_node_or_null(P_ARROW_KEY)
	if arrow is OptionButton:
		arrow.item_selected.connect(_run_check)
	# 冲刺复选框
	var sprint_cb: Node = get_node_or_null(P_SPRINT_CB)
	if sprint_cb is BaseButton:
		sprint_cb.toggled.connect(_run_check)


# ------------------------------------------------------------------ 检查入口
func _run_check(_a = null, _b = null) -> void:
	var issues: Array = []
	_check_channel(issues)
	_check_deadzone(issues)
	_check_speeds(issues)
	_check_arrow_trigger_conflict(issues)
	_check_io_duplicate(issues)
	_check_gimbal_pin_conflict(issues)
	# 将问题展示到 Output
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("set_issues"):
		out.set_issues(issues)


# ------------------------------------------------------------------ 规则：通道号
# NRF24L01 通道号有效范围为 0-125（2.4GHz 频段）
func _check_channel(issues: Array) -> void:
	var text: String = _get_line_text(P_CHANNEL).strip_edges()
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


# ------------------------------------------------------------------ 规则：死区
# 摇杆 ADC 为 12bit（数值范围 -2047~2047），死区应在 0-2047 内
func _check_deadzone(issues: Array) -> void:
	var text: String = _get_line_text(P_DEADZONE).strip_edges()
	if text.is_empty():
		return # 留空时不报，沿用默认
	if not text.is_valid_int():
		issues.append({"type": "Warn",
			"msg": "死区「%s」不是合法整数（建议 0-2047）" % text})
		return
	var dz: int = text.to_int()
	if dz < 0 or dz > 2047:
		issues.append({"type": "Warn",
			"msg": "死区 %d 超出范围（有效范围 0-2047）" % dz})


# ------------------------------------------------------------------ 规则：速度
func _check_speeds(issues: Array) -> void:
	var normal_text: String = _get_line_text(P_NORMAL_SPEED).strip_edges()
	var sprint_text: String = _get_line_text(P_SPRINT_SPEED).strip_edges()

	if normal_text.is_empty():
		issues.append({"type": "Error", "msg": "普通速度未设置（底盘 -> 普通速度）"})
	# 冲刺复选框被选中但未设置冲刺速度 -> Error
	var sprint_cb: Node = get_node_or_null(P_SPRINT_CB)
	var sprint_checked: bool = (sprint_cb is BaseButton) and sprint_cb.button_pressed
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


# ------------------------------------------------------------------ 规则：方向键与扳机键冲突
func _check_arrow_trigger_conflict(issues: Array) -> void:
	# ArrowKey 选项：0=移动, 1=冲刺, 2=其他
	var arrow: Node = get_node_or_null(P_ARROW_KEY)
	if not arrow is OptionButton:
		return
	var arrow_idx: int = arrow.selected
	if arrow_idx != 0 and arrow_idx != 1:
		return # 「其他」不视为方向键使用
	# Trigger 选项：0=R, 1=↑, 2=↓, 3=←, 4=->, 5..8=A/B/C/D
	var trigger: Node = get_node_or_null(P_TRIGGER)
	if not trigger is OptionButton:
		return
	var trig_idx: int = trigger.selected
	# 方向键对应 ↑↓←-> (1..4)；若扳机键也选了同一方向键，则冲突
	if trig_idx in [1, 2, 3, 4]:
		var arrow_label: String = "移动" if arrow_idx == 0 else "冲刺"
		issues.append({"type": "Error",
			"msg": "方向键已被设为「%s」，但扳机键也使用了方向键「%s」，二者不能相同"
				% [arrow_label, trigger.get_item_text(trig_idx)]})


# ------------------------------------------------------------------ 规则：IO 重复引用
# 规则：底盘同一侧（左前/左后 或 右前/右后）允许共用一个 IO；
# 异侧之间、以及与云台各 IO 之间不能共用。
func _check_io_duplicate(issues: Array) -> void:
	# 为每个 IO 引用位置标注所属「组」；同组内允许共用，跨组则报错
	var io_entries: Array = [
		{"path": P_L1_IO, "label": "底盘-左前轮 IO", "group": "left"},
		{"path": P_L2_IO, "label": "底盘-左后轮 IO", "group": "left"},
		{"path": P_R1_IO, "label": "底盘-右前轮 IO", "group": "right"},
		{"path": P_R2_IO, "label": "底盘-右后轮 IO", "group": "right"},
		{"path": P_BOOSTER_IO, "label": "云台-拨弹电机 IO", "group": "booster"},
		{"path": P_YAW_IO, "label": "云台-Yaw 轴 IO", "group": "yaw"},
		{"path": P_PITCH_IO, "label": "云台-Pitch 轴 IO", "group": "pitch"},
	]
	# io_text -> Array[{label, group}]
	var io_map: Dictionary = {}
	for entry in io_entries:
		var btn: Node = get_node_or_null(entry["path"])
		if not btn is OptionButton:
			continue
		var io_text: String = btn.get_item_text(btn.selected)
		if not io_map.has(io_text):
			io_map[io_text] = []
		io_map[io_text].append({"label": entry["label"], "group": entry["group"]})
	# 检查每个 IO 的所有引用
	for io_text in io_map.keys():
		var refs: Array = io_map[io_text]
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
				continue
		# 否则视为冲突，列出全部引用位置
		var locs: Array = []
		for r in refs:
			locs.append(r["label"])
		issues.append({"type": "Error",
			"msg": "IO %s 被多次引用：%s" % [io_text, ", ".join(locs)]})


# ------------------------------------------------------------------ 规则：摩擦轮引脚 / 驱动类型
# 文档约束：P64/P66 固定用于两路摩擦轮，与两路舵机共用 PWM 信号。
#   - Yaw/Pitch 若选 P64/P66 -> Error（与摩擦轮冲突）
#   - Yaw/Pitch 选「电机」驱动时不能用 P64/P66（电机无对应 PWM 通道）-> Error
const FRICTION_PINS: Array = ["P64", "P66"]

func _check_gimbal_pin_conflict(issues: Array) -> void:
	# Yaw/Pitch 轴的 (驱动类型节点, IO节点, 名称)
	var axes: Array = [
		{"drive": P_YAW_DRIVE, "io": P_YAW_IO, "name": "Yaw"},
		{"drive": P_PITCH_DRIVE, "io": P_PITCH_IO, "name": "Pitch"},
	]
	for ax in axes:
		var drive_btn: Node = get_node_or_null(ax["drive"])
		var io_btn: Node = get_node_or_null(ax["io"])
		if not drive_btn is OptionButton or not io_btn is OptionButton:
			continue
		# 0=电机, 1=舵机
		var drive_type: int = drive_btn.selected
		var io_text: String = io_btn.get_item_text(io_btn.selected)
		if io_text in FRICTION_PINS:
			issues.append({"type": "Error",
				"msg": "%s 轴 IO 选用了 %s，该引脚已被摩擦轮占用" % [ax["name"], io_text]})
		# 「电机」驱动时摩擦轮引脚不可用（PWM 通道已被摩擦轮占用）
		if drive_type == 0 and io_text in FRICTION_PINS:
			issues.append({"type": "Error",
				"msg": "%s 轴选「电机」驱动时不能使用 %s（摩擦轮 PWM 通道占用）"
					% [ax["name"], io_text]})


# ------------------------------------------------------------------ 工具
func _get_line_text(path: NodePath) -> String:
	var node: Node = get_node_or_null(path)
	if node is LineEdit:
		return node.text
	return ""

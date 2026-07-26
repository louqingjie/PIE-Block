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
# 底盘方向（正向 id=0 / 反向 id=1）
const CHASSIS: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis"
const P_L1_DIR: NodePath = CHASSIS + "/L1/OptionButton2"
const P_L2_DIR: NodePath = CHASSIS + "/L2/OptionButton2"
const P_R1_DIR: NodePath = CHASSIS + "/R1/OptionButton2"
const P_R2_DIR: NodePath = CHASSIS + "/R2/OptionButton2"
# 云台（步兵）
const GIMBAL: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Infantry/GimbalSetting"
const P_BOOSTER_IO: NodePath = GIMBAL + "/Booster/OptionButton"
const P_BOOSTER_DIR: NodePath = GIMBAL + "/Booster/OptionButton2"
const P_FRICTION_L_DIR: NodePath = GIMBAL + "/P64/OptionButton"
const P_FRICTION_R_DIR: NodePath = GIMBAL + "/P66/OptionButton"
const P_YAW_DRIVE: NodePath = GIMBAL + "/Yaw/OptionButton"
const P_YAW_IO: NodePath = GIMBAL + "/Yaw/OptionButton2"
const P_YAW_DIR: NodePath = GIMBAL + "/Yaw/OptionButton3"
const P_PITCH_DRIVE: NodePath = GIMBAL + "/Pitch/OptionButton"
const P_PITCH_IO: NodePath = GIMBAL + "/Pitch/OptionButton2"
const P_PITCH_DIR: NodePath = GIMBAL + "/Pitch/OptionButton3"
# 按键映射
const KEYSET: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Infantry/KeySetting"
const P_SPRINT_CB: NodePath = KEYSET + "/Sprint/CheckBox"
const P_ARROW_KEY: NodePath = KEYSET + "/ArrowKey/CheckBox"
const P_TRIGGER: NodePath = KEYSET + "/Trigger/OptionButton"
const P_TRIGGER_SPEED: NodePath = KEYSET + "/Trigger/Speed"
const P_TRIGGER_TIME: NodePath = KEYSET + "/Trigger/Time"
const P_BOOSTER_KEY: NodePath = KEYSET + "/Booster/OptionButton"
# 调试界面
const DEBUG: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Debug"
# 调试界面各行容器名（P60, P62, P64, P66, P74, P75, P76, P77, MP03, MP74）
const DEBUG_ROWS: Array = [
	"HBoxContainer",  "HBoxContainer2",  "HBoxContainer3",  "HBoxContainer4",  "HBoxContainer5",
	"HBoxContainer6", "HBoxContainer7",  "HBoxContainer8",  "HBoxContainer9",  "HBoxContainer10",
]
# 输出
const P_OUTPUT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output"
const P_CODE_EDIT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit"
# 顶栏按钮
const P_BUILD_BTN: NodePath = "VBoxContainer/TopPanel/Build"
# Keil 工具链源路径（res://，打包进 pck，只读）
const TOOLCHAIN_SRC: String = "res://stc32g/toolchain/Keil_noarm"
# 工具链解压目标路径（user://，可写，TOOLS.INI 需动态生成绝对路径）
const TOOLCHAIN_DST: String = "user://keil"
# 项目模板源路径（res://，只读）
const PROJECT_SRC: String = "res://stc32g/Projects/ROBOMASTER_INFANTRY"
# 项目模板解压目标路径（user://，可写 main.c 和日志）
# 保持 stc32g/ 层级结构，因为 uvproj 用相对路径 ..\..\..\Libraries\ 引用库
const PROJECT_DST: String = "user://stc32g/Projects/ROBOMASTER_INFANTRY"
# 库文件源路径（res://，只读）— uvproj 通过 ..\..\..\Libraries\ 相对引用
const LIBRARIES_SRC: String = "res://stc32g/Libraries"
# 库文件目标路径（user://，只读使用）
const LIBRARIES_DST: String = "user://stc32g/Libraries"
# 编译日志文件名
const BUILD_LOG_NAME: String = "pie_block_build.log"
# 工具链版本标记文件（内容变更时触发重新解压）
const TOOLCHAIN_VERSION: String = "keil_noarm_v1"
# UV4 可执行文件候选名，按优先级排序：
# uVision.com 是控制台子系统版本，-b 批处理时不会弹出 GUI 窗口盖住本程序；
# UV4.exe 是 GUI 子系统版本，会弹窗抢焦点，仅作回退。
# 注：PackedStringArray 字面量不是常量表达式，故用 var 而非 const
var UV4_CANDIDATES: PackedStringArray = PackedStringArray(["uVision.com", "UV4.exe"])


# ------------------------------------------------------------------ 生命周期
var _build_thread: Thread = null
var _build_busy: bool = false


func _ready() -> void:
	# 为 C 代码预览框挂载语法高亮器（状态机正则）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		var hl: SyntaxHighlighter = preload("res://scripts/c_highlighter.gd").new()
		code_edit.syntax_highlighter = hl
	# 初始执行一次检查，并在控件变化时实时检查
	_run_check()
	_connect_signals()
	# 初始化调试界面输入框占位提示
	_update_debug_placeholders()


# ------------------------------------------------------------------ 信号连接
func _connect_signals() -> void:
	# LineEdit 文本变化
	for p in [P_CHANNEL, P_DEADZONE, P_NORMAL_SPEED, P_SPRINT_SPEED,
			P_TRIGGER_SPEED, P_TRIGGER_TIME]:
		var node: Node = get_node_or_null(p)
		if node is LineEdit:
			node.text_changed.connect(_run_check)
	# OptionButton 选项变化
	for p in [P_L1_IO, P_L2_IO, P_R1_IO, P_R2_IO,
			P_L1_DIR, P_L2_DIR, P_R1_DIR, P_R2_DIR,
			P_BOOSTER_IO, P_BOOSTER_DIR,
			P_FRICTION_L_DIR, P_FRICTION_R_DIR,
			P_YAW_DRIVE, P_YAW_IO, P_YAW_DIR,
			P_PITCH_DRIVE, P_PITCH_IO, P_PITCH_DIR,
			P_TRIGGER, P_BOOSTER_KEY]:
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
	# 编译按钮
	var build_btn: Node = get_node_or_null(P_BUILD_BTN)
	if build_btn is BaseButton:
		build_btn.pressed.connect(_on_build_pressed)
	# 调试界面：驱动类型变化时更新占位提示
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/OptionButton"))
		if drive_btn is OptionButton:
			drive_btn.item_selected.connect(_update_debug_placeholders)
			drive_btn.item_selected.connect(_run_check)
	# 调试界面：输入框文本变化时触发检查
	for row_name in DEBUG_ROWS:
		var debug_le: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/LineEdit"))
		if debug_le is LineEdit:
			debug_le.text_changed.connect(_run_check)


# ------------------------------------------------------------------ 调试界面占位提示
## 根据调试界面各行驱动类型（电机/舵机/摩擦轮）更新输入框占位文本
func _update_debug_placeholders(_idx: int = -1) -> void:
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/OptionButton"))
		var line_edit: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/LineEdit"))
		if not drive_btn is OptionButton or not line_edit is LineEdit:
			continue
		var drive_type: String = drive_btn.get_item_text(drive_btn.selected)
		var placeholder: String = ""
		match drive_type:
			"电机":
				placeholder = "速度 0~10000"
			"舵机":
				placeholder = "角度 -180~180"
			"摩擦轮":
				placeholder = "速度 0~1100"
		line_edit.placeholder_text = placeholder


# ------------------------------------------------------------------ 规则：调试界面参数范围
# 舵机角度 ∈ [-180, 180]，电机速度 ∈ [0, 10000]，摩擦轮速度 ∈ [0, 1100]
func _check_debug_params(issues: Array) -> void:
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/OptionButton"))
		var line_edit: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/LineEdit"))
		var label_node: Node = get_node_or_null(NodePath(DEBUG + "/" + row_name + "/Label"))
		if not drive_btn is OptionButton or not line_edit is LineEdit:
			continue
		var text: String = line_edit.text.strip_edges()
		if text.is_empty():
			continue # 留空时不报
		var pin_name: String = label_node.text if label_node is Label else row_name
		var drive_type: String = drive_btn.get_item_text(drive_btn.selected)
		if not text.is_valid_int():
			issues.append({"type": "Error",
				"msg": "调试 %s 参数「%s」不是合法整数" % [pin_name, text]})
			continue
		var val: int = text.to_int()
		match drive_type:
			"电机":
				if val < 0 or val > 10000:
					issues.append({"type": "Error",
						"msg": "调试 %s 电机速度 %d 超出范围（有效范围 0-10000）" % [pin_name, val]})
			"舵机":
				if val < -180 or val > 180:
					issues.append({"type": "Error",
						"msg": "调试 %s 舵机角度 %d 超出范围（有效范围 -180~180）" % [pin_name, val]})
			"摩擦轮":
				if val < 0 or val > 1100:
					issues.append({"type": "Error",
						"msg": "调试 %s 摩擦轮速度 %d 超出范围（有效范围 0-1100）" % [pin_name, val]})


# ------------------------------------------------------------------ 检查入口
func _run_check(_a = null, _b = null) -> void:
	var issues: Array = []
	_check_channel(issues)
	_check_deadzone(issues)
	_check_speeds(issues)
	_check_arrow_trigger_conflict(issues)
	_check_io_duplicate(issues)
	_check_gimbal_pin_conflict(issues)
	_check_debug_params(issues)
	# 将问题展示到 Output
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("set_issues"):
		out.set_issues(issues)
	# 实时生成 main.c 并预览到 CodeEdit
	var cfg: Dictionary = _collect_config()
	var code: String = _generate_main_c(cfg)
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		code_edit.text = code


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
# 文档约束：P64/P66 固定用于两路摩擦轮
#   - Yaw/Pitch 若选 P64/P66 -> Error（与摩擦轮冲突）
const FRICTION_PINS: Array = ["P64", "P66"]
# 扩展板引脚（通过 ExpansionBoradControl 控制）
# 文档明确写: 电机所有端口都可以作为舵机使用，初始化频率 50=舵机，10000=电机
const EXPANSION_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]

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
		var io_text: String = io_btn.get_item_text(io_btn.selected)
		# 摩擦轮引脚不可用于 Yaw/Pitch（与摩擦轮固定占用冲突）
		if io_text in FRICTION_PINS:
			issues.append({"type": "Error",
				"msg": "%s 轴 IO 选用了 %s，该引脚已被摩擦轮占用" % [ax["name"], io_text]})
	# 两个轴不能使用同一个引脚（无论舵机还是电机）
	var yaw_io: String = _get_option_text(P_YAW_IO)
	var pitch_io: String = _get_option_text(P_PITCH_IO)
	if yaw_io == pitch_io:
		issues.append({"type": "Error",
			"msg": "Yaw 和 Pitch 使用了相同的引脚 %s" % yaw_io})


# ------------------------------------------------------------------ 工具
func _get_line_text(path: NodePath) -> String:
	var node: Node = get_node_or_null(path)
	if node is LineEdit:
		return node.text
	return ""


# ------------------------------------------------------------------ 配置收集
## 从 UI 控件收集所有参数，返回字典供代码生成使用
func _collect_config() -> Dictionary:
	var cfg: Dictionary = {}
	# --- 遥控器参数 ---
	cfg["channel"] = _get_line_text(P_CHANNEL).strip_edges()
	cfg["deadzone"] = _get_line_text(P_DEADZONE).strip_edges()
	# --- 底盘参数 ---
	cfg["l1_io"] = _get_option_text(P_L1_IO)
	cfg["l1_dir"] = _get_option_text(P_L1_DIR)
	cfg["l2_io"] = _get_option_text(P_L2_IO)
	cfg["l2_dir"] = _get_option_text(P_L2_DIR)
	cfg["r1_io"] = _get_option_text(P_R1_IO)
	cfg["r1_dir"] = _get_option_text(P_R1_DIR)
	cfg["r2_io"] = _get_option_text(P_R2_IO)
	cfg["r2_dir"] = _get_option_text(P_R2_DIR)
	cfg["normal_speed"] = _get_line_text(P_NORMAL_SPEED).strip_edges()
	cfg["sprint_speed"] = _get_line_text(P_SPRINT_SPEED).strip_edges()
	var sprint_cb: Node = get_node_or_null(P_SPRINT_CB)
	cfg["sprint_enabled"] = (sprint_cb is BaseButton) and sprint_cb.button_pressed
	# --- 云台参数 ---
	cfg["booster_io"] = _get_option_text(P_BOOSTER_IO)
	cfg["booster_dir"] = _get_option_text(P_BOOSTER_DIR)
	cfg["friction_l_dir"] = _get_option_text(P_FRICTION_L_DIR)
	cfg["friction_r_dir"] = _get_option_text(P_FRICTION_R_DIR)
	cfg["yaw_drive"] = _get_option_text(P_YAW_DRIVE)
	cfg["yaw_io"] = _get_option_text(P_YAW_IO)
	cfg["yaw_dir"] = _get_option_text(P_YAW_DIR)
	cfg["pitch_drive"] = _get_option_text(P_PITCH_DRIVE)
	cfg["pitch_io"] = _get_option_text(P_PITCH_IO)
	cfg["pitch_dir"] = _get_option_text(P_PITCH_DIR)
	# --- 按键映射 ---
	var arrow: Node = get_node_or_null(P_ARROW_KEY)
	cfg["arrow_key"] = arrow.get_item_text(arrow.selected) if arrow is OptionButton else "移动"
	cfg["trigger_key"] = _get_option_text(P_TRIGGER)
	cfg["trigger_speed"] = _get_line_text(P_TRIGGER_SPEED).strip_edges()
	cfg["trigger_time"] = _get_line_text(P_TRIGGER_TIME).strip_edges()
	cfg["booster_key"] = _get_option_text(P_BOOSTER_KEY)
	return cfg


## 获取 OptionButton 当前选中的文本
func _get_option_text(path: NodePath) -> String:
	var btn: Node = get_node_or_null(path)
	if btn is OptionButton:
		return btn.get_item_text(btn.selected)
	return ""


## 获取 OptionButton 当前选中的索引
func _get_option_idx(path: NodePath) -> int:
	var btn: Node = get_node_or_null(path)
	if btn is OptionButton:
		return btn.selected
	return -1


## 从 IO 对字符串中提取通信脚（前半），如 "P77 P27" -> "P77"
func _parse_io_pair(text: String) -> String:
	var parts: PackedStringArray = text.split(" ")
	if parts.size() > 0:
		return parts[0]
	return text


## IO 引脚名映射到拓展板槽位序号
## P60->0(拨弹), P62->1(空), P64->2(摩擦L), P66->3(摩擦R),
## P74->4(LF), P75->5(LR), P76->6(RF), P77->7(RR)
func _io_to_exp_slot(pin: String) -> int:
	var mapping: Dictionary = {
		"P60": 0, "P62": 1, "P64": 2, "P66": 3,
		"P74": 4, "P75": 5, "P76": 6, "P77": 7,
	}
	return mapping.get(pin, -1)


## 按键名称映射到 C 代码中的 KEY_OFFSET 宏名
func _key_name_to_offset(name: String) -> String:
	var mapping: Dictionary = {
		"R": "KEY_OFFSET_1",
		"↑": "KEY_OFFSET_UP",
		"↓": "KEY_OFFSET_DOWN",
		"←": "KEY_OFFSET_LEFT",
		"->": "KEY_OFFSET_RIGHT",
		"A": "KEY_OFFSET_A",
		"B": "KEY_OFFSET_B",
		"C": "KEY_OFFSET_C",
		"D": "KEY_OFFSET_D",
	}
	return mapping.get(name, "KEY_OFFSET_1")


## 方向文本映射到 C 代码中的整数值（Dir_Change_Order: 1=正, 0=负）
func _dir_to_int(text: String) -> int:
	if text == "正向":
		return 1
	return 0


# ------------------------------------------------------------------ 代码生成
## 基于配置字典生成完整的 main.c 代码字符串
func _generate_main_c(cfg: Dictionary) -> String:
	# --- 解析参数（带默认值）---
	var ch: String = cfg.get("channel", "36")
	if ch.is_empty():
		ch = "36"
	var dz: String = cfg.get("deadzone", "10")
	if dz.is_empty():
		dz = "10"
	var normal_spd: String = cfg.get("normal_speed", "4000")
	if normal_spd.is_empty():
		normal_spd = "4000"
	var sprint_spd: String = cfg.get("sprint_speed", "8000")
	if sprint_spd.is_empty():
		sprint_spd = "8000"
	var trig_spd: String = cfg.get("trigger_speed", "10000")
	if trig_spd.is_empty():
		trig_spd = "10000"
	var trig_time: String = cfg.get("trigger_time", "250")
	if trig_time.is_empty():
		trig_time = "250"

	# --- 按键映射 ---
	var trigger_key_offset: String = _key_name_to_offset(cfg.get("trigger_key", "R"))
	var booster_key_offset: String = _key_name_to_offset(cfg.get("booster_key", "A"))

	# --- IO 槽位映射 ---
	# 将功能角色映射到拓展板槽位（0-7 对应 p60,p62,p64,p66,p74,p75,p76,p77）
	var feeder_pin: String = _parse_io_pair(cfg.get("booster_io", "P60 P61"))
	var l1_pin: String = _parse_io_pair(cfg.get("l1_io", "P74 P24"))
	var l2_pin: String = _parse_io_pair(cfg.get("l2_io", "P75 P25"))
	var r1_pin: String = _parse_io_pair(cfg.get("r1_io", "P76 P26"))
	var r2_pin: String = _parse_io_pair(cfg.get("r2_io", "P77 P27"))
	# 摩擦轮固定 P64/P66
	var friction_l_pin: String = "P64"
	var friction_r_pin: String = "P66"

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
	var fric_l_dir: int = _dir_to_int(cfg.get("friction_l_dir", "正向"))
	var fric_r_dir: int = _dir_to_int(cfg.get("friction_r_dir", "正向"))

	# --- Yaw/Pitch 驱动类型 ---
	var yaw_is_servo: bool = cfg.get("yaw_drive", "舵机") == "舵机"
	var pitch_is_servo: bool = cfg.get("pitch_drive", "舵机") == "舵机"
	var yaw_pin: String = _parse_io_pair(cfg.get("yaw_io", "MP74"))
	var pitch_pin: String = _parse_io_pair(cfg.get("pitch_io", "MP03"))
	# 扩展板槽位（-1 表示不在扩展板上，即主控板 PWM 引脚）
	var yaw_slot: int = _io_to_exp_slot(yaw_pin)
	var pitch_slot: int = _io_to_exp_slot(pitch_pin)
	# 舵机在主控板 PWM 引脚上（需要 PWM_Init），还是在扩展板上（走 ExpansionBoradControl）
	var yaw_servo_on_main: bool = yaw_is_servo and yaw_slot < 0
	var pitch_servo_on_main: bool = pitch_is_servo and pitch_slot < 0

	# --- 构建 Init_Order 参数（8 个槽位）---
	# P60=拨弹电机(10000), P62=空(50), P64/P66=摩擦轮(50), P74-P77=底盘电机(10000)
	var init_vals: Array = [10000, 50, 50, 50, 10000, 10000, 10000, 10000]
	if feeder_slot >= 0:
		init_vals[feeder_slot] = 10000 # 拨弹电机
	# p64/p66 固定摩擦轮（50），底盘电机槽位（10000）已为默认
	# 如果用户把底盘 IO 选到了 p64/p66 之外的槽位，需要覆盖
	if l1_slot >= 0:
		init_vals[l1_slot] = 10000
	if l2_slot >= 0:
		init_vals[l2_slot] = 10000
	if r1_slot >= 0:
		init_vals[r1_slot] = 10000
	if r2_slot >= 0:
		init_vals[r2_slot] = 10000
	# Yaw/Pitch 在扩展板上时需要初始化：电机=10000，舵机=50
	if yaw_slot >= 0:
		init_vals[yaw_slot] = 50 if yaw_is_servo else 10000
	if pitch_slot >= 0:
		init_vals[pitch_slot] = 50 if pitch_is_servo else 10000

	# --- 构建 Dir_Change_Order 参数 ---
	# 每个槽位的方向表达式（字符串）
	# 底盘/云台电机用 Get_Dir() 动态判断方向，拨弹/摩擦轮用固定值
	var dir_exprs: Array = ["1", "1", "1", "1", "1", "1", "1", "1"]
	# 拨弹电机
	if feeder_slot >= 0:
		dir_exprs[feeder_slot] = str(booster_dir)
	# 摩擦轮
	dir_exprs[2] = str(fric_l_dir)
	dir_exprs[3] = str(fric_r_dir)
	# 底盘/Yaw/Pitch 电机槽位 -> dutyOfMotor 索引映射
	var yaw_motor_idx: int = 5
	var pitch_motor_idx: int = 6 if not yaw_is_servo else 5
	var slot_motor_map: Dictionary = {}
	if l1_slot >= 0:
		slot_motor_map[l1_slot] = 0
	if l2_slot >= 0:
		slot_motor_map[l2_slot] = 1
	if r1_slot >= 0:
		slot_motor_map[r1_slot] = 2
	if r2_slot >= 0:
		slot_motor_map[r2_slot] = 3
	if not yaw_is_servo and yaw_slot >= 0:
		slot_motor_map[yaw_slot] = yaw_motor_idx
	if not pitch_is_servo and pitch_slot >= 0:
		slot_motor_map[pitch_slot] = pitch_motor_idx
	# 生成方向表达式
	for s in range(4, 8):
		if slot_motor_map.has(s):
			dir_exprs[s] = "Get_Dir(dutyOfMotor[%d])" % slot_motor_map[s]

	# --- 构建 Duty_Change_Order 参数 ---
	# P60=拨弹电机(dutyOfMotor[4]), P62=空(10000), P64/P66=摩擦轮(dutyOfBooster), P74-P77=底盘电机
	var duty_vals: Array = ["dutyOfMotor[4]", "10000", "dutyOfBooster", "dutyOfBooster",
		"(uint16_t)abs(dutyOfMotor[0])", "(uint16_t)abs(dutyOfMotor[1])",
		"(uint16_t)abs(dutyOfMotor[2])", "(uint16_t)abs(dutyOfMotor[3])"]
	# 拨弹电机 -> dutyOfMotor[4]
	if feeder_slot >= 0:
		duty_vals[feeder_slot] = "dutyOfMotor[4]"
	# 底盘电机按 L1/L2/R1/R2 映射到 dutyOfMotor[0..3]
	# 蓝本中: dutyOfMotor[0]=L1, [1]=L2, [2]=R1, [3]=R2
	if l1_slot >= 0:
		duty_vals[l1_slot] = "(uint16_t)abs(dutyOfMotor[0])"
	if l2_slot >= 0:
		duty_vals[l2_slot] = "(uint16_t)abs(dutyOfMotor[1])"
	if r1_slot >= 0:
		duty_vals[r1_slot] = "(uint16_t)abs(dutyOfMotor[2])"
	if r2_slot >= 0:
		duty_vals[r2_slot] = "(uint16_t)abs(dutyOfMotor[3])"
	# Yaw: 电机模式 -> abs(dutyOfMotor)，舵机模式(扩展板) -> dutyOfServo[0]
	if yaw_slot >= 0:
		if yaw_is_servo:
			duty_vals[yaw_slot] = "dutyOfServo[0]"
		else:
			duty_vals[yaw_slot] = "(uint16_t)abs(dutyOfMotor[%d])" % yaw_motor_idx
	# Pitch: 同理
	if pitch_slot >= 0:
		if pitch_is_servo:
			duty_vals[pitch_slot] = "dutyOfServo[1]"
		else:
			duty_vals[pitch_slot] = "(uint16_t)abs(dutyOfMotor[%d])" % pitch_motor_idx

	# --- 底盘电机公式（反向时取反）---
	var l1_formula: String = "-baseSpeed - turnSpeed" if l1_dir == 1 else "baseSpeed + turnSpeed"
	var l2_formula: String = "-baseSpeed - turnSpeed" if l2_dir == 1 else "baseSpeed + turnSpeed"
	var r1_formula: String = "baseSpeed - turnSpeed" if r1_dir == 1 else "-baseSpeed + turnSpeed"
	var r2_formula: String = "baseSpeed - turnSpeed" if r2_dir == 1 else "-baseSpeed + turnSpeed"

	# --- 冲刺/移动速度逻辑 ---
	var arrow_key: String = cfg.get("arrow_key", "移动")
	var sprint_enabled: bool = cfg.get("sprint_enabled", false)
	# sprint_check: 生成 baseSpeed/turnSpeed 的初始赋值代码块
	var sprint_check: String = ""
	if sprint_enabled:
		sprint_check = "\n    // 冲刺模式：按下左摇杆时使用冲刺速度\n    if (valueOfKey[2][0])\n    {\n        baseSpeed = (int)((float)valueOfRoker[0][1] * ultraSpeed / 2047);\n        turnSpeed = -(int)((float)valueOfRoker[0][0] * ultraSpeed / 2047);\n    }\n    else\n    {\n        baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n        turnSpeed = -(int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n    }\n"
	else:
		sprint_check = "\n    // 冲刺模式不可用（未勾选），使用普通速度\n    baseSpeed = (int)((float)valueOfRoker[0][1] * maxSpeed / 2047);\n    turnSpeed = -(int)((float)valueOfRoker[0][0] * maxSpeed / 2047);\n"
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
	code += "uint16_t midDutyOfServo[2] = {750, 750};        // 分别为云台水平舵机、云台垂直舵机\n"
	code += "uint16_t maxChangeDutyOfServo[2] = {200, 200};  // 同上\n"
	code += "uint16_t singleChangeDutyOfServo[2] = {10, 10}; // 按下按键单次占空比改变量\n"
	code += "uint16_t singleChangeDutyOfBooster = 100;       // 按下按键单次占空比改变量\n"
	code += "uint16_t maxDutyOfBooster = 1100;               // 摩擦轮最大占空比\n"
	code += "uint16_t boosterDutyOfFeed = %s;             // 拨弹电机单发转动占空比\n" % trig_spd
	code += "uint16_t boosterFeedDelayMs = %s;              // 拨弹电机单发转动时长(ms)\n" % trig_time
	code += "float changeRateOfServo[2] = {0.01, 0.01};\n\n"
	code += "#define LIMIT_VALUE(x, min, max) \\\n    do                           \\\n    {                            \\\n        if ((x) < (min))         \\\n            (x) = (min);         \\\n        else if ((x) > (max))    \\\n            (x) = (max);         \\\n    } while (0)\n"
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
	code += "float floatDutyOfServo[2]; // 云台舵机\n"
	code += "uint16_t dutyOfServo[2];\n"
	var motor_array_size: int = 5 # 4底盘 + 1供弹
	if not yaw_is_servo:
		motor_array_size = pitch_motor_idx + 1 # 6 (仅yaw) 或 7 (yaw+pitch)
	code += "int dutyOfMotor[%d]; // 底盘电机、供弹电机、云台电机（如有）\n" % motor_array_size
	code += "uint16_t dutyOfBooster = 0, expectDutyOfBooster = 0;\n"
	code += "uint8_t valueOfKey[3][4];\n"
	code += "uint8_t triggerKeyValue, lastTriggerKeyValue, boosterKeyValue, lastBoosterKeyValue;\n"
	code += "uint8_t statusOfBooster = 0;\n"
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
	code += "uint8_t Get_Dir(int rawdata);\n"
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster);\n"
	code += "void ExpansionBoradControl(uint8_t control_cmd, uint16_t data_p60, uint16_t data_p62, uint16_t data_p64,\n"
	code += "                           uint16_t data_p66, uint16_t data_p74, uint16_t data_p75, uint16_t data_p76,\n"
	code += "                           uint16_t data_p77);\n\n"

	# --- main() ---
	code += "void main()\n{\n"
	code += "    All_Init();\n"
	if yaw_is_servo:
		code += "    floatDutyOfServo[0] = midDutyOfServo[0];\n"
	if pitch_is_servo:
		code += "    floatDutyOfServo[1] = midDutyOfServo[1];\n"
	code += "    while (1)\n"
	code += "    {\n"
	code += "        // 测试手柄连接状态\n"
	code += "        if (RcKeyValueRead(KEY_OFFSET_UP))\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 0);\n"
	code += "        else\n"
	code += "            GPIO_Write_Bit(GPIO_P3, GPIO_Pin_7, 1);\n\n"
	code += "        ReadControllerInputs();    // 统一读取输入\n"
	code += "        CalculateMotorControls();  // 计算电机控制\n"
	code += "        CalculateGimbalControls(); // 计算云台控制\n"
	code += "        CalculateBoosterControl(); // 计算摩擦轮控制\n"
	code += "        LIMIT_VALUE(dutyOfMotor[0], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[1], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[2], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[3], -10000, 10000);\n"
	code += "        LIMIT_VALUE(dutyOfMotor[4], 0, 10000);\n"
	if not yaw_is_servo:
		code += "        LIMIT_VALUE(dutyOfMotor[5], -10000, 10000);\n"
	if not pitch_is_servo:
		var pitch_idx: int = 6 if not yaw_is_servo else 5
		code += "        LIMIT_VALUE(dutyOfMotor[%d], -10000, 10000);\n" % pitch_idx
	if yaw_is_servo:
		code += "        LIMIT_VALUE(floatDutyOfServo[0], 250, 1250);\n"
	if pitch_is_servo:
		code += "        LIMIT_VALUE(floatDutyOfServo[1], 250, 1250);\n"
	# 单发拨弹：使用 triggerKeyValue 替代 valueOfRKey
	code += "        // 扳机键单发拨弹：上升沿触发，拨弹电机转动 boosterFeedDelayMs 后停转，期间阻塞主线程\n"
	code += "        if (triggerKeyValue && !lastTriggerKeyValue)\n"
	code += "        {\n"
	code += "            dutyOfMotor[4] = boosterDutyOfFeed;\n"
	code += "            dutyOfBooster = expectDutyOfBooster; // 锁定摩擦轮当前值，平滑过程暂停\n"
	code += "            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);\n"
	code += "            Ms_Delay(boosterFeedDelayMs);\n"
	code += "            dutyOfMotor[4] = 0;\n"
	code += "            Main_Countrol(dutyOfMotor, dutyOfServo, dutyOfBooster);\n"
	code += "        }\n"
	code += "        lastTriggerKeyValue = triggerKeyValue;\n\n"
	code += "        // 平滑占空比变化\n"
	code += "        if (expectDutyOfBooster > 500 && dutyOfBooster < 500)\n"
	code += "            dutyOfBooster = 500;\n\n"
	code += "        if (dutyOfBooster + 2 <= expectDutyOfBooster)\n"
	code += "            dutyOfBooster += 2;\n"
	code += "        else if (dutyOfBooster < expectDutyOfBooster)\n"
	code += "            dutyOfBooster++;\n"
	code += "        else if (dutyOfBooster - 2 >= expectDutyOfBooster)\n"
	code += "            dutyOfBooster -= 2;\n"
	code += "        else if (dutyOfBooster > expectDutyOfBooster)\n"
	code += "            dutyOfBooster--;\n"
	code += "        else\n"
	code += "            dutyOfBooster = expectDutyOfBooster;\n\n"
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
	code += "    Board_Init();\n"
	code += "    GPIO_Init(GPIO_P3, GPIO_Pin_4, GPIO_OUT_PP);\n"
	code += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 0);\n"
	code += "    remote_control_init();\n"
	code += "    GPIO_Write_Bit(GPIO_P3, GPIO_Pin_4, 1);\n"
	code += "    UART_Init(UART_1, UART1_RX_P30, UART1_TX_P31, 230400, TIM1);\n"
	code += "    ExpansionBoradControl(Init_Order,\n"
	code += "                          %s); // p60,p62,p64,p66,p74,p75,p76,p77\n" % init_str
	code += "    Ms_Delay(20);\n"
	code += pwm_init_lines
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
	code += "    // 摩擦轮占空比计算\n"
	code += "    if (valueOfKey[1][1])\n"
	code += "        expectDutyOfBooster += singleChangeDutyOfBooster;\n"
	code += "    else if (valueOfKey[1][2])\n"
	code += "        expectDutyOfBooster -= singleChangeDutyOfBooster;\n\n"
	code += "    // 摩擦轮开关由 %s 上升沿翻转\n" % cfg.get("booster_key", "A")
	code += "    if (boosterKeyValue && !lastBoosterKeyValue)\n"
	code += "    {                                       // 检测上升沿\n"
	code += "        statusOfBooster = !statusOfBooster; // 翻转状态\n"
	code += "    }\n"
	code += "    lastBoosterKeyValue = boosterKeyValue;\n\n"
	code += "    if (statusOfBooster)\n"
	code += "        expectDutyOfBooster = maxDutyOfBooster;\n"
	code += "    else\n"
	code += "        expectDutyOfBooster = 0;\n"
	code += "}\n\n"

	# --- CalculateGimbalControls ---
	code += "void CalculateGimbalControls()\n{\n"
	if yaw_is_servo or pitch_is_servo:
		code += "    // 云台舵机控制值计算\n"
		if yaw_is_servo:
			code += "    floatDutyOfServo[0] += valueOfRoker[1][0] * changeRateOfServo[0];\n"
		if pitch_is_servo:
			code += "    floatDutyOfServo[1] += valueOfRoker[1][1] * changeRateOfServo[1];\n"
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

	# --- Main_Countrol ---
	code += "void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo, uint16_t dutyOfBooster)\n{\n"
	code += "    ExpansionBoradControl(Dir_Change_Order,\n"
	code += "                          %s);\n" % dir_str
	code += "    Ms_Delay(5);\n"
	code += "    ExpansionBoradControl(Duty_Change_Order, %s);\n" % duty_str
	code += "    Ms_Delay(5);\n"
	code += pwm_set_lines
	code += "}\n\n"

	# --- ExpansionBoradControl ---
	code += "/// @brief 板间通信函数，用于主控给拓展版发送\n"
	code += "/// @param control_cmd\n"
	code += "/// @param data_p60 供弹电机\n"
	code += "/// @param data_p62 空\n"
	code += "/// @param data_p64 摩擦轮L\n"
	code += "/// @param data_p66 摩擦轮R\n"
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
	code += "        UART_PutChar(UART_1, control_frame_pack[i]);\n"
	code += "}\n"

	return code


## IO 引脚名映射到 PWM 通道枚举
## MP74 / MP03 是主控板舵机端口，与扩展板 P74 不同
func _pin_to_pwm_channel(pin: String) -> String:
	var mapping: Dictionary = {
		"MP74": "PWMB_CH1_P74",
		"MP03": "PWMB_CH4_P03",
		"P24": "PWMA_CH3P_P24",
		"P25": "PWMA_CH3N_P25",
		"P26": "PWMA_CH4P_P26",
		"P27": "PWMA_CH4N_P27",
		"P74": "PWMB_CH1_P74",
		"P75": "PWMB_CH2_P75",
		"P76": "PWMB_CH3_P76",
		"P77": "PWMB_CH4_P77",
		"P03": "PWMB_CH4_P03",
		"P20": "PWMB_CH1_P20",
		"P21": "PWMB_CH2_P21",
		"P22": "PWMB_CH3_P22",
		"P23": "PWMB_CH4_P23",
		"P00": "PWMB_CH1_P00",
		"P01": "PWMB_CH2_P01",
		"P02": "PWMB_CH3_P02",
		"P17": "PWMB_CH1_P17",
		"P33": "PWMB_CH3_P33",
		"P34": "PWMB_CH4_P34",
		"P54": "PWMB_CH2_P54",
	}
	var ch: String = mapping.get(pin, "")
	if ch.is_empty():
		push_warning("_pin_to_pwm_channel: 未知引脚 %s，请确认是主控板舵机端口 MP74 或 MP03" % pin)
		return "PWMB_CH1_P74" # 兜底，实际应被静态检查拦截
	return ch


# ==================================================================
# 编译功能（Keil C251 集成）
# ==================================================================
## 退出时清理编译线程，避免泄漏
func _exit_tree() -> void:
	if _build_thread and _build_thread.is_alive():
		_build_thread.wait_to_finish()


## res:// 或 user:// 路径转 OS 绝对路径（供 OS.execute / FileAccess 使用）
func _to_abs(virt_path: String) -> String:
	return ProjectSettings.globalize_path(virt_path)


## 确保工具链和项目模板已从 res://（PCK 只读）解压到 user://（可写）。
## 首次运行或版本变更时执行全量复制；通过版本标记文件判断是否需要重新解压。
## 返回 true 表示就绪，false 表示失败（错误信息已 append）。
func _ensure_deployed() -> bool:
	var ver_file: String = _to_abs("user://keil/.pie_block_version")
	var need_extract: bool = true
	if FileAccess.file_exists(ver_file):
		var cur_ver: String = FileAccess.get_file_as_string(ver_file).strip_edges()
		if cur_ver == TOOLCHAIN_VERSION:
			# 工具链已解压且版本一致，检查关键文件是否还在
			if FileAccess.file_exists(_to_abs(TOOLCHAIN_DST).path_join("UV4/uVision.com")):
				need_extract = false
	if need_extract:
		if not _extract_toolchain():
			return false
	# 项目模板始终确保存在（体积小，不做版本检查）
	if not DirAccess.dir_exists_absolute(_to_abs(PROJECT_DST)):
		if not _copy_dir_recursive(PROJECT_SRC, PROJECT_DST):
			_append_output("[Error] 无法复制项目模板到 user://，请检查磁盘空间")
			return false
	# 库文件也需复制（uvproj 用相对路径引用 Libraries）
	if not DirAccess.dir_exists_absolute(_to_abs(LIBRARIES_DST)):
		if not _copy_dir_recursive(LIBRARIES_SRC, LIBRARIES_DST):
			_append_output("[Error] 无法复制库文件到 user://，请检查磁盘空间")
			return false
	return true


## 从 res://stc32g/toolchain/Keil_noarm 递归复制到 user://keil/
func _extract_toolchain() -> bool:
	_append_output("首次运行：正在解压 Keil 工具链到 user://（约 68MB，请稍候）…")
	var src_abs: String = _to_abs(TOOLCHAIN_SRC)
	var dst_abs: String = _to_abs(TOOLCHAIN_DST)
	if not DirAccess.dir_exists_absolute(src_abs):
		_append_output("[Error] 工具链源目录不存在: %s" % src_abs)
		return false
	# 清理旧目录
	if DirAccess.dir_exists_absolute(dst_abs):
		_remove_dir_recursive(TOOLCHAIN_DST)
	if not _copy_dir_recursive(TOOLCHAIN_SRC, TOOLCHAIN_DST):
		_append_output("[Error] 工具链解压失败")
		return false
	# 写入版本标记
	var vf: FileAccess = FileAccess.open("user://keil/.pie_block_version", FileAccess.WRITE)
	if vf:
		vf.store_string(TOOLCHAIN_VERSION)
		vf.close()
	_append_output("工具链解压完成")
	return true


## 递归复制目录（res:// -> user:// 或任意路径组合）
func _copy_dir_recursive(src_path: String, dst_path: String) -> bool:
	var src_abs: String = _to_abs(src_path)
	var dst_abs: String = _to_abs(dst_path)
	if not DirAccess.dir_exists_absolute(dst_abs):
		var err: int = DirAccess.make_dir_recursive_absolute(dst_abs)
		if err != OK:
			push_error("无法创建目录 %s（错误码 %d）" % [dst_abs, err])
			return false
	var da: DirAccess = DirAccess.open(src_abs)
	if da == null:
		push_error("无法打开源目录: %s" % src_abs)
		return false
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var src_item: String = src_path.path_join(name)
		var dst_item: String = dst_path.path_join(name)
		if da.current_is_dir():
			if not _copy_dir_recursive(src_item, dst_item):
				da.list_dir_end()
				return false
		else:
			if not _copy_file(src_item, dst_item):
				da.list_dir_end()
				return false
		name = da.get_next()
	da.list_dir_end()
	return true


## 递归删除目录（user:// 路径）
func _remove_dir_recursive(dir_path: String) -> void:
	var abs_path: String = _to_abs(dir_path)
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var name: String = da.get_next()
	while name != "":
		if name.begins_with("."):
			name = da.get_next()
			continue
		var item_path: String = dir_path.path_join(name)
		if da.current_is_dir():
			_remove_dir_recursive(item_path)
		else:
			var item_da: DirAccess = DirAccess.open(_to_abs(dir_path))
			if item_da:
				item_da.remove(name)
		name = da.get_next()
	da.list_dir_end()
	# 删除空目录本身：打开父目录，用 remove 删本目录名
	var parent_path: String = dir_path.get_base_dir()
	var dir_name: String = dir_path.get_file()
	var parent_da: DirAccess = DirAccess.open(_to_abs(parent_path))
	if parent_da:
		parent_da.remove(dir_name)


## 复制单个文件
func _copy_file(src_path: String, dst_path: String) -> bool:
	var src_abs: String = _to_abs(src_path)
	var dst_abs: String = _to_abs(dst_path)
	var src_f: FileAccess = FileAccess.open(src_abs, FileAccess.READ)
	if src_f == null:
		push_error("无法读取: %s" % src_abs)
		return false
	var dst_f: FileAccess = FileAccess.open(dst_abs, FileAccess.WRITE)
	if dst_f == null:
		push_error("无法写入: %s" % dst_abs)
		src_f.close()
		return false
	var buf_size: int = 65536
	while src_f.get_position() < src_f.get_length():
		dst_f.store_buffer(src_f.get_buffer(buf_size))
	src_f.close()
	dst_f.close()
	return true


## 在 user://keil/ 中探测 Keil 命令行编译器；找不到返回空串
## 优先 uVision.com（控制台子系统，-b 不弹 GUI 窗口），回退 UV4.exe（GUI 子系统，会弹窗）
func _find_uv4() -> String:
	var dir_abs: String = _to_abs(TOOLCHAIN_DST)
	# UV4 子目录是标准布局
	var uv4_dir: String = dir_abs.path_join("UV4")
	for cand in UV4_CANDIDATES:
		var candidate: String = uv4_dir.path_join(cand)
		if FileAccess.file_exists(candidate):
			return candidate
	# 回退：深度优先递归扫描
	return _find_uv4_recursive(dir_abs)


func _find_uv4_recursive(dir_abs: String) -> String:
	var da: DirAccess = DirAccess.open(dir_abs)
	if da == null:
		return ""
	da.list_dir_begin()
	var name: String = da.get_next()
	var found: String = ""
	while name != "" and found == "":
		if da.current_is_dir() and not name.begins_with("."):
			var sub_dir: String = dir_abs.path_join(name)
			for cand in UV4_CANDIDATES:
				var candidate: String = sub_dir.path_join(cand)
				if FileAccess.file_exists(candidate):
					found = candidate
					break
			if found == "":
				found = _find_uv4_recursive(sub_dir)
		name = da.get_next()
	da.list_dir_end()
	return found


## 动态生成 TOOLS.INI：PATH 用绝对路径指向 user://keil/C251/
## TOOLS.INI 必须与 uVision.com 同级或在其上级目录（UV4/ 的上级 = keil/）
## 注意：Keil C251 的 PATH 必须使用反斜杠（\\），正斜杠会导致
## "failed to execute C251.EXE" 错误。末尾必须以单个反斜杠结尾。
func _generate_tools_ini() -> bool:
	var keil_abs: String = _to_abs(TOOLCHAIN_DST).replace("/", "\\")
	var c251_path: String = keil_abs + "\\C251\\"
	var ini_abs: String = keil_abs + "\\TOOLS.INI"
	# 读取原始 TOOLS.INI 模板（res:// 中的），替换 PATH 行
	var template_path: String = TOOLCHAIN_SRC.path_join("TOOLS.INI")
	var template_abs: String = _to_abs(template_path)
	var content: String = ""
	if FileAccess.file_exists(template_abs):
		content = FileAccess.get_file_as_string(template_abs)
	else:
		# 无模板则用最小配置
		content = "[C251]\nPATH=\"\"\nVERSION=5.60\n"
	# 替换 [C251] 段的 PATH 为绝对路径
	# 注意：源文件可能是 CRLF 换行，split("\n") 后行末残留 \r，
	# 因此 strip_edges 必须同时去掉首尾空白（left=true, right=true）
	var lines: PackedStringArray = content.split("\n", false)
	var in_c251: bool = false
	var output_lines: PackedStringArray = PackedStringArray()
	for line in lines:
		var stripped: String = line.strip_edges(true, true)
		if stripped.to_upper() == "[C251]":
			in_c251 = true
		elif stripped.begins_with("[") and stripped.ends_with("]") and in_c251:
			in_c251 = false
		if in_c251 and stripped.to_upper().begins_with("PATH="):
			output_lines.append('PATH="%s"' % c251_path)
		else:
			output_lines.append(line)
	var f: FileAccess = FileAccess.open(ini_abs, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 TOOLS.INI: %s" % ini_abs)
		return false
	f.store_string("\n".join(output_lines) + "\n")
	f.close()
	return true


## 把最新生成的 main.c 写入 user://projects/infantry/USER/src/main.c
func _write_main_c_to_disk(code: String) -> bool:
	var main_c_path: String = PROJECT_DST.path_join("USER/src/main.c")
	var abs_path: String = _to_abs(main_c_path)
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 main.c: %s（%s）" % [abs_path, FileAccess.get_open_error()])
		return false
	f.store_string(code)
	f.close()
	return true


## 编译按钮回调：解压工具链 -> 写盘 -> 生成 TOOLS.INI -> 异步编译
func _on_build_pressed() -> void:
	if _build_busy:
		return # 防重入
	# 0) 确保工具链和项目模板已解压到 user://
	_clear_output()
	if not _ensure_deployed():
		_append_output("[Error] 工具链初始化失败，无法编译")
		return
	# 1) 取 CodeEdit 中最新生成的 main.c（即 _generate_main_c 产物）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = ""
	if code_edit is CodeEdit:
		code = code_edit.text
	if code.strip_edges().is_empty():
		_run_check()
		if code_edit is CodeEdit:
			code = code_edit.text
		if code.strip_edges().is_empty():
			_append_output("[Error] 没有可编译的代码，请先完成配置")
			return
	# 2) 写入磁盘（user://projects/infantry/USER/src/main.c）
	if not _write_main_c_to_disk(code):
		_append_output("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
		return
	# 3) 探测编译器
	var uv4_abs: String = _find_uv4()
	if uv4_abs.is_empty():
		_append_output("[Error] 未在 user://keil/ 找到 uVision.com / UV4.exe")
		_append_output("       请尝试删除 user://keil/ 后重新编译（触发重新解压）")
		return
	# 3.1) 生成 TOOLS.INI（动态写入绝对路径）
	if not _generate_tools_ini():
		_append_output("[Warn] TOOLS.INI 生成失败，编译可能报错")
	# 4) 启动异步编译
	_build_busy = true
	var btn: Node = get_node_or_null(P_BUILD_BTN)
	if btn is BaseButton:
		btn.disabled = true
		btn.text = "编译中…"
	_append_output("正在编译…（已写入 main.c，调用 Keil 编译器）")
	_build_thread = Thread.new()
	var err: int = _build_thread.start(_build_worker.bind(uv4_abs))
	if err != OK:
		_build_busy = false
		if btn is BaseButton:
			btn.disabled = false
			btn.text = "编译"
		_append_output("[Error] 无法启动编译线程（错误码 %d）" % err)


## 编译工作线程：执行 Keil 编译器 -b，读日志，完成后回主线程
## 注意：子线程禁止访问 UI 节点，结果通过 call_deferred 传递
func _build_worker(uv4_abs: String) -> void:
	# 项目模板已在 user://projects/infantry/，可写 main.c 和日志
	var mdk_abs: String = _to_abs(PROJECT_DST).path_join("MDK").replace("/", "\\")
	var uvproj_abs: String = mdk_abs + "\\Project_Template.uvproj"
	var log_abs: String = mdk_abs + "\\" + BUILD_LOG_NAME
	var uv4_win: String = uv4_abs.replace("/", "\\")
	var output: Array = []
	var exit_code: int = OS.execute(uv4_win, ["-b", uvproj_abs, "-o", log_abs], output, true)
	# 读取编译日志
	var log_text: String = ""
	if FileAccess.file_exists(log_abs):
		log_text = FileAccess.get_file_as_string(log_abs)
	var result: Dictionary = {
		"exit": exit_code,
		"log": log_text,
	}
	call_deferred("_on_build_finished", result)


## 编译完成回调（主线程）：复位按钮，解析日志，展示结果
func _on_build_finished(result: Dictionary) -> void:
	_build_busy = false
	# 清理线程
	if _build_thread and _build_thread.is_alive():
		_build_thread.wait_to_finish()
	_build_thread = null
	# 复位按钮
	var btn: Node = get_node_or_null(P_BUILD_BTN)
	if btn is BaseButton:
		btn.disabled = false
		btn.text = "编译"
	# 解析结果
	var log_text: String = result.get("log", "")
	var exit_code: int = int(result.get("exit", -1))
	_clear_output()
	# 成功判据：日志非空且包含 "0 Error(s)"（UV4 批处理退出码不可靠，以日志为准）
	var ok: bool = (not log_text.is_empty()) and log_text.find("0 Error(s)") >= 0
	if ok:
		_append_output("✓ 编译成功")
	else:
		# exit_code 可能是 0（UV4 批处理常不返回标准码），故仅作参考
		_append_output("✗ 编译失败（UV4 退出码 %d，请查看下方日志）" % exit_code)
	_append_output("")
	if log_text.is_empty():
		_append_output("[Warn] 未读取到编译日志（pie_block_build.log），请检查 UV4 是否正常执行")
	else:
		# 逐行追加，IssueHighlighter 会自动给 Error/Warning 行着色
		for line in log_text.split("\n", false):
			_append_output(line)


## 向 Output 框追加一行（复用 output.gd 的 append_line）
func _append_output(line_text: String) -> void:
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("append_line"):
		out.append_line(line_text)


## 清空 Output 框
func _clear_output() -> void:
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("clear_output"):
		out.clear_output()

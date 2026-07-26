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
const P_YAW_MID_OFFSET: NodePath = GIMBAL + "/Yaw/LineEdit"
const P_PITCH_MID_OFFSET: NodePath = GIMBAL + "/Pitch/LineEdit"
# 按键映射
const KEYSET: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Infantry/KeySetting"
const P_SPRINT_CB: NodePath = KEYSET + "/Sprint/CheckBox"
const P_ZERO_CB: NodePath = KEYSET + "/Zero/CheckBox"
const P_ARROW_KEY: NodePath = KEYSET + "/ArrowKey/CheckBox"
const P_TRIGGER: NodePath = KEYSET + "/Trigger/OptionButton"
const P_TRIGGER_SPEED: NodePath = KEYSET + "/Trigger/Speed"
const P_TRIGGER_TIME: NodePath = KEYSET + "/Trigger/Time"
const P_BOOSTER_KEY: NodePath = KEYSET + "/Booster/OptionButton"
# 调试界面
const DEBUG: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Debug"
# 调试界面各行容器名（P60, P62, P64, P66, P74, P75, P76, P77, MP03, MP74）
const DEBUG_ROWS: Array = [
	"HBoxContainer", "HBoxContainer2", "HBoxContainer3", "HBoxContainer4", "HBoxContainer5",
	"HBoxContainer6", "HBoxContainer7", "HBoxContainer8", "HBoxContainer9", "HBoxContainer10",
]
# 工程师界面
const ENGINEER: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/Engineer"
# IO 初始化区（OptionButton 选 电机/舵机，P60/P62 固定舵机只有1项）
const P_ENG_P60: NodePath = ENGINEER + "/P60P62/OptionButton"
const P_ENG_P62: NodePath = ENGINEER + "/P60P62/OptionButton2"
const P_ENG_P64: NodePath = ENGINEER + "/P64P66/OptionButton"
const P_ENG_P66: NodePath = ENGINEER + "/P64P66/OptionButton2"
const P_ENG_P74: NodePath = ENGINEER + "/P74P75/OptionButton"
const P_ENG_P75: NodePath = ENGINEER + "/P74P75/OptionButton2"
const P_ENG_P76: NodePath = ENGINEER + "/P76P77/OptionButton2"
const P_ENG_P77: NodePath = ENGINEER + "/P76P77/OptionButton"
# 按键映射区各行容器名
const ENG_KEY_ROWS: Array = [
	"RightJoystickX", "RightJoystickY", "A", "B", "C", "D", "Up", "Down", "Left", "Right", "R",
]
# 按键映射区各行的显示名（与 ENG_KEY_ROWS 一一对应）
const ENG_KEY_LABELS: Array = [
	"右摇杆X", "右摇杆Y", "A", "B", "C", "D", "↑", "↓", "←", "->", "R",
]
# 工程逆解算界面（Tab 2）
const IK: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/EngineerAdvanced"
const P_IK_CONFIG_TYPE: NodePath = IK + "/ConfigType/OptionButton"
const P_IK_L1: NodePath = IK + "/LinkLength/L1"
const P_IK_L2: NodePath = IK + "/LinkLength/L2"
const P_IK_L3: NodePath = IK + "/LinkLength/L3"
# 关节行（Joint1~Joint4），每行子节点：IO/Dir/Zero/Min/Max
const IK_JOINT_ROWS: Array = ["Joint1", "Joint2", "Joint3", "Joint4"]
# 预设点位行（Preset1~Preset4），每行子节点：Key/X/Y/Z/Phi
const IK_PRESET_ROWS: Array = ["Preset1", "Preset2", "Preset3", "Preset4"]
const P_IK_JOY_X: NodePath = IK + "/JoystickMap/XAxis"
const P_IK_JOY_Y: NodePath = IK + "/JoystickMap/YAxis"
const P_IK_JOY_Z: NodePath = IK + "/JoystickMap/ZAxis"
const P_IK_JOY_SCALE: NodePath = IK + "/JoystickMap/Scale"
# TabContainer（用于切换代码生成器）
const P_TAB_CONTAINER: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer"
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
# 工程师项目模板
const PROJECT_ENGINEER_SRC: String = "res://stc32g/Projects/ROBOMASTER_ENGINEER"
const PROJECT_ENGINEER_DST: String = "user://stc32g/Projects/ROBOMASTER_ENGINEER"
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
# 当前选中的代码生成器（随 Tab 切换）
var _codegen: CodeGenBase = null


func _ready() -> void:
	# 为 C 代码预览框挂载语法高亮器（状态机正则）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		var hl: SyntaxHighlighter = preload("res://scripts/c_highlighter.gd").new()
		code_edit.syntax_highlighter = hl
	# 初始化调试界面占位提示
	_update_debug_placeholders()
	# 初始执行一次检查，并在控件变化时实时检查
	_run_check()
	_connect_signals()


# ------------------------------------------------------------------ 信号连接
func _connect_signals() -> void:
	# LineEdit 文本变化
	for p in [P_CHANNEL, P_DEADZONE, P_NORMAL_SPEED, P_SPRINT_SPEED,
			P_TRIGGER_SPEED, P_TRIGGER_TIME,
			P_YAW_MID_OFFSET, P_PITCH_MID_OFFSET]:
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
	# 归中复选框
	var zero_cb: Node = get_node_or_null(P_ZERO_CB)
	if zero_cb is BaseButton:
		zero_cb.toggled.connect(_run_check)
	# 工程师界面：IO 初始化区变化触发检查
	for p in [P_ENG_P60, P_ENG_P62, P_ENG_P64, P_ENG_P66,
			P_ENG_P74, P_ENG_P75, P_ENG_P76, P_ENG_P77]:
		var eng_btn: Node = get_node_or_null(p)
		if eng_btn is OptionButton:
			eng_btn.item_selected.connect(_run_check)
	# 工程师界面：按键映射区变化触发检查
	for row_name in ENG_KEY_ROWS:
		var row_path: String = ENGINEER + "/" + row_name
		for child_name in ["OptionButton2", "OptionButton", "OptionButton3"]:
			var eng_child: Node = get_node_or_null(NodePath(row_path +"/"+ child_name))
			if eng_child is OptionButton:
				eng_child.item_selected.connect(_run_check)
		var eng_le: Node = get_node_or_null(NodePath(row_path +"/LineEdit"))
		if eng_le is LineEdit:
			eng_le.text_changed.connect(_run_check)
	# 编译按钮
	var build_btn: Node = get_node_or_null(P_BUILD_BTN)
	if build_btn is BaseButton:
		build_btn.pressed.connect(_on_build_pressed)
	# 调试界面：驱动类型变化时更新占位提示并触发检查
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton"))
		if drive_btn is OptionButton:
			drive_btn.item_selected.connect(_update_debug_placeholders)
			drive_btn.item_selected.connect(_run_check)
	# 调试界面：方向变化触发检查
	for row_name in DEBUG_ROWS:
		var dir_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton2"))
		if dir_btn is OptionButton:
			dir_btn.item_selected.connect(_run_check)
	# 调试界面：输入框文本变化时触发检查
	for row_name in DEBUG_ROWS:
		var debug_le: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/LineEdit"))
		if debug_le is LineEdit:
			debug_le.text_changed.connect(_run_check)
	# 工程逆解算界面：构型/连杆长度变化触发检查
	for p in [P_IK_CONFIG_TYPE, P_IK_JOY_X, P_IK_JOY_Y, P_IK_JOY_Z]:
		var ik_opt: Node = get_node_or_null(p)
		if ik_opt is OptionButton:
			ik_opt.item_selected.connect(_run_check)
	for p in [P_IK_L1, P_IK_L2, P_IK_L3, P_IK_JOY_SCALE]:
		var ik_le: Node = get_node_or_null(p)
		if ik_le is LineEdit:
			ik_le.text_changed.connect(_run_check)
	# 工程逆解算界面：各关节 IO/方向变化触发检查
	for row_name in IK_JOINT_ROWS:
		for child in ["IO", "Dir"]:
			var joint_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/"+ child))
			if joint_btn is OptionButton:
				joint_btn.item_selected.connect(_run_check)
	# 工程逆解算界面：各关节输入框文本变化触发检查
	for row_name in IK_JOINT_ROWS:
		for child in ["Zero", "Min", "Max"]:
			var joint_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/"+ child))
			if joint_le is LineEdit:
				joint_le.text_changed.connect(_run_check)
	# 工程逆解算界面：预设点位按键/坐标变化触发检查
	for row_name in IK_PRESET_ROWS:
		var key_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Key"))
		if key_btn is OptionButton:
			key_btn.item_selected.connect(_run_check)
		for child in ["X", "Y", "Z", "Phi"]:
			var preset_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/"+ child))
			if preset_le is LineEdit:
				preset_le.text_changed.connect(_run_check)
	# Tab 切换时更新代码生成器
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	if tab_container is TabContainer:
		tab_container.tab_changed.connect(_on_tab_changed)


# ------------------------------------------------------------------ Tab 切换
## Tab 切换时更新代码生成器并重新生成预览
func _on_tab_changed(_tab: int) -> void:
	_run_check()


## 根据当前 Tab 选项获取对应的代码生成器
func _get_current_codegen() -> CodeGenBase:
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	if not tab_container is TabContainer:
		return CodeGenInfantry.new()
	var current: int = tab_container.current_tab
	# Tab 顺序：0=步兵, 1=工程, 2=工程逆解算, 3=调试
	match current:
		0:
			return CodeGenInfantry.new()
		1:
			return CodeGenEngineer.new()
		2:
			return CodeGenEngineerIK.new()
		3:
			return CodeGenDebug.new()
		_:
			return CodeGenInfantry.new()


# ------------------------------------------------------------------ 调试界面占位提示
## 根据调试界面各行驱动类型（电机/舵机/摩擦轮）更新输入框占位文本
func _update_debug_placeholders(_idx: int = -1) -> void:
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton"))
		var line_edit: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/LineEdit"))
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


# ------------------------------------------------------------------ 规则：工程师底盘 IO 检查
# 底盘 L1-L4 之间：同侧（左前/左后 或 右前/右后）允许共用 IO，异侧不可
# 底盘 IO 与 IO 初始化区一致性：底盘选的槽位在 IO 初始化区必须为「电机」
func _check_engineer_chassis_io(issues: Array) -> void:
	# --- 底盘 IO 重复检查 ---
	var io_entries: Array = [
		{"path": P_L1_IO, "label": "底盘-左前轮 IO", "group": "left"},
		{"path": P_L2_IO, "label": "底盘-左后轮 IO", "group": "left"},
		{"path": P_R1_IO, "label": "底盘-右前轮 IO", "group": "right"},
		{"path": P_R2_IO, "label": "底盘-右后轮 IO", "group": "right"},
	]
	var io_map: Dictionary = {}
	for entry in io_entries:
		var btn: Node = get_node_or_null(entry["path"])
		if not btn is OptionButton:
			continue
		var io_text: String = btn.get_item_text(btn.selected)
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
	var cfg: Dictionary = _collect_engineer_config()
	var io_init: Dictionary = cfg.get("io_init", {})
	for entry in io_entries:
		var btn2: Node = get_node_or_null(entry["path"])
		if not btn2 is OptionButton:
			continue
		var io_text2: String = btn2.get_item_text(btn2.selected)
		var pin2: String = io_text2.split(" ")[0] if io_text2.contains(" ") else io_text2
		# MP03/MP74 不是底盘电机 IO，跳过
		if pin2.begins_with("MP"):
			continue
		var init_type: String = io_init.get(pin2, "")
		if not init_type.is_empty() and init_type != "电机":
			issues.append({"type": "Error",
				"msg": "工程 %s 选了 %s，但 IO 初始化区将其设为「%s」（底盘电机必须为电机模式）"
					% [entry["label"], pin2, init_type]})


# ------------------------------------------------------------------ 规则：工程师按键映射检查
func _check_engineer_keymap(issues: Array) -> void:
	var cfg: Dictionary = _collect_engineer_config()
	var io_init: Dictionary = cfg.get("io_init", {})
	var key_map: Array = cfg.get("key_map", [])
	# IO 类型映射（MP03/MP74 -> 舵机，P60-P77 -> io_init 中的类型）
	var slot_type: Dictionary = {}
	for pin in ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]:
		slot_type[pin] = io_init.get(pin, "舵机")
	slot_type["MP03"] = "舵机"
	slot_type["MP74"] = "舵机"
	# IO 冲突检查：多个映射行选同一目标 IO
	var target_used: Dictionary = {}
	for i in range(key_map.size()):
		var row: Dictionary = key_map[i]
		var target: String = row.get("target", "")
		if target.is_empty():
			continue
		var label: String = ENG_KEY_LABELS[i] if i < ENG_KEY_LABELS.size() else str(i)
		# 检查 target 是否与底盘 IO 冲突（底盘 L1-L4 占用的槽位不可被按键映射重复使用为电机）
		if target_used.has(target):
			issues.append({"type": "Error",
				"msg": "工程按键映射 IO %s 被 %s 和 %s 重复使用" % [target, target_used[target], label]})
		else:
			target_used[target] = label
		# 按键映射目标 IO 与底盘 IO 冲突检查
		if not target.begins_with("MP"):
			var l1_io: String = cfg.get("l1_io", "")
			var l2_io: String = cfg.get("l2_io", "")
			var r1_io: String = cfg.get("r1_io", "")
			var r2_io: String = cfg.get("r2_io", "")
			var l1_pin: String = l1_io.split(" ")[0] if l1_io.contains(" ") else l1_io
			var l2_pin: String = l2_io.split(" ")[0] if l2_io.contains(" ") else l2_io
			var r1_pin: String = r1_io.split(" ")[0] if r1_io.contains(" ") else r1_io
			var r2_pin: String = r2_io.split(" ")[0] if r2_io.contains(" ") else r2_io
			if target in [l1_pin, l2_pin, r1_pin, r2_pin]:
				issues.append({"type": "Error",
					"msg": "工程 %s 目标 IO %s 与底盘电机 IO 冲突" % [label, target]})
		# IO 初始化区未配置该 IO 时 Warn
		if not target.begins_with("MP"):
			var init_t: String = io_init.get(target, "")
			if init_t.is_empty():
				issues.append({"type": "Warn",
					"msg": "工程 %s 目标 IO %s 未在 IO 初始化区配置" % [label, target]})
		# 控制模式与 IO 类型匹配
		var mode: String = row.get("mode", "增量")
		var t_type: String = slot_type.get(target, "舵机")
		match mode:
			"增量":
				if t_type != "舵机":
					issues.append({"type": "Error",
						"msg": "工程 %s 增量模式只能用于舵机，但 %s 是 %s" % [label, target, t_type]})
			"速度", "增速":
				if t_type != "电机":
					issues.append({"type": "Error",
						"msg": "工程 %s %s模式只能用于电机，但 %s 是 %s" % [label, mode, target, t_type]})
		# 摇杆行不能用「直接」模式
		var input_name: String = row.get("input", "")
		var is_joystick: bool = input_name in ["右摇杆X", "右摇杆Y"]
		if is_joystick and mode == "直接":
			issues.append({"type": "Error",
				"msg": "工程 %s 摇杆行不能用直接模式" % label})
		# 按键行不能用「速度/增速」模式
		if not is_joystick and mode in ["速度", "增速"]:
			issues.append({"type": "Error",
				"msg": "工程 %s 按键行不能用%s模式（需要摇杆值）" % [label, mode]})
		# 参数范围检查
		var param: String = row.get("param", "")
		if not param.is_empty():
			if not param.is_valid_int():
				issues.append({"type": "Error",
					"msg": "工程 %s 参数「%s」不是合法整数" % [label, param]})
			else:
				var val: int = param.to_int()
				match mode:
					"增量":
						if val < 0 or val > 180:
							issues.append({"type": "Error",
								"msg": "工程 %s 增量参数 %d 超出范围（0-180）" % [label, val]})
					"直接":
						if t_type == "舵机":
							if val < -180 or val > 180:
								issues.append({"type": "Error",
									"msg": "工程 %s 舵机角度 %d 超出范围（-180~180）" % [label, val]})
						else:
							if val < 0 or val > 10000:
								issues.append({"type": "Error",
									"msg": "工程 %s 电机速度 %d 超出范围（0-10000）" % [label, val]})
					"速度", "增速":
						if val < 0 or val > 10000:
							issues.append({"type": "Error",
								"msg": "工程 %s %s参数 %d 超出范围（0-10000）" % [label, mode, val]})


# ------------------------------------------------------------------ 规则：调试界面参数范围
# 舵机角度 ∈ [-180, 180]，电机速度 ∈ [0, 10000]，摩擦轮速度 ∈ [0, 1100]
func _check_debug_params(issues: Array) -> void:
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton"))
		var line_edit: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/LineEdit"))
		var label_node: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/Label"))
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


## 收集调试界面各行配置，返回 Array[Dictionary]
func _collect_debug_config() -> Array:
	var rows: Array = []
	for row_name in DEBUG_ROWS:
		var drive_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton"))
		var dir_btn: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/OptionButton2"))
		var line_edit: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/LineEdit"))
		var label_node: Node = get_node_or_null(NodePath(DEBUG +"/"+ row_name +"/Label"))
		if not drive_btn is OptionButton or not dir_btn is OptionButton or not line_edit is LineEdit:
			continue
		var pin_name: String = label_node.text if label_node is Label else row_name
		var drive_type: String = drive_btn.get_item_text(drive_btn.selected)
		var dir_text: String = dir_btn.get_item_text(dir_btn.selected)
		var dir_val: int = 1 if dir_text == "正" else 0
		var text: String = line_edit.text.strip_edges()
		var enabled: bool = not text.is_empty()
		var value: int = text.to_int() if text.is_valid_int() else 0
		rows.append({
			"pin": pin_name,
			"drive_type": drive_type,
			"dir": dir_val,
			"value": value,
			"enabled": enabled,
		})
	return rows


# ------------------------------------------------------------------ 工程逆解算：配置收集
## 构型索引 -> 关节数（2/3/4）
func _ik_joint_count(config_type_idx: int) -> int:
	match config_type_idx:
		0: return 2
		1: return 3
		2: return 4
	return 2


## 收集工程逆解算界面配置，返回字典供代码生成使用
func _collect_ik_config() -> Dictionary:
	var cfg: Dictionary = {}
	var type_btn: Node = get_node_or_null(P_IK_CONFIG_TYPE)
	var type_idx: int = type_btn.selected if type_btn is OptionButton else 0
	cfg["config_type"] = type_idx # 0=2轴, 1=3轴, 2=4轴
	cfg["joint_count"] = _ik_joint_count(type_idx)
	# 连杆长度（mm）
	cfg["L1"] = _get_line_text(P_IK_L1).strip_edges()
	cfg["L2"] = _get_line_text(P_IK_L2).strip_edges()
	cfg["L3"] = _get_line_text(P_IK_L3).strip_edges()
	# 各关节配置
	var joints: Array = []
	for i in range(cfg["joint_count"]):
		var row_name: String = IK_JOINT_ROWS[i]
		var io_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/IO"))
		var dir_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Dir"))
		var zero_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Zero"))
		var min_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Min"))
		var max_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Max"))
		joints.append({
			"io": io_btn.get_item_text(io_btn.selected) if io_btn is OptionButton else "P60",
			"dir": dir_btn.get_item_text(dir_btn.selected) if dir_btn is OptionButton else "正向",
			"zero": (zero_le.text.strip_edges() if zero_le is LineEdit else ""),
			"min": (min_le.text.strip_edges() if min_le is LineEdit else ""),
			"max": (max_le.text.strip_edges() if max_le is LineEdit else ""),
		})
	cfg["joints"] = joints
	# 预设点位
	var presets: Array = []
	for row_name in IK_PRESET_ROWS:
		var key_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Key"))
		var x_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/X"))
		var y_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Y"))
		var z_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Z"))
		var phi_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Phi"))
		var x_text: String = x_le.text.strip_edges() if x_le is LineEdit else ""
		var y_text: String = y_le.text.strip_edges() if y_le is LineEdit else ""
		# 判断是否启用：至少 X 和 Y 填了
		var enabled: bool = not x_text.is_empty() and not y_text.is_empty()
		presets.append({
			"key": key_btn.get_item_text(key_btn.selected) if key_btn is OptionButton else "A",
			"x": x_text,
			"y": y_text,
			"z": z_le.text.strip_edges() if z_le is LineEdit else "",
			"phi": phi_le.text.strip_edges() if phi_le is LineEdit else "",
			"enabled": enabled,
		})
	cfg["presets"] = presets
	# 摇杆映射
	cfg["joy_x"] = _get_option_text(P_IK_JOY_X)
	cfg["joy_y"] = _get_option_text(P_IK_JOY_Y)
	cfg["joy_z"] = _get_option_text(P_IK_JOY_Z)
	cfg["joy_scale"] = _get_line_text(P_IK_JOY_SCALE).strip_edges()
	return cfg


# ------------------------------------------------------------------ 工程逆解算：静态检查
func _check_ik_params(issues: Array) -> void:
	var cfg: Dictionary = _collect_ik_config()
	var jc: int = cfg["joint_count"]
	# 连杆长度
	for lk in ["L1", "L2"]:
		var s: String = cfg.get(lk, "")
		if s.is_empty():
			issues.append({"type": "Error", "msg": "工程逆解算 %s 未设置（连杆长度）" % lk})
		elif not s.is_valid_float():
			issues.append({"type": "Error", "msg": "工程逆解算 %s「%s」不是合法数值" % [lk, s]})
		elif s.to_float() <= 0:
			issues.append({"type": "Error", "msg": "工程逆解算 %s = %s 必须 > 0" % [lk, s]})
	# 4 轴时 L3 可选，填了则需合法
	if jc == 4:
		var l3: String = cfg.get("L3", "")
		if not l3.is_empty() and (not l3.is_valid_float() or l3.to_float() < 0):
			issues.append({"type": "Error", "msg": "工程逆解算 L3「%s」不是合法非负数值" % l3})
	# 各关节限位与零点
	var joints: Array = cfg["joints"]
	for i in range(joints.size()):
		var j: Dictionary = joints[i]
		var min_s: String = j.get("min", "")
		var max_s: String = j.get("max", "")
		var zero_s: String = j.get("zero", "")
		if min_s.is_empty() or max_s.is_empty():
			issues.append({"type": "Error", "msg": "工程逆解算 关节%d 限位未设置" % (i + 1)})
			continue
		if not min_s.is_valid_float() or not max_s.is_valid_float():
			issues.append({"type": "Error",
				"msg": "工程逆解算 关节%d 限位不是合法数值" % (i + 1)})
			continue
		var min_v: float = min_s.to_float()
		var max_v: float = max_s.to_float()
		if min_v >= max_v:
			issues.append({"type": "Error",
				"msg": "工程逆解算 关节%d 限位 min(%.1f) >= max(%.1f)" % [i + 1, min_v, max_v]})
		if min_v < -180 or max_v > 180:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 关节%d 限位超出 ±180°" % (i + 1)})
		# 零点偏移：若填了需在 [min, max] 内
		if not zero_s.is_empty():
			if not zero_s.is_valid_float():
				issues.append({"type": "Error",
					"msg": "工程逆解算 关节%d 零点「%s」不是合法数值" % [i + 1, zero_s]})
			elif zero_s.to_float() < min_v or zero_s.to_float() > max_v:
				issues.append({"type": "Error",
					"msg": "工程逆解算 关节%d 零点 %.1f 超出限位 [%.1f, %.1f]" % [i + 1, zero_s.to_float(), min_v, max_v]})
	# IO 不重复
	var io_map: Dictionary = {}
	for i in range(joints.size()):
		var io: String = joints[i].get("io", "")
		if not io_map.has(io):
			io_map[io] = []
		io_map[io].append(i + 1)
	for io in io_map.keys():
		if io_map[io].size() > 1:
			issues.append({"type": "Error",
				"msg": "工程逆解算 IO %s 被多关节复用：%s" % [io, str(io_map[io])]})
	# 预设点位可达性检查（仅对启用的点位）
	var l1: float = cfg.get("L1", "0").to_float()
	var l2: float = cfg.get("L2", "0").to_float()
	var presets: Array = cfg["presets"]
	for i in range(presets.size()):
		var p: Dictionary = presets[i]
		if not p.get("enabled", false):
			continue
		var x: float = p.get("x", "0").to_float() if p.get("x", "").is_valid_float() else 0
		var y: float = p.get("y", "0").to_float() if p.get("y", "").is_valid_float() else 0
		var r: float = sqrt(x * x + y * y)
		var reach_min: float = abs(l1 - l2)
		var reach_max: float = l1 + l2
		if r < reach_min or r > reach_max:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 预设点位 P%d (x=%.1f, y=%.1f) 超出可达范围 [%.1f, %.1f]" % [i + 1, x, y, reach_min, reach_max]})
	# 摇杆轴不能重复
	var jx: String = cfg.get("joy_x", "")
	var jy: String = cfg.get("joy_y", "")
	var jz: String = cfg.get("joy_z", "")
	var joy_axes: Array = [jx, jy, jz]
	var seen: Dictionary = {}
	for i in range(joy_axes.size()):
		var ax: String = joy_axes[i]
		if ax.is_empty():
			continue
		if seen.has(ax):
			issues.append({"type": "Error",
				"msg": "工程逆解算 摇杆映射重复：%s 被多轴使用" % ax})
		seen[ax] = true
	# 缩放
	var scale_s: String = cfg.get("joy_scale", "")
	if not scale_s.is_empty() and (not scale_s.is_valid_float() or scale_s.to_float() <= 0):
		issues.append({"type": "Error",
			"msg": "工程逆解算 摇杆缩放「%s」不是合法正数" % scale_s})


# ------------------------------------------------------------------ 检查入口
func _run_check(_a = null, _b = null) -> void:
	var issues: Array = []
	# 根据当前 Tab 决定执行哪些检查
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var current_tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	if current_tab == 0:
		# 步兵模式检查
		_check_channel(issues)
		_check_deadzone(issues)
		_check_speeds(issues)
		_check_arrow_trigger_conflict(issues)
		_check_io_duplicate(issues)
		_check_gimbal_pin_conflict(issues)
	elif current_tab == 1:
		# 工程模式检查
		_check_channel(issues)
		_check_deadzone(issues)
		_check_speeds(issues)
		_check_engineer_chassis_io(issues)
		_check_engineer_keymap(issues)
	elif current_tab == 3:
		# 调试模式检查（tab 顺序：0=步兵, 1=工程, 2=工程逆解算, 3=调试）
		_check_debug_params(issues)
	elif current_tab == 2:
		# 工程逆解算模式检查
		_check_ik_params(issues)
	# 将问题展示到 Output
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("set_issues"):
		out.set_issues(issues)
	# 实时生成 main.c 并预览到 CodeEdit
	_codegen = _get_current_codegen()
	var cfg: Dictionary
	match current_tab:
		3:
			cfg = {"debug_rows": _collect_debug_config()}
		1:
			cfg = _collect_engineer_config()
		2:
			cfg = _collect_ik_config()
		_:
			cfg = _collect_config()
	var code: String = _codegen.generate(cfg)
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
	cfg["yaw_mid_offset"] = _get_line_text(P_YAW_MID_OFFSET).strip_edges()
	cfg["pitch_mid_offset"] = _get_line_text(P_PITCH_MID_OFFSET).strip_edges()
	# --- 按键映射 ---
	var arrow: Node = get_node_or_null(P_ARROW_KEY)
	cfg["arrow_key"] = arrow.get_item_text(arrow.selected) if arrow is OptionButton else "移动"
	cfg["trigger_key"] = _get_option_text(P_TRIGGER)
	cfg["trigger_speed"] = _get_line_text(P_TRIGGER_SPEED).strip_edges()
	cfg["trigger_time"] = _get_line_text(P_TRIGGER_TIME).strip_edges()
	cfg["booster_key"] = _get_option_text(P_BOOSTER_KEY)
	var zero_cb: Node = get_node_or_null(P_ZERO_CB)
	cfg["zero_enabled"] = (zero_cb is BaseButton) and zero_cb.button_pressed
	return cfg


## 收集工程师界面配置，返回 Dictionary（含 FirstRow 共享参数）
func _collect_engineer_config() -> Dictionary:
	var cfg: Dictionary = {}
	# --- FirstRow 共享参数 ---
	cfg["channel"] = _get_line_text(P_CHANNEL).strip_edges()
	cfg["deadzone"] = _get_line_text(P_DEADZONE).strip_edges()
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
	# --- IO 初始化区 ---
	var io_init: Dictionary = {}
	io_init["P60"] = _get_option_text(P_ENG_P60)
	io_init["P62"] = _get_option_text(P_ENG_P62)
	io_init["P64"] = _get_option_text(P_ENG_P64)
	io_init["P66"] = _get_option_text(P_ENG_P66)
	io_init["P74"] = _get_option_text(P_ENG_P74)
	io_init["P75"] = _get_option_text(P_ENG_P75)
	io_init["P76"] = _get_option_text(P_ENG_P76)
	io_init["P77"] = _get_option_text(P_ENG_P77)
	cfg["io_init"] = io_init
	# --- 按键映射区 ---
	var key_map: Array = []
	for i in range(ENG_KEY_ROWS.size()):
		var row_name: String = ENG_KEY_ROWS[i]
		var row_path: String = ENGINEER + "/" + row_name
		var dir_btn: Node = get_node_or_null(NodePath(row_path +"/OptionButton2"))
		var mode_btn: Node = get_node_or_null(NodePath(row_path +"/OptionButton"))
		var param_edit: Node = get_node_or_null(NodePath(row_path +"/LineEdit"))
		var target_btn: Node = get_node_or_null(NodePath(row_path +"/OptionButton3"))
		if not dir_btn is OptionButton or not mode_btn is OptionButton or not target_btn is OptionButton:
			continue
		var param_text: String = param_edit.text.strip_edges() if param_edit is LineEdit else ""
		key_map.append({
			"input": ENG_KEY_LABELS[i],
			"dir": dir_btn.get_item_text(dir_btn.selected),
			"mode": mode_btn.get_item_text(mode_btn.selected),
			"param": param_text,
			"target": target_btn.get_item_text(target_btn.selected),
		})
	cfg["key_map"] = key_map
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
	# 工程师项目模板也确保存在
	if not DirAccess.dir_exists_absolute(_to_abs(PROJECT_ENGINEER_DST)):
		if not _copy_dir_recursive(PROJECT_ENGINEER_SRC, PROJECT_ENGINEER_DST):
			_append_output("[Error] 无法复制工程师项目模板到 user://，请检查磁盘空间")
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
	var entry_name: String = da.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = da.get_next()
			continue
		var src_item: String = src_path.path_join(entry_name)
		var dst_item: String = dst_path.path_join(entry_name)
		if da.current_is_dir():
			if not _copy_dir_recursive(src_item, dst_item):
				da.list_dir_end()
				return false
		else:
			if not _copy_file(src_item, dst_item):
				da.list_dir_end()
				return false
		entry_name = da.get_next()
	da.list_dir_end()
	return true


## 递归删除目录（user:// 路径）
func _remove_dir_recursive(dir_path: String) -> void:
	var abs_path: String = _to_abs(dir_path)
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry_name: String = da.get_next()
	while entry_name != "":
		if entry_name.begins_with("."):
			entry_name = da.get_next()
			continue
		var item_path: String = dir_path.path_join(entry_name)
		if da.current_is_dir():
			_remove_dir_recursive(item_path)
		else:
			var item_da: DirAccess = DirAccess.open(_to_abs(dir_path))
			if item_da:
				item_da.remove(entry_name)
		entry_name = da.get_next()
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
	var entry_name: String = da.get_next()
	var found: String = ""
	while entry_name != "" and found == "":
		if da.current_is_dir() and not entry_name.begins_with("."):
			var sub_dir: String = dir_abs.path_join(entry_name)
			for cand in UV4_CANDIDATES:
				var candidate: String = sub_dir.path_join(cand)
				if FileAccess.file_exists(candidate):
					found = candidate
					break
			if found == "":
				found = _find_uv4_recursive(sub_dir)
		entry_name = da.get_next()
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
	var project_dst: String = _get_current_project_dst()
	var main_c_path: String = project_dst.path_join("USER/src/main.c")
	var abs_path: String = _to_abs(main_c_path)
	var f: FileAccess = FileAccess.open(abs_path, FileAccess.WRITE)
	if f == null:
		push_error("无法写入 main.c: %s（%s）" % [abs_path, FileAccess.get_open_error()])
		return false
	f.store_string(code)
	f.close()
	return true


## 根据当前 Tab 获取项目部署路径
func _get_current_project_dst() -> String:
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var current_tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	# Tab 1=工程 -> ENGINEER 项目；其余 -> INFANTRY 项目
	if current_tab == 1:
		return PROJECT_ENGINEER_DST
	return PROJECT_DST


## 编译按钮回调：解压工具链 -> 写盘 -> 生成 TOOLS.INI -> 异步编译
func _on_build_pressed() -> void:
	if _build_busy:
		return # 防重入
	# 0) 确保工具链和项目模板已解压到 user://
	_clear_output()
	if not _ensure_deployed():
		_append_output("[Error] 工具链初始化失败，无法编译")
		return
	# 1) 取 CodeEdit 中最新生成的 main.c（即 _codegen.generate() 产物）
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
	# 根据当前 Tab 选择对应的项目模板路径
	var project_dst: String = _get_current_project_dst()
	var mdk_abs: String = _to_abs(project_dst).path_join("MDK").replace("/", "\\")
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

extends Control
## 主界面脚本。
## 负责收集各个配置控件的当前值并执行静态检查，把结果输出到 Output 代码框。
## 步兵检查规则：
##   - 通道号未设置 / 非整数 / 超出 0-125          -> Error
##   - 普通速度未设置 / 非整数 / 超出 0-10000       -> Error
##   - 死区、冲刺速度、拨弹速度、拨弹时间非整数或越界 -> Error
##   - 冲刺复选框选中但未设冲刺速度                 -> Error
##   - 同一物理引脚被多次引用（跨侧/跨云台）        -> Error（引脚对已归一化后比较）
##   - 摩擦轮引脚 P64/P66 被其他角色占用            -> Error
##   - Yaw/Pitch 在主控板 MP74/MP03 上选「电机」    -> Error（该端口只能驱动舵机）
##   - Yaw/Pitch 选了既非拓展板也非 MP74/MP03 的引脚 -> Error
##   - Yaw 与 Pitch 使用同一引脚                    -> Error
##   - 扳机键与摩擦轮开关键相同                     -> Error
##   - 方向键设为冲刺/移动但扳机键或开关键占用方向键 -> Error
##   - 归中角非整数或超出 -90~90（相对舵机中位）    -> Error
##   - 冲刺速度 < 普通速度                          -> Warn
##   - 同侧两轮共用 IO 但方向不同                   -> Warn
##   - 扳机键/开关键占用 B/C（摩擦轮档位微调）      -> Warn
##   - 拨弹时间 > 1000ms（阻塞主循环）              -> Warn


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
# 冲刺开关放在 FirstRow/Chassis（步兵与工程共用底盘设置）
const P_SPRINT_CB: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/FirstRow/Chassis/Sprint/CheckBox"
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
const P_ZERO_CB: NodePath = KEYSET + "/Zero/CheckBox"
# 方向键用途选择（移动 / 冲刺 / 其他），是 OptionButton 而非 CheckBox
const P_ARROW_KEY: NodePath = KEYSET + "/ArrowKey/OptionButton"
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
# 主控板舵机端口（固定舵机，只有一项，与扩展板 P74 不是同一个 IO）
const P_ENG_MP03: NodePath = ENGINEER + "/MP03MP74/OptionButton2"
const P_ENG_MP74: NodePath = ENGINEER + "/MP03MP74/OptionButton"
# 扩展板引脚名 -> IO 初始化区节点路径（供占位提示与配置收集共用）
const ENG_IO_PATHS: Dictionary = {
	"P60": ENGINEER + "/P60P62/OptionButton",
	"P62": ENGINEER + "/P60P62/OptionButton2",
	"P64": ENGINEER + "/P64P66/OptionButton",
	"P66": ENGINEER + "/P64P66/OptionButton2",
	"P74": ENGINEER + "/P74P75/OptionButton",
	"P75": ENGINEER + "/P74P75/OptionButton2",
	"P76": ENGINEER + "/P76P77/OptionButton2",
	"P77": ENGINEER + "/P76P77/OptionButton",
}
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
# 按键控制末端移动（长按持续移动）
const P_IK_KEYMOVE_SPEED: NodePath = IK + "/KeyMoveSpeed/Speed"
# 按键移动行（末端 X/Y/Z/姿态角φ），每行子节点：Plus/Minus
const IK_KEYMOVE_ROWS: Array = ["KeyMoveX", "KeyMoveY", "KeyMoveZ", "KeyMovePhi"]
# 与 IK_KEYMOVE_ROWS 一一对应的轴显示名
const IK_KEYMOVE_LABELS: Array = ["X", "Y", "Z", "φ"]
# 关节角以舵机中位为 0°，行程 ±90°（对应物理 0~180°）
const IK_ANGLE_MIN: float = -90.0
const IK_ANGLE_MAX: float = 90.0
# TabContainer（用于切换代码生成器）
const P_TAB_CONTAINER: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer"
# 输出
const P_OUTPUT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output"
const P_CODE_EDIT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit"
# 顶栏按钮
const P_BUILD_BTN: NodePath = "VBoxContainer/TopPanel/Build"
# AI 编辑入口（跳转到 code_edit.tscn）
const P_AI_EDIT_BTN: NodePath = "VBoxContainer/TopPanel/AIEdit"
# AI 代码编辑器场景
const AI_EDIT_SCENE: String = "res://scenes/code_edit.tscn"
# 注：工具链路径常量与部署/编译实现已迁到 scripts/toolchain.gd，与 AI 编辑器共用
# 用 preload 而非 class_name：headless / 首次导入时全局类名缓存可能尚未建立
const TC = preload("res://scripts/toolchain.gd")


# ------------------------------------------------------------------ 生命周期
var _build_thread: Thread = null
var _build_busy: bool = false
# 当前选中的代码生成器（随 Tab 切换）
var _codegen: CodeGenBase = null
# 工具链管理器（惰性创建，见 _toolchain()）
var _tc = null


func _ready() -> void:
	# 为 C 代码预览框挂载语法高亮器（状态机正则）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		var hl: SyntaxHighlighter = preload("res://scripts/c_highlighter.gd").new()
		code_edit.syntax_highlighter = hl
	# 从 AI 编辑器返回时恢复原来的 Tab（配置本身不做序列化，会回到默认值）
	if not AppState.project_dst.is_empty():
		var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
		if tab_container is TabContainer and AppState.source_tab < tab_container.get_tab_count():
			tab_container.current_tab = AppState.source_tab
	# 初始化调试界面占位提示
	_update_debug_placeholders()
	# 初始化工程界面参数框占位提示
	_update_engineer_placeholders()
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
	# 工程师界面：IO 初始化区变化触发检查（也会改变参数框的含义）
	for p in [P_ENG_P60, P_ENG_P62, P_ENG_P64, P_ENG_P66,
			P_ENG_P74, P_ENG_P75, P_ENG_P76, P_ENG_P77,
			P_ENG_MP03, P_ENG_MP74]:
		var eng_btn: Node = get_node_or_null(p)
		if eng_btn is OptionButton:
			eng_btn.item_selected.connect(_update_engineer_placeholders)
			eng_btn.item_selected.connect(_run_check)
	# 工程师界面：按键映射区变化触发检查
	for row_name in ENG_KEY_ROWS:
		var row_path: String = ENGINEER + "/" + row_name
		for child_name in ["OptionButton2", "OptionButton", "OptionButton3"]:
			var eng_child: Node = get_node_or_null(NodePath(row_path +"/"+ child_name))
			if eng_child is OptionButton:
				# 模式/目标 IO 变了，参数的量纲和范围也跟着变
				eng_child.item_selected.connect(_update_engineer_placeholders)
				eng_child.item_selected.connect(_run_check)
		var eng_le: Node = get_node_or_null(NodePath(row_path +"/LineEdit"))
		if eng_le is LineEdit:
			eng_le.text_changed.connect(_run_check)
	# 编译按钮
	var build_btn: Node = get_node_or_null(P_BUILD_BTN)
	if build_btn is BaseButton:
		build_btn.pressed.connect(_on_build_pressed)
	# AI 编辑入口
	var ai_btn: Node = get_node_or_null(P_AI_EDIT_BTN)
	if ai_btn is BaseButton:
		ai_btn.pressed.connect(_on_ai_edit_pressed)
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
	for p in [P_IK_L1, P_IK_L2, P_IK_L3, P_IK_JOY_SCALE, P_IK_KEYMOVE_SPEED]:
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
	# 工程逆解算界面：按键控制末端移动的按键选择变化触发检查
	for row_name in IK_KEYMOVE_ROWS:
		for child in ["Plus", "Minus"]:
			var km_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/"+ child))
			if km_btn is OptionButton:
				km_btn.item_selected.connect(_run_check)
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
		var drive_type: String = _option_text(drive_btn)
		var placeholder: String = ""
		match drive_type:
			"电机":
				placeholder = "速度 0~10000"
			"舵机":
				placeholder = "角度 -90~90"
			"摩擦轮":
				placeholder = "速度 0~1100"
		line_edit.placeholder_text = placeholder


# ------------------------------------------------------------------ 工程界面占位提示
## 根据每行的控制模式和目标 IO 类型，更新参数框的占位文本。
## 舵机角度一律是「相对中位的偏移角」，行程 ±90°，不是 0~180°。
func _update_engineer_placeholders(_idx: int = -1) -> void:
	var io_init: Dictionary = {}
	for pin in EXPANSION_PINS:
		io_init[pin] = _get_option_text(NodePath(ENG_IO_PATHS[pin]))
	for row_name in ENG_KEY_ROWS:
		var row_path: String = ENGINEER + "/" + row_name
		var mode_btn: Node = get_node_or_null(NodePath(row_path +"/OptionButton"))
		var target_btn: Node = get_node_or_null(NodePath(row_path +"/OptionButton3"))
		var line_edit: Node = get_node_or_null(NodePath(row_path +"/LineEdit"))
		if not mode_btn is OptionButton or not target_btn is OptionButton \
				or not line_edit is LineEdit:
			continue
		var mode: String = _option_text(mode_btn)
		var target: String = _option_text(target_btn)
		if target.is_empty() or target == "不使用":
			line_edit.placeholder_text = ""
			continue
		# MP03/MP74 固定舵机；扩展板引脚看 IO 初始化区
		var is_servo: bool = target.begins_with("MP") or io_init.get(target, "舵机") == "舵机"
		var placeholder: String = ""
		match mode:
			"增量":
				# 单次/满偏步长，取正值，方向由左侧「正/反」决定
				placeholder = "步长 0~%d°" % SERVO_MAX_ANGLE
			"直接":
				if is_servo:
					placeholder = "偏移角 -%d~%d°" % [SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]
				else:
					placeholder = "速度 0~%d" % MOTOR_SPEED_MAX
			"速度", "增速":
				placeholder = "满偏速度 0~%d" % MOTOR_SPEED_MAX
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
		var io_text: String = _option_text(btn)
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
		var io_text2: String = _option_text(btn2)
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
# 舵机相对中位的可用偏移角上限（与 CodeGenBase.SERVO_MAX_OFFSET_DEG 一致）
const SERVO_MAX_ANGLE: int = 90
# 单次增量超过此角度时提示过快（主循环 10ms 一轮）
const SERVO_STEP_WARN_DEG: int = 30
# 电机速度上限
const MOTOR_SPEED_MAX: int = 10000

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
	# 底盘占用的引脚（按键映射不可重复使用）
	var chassis_pins: Array = []
	for key in ["l1_io", "l2_io", "r1_io", "r2_io"]:
		var io_text: String = cfg.get(key, "")
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
		var target: String = row.get("target", "")
		if target.is_empty():
			continue
		# 标签取自行自身的 input，避免 key_map 有行被跳过时索引错位
		var label: String = row.get("input", "?")
		var mode: String = row.get("mode", "增量")
		var t_type: String = slot_type.get(target, "舵机")
		if t_type.is_empty():
			t_type = "舵机"
		if not groups.has(target):
			groups[target] = []
		groups[target].append({"label": label, "mode": mode, "dir": row.get("dir", "正"),
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
				if t_type == "舵机" and row.get("dir", "正") == "反":
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
		var param: String = row.get("param", "")
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
			# “增速 + 直接”组合没有归零，松开按键后值会被增速持续累加
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
		var drive_type: String = _option_text(drive_btn)
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
				# 相对中位的偏移角，舵机总行程 180°，即 ±90°
				if val < -SERVO_MAX_ANGLE or val > SERVO_MAX_ANGLE:
					issues.append({"type": "Error",
						"msg": "调试 %s 舵机角度 %d 超出范围（有效范围 -%d~%d，相对中位）"
							% [pin_name, val, SERVO_MAX_ANGLE, SERVO_MAX_ANGLE]})
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
		var drive_type: String = _option_text(drive_btn)
		var dir_text: String = _option_text(dir_btn)
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
			"io": _option_text(io_btn) if io_btn is OptionButton else "P60",
			"dir": _option_text(dir_btn) if dir_btn is OptionButton else "正向",
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
		var z_text: String = z_le.text.strip_edges() if z_le is LineEdit else ""
		var phi_text: String = phi_le.text.strip_edges() if phi_le is LineEdit else ""
		# 判断是否启用：任一坐标填了即视为用户想启用该点位。
		# 内容是否合法由 _check_ik_params 报错，避免非法输入被静默当成 0。
		var enabled: bool = not (x_text.is_empty() and y_text.is_empty()
			and z_text.is_empty() and phi_text.is_empty())
		presets.append({
			"key": _option_text(key_btn) if key_btn is OptionButton else "A",
			"x": x_text,
			"y": y_text,
			"z": z_text,
			"phi": phi_text,
			"enabled": enabled,
		})
	cfg["presets"] = presets
	# 摇杆映射
	cfg["joy_x"] = _get_option_text(P_IK_JOY_X)
	cfg["joy_y"] = _get_option_text(P_IK_JOY_Y)
	cfg["joy_z"] = _get_option_text(P_IK_JOY_Z)
	cfg["joy_scale"] = _get_line_text(P_IK_JOY_SCALE).strip_edges()
	# 按键控制末端移动（长按持续移动）
	cfg["keymove_speed"] = _get_line_text(P_IK_KEYMOVE_SPEED).strip_edges()
	var keymove: Array = []
	for row_name in IK_KEYMOVE_ROWS:
		var plus_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Plus"))
		var minus_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Minus"))
		keymove.append({
			"plus": _option_text(plus_btn) if plus_btn is OptionButton else "不使用",
			"minus": _option_text(minus_btn) if minus_btn is OptionButton else "不使用",
		})
	cfg["keymove"] = keymove
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
	# 各关节限位与初始角
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
		# 舵机角是相对中位的偏移角，行程 ±90°（占空比见 CodeGenBase），超出部分会被钳到端点
		if min_v < IK_ANGLE_MIN or max_v > IK_ANGLE_MAX:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 关节%d 限位 [%.1f, %.1f] 超出舵机行程 ±90°（相对中位），超出部分会被钳到端点"
					% [i + 1, min_v, max_v]})
		# 初始角：若填了需在 [min, max] 内
		if not zero_s.is_empty():
			if not zero_s.is_valid_float():
				issues.append({"type": "Error",
					"msg": "工程逆解算 关节%d 初始角「%s」不是合法数值" % [i + 1, zero_s]})
			elif zero_s.to_float() < min_v or zero_s.to_float() > max_v:
				issues.append({"type": "Error",
					"msg": "工程逆解算 关节%d 初始角 %.1f 超出限位 [%.1f, %.1f]" % [i + 1, zero_s.to_float(), min_v, max_v]})
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
	# 预设点位：数值合法性、按键重复、可达性
	var l1: float = cfg.get("L1", "0").to_float()
	var l2: float = cfg.get("L2", "0").to_float()
	var l3: float = cfg.get("L3", "0").to_float()
	var presets: Array = cfg["presets"]
	var reach_min: float = abs(l1 - l2)
	var reach_max: float = l1 + l2
	var preset_keys: Dictionary = {} # 按键名 -> 首次使用的点位序号
	var active_count: int = 0
	for i in range(presets.size()):
		var p: Dictionary = presets[i]
		if not p.get("enabled", false):
			continue
		active_count += 1
		# 坐标必须是合法数值，否则生成时会被静默当成 0
		var bad_field: bool = false
		var need_fields: Array = ["x", "y"]
		if jc >= 3:
			need_fields.append("z")
		if jc >= 4:
			need_fields.append("phi")
		for f in need_fields:
			var t: String = p.get(f, "")
			if t.is_empty():
				issues.append({"type": "Warn",
					"msg": "工程逆解算 预设点位 P%d 的 %s 未填，将按 0 处理" % [i + 1, f.to_upper()]})
			elif not t.is_valid_float():
				issues.append({"type": "Error",
					"msg": "工程逆解算 预设点位 P%d 的 %s「%s」不是合法数值" % [i + 1, f.to_upper(), t]})
				bad_field = true
		# 预设点位按键不能互相重复，否则靠后的点位永远无法触发
		var pkey: String = p.get("key", "")
		if preset_keys.has(pkey):
			issues.append({"type": "Error",
				"msg": "工程逆解算 预设点位 P%d 与 P%d 使用了同一按键「%s」" % [i + 1, preset_keys[pkey], pkey]})
		else:
			preset_keys[pkey] = i + 1
		if bad_field:
			continue
		# 可达性：2 轴只看 XY 平面；3/4 轴需算上 Z；4 轴先沿 φ 回退 L3 得到腕心
		var x: float = _ik_num(p.get("x", ""))
		var y: float = _ik_num(p.get("y", ""))
		var z: float = _ik_num(p.get("z", ""))
		var phi: float = _ik_num(p.get("phi", ""))
		var r: float = 0.0
		if jc == 2:
			r = sqrt(x * x + y * y)
		elif jc == 3:
			r = sqrt(x * x + y * y + z * z)
		else:
			var phi_rad: float = deg_to_rad(phi)
			var rw: float = sqrt(x * x + y * y) - l3 * cos(phi_rad)
			var zw: float = z - l3 * sin(phi_rad)
			r = sqrt(rw * rw + zw * zw)
		if r < reach_min or r > reach_max:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 预设点位 P%d 折算半径 %.1f 超出可达范围 [%.1f, %.1f]"
					% [i + 1, r, reach_min, reach_max]})
	if active_count == 0:
		issues.append({"type": "Warn",
			"msg": "工程逆解算 未配置任何预设点位，生成的代码只能靠摇杆/按键增量控制"})
	# 摇杆映射检查（左摇杆固定用于底盘，末端控制只用右摇杆的水平/竖直两轴）
	# 选项文本形如「右Y->末端X」，必须比较 "->" 左侧的源轴，不能直接比整串
	var jx: String = _ik_joy_src(cfg.get("joy_x", ""))
	var jy: String = _ik_joy_src(cfg.get("joy_y", ""))
	var jz: String = _ik_joy_src(cfg.get("joy_z", ""))
	# X 和 Y 是主要控制维度，不能映射到同一摇杆轴；Z 可与 X 或 Y 共用
	if not jx.is_empty() and not jy.is_empty() and jx == jy:
		issues.append({"type": "Error",
			"msg": "工程逆解算 末端X和末端Y映射到同一摇杆轴「%s」，需区分" % jx})
	# Z 与 X/Y 共用时给出提示（3/4轴才需要Z，2轴时Z未使用）
	if jc >= 3 and not jz.is_empty() and (jz == jx or jz == jy):
		issues.append({"type": "Warn",
			"msg": "工程逆解算 末端Z与末端%s共用摇杆轴「%s」，Z方向将随该轴联动" % ["X" if jz == jx else "Y", jz]})
	# 缩放：满偏时每周期位移，过大会让末端一帧冲出量程
	var scale_s: String = cfg.get("joy_scale", "")
	if not scale_s.is_empty():
		if not scale_s.is_valid_float() or scale_s.to_float() <= 0:
			issues.append({"type": "Error",
				"msg": "工程逆解算 摇杆缩放「%s」不是合法正数" % scale_s})
		elif reach_max > 0 and scale_s.to_float() > reach_max * 0.2:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 摇杆缩放 %.1fmm/周期 相对臂长(%.1fmm)偏大，末端会移动过快"
					% [scale_s.to_float(), reach_max]})
	# 按键控制末端移动检查
	var km_speed: String = cfg.get("keymove_speed", "")
	if not km_speed.is_empty() and (not km_speed.is_valid_float() or km_speed.to_float() <= 0):
		issues.append({"type": "Error",
			"msg": "工程逆解算 按键移动速度「%s」不是合法正数" % km_speed})
	var keymove: Array = cfg.get("keymove", [])
	# 收集所有按键移动用到的按键，检测冲突
	var km_used: Dictionary = {} # 按键名 -> 用途描述
	for i in range(keymove.size()):
		var plus_key: String = keymove[i].get("plus", "不使用")
		var minus_key: String = keymove[i].get("minus", "不使用")
		var ax_name: String = IK_KEYMOVE_LABELS[i] if i < IK_KEYMOVE_LABELS.size() else str(i)
		# 同轴正负方向不能用同一按键
		if plus_key != "不使用" and plus_key == minus_key:
			issues.append({"type": "Error",
				"msg": "工程逆解算 末端%s 的正/负方向使用了同一按键「%s」" % [ax_name, plus_key]})
		# 当前构型不使用的轴：配置了按键也不会生成代码
		var unused: bool = (jc < 3 and i == 2) or (jc < 4 and i == 3)
		if unused and (plus_key != "不使用" or minus_key != "不使用"):
			issues.append({"type": "Warn",
				"msg": "工程逆解算 %d轴构型不使用末端%s，已配置的按键不会生效" % [jc, ax_name]})
			continue
		# 跨轴按键冲突
		for pair in [[plus_key, "末端%s+" % ax_name], [minus_key, "末端%s-" % ax_name]]:
			var k: String = pair[0]
			if k == "不使用":
				continue
			if km_used.has(k):
				issues.append({"type": "Error",
					"msg": "工程逆解算 按键「%s」被重复使用：%s, %s" % [k, km_used[k], pair[1]]})
			else:
				km_used[k] = pair[1]
	# 按键移动与预设点位按键冲突
	for i in range(presets.size()):
		if not presets[i].get("enabled", false):
			continue
		var pk: String = presets[i].get("key", "")
		if km_used.has(pk):
			issues.append({"type": "Error",
				"msg": "工程逆解算 按键「%s」既用于预设点位 P%d 又用于%s" % [pk, i + 1, km_used[pk]]})
	# 4 轴时姿态角没有任何输入通道，腕部将固定在初始姿态
	if jc >= 4 and keymove.size() > 3:
		var phi_plus: String = keymove[3].get("plus", "不使用")
		var phi_minus: String = keymove[3].get("minus", "不使用")
		if phi_plus == "不使用" and phi_minus == "不使用":
			issues.append({"type": "Warn",
				"msg": "工程逆解算 4轴构型未配置末端φ的加减按键，腕部姿态只能由预设点位改变"})


## 解析预设坐标文本，非法或留空按 0 处理（合法性另有检查负责报错）
func _ik_num(text: String) -> float:
	if text.is_valid_float():
		return text.to_float()
	return 0.0


## 取摇杆映射选项的源轴，即 "->" 左侧部分（如「右Y->末端X」-> "右Y"）
func _ik_joy_src(text: String) -> String:
	var arrow: int = text.find("->")
	if arrow < 0:
		return text
	return text.substr(0, arrow)


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
		_check_trigger_params(issues)
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


# ------------------------------------------------------------------ 规则：整数范围通用校验
## 校验一个 LineEdit 是否为指定范围内的整数。
## 留空时按 required 决定报 Error 还是跳过（沿用生成器默认值）。
func _check_int_field(issues: Array, path: NodePath, label: String,
		lo: int, hi: int, required: bool = false) -> void:
	var node: Node = get_node_or_null(path)
	if not node is LineEdit:
		return # 节点缺失时不重复报，由界面结构保证
	var text: String = node.text.strip_edges()
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
func _check_deadzone(issues: Array) -> void:
	_check_int_field(issues, P_DEADZONE, "死区", 0, 2047)


# ------------------------------------------------------------------ 规则：速度
func _check_speeds(issues: Array) -> void:
	var normal_text: String = _get_line_text(P_NORMAL_SPEED).strip_edges()
	var sprint_text: String = _get_line_text(P_SPRINT_SPEED).strip_edges()

	# 占空比上限 10000（拓展板电机满量程）
	_check_int_field(issues, P_NORMAL_SPEED, "普通速度", 0, 10000, true)
	_check_int_field(issues, P_SPRINT_SPEED, "冲刺速度", 0, 10000)
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


# ------------------------------------------------------------------ 规则：扳机（单发拨弹）参数
func _check_trigger_params(issues: Array) -> void:
	_check_int_field(issues, P_TRIGGER_SPEED, "拨弹速度", 0, 10000)
	# 生成的代码用 Ms_Delay(boosterFeedDelayMs)，参数是 uint16_t
	_check_int_field(issues, P_TRIGGER_TIME, "拨弹时间(ms)", 0, 65535)
	# 单发期间会阻塞主循环，时间过长会让整车失控
	var t_text: String = _get_line_text(P_TRIGGER_TIME).strip_edges()
	if t_text.is_valid_int() and t_text.to_int() > 1000:
		issues.append({"type": "Warn",
			"msg": "拨弹时间 %s ms 过长，单发期间主循环阻塞，底盘和云台会失去响应" % t_text})


# ------------------------------------------------------------------ 规则：按键冲突
# 扳机键 / 摩擦轮开关键的选项：0=R, 1=↑, 2=↓, 3=←, 4=→, 5..8=A/B/C/D
# 索引 1..4 属于方向键；索引 6/7（B/C）被摩擦轮档位微调固定占用
const ARROW_KEY_INDICES: Array = [1, 2, 3, 4]
const BOOSTER_LEVEL_KEY_INDICES: Array = [6, 7]

func _check_arrow_trigger_conflict(issues: Array) -> void:
	var trigger: Node = get_node_or_null(P_TRIGGER)
	var booster: Node = get_node_or_null(P_BOOSTER_KEY)
	if not trigger is OptionButton or not booster is OptionButton:
		return
	var trig_idx: int = trigger.selected
	var boost_idx: int = booster.selected
	# 扳机键与摩擦轮开关键不能相同
	if trig_idx == boost_idx:
		issues.append({"type": "Error",
			"msg": "扳机键与摩擦轮开关键都设为「%s」，会同时触发单发拨弹和摩擦轮开关"
				% trigger.get_item_text(trig_idx)})
	# ArrowKey 选项：0=移动, 1=冲刺, 2=其他
	var arrow: Node = get_node_or_null(P_ARROW_KEY)
	if arrow is OptionButton and arrow.selected in [0, 1]:
		var arrow_label: String = "移动" if arrow.selected == 0 else "冲刺"
		for pair in [[trigger, trig_idx, "扳机键"], [booster, boost_idx, "摩擦轮开关键"]]:
			if pair[1] in ARROW_KEY_INDICES:
				issues.append({"type": "Error",
					"msg": "方向键已被设为「%s」，但%s也使用了方向键「%s」，二者不能相同"
						% [arrow_label, pair[2], pair[0].get_item_text(pair[1])]})
	# B/C 键固定用于摩擦轮档位微调，不能再被扳机键/开关键占用
	for pair2 in [[trigger, trig_idx, "扳机键"], [booster, boost_idx, "摩擦轮开关键"]]:
		if pair2[1] in BOOSTER_LEVEL_KEY_INDICES:
			issues.append({"type": "Warn",
				"msg": "%s使用了「%s」，该键已固定用于摩擦轮转速档位微调"
					% [pair2[2], pair2[0].get_item_text(pair2[1])]})


# ------------------------------------------------------------------ 规则：IO 重复引用
# 规则：底盘同一侧（左前/左后 或 右前/右后）允许共用一个 IO；
# 异侧之间、以及与云台各 IO 之间不能共用。
# 注意：底盘/拨弹的选项文本是引脚对（"P74 P24"），云台是单引脚（"P74"），
# 必须先归一化成通信脚再比较，否则同一物理引脚的冲突检测不出来。
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
	# pin -> Array[{label, group}]
	var io_map: Dictionary = {}
	for entry in io_entries:
		var btn: Node = get_node_or_null(entry["path"])
		if not btn is OptionButton:
			continue
		var pin: String = _normalize_pin(_option_text(btn))
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
				_check_same_side_dir(issues, refs, pin3, only_group)
				continue
		# 否则视为冲突，列出全部引用位置
		var locs: Array = []
		for r in refs:
			locs.append(r["label"])
		issues.append({"type": "Error",
			"msg": "IO %s 被多次引用：%s" % [pin3, ", ".join(locs)]})


## 同侧共用一个 IO 时，两轮方向必须一致，否则实际只会生效后写入的那一个
func _check_same_side_dir(issues: Array, refs: Array, pin: String, side: String) -> void:
	if refs.size() < 2:
		return
	var dir_paths: Array = [P_L1_DIR, P_L2_DIR] if side == "left" else [P_R1_DIR, P_R2_DIR]
	var d1: String = _get_option_text(dir_paths[0])
	var d2: String = _get_option_text(dir_paths[1])
	if d1 != d2:
		issues.append({"type": "Warn",
			"msg": "%s 侧两轮共用 IO %s 但方向不同（%s / %s），实际只有一个方向生效"
				% ["左" if side == "left" else "右", pin, d1, d2]})


## 把 OptionButton 文本归一化为通信脚名："P74 P24" -> "P74"，"MP74" 保持原样
func _normalize_pin(text: String) -> String:
	var parts: PackedStringArray = text.strip_edges().split(" ", false)
	if parts.size() > 0:
		return parts[0]
	return text.strip_edges()


# ------------------------------------------------------------------ 规则：摩擦轮引脚 / 驱动类型
# 文档约束：P64/P66 固定用于两路摩擦轮
#   - Yaw/Pitch 若选 P64/P66 -> Error（与摩擦轮冲突）
const FRICTION_PINS: Array = ["P64", "P66"]
# 扩展板引脚（通过 ExpansionBoradControl 控制）
# 文档明确写: 电机所有端口都可以作为舵机使用，初始化频率 50=舵机，10000=电机
const EXPANSION_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
# 主控板上仅有的两个舵机端口，只能驱动舵机，且与扩展板 P74 不是同一个 IO
const MAIN_SERVO_PINS: Array = ["MP74", "MP03"]

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
		var pin: String = _normalize_pin(_option_text(io_btn))
		var drive: String = _option_text(drive_btn)
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
	var yaw_io: String = _normalize_pin(_get_option_text(P_YAW_IO))
	var pitch_io: String = _normalize_pin(_get_option_text(P_PITCH_IO))
	if yaw_io == pitch_io:
		issues.append({"type": "Error",
			"msg": "Yaw 和 Pitch 使用了相同的引脚 %s" % yaw_io})
	# 归中角是相对舵机中位的偏移角，行程 ±90°，仅在对应轴用舵机时有意义
	if _get_option_text(P_YAW_DRIVE) == "舵机":
		_check_int_field(issues, P_YAW_MID_OFFSET, "Yaw 归中角",
			- SERVO_MAX_ANGLE, SERVO_MAX_ANGLE)
	if _get_option_text(P_PITCH_DRIVE) == "舵机":
		_check_int_field(issues, P_PITCH_MID_OFFSET, "Pitch 归中角",
			- SERVO_MAX_ANGLE, SERVO_MAX_ANGLE)


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
	cfg["arrow_key"] = _option_text(arrow) if arrow is OptionButton else "移动"
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
	for pin in EXPANSION_PINS:
		io_init[pin] = _get_option_text(NodePath(ENG_IO_PATHS[pin]))
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
		# 目标为「不使用」时归一成空串，下游据此跳过该行
		var target_text: String = _option_text(target_btn)
		if target_text == "不使用":
			target_text = ""
		key_map.append({
			"input": ENG_KEY_LABELS[i],
			"dir": _option_text(dir_btn),
			"mode": _option_text(mode_btn),
			"param": param_text,
			"target": target_text,
		})
	cfg["key_map"] = key_map
	return cfg


## 读取 OptionButton 当前项文本。
## selected 为 -1（场景未写 selected 属性）时回退到第 0 项，
## 避免 get_item_text(-1) 抛 "Index p_idx = -1 is out of bounds"。
func _option_text(btn: OptionButton) -> String:
	if btn == null or btn.item_count <= 0:
		return ""
	var idx: int = btn.selected
	if idx < 0 or idx >= btn.item_count:
		idx = 0
	return btn.get_item_text(idx)


## 获取 OptionButton 当前选中的文本
func _get_option_text(path: NodePath) -> String:
	var btn: Node = get_node_or_null(path)
	if btn is OptionButton:
		return _option_text(btn)
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


## 工具链管理器（惰性创建，日志接到 Output 框）
## 部署/探测/TOOLS.INI/编译等实现见 scripts/toolchain.gd，与 AI 编辑器共用
func _toolchain():
	if _tc == null:
		_tc = TC.new(_append_output)
	return _tc


## 根据当前 Tab 获取项目部署路径
## 注：Tab 1=工程；Tab 2(逆解算) 也是工程构型，但历史实现只认 Tab 1，
## 会把逆解算代码送去步兵工程编译。此为既有行为，另行确认后再改。
func _get_current_project_dst() -> String:
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var current_tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	if current_tab == 1:
		return TC.PROJECT_ENGINEER_DST
	return TC.PROJECT_DST


## 编译按钮回调：解压工具链 -> 写盘 -> 生成 TOOLS.INI -> 异步编译
func _on_build_pressed() -> void:
	if _build_busy:
		return # 防重入
	# 0) 确保工具链和项目模板已解压到 user://
	_clear_output()
	if not _toolchain().ensure_deployed():
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
	# 2) 写入磁盘（user://stc32g/Projects/<构型>/USER/src/main.c）
	if not _toolchain().write_main_c(_get_current_project_dst(), code):
		_append_output("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
		return
	# 3) 探测编译器
	var uv4_abs: String = _toolchain().find_uv4()
	if uv4_abs.is_empty():
		_append_output("[Error] 未在 user://keil/ 找到 uVision.com / UV4.exe")
		_append_output("       请尝试删除 user://keil/ 后重新编译（触发重新解压）")
		return
	# 3.1) 生成 TOOLS.INI（动态写入绝对路径）
	if not _toolchain().generate_tools_ini():
		_append_output("[Warn] TOOLS.INI 生成失败，编译可能报错")
	# 4) 启动异步编译
	_build_busy = true
	var btn: Node = get_node_or_null(P_BUILD_BTN)
	if btn is BaseButton:
		btn.disabled = true
		btn.text = "编译中…"
	_append_output("正在编译…（已写入 main.c，调用 Keil 编译器）")
	_build_thread = Thread.new()
	var err: int = _build_thread.start(
		_build_worker.bind(uv4_abs, _get_current_project_dst()))
	if err != OK:
		_build_busy = false
		if btn is BaseButton:
			btn.disabled = false
			btn.text = "编译"
		_append_output("[Error] 无法启动编译线程（错误码 %d）" % err)


## 编译工作线程：执行 Keil 编译器 -b，读日志，完成后回主线程
## 注意：子线程禁止访问 UI 节点，结果通过 call_deferred 传递
func _build_worker(uv4_abs: String, project_dst: String) -> void:
	var result: Dictionary = _toolchain().build_sync(uv4_abs, project_dst)
	call_deferred("_on_build_finished", result)


## AI 编辑入口：把当前生成的 main.c 落盘，记录上下文后切场景
## 注意：第一期不序列化图形化配置，返回后配置控件会回到默认值
func _on_ai_edit_pressed() -> void:
	_clear_output()
	if not _toolchain().ensure_deployed():
		_append_output("[Error] 工具链初始化失败，无法进入 AI 编辑")
		return
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = ""
	if code_edit is CodeEdit:
		code = code_edit.text
	if code.strip_edges().is_empty():
		_run_check()
		if code_edit is CodeEdit:
			code = code_edit.text
	if code.strip_edges().is_empty():
		_append_output("[Error] 没有可编辑的代码，请先完成配置")
		return
	var project_dst: String = _get_current_project_dst()
	if not _toolchain().write_main_c(project_dst, code):
		_append_output("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
		return
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	var kind: String = "engineer" if project_dst == TC.PROJECT_ENGINEER_DST else "infantry"
	AppState.set_context(project_dst, kind, tab)
	get_tree().change_scene_to_file(AI_EDIT_SCENE)


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

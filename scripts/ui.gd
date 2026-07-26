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
## 关节数下拉（选项 0..4 对应 2..6 个关节）。
## 旧版是「2轴/3轴/4轴」固定构型，现在轴类型由各关节自己选。
const P_IK_CONFIG_TYPE: NodePath = IK + "/ConfigType/OptionButton"
## 关节数上下限（上限依据 STC32G 浮点预算实测，见 CodeGenEngineerIK.MAX_JOINTS）
const IK_MIN_JOINTS: int = 2
const IK_MAX_JOINTS: int = 6
# 关节行（Joint1~Joint4），每行子节点：IO/Dir/Zero/Min/Max
const IK_JOINT_ROWS: Array = ["Joint1", "Joint2", "Joint3", "Joint4",
	"Joint5", "Joint6"]
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
# 图形化配置区根节点（配置序列化的遍历起点）
const P_EDIT_ZONE: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone"
# 顶栏按钮
const P_BUILD_BTN: NodePath = "VBoxContainer/TopPanel/Build"
# 项目管理按钮
const P_CREATE_BTN: NodePath = "VBoxContainer/TopPanel/Create"
const P_OPEN_BTN: NodePath = "VBoxContainer/TopPanel/Open"
const P_SAVE_BTN: NodePath = "VBoxContainer/TopPanel/Save"
# 顶栏标题（显示 项目名 · 构型 · 阶段）
const P_TITLE_LABEL: NodePath = "VBoxContainer/TopPanel/Label"
# 无项目时需要禁用的按钮（只留 新建 / 打开 可用）
const PROJECT_GATED_BTNS: Array = [
	"VBoxContainer/TopPanel/Save",
	"VBoxContainer/TopPanel/Export",
	"VBoxContainer/TopPanel/Button",
	"VBoxContainer/TopPanel/AIEdit",
	"VBoxContainer/TopPanel/ArmSim",
	"VBoxContainer/TopPanel/Build",
]
# AI 编辑入口（跳转到 code_edit.tscn）
const P_AI_EDIT_BTN: NodePath = "VBoxContainer/TopPanel/AIEdit"
# AI 代码编辑器场景
const AI_EDIT_SCENE: String = "res://scenes/code_edit.tscn"
# 启动页（新建 / 打开项目都在那里做）
const LAUNCHER_SCENE: String = "res://scenes/launcher.tscn"
# 3D 仿真入口
const P_ARM_SIM_BTN: NodePath = "VBoxContainer/TopPanel/ArmSim"
# 3D 仿真场景（作为子节点覆盖显示，避免切场景丢失整页配置状态）
const ARM_SIM_SCENE: String = "res://scenes/arm_sim.tscn"
## 步兵整车仿真（底盘 / 云台 / 发射），入口与机械臂仿真共用顶栏按钮
const INFANTRY_SIM_SCENE: String = "res://scenes/infantry_sim.tscn"
# 注：工具链路径常量与部署/编译实现已迁到 scripts/toolchain.gd，与 AI 编辑器共用
# 用 preload 而非 class_name：headless / 首次导入时全局类名缓存可能尚未建立
const TC = preload("res://scripts/toolchain.gd")
# 项目文件（.pieproj）读写与「项目类型 <-> Tab」映射表
const PF = preload("res://scripts/project_file.gd")


# ------------------------------------------------------------------ 生命周期
var _build_thread: Thread = null
var _build_busy: bool = false
# 当前选中的代码生成器（随 Tab 切换）
var _codegen: CodeGenBase = null
# 工具链管理器（惰性创建，见 _toolchain()）
var _tc = null
# 当前打开的 3D 仿真视图实例（null 表示未打开）
var _arm_sim: Control = null

# --- 项目状态 ---
## 当前 .pieproj 数据（见 project_file.gd），无项目时为空字典
var _project: Dictionary = {}
## 场景初始状态的配置快照，新建项目时用它把控件恢复成默认值
var _default_config: Dictionary = {}
## 正在批量回填配置：期间抑制检查与「用户改动」判定
var _loading: bool = false
## 有未保存的改动
var _dirty: bool = false
## 阶段二的只读预览态：任何配置改动都会先回滚再弹确认
var _stage2_preview: bool = false
## 阶段二回滚用的基准配置（已与默认值合并过，缺项也能回滚干净）
var _frozen_config: Dictionary = {}
## 已经弹过「继续修改将丢弃 AI 代码」确认框，避免连点堆叠弹窗
var _discard_dialog_open: bool = false


func _ready() -> void:
	# 为 C 代码预览框挂载语法高亮器（状态机正则）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		var hl: SyntaxHighlighter = preload("res://scripts/c_highlighter.gd").new()
		code_edit.syntax_highlighter = hl
	# 场景刚实例化，此刻的控件值就是「默认配置」，新建项目时用它复位
	_default_config = _snapshot_config()
	# 初始化调试界面占位提示
	_update_debug_placeholders()
	# 初始化工程界面参数框占位提示
	_update_engineer_placeholders()
	# 按默认关节数显隐逆解界面的关节行
	_update_ik_joint_rows()
	_connect_signals()
	# 恢复 / 初始化项目上下文（会自行触发 _run_check）
	_restore_project_context()


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
	# 3D 仿真入口
	var sim_btn: Node = get_node_or_null(P_ARM_SIM_BTN)
	if sim_btn is BaseButton:
		sim_btn.pressed.connect(_on_arm_sim_pressed)
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
	# 工程逆解算界面：摇杆映射变化触发检查
	for p in [P_IK_JOY_X, P_IK_JOY_Y, P_IK_JOY_Z]:
		var ik_opt: Node = get_node_or_null(p)
		if ik_opt is OptionButton:
			ik_opt.item_selected.connect(_run_check)
	# 关节数变化：除了重跑检查，还要显隐对应的关节行
	var jc_btn: Node = get_node_or_null(P_IK_CONFIG_TYPE)
	if jc_btn is OptionButton:
		jc_btn.item_selected.connect(_on_ik_joint_count_changed)
	for p in [P_IK_JOY_SCALE, P_IK_KEYMOVE_SPEED]:
		var ik_le: Node = get_node_or_null(p)
		if ik_le is LineEdit:
			ik_le.text_changed.connect(_run_check)
	# 工程逆解算界面：各关节 IO/方向/转轴变化触发检查
	for row_name in IK_JOINT_ROWS:
		for child in ["IO", "Dir", "Axis"]:
			var joint_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/"+ child))
			if joint_btn is OptionButton:
				joint_btn.item_selected.connect(_run_check)
	# 工程逆解算界面：各关节输入框文本变化触发检查
	for row_name in IK_JOINT_ROWS:
		for child in ["Len", "Offset", "Zero", "Min", "Max"]:
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
	# 项目管理按钮
	var create_btn: Node = get_node_or_null(P_CREATE_BTN)
	if create_btn is BaseButton:
		create_btn.pressed.connect(_on_create_pressed)
	var open_btn: Node = get_node_or_null(P_OPEN_BTN)
	if open_btn is BaseButton:
		open_btn.pressed.connect(_on_open_pressed)
	var save_btn: Node = get_node_or_null(P_SAVE_BTN)
	if save_btn is BaseButton:
		save_btn.pressed.connect(_on_save_pressed)
	# 配置区所有控件统一挂一个「改动」监听，用于脏标记与阶段二锁定。
	# 走通用遍历而非逐个列举：上面那些 _run_check 连接是按语义挑的，
	# 这里要的是「任何控件动了」，漏一个就会让脏标记或锁定失效。
	_connect_config_watchers()


# ==================================================================
# 配置序列化
# ==================================================================
## 递归收集 EditZone 下所有输入控件的当前值。
## key 用「相对 EditZone 的节点路径」，加控件不用改这里；
## 但重命名已有节点会让旧存档对不上（届时该项按缺失处理，回落默认值）。
func _snapshot_config() -> Dictionary:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	var out: Dictionary = {}
	if zone == null:
		return out
	_snapshot_node(zone, zone, out)
	return out


func _snapshot_node(node: Node, zone: Node, out: Dictionary) -> void:
	for child in node.get_children():
		var value: Variant = _control_value(child)
		if value != null:
			out[str(zone.get_path_to(child))] = value
		_snapshot_node(child, zone, out)


## 取单个控件的可序列化值，非输入控件返回 null。
## OptionButton 同时存索引和文本：选项顺序变了还能按文本找回。
func _control_value(node: Node) -> Variant:
	if node is OptionButton:
		return {"i": _option_index(node), "s": _option_text(node)}
	if node is LineEdit:
		return {"t": node.text}
	if node is BaseButton and node.toggle_mode:
		return {"b": node.button_pressed}
	return null


## OptionButton 的有效索引。场景没写 selected 属性时它是 -1，
## 但界面显示的是第 0 项（_option_text 也按第 0 项回退）。
## 存 -1 会让「快照 -> 回填 -> 再快照」得到 0 而对不上，故这里统一归一化。
func _option_index(btn: OptionButton) -> int:
	if btn.item_count <= 0:
		return -1
	var idx: int = btn.selected
	if idx < 0 or idx >= btn.item_count:
		return 0
	return idx


## 把配置写回控件。期间 _loading = true，抑制检查与改动判定，
## 否则上百个控件的信号会触发上百次全量检查 + 代码生成。
func _apply_config(cfg: Dictionary) -> void:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	if zone == null:
		return
	_loading = true
	for key in cfg.keys():
		var node: Node = zone.get_node_or_null(NodePath(str(key)))
		if node == null:
			continue
		_apply_control_value(node, cfg[key])
	_loading = false
	_update_debug_placeholders()
	_update_engineer_placeholders()
	_run_check()


func _apply_control_value(node: Node, value: Variant) -> void:
	if not value is Dictionary:
		return
	var v: Dictionary = value
	if node is OptionButton:
		# 先按文本匹配，失败再回退索引（并钳到合法范围，避免 selected=-1 的坑）
		var text: String = str(v.get("s", ""))
		var matched: bool = false
		for i in range(node.item_count):
			if node.get_item_text(i) == text:
				node.selected = i
				matched = true
				break
		if not matched and v.has("i"):
			var idx: int = int(v["i"])
			if idx >= 0 and idx < node.item_count:
				node.selected = idx
	elif node is LineEdit:
		node.text = str(v.get("t", ""))
	elif node is BaseButton and node.toggle_mode:
		node.button_pressed = bool(v.get("b", false))


## 给配置区所有输入控件挂「改动」监听（脏标记 + 阶段二锁定）
func _connect_config_watchers() -> void:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	if zone == null:
		return
	_watch_node(zone)


func _watch_node(node: Node) -> void:
	for child in node.get_children():
		if child is OptionButton:
			child.item_selected.connect(_on_config_touched.unbind(1))
		elif child is LineEdit:
			child.text_changed.connect(_on_config_touched.unbind(1))
		elif child is BaseButton and child.toggle_mode:
			child.toggled.connect(_on_config_touched.unbind(1))
		_watch_node(child)


## 任一配置控件被改动。阶段二要先回滚再问用户，其余情况只打脏标记。
func _on_config_touched() -> void:
	if _loading:
		return
	if _stage2_preview:
		_prompt_discard_ai_code()
		return
	_mark_dirty()


func _mark_dirty() -> void:
	if _dirty:
		return
	_dirty = true
	_update_title()


# ==================================================================
# 项目生命周期（新建 / 打开 / 保存）
# ==================================================================
## 启动或从 AI 编辑器返回时恢复项目上下文。
##
## 没有项目上下文时**保持老的自由编辑行为**（全部 Tab 可见、控件可编辑）。
## 正常流程一定从 launcher.tscn 带着项目进来，走到这个分支只有两种情况：
## 开发时直接运行 ui.tscn，或项目文件读不出来。两种都不该把界面锁死。
func _restore_project_context() -> void:
	# 在 AI 编辑器里点了「新建 / 打开」：直接回启动页
	var pending: String = AppState.take_pending_action()
	if pending == "create" or pending == "open":
		_go_to_launcher()
		return
	if not AppState.has_project():
		_apply_no_project_state()
		return
	var res: Dictionary = PF.load_from(AppState.project_path)
	if not res["ok"]:
		AppState.reset()
		_apply_no_project_state()
		_append_output("[Error] 无法读取项目：%s" % res["err"])
		return
	_adopt_project(res["data"], AppState.project_path)
	if AppState.stage >= 2:
		# 阶段二回到图形化界面：只能预览
		_notify_stage2_preview()


## 无项目上下文时的界面状态 = 老的自由编辑模式。
## 不禁用任何东西，只是标题上说明一下、编译等操作退化成按 Tab 猜构型。
func _apply_no_project_state() -> void:
	_project = {}
	_stage2_preview = false
	_dirty = false
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	if tab_container is TabContainer:
		for i in range(tab_container.get_tab_count()):
			tab_container.set_tab_hidden(i, false)
	_set_gated_buttons_disabled(false)
	_set_config_enabled(true)
	_update_title()
	_run_check()


func _set_gated_buttons_disabled(disabled: bool) -> void:
	for path in PROJECT_GATED_BTNS:
		var btn: Node = get_node_or_null(NodePath(path))
		if btn is BaseButton:
			btn.disabled = disabled


## 整个配置区可否编辑（无项目时全部禁用）
func _set_config_enabled(enabled: bool) -> void:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	if zone != null:
		_set_node_tree_enabled(zone, enabled)


func _set_node_tree_enabled(node: Node, enabled: bool) -> void:
	for child in node.get_children():
		if child is LineEdit:
			child.editable = enabled
		elif child is BaseButton:
			child.disabled = not enabled
		_set_node_tree_enabled(child, enabled)


## 把一份项目数据装载进界面
func _adopt_project(data: Dictionary, path: String) -> void:
	_project = data
	var kind: String = str(data["kind"])
	AppState.project_path = path
	AppState.project_kind = kind
	AppState.stage = int(data["stage"])
	AppState.project_dst = AppState.project_dst_for_kind(kind)
	AppState.source_tab = int(data["active_tab"])
	_set_gated_buttons_disabled(false)
	_set_config_enabled(true)
	_apply_kind_visibility(kind, int(data["active_tab"]))
	# 配置回填：缺项由默认值兜底，避免旧存档少字段时控件停在上个项目的值
	var cfg: Dictionary = _default_config.duplicate(true)
	cfg.merge(data["config"] as Dictionary, true)
	_apply_config(cfg)
	_frozen_config = cfg
	_stage2_preview = int(data["stage"]) >= 2
	_dirty = false
	_update_title()


## 按项目类型隐藏无关的 Tab（类型不可转换的第二道保证）
func _apply_kind_visibility(kind: String, want_tab: int) -> void:
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	if not tab_container is TabContainer:
		return
	var allowed: Array = PF.kind_tabs(kind)
	for i in range(tab_container.get_tab_count()):
		tab_container.set_tab_hidden(i, not i in allowed)
	# current_tab 指向隐藏页会显示空白，必须落在可见页上
	var target: int = want_tab if want_tab in allowed else PF.kind_default_tab(kind)
	if target < tab_container.get_tab_count():
		tab_container.current_tab = target


## 顶栏标题：* 项目名 · 构型 · 阶段
func _update_title() -> void:
	var label: Node = get_node_or_null(P_TITLE_LABEL)
	if not label is Label:
		return
	if _project.is_empty():
		label.text = "未打开项目（自由编辑）"
		return
	var kind: String = str(_project["kind"])
	var stage: int = int(_project["stage"])
	label.text = "%s%s · %s · %s" % [
		"*" if _dirty else "",
		PF.display_name(AppState.project_path),
		PF.kind_label(kind),
		PF.stage_label(stage),
	]


# ------------------------------------------------------------------ 新建 / 打开
## 新建与打开都在启动页（launcher.tscn）里做，这里只负责回去。
## 项目管理与图形化配置分层，主界面不必关心项目从哪来。
func _on_create_pressed() -> void:
	_confirm_discard_unsaved(_go_to_launcher)


func _on_open_pressed() -> void:
	_confirm_discard_unsaved(_go_to_launcher)


func _go_to_launcher() -> void:
	get_tree().change_scene_to_file(LAUNCHER_SCENE)


## 在当前界面直接创建项目。仅供测试与直跑本场景时用，
## 正常流程走 launcher.tscn。
func _create_project_at(kind: String, path: String) -> bool:
	var data: Dictionary = PF.new_data(kind)
	# 新项目从场景默认值开始
	data["config"] = _default_config.duplicate(true)
	var res: Dictionary = PF.save_to(path, data)
	if not res["ok"]:
		_clear_output()
		_append_output("[Error] 新建失败：%s" % res["err"])
		return false
	AppState.reset()
	_adopt_project(data, path)
	_clear_output()
	_append_output("已新建%s项目：%s" % [PF.kind_label(kind), path])
	# 生成一次代码并回写，让 .pieproj 里立刻有阶段一产物
	_save_project(false)
	return true


# ------------------------------------------------------------------ 保存
func _on_save_pressed() -> void:
	if _project.is_empty():
		_clear_output()
		_append_output("[Warn] 当前没有项目，请回到启动页新建或打开")
		return
	_save_project(true)


## 写回 .pieproj。阶段一同时刷新配置快照与 main_c_stage1；
## 阶段二只在这里保存不覆盖 AI 代码（main_c_ai 归 code_edit.tscn 管），
## 且 config 保持阶段一冻结的那份不动。
func _save_project(verbose: bool) -> void:
	if _project.is_empty() or AppState.project_path.is_empty():
		return
	if int(_project["stage"]) < 2:
		_project["config"] = _snapshot_config()
		_project["main_c_stage1"] = _current_preview_code()
		var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
		if tab_container is TabContainer:
			_project["active_tab"] = tab_container.current_tab
	var res: Dictionary = PF.save_to(AppState.project_path, _project)
	if not res["ok"]:
		_append_output("[Error] 保存失败：%s" % res["err"])
		return
	_dirty = false
	_update_title()
	if verbose:
		_append_output("已保存项目：%s" % AppState.project_path)


## 取 CodeEdit 里当前的 C 代码预览；为空时先跑一次生成
func _current_preview_code() -> String:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = ce.text if ce is CodeEdit else ""
	if code.strip_edges().is_empty():
		_run_check()
		code = ce.text if ce is CodeEdit else ""
	return code


# ------------------------------------------------------------------ 对话框
## 有未保存改动时先问一句，再执行后续动作
func _confirm_discard_unsaved(then: Callable) -> void:
	if not _dirty or _project.is_empty():
		then.call()
		return
	var dlg := ConfirmationDialog.new()
	dlg.title = "未保存的修改"
	dlg.dialog_text = "当前项目有未保存的修改。继续将丢弃这些修改。"
	dlg.get_ok_button().text = "丢弃并继续"
	dlg.get_cancel_button().text = "返回"
	dlg.confirmed.connect(func() -> void:
		_dirty = false
		then.call())
	add_child(dlg)
	dlg.popup_centered()
	dlg.close_requested.connect(dlg.queue_free)


# ------------------------------------------------------------------ 阶段二锁定
## 阶段二回到图形化界面时的一次性说明
func _notify_stage2_preview() -> void:
	_append_output("[Warn] 阶段二：图形化配置仅供预览，修改会丢弃 AI 编辑的代码")
	var dlg := AcceptDialog.new()
	dlg.title = "只能预览"
	dlg.dialog_text = "该项目已进入 AI 编辑阶段。\n"\
		+ "这里的图形化配置只能预览，不能更改。\n"\
		+ "如果在这里更改，AI 编辑的内容会丢失。\n"\
		+ "建议把想修改的地方直接告诉 AI。"
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(dlg.queue_free)
	dlg.close_requested.connect(dlg.queue_free)


## 阶段二被改动：先整份回滚，再问是否降回阶段一。
## 必须整份重放而不是逐控件撤销 —— LineEdit 的 text_changed 拿不到旧值。
func _prompt_discard_ai_code() -> void:
	if _discard_dialog_open:
		return
	_discard_dialog_open = true
	_apply_config(_frozen_config)
	var dlg := ConfirmationDialog.new()
	dlg.title = "确认修改图形化配置"
	dlg.dialog_text = "继续修改将丢弃 AI 编辑的代码，项目回到图形化配置阶段。\n"\
		+ "更稳妥的做法是把想改的地方告诉 AI。\n确定要继续吗？"
	dlg.get_ok_button().text = "丢弃 AI 代码并继续"
	dlg.get_cancel_button().text = "保持预览"
	dlg.confirmed.connect(_downgrade_to_stage1)
	var cleanup := func() -> void:
		_discard_dialog_open = false
		dlg.queue_free()
	dlg.confirmed.connect(cleanup)
	dlg.canceled.connect(cleanup)
	dlg.close_requested.connect(cleanup)
	add_child(dlg)
	dlg.popup_centered()


## 阶段二 -> 阶段一。这是唯一的降阶入口，代价是丢弃 AI 代码。
func _downgrade_to_stage1() -> void:
	_project["stage"] = 1
	_project["main_c_ai"] = ""
	AppState.stage = 1
	_stage2_preview = false
	_dirty = true
	_save_project(false)
	_clear_output()
	_append_output("已回到阶段一，AI 编辑的代码已丢弃")
	_run_check()


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
## 下拉选项索引 -> 关节数。0 对应 2 个关节，以此类推至 6。
func _ik_joint_count(idx: int) -> int:
	return clampi(idx + IK_MIN_JOINTS, IK_MIN_JOINTS, IK_MAX_JOINTS)


## 关节数变化：显隐关节行后重跑检查
func _on_ik_joint_count_changed(_idx: int = -1) -> void:
	_update_ik_joint_rows()
	_run_check()


## 只显示当前关节数用到的关节行。多余的行留在场景里但隐藏，
## 这样切换关节数时用户已填的内容不会丢。
func _update_ik_joint_rows() -> void:
	var btn: Node = get_node_or_null(P_IK_CONFIG_TYPE)
	var jc: int = _ik_joint_count(btn.selected if btn is OptionButton else 1)
	for i in range(IK_JOINT_ROWS.size()):
		var row: Node = get_node_or_null(NodePath(IK + "/" + IK_JOINT_ROWS[i]))
		if row is Control:
			row.visible = i < jc


## 收集工程逆解算界面配置，返回字典供代码生成使用
func _collect_ik_config() -> Dictionary:
	var cfg: Dictionary = {}
	var type_btn: Node = get_node_or_null(P_IK_CONFIG_TYPE)
	var type_idx: int = type_btn.selected if type_btn is OptionButton else 1
	var jc: int = _ik_joint_count(type_idx)
	cfg["joint_count"] = jc
	# config_type 仅供旧解析路径与 axis/len 缺失时的兼容推断，
	# 不再决定构型：轴类型由各关节自己选
	cfg["config_type"] = clampi(jc - 2, 0, 2)
	# 各关节配置
	var joints: Array = []
	for i in range(jc):
		var row_name: String = IK_JOINT_ROWS[i]
		var io_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/IO"))
		var dir_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Dir"))
		var axis_btn: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Axis"))
		var len_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Len"))
		var off_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Offset"))
		var zero_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Zero"))
		var min_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Min"))
		var max_le: Node = get_node_or_null(NodePath(IK +"/"+ row_name +"/Max"))
		joints.append({
			"io": _option_text(io_btn) if io_btn is OptionButton else "P60",
			"dir": _option_text(dir_btn) if dir_btn is OptionButton else "正向",
			# 转轴类型：Pitch=上下俯仰 / Yaw=左右摆动 / Roll=绕连杆自转
			"axis": _option_text(axis_btn) if axis_btn is OptionButton else "",
			# 该关节到下一关节的连杆长度（mm）；最后一个关节填到夹爪的距离
			"len": (len_le.text.strip_edges() if len_le is LineEdit else ""),
			# 安装中位朝向（运动学角）：空白视为 0，即中位与参考方向共线
			"offset": (off_le.text.strip_edges() if off_le is LineEdit else ""),
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
	# 各关节限位与初始角（全部是运动学角，即连杆实际朝向）
	var joints: Array = cfg["joints"]
	for i in range(joints.size()):
		var j: Dictionary = joints[i]
		var min_s: String = j.get("min", "")
		var max_s: String = j.get("max", "")
		var zero_s: String = j.get("zero", "")
		# 安装中位朝向：舵机中位时该关节的运动学角。空白视为 0（中位与参考方向共线）
		var off_s: String = j.get("offset", "")
		var off_v: float = 0.0
		if not off_s.is_empty():
			if not off_s.is_valid_float():
				issues.append({"type": "Error",
					"msg": "工程逆解算 关节%d 中位朝向「%s」不是合法数值" % [i + 1, off_s]})
			else:
				off_v = off_s.to_float()
		# 舵机行程以中位朝向为中心 ±90°
		var travel_lo: float = off_v + IK_ANGLE_MIN
		var travel_hi: float = off_v + IK_ANGLE_MAX
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
		# 限位必须落在舵机能到达的行程内，否则超出部分会被钳到端点
		if min_v < travel_lo or max_v > travel_hi:
			issues.append({"type": "Warn",
				"msg": "工程逆解算 关节%d 限位 [%.1f, %.1f] 超出舵机行程 [%.1f, %.1f]（中位朝向 %.1f° ±90°），超出部分会被钳到端点"
					% [i + 1, min_v, max_v, travel_lo, travel_hi, off_v]})
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
	# 批量回填配置期间不检查：上百个控件的信号会触发上百次全量检查 + 代码生成
	if _loading:
		return
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


func _set_line_text(path: NodePath, text: String) -> void:
	var node: Node = get_node_or_null(path)
	if node is LineEdit:
		node.text = text


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


## 获取项目部署路径。
## 按**项目类型**判定而非当前 Tab：工程与工程逆解算同属工程项目，
## 都应送去 ROBOMASTER_ENGINEER 模板编译（旧实现只认 Tab 1，
## 会把逆解算代码送进步兵工程）。
func _get_current_project_dst() -> String:
	if not _project.is_empty():
		return AppState.project_dst_for_kind(str(_project["kind"]))
	# 没有项目时（直接运行本场景）退化成按 Tab 猜
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var current_tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	return AppState.project_dst_for_kind(PF.tab_to_kind(current_tab))


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


## AI 编辑入口（阶段一 -> 阶段二）。
## 进入前先把阶段一的配置与生成代码冻结进 .pieproj，这一步不可逆：
## 之后图形化配置只能预览，降回阶段一必须显式丢弃 AI 代码。
func _on_ai_edit_pressed() -> void:
	_clear_output()
	if not _toolchain().ensure_deployed():
		_append_output("[Error] 工具链初始化失败，无法进入 AI 编辑")
		return
	var code: String = _current_preview_code()
	if code.strip_edges().is_empty():
		_append_output("[Error] 没有可编辑的代码，请先完成配置")
		return
	var project_dst: String = _get_current_project_dst()
	if not _toolchain().write_main_c(project_dst, code):
		_append_output("[Error] 写入 main.c 失败，请检查 user:// 目录权限")
		return
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	if _project.is_empty():
		# 无项目（直跑本场景）：只切场景，没有阶段概念
		AppState.set_context(project_dst, PF.tab_to_kind(tab), tab)
		get_tree().change_scene_to_file(AI_EDIT_SCENE)
		return
	# 冻结阶段一：配置快照 + 生成代码；AI 从这份代码起步
	if int(_project["stage"]) < 2:
		_project["config"] = _snapshot_config()
		_project["main_c_stage1"] = code
		_project["active_tab"] = tab
		_project["stage"] = 2
		_project["main_c_ai"] = code
	AppState.set_context(project_dst, str(_project["kind"]), tab)
	AppState.stage = 2
	_save_project(false)
	get_tree().change_scene_to_file(AI_EDIT_SCENE)


# ------------------------------------------------------------------ 3D 仿真
## 打开 3D 仿真，按当前 Tab 分派：
##   Tab 0（步兵）      -> 步兵整车仿真（底盘 / 云台 / 发射）
##   Tab 2（工程逆解算）-> 机械臂逆解仿真与标定台
## 用「加子节点覆盖」而非 change_scene_to_file：整页配置状态留在内存里，
## 返回时不需要重建任何控件。
func _on_arm_sim_pressed() -> void:
	if _arm_sim != null:
		return
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	var tab: int = tab_container.current_tab if tab_container is TabContainer else 0
	var scene_path: String = ""
	var cfg: Dictionary = {}
	match tab:
		0:
			scene_path = INFANTRY_SIM_SCENE
			cfg = _collect_config()
		2:
			scene_path = ARM_SIM_SCENE
			cfg = _collect_ik_config()
		_:
			_clear_output()
			_append_output("[Warn] 当前构型没有 3D 仿真，请切到「步兵」或「工程逆解算」标签页")
			return
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("无法加载 3D 仿真场景：%s" % scene_path)
		return
	var sim: Node = packed.instantiate()
	if not sim is Control:
		push_error("3D 仿真场景根节点不是 Control")
		return
	_arm_sim = sim
	_arm_sim.set_anchors_preset(Control.PRESET_FULL_RECT)
	if _arm_sim.has_signal("closed"):
		_arm_sim.closed.connect(_on_arm_sim_closed)
	# 仿真里改了参数时回填到配置界面（两种仿真回填的字段不同）
	if _arm_sim.has_signal("config_changed"):
		if tab == 0:
			_arm_sim.config_changed.connect(_on_infantry_sim_config_changed)
		else:
			_arm_sim.config_changed.connect(_on_arm_sim_config_changed)
	# set_config 在 add_child 之前调用，_ready 里会自行应用
	if _arm_sim.has_method("set_config"):
		_arm_sim.set_config(cfg)
	add_child(_arm_sim)


func _on_arm_sim_closed() -> void:
	if _arm_sim == null:
		return
	_arm_sim.queue_free()
	_arm_sim = null


## 步兵仿真里标定出来的云台归中角回填到配置界面，再重跑检查与代码生成
func _on_infantry_sim_config_changed(cfg: Dictionary) -> void:
	_set_line_text(P_YAW_MID_OFFSET, str(cfg.get("yaw_mid_offset", "")))
	_set_line_text(P_PITCH_MID_OFFSET, str(cfg.get("pitch_mid_offset", "")))
	_run_check()


## 把 3D 标定台里的编辑结果写回配置界面控件，再重跑检查与代码生成。
## 只回填仿真能改的字段，IO/方向/摇杆映射等仍由配置界面独占。
func _on_arm_sim_config_changed(cfg: Dictionary) -> void:
	var joints: Array = cfg.get("joints", [])
	for i in range(min(joints.size(), IK_JOINT_ROWS.size())):
		var row: String = IK_JOINT_ROWS[i]
		# 连杆长度现在是逐关节的（原 L1/L2/L3 已迁移）
		for field in [["Len", "len"], ["Offset", "offset"], ["Zero", "zero"],
				["Min", "min"], ["Max", "max"]]:
			var le: Node = get_node_or_null(NodePath(IK +"/"+ row +"/"+ field[0]))
			if le is LineEdit and joints[i].has(field[1]):
				le.text = str(joints[i].get(field[1], ""))
		# 转轴类型
		var ax: Node = get_node_or_null(NodePath(IK +"/"+ row +"/Axis"))
		if ax is OptionButton and joints[i].has("axis"):
			_select_option_by_text(ax, str(joints[i].get("axis", "")))
	var presets: Array = cfg.get("presets", [])
	for i in range(min(presets.size(), IK_PRESET_ROWS.size())):
		var prow: String = IK_PRESET_ROWS[i]
		var p: Dictionary = presets[i]
		# 未启用的点位一律清空，否则配置界面会把残留坐标当成已启用
		var on: bool = p.get("enabled", false)
		for field2 in [["X", "x"], ["Y", "y"], ["Z", "z"], ["Phi", "phi"]]:
			var ple: Node = get_node_or_null(NodePath(IK +"/"+ prow +"/"+ field2[0]))
			if ple is LineEdit:
				ple.text = str(p.get(field2[1], "")) if on else ""
		var key_btn: Node = get_node_or_null(NodePath(IK +"/"+ prow +"/Key"))
		if on and key_btn is OptionButton:
			_select_option_by_text(key_btn, str(p.get("key", "")))
	_run_check()


## 按显示文本选中 OptionButton 的对应项（找不到则保持原选择）
func _select_option_by_text(btn: OptionButton, text: String) -> void:
	if text.is_empty():
		return
	for i in range(btn.item_count):
		if btn.get_item_text(i) == text:
			btn.selected = i
			return


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

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
##   - 拨弹时间 > 1000ms（阻塞主循环）              -> Warn（仅「阻塞开环」模式）


# ------------------------------------------------------------------ 节点路径
# 遥控器
const P_CHANNEL: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/RemoteSetting/Channel/LineEdit"
const P_DEADZONE: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/RemoteSetting/DeadZone/LineEdit"
# 底盘
const P_L1_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/L1/OptionButton"
const P_L2_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/L2/OptionButton"
const P_R1_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/R1/OptionButton"
const P_R2_IO: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/R2/OptionButton"
const P_NORMAL_SPEED: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/Speed/LineEdit"
const P_SPRINT_SPEED: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/SprintSpeed/LineEdit"
# 冲刺开关放在 FirstRow/Chassis（步兵与工程共用底盘设置）
const P_SPRINT_CB: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/Sprint/CheckBox"
# 底盘方向（正向 id=0 / 反向 id=1）
const CHASSIS: String = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis"
const P_L1_DIR: NodePath = CHASSIS + "/L1/OptionButton2"
const P_L2_DIR: NodePath = CHASSIS + "/L2/OptionButton2"
const P_R1_DIR: NodePath = CHASSIS + "/R1/OptionButton2"
const P_R2_DIR: NodePath = CHASSIS + "/R2/OptionButton2"
# 云台（步兵）
const GIMBAL: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Infantry/GimbalSetting"
const P_BOOSTER_IO: NodePath = GIMBAL + "/Booster/OptionButton"
const P_BOOSTER_DIR: NodePath = GIMBAL + "/Booster/OptionButton2"
# 摩擦轮方向已删除 UI：Dir 固定发 0（实测拓展板协议方向位 1 会导致摩擦轮不转）
const P_YAW_DRIVE: NodePath = GIMBAL + "/Yaw/OptionButton"
const P_YAW_IO: NodePath = GIMBAL + "/Yaw/OptionButton2"
const P_YAW_DIR: NodePath = GIMBAL + "/Yaw/OptionButton3"
const P_PITCH_DRIVE: NodePath = GIMBAL + "/Pitch/OptionButton"
const P_PITCH_IO: NodePath = GIMBAL + "/Pitch/OptionButton2"
const P_PITCH_DIR: NodePath = GIMBAL + "/Pitch/OptionButton3"
const P_YAW_MID_OFFSET: NodePath = GIMBAL + "/Yaw/LineEdit"
const P_PITCH_MID_OFFSET: NodePath = GIMBAL + "/Pitch/LineEdit"
# 按键映射
const KEYSET: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Infantry/KeySetting"
const P_ZERO_CB: NodePath = KEYSET + "/Zero/CheckBox"
# 方向键用途选择（移动 / 冲刺 / 其他），是 OptionButton 而非 CheckBox
const P_ARROW_KEY: NodePath = KEYSET + "/ArrowKey/OptionButton"
# 拨弹模式选择（阻塞开环 / 目视闭环），目视闭环时隐藏拨弹时间输入框
const P_FEED_MODE: NodePath = KEYSET + "/FeedMode/OptionButton"
const P_TRIGGER: NodePath = KEYSET + "/Trigger/OptionButton"
const P_TRIGGER_SPEED: NodePath = KEYSET + "/Trigger/Speed"
const P_TRIGGER_TIME: NodePath = KEYSET + "/Trigger/Time"
const P_BOOSTER_KEY: NodePath = KEYSET + "/Booster/OptionButton"
# 调试界面
const DEBUG: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Debug"
# 调试界面各行容器名（P60, P62, P64, P66, P74, P75, P76, P77, MP03, MP74）
const DEBUG_ROWS: Array = [
	"HBoxContainer", "HBoxContainer2", "HBoxContainer3", "HBoxContainer4", "HBoxContainer5",
	"HBoxContainer6", "HBoxContainer7", "HBoxContainer8", "HBoxContainer9", "HBoxContainer10",
]
# 构型页：EditZone 下平铺三个 Control（按项目类型切换可见性，无外层 TabContainer）
const INFANTRY_PAGE: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Infantry"
const ENGINEER_TABS: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Engineer"
const DEBUG_PAGE: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Debug"
# 工程师界面（工程页：Engineer TabContainer 的第 0 个 tab）
const ENGINEER: String = ENGINEER_TABS + "/Engineer"
# 步兵页「高级设置」折叠区内的同一套 IO+模式+按键映射（与工程页共用同一份配置）
const ADV_ENGINEER: String = INFANTRY_PAGE + "/Advanced/ScrollContainer/AdvancedAndEngineer"
# 共享配置根：按当前构型返回 工程页 / 步兵高级设置
func _shared_cfg_root() -> String:
	return ADV_ENGINEER if _current_tab() == 0 else ENGINEER
# 共享 IO 初始化区相对路径（工程页与步兵高级设置结构一致）。
# 每个引脚一个 OptionButton(电机/舵机) + MidDegree2(初始角)。
const ENG_IO_REL: Dictionary = {
	"P60": "IOs/Row1/P60/OptionButton",
	"P62": "IOs/Row1/P62/OptionButton",
	"P64": "IOs/Row1/P64/OptionButton",
	"P66": "IOs/Row1/P66/OptionButton",
	"P74": "IOs/Row1/P74/OptionButton",
	"P75": "IOs/Row2/P75/OptionButton",
	"P76": "IOs/Row2/P76/OptionButton",
	"P77": "IOs/Row2/P77/OptionButton",
	"MP03": "IOs/Row2/MP03/OptionButton",
	"MP74": "IOs/Row2/MP74/OptionButton",
}
const ENG_IO_MID_REL: Dictionary = {
	"P60": "IOs/Row1/P60/MidDegree2",
	"P62": "IOs/Row1/P62/MidDegree2",
	"P64": "IOs/Row1/P64/MidDegree2",
	"P66": "IOs/Row1/P66/MidDegree2",
	"P74": "IOs/Row1/P74/MidDegree2",
	"P75": "IOs/Row2/P75/MidDegree2",
	"P76": "IOs/Row2/P76/MidDegree2",
	"P77": "IOs/Row2/P77/MidDegree2",
	"MP03": "IOs/Row2/MP03/MidDegree2",
	"MP74": "IOs/Row2/MP74/MidDegree2",
}
# IO 初始化区全部引脚（扩展板 + 主控板舵机口）
const ENG_ALL_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77", "MP03", "MP74"]
# 动态按键映射行控件名（io_and_key.tscn 每行结构）
const ENG_ROW_CONTROLS: Array = ["Key", "Dir", "Option", "Para", "IO", "Remove"]
# 模式配置相对路径
const ENG_MODE_COUNT: String = "Mode/OptionButton"
const ENG_MODE_SWITCH_KEY: String = "Mode/TabContainer/Change/OptionButton2"
const ENG_MODE_KEYS: Array = ["Key", "Key2", "Key3", "Key4"]
# 每模式按键映射页容器
const ENG_MODE_PAGES: Array = ["TabContainer/M1", "TabContainer/M2", "TabContainer/M3", "TabContainer/M4"]


func _eng_io_path(pin: String) -> String:
	return _shared_cfg_root() + "/" + str(ENG_IO_REL.get(pin, ""))


func _eng_io_mid_path(pin: String) -> String:
	return _shared_cfg_root() + "/" + str(ENG_IO_MID_REL.get(pin, ""))


# 工程逆解算界面（Engineer TabContainer 的第 1 个 tab）
const IK: String = ENGINEER_TABS + "/EngineerAdvanced"
const P_IK: NodePath = IK
const P_IK_SUMMARY: NodePath = IK + "/Summary"
const P_IK_OPEN_SIM: NodePath = IK + "/OpenSim"
const P_IK_ENABLE_CB: NodePath = IK + "/HBoxContainer/CheckButton"
const P_IK_PANEL_LABEL: NodePath = IK + "/Label"
# 工程内部 TabContainer（0=工程, 1=工程逆解算）；步兵/调试是平铺 Control
const P_TAB_CONTAINER: NodePath = ENGINEER_TABS
# 输出
const P_OUTPUT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output"
const P_CODE_EDIT: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit"
# 图形化配置区根节点（配置序列化的遍历起点）
const P_EDIT_ZONE: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone"
const P_FIRST_ROW: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow"
# 顶栏按钮
const P_BUILD_BTN: NodePath = "VBoxContainer/TopPanel/Build"
const P_DOWNLOAD_BTN: NodePath = "VBoxContainer/TopPanel/Download"
const P_HEX_EXPORT_BTN: NodePath = "VBoxContainer/TopPanel/HEXExport"
const P_BUILD_MODE: NodePath = "VBoxContainer/TopPanel/BuildMode"
const P_CLOUD_SETTINGS: NodePath = "VBoxContainer/TopPanel/Settings"
const P_UPGRADE_BTN: NodePath = "VBoxContainer/TopPanel/Upgrade"
const P_UPGRADE_PROGRESS: NodePath = "UpgradeProgress"
# 项目引导
const P_MAIN_UI: NodePath = "VBoxContainer"
const P_HARDWARE_GATE: NodePath = "HardwareGate"
const P_GATE_CONFIRM: NodePath = "HardwareGate/Center/Content/Actions/Confirm"
const P_GATE_BACK: NodePath = "HardwareGate/Center/Content/Actions/Back"
const P_PROJECT_GUIDE: NodePath = "VBoxContainer/HBoxContainer/ProjectGuide"
# 项目管理按钮
const P_CREATE_BTN: NodePath = "VBoxContainer/TopPanel/Create"
const P_OPEN_BTN: NodePath = "VBoxContainer/TopPanel/Open"
const P_SAVE_BTN: NodePath = "VBoxContainer/TopPanel/Save"
# 顶栏标题（显示 项目名 · 构型 · 阶段）
const P_TITLE_LABEL: NodePath = "VBoxContainer/TopPanel/Label"
# AI 功能开关（启用后才显示 AI 编辑按钮）
const P_ENABLE_AI_BTN: NodePath = "VBoxContainer/TopPanel/EnableAI"
# 无项目时需要禁用的按钮（只留 新建 / 打开 可用）
const PROJECT_GATED_BTNS: Array = [
	"VBoxContainer/TopPanel/Save",
	"VBoxContainer/TopPanel/Export",
	"VBoxContainer/TopPanel/Button",
	"VBoxContainer/TopPanel/AIEdit",
	"VBoxContainer/TopPanel/ArmSim",
	"VBoxContainer/TopPanel/Build",
	"VBoxContainer/TopPanel/Download",
	"VBoxContainer/TopPanel/HEXExport",
	"VBoxContainer/TopPanel/Upgrade",
]
# AI 编辑入口（跳转到 code_edit.tscn）
const P_AI_EDIT_BTN: NodePath = "VBoxContainer/TopPanel/AIEdit"
# AI 代码编辑器场景
const AI_EDIT_SCENE: String = "res://scenes/code_edit.tscn"
## AI 编辑功能总开关：false 时隐藏一切入口（EnableAI 开关与 AIEdit 按钮），
## 程序化触发也一律无效。置回 true 即可恢复原有入口与门禁流程。
const AI_EDIT_ENABLED: bool = false
const WARN_AI_SCENE: String = "res://scenes/warn_ai.tscn"
const WARN_IK_SCENE: String = "res://scenes/warn_ik.tscn"
const ERROR_SCENE: String = "res://scenes/error.tscn"
const FATAL_ERROR_SCENE: String = "res://scenes/fatal_error.tscn"
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
const BC = preload("res://scripts/build_controller.gd")
const DC = preload("res://scripts/download_controller.gd")
const UPGRADE_PROGRESS = preload("res://scripts/upgrade_progress.gd")
const KG = preload("res://scripts/keil_guide.gd")
## 首次烧录指引（烧录前确认板上开关已断开，可勾选「不再显示」）
const FFG = preload("res://scripts/first_flash_guide.gd")
## 云端编译核心与配置引导（preload 避免全局类名缓存未建立）
const CLOUD_COMPILER = preload("res://scripts/cloud_compiler.gd")
const CLOUD_GUIDE = preload("res://scripts/cloud_guide.gd")
# Web 平台工具（浏览器版功能禁用 / 文件下载）
const WEB = preload("res://scripts/web_support.gd")
## 构形诊断（判定末端可控自由度与俯仰角是否解耦）
# 项目文件（.pieproj）读写与「项目类型 <-> Tab」映射表
const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const SC = preload("res://scripts/static_checker.gd")


# ------------------------------------------------------------------ 生命周期
var _build_controller = null
var _download_controller = null
## 编译方式下拉（本地/云端）；null 表示场景里没有（不应发生）
var _build_mode: OptionButton = null
var _upgrade_active: bool = false
var _solver_upgrade_active: bool = false
## 「无法开始烧录（HID 未连接）」重试时要用到的编译产物路径与构型
var _retry_download_dst: String = ""
var _retry_is_solver: bool = false
var _project_dst_override: String = ""
## 正在走「导出 HEX」流程：编译成功回调改弹保存对话框而不是烧录
var _hex_export_pending: bool = false
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
## 工程逆解唯一状态源。主页面不再从 Tab 2 控件树拼装配置。
var _ik_config: Dictionary = {}
## 阶段二只读预览时用于恢复结构化逆解配置。
var _frozen_ik_config: Dictionary = {}
## 工程逆解系统门控是否已经确认
var _ik_confirmed: bool = false
## AI 功能是否已经启用
var _ai_enabled: bool = false
## 已经弹过「继续修改将丢弃 AI 代码」确认框，避免连点堆叠弹窗
var _discard_dialog_open: bool = false
## 最近一次静态检查的结果，进入 AI 编辑前的提示要拿它报问题数
var _last_issues: Array = []
const GUIDE_TITLES: Array[String] = [
	"项目与硬件确认", "配置遥控器", "配置执行机构", "检查与仿真",
	"升级主控板", "确认升级完成", "真机低速测试",
]
const GUIDE_HINTS: Array[String] = [
	"确认程序只烧录到主控板，绝不向机械扩展板烧录程序。",
	"填写遥控器通道号（0-125）和死区。不确定死区时可保持默认值 10。",
	"按机械接线配置底盘、云台、执行机构和按键。P74 是扩展板口，MP74 是主控板舵机口。",
	"修正“问题与输出”中的错误；步兵和机械臂项目建议再进入 3D 仿真检查方向。",
	"静态检查通过后升级：程序会先编译，再自动烧录到主控板。",
	"确认升级面板显示完成。这里只升级主控板，绝不要给机械扩展板烧录程序。",
	"架空底盘或拆下危险机构，逐个低速测试方向和停止功能，确认后完成项目。",
]


func _ready() -> void:
	# 移动端圆角屏/刘海：整屏内缩到安全区（桌面端恒为 0）
	SafeArea.apply_to_root(self)
	# 为 C 代码预览框挂载语法高亮器（状态机正则）
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		var hl: SyntaxHighlighter = preload("res://scripts/c_highlighter.gd").new()
		code_edit.syntax_highlighter = hl
	# 场景模板行保持隐藏（Example 仅作「+」新建行的原型），真实行命名为 RowNN
	_normalize_eng_row_names()
	# 固定子系统引脚在 IO 初始化区自动同步（须在默认快照之前，让默认配置自洽）
	_sync_io_locks()
	# 左摇杆保留开关：模式1 强制开启（须在默认快照之前，让默认配置自洽）
	_sync_chassis_switch()
	# 场景刚实例化，此刻的控件值就是「默认配置」，新建项目时用它复位
	_default_config = _snapshot_config()
	_ik_config = IK_CONFIG.default_config()
	# 初始化调试界面占位提示
	_update_debug_placeholders()
	# 初始化工程界面参数框占位提示
	_update_engineer_placeholders()
	_update_mode_page_visibility()
	_setup_guide()
	_setup_build_controller()
	_setup_download_controller()
	_connect_signals()
	# 恢复 / 初始化项目上下文（会自行触发 _run_check）
	_restore_project_context()
	# 顶栏「3D 仿真」按钮可见性跟随当前 Tab
	_update_sim_btn_visibility()
	# 无项目路径会整体重开配置区控件（_set_config_enabled），
	# 左摇杆保留开关的模式1强制状态必须最后再兜一次
	_sync_chassis_switch()


## 窗口尺寸/方向变化后重算安全区内缩（旋转屏幕、折叠屏展开等场景）。
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_SIZE_CHANGED:
		SafeArea.apply_to_root(self)

func _setup_build_controller() -> void:
	_build_controller = BC.new()
	add_child(_build_controller)
	_build_controller.configure(_toolchain(), _clear_output, _append_output)
	# 云端编译：注入 CloudCompiler（日志走同一输出），并创建「本地/云端」下拉与设置入口
	_build_controller.configure_cloud(CLOUD_COMPILER.new(_toolchain(), _append_output))
	_setup_build_mode_selector()
	_build_controller.busy_changed.connect(_on_build_busy_changed)
	_build_controller.succeeded.connect(_on_build_succeeded)
	_build_controller.finished.connect(func(result: Dictionary) -> void:
		_update_guide()
		_on_upgrade_build_finished(result)
		if _hex_export_pending:
			_hex_export_pending = false
			_append_output("[Error] 编译失败，未导出 HEX"))


## 编译方式下拉与云端设置按钮：已固化在 ui.tscn，只读节点、禁止动态创建。
func _setup_build_mode_selector() -> void:
	var opt: OptionButton = get_node_or_null(P_BUILD_MODE)
	var set_btn: Button = get_node_or_null(P_CLOUD_SETTINGS)
	if opt == null:
		push_error("场景缺少 BuildMode 节点（%s）" % P_BUILD_MODE)
		return
	_build_mode = opt
	if set_btn == null:
		push_error("场景缺少 Settings 节点（%s）" % P_CLOUD_SETTINGS)
		return
	if not set_btn.pressed.is_connected(_on_cloud_settings_pressed):
		set_btn.pressed.connect(_on_cloud_settings_pressed)
	# Web 版无本地 Keil：编译模式锁死在云端
	if WEB.is_web():
		_build_mode.select(1)
		_build_mode.disabled = true


## 当前是否云端编译模式
func _is_cloud_mode() -> bool:
	return _build_mode != null and _build_mode.selected == 1


## 「云端设置」按钮：随时打开云端配置对话框
func _on_cloud_settings_pressed() -> void:
	CLOUD_GUIDE.open_settings(self, _toolchain())


## 云端配置引导取消
func _on_cloud_guide_cancel() -> void:
	_append_output("[Error] 未配置云端编译服务器，编译已中止（可在顶栏「云端设置」填写）")


func _setup_download_controller() -> void:
	_download_controller = DC.new()
	add_child(_download_controller)
	_download_controller.configure(_toolchain(), _clear_output, _append_output)
	_download_controller.busy_changed.connect(_on_download_busy_changed)
	_download_controller.succeeded.connect(_on_download_succeeded)
	_download_controller.progress_changed.connect(_on_upgrade_progress_changed)
	_download_controller.finished.connect(_on_upgrade_download_finished)


# ------------------------------------------------------------------ 信号连接
func _connect_signals() -> void:
	# Web 版禁用：AI 编辑（WebView）、烧录/升级、下载固件、3D 仿真（串口桥）
	WEB.disable_buttons(self, [P_AI_EDIT_BTN, P_UPGRADE_BTN, P_DOWNLOAD_BTN, P_ARM_SIM_BTN])
	var gate_confirm: Node = get_node_or_null(P_GATE_CONFIRM)
	if gate_confirm is BaseButton:
		gate_confirm.pressed.connect(_on_hardware_gate_confirmed)
	var ai_enable_btn: Node = get_node_or_null(P_ENABLE_AI_BTN)
	if ai_enable_btn is BaseButton:
		ai_enable_btn.toggled.connect(_on_ai_enable_toggled)
	var ik_gate: Node = get_node_or_null(P_IK_ENABLE_CB)
	if ik_gate is BaseButton:
		ik_gate.toggled.connect(_on_ik_gate_toggled)
	var gate_back: Node = get_node_or_null(P_GATE_BACK)
	if gate_back is BaseButton:
		gate_back.pressed.connect(_go_to_launcher)
	# LineEdit 文本变化
	for p in [P_CHANNEL, P_DEADZONE, P_NORMAL_SPEED, P_SPRINT_SPEED,
			P_TRIGGER_SPEED, P_TRIGGER_TIME,
			P_YAW_MID_OFFSET, P_PITCH_MID_OFFSET]:
		var node: Node = get_node_or_null(p)
		if node is LineEdit:
			node.text_changed.connect(_run_check)
	# 底盘电机选择变化时，IO 初始化区自动锁定为电机。
	# 同步须在 _run_check 之前连接：先纠正 IO 初始化区，检查才能看到一致状态，
	# 避免用户改子系统配置时出现瞬时误报。
	for p in [P_L1_IO, P_L2_IO, P_R1_IO, P_R2_IO]:
		var ch_btn: Node = get_node_or_null(p)
		if ch_btn is OptionButton:
			ch_btn.item_selected.connect(_sync_io_locks)
	# 步兵固定子系统（拨弹电机 / Yaw / Pitch）配置变化时，IO 初始化区自动同步
	for p in [P_BOOSTER_IO, P_YAW_DRIVE, P_YAW_IO, P_PITCH_DRIVE, P_PITCH_IO]:
		var sub_btn: Node = get_node_or_null(p)
		if sub_btn is OptionButton:
			sub_btn.item_selected.connect(_sync_io_locks)
	# 步骤：OptionButton 选项变化
	for p in [P_L1_IO, P_L2_IO, P_R1_IO, P_R2_IO,
		P_L1_DIR, P_L2_DIR, P_R1_DIR, P_R2_DIR,
		P_BOOSTER_IO, P_BOOSTER_DIR,
		P_YAW_DRIVE, P_YAW_IO, P_YAW_DIR,
		P_PITCH_DRIVE, P_PITCH_IO, P_PITCH_DIR,
		P_TRIGGER, P_BOOSTER_KEY, P_FEED_MODE]:
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
	# 工程师界面：共享 IO 初始化区（工程页 + 步兵高级设置，两份实例都接线）
	for root in [ENGINEER, ADV_ENGINEER]:
		for pin in ENG_ALL_PINS:
			var eng_btn: Node = get_node_or_null(NodePath(root + "/" + str(ENG_IO_REL.get(pin, ""))))
			if eng_btn is OptionButton:
				eng_btn.item_selected.connect(_update_engineer_placeholders)
				eng_btn.item_selected.connect(_run_check)
			var mid_le: Node = get_node_or_null(NodePath(root + "/" + str(ENG_IO_MID_REL.get(pin, ""))))
			if mid_le is LineEdit:
				mid_le.text_changed.connect(_run_check)
		# 模式配置：模式个数 / 切换按键 / 一一对应模式键 / 切换方式 tab
		var mode_count_btn: Node = get_node_or_null(NodePath(root + "/Mode/OptionButton"))
		if mode_count_btn is OptionButton:
			mode_count_btn.item_selected.connect(_update_mode_page_visibility)
			mode_count_btn.item_selected.connect(_run_check)
		var switch_key_btn: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer/Change/OptionButton2"))
		if switch_key_btn is OptionButton:
			switch_key_btn.item_selected.connect(_run_check)
		for kname in ENG_MODE_KEYS:
			var kbtn: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer/Select/" + kname))
			if kbtn is OptionButton:
				kbtn.item_selected.connect(_run_check)
		var mode_tabs: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer"))
		if mode_tabs is TabContainer:
			mode_tabs.tab_changed.connect(_run_check)
		# 每模式动态按键映射行
		for page in ENG_MODE_PAGES:
			_wire_eng_mode_page(root, page)
	_update_mode_page_visibility()
	# 编译按钮
	var build_btn: Node = get_node_or_null(P_BUILD_BTN)
	if build_btn is BaseButton:
		build_btn.pressed.connect(_on_build_pressed)
	# 下载按钮
	var download_btn: Node = get_node_or_null(P_DOWNLOAD_BTN)
	if download_btn is BaseButton:
		download_btn.pressed.connect(_on_download_pressed)
	# 导出 HEX 按钮
	var hex_export_btn: Node = get_node_or_null(P_HEX_EXPORT_BTN)
	if hex_export_btn is BaseButton:
		hex_export_btn.pressed.connect(_on_hex_export_pressed)
	var upgrade_btn: Node = get_node_or_null(P_UPGRADE_BTN)
	if upgrade_btn is BaseButton:
		upgrade_btn.pressed.connect(_on_upgrade_pressed)
	# AI 编辑入口
	var ai_btn: Node = get_node_or_null(P_AI_EDIT_BTN)
	if ai_btn is BaseButton:
		ai_btn.pressed.connect(_on_ai_edit_pressed)
	# 3D 仿真入口
	var sim_btn: Node = get_node_or_null(P_ARM_SIM_BTN)
	if sim_btn is BaseButton:
		sim_btn.pressed.connect(_on_arm_sim_pressed)
	var ik_sim_btn: Node = get_node_or_null(P_IK_OPEN_SIM)
	if ik_sim_btn is BaseButton:
		ik_sim_btn.pressed.connect(_on_arm_sim_pressed)
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
	# Tab 切换时更新代码生成器
	var tab_container: Node = get_node_or_null(P_TAB_CONTAINER)
	if tab_container is TabContainer:
		tab_container.tab_changed.connect(_on_tab_changed)
	# 项目管理按钮
	var create_btn: Node = get_node_or_null(P_CREATE_BTN)
	if create_btn is BaseButton:
		create_btn.pressed.connect(_on_create_pressed)
	var enable_ai_btn: Node = get_node_or_null(P_ENABLE_AI_BTN)
	if enable_ai_btn is BaseButton:
		var ai_toggle_cb: Callable = Callable(self, "_on_ai_enable_toggled")
		if not enable_ai_btn.toggled.is_connected(ai_toggle_cb):
			enable_ai_btn.toggled.connect(ai_toggle_cb)
	var open_btn: Node = get_node_or_null(P_OPEN_BTN)
	if open_btn is BaseButton:
		open_btn.pressed.connect(_on_open_pressed)
	var save_btn: Node = get_node_or_null(P_SAVE_BTN)
	if save_btn is BaseButton:
		save_btn.pressed.connect(_on_save_pressed)
	# 升级进度面板关闭后重置升级/求解器标志，避免面板已隐藏但标志残留
	var upgrade_progress: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if upgrade_progress != null and upgrade_progress.has_signal("closed"):
		upgrade_progress.closed.connect(_on_upgrade_panel_closed)
	if upgrade_progress != null and upgrade_progress.has_signal("cancel_requested"):
		upgrade_progress.cancel_requested.connect(_on_upgrade_cancel_pressed)
	if upgrade_progress != null and upgrade_progress.has_signal("retry_requested"):
		upgrade_progress.retry_requested.connect(_on_upgrade_retry_pressed)
	# 配置区所有控件统一挂一个「改动」监听，用于脏标记与阶段二锁定。
	# 走通用遍历而非逐个列举：上面那些 _run_check 连接是按语义挑的，
	# 这里要的是「任何控件动了」，漏一个就会让脏标记或锁定失效。
	_connect_config_watchers()


# ==================================================================
# 配置序列化
# ==================================================================
## 递归收集左侧 FirstRow 与右侧 EditZone 下所有输入控件。
## FirstRow 键保留 FirstRow/ 前缀，EditZone 键仍以其内部路径保存；
## 但重命名已有节点会让旧存档对不上（届时该项按缺失处理，回落默认值）。
func _snapshot_config() -> Dictionary:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	var first_row: Node = get_node_or_null(P_FIRST_ROW)
	var out: Dictionary = {}
	if first_row != null:
		_snapshot_node(first_row, first_row.get_parent(), out)
	if zone != null:
		_snapshot_node(zone, zone, out)
	return out


func _snapshot_node(node: Node, zone: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if child == get_node_or_null(P_IK_ENABLE_CB):
			continue
		# 隐藏模板行 Example 不算配置，不进快照
		if child.name == "Example":
			continue
		var value: Variant = _control_value(child)
		if value != null:
			out[str(zone.get_path_to(child))] = value
		_snapshot_node(child, zone, out)


## 取单个控件的可序列化值，非输入控件返回 null。
## OptionButton 同时存索引和文本：选项顺序变了还能按文本找回。
func _control_value(node: Node) -> Variant:
	if node == get_node_or_null(P_IK_ENABLE_CB):
		return null
	if node is TabContainer:
		# 工程「切换方式」等 TabContainer 需要持久化当前 tab
		return {"i": node.current_tab}
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
	var first_row: Node = get_node_or_null(P_FIRST_ROW)
	if zone == null or first_row == null:
		return
	_loading = true
	# 旧存档的行以 RowNN 路径存快照，场景默认 0 行：按配置补齐行再回填值
	_ensure_eng_rows_from_config(cfg)
	for key in cfg.keys():
		var path: String = str(key)
		if path == String(P_IK_ENABLE_CB):
			continue
		var node: Node = first_row.get_parent().get_node_or_null(NodePath(path)) \
			if path.begins_with("FirstRow/") else zone.get_node_or_null(NodePath(path))
		if node == null:
			continue
		_apply_control_value(node, cfg[key])
	_loading = false
	_update_debug_placeholders()
	_update_engineer_placeholders()
	_update_mode_page_visibility()
	# 固定子系统引脚锁定：旧存档把引脚存成错误类型时，这里自动纠正
	_sync_io_locks()
	# 左摇杆保留开关：模式1 强制开启，各模式 LX/LY 键位随开关禁用
	_sync_chassis_switch()
	_run_check()


func _apply_control_value(node: Node, value: Variant) -> void:
	if not value is Dictionary:
		return
	var v: Dictionary = value
	if node is TabContainer:
		# 恢复当前 tab（钳到合法范围）
		if v.has("i"):
			var idx: int = int(v["i"])
			if idx >= 0 and idx < node.get_tab_count():
				node.current_tab = idx
	elif node is OptionButton:
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
	var first_row: Node = get_node_or_null(P_FIRST_ROW)
	if first_row != null:
		_watch_node(first_row)
	if zone != null:
		_watch_node(zone)


func _watch_node(node: Node) -> void:
	for child in node.get_children():
		if child == get_node_or_null(P_IK_ENABLE_CB):
			continue
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
	if not _dirty:
		_dirty = true
		_update_title()
	_update_guide()


# ==================================================================
# 项目引导
# ==================================================================
func _setup_guide() -> void:
	var guide: Node = get_node_or_null(P_PROJECT_GUIDE)
	if guide == null or not guide.has_method("setup"):
		return
	var done: Array[bool] = _guide_done_states()
	guide.setup(_guide_titles(), GUIDE_HINTS, done)
	_persist_guide_progress_if_changed(done)
	if not guide.step_pressed.is_connected(_on_guide_step_pressed):
		guide.step_pressed.connect(_on_guide_step_pressed)


func _workflow() -> Dictionary:
	if _project.is_empty():
		return PF.normalize_workflow({})
	var workflow: Dictionary = PF.normalize_workflow(_project.get("workflow", {}))
	_project["workflow"] = workflow
	return workflow


func _code_hash() -> String:
	var code: String = _current_preview_code()
	return code.sha256_text() if not code.strip_edges().is_empty() else ""


func _guide_done_states() -> Array[bool]:
	var workflow: Dictionary = _workflow()
	var code_hash: String = _code_hash()
	var channel: String = _get_line_text(P_CHANNEL).strip_edges()
	var remote_done: bool = channel.is_valid_int() and channel.to_int() >= 0 \
		and channel.to_int() <= 125
	var has_error: bool = false
	for issue in _last_issues:
		if str(issue.get("type", "")) == "Error":
			has_error = true
			break
	var checked: bool = not code_hash.is_empty() and not has_error
	var tab: int = _current_tab()
	var input_done: bool = remote_done if tab == 0 or tab == 1 else checked
	var production_firmware: bool = str(workflow.get("firmware_mode", "unknown")) == "production"
	return [
		bool(workflow.get("hardware_confirmed", false)),
		input_done,
		checked,
		str(workflow.get("checked_hash", "")) == code_hash and checked,
		str(workflow.get("built_hash", "")) == code_hash and not code_hash.is_empty(),
		production_firmware and str(workflow.get("flashed_hash", "")) == code_hash
			and not code_hash.is_empty(),
		production_firmware and bool(workflow.get("hardware_tested", false))
			and str(workflow.get("flashed_hash", "")) == code_hash and not code_hash.is_empty(),
	]


func _update_guide() -> void:
	var guide: Node = get_node_or_null(P_PROJECT_GUIDE)
	if guide == null or not guide.has_method("set_state"):
		return
	var done: Array[bool] = _guide_done_states()
	guide.set_state(_guide_titles(), GUIDE_HINTS, done)
	_persist_guide_progress_if_changed(done)


func _persist_guide_progress_if_changed(done: Array[bool]) -> void:
	if _project.is_empty() or AppState.project_path.is_empty():
		return
	var workflow: Dictionary = _workflow()
	var saved: Array = workflow.get("guide_completed", [])
	if saved == done:
		return
	workflow["guide_completed"] = done.duplicate()
	_project["workflow"] = workflow
	var result: Dictionary = PF.save_to(AppState.project_path, _project)
	if not result["ok"]:
		_append_output("[Error] 保存项目引导进度失败：%s" % result["err"])


func _guide_titles() -> Array[String]:
	var titles: Array[String] = GUIDE_TITLES.duplicate()
	match _current_tab():
		2:
			titles[1] = "配置机械臂构形"
			titles[2] = "配置关节与控制"
		3:
			titles[1] = "选择测试端口"
			titles[2] = "配置测试参数"
	return titles


func _on_guide_step_pressed(step: int) -> void:
	match step:
		0:
			_confirm_hardware()
		1:
			match _current_tab():
				2:
					_on_arm_sim_pressed()
				3:
					_focus_control(NodePath(DEBUG +"/HBoxContainer/OptionButton"))
				_:
					_focus_control(P_CHANNEL)
		2:
			_focus_control(P_L1_IO if _current_tab() != 3 else NodePath(DEBUG +"/HBoxContainer/LineEdit"))
		3:
			_run_guide_check()
		4:
			_run_guide_build()
		5:
			_on_download_pressed()
		6:
			_confirm_hardware_test()


## 当前编辑页的逻辑索引（0=步兵, 1=工程, 2=工程逆解算, 3=调试）。
## 步兵/调试是平铺 Control（按项目类型切换可见性），工程是内部 TabContainer。
func _current_tab() -> int:
	var edit_zone: Node = get_node_or_null(P_EDIT_ZONE)
	if not is_instance_valid(edit_zone):
		return 0
	var infra: Node = edit_zone.get_node_or_null("Infantry")
	var dbg: Node = edit_zone.get_node_or_null("Debug")
	if infra is CanvasItem and infra.visible:
		return 0
	if dbg is CanvasItem and dbg.visible:
		return 3
	var tabs: Node = get_node_or_null(P_TAB_CONTAINER)
	if tabs is TabContainer:
		return 1 if tabs.current_tab == 0 else 2
	return 0


func _focus_control(path: NodePath) -> void:
	var control: Node = get_node_or_null(path)
	if control is Control:
		control.grab_focus()


func _run_guide_check() -> void:
	_run_check()
	var has_error: bool = false
	for issue in _last_issues:
		if str(issue.get("type", "")) == "Error":
			has_error = true
			break
	if not _project.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["checked_hash"] = "" if has_error else _code_hash()
		_project["workflow"] = workflow
		_save_project(false)
	_update_guide()


func _run_guide_build() -> void:
	_run_guide_check()
	for issue in _last_issues:
		if str(issue.get("type", "")) == "Error":
			_append_output("[Error] 配置仍有错误，请先完成“检查与仿真”步骤")
			return
	_on_build_pressed()


func _confirm_hardware() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "查看第一步确认"
	dialog.dialog_text = "请确认：\n\n1. 程序只烧录到主控板。\n2. 绝不向机械扩展板烧录程序。"
	dialog.get_ok_button().text = "已确认"
	dialog.get_cancel_button().text = "返回检查"
	dialog.confirmed.connect(func() -> void:
		var workflow: Dictionary = _workflow()
		workflow["hardware_confirmed"] = true
		_project["workflow"] = workflow
		_save_project(false)
		_update_guide())
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 300))
	dialog.close_requested.connect(dialog.queue_free)


func _on_hardware_gate_confirmed() -> void:
	if _project.is_empty():
		_apply_hardware_gate(false)
		return
	var workflow: Dictionary = _workflow()
	workflow["hardware_confirmed"] = true
	_project["workflow"] = workflow
	_save_project(false)
	_apply_hardware_gate(false)
	_update_guide()


func _apply_hardware_gate(required: bool) -> void:
	var main_ui: Node = get_node_or_null(P_MAIN_UI)
	var gate: Node = get_node_or_null(P_HARDWARE_GATE)
	if main_ui is CanvasItem:
		main_ui.visible = not required
	if gate is CanvasItem:
		gate.visible = required


func _confirm_hardware_test() -> void:
	var workflow: Dictionary = _workflow()
	var code_hash: String = _code_hash()
	if code_hash.is_empty() or str(workflow.get("flashed_hash", "")) != code_hash:
		_clear_output()
		_append_output("[Error] 请先编译并烧录当前程序，再进行真机测试")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "确认真机低速测试"
	dialog.dialog_text = "请确认已经架空底盘或拆下危险机构，并逐个低速验证：\n\n- 每个电机和舵机方向正确\n- 停止操作有效\n- 摩擦轮从低速逐渐启动和停止"
	dialog.get_ok_button().text = "测试通过"
	dialog.get_cancel_button().text = "尚未完成"
	dialog.confirmed.connect(func() -> void:
		workflow["hardware_tested"] = true
		_project["workflow"] = workflow
		_save_project(false)
		_update_guide())
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 300))
	dialog.close_requested.connect(dialog.queue_free)


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
	_ik_config = IK_CONFIG.default_config()
	_ai_enabled = false
	_ik_confirmed = false
	_apply_ai_gate(false)
	_apply_hardware_gate(false)
	_apply_ik_gate(false)
	_stage2_preview = false
	_dirty = false
	# 无项目（自由编辑）：默认显示步兵页
	_apply_kind_visibility(PF.KIND_INFANTRY, 0)
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


func _apply_ai_gate(enabled: bool) -> void:
	_ai_enabled = enabled
	var enable_btn: Node = get_node_or_null(P_ENABLE_AI_BTN)
	var ai_btn: Node = get_node_or_null(P_AI_EDIT_BTN)
	# 功能下线：无论开关状态如何，两个入口一律隐藏
	if not AI_EDIT_ENABLED:
		if enable_btn is CanvasItem:
			enable_btn.visible = false
		if ai_btn is CanvasItem:
			ai_btn.visible = false
		if ai_btn is BaseButton:
			ai_btn.disabled = true
		return
	if enable_btn is BaseButton:
		enable_btn.button_pressed = enabled
	# 启用后隐藏「启用 AI 功能」按钮（已通过 10s 门禁确认，无需再显示）
	if enable_btn is CanvasItem:
		enable_btn.visible = not enabled
	if ai_btn is CanvasItem:
		ai_btn.visible = enabled
	if ai_btn is BaseButton:
		ai_btn.disabled = not enabled
	var ai_btn2: Node = get_node_or_null(P_AI_EDIT_BTN)
	if ai_btn2 is BaseButton:
		ai_btn2.disabled = not enabled


func _apply_ik_gate(confirmed: bool) -> void:
	_ik_confirmed = confirmed
	_ik_config["enabled"] = confirmed
	var root: Node = get_node_or_null(P_IK)
	if root != null:
		_set_node_tree_enabled(root, confirmed)
	var gate_row: Node = get_node_or_null(NodePath(IK +"/HBoxContainer"))
	if gate_row != null:
		_set_node_tree_enabled(gate_row, true)
	var panel_label: Node = get_node_or_null(P_IK_PANEL_LABEL)
	if panel_label is CanvasItem:
		panel_label.visible = confirmed
	var summary: Node = get_node_or_null(P_IK_SUMMARY)
	if summary is CanvasItem:
		summary.visible = confirmed
	var open_sim: Node = get_node_or_null(P_IK_OPEN_SIM)
	if open_sim is CanvasItem:
		open_sim.visible = confirmed
	if open_sim is BaseButton:
		open_sim.disabled = not confirmed
	var gate_cb: Node = get_node_or_null(P_IK_ENABLE_CB)
	if gate_cb is BaseButton:
		gate_cb.disabled = false
		if gate_cb.button_pressed != confirmed:
			_loading = true
			gate_cb.button_pressed = confirmed
			_loading = false
	_update_ik_summary()


func _show_countdown_scene(scene_path: String, title: String, body: String,
		primary_text: String, secondary_text: String = "", error_text: String = "",
		on_confirm: Callable = Callable(), on_cancel: Callable = Callable()) -> void:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("无法加载确认页面：%s" % scene_path)
		return
	var dialog: Node = packed.instantiate()
	if dialog.has_method("configure"):
		dialog.call("configure", title, body, primary_text, secondary_text, 10, error_text)
	add_child(dialog)
	# 编译失败时升级进度面板可能正可见，必须把门控页提到最前，否则用户以为没反应
	if dialog is CanvasItem:
		dialog.move_to_front()
	if dialog.has_signal("confirmed") and on_confirm.is_valid():
		dialog.confirmed.connect(on_confirm)
	if dialog.has_signal("canceled") and on_cancel.is_valid():
		dialog.canceled.connect(on_cancel)
	if dialog.has_signal("confirmed"):
		dialog.confirmed.connect(dialog.queue_free)
	if dialog.has_signal("canceled"):
		dialog.canceled.connect(dialog.queue_free)


func _on_ik_gate_toggled(pressed: bool) -> void:
	if _loading:
		return
	if pressed:
		if _ik_confirmed:
			_apply_ik_gate(true)
			if not AppState.project_path.is_empty():
				var workflow: Dictionary = _workflow()
				workflow["ik_confirmed"] = true
				_project["workflow"] = workflow
				_save_project(false)
			return
		# warn_ik 页面自带文案（启用机械臂逆解），这里不改动它的文本，只接回调
		_show_countdown_scene(WARN_IK_SCENE,
			"", "", "", "", "",
			Callable(self, "_on_ik_gate_confirmed"), Callable(self, "_on_ik_gate_canceled"))
		return
	_apply_ik_gate(false)
	if not AppState.project_path.is_empty():
		var workflow2: Dictionary = _workflow()
		workflow2["ik_confirmed"] = false
		_project["workflow"] = workflow2
		_save_project(false)


func _on_ik_gate_confirmed() -> void:
	_apply_ik_gate(true)
	if not AppState.project_path.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["ik_confirmed"] = true
		_project["workflow"] = workflow
		_save_project(false)


func _on_ik_gate_confirmed_and_open_sim() -> void:
	_on_ik_gate_confirmed()
	_on_arm_sim_pressed()


func _on_ik_gate_canceled() -> void:
	_loading = true
	var gate_cb: Node = get_node_or_null(P_IK_ENABLE_CB)
	if gate_cb is BaseButton:
		gate_cb.button_pressed = false
	_loading = false
	_apply_ik_gate(false)


## 把一份项目数据装载进界面
func _adopt_project(data: Dictionary, path: String) -> void:
	_project = data
	_ik_config = IK_CONFIG.normalize(data.get("ik_config", {}))
	# workflow.ik_confirmed 是旧存档门控状态的唯一可信源：缺字段一律视为未启用
	_ik_config["enabled"] = bool(_workflow().get("ik_confirmed", false))
	_ai_enabled = bool(_workflow().get("ai_enabled", false))
	_ik_confirmed = bool(_workflow().get("ik_confirmed", false))
	_apply_ai_gate(_ai_enabled)
	_apply_hardware_gate(not bool(_workflow().get("hardware_confirmed", false)))
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
	_frozen_ik_config = _ik_config.duplicate(true)
	_stage2_preview = int(data["stage"]) >= 2
	_dirty = false
	_apply_ai_gate(_ai_enabled)
	_apply_ik_gate(_ik_confirmed)
	_update_title()


## 按项目类型显示对应页面（类型不可转换的第二道保证）。
## 步兵/调试是 EditZone 下平铺的 Control（可见性切换）；工程是内部 TabContainer。
func _apply_kind_visibility(kind: String, want_tab: int) -> void:
	var edit_zone: Node = get_node_or_null(P_EDIT_ZONE)
	if not is_instance_valid(edit_zone):
		return
	var infra: Node = edit_zone.get_node_or_null("Infantry")
	var eng_tabs: Node = edit_zone.get_node_or_null("Engineer")
	var dbg: Node = edit_zone.get_node_or_null("Debug")
	if infra is CanvasItem:
		infra.visible = (kind == PF.KIND_INFANTRY)
	if eng_tabs is CanvasItem:
		eng_tabs.visible = (kind == PF.KIND_ENGINEER)
	if dbg is CanvasItem:
		dbg.visible = (kind == PF.KIND_DEBUG)
	# 工程内部 tab：0=工程, 1=工程逆解算（want_tab 是逻辑索引 1/2）
	var allowed: Array = PF.kind_tabs(kind)
	var target: int = want_tab if want_tab in allowed else PF.kind_default_tab(kind)
	if eng_tabs is TabContainer and kind == PF.KIND_ENGINEER:
		eng_tabs.current_tab = target - 1
	_update_mode_page_visibility()


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
	data["ik_config"] = IK_CONFIG.default_config()
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
## 快捷键：Ctrl+S 保存、Ctrl+B 编译（与顶栏按钮等效）。
## 走 _unhandled_key_input：控件未消费的按键才会到达这里，不影响输入框打字。
func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and event.ctrl_pressed:
		if event.keycode == KEY_S:
			_on_save_pressed()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_B:
			_on_build_pressed()
			get_viewport().set_input_as_handled()


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
		_project["ik_config"] = _ik_config.duplicate(true)
		_project["main_c_stage1"] = _current_preview_code()
		_project["active_tab"] = _current_tab()
	var res: Dictionary = PF.save_to(AppState.project_path, _project)
	if not res["ok"]:
		_append_output("[Error] 保存失败：%s" % res["err"])
		return
	_dirty = false
	_update_title()
	if verbose:
		if WEB.is_web():
			_append_output("已保存项目（浏览器虚拟磁盘，需要带出电脑请用「导出 HEX」或复制代码）")
		else:
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
	dlg.dialog_text = "该项目已进入 AI 编辑阶段。\n" \
		+"这里的图形化配置只能预览，不能更改。\n" \
		+"如果在这里更改，AI 编辑的内容会丢失。\n" \
		+"建议把想修改的地方直接告诉 AI。"
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
	dlg.dialog_text = "继续修改将丢弃 AI 编辑的代码，项目回到图形化配置阶段。\n" \
		+"更稳妥的做法是把想改的地方告诉 AI。\n确定要继续吗？"
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
	_update_sim_btn_visibility()
	_run_check()


## 顶栏「3D 仿真」按钮按当前 Tab 显示：
##   0=步兵 -> 步兵整车仿真（基础功能，无需机械臂逆解门控）
##   2=工程逆解算 -> 机械臂仿真（点击时经 IK 门控确认）
##   其余 Tab 没有仿真，隐藏按钮以免点到「当前构型没有 3D 仿真」警告。
func _update_sim_btn_visibility() -> void:
	var sim_btn: Node = get_node_or_null(P_ARM_SIM_BTN)
	if not sim_btn is CanvasItem:
		return
	var tab: int = _current_tab()
	sim_btn.visible = (tab == 0 or tab == 2)


## 根据当前 Tab 选项获取对应的代码生成器
func _get_current_codegen() -> CodeGenBase:
	# Tab 顺序：0=步兵, 1=工程, 2=工程逆解算, 3=调试
	match _current_tab():
		0:
			return CodeGenInfantry.new()
		1, 2:
			# 未启用逆解算时生成纯正解（按键映射）固件，不含任何逆解内容
			if not bool(_ik_config.get("enabled", false)):
				return CodeGenEngineer.new()
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
# 舵机相对中位的可用偏移角上限（与 CodeGenBase.SERVO_MAX_OFFSET_DEG 一致）
const SERVO_MAX_ANGLE: int = 90
# 电机速度上限
const MOTOR_SPEED_MAX: int = 10000
# 扩展板引脚（通过 ExpansionBoradControl 控制）
const EXPANSION_PINS: Array = ["P60", "P62", "P64", "P66", "P74", "P75", "P76", "P77"]
## 根据每行的控制模式和目标 IO 类型，更新参数框的占位文本，并按
## 「控制方式 × IO 类型 × 键位类型」过滤下拉选项：
##   舵机（MP 恒舵机或拓展板选舵机）+ 按键 -> 增量/直接；+ 摇杆轴 -> 增量
##   电机 + 按键 -> 直接；+ 摇杆轴 -> 速度/增速
## 与静态检查器的合法性矩阵一致，从源头杜绝非法组合。程序化重建不触发 item_selected。
## 舵机角度一律是「相对中位的偏移角」，行程 ±90°，不是 0~180°。
func _update_engineer_placeholders(_idx: int = -1) -> void:
	# 工程页与步兵高级设置是两份实例，都要过滤，否则切页后残留旧选项
	for root in [ENGINEER, ADV_ENGINEER]:
		_update_engineer_root_placeholders(root)


## 单个共享配置根（工程页 / 步兵高级设置）的过滤与占位提示
func _update_engineer_root_placeholders(root: String) -> void:
	var io_init: Dictionary = {}
	for pin in ENG_ALL_PINS:
		io_init[pin] = _get_option_text(NodePath(root + "/" + str(ENG_IO_REL.get(pin, ""))))
	for page in ENG_MODE_PAGES:
		var vb: Node = get_node_or_null(NodePath(root + "/" + page + "/ScrollContainer/VBoxContainer"))
		if vb == null:
			continue
		for row in vb.get_children():
			if not row is HBoxContainer:
				continue
			var key_btn: Node = row.get_node_or_null("Key")
			var mode_btn: Node = row.get_node_or_null("Option")
			var io_btn: Node = row.get_node_or_null("IO")
			var para_le: Node = row.get_node_or_null("Para")
			if not key_btn is OptionButton or not mode_btn is OptionButton \
					or not io_btn is OptionButton or not para_le is LineEdit:
				continue
			var mode: String = _option_text(mode_btn)
			var target: String = _option_text(io_btn)
			# MP03/MP74 固定舵机；扩展板引脚看 IO 初始化区
			var is_servo: bool = target.begins_with("MP") or io_init.get(target, "舵机") == "舵机"
			# 摇杆轴行（LX/LY/RX/RY）不能用「直接」，按键行不能用「速度/增速」
			var is_axis: bool = _option_text(key_btn) in ["LX", "LY", "RX", "RY"]
			var allowed_modes: Array
			if is_servo:
				allowed_modes = ["增量"] if is_axis else ["增量", "直接"]
			else:
				allowed_modes = ["速度", "增速"] if is_axis else ["直接"]
			var cur_mode: String = _option_text(mode_btn)
			var changed: bool = false
			if mode_btn.item_count != allowed_modes.size():
				changed = true
			else:
				for i in range(allowed_modes.size()):
					if mode_btn.get_item_text(i) != allowed_modes[i]:
						changed = true
						break
			if changed:
				mode_btn.clear()
				for m in allowed_modes:
					mode_btn.add_item(m)
				mode_btn.select(allowed_modes.find(cur_mode) if cur_mode in allowed_modes else 0)
				mode = _option_text(mode_btn)
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
			para_le.placeholder_text = placeholder


# ------------------------------------------------------------------ 动态按键映射行
## 场景里的模板行保持名为 Example（隐藏），只作为「+」新建行的原型；
## 真实行从 Row01 开始命名，使配置快照路径稳定。
func _normalize_eng_row_names() -> void:
	for root in [ENGINEER, ADV_ENGINEER]:
		for page in ENG_MODE_PAGES:
			var vb: Node = get_node_or_null(NodePath(root + "/" + page + "/ScrollContainer/VBoxContainer"))
			if vb == null:
				continue
			var idx: int = 1
			for child in vb.get_children():
				if child is HBoxContainer and child.name != "Example":
					child.name = "Row%02d" % idx
					idx += 1


## 给某个模式页的「+」按钮与已有行接线
func _wire_eng_mode_page(root: String, page: String) -> void:
	var vb: Node = get_node_or_null(NodePath(root + "/" + page + "/ScrollContainer/VBoxContainer"))
	if vb == null:
		return
	var add_btn: Node = vb.get_node_or_null("Add")
	if add_btn is BaseButton:
		add_btn.pressed.connect(_on_eng_row_add_pressed.bind(add_btn))
	var ck: Node = get_node_or_null(NodePath(root + "/" + page + "/Chassis/CheckButton"))
	if ck is CheckButton:
		ck.toggled.connect(_sync_chassis_switch)
		ck.toggled.connect(_run_check)
	for child in vb.get_children():
		if child is HBoxContainer and child.name != "Example":
			_wire_eng_row(child)


func _wire_eng_row(row: Node) -> void:
	for child_name in ["Key", "Dir", "Option", "IO"]:
		var ctrl: Node = row.get_node_or_null(child_name)
		if ctrl is OptionButton:
			ctrl.item_selected.connect(_update_engineer_placeholders)
			ctrl.item_selected.connect(_run_check)
	var para: Node = row.get_node_or_null("Para")
	if para is LineEdit:
		para.text_changed.connect(_run_check)
	var rem: Node = row.get_node_or_null("Remove")
	if rem is BaseButton:
		rem.pressed.connect(_on_eng_row_remove_pressed.bind(row))


## 按「+」新增一行（复制隐藏模板行 Example 并重置为默认值）
func _on_eng_row_add_pressed(add_btn: Node) -> void:
	var vb: Node = add_btn.get_parent() if add_btn != null else null
	if vb == null:
		return
	if _add_eng_row(vb) != null:
		_run_check()


## 在 vb 里新建一行，返回新行（失败返回 null）。
## 原型是场景里始终存在的隐藏模板行 Example，删除全部行后仍能新建。
func _add_eng_row(vb: Node) -> Node:
	var proto: Node = vb.get_node_or_null("Example")
	if proto == null:
		for child in vb.get_children():
			if child is HBoxContainer and child.name != "Example":
				proto = child
				break
	if proto == null:
		return null
	var row: Node = proto.duplicate(true)
	row.name = "Row%02d" % (_eng_row_count(vb) + 1)
	if row is CanvasItem:
		row.visible = true
	# 重置为默认值：E / 正 / 增量 / 空参数 / P60
	for child_name in ["Key", "Dir", "Option", "IO"]:
		var ctrl: Node = row.get_node_or_null(child_name)
		if ctrl is OptionButton and ctrl.item_count > 0:
			ctrl.selected = 0
	var para: Node = row.get_node_or_null("Para")
	if para is LineEdit:
		para.text = ""
	vb.add_child(row)
	# Add 按钮保持在最后
	vb.move_child(row, vb.get_child_count() - 2)
	_wire_eng_row(row)
	# 新建行按目标 IO 类型过滤「控制方式」下拉并更新占位提示
	_update_engineer_placeholders()
	# 新建行同样受左摇杆保留开关约束（模式1 恒开，LX/LY 不可选）
	_sync_chassis_switch()
	return row


## 删除一行（允许删到 0 行）
func _on_eng_row_remove_pressed(row: Node) -> void:
	if row == null or not is_instance_valid(row):
		return
	row.queue_free()
	_run_check()


func _eng_row_count(vb: Node) -> int:
	var n: int = 0
	for child in vb.get_children():
		if child is HBoxContainer and child.name != "Example":
			n += 1
	return n


## 模式个数变化：隐藏/显示 模式2~4 页；模式1 时隐藏切换方式区；
## 一一对应模式下 Label 与模式键下拉个数跟随模式数
## 带可选参数以兼容 item_selected 信号（信号会传入被选中的索引）
func _update_mode_page_visibility(_idx: int = -1) -> void:
	for root in [ENGINEER, ADV_ENGINEER]:
		var count_btn: Node = get_node_or_null(NodePath(root + "/Mode/OptionButton"))
		if not count_btn is OptionButton:
			continue
		var count: int = _option_text(count_btn).to_int()
		# 模式1 时没有切换需求，隐藏整个切换方式区（单击切换/一一对应两个 tab）
		var mode_tabs: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer"))
		if mode_tabs is CanvasItem:
			mode_tabs.visible = (count >= 2)
		# 一一对应：Label 与模式键下拉个数跟随模式数（模式1-2 / 模式1-3 / 模式1-4）
		var select_label: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer/Select/Label"))
		if select_label is Label:
			select_label.text = "模式1-%d" % count
		for i in range(4):
			var kbtn: Node = get_node_or_null(NodePath(
				root + "/Mode/TabContainer/Select/" + ENG_MODE_KEYS[i]))
			if kbtn is CanvasItem:
				kbtn.visible = (i < count)
		var tabs: Node = get_node_or_null(NodePath(root + "/TabContainer"))
		var prev_tab: int = tabs.current_tab if tabs is TabContainer else 0
		if tabs is TabContainer:
			for i in range(tabs.get_tab_count()):
				tabs.set_tab_hidden(i, i >= count)
		for i in range(4):
			var page: Node = get_node_or_null(NodePath(root + "/" + ENG_MODE_PAGES[i]))
			if page is CanvasItem:
				page.visible = (i < count)
		# 子页可见性变化会让 TabContainer 跳到被改动的页（Godot 行为），
		# 恢复原来的页；模式数减少时钳到最后一个可见页
		if tabs is TabContainer:
			tabs.current_tab = mini(prev_tab, maxi(count - 1, 0))


## 计算某个 IO 初始化区根下每个引脚的期望类型（空字符串 = 不锁定）。
## 底盘四轮对两个根（工程页 / 步兵高级设置）都生效；
## 步兵固定子系统（拨弹电机 / 摩擦轮 / Yaw / Pitch）只对步兵高级设置生效。
## 期望类型与 static_checker._check_infantry_shared 保持一致。
func _compute_io_desired(root: String) -> Dictionary:
	var desired: Dictionary = {}
	# 底盘四轮：恒为电机（两个根都适用）
	var chassis_pins: Array = []
	for p in [P_L1_IO, P_L2_IO, P_R1_IO, P_R2_IO]:
		var pin: String = _get_option_text(p).split(" ")[0].strip_edges()
		if not pin.is_empty() and not pin in chassis_pins:
			chassis_pins.append(pin)
	# 步兵固定子系统：仅步兵高级设置（ADV_ENGINEER）
	if root == ADV_ENGINEER:
		# Yaw / Pitch：跟随驱动类型（舵机 -> 舵机，电机 -> 电机），优先级最低
		var yaw_drive: String = _get_option_text(P_YAW_DRIVE)
		var yaw_pin: String = _get_option_text(P_YAW_IO).split(" ")[0].strip_edges()
		if not yaw_pin.is_empty() and not yaw_pin.begins_with("MP") \
				and (yaw_drive == "电机" or yaw_drive == "舵机"):
			desired[yaw_pin] = yaw_drive
		var pitch_drive: String = _get_option_text(P_PITCH_DRIVE)
		var pitch_pin: String = _get_option_text(P_PITCH_IO).split(" ")[0].strip_edges()
		if not pitch_pin.is_empty() and not pitch_pin.begins_with("MP") \
				and (pitch_drive == "电机" or pitch_drive == "舵机"):
			desired[pitch_pin] = pitch_drive
		# 拨弹电机：恒为电机（10000Hz 初始化），优先级高于 Yaw/Pitch
		var booster_pin: String = _get_option_text(P_BOOSTER_IO).split(" ")[0].strip_edges()
		if not booster_pin.is_empty() and not booster_pin.begins_with("MP"):
			desired[booster_pin] = "电机"
	# 底盘四轮：恒为电机，优先级高于步兵子系统
	for pin in chassis_pins:
		desired[pin] = "电机"
	# 摩擦轮固定占用 P64/P66，恒为舵机（50Hz 初始化，与舵机同频），优先级最高
	if root == ADV_ENGINEER:
		for pin in ["P64", "P66"]:
			desired[pin] = "舵机"
	return desired


## 步兵 IO 初始化区自动同步：固定子系统（底盘 / 拨弹电机 / 摩擦轮 / Yaw / Pitch）
## 选中的引脚在 IO 初始化区强制为对应类型并禁用另一项，
## 防止用户未展开高级设置时因类型不匹配而报错。
## 子系统配置变化、项目载入后都要调用。
## 带可选参数以兼容 item_selected 信号（信号会传入被选中的索引）
func _sync_io_locks(_idx: int = -1) -> void:
	for root in [ENGINEER, ADV_ENGINEER]:
		var desired: Dictionary = _compute_io_desired(root)
		for pin in ENG_IO_REL.keys():
			var btn: Node = get_node_or_null(NodePath(root + "/" + str(ENG_IO_REL.get(pin, ""))))
			if not btn is OptionButton:
				continue
			var want: String = str(desired.get(pin, ""))
			if want.is_empty():
				# 未占用：解锁，恢复两个选项
				for i in range(btn.item_count):
					btn.set_item_disabled(i, false)
				if btn.selected < 0 or btn.is_item_disabled(btn.selected):
					# 兜底：当前项被禁用时回到第一个可用项
					for i in range(btn.item_count):
						if not btn.is_item_disabled(i):
							btn.selected = i
							break
				continue
			# 占用：选中期望类型并禁用另一项（IO 初始化区只有 电机/舵机 两项）
			var other: String = "舵机" if want == "电机" else "电机"
			var want_idx: int = -1
			var other_idx: int = -1
			for i in range(btn.item_count):
				match btn.get_item_text(i):
					want:
						want_idx = i
					other:
						other_idx = i
			if want_idx >= 0:
				btn.selected = want_idx
			if other_idx >= 0:
				btn.set_item_disabled(other_idx, true)
	# IO 类型变化后，相关按键映射行的「控制方式」下拉同步刷新
	_update_engineer_placeholders()


## 同步各模式页「此模式下保留左摇杆作为底盘控制」开关：
## 模式1 强制开启且不可关；开启的模式页禁用该页所有行的 LX/LY 键位（左摇杆已归底盘）。
## 带可选参数以兼容 toggled 信号（信号会传入开关状态）
func _sync_chassis_switch(_pressed: bool = false) -> void:
	for root in [ENGINEER, ADV_ENGINEER]:
		for mi in range(4):
			var ck: Node = get_node_or_null(NodePath(
				root + "/" + ENG_MODE_PAGES[mi] + "/Chassis/CheckButton"))
			if not ck is CheckButton:
				continue
			if mi == 0:
				ck.button_pressed = true
				ck.disabled = true
			else:
				ck.disabled = false
			_sync_row_axis_locks(root, ENG_MODE_PAGES[mi], ck.button_pressed)
	# LX/LY 键位锁定后键位类型可能从摇杆轴回退成按键，控制方式下拉同步刷新
	_update_engineer_placeholders()


## 模式页开关开启时，该页所有行的 LX/LY 键位禁用
func _sync_row_axis_locks(root: String, page: String, locked: bool) -> void:
	var vb: Node = get_node_or_null(NodePath(
		root + "/" + page + "/ScrollContainer/VBoxContainer"))
	if vb == null:
		return
	for child in vb.get_children():
		if not child is HBoxContainer or child.name == "Example":
			continue
		_lock_row_key_axes(child, locked)


## 单行 Key 下拉的 LX/LY 禁用；锁定且当前选中被禁用时回到第一个可用项
func _lock_row_key_axes(row: Node, locked: bool) -> void:
	var key: Node = row.get_node_or_null("Key")
	if not key is OptionButton:
		return
	for i in range(key.item_count):
		if key.get_item_text(i) == "LX" or key.get_item_text(i) == "LY":
			key.set_item_disabled(i, locked)
	if locked:
		var sel: int = key.selected
		if sel >= 0 and sel < key.item_count and key.is_item_disabled(sel):
			for i in range(key.item_count):
				if not key.is_item_disabled(i):
					key.selected = i
					break


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
func _collect_ik_config() -> Dictionary:
	return _ik_config.duplicate(true)


## 两个工程配置页共同描述同一份双模式固件。
func _collect_engineer_dual_config() -> Dictionary:
	return {
		"engineer": _collect_engineer_config(),
		"ik": _collect_ik_config(),
	}


# ------------------------------------------------------------------ 检查入口
func _run_check(_a = null, _b = null) -> void:
	# 批量回填配置期间不检查：上百个控件的信号会触发上百次全量检查 + 代码生成
	if _loading:
		return
	# 拨弹模式切换：目视闭环不需要拨弹时间，隐藏输入框（只影响可见性，不影响门控）
	_update_feed_mode_ui()
	# 根据当前 Tab 决定执行哪些检查
	var current_tab: int = _current_tab()
	var issues: Array = []
	match current_tab:
		0:
			# 步兵模式检查（含高级设置里的共享多模式按键映射）
			var inf_cfg: Dictionary = _collect_config()
			inf_cfg.merge(_collect_engineer_config(), true)
			issues = SC.check_infantry(inf_cfg)
		1, 2:
			# 工程多模式：工程页与逆解算页共同配置同一份固件。
			# 未启用逆解算时只检查正解（按键映射）部分，逆解校验由检查器按 enabled 跳过。
			issues = SC.check_engineer(_collect_engineer_config(), _collect_ik_config())
		3:
			# 调试模式检查（tab 顺序：0=步兵, 1=工程, 2=工程逆解算, 3=调试）
			issues = SC.check_debug(_collect_debug_config())
	_last_issues = issues
	_update_ik_summary()
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
		1, 2:
			# 未启用逆解算时走纯正解生成器，需要扁平工程配置
			if bool(_ik_config.get("enabled", false)):
				cfg = _collect_engineer_dual_config()
			else:
				cfg = _collect_engineer_config()
		_:
			# 步兵：固定云台/发射配置 + 高级设置的共享多模式按键映射
			var inf_gen_cfg: Dictionary = _collect_config()
			inf_gen_cfg.merge(_collect_engineer_config(), true)
			cfg = inf_gen_cfg
	var code: String = _codegen.generate(cfg)
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	if code_edit is CodeEdit:
		code_edit.text = code

func _update_ik_summary() -> void:
	var label: Node = get_node_or_null(P_IK_SUMMARY)
	if not label is Label:
		return
	if not bool(_ik_config.get("enabled", false)):
		# 未启用逆解算：不校验配置，摘要只说明当前状态（门控关闭时该标签本就隐藏）
		label.text = "机械臂逆解算未启用"
		return
	var result: Dictionary = IK_CONFIG.validate(_ik_config, _collect_engineer_config())
	var errors: int = 0
	var warnings: int = 0
	for issue in result.get("issues", []):
		if str(issue.get("type", "")) == "Error":
			errors += 1
		else:
			warnings += 1
	var ios: Array[String] = []
	for joint in _ik_config.get("joints", []):
		ios.append(str(joint.get("io", "")))
	var active_presets: int = 0
	for preset in _ik_config.get("presets", []):
		if preset.get("enabled", false):
			active_presets += 1
	var gripper: Dictionary = _ik_config.get("gripper", {})
	var gripper_text: String = "夹爪 %s" % str(gripper.get("io", "")) \
		if bool(gripper.get("enabled", false)) else "夹爪未启用"
	label.text = "%d 个关节  |  IO %s  |  %s  |  %d 个预设\n%d 个错误，%d 个警告" % [
		int(_ik_config.get("joint_count", 3)), ", ".join(ios), gripper_text,
		active_presets, errors, warnings,
	]
	if str(_workflow().get("firmware_mode", "unknown")) == "simulator":
		label.text += "\n主控板当前记录为仿真固件，不能直接驱动机器人"


## 拨弹模式联动：目视闭环按住持续拨弹，不需要「时间(ms)」参数，隐藏输入框。
## 只改可见性，不改 editable，避免与 _set_node_tree_enabled 的门控逻辑相互干扰。
func _update_feed_mode_ui() -> void:
	var time_edit: Node = get_node_or_null(P_TRIGGER_TIME)
	if not time_edit is CanvasItem:
		return
	var mode: String = _get_option_text(P_FEED_MODE)
	time_edit.visible = mode != "目视闭环"


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
	cfg["feed_mode"] = _get_option_text(P_FEED_MODE)
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
	# --- IO 初始化区（共享区：工程页 / 步兵高级设置，含主控板口）---
	var root: String = _shared_cfg_root()
	var io_init: Dictionary = {}
	for pin in ENG_ALL_PINS:
		io_init[pin] = _get_option_text(NodePath(root + "/" + str(ENG_IO_REL.get(pin, ""))))
	cfg["io_init"] = io_init
	# --- 各引脚舵机初始角（相对中位偏移，仅舵机有效）---
	var io_mid: Dictionary = {}
	for pin in ENG_ALL_PINS:
		io_mid[pin] = _get_line_text(NodePath(root + "/" + str(ENG_IO_MID_REL.get(pin, "")))).strip_edges()
	cfg["io_mid"] = io_mid
	# --- 模式配置 ---
	var mode_count_btn: Node = get_node_or_null(NodePath(root + "/Mode/OptionButton"))
	cfg["mode_count"] = _option_text(mode_count_btn).to_int() if mode_count_btn is OptionButton else 1
	var mode_tabs: Node = get_node_or_null(NodePath(root + "/Mode/TabContainer"))
	# 切换方式：0=单击切换, 1=一一对应
	cfg["switch_strategy"] = "一一对应" \
		if (mode_tabs is TabContainer and mode_tabs.current_tab == 1) else "单击切换"
	cfg["mode_switch_key"] = _get_option_text(NodePath(root + "/" + ENG_MODE_SWITCH_KEY))
	var mode_keys: Array = []
	for kname in ENG_MODE_KEYS:
		mode_keys.append(_get_option_text(NodePath(root + "/Mode/TabContainer/Select/" + kname)))
	cfg["mode_keys"] = mode_keys
	# --- 每模式动态按键映射行 ---
	var modes: Array = []
	for page in ENG_MODE_PAGES:
		modes.append({"rows": _collect_eng_rows(root, page)})
	cfg["modes"] = modes
	return cfg


## 收集某个模式页的动态按键映射行
func _collect_eng_rows(root: String, page: String) -> Array:
	var rows: Array = []
	var vb: Node = get_node_or_null(NodePath(root + "/" + page + "/ScrollContainer/VBoxContainer"))
	if vb == null:
		return rows
	for child in vb.get_children():
		if not child is HBoxContainer or child.name == "Example":
			continue
		var para: Node = child.get_node_or_null("Para")
		rows.append({
			"key": _option_text(child.get_node_or_null("Key")),
			"dir": _option_text(child.get_node_or_null("Dir")),
			"mode": _option_text(child.get_node_or_null("Option")),
			"param": (para.text.strip_edges() if para is LineEdit else ""),
			"io": _option_text(child.get_node_or_null("IO")),
		})
	return rows


## 旧存档的按键映射行以 RowNN 路径存快照；场景默认只有隐藏模板行 Example。
## 打开旧项目时按配置里出现的最大行号把行补齐，避免行数据丢失。
func _ensure_eng_rows_from_config(cfg: Dictionary) -> void:
	var zone: Node = get_node_or_null(P_EDIT_ZONE)
	if zone == null:
		return
	for root in [ENGINEER, ADV_ENGINEER]:
		for page in ENG_MODE_PAGES:
			var vb: Node = get_node_or_null(NodePath(
				root + "/" + page + "/ScrollContainer/VBoxContainer"))
			if vb == null:
				continue
			var prefix: String = str(zone.get_path_to(vb)) + "/"
			var needed: int = 0
			for key in cfg.keys():
				var s: String = str(key)
				if not s.begins_with(prefix):
					continue
				var rel: String = s.substr(prefix.length())
				if not rel.begins_with("Row"):
					continue
				var n: int = rel.split("/")[0].trim_prefix("Row").to_int()
				if n > needed:
					needed = n
			while _eng_row_count(vb) < needed:
				if _add_eng_row(vb) == null:
					break


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
	if _build_controller:
		_build_controller.shutdown()
	if _download_controller:
		_download_controller.shutdown()


## 工具链管理器（惰性创建，日志接到 Output 框）
## 项目部署、外置 Keil 探测和编译等实现见 scripts/toolchain.gd，与 AI 编辑器共用
func _toolchain():
	if _tc == null:
		_tc = TC.new(_append_output)
	return _tc


## 获取项目部署路径。
## 按**项目类型**判定而非当前 Tab：工程与工程逆解算同属工程项目，
## 都应送去 ROBOMASTER_ENGINEER 模板编译（旧实现只认 Tab 1，
## 会把逆解算代码送进步兵工程）。
func _get_current_project_dst() -> String:
	if not _project_dst_override.is_empty():
		return _project_dst_override
	if not _project.is_empty():
		return AppState.project_dst_for_kind(str(_project["kind"]))
	# 没有项目时（直接运行本场景）退化成按 Tab 猜
	return AppState.project_dst_for_kind(PF.tab_to_kind(_current_tab()))


## 编译按钮回调：确认外部 Keil 目录 -> 写盘 -> 异步编译
func _on_build_pressed() -> void:
	if _build_controller == null or _build_controller.is_busy() \
			or (_download_controller != null and _download_controller.is_busy()):
		return # 防重入
	if _is_cloud_mode():
		# 云端编译：先确保云端配置（Base URL + API Key）有效，再真正编译
		CLOUD_GUIDE.ensure_cloud(self, _toolchain(), _do_build, _on_cloud_guide_cancel)
	else:
		# 本地编译：未配置/失效的外部 Keil 会先弹引导，引导成功后才真正编译
		KG.ensure_keil(self, _toolchain(), _do_build, _on_keil_guide_cancel)


func _do_build() -> void:
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
	_build_controller.start(_get_current_project_dst(), code,
		"cloud" if _is_cloud_mode() else "local")


## 用户在 Keil 目录引导对话框里点「取消」时中止编译并提示。
func _on_keil_guide_cancel() -> void:
	_append_output("[Error] 未指定 Keil 目录，编译已中止（可在下次编译时选择）")


## 导出 HEX 按钮：先按「编译」的流程编译，成功后弹保存对话框
## （复用 build_controller；成功回调见 _on_build_succeeded 的 pending 分支）
func _on_hex_export_pressed() -> void:
	if _build_controller == null or _build_controller.is_busy() \
			or (_download_controller != null and _download_controller.is_busy()):
		return # 防重入
	# 引导成功后在 _do_hex_export 内重跑原流程，_hex_export_pending 状态不丢
	if _is_cloud_mode():
		CLOUD_GUIDE.ensure_cloud(self, _toolchain(), _do_hex_export, _on_cloud_guide_cancel)
	else:
		KG.ensure_keil(self, _toolchain(), _do_hex_export, _on_keil_guide_cancel)


func _do_hex_export() -> void:
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = ""
	if code_edit is CodeEdit:
		code = code_edit.text
	if code.strip_edges().is_empty():
		_run_check()
		if code_edit is CodeEdit:
			code = code_edit.text
		if code.strip_edges().is_empty():
			_append_output("[Error] 没有可导出的代码，请先完成配置")
			return
	_hex_export_pending = true
	if not _build_controller.start(_get_current_project_dst(), code,
			"cloud" if _is_cloud_mode() else "local"):
		_hex_export_pending = false


func _on_build_busy_changed(is_busy: bool) -> void:
	var btn: Node = get_node_or_null(P_BUILD_BTN)
	if btn is BaseButton:
		btn.disabled = is_busy
		btn.text = "编译中…" if is_busy else "编译"
	var download_button: Node = get_node_or_null(P_DOWNLOAD_BTN)
	if download_button is BaseButton:
		download_button.disabled = is_busy
	var hex_export_btn: Node = get_node_or_null(P_HEX_EXPORT_BTN)
	if hex_export_btn is BaseButton:
		hex_export_btn.disabled = is_busy
	_set_upgrade_button_busy(is_busy)


func _on_build_succeeded() -> void:
	if _hex_export_pending:
		_hex_export_pending = false
		_open_hex_save_dialog()
		return
	if _solver_upgrade_active:
		_set_upgrade_progress("求解器编译完成", 28.0, "正在连接主控板…")
		if not _download_controller.start(TC.PROJECT_ENGINEER_SIM_DST):
			_fail_upgrade_retry(true, "无法开始烧录",
				"未检测到 USB-HID 设备。\n请确认板子已通过 USB 线连接，并处于 ISP 模式（拔下 USB 再插上）。")
		return
	if not _project.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["built_hash"] = _code_hash()
		_project["workflow"] = workflow
		_save_project(false)
		_update_guide()
	if _upgrade_active:
		_set_upgrade_progress("编译完成", 28.0, "正在连接主控板…")
		if not _download_controller.start(_get_current_project_dst()):
			_fail_upgrade_retry(false, "无法开始烧录",
				"未检测到 USB-HID 设备。\n请确认板子已通过 USB 线连接，并处于 ISP 模式（拔下 USB 再插上）。")


## 编译成功后弹出保存对话框，让用户选择 hex 导出位置
func _open_hex_save_dialog() -> void:
	if not _toolchain().hex_exists(_get_current_project_dst()):
		_append_output("[Error] 未找到编译产物 hex，导出中止")
		return
	var dlg := FileDialog.new()
	dlg.title = "导出 HEX 固件"
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	# 与启动页 SaveDialog 一致：走 Windows 原生保存对话框
	dlg.use_native_dialog = true
	dlg.current_file = "output.hex"
	dlg.add_filter("*.hex", "Keil HEX 固件")
	dlg.file_selected.connect(func(path: String) -> void:
		_save_hex_to(path)
		dlg.queue_free())
	dlg.close_requested.connect(dlg.queue_free)
	add_child(dlg)
	dlg.popup_centered(Vector2i(640, 480))


## 把编译产物复制到用户选择的位置（自动补 .hex 扩展名）
func _save_hex_to(dst_path: String) -> void:
	var src: String = _toolchain().get_hex_path(_get_current_project_dst())
	var src_f: FileAccess = FileAccess.open(src, FileAccess.READ)
	if src_f == null:
		_append_output("[Error] 读取编译产物失败：%s" % src)
		return
	var data: PackedByteArray = src_f.get_buffer(src_f.get_length())
	src_f.close()
	if WEB.is_web():
		# 浏览器版：直接触发下载，没有真实保存路径
		WEB.download_bytes(data, dst_path.get_file())
		_append_output("[✓] 已导出 HEX（浏览器下载）：%s" % dst_path.get_file())
		return
	var dst: String = dst_path
	if not dst.to_lower().ends_with(".hex"):
		dst += ".hex"
	var dst_f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if dst_f == null:
		_append_output("[Error] 无法写入：%s" % dst)
		return
	dst_f.store_buffer(data)
	dst_f.close()
	_append_output("[✓] 已导出 HEX：%s" % dst)


## AI 编辑入口（阶段一 -> 阶段二）。仅在 AI 功能已启用后可见。
func _on_ai_edit_pressed() -> void:
	# 功能下线：入口已隐藏，程序化触发也一律无效
	if not AI_EDIT_ENABLED:
		return
	# Web / 移动端：AI 编辑依赖桌面 WebView，提示后直接返回
	if not WEB.is_desktop():
		WEB.popup_desktop_only(self, "AI 编辑")
		return
	if not _ai_enabled and not _project.is_empty():
		return
	if _project.is_empty():
		_enter_ai_edit()
		return
	if int(_project["stage"]) >= 2:
		_enter_ai_edit()
		return
	_run_check()
	_enter_ai_edit()


func _on_ai_enable_toggled(pressed: bool) -> void:
	# 功能下线：开关已隐藏，程序化触发一律无效并复位开关状态
	if not AI_EDIT_ENABLED:
		var off_toggle: BaseButton = get_node_or_null(P_ENABLE_AI_BTN)
		if off_toggle is BaseButton:
			off_toggle.set_pressed_no_signal(false)
		return
	# Web / 移动端：AI 编辑依赖桌面 WebView，开关不生效并提示
	if pressed and not WEB.is_desktop():
		var toggle: BaseButton = get_node_or_null(P_ENABLE_AI_BTN)
		if toggle is BaseButton:
			toggle.set_pressed_no_signal(false)
		WEB.popup_desktop_only(self, "AI 编辑")
		return
	if _loading:
		return
	if pressed:
		if _ai_enabled:
			_apply_ai_gate(true)
			return
		# warn_ai 页面自带文案（启用 AI 编辑），这里不改动它的文本，只接回调
		_show_countdown_scene(WARN_AI_SCENE,
			"", "", "", "", "",
			Callable(self, "_on_ai_enable_confirmed"), Callable(self, "_on_ai_enable_canceled"))
		return
	_apply_ai_gate(false)
	if not AppState.project_path.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["ai_enabled"] = false
		_project["workflow"] = workflow
		_save_project(false)


func _on_ai_enable_confirmed() -> void:
	_apply_ai_gate(true)
	if not AppState.project_path.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["ai_enabled"] = true
		_project["workflow"] = workflow
		_save_project(false)


func _on_ai_enable_canceled() -> void:
	_loading = true
	var enable_btn: Node = get_node_or_null(P_ENABLE_AI_BTN)
	if enable_btn is BaseButton:
		enable_btn.button_pressed = false
	_loading = false
	_apply_ai_gate(false)


## 真正进入 AI 编辑：把阶段一的配置与生成代码冻结进 .pieproj，然后切场景
func _enter_ai_edit() -> void:
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
	var tab: int = _current_tab()
	if _project.is_empty():
		# 无项目（直跑本场景）：只切场景，没有阶段概念
		AppState.set_context(project_dst, PF.tab_to_kind(tab), tab)
		get_tree().change_scene_to_file(AI_EDIT_SCENE)
		return
	# 冻结阶段一：配置快照 + 生成代码；AI 从这份代码起步
	if int(_project["stage"]) < 2:
		_project["config"] = _snapshot_config()
		_project["ik_config"] = _ik_config.duplicate(true)
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
	var tab: int = _current_tab()
	if tab == 2 and not _ik_confirmed:
		# warn_ik 页面自带文案（启用机械臂逆解），这里不改动它的文本，只接回调
		_show_countdown_scene(WARN_IK_SCENE,
			"", "", "", "", "",
			Callable(self, "_on_ik_gate_confirmed_and_open_sim"), Callable(self, "_on_ik_gate_canceled"))
		return
	var scene_path: String = ""
	var cfg: Dictionary = {}
	match tab:
		0:
			scene_path = INFANTRY_SIM_SCENE
			cfg = _collect_config()
		2:
			scene_path = ARM_SIM_SCENE
			cfg = {
				"ik": _collect_ik_config(),
				"engineer": _collect_engineer_config(),
				"editable": not _stage2_preview,
			}
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
	if _arm_sim.has_signal("solver_build_requested"):
		_arm_sim.solver_build_requested.connect(_on_solver_build_requested)
	# set_config 在 add_child 之前调用，_ready 里会自行应用
	if _arm_sim.has_method("set_config"):
		_arm_sim.set_config(cfg)
	add_child(_arm_sim)
	# 3D 仿真视图全屏覆盖且拦截鼠标，升级进度面板必须始终排在它之后，
	# 否则面板的按钮（完成/关闭）无法被点击或悬停。
	var panel_front: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel_front != null:
		panel_front.move_to_front()


func _on_arm_sim_closed() -> void:
	if _arm_sim == null:
		return
	_arm_sim.queue_free()
	_arm_sim = null

func _on_solver_build_requested() -> void:
	# 自愈：进度面板已隐藏但标志残留（上次流程异常结束）时自动清理，
	# 否则之后所有点击都会被静默拦截，表现为“点了没反应”。
	if (_solver_upgrade_active or _upgrade_active) and not _upgrade_panel_visible():
		_solver_upgrade_active = false
		_upgrade_active = false
		_project_dst_override = ""
		_set_upgrade_button_busy(false)
	if _solver_upgrade_active or _upgrade_active or _build_controller == null \
			or _build_controller.is_busy() or _download_controller == null \
			or _download_controller.is_busy():
		var reason: String = _solver_block_reason()
		if not reason.is_empty():
			_append_output("[Warn] 暂无法开始求解器编译：%s" % reason)
		return
	# 配置校验/代码生成是纯计算、不依赖 Keil，先做（配置错误的提示优先级更高）；
	# 校验与生成都通过后，才需要确认外部 Keil 目录（引导成功再进入状态置位与编译）。
	var ik_config: Dictionary = IK_CONFIG.normalize(_collect_ik_config())
	var validation: Dictionary = IK_CONFIG.validate(ik_config, _collect_engineer_config())
	var errors: Array[String] = []
	var io_issues: Array[String] = []
	for issue in validation.get("issues", []):
		if str(issue.get("type", "")) != "Error":
			continue
		var message: String = str(issue.get("msg", ""))
		# MCU 求解器固件不初始化任何执行器 IO（generate_simulator 明确无 IO），
		# 因此 IO 冲突/初始化错误不影响求解器编译，只影响正式固件
		# （编译正式固件时会再次检查）。
		if message.contains("IO"):
			io_issues.append(message)
		else:
			errors.append(message)
	if not io_issues.is_empty():
		_append_output("[Info] MCU 求解器无执行器 IO，已忽略 %d 条 IO 配置问题（编译正式固件时仍会检查）：" \
			% io_issues.size())
		for message in io_issues:
			_append_output("  - " + message)
	if not errors.is_empty():
		_append_output("[Error] MCU 求解器构型无效，未开始编译：")
		for message in errors:
			_append_output("  - " + message)
		# 3D 仿真全屏覆盖主界面输出面板，必须弹窗让用户能看到失败原因
		_show_solver_error_dialog("MCU 求解器构型无效", errors)
		return
	var code: String = CodeGenEngineerIK.new().generate_simulator(ik_config)
	if code.is_empty():
		_append_output("[Error] 无法生成 MCU 求解器固件")
		_show_solver_error_dialog("无法生成 MCU 求解器固件", ["生成器返回空代码，请检查配置。"])
		return
	# 首次烧录指引（求解器固件同样写入主控板，开关必须先断开），确认后再走 Keil 引导
	FFG.ensure_guide(self, _continue_solver_build.bind(code))


func _continue_solver_build(code: String) -> void:
	# 确认外部 Keil 目录（引导成功）后再编译；状态置位在 _start_solver_build 内，取消不残留
	KG.ensure_keil(self, _toolchain(), _start_solver_build.bind(code), _on_keil_guide_cancel)


func _start_solver_build(code: String) -> void:
	if _arm_sim != null and _arm_sim.has_method("prepare_solver_build"):
		_arm_sim.prepare_solver_build()
	_solver_upgrade_active = true
	_upgrade_active = true
	_project_dst_override = TC.PROJECT_ENGINEER_SIM_DST
	_set_upgrade_button_busy(true)
	# 显示进度面板（此前只 set_progress 未 show，3D 页面点击后无反馈）
	var panel_sim: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel_sim != null and panel_sim.has_method("begin_solver"):
		panel_sim.begin_solver()
	_set_upgrade_progress("正在编译 MCU 求解器", 8.0, "仿真固件不会初始化或输出任何执行器 IO。")
	if not _build_controller.start(TC.PROJECT_ENGINEER_SIM_DST, code):
		_solver_upgrade_active = false
		_project_dst_override = ""
		_fail_upgrade("无法开始编译", "请查看下方输出中的详细提示。")


## 返回求解器编译被拦截的具体原因（空串=未被拦截）。
## 用于把“点击无反应”变成可读的提示，方便定位是状态残留还是控制器卡死。
func _solver_block_reason() -> String:
	if _solver_upgrade_active:
		return "上一次求解器编译/烧录流程尚未结束（若进度面板已关闭请重启编辑器）"
	if _upgrade_active:
		return "主控板升级流程正在进行中"
	if _build_controller == null:
		return "编译控制器未初始化"
	if _download_controller == null:
		return "烧录控制器未初始化"
	if _build_controller.is_busy():
		return "编译器正在运行，请等待完成"
	if _download_controller.is_busy():
		return "烧录正在进行，请等待完成"
	return ""


## 步兵仿真里标定出来的云台归中角回填到配置界面，再重跑检查与代码生成
func _on_infantry_sim_config_changed(cfg: Dictionary) -> void:
	_set_line_text(P_YAW_MID_OFFSET, str(cfg.get("yaw_mid_offset", "")))
	_set_line_text(P_PITCH_MID_OFFSET, str(cfg.get("pitch_mid_offset", "")))
	_run_check()


## 把 3D 标定台里的编辑结果写回配置界面控件，再重跑检查与代码生成。
## 只回填仿真能改的字段，IO/方向/摇杆映射等仍由配置界面独占。
func _on_arm_sim_config_changed(payload: Dictionary) -> void:
	if _stage2_preview:
		return
	var next_ik: Variant = payload.get("ik", payload)
	var prev_enabled: bool = bool(_ik_config.get("enabled", false))
	_ik_config = IK_CONFIG.normalize(next_ik)
	_ik_config["enabled"] = prev_enabled
	var io_patch: Dictionary = payload.get("io_init", {})
	_loading = true
	for pin in io_patch.keys():
		if ENG_IO_REL.has(pin):
			var node: Node = get_node_or_null(NodePath(_shared_cfg_root() + "/" + str(ENG_IO_REL.get(pin, ""))))
			if node is OptionButton:
				_select_option_by_text(node, str(io_patch[pin]))
	_loading = false
	_mark_dirty()
	_run_check()
	_update_ik_summary()


## 按显示文本选中 OptionButton 的对应项（找不到则保持原选择）
func _select_option_by_text(btn: OptionButton, text: String) -> void:
	if text.is_empty():
		return
	for i in range(btn.item_count):
		if btn.get_item_text(i) == text:
			btn.selected = i
			return


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


# ------------------------------------------------------------------ 下载/烧录
func _on_download_pressed() -> void:
	if _download_controller == null or _download_controller.is_busy() \
			or (_build_controller != null and _build_controller.is_busy()):
		return
	# 首次烧录指引：确认板上开关已断开（可勾选「不再显示」）后再烧录
	FFG.ensure_guide(self, _start_download)


func _start_download() -> void:
	_download_controller.start(_get_current_project_dst())


func _on_download_busy_changed(is_busy: bool) -> void:
	var button: Node = get_node_or_null(P_DOWNLOAD_BTN)
	if button is BaseButton:
		button.disabled = is_busy
		button.text = "烧录中…" if is_busy else "烧录主控板"
	var build_button: Node = get_node_or_null(P_BUILD_BTN)
	if build_button is BaseButton:
		build_button.disabled = is_busy
	var hex_export_btn: Node = get_node_or_null(P_HEX_EXPORT_BTN)
	if hex_export_btn is BaseButton:
		hex_export_btn.disabled = is_busy
	_set_upgrade_button_busy(is_busy)
	# 烧录阶段允许取消（编译阶段取消按钮保持禁用）。
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("set_cancel_enabled"):
		panel.set_cancel_enabled(is_busy)


func _on_download_succeeded() -> void:
	if _solver_upgrade_active:
		_solver_upgrade_active = false
		_upgrade_active = false
		_project_dst_override = ""
		_append_output("MCU 求解器已烧录；进入操控模式后将自动握手并校验构型指纹。")
		var panel_sim: Node = get_node_or_null(P_UPGRADE_PROGRESS)
		if panel_sim != null and panel_sim.has_method("complete"):
			panel_sim.complete()
		_set_upgrade_button_busy(false)
		if not _project.is_empty():
			var sim_workflow: Dictionary = _workflow()
			sim_workflow["firmware_mode"] = "simulator"
			sim_workflow["flashed_hash"] = ""
			sim_workflow["hardware_tested"] = false
			_project["workflow"] = sim_workflow
			_save_project(false)
			_update_ik_summary()
			_update_guide()
		if _arm_sim != null and _arm_sim.has_method("reconnect_mcu_solver_after_flash"):
			_arm_sim.call_deferred("reconnect_mcu_solver_after_flash")
		return
	if not _project.is_empty():
		var workflow: Dictionary = _workflow()
		workflow["flashed_hash"] = _code_hash()
		workflow["firmware_mode"] = "production"
		workflow["hardware_tested"] = false
		_project["workflow"] = workflow
		_save_project(false)
		_update_guide()
	if _upgrade_active:
		_upgrade_active = false
		var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
		if panel != null and panel.has_method("complete"):
			panel.complete()
		_set_upgrade_button_busy(false)


func _on_upgrade_pressed() -> void:
	if _upgrade_active or _build_controller == null or _build_controller.is_busy() \
			or _download_controller == null or _download_controller.is_busy():
		return
	# 首次烧录指引：确认板上开关已断开（可勾选「不再显示」）后再进入升级流程
	FFG.ensure_guide(self, _continue_upgrade_pressed)


func _continue_upgrade_pressed() -> void:
	# 引导成功后才进入升级流程（_upgrade_active 在 _do_upgrade 内置位，取消不残留）
	# 云端编译模式下不需要本机 Keil，只需确认云端配置
	if _is_cloud_mode():
		CLOUD_GUIDE.ensure_cloud(self, _toolchain(), _do_upgrade, _on_cloud_guide_cancel)
	else:
		KG.ensure_keil(self, _toolchain(), _do_upgrade, _on_keil_guide_cancel)


func _do_upgrade() -> void:
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = code_edit.text if code_edit is CodeEdit else ""
	if code.strip_edges().is_empty():
		_run_check()
		code = code_edit.text if code_edit is CodeEdit else ""
	if code.strip_edges().is_empty():
		_append_output("[Error] 没有可升级的代码，请先完成配置")
		return
	_upgrade_active = true
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("begin"):
		panel.begin()
	_set_upgrade_progress("正在编译程序", 8.0, "编译成功后会自动烧录到主控板。")
	_set_upgrade_button_busy(true)
	if not _build_controller.start(_get_current_project_dst(), code,
			"cloud" if _is_cloud_mode() else "local"):
		_fail_upgrade("无法开始编译", "请查看下方输出中的详细提示。")


func _on_upgrade_progress_changed(stage: String, percent: float, detail: String) -> void:
	if _upgrade_active:
		_set_upgrade_progress(stage, percent, detail)


func _on_upgrade_build_finished(result: Dictionary) -> void:
	if _upgrade_active and not bool(result.get("ok", false)):
		var project_stage: int = int(_project.get("stage", AppState.stage))
		_show_upgrade_error_scene(project_stage, str(result.get("log", "")))
		_fail_upgrade("编译失败",
			UPGRADE_PROGRESS.compile_error_hint(project_stage))


func _on_upgrade_download_finished(result: Dictionary) -> void:
	# 用户取消 / 硬超时：显示「已取消」状态，而不是「烧录失败」。
	if bool(result.get("canceled", false)):
		if not (_upgrade_active or _solver_upgrade_active):
			return
		_upgrade_active = false
		_solver_upgrade_active = false
		_project_dst_override = ""
		var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
		if panel != null and panel.has_method("canceled"):
			if str(result.get("stage", "")) == "timeout":
				panel.canceled("烧录超时，已自动取消并释放串口，可以重新升级。")
			else:
				panel.canceled()
		_set_upgrade_button_busy(false)
		return
	if not bool(result.get("ok", false)):
		var failed_stage: String = str(result.get("stage", ""))
		if _upgrade_active:
			# 连不上主控板（HID 未连接/中途掉线）：弹窗带「重试」，重新连接后可直接重试
			if failed_stage in ["", "connect"]:
				_fail_upgrade_retry(_solver_upgrade_active, "烧录失败",
					"未能连接主控板。\n请确认板子已通过 USB 线连接，并处于 ISP 模式（拔下 USB 再插上）。")
			else:
				_fail_upgrade("烧录失败", "连接或写入未完成，请查看下方输出。")
		# 连不上板子（connect 阶段）时，提示重新插拔 USB 让板子回到 ISP 模式
		if failed_stage in ["", "connect"]:
			_append_output("\n[提示] 烧录没能连上主控板。")
			_append_output("请确认板子已通过 USB 线连接，并处于 ISP 模式：")
			_append_output("  拔下 USB 线再插上（冷启动进入 ISP），然后重新点「烧录主控板」。")


func _on_upgrade_cancel_pressed() -> void:
	if _download_controller != null and _download_controller.is_busy():
		_download_controller.cancel()
	# 编译阶段取消按钮是禁用的，无需处理。


func _set_upgrade_progress(stage: String, percent: float, detail: String) -> void:
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("set_progress"):
		panel.set_progress(stage, percent, detail)


## 进度面板当前是否可见。用于区分「流程正在进行」与「标志残留」。
func _upgrade_panel_visible() -> bool:
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	return panel != null and panel.visible


## 升级主控编译失败弹窗：阶段一且未开启逆解属于基础功能，编译错误不可容忍，
## 弹致命错误页；第二阶段或已开启逆解属于高级功能，编译错误可容忍，弹普通错误页。
## 保留场景自带文案，只把编译日志填进页面的 TextEdit。
func _show_upgrade_error_scene(project_stage: int, log_text: String) -> void:
	var advanced: bool = project_stage >= 2 or _ik_confirmed
	var scene_path: String = ERROR_SCENE if advanced else FATAL_ERROR_SCENE
	_show_countdown_scene(scene_path, "", "", "", "", log_text)


## 求解器编译失败弹窗：3D 仿真全屏覆盖主界面输出面板，
## 错误必须弹出可见对话框，否则用户以为「点击没反应」。
func _show_solver_error_dialog(title: String, messages: Array) -> void:
	var scene_path: String = ERROR_SCENE if title.contains("构型") else FATAL_ERROR_SCENE
	_show_countdown_scene(scene_path,
		title,
		"您在使用高级功能时遇到了编译错误，这是可被容忍的，但在修复范围内",
		"确认并导出错误的项目文件", "", "\n".join(messages))


func _fail_upgrade(stage: String, detail: String) -> void:
	_upgrade_active = false
	_solver_upgrade_active = false
	_project_dst_override = ""
	_retry_download_dst = ""
	_retry_is_solver = false
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("fail"):
		panel.fail(stage, detail)
	_set_upgrade_button_busy(false)


## 烧录前连接失败（如未检测到 USB-HID 设备）：弹窗带「重试」按钮，
## 用户重新连接设备后点重试可直接烧录，无需重新编译。
func _fail_upgrade_retry(is_solver: bool, stage: String, detail: String) -> void:
	_retry_download_dst = TC.PROJECT_ENGINEER_SIM_DST if is_solver \
		else _get_current_project_dst()
	_retry_is_solver = is_solver
	_upgrade_active = false
	_solver_upgrade_active = false
	_project_dst_override = ""
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("fail_with_retry"):
		panel.fail_with_retry(stage, detail)
	_set_upgrade_button_busy(false)


## 弹窗「重试」按钮：设备重新连接后重跑烧录（编译产物已存在，无需重新编译）。
func _on_upgrade_retry_pressed() -> void:
	var dst: String = _retry_download_dst
	var is_solver: bool = _retry_is_solver
	_retry_download_dst = ""
	_retry_is_solver = false
	if dst.is_empty() or _download_controller == null \
			or _download_controller.is_busy() \
			or (_build_controller != null and _build_controller.is_busy()):
		return
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null:
		if is_solver and panel.has_method("begin_solver"):
			panel.begin_solver()
		elif panel.has_method("begin"):
			panel.begin()
	_upgrade_active = true
	_solver_upgrade_active = is_solver
	_set_upgrade_progress("正在连接主控板", 30.0, "正在启动烧录程序…")
	_set_upgrade_button_busy(true)
	if not _download_controller.start(dst):
		_fail_upgrade_retry(is_solver, "无法开始烧录",
			"未检测到 USB-HID 设备。\n请确认板子已通过 USB 线连接，并处于 ISP 模式（拔下 USB 再插上）。")


func _set_upgrade_button_busy(is_busy: bool) -> void:
	var button: Node = get_node_or_null(P_UPGRADE_BTN)
	if button is BaseButton:
		button.disabled = is_busy
		button.text = "升级中…" if is_busy else "升级主控板"


## 升级/求解器烧录进度面板关闭后，重置标志并恢复按钮状态。
## complete()/fail() 已经 show 了关闭按钮，用户点「完成/关闭」后来到这里。
func _on_upgrade_panel_closed() -> void:
	_upgrade_active = false
	_solver_upgrade_active = false
	_project_dst_override = ""
	_set_upgrade_button_busy(false)

extends SceneTree

## 按键映射行「控制方式」下拉按 IO 类型 + 键位类型过滤的 UI 端到端验证。
## 合法性矩阵与 static_checker 一致：
##   舵机（MP03/MP74 恒舵机，或拓展板引脚在 IO 初始化区选舵机）+ 按键 -> 增量/直接
##   舵机 + 摇杆轴(LX/LY/RX/RY)                     -> 增量
##   电机 + 按键                                    -> 直接
##   电机 + 摇杆轴                                  -> 速度/增速
## 当前选中项被过滤掉时自动回退到第一项。
## 工程页的底盘锁定、摇杆保留开关等程序化改动也要同步刷新。

const UI_SCENE_PATH: String = "res://scenes/ui.tscn"
const CHASSIS_L1: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/L1/OptionButton"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


## 收集某个模式页所有真实行的「控制方式」选项文本
func _row_modes(ui: Node, page: String) -> Array:
	var out: Array = []
	var vb: Node = ui.get_node_or_null(NodePath(page + "/ScrollContainer/VBoxContainer"))
	if vb == null:
		return out
	for child in vb.get_children():
		if child is HBoxContainer and child.name != "Example":
			out.append(ui._option_text(child.get_node_or_null("Option")))
	return out


func _row_ios(ui: Node, page: String) -> Array:
	var out: Array = []
	var vb: Node = ui.get_node_or_null(NodePath(page + "/ScrollContainer/VBoxContainer"))
	if vb == null:
		return out
	for child in vb.get_children():
		if child is HBoxContainer and child.name != "Example":
			out.append(ui._option_text(child.get_node_or_null("IO")))
	return out


## 程序化选择下拉项并同步过滤（真实 UI 靠 item_selected 信号触发）
func _pick(ui: Node, btn: Node, text: String) -> void:
	if not btn is OptionButton:
		return
	for i in range(btn.item_count):
		if btn.get_item_text(i) == text:
			btn.selected = i
			ui._update_engineer_placeholders()
			return
	push_error("下拉项不存在：%s" % text)


func _set_io_init(ui: Node, pin: String, type: String) -> void:
	var btn: Node = ui.get_node_or_null(NodePath(ui._eng_io_path(pin)))
	if btn is OptionButton:
		for i in range(btn.item_count):
			if btn.get_item_text(i) == type:
				btn.selected = i
				ui._update_engineer_placeholders()
				return
	push_error("IO 初始化控件未找到：%s" % pin)


func _mode_items(btn: Node) -> Array:
	var out: Array = []
	if btn is OptionButton:
		for i in range(btn.item_count):
			out.append(btn.get_item_text(i))
	return out


func _pin_item_disabled(btn: OptionButton, pin: String) -> bool:
	for i in range(btn.item_count):
		if btn.get_item_text(i).split(" ")[0] == pin:
			return btn.is_item_disabled(i)
	return true


func _has_pin(btn: OptionButton, pin: String) -> bool:
	for i in range(btn.item_count):
		if btn.get_item_text(i).split(" ")[0] == pin:
			return true
	return false


func _initialize() -> void:
	print("=== 按键映射行控制方式过滤验证 ===")
	# In --script mode autoload names are registered after this script's constants.
	# Load the UI at runtime so ui.gd can resolve the AppState singleton.
	await process_frame
	var ui_scene: PackedScene = load(UI_SCENE_PATH)
	var ui = ui_scene.instantiate()
	root.add_child(ui)
	await process_frame

	ui._apply_kind_visibility("engineer", 1)
	var engineer_l1: OptionButton = ui.get_node(CHASSIS_L1)
	_check("工程构型底盘不提供 P64/P66",
		not _has_pin(engineer_l1, "P64") and not _has_pin(engineer_l1, "P66"))
	var engineer_p64_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P64")))
	var engineer_p66_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P66")))
	var engineer_p60_mid: LineEdit = ui.get_node(NodePath(ui._eng_io_mid_path("P60")))
	_check("工程 P64/P66 提供四种输出角色",
		_mode_items(engineer_p64_type) == ["舵机", "摩擦轮", "抖动电机", "平滑电机"]
		and _mode_items(engineer_p66_type) == ["舵机", "摩擦轮", "抖动电机", "平滑电机"])
	var engineer_pwma: OptionButton = ui.get_node(ui._eng_pwm_group_path(ui.ENGINEER, "PWMA"))
	var engineer_pwmb: OptionButton = ui.get_node(ui._eng_pwm_group_path(ui.ENGINEER, "PWMB"))
	_check("工程 PWMA/PWMB 提供 50Hz 与 10000Hz",
		_mode_items(engineer_pwma) == ["50Hz（摩擦轮/舵机/抖动电机）", "10000Hz（平滑电机）"]
		and _mode_items(engineer_pwmb) == _mode_items(engineer_pwma)
		and not engineer_pwma.disabled and not engineer_pwmb.disabled)
	engineer_pwma.select(1)
	engineer_pwmb.select(0)
	var collected_pwm: Dictionary = ui._collect_engineer_config()
	_check("工程 PWM 组配置独立收集",
		collected_pwm.get("pwm_group_init", {}).get("PWMA", "") == "10000Hz"
		and collected_pwm.get("pwm_group_init", {}).get("PWMB", "") == "50Hz"
		and collected_pwm.has("io_role")
		and not collected_pwm.has("io_init"))
	var eng_page: String = ui.ENGINEER + "/TabContainer/M1"
	var vb: Node = ui.get_node(NodePath(eng_page + "/ScrollContainer/VBoxContainer"))
	# 默认场景 0 真实行，先加两行
	var row1: Node = ui._add_eng_row(vb)
	var row2: Node = ui._add_eng_row(vb)

	# ---- 舵机 + 按键：增量/直接（默认 P60 舵机） ----
	var opt1: OptionButton = row1.get_node("Option")
	_check("默认行(P60舵机+按键)选项为 增量/直接",
		[_mode_items(opt1), opt1.item_count] == [["增量", "直接"], 2], str(_mode_items(opt1)))
	_pick(ui, row1.get_node("IO"), "P62")
	_check("行内切到 P62(舵机) 仍是 增量/直接",
		_mode_items(opt1) == ["增量", "直接"], str(_mode_items(opt1)))

	# ---- IO 初始化区切成电机：按键行只剩 直接，原选中 增量 回退 ----
	_pick(ui, row1.get_node("IO"), "P60")
	_pick(ui, opt1, "增量")
	_set_io_init(ui, "P60", "平滑电机")
	_check("P60 切电机+按键后行选项为 直接",
		_mode_items(opt1) == ["直接"], str(_mode_items(opt1)))
	_check("原选中 增量 自动回退到 直接",
		ui._option_text(opt1) == "直接", ui._option_text(opt1))
	var para1: LineEdit = row1.get_node("Para")
	_check("电机直接模式占位为速度", para1.placeholder_text.contains("速度"))
	_check("P60 选电机后隐藏初始角", not engineer_p60_mid.visible)

	# ---- 电机 + 摇杆轴：速度/增速 ----
	_pick(ui, row1.get_node("Key"), "RX")
	_check("P60 切电机+摇杆RX后行选项为 速度/增速",
		_mode_items(opt1) == ["速度", "增速"], str(_mode_items(opt1)))
	_pick(ui, row1.get_node("Key"), "E")
	_check("摇杆切回按键后恢复 直接",
		_mode_items(opt1) == ["直接"], str(_mode_items(opt1)))

	# ---- 切回舵机：恢复 增量/直接 ----
	_set_io_init(ui, "P60", "舵机")
	_check("P60 切回舵机后选项恢复 增量/直接",
		_mode_items(opt1) == ["增量", "直接"], str(_mode_items(opt1)))
	_check("舵机直接模式占位包含正反方向", para1.placeholder_text.contains("正/反"))
	_check("P60 切回舵机后显示初始角", engineer_p60_mid.visible)

	# ---- 舵机 + 摇杆轴：只剩 增量，原选中 直接 回退 ----
	_pick(ui, opt1, "直接")
	_pick(ui, row1.get_node("Key"), "RY")
	_check("舵机+摇杆RY后行选项只剩 增量",
		_mode_items(opt1) == ["增量"], str(_mode_items(opt1)))
	_check("原选中 直接 自动回退到 增量", ui._option_text(opt1) == "增量")
	_check("舵机增量模式占位为步长", para1.placeholder_text.contains("步长"))
	_pick(ui, row1.get_node("Key"), "E")

	# ---- MP03 恒舵机，不受 IO 初始化区影响 ----
	_pick(ui, row2.get_node("IO"), "MP03")
	_set_io_init(ui, "MP03", "平滑电机")
	var opt2: OptionButton = row2.get_node("Option")
	_check("MP03 恒舵机+按键选项为 增量/直接（IO初始化区设为电机也不变）",
		_mode_items(opt2) == ["增量", "直接"], str(_mode_items(opt2)))
	_pick(ui, row2.get_node("Key"), "RX")
	_check("MP03 恒舵机+摇杆RX选项只剩 增量",
		_mode_items(opt2) == ["增量"], str(_mode_items(opt2)))
	_pick(ui, row2.get_node("Key"), "E")

	# ---- 新建行按当前目标 IO 过滤 ----
	_pick(ui, row2.get_node("IO"), "P64")
	_set_io_init(ui, "P64", "平滑电机")
	var row3: Node = ui._add_eng_row(vb)
	_pick(ui, row3.get_node("IO"), "P64")
	var opt3: OptionButton = row3.get_node("Option")
	_check("新建行选电机IO+按键后选项为 直接",
		_mode_items(opt3) == ["直接"], str(_mode_items(opt3)))
	_pick(ui, row3.get_node("Key"), "RY")
	_check("新建行选电机IO+摇杆后选项为 速度/增速",
		_mode_items(opt3) == ["速度", "增速"], str(_mode_items(opt3)))

	# ---- 旧存档回填：配置里的行在 _apply_config 后按 IO 初始化区过滤 ----
	var cfg: Dictionary = ui._snapshot_config()
	_set_io_init(ui, "P62", "平滑电机")
	ui._apply_config(cfg)
	_check("回填后行仍存在", _row_ios(ui, eng_page).size() >= 2)
	var opt4: OptionButton = row1.get_node("Option")
	# 回填恢复 P60=舵机、Key=E -> 增量/直接
	_check("回填后按 IO 初始化区过滤",
		_mode_items(opt4) == ["增量", "直接"], str(_mode_items(opt4)))

	# ---- 步兵高级设置仅提供独立选项，不恢复工程 IO/模式配置 ----
	ui._apply_kind_visibility("infantry", 0)
	_check("步兵页高级设置提供禁用蜂鸣器",
		ui.get_node_or_null(NodePath(ui.ADV_ENGINEER + "/PWMGroups/Buzzer/CheckBox")) is CheckBox)
	_check("步兵页不恢复工程 IO 设置",
		ui.get_node_or_null(NodePath(ui.ADV_ENGINEER + "/IOs")) == null)
	# ---- 摩擦轮类型：无刷保留 P64/P66；禁用后释放并关闭参数控件 ----
	var friction_type: OptionButton = ui.get_node(ui.P_FRICTION_TYPE)
	var friction_key: OptionButton = ui.get_node(ui.P_BOOSTER_KEY)
	var friction_duty: LineEdit = ui.get_node(ui.P_FRICTION_MAX_DUTY)
	var friction_up: OptionButton = ui.get_node(ui.P_FRICTION_SPEED_UP_KEY)
	var friction_down: OptionButton = ui.get_node(ui.P_FRICTION_SPEED_DOWN_KEY)
	var friction_step: LineEdit = ui.get_node(ui.P_FRICTION_SPEED_STEP)
	var infantry_motor_selectors: Array = [
		ui.get_node(ui.P_L1_IO), ui.get_node(ui.P_L2_IO),
		ui.get_node(ui.P_R1_IO), ui.get_node(ui.P_R2_IO),
		ui.get_node(ui.P_BOOSTER_IO),
	]
	var unsupported_motor_pins_absent: bool = true
	for port_btn in infantry_motor_selectors:
		unsupported_motor_pins_absent = unsupported_motor_pins_absent \
			and not _has_pin(port_btn, "P64") and not _has_pin(port_btn, "P66")
	_check("步兵轮电机和拨弹电机不提供 P64/P66", unsupported_motor_pins_absent)
	var infantry_gimbal_selectors: Array = [ui.get_node(ui.P_YAW_IO), ui.get_node(ui.P_PITCH_IO)]
	var brushless_reserved: bool = true
	for port_btn in infantry_gimbal_selectors:
		brushless_reserved = brushless_reserved \
			and _pin_item_disabled(port_btn, "P64") and _pin_item_disabled(port_btn, "P66")
	_check("默认无刷模式锁定云台 P64/P66", brushless_reserved)
	_pick(ui, friction_type, "不使用")
	ui._sync_friction_type_ui()
	var disabled_released: bool = true
	for port_btn in infantry_gimbal_selectors:
		disabled_released = disabled_released \
			and not _pin_item_disabled(port_btn, "P64") and not _pin_item_disabled(port_btn, "P66")
	_check("不使用摩擦轮时释放云台 P64/P66", disabled_released)
	_check("不使用摩擦轮时隐藏并禁用全部速度控件",
		friction_key.disabled and not friction_duty.editable
		and friction_up.disabled and friction_down.disabled and not friction_step.editable
		and not ui.get_node(ui.P_FRICTION_SPEED_ROW).visible
		and not ui.get_node(ui.P_FRICTION_SPEED_CONTROL_ROW).visible)
	var friction_l1: OptionButton = ui.get_node(ui.P_L1_IO)
	_check("无刷模式下轮电机仍不提供 P64/P66",
		not _has_pin(friction_l1, "P64") and not _has_pin(friction_l1, "P66"))
	_pick(ui, friction_type, "无刷电调")
	ui._sync_friction_type_ui()
	var collected_friction: Dictionary = ui._collect_config()
	_check("摩擦轮新控件接线并收集配置",
		collected_friction.has("friction_max_duty")
		and collected_friction.has("friction_speed_up_key")
		and collected_friction.has("friction_speed_down_key")
		and collected_friction.has("friction_speed_step"))
	ui._apply_config({"Infantry/KeySetting/Booster/MaxDuty": {"t": "700"}})
	_check("旧 Booster/MaxDuty 配置可回填到新控件", friction_duty.text == "700")
	_check("切回无刷后轮电机仍不提供 P64/P66",
		not _has_pin(friction_l1, "P64") and not _has_pin(friction_l1, "P66"))

	# ---- 底盘锁定：选中的引脚强制为电机，相关行选项同步刷新 ----
	ui._apply_kind_visibility("engineer", 1)
	var l1: OptionButton = ui.get_node(CHASSIS_L1)
	_pick(ui, row1.get_node("IO"), "P60")
	_pick(ui, opt4, "增量")
	_pick(ui, l1, "P60 P61")
	ui._sync_io_locks()
	_check("底盘锁定 P60 后行选项刷新为 直接（电机）",
		_mode_items(opt4) == ["直接"], str(_mode_items(opt4)))
	_check("底盘锁定后 P60 在输出角色区被强制为平滑电机",
		ui._option_text(ui.get_node(NodePath(ui._eng_io_path("P60")))) == "平滑电机")

	if _fail > 0:
		print("失败 %d 项" % _fail)
		quit(1)
	else:
		print("全部通过")
		quit(0)

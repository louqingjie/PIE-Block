extends SceneTree

## 按键映射行「控制方式」下拉按 IO 类型 + 键位类型过滤的 UI 端到端验证。
## 合法性矩阵与 static_checker 一致：
##   舵机（MP03/MP74 恒舵机，或拓展板引脚在 IO 初始化区选舵机）+ 按键 -> 增量/直接
##   舵机 + 摇杆轴(LX/LY/RX/RY)                     -> 增量
##   电机 + 按键                                    -> 直接
##   电机 + 摇杆轴                                  -> 速度/增速
## 当前选中项被过滤掉时自动回退到第一项。
## 工程页与步兵高级设置（ADV_ENGINEER）两份实例都要过滤；底盘锁定、摇杆保留
## 开关等程序化改动也要同步刷新。

const UI_SCENE_PATH: String = "res://scenes/ui.tscn"
const CHASSIS_L1: NodePath = "VBoxContainer/HBoxContainer/HSplitContainer/FirstRow/Chassis/L1/OptionButton"
const SC = preload("res://scripts/static_checker.gd")

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
	_check("工程构型底盘可使用 P64/P66",
		not _pin_item_disabled(engineer_l1, "P64") and not _pin_item_disabled(engineer_l1, "P66"))
	var engineer_p64_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P64")))
	var engineer_p66_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P66")))
	var engineer_p60_mid: LineEdit = ui.get_node(NodePath(ui._eng_io_mid_path("P60")))
	_check("工程 P64/P66 仍保持电机/舵机",
		_mode_items(engineer_p64_type) == ["电机", "舵机"]
		and _mode_items(engineer_p66_type) == ["电机", "舵机"])
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
	_set_io_init(ui, "P60", "电机")
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
	_check("舵机直接模式占位为偏移角", para1.placeholder_text.contains("偏移角"))
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
	_set_io_init(ui, "MP03", "电机")
	var opt2: OptionButton = row2.get_node("Option")
	_check("MP03 恒舵机+按键选项为 增量/直接（IO初始化区设为电机也不变）",
		_mode_items(opt2) == ["增量", "直接"], str(_mode_items(opt2)))
	_pick(ui, row2.get_node("Key"), "RX")
	_check("MP03 恒舵机+摇杆RX选项只剩 增量",
		_mode_items(opt2) == ["增量"], str(_mode_items(opt2)))
	_pick(ui, row2.get_node("Key"), "E")

	# ---- 新建行按当前目标 IO 过滤 ----
	_pick(ui, row2.get_node("IO"), "P64")
	_set_io_init(ui, "P64", "电机")
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
	_set_io_init(ui, "P62", "电机")
	ui._apply_config(cfg)
	_check("回填后行仍存在", _row_ios(ui, eng_page).size() >= 2)
	var opt4: OptionButton = row1.get_node("Option")
	# 回填恢复 P60=舵机、Key=E -> 增量/直接
	_check("回填后按 IO 初始化区过滤",
		_mode_items(opt4) == ["增量", "直接"], str(_mode_items(opt4)))

	# ---- 步兵高级设置（ADV_ENGINEER）同样过滤 ----
	ui._apply_kind_visibility("infantry", 0)
	var adv_p64_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P64")))
	var adv_p66_type: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P66")))
	_check("步兵 P64 初始化选项为电机/摩擦轮",
		_mode_items(adv_p64_type) == ["电机", "摩擦轮"], str(_mode_items(adv_p64_type)))
	_check("步兵 P66 初始化选项为电机/摩擦轮",
		_mode_items(adv_p66_type) == ["电机", "摩擦轮"], str(_mode_items(adv_p66_type)))
	var adv_p64_mid: LineEdit = ui.get_node(NodePath(ui._eng_io_mid_path("P64")))
	var adv_p66_mid: LineEdit = ui.get_node(NodePath(ui._eng_io_mid_path("P66")))
	_check("步兵 P64/P66 不显示舵机初始角",
		not adv_p64_mid.visible and not adv_p66_mid.visible)
	# ---- 摩擦轮类型：无刷保留 P64/P66；禁用后释放并关闭参数控件 ----
	var friction_type: OptionButton = ui.get_node(ui.P_FRICTION_TYPE)
	var friction_key: OptionButton = ui.get_node(ui.P_BOOSTER_KEY)
	var friction_duty: LineEdit = ui.get_node(ui.P_FRICTION_MAX_DUTY)
	var infantry_port_selectors: Array = [
		ui.get_node(ui.P_L1_IO), ui.get_node(ui.P_L2_IO),
		ui.get_node(ui.P_R1_IO), ui.get_node(ui.P_R2_IO),
		ui.get_node(ui.P_BOOSTER_IO), ui.get_node(ui.P_YAW_IO), ui.get_node(ui.P_PITCH_IO),
	]
	var brushless_reserved: bool = true
	for port_btn in infantry_port_selectors:
		brushless_reserved = brushless_reserved \
			and _pin_item_disabled(port_btn, "P64") and _pin_item_disabled(port_btn, "P66")
	_check("默认无刷模式在普通角色下拉中保留 P64/P66", brushless_reserved)
	_pick(ui, friction_type, "不使用")
	ui._sync_friction_type_ui()
	var disabled_released: bool = true
	for port_btn in infantry_port_selectors:
		disabled_released = disabled_released \
			and not _pin_item_disabled(port_btn, "P64") and not _pin_item_disabled(port_btn, "P66")
	_check("不使用摩擦轮时释放 P64/P66 给底盘/拨弹/云台", disabled_released)
	_check("不使用摩擦轮时禁用开关键和最大 duty", friction_key.disabled and not friction_duty.editable)
	var friction_l1: OptionButton = ui.get_node(ui.P_L1_IO)
	_pick(ui, friction_l1, "P64 P65")
	_pick(ui, friction_type, "无刷电调")
	ui._sync_friction_type_ui()
	_check("切回无刷时保留已选 P64 配置", ui._option_text(friction_l1) == "P64 P65")
	var has_friction_conflict: bool = false
	for issue in SC.check_infantry(ui._collect_config()):
		if str(issue.get("msg", "")).contains("P64 已被摩擦轮固定占用"):
			has_friction_conflict = true
	_check("切回无刷后的 P64 冲突阻止生成", has_friction_conflict)
	# 恢复默认底盘端口，避免影响后续 IO 锁定测试。
	_pick(ui, friction_l1, "P74 P24")
	ui._sync_io_locks()
	var adv_page: String = ui.ADV_ENGINEER + "/TabContainer/M1"
	var adv_vb: Node = ui.get_node(NodePath(adv_page + "/ScrollContainer/VBoxContainer"))
	var adv_row: Node = ui._add_eng_row(adv_vb)
	var adv_opt: OptionButton = adv_row.get_node("Option")
	# 步兵高级设置默认行指向 P60，而 P60 是拨弹电机默认 IO，已被自动同步为电机
	_check("步兵高级设置默认行(P60拨弹电机)选项为 直接",
		_mode_items(adv_opt) == ["直接"], str(_mode_items(adv_opt)))
	# 步兵页高级设置的 IO 初始化区独立实例
	_pick(ui, adv_row.get_node("IO"), "P64")
	_set_io_init(ui, "P64", "电机")
	_check("步兵高级设置 P64 切电机后行选项为 直接",
		_mode_items(adv_opt) == ["直接"], str(_mode_items(adv_opt)))
	_pick(ui, adv_row.get_node("Key"), "RX")
	_check("步兵高级设置 电机+摇杆后行选项为 速度/增速",
		_mode_items(adv_opt) == ["速度", "增速"], str(_mode_items(adv_opt)))

	# ---- 切页后工程页行不残留旧选项（双根都过滤） ----
	ui._apply_kind_visibility("engineer", 1)
	var opt5: OptionButton = row3.get_node("Option")
	_check("切回工程页后行3仍为 速度/增速（不残留 增量/直接）",
		_mode_items(opt5) == ["速度", "增速"], str(_mode_items(opt5)))

	# ---- 底盘锁定：选中的引脚强制为电机，相关行选项同步刷新 ----
	var l1: OptionButton = ui.get_node(CHASSIS_L1)
	_pick(ui, row1.get_node("IO"), "P60")
	_pick(ui, opt4, "增量")
	_pick(ui, l1, "P60 P61")
	ui._sync_io_locks()
	_check("底盘锁定 P60 后行选项刷新为 直接（电机）",
		_mode_items(opt4) == ["直接"], str(_mode_items(opt4)))
	_check("底盘锁定后 P60 在 IO 初始化区被强制为电机",
		ui._option_text(ui.get_node(NodePath(ui._eng_io_path("P60")))) == "电机")
	# 步兵高级设置实例的 P60 也一并锁定
	ui._apply_kind_visibility("infantry", 0)
	_check("步兵高级设置 P60 同样被底盘锁定为电机",
		ui._option_text(ui.get_node(NodePath(ui._eng_io_path("P60")))) == "电机")

	# ---- 步兵固定子系统：拨弹电机 / 摩擦轮 / Yaw/Pitch 自动同步 IO 初始化区 ----
	# 当前在步兵视图（上面已 _apply_kind_visibility("infantry", 0)）
	# 底盘 L1 已锁定 P60（电机），拨弹测试用 P62/P77 避开底盘引脚
	var booster_btn: OptionButton = ui.get_node(ui.P_BOOSTER_IO)
	_pick(ui, booster_btn, "P62 P63")
	ui._sync_io_locks()
	var adv_p62: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P62")))
	_check("拨弹电机选 P62 后 IO 初始化区强制为电机",
		ui._option_text(adv_p62) == "电机", ui._option_text(adv_p62))
	_check("拨弹电机选 P62 后舵机选项被禁用",
		adv_p62.is_item_disabled(1), str(adv_p62.is_item_disabled(1)))
	# 拨弹电机换到 P77：P62 解锁、P77 锁定
	_pick(ui, booster_btn, "P77 P27")
	ui._sync_io_locks()
	_check("拨弹电机改 P77 后 P62 解锁（舵机恢复可选）",
		not adv_p62.is_item_disabled(1), str(adv_p62.is_item_disabled(1)))
	var adv_p77: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P77")))
	_check("拨弹电机改 P77 后 P77 强制为电机",
		ui._option_text(adv_p77) == "电机", ui._option_text(adv_p77))
	# 摩擦轮 P64/P66 的频率类型开放选择，供实测 50/10000Hz
	var adv_p64: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P64")))
	var adv_p66: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P66")))
	_check("摩擦轮 P64 的电机/摩擦轮选项均开放",
		not adv_p64.is_item_disabled(0) and not adv_p64.is_item_disabled(1))
	_check("摩擦轮 P66 的电机/摩擦轮选项均开放",
		not adv_p66.is_item_disabled(0) and not adv_p66.is_item_disabled(1))
	_set_io_init(ui, "P64", "电机")
	_set_io_init(ui, "P66", "电机")
	ui._sync_io_locks()
	_check("摩擦轮 P64 可保持电机(10000Hz)选择", ui._option_text(adv_p64) == "电机")
	_check("摩擦轮 P66 可保持电机(10000Hz)选择", ui._option_text(adv_p66) == "电机")
	# Yaw/Pitch 跟随驱动类型
	var yaw_drive_btn: OptionButton = ui.get_node(ui.P_YAW_DRIVE)
	var yaw_io_btn: OptionButton = ui.get_node(ui.P_YAW_IO)
	_pick(ui, yaw_io_btn, "P74")
	_pick(ui, yaw_drive_btn, "电机")
	ui._sync_io_locks()
	var adv_p74: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P74")))
	_check("Yaw 驱动=电机+P74 后 IO 初始化区强制为电机",
		ui._option_text(adv_p74) == "电机", ui._option_text(adv_p74))
	_pick(ui, yaw_drive_btn, "舵机")
	ui._sync_io_locks()
	_check("Yaw 驱动=舵机+P74 后 IO 初始化区强制为舵机",
		ui._option_text(adv_p74) == "舵机", ui._option_text(adv_p74))
	# 工程页根不受步兵子系统锁定影响（显式设 P62 舵机后验证不被拨弹锁定）
	ui._apply_kind_visibility("engineer", 1)
	_set_io_init(ui, "P62", "舵机")
	ui._sync_io_locks()
	var eng_p62: OptionButton = ui.get_node(NodePath(ui._eng_io_path("P62")))
	_check("工程页 IO 初始化区 P62 不受步兵拨弹锁定影响（仍舵机）",
		ui._option_text(eng_p62) == "舵机", ui._option_text(eng_p62))
	_check("工程页 IO 初始化区 P62 舵机选项未被禁用",
		not eng_p62.is_item_disabled(1), str(eng_p62.is_item_disabled(1)))

	if _fail > 0:
		print("失败 %d 项" % _fail)
		quit(1)
	else:
		print("全部通过")
		quit(0)

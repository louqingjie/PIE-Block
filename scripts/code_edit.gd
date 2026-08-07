extends Control

## AI 代码编辑器场景。
##
## 数据流：磁盘上的 main.c 是唯一真相源。
##   - 进入场景时从磁盘读取填充 CodeEdit
##   - 用户手工编辑后打脏标记，发消息/编译前先落盘
##   - AI 改完文件后比对 mtime，有变化则重新读取刷新 CodeEdit
## 不做内存态双向同步 —— 那样两边会互相覆盖。

# ------------------------------------------------------------------ 节点路径
const P_PROJECT_GUIDE: NodePath = "VBoxContainer/Workspace/ProjectGuide"
const P_CODE_EDIT: NodePath = "VBoxContainer/Workspace/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit"
const P_CODE_PANEL: NodePath = "VBoxContainer/Workspace/HSplitContainer/CodeZone/VSplitContainer/Code"
const P_OUTPUT: NodePath = "VBoxContainer/Workspace/HSplitContainer/CodeZone/VSplitContainer/Output/Output"
const P_STATUS: NodePath = "VBoxContainer/Workspace/HSplitContainer/AIPanel/Header/Status"
## WebView 必须挂在根节点下、脱离容器管辖，理由见 _sync_webview_rect()
const P_WEBVIEW: NodePath = "WebView"
## 容器里的占位节点，WebView 的目标矩形以它为准
const P_WEB_SLOT: NodePath = "VBoxContainer/Workspace/HSplitContainer/AIPanel/WebSlot"
const P_RESTART: NodePath = "VBoxContainer/Workspace/HSplitContainer/AIPanel/Header/Restart"
const P_BUILD: NodePath = "VBoxContainer/TopPanel/Build"
const P_DOWNLOAD: NodePath = "VBoxContainer/TopPanel/Download"
const P_HEX_EXPORT: NodePath = "VBoxContainer/TopPanel/HEXExport"
const P_BUILD_MODE: NodePath = "VBoxContainer/TopPanel/BuildMode"
const P_CLOUD_SETTINGS: NodePath = "VBoxContainer/TopPanel/Settings"
const P_UPGRADE: NodePath = "VBoxContainer/TopPanel/Upgrade"
const P_UPGRADE_PROGRESS: NodePath = "UpgradeProgress"
const P_BACK: NodePath = "VBoxContainer/TopPanel/Button"
const P_SAVE: NodePath = "VBoxContainer/TopPanel/Save"
const P_TITLE: NodePath = "VBoxContainer/TopPanel/Label"
const P_CREATE: NodePath = "VBoxContainer/TopPanel/Create"
const P_OPEN: NodePath = "VBoxContainer/TopPanel/Open"

const UI_SCENE: String = "res://scenes/ui.tscn"
const LAUNCHER_SCENE: String = "res://scenes/launcher.tscn"

# 用 preload 而非 class_name 引用：headless / 首次导入时
# 全局类名缓存可能尚未建立，class_name 会解析失败
const TC = preload("res://scripts/toolchain.gd")
const BC = preload("res://scripts/build_controller.gd")
const DC = preload("res://scripts/download_controller.gd")
const AT = preload("res://scripts/agent_terminal.gd")
const PF = preload("res://scripts/project_file.gd")
const UPGRADE_PROGRESS = preload("res://scripts/upgrade_progress.gd")
const KG = preload("res://scripts/keil_guide.gd")
const CLOUD_COMPILER = preload("res://scripts/cloud_compiler.gd")
const CLOUD_GUIDE = preload("res://scripts/cloud_guide.gd")

## AI 随时会在终端里改盘上的 main.c，靠轮询 mtime 发现
const RELOAD_POLL_SEC: float = 1.5

const GUIDE_TITLES: Array[String] = [
	"项目与硬件确认", "配置遥控器", "配置执行机构", "检查与仿真",
	"升级主控板", "确认升级完成", "真机低速测试",
]
const GUIDE_HINTS: Array[String] = [
	"确认程序只烧录到主控板，绝不向机械扩展板烧录程序。",
	"图形化配置已冻结；需要修改时返回图形化编辑并丢弃 AI 代码。",
	"执行机构配置已冻结；需要修改时返回图形化编辑并丢弃 AI 代码。",
	"查看阶段一检查结果；需要重新检查或仿真时返回图形化编辑。",
	"编译当前 AI 编辑后的 main.c，并自动烧录到主控板。",
	"确认升级面板显示完成，主控板已经运行新程序。",
	"烧录后在图形化界面完成真机低速测试确认。",
]

# ------------------------------------------------------------------ 状态
var _tc = null
var _client = null
var _project_dst: String = ""
var _dirty: bool = false
var _last_mtime: int = 0
var _build_controller = null
var _download_controller = null
## 编译方式下拉（本地/云端）
var _build_mode: OptionButton = null
var _upgrade_active: bool = false
## 正在走「导出 HEX」流程：编译成功回调改弹保存对话框而不是烧录
var _hex_export_pending: bool = false
var _wv: Control = null
## 置 true 可打印 WebView 的 DPI 修正过程，排查偏移时用
var _wv_debug: bool = false
## 上次设过的 zoom，避免每帧重复调用
var _wv_zoom: float = 0.0


func _ready() -> void:
	_project_dst = AppState.project_dst
	if _project_dst.is_empty():
		# 直接运行本场景（未经 ui.tscn）时兜底到步兵工程
		_project_dst = TC.PROJECT_DST
	_tc = TC.new(_append_output)
	_setup_build_controller()
	_setup_download_controller()

	var title: Node = get_node_or_null(P_TITLE)
	if title is Label:
		title.text = "%s · %s · %s" % [
			AppState.project_name(), AppState.kind_label(), PF.stage_label(AppState.stage)]

	# 接管窗口关闭：默认行为是引擎直接退出，_exit_tree 不保证跑完，
	# 会把 ttyd 和 Agent 留成孤儿进程（实测确认）。
	# 关掉自动退出后由 _notification 里显式清理再 quit。
	get_tree().auto_accept_quit = false

	_setup_code_edit()
	_load_from_disk()
	_setup_guide()
	_connect_signals()
	_start_ai()


func _exit_tree() -> void:
	_shutdown()


## 窗口关闭请求：先停子进程再退出，否则 ttyd/Agent 会变孤儿
func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_shutdown()
		get_tree().quit()


## 清理子进程与编译线程。可能被调用多次，需幂等
func _shutdown() -> void:
	if _build_controller:
		_build_controller.shutdown()
	if _download_controller:
		_download_controller.shutdown()
	if _client:
		_client.stop()


# ------------------------------------------------------------------ 初始化
func _setup_code_edit() -> void:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.syntax_highlighter = preload("res://scripts/c_highlighter.gd").new()


func _setup_build_controller() -> void:
	_build_controller = BC.new()
	add_child(_build_controller)
	_build_controller.configure(_tc, _clear_output, _append_output)
	# 云端编译：注入 CloudCompiler 并创建「本地/云端」下拉与设置入口
	_build_controller.configure_cloud(CLOUD_COMPILER.new(_tc, _append_output))
	_setup_build_mode_selector()
	_build_controller.busy_changed.connect(_on_build_busy_changed)
	_build_controller.succeeded.connect(_on_build_succeeded)
	_build_controller.finished.connect(func(result: Dictionary) -> void:
		_update_guide()
		_on_upgrade_build_finished(result)
		if _hex_export_pending:
			_hex_export_pending = false
			_append_output("[Error] 编译失败，未导出 HEX")
		if not bool(result.get("ok", false)) and _tc != null \
				and _tc.detect_license_failure(str(result.get("log", ""))):
			_show_license_dialog())


## 编译方式下拉与云端设置按钮：已固化在 code_edit.tscn，只读节点、禁止动态创建。
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


func _is_cloud_mode() -> bool:
	return _build_mode != null and _build_mode.selected == 1


func _on_cloud_settings_pressed() -> void:
	CLOUD_GUIDE.open_settings(self, _tc)


func _on_cloud_guide_cancel() -> void:
	_append_output("[Error] 未配置云端编译服务器，编译已中止（可在顶栏「云端设置」填写）")


func _setup_download_controller() -> void:
	_download_controller = DC.new()
	add_child(_download_controller)
	_download_controller.configure(_tc, _clear_output, _append_output)
	_download_controller.busy_changed.connect(_on_download_busy_changed)
	_download_controller.succeeded.connect(_on_download_succeeded)
	_download_controller.progress_changed.connect(_on_upgrade_progress_changed)
	_download_controller.finished.connect(_on_upgrade_download_finished)


func _connect_signals() -> void:
	var build: Node = get_node_or_null(P_BUILD)
	if build is BaseButton:
		build.pressed.connect(_on_build_pressed)
	var download: Node = get_node_or_null(P_DOWNLOAD)
	if download is BaseButton:
		download.pressed.connect(_on_download_pressed)
	var hex_export: Node = get_node_or_null(P_HEX_EXPORT)
	if hex_export is BaseButton:
		hex_export.pressed.connect(_on_hex_export_pressed)
	var upgrade: Node = get_node_or_null(P_UPGRADE)
	if upgrade is BaseButton:
		upgrade.pressed.connect(_on_upgrade_pressed)
	var upgrade_progress: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if upgrade_progress != null and upgrade_progress.has_signal("closed"):
		upgrade_progress.closed.connect(_on_upgrade_panel_closed)
	if upgrade_progress != null and upgrade_progress.has_signal("cancel_requested"):
		upgrade_progress.cancel_requested.connect(_on_upgrade_cancel_pressed)
	var back: Node = get_node_or_null(P_BACK)
	if back is BaseButton:
		back.pressed.connect(_on_back_pressed)
	var save: Node = get_node_or_null(P_SAVE)
	if save is BaseButton:
		save.pressed.connect(_on_save_pressed)
	var create: Node = get_node_or_null(P_CREATE)
	if create is BaseButton:
		create.pressed.connect(_on_create_pressed)
	var open: Node = get_node_or_null(P_OPEN)
	if open is BaseButton:
		open.pressed.connect(_on_open_pressed)
	var restart: Node = get_node_or_null(P_RESTART)
	if restart is BaseButton:
		restart.pressed.connect(_on_restart_pressed)
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.text_changed.connect(func() -> void:
			_dirty = true
			_update_guide())
	# AI 会在终端里改盘上的 main.c，定时回读
	var t: Timer = Timer.new()
	t.wait_time = RELOAD_POLL_SEC
	t.autostart = true
	t.timeout.connect(_on_reload_tick)
	add_child(t)


func _setup_guide() -> void:
	var guide: Node = get_node_or_null(P_PROJECT_GUIDE)
	if guide == null or not guide.has_method("setup"):
		return
	var done: Array[bool] = _guide_done_states()
	guide.setup(GUIDE_TITLES, GUIDE_HINTS, done)
	_persist_guide_progress_if_changed(done)
	guide.step_pressed.connect(_on_guide_step_pressed)


func _update_guide() -> void:
	var guide: Node = get_node_or_null(P_PROJECT_GUIDE)
	if guide != null and guide.has_method("set_state"):
		var done: Array[bool] = _guide_done_states()
		guide.set_state(GUIDE_TITLES, GUIDE_HINTS, done)
		_persist_guide_progress_if_changed(done)


func _persist_guide_progress_if_changed(done: Array[bool]) -> void:
	if AppState.project_path.is_empty():
		return
	var result: Dictionary = PF.load_from(AppState.project_path)
	if not result["ok"]:
		return
	var data: Dictionary = result["data"]
	var workflow: Dictionary = PF.normalize_workflow(data.get("workflow", {}))
	if workflow.get("guide_completed", []) == done:
		return
	workflow["guide_completed"] = done.duplicate()
	data["workflow"] = workflow
	var saved: Dictionary = PF.save_to(AppState.project_path, data)
	if not saved["ok"]:
		_append_output("[Error] 保存项目引导进度失败：%s" % saved["err"])


func _guide_done_states() -> Array[bool]:
	var workflow: Dictionary = _load_workflow()
	var code_hash: String = _current_code_hash()
	return [
		bool(workflow.get("hardware_confirmed", false)),
		AppState.stage >= 2,
		AppState.stage >= 2,
		not str(workflow.get("checked_hash", "")).is_empty(),
		str(workflow.get("built_hash", "")) == code_hash and not code_hash.is_empty(),
		str(workflow.get("flashed_hash", "")) == code_hash and not code_hash.is_empty(),
		bool(workflow.get("hardware_tested", false))
			and str(workflow.get("flashed_hash", "")) == code_hash and not code_hash.is_empty(),
	]


func _load_workflow() -> Dictionary:
	if AppState.project_path.is_empty():
		return PF.normalize_workflow({})
	var result: Dictionary = PF.load_from(AppState.project_path)
	if not result["ok"]:
		return PF.normalize_workflow({})
	return PF.normalize_workflow(result["data"].get("workflow", {}))


func _current_code_hash() -> String:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = ce.text if ce is CodeEdit else ""
	return code.sha256_text() if not code.strip_edges().is_empty() else ""


func _on_guide_step_pressed(step: int) -> void:
	match step:
		0:
			_show_hardware_confirmation()
		1, 2, 3, 6:
			_on_back_pressed()
		4:
			_on_upgrade_pressed()
		5:
			_on_upgrade_pressed()


func _show_hardware_confirmation() -> void:
	var dialog := AcceptDialog.new()
	dialog.title = "查看第一步确认"
	dialog.dialog_text = "1. 程序只烧录到主控板。\n\n2. 绝不向机械扩展板烧录程序。\n\n3. 新主控板已经由维护者安装引导程序。"
	dialog.ok_button_text = "已了解"
	add_child(dialog)
	dialog.popup_centered(Vector2i(520, 280))
	dialog.close_requested.connect(dialog.queue_free)


## 高 DPI 下修正 WebView 的位置与尺寸。
##
## WebView2 是挂在 Godot 窗口上的原生子 HWND，由系统合成器绘制，
## 像素不进 Godot 渲染管线（所以也无法渲染到 TextureRect）。
## 它的矩形只能用**物理**像素表达。
##
## WRY 的 resize() 这样算：
##     scale = window.get_size() / viewport.get_visible_rect().size
##     rect  = 节点 global_position * scale, 节点 size * scale
## 但 Godot 在 Windows 上这两个尺寸都是**逻辑**像素，比值恒为 1，
## 等于完全没做 DPI 换算，直接把逻辑坐标当物理像素交给了 WebView2。
## 实测（系统 150% 缩放）：Godot 报窗口 1600x900，
## Win32 GetClientRect 报 1066x600 —— 这就是终端偏移的确切来源。
##
## 修正办法：既然 WRY 只认节点自身的 global_position/size，
## 就把目标矩形预先乘上 96/dpi 再写进节点，抵消它缺失的那一步换算。
## 注意 Control.scale 无效 —— WRY 读的是未经自身 scale 变换的原始值。
## 因此 WebView 必须挂在根节点下：容器每帧会覆写子节点的 rect，
## 真实布局由容器里的 WebSlot 占位节点提供。
func _sync_webview_rect() -> void:
	if _wv == null:
		return
	var slot: Node = get_node_or_null(P_WEB_SLOT)
	if not slot is Control:
		return
	var f: float = _compensation_factor()
	var pos: Vector2 = ((slot as Control).global_position * f).round()
	var siz: Vector2 = ((slot as Control).size * f).round()
	if _wv.global_position == pos and _wv.size == siz:
		return
	_wv.global_position = pos
	_wv.size = siz
	_wv.resize()
	_apply_zoom()
	if _wv_debug:
		# 按实测关系（真实 rect = 节点值 / DPI倍率）推出预期值，
		# 可直接与 Win32 量到的 WRY_WEBVIEW 子窗口矩形逐项对账
		var vp: Vector2 = get_viewport().get_visible_rect().size
		var dpi: int = DisplayServer.screen_get_dpi(
			DisplayServer.window_get_current_screen())
		var ds: float = 1.0 if dpi <= 0 else float(dpi) / 96.0
		print("[wv] slot=%s %s | f=%.4f -> node=%s %s | expect_real=%s %s | zoom=%.4f | ds_win=%s vp=%s" % [
			(slot as Control).global_position, (slot as Control).size,
			f, pos, siz, (pos / ds).round(), (siz / ds).round(),
			_wv_zoom, DisplayServer.window_get_size(0), vp])


## 写进 WebView 节点前要乘的补偿系数。
##
## 目标：  节点值 × WRY_scale == slot 画布坐标 × (客户区物理尺寸 / 视口尺寸)
## WRY 内部 scale = window_get_size / 视口尺寸，这一项已经把 Godot 的
## stretch 缩放算进去了（最大化时 2560/1600 = 1.6），它唯独漏掉 DPI 换算。
## 而 客户区物理尺寸 = window_get_size / DPI倍率，代入化简后
##     f = 1 / DPI倍率
## 是个**常数**，与窗口是否最大化无关。实测（150% 缩放）：
##     非最大化 WRY_scale 1.0 × 0.667 = 0.667，正确值 1066/1600 = 0.666 ✔
##     最大化   WRY_scale 1.6 × 0.667 = 1.067，正确值 1706/1600 = 1.066 ✔
## 写进 WebView 节点前要乘的补偿系数。
##
## 用 Win32 EnumChildWindows 量过 WRY_WEBVIEW 子窗口的真实矩形，实测关系是
##     真实物理 rect == 写进节点的值 / DPI倍率
## 也就是说 WRY resize() 里那个 scale 并未生效（WebView2 的 Bounds 收的是
## DIP 而非物理像素），节点值被当逻辑坐标又除了一次 DPI。
##
## 目标物理 rect = slot 画布坐标 × (客户区物理尺寸 / 视口尺寸)
## 令 节点值 / DPI倍率 == 目标，得
##     f = 客户区/视口 × DPI倍率 = window_get_size / 视口
## 注意 window_get_size 在最大化时返回物理尺寸(2560)，非最大化时返回
## 逻辑尺寸(1600)，两种情况下这个式子都成立。
func _compensation_factor() -> float:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	if vp.x <= 0.0:
		return 1.0
	return float(DisplayServer.window_get_size(0).x) / vp.x


## 让 webview 里的内容与 Godot UI 视觉密度一致。
##
## 矩形对齐之后还有一层独立的缩放问题：
##   - Godot 把 1600x900 逻辑画布压进物理窗口，UI 实际被缩到 stretch 倍率
##   - WebView2 拿到的是物理像素框，再按 DPI 倍率换算成 CSS 像素
## 两者不一致时 webview 里的字会明显偏大，且可用 CSS 宽度偏窄
## （实测 459 物理 px ÷ 1.5 只剩 306 CSS px，TUI 列数不足，logo 被截断）。
##
## webview 的可用 CSS 宽度 = 节点值 / DPI倍率（见 _compensation_factor 实测），
## 而它要承载的是 slot 在画布空间里的宽度。两者之比就是需要的 zoom：
##     zoom = (节点值 / DPI倍率) / slot画布宽 = f / DPI倍率
## 这样 webview 里 1 CSS 像素对应的视觉大小与 Godot UI 一致。
func _apply_zoom() -> void:
	var dpi: int = DisplayServer.screen_get_dpi(
		DisplayServer.window_get_current_screen())
	if dpi <= 0:
		return
	var z: float = _compensation_factor() * 96.0 / float(dpi)
	if z <= 0.0 or is_equal_approx(z, _wv_zoom):
		return
	_wv_zoom = z
	_wv.zoom(z)


## WRY 自己的 update_webview() 每帧比对节点 rect 并调 resize()，
## 只在信号里写一次会被它覆盖回去，必须每帧维持预缩放后的值。
## _sync_webview_rect() 内部有等值短路，实际不会每帧真的调 resize()。
func _process(_delta: float) -> void:
	_sync_webview_rect()


## WebView2 与 Godot 使用两套原生焦点系统，不能只依赖 Control.grab_focus()。
## 终端转发的鼠标事件也会进入这里，因此可用真实面板矩形统一判定点击目标。
func _input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var mouse_pos: Vector2 = event.position
	var code_panel: Node = get_node_or_null(P_CODE_PANEL)
	if code_panel is Control and code_panel.get_global_rect().has_point(mouse_pos):
		_focus_code_input()
		return
	var web_slot: Node = get_node_or_null(P_WEB_SLOT)
	if web_slot is Control and web_slot.get_global_rect().has_point(mouse_pos):
		_focus_terminal_input()


func _focus_code_input() -> void:
	if _wv != null:
		_wv.focus_parent()
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		# focus_parent() 先把原生 HWND 焦点还给 Godot；延迟执行避免同一次
		# 鼠标事件结束时 WebView2 又把焦点夺回去。
		ce.call_deferred("grab_focus")


func _focus_terminal_input() -> void:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.release_focus()
	if _wv != null:
		_wv.focus()


func _start_ai() -> void:
	_wv = get_node_or_null(P_WEBVIEW)
	if _wv == null:
		_append_output("[Error] 缺少 WebView 节点，AI 面板不可用")
		return
	_client = AT.new()
	add_child(_client)
	_client.status_changed.connect(_set_status)
	_client.log_line.connect(_append_output)
	_client.ready_changed.connect(_on_ai_ready_changed)
	# AI 工作区是整个 stc32g/，这样它能读到 Libraries 下的头文件
	# （依赖检查在 AgentTerminal.start() 内部做，失败会发 log）
	if not _client.start(TC.WORKSPACE_DST):
		_set_status("AI 不可用")


# ------------------------------------------------------------------ 磁盘同步
## 从磁盘载入 main.c 到编辑器
func _load_from_disk() -> void:
	var code: String = _tc.read_main_c(_project_dst)
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.text = code
	_last_mtime = _tc.main_c_mtime(_project_dst)
	_dirty = false
	if code.is_empty():
		_append_output("[Warn] 磁盘上没有 main.c，请先在图形化界面生成一次")


## 把编辑器内容落盘（仅在有改动时）
func _flush_to_disk() -> bool:
	if not _dirty:
		return true
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if not ce is CodeEdit:
		return false
	if not _tc.write_main_c(_project_dst, ce.text):
		_append_output("[Error] 写入 main.c 失败")
		return false
	_last_mtime = _tc.main_c_mtime(_project_dst)
	_dirty = false
	return true


## AI 可能改过文件，检查 mtime 并刷新编辑器。返回是否发生了刷新
func _reload_if_changed() -> bool:
	var mtime: int = _tc.main_c_mtime(_project_dst)
	if mtime == _last_mtime:
		return false
	var code: String = _tc.read_main_c(_project_dst)
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit and ce.text != code:
		# 尽量保留视口位置，避免刷新后跳到文件开头
		var scroll_v: float = ce.scroll_vertical
		var caret_line: int = ce.get_caret_line()
		ce.text = code
		ce.scroll_vertical = scroll_v
		if caret_line < ce.get_line_count():
			ce.set_caret_line(caret_line)
	_last_mtime = mtime
	_dirty = false
	return true


# ------------------------------------------------------------------ AI 面板
## 终端就绪：把 WebView 指向 ttyd，Agent 的 TUI 就渲染在里面
func _on_ai_ready_changed(is_ready: bool, url: String) -> void:
	var rb: Node = get_node_or_null(P_RESTART)
	if rb is BaseButton:
		rb.disabled = not is_ready
	if is_ready and _wv != null and not url.is_empty():
		_wv.load_url(url)


## 重启终端：ttyd 带 -q，客户端断开后自身会退出，
## 所以「重启」= 停掉旧进程再起一个新的
func _on_restart_pressed() -> void:
	if _client == null:
		return
	_flush_to_disk()
	_set_status("正在重启终端…")
	_client.stop()
	_client.start(TC.WORKSPACE_DST)


## 定时回读：AI 在终端里改盘上的 main.c 后刷新编辑器。
## 用户有未保存改动时不覆盖，避免吞掉手工编辑。
func _on_reload_tick() -> void:
	if _dirty or (_build_controller != null and _build_controller.is_busy()):
		return
	if _reload_if_changed():
		_append_output("检测到 main.c 已被 AI 修改，编辑器已刷新")


# ------------------------------------------------------------------ 项目文件
## 把编辑器里的代码写进 .pieproj 的 main_c_ai。
## 阶段一冻结的 config 与 main_c_stage1 一律不动 —— 那份是阶段一的存档。
func _save_project(verbose: bool) -> bool:
	if AppState.project_path.is_empty():
		return false
	var res: Dictionary = PF.load_from(AppState.project_path)
	if not res["ok"]:
		_append_output("[Error] 无法读取项目文件：%s" % res["err"])
		return false
	var data: Dictionary = res["data"]
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	data["stage"] = 2
	data["main_c_ai"] = ce.text if ce is CodeEdit else ""
	var w: Dictionary = PF.save_to(AppState.project_path, data)
	if not w["ok"]:
		_append_output("[Error] 保存项目失败：%s" % w["err"])
		return false
	if verbose:
		_append_output("已保存项目：%s" % AppState.project_path)
	return true


## 在 AI 编辑器里点新建 / 打开：先落盘，再回启动页做项目管理
func _on_create_pressed() -> void:
	_leave_for_project_action("create", "新建项目将离开 AI 编辑，回到启动页。")


func _on_open_pressed() -> void:
	_leave_for_project_action("open", "打开项目将离开 AI 编辑，回到启动页。")


func _leave_for_project_action(action: String, text: String) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "离开 AI 编辑"
	dlg.dialog_text = text + "\n当前代码会先保存到项目文件。"
	dlg.get_ok_button().text = "继续"
	dlg.confirmed.connect(func() -> void:
		AppState.pending_action = action
		_leave_to_scene(LAUNCHER_SCENE))
	add_child(dlg)
	dlg.popup_centered()
	dlg.close_requested.connect(dlg.queue_free)


# ------------------------------------------------------------------ 编译
func _on_save_pressed() -> void:
	if not _flush_to_disk():
		return
	_append_output("已保存 main.c")
	# 无项目（直跑本场景）时只写磁盘 main.c，不报错
	if AppState.has_project():
		_save_project(true)


func _on_build_pressed() -> void:
	if _build_controller == null or _build_controller.is_busy() \
			or (_download_controller != null and _download_controller.is_busy()):
		return
	# 云端：先确认云端配置；本地：确认外部 Keil 目录，未配置时弹引导
	if _is_cloud_mode():
		CLOUD_GUIDE.ensure_cloud(self, _tc, _do_build, _on_cloud_guide_cancel)
	else:
		KG.ensure_keil(self, _tc, _do_build, _on_keil_guide_cancel)


func _do_build() -> void:
	if not _flush_to_disk():
		return
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = code_edit.text if code_edit is CodeEdit else ""
	_build_controller.start(_project_dst, code, "cloud" if _is_cloud_mode() else "local")


## 用户在 Keil 目录引导对话框里点「取消」时中止编译并提示。
func _on_keil_guide_cancel() -> void:
	_append_output("[Error] 未指定 Keil 目录，编译已中止（可在下次编译时选择）")


## 导出 HEX 按钮：先按「编译」的流程编译，成功后弹保存对话框
## （复用 build_controller；成功回调见 _on_build_succeeded 的 pending 分支）
func _on_hex_export_pressed() -> void:
	if _build_controller == null or _build_controller.is_busy() \
			or (_download_controller != null and _download_controller.is_busy()):
		return
	# 引导成功后重跑原流程，_hex_export_pending 在 _do_hex_export 内设置，状态不丢
	if _is_cloud_mode():
		CLOUD_GUIDE.ensure_cloud(self, _tc, _do_hex_export, _on_cloud_guide_cancel)
	else:
		KG.ensure_keil(self, _tc, _do_hex_export, _on_keil_guide_cancel)


func _do_hex_export() -> void:
	if not _flush_to_disk():
		return
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	var code2: String = ce.text if ce is CodeEdit else ""
	_hex_export_pending = true
	if not _build_controller.start(_project_dst, code2,
			"cloud" if _is_cloud_mode() else "local"):
		_hex_export_pending = false


func _on_build_busy_changed(is_busy: bool) -> void:
	var btn: Node = get_node_or_null(P_BUILD)
	if btn is BaseButton:
		btn.disabled = is_busy
		btn.text = "编译中…" if is_busy else "编译"
	var download_button: Node = get_node_or_null(P_DOWNLOAD)
	if download_button is BaseButton:
		download_button.disabled = is_busy
	var hex_export_btn: Node = get_node_or_null(P_HEX_EXPORT)
	if hex_export_btn is BaseButton:
		hex_export_btn.disabled = is_busy
	_set_upgrade_button_busy(is_busy)


func _on_build_succeeded() -> void:
	if _hex_export_pending:
		_hex_export_pending = false
		_open_hex_save_dialog()
		return
	_update_built_hash()
	_update_guide()
	if _upgrade_active:
		_set_upgrade_progress("编译完成", 28.0, "正在连接主控板…")
		if not _download_controller.start(_project_dst):
			_fail_upgrade("无法开始烧录", "请查看下方输出中的串口或固件提示。")


## 编译成功后弹出保存对话框，让用户选择 hex 导出位置
func _open_hex_save_dialog() -> void:
	if not _tc.hex_exists(_project_dst):
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
	var dst: String = dst_path
	if not dst.to_lower().ends_with(".hex"):
		dst += ".hex"
	var src: String = _tc.get_hex_path(_project_dst)
	var src_f: FileAccess = FileAccess.open(src, FileAccess.READ)
	if src_f == null:
		_append_output("[Error] 读取编译产物失败：%s" % src)
		return
	var dst_f: FileAccess = FileAccess.open(dst, FileAccess.WRITE)
	if dst_f == null:
		src_f.close()
		_append_output("[Error] 无法写入：%s" % dst)
		return
	var buf_size: int = 65536
	while src_f.get_position() < src_f.get_length():
		dst_f.store_buffer(src_f.get_buffer(buf_size))
	src_f.close()
	dst_f.close()
	_append_output("[✓] 已导出 HEX：%s" % dst)


# ------------------------------------------------------------------ 许可证引导
## 编译被 Keil 许可证限制（本机缺 C251 许可）时弹出引导：告诉学生领免费密钥并粘贴。
## 许可证按机器发放，每台电脑需各自的有效密钥；粘贴后写入 TOOLS.INI 并重编。
func _show_license_dialog() -> void:
	var keil_dir: String = _tc.resolve_keil_root().replace("/", "\\")
	var dlg := AcceptDialog.new()
	dlg.title = "需要 Keil C251 许可证"
	dlg.dialog_text = "本机缺少 Keil C251 许可证，编译被限制在 2KB，无法生成固件。\n\n" \
		+"Keil 许可证按机器发放，每台电脑要用各自的免费密钥（约 2 分钟）：\n" \
		+"1. 打开 %s\\UV4\\UV4.exe → 菜单 License Management，记下 License ID Code。\n" \
		+"2. 浏览器打开 https://www.keil.com/download/product/ ，登录后选 C251，\n" \
		+"    输入上面的 License ID Code，免费生成许可证密钥。\n" \
		+"3. 把密钥粘贴到下方输入框，点「应用许可证并重试」。\n\n" \
		+"之后这台电脑即可正常编译，无需再次配置。" % keil_dir
	dlg.ok_button_text = "应用许可证并重试"
	var edit := LineEdit.new()
	edit.placeholder_text = "在此粘贴 C251 许可证密钥"
	edit.custom_minimum_size = Vector2(460, 0)
	dlg.get_vbox().add_child(edit)
	add_child(dlg)
	dlg.popup_centered(Vector2i(620, 380))
	edit.grab_focus()
	dlg.confirmed.connect(func() -> void:
		_apply_license_and_rebuild(edit.text.strip_edges()))
	dlg.close_requested.connect(dlg.queue_free)


func _apply_license_and_rebuild(key: String) -> void:
	if key.is_empty():
		_append_output("[提示] 未输入许可证密钥")
		return
	if not _tc.apply_license_key(key):
		var root: String = _tc.resolve_keil_root().replace("/", "\\")
		_append_output("[Error] 写入许可证失败，请检查 %s\\TOOLS.INI 权限" % root)
		return
	_append_output("[✓] 已写入 C251 许可证，正在重新编译…")
	_on_build_pressed()


func _update_built_hash() -> void:
	if AppState.project_path.is_empty():
		return
	var result: Dictionary = PF.load_from(AppState.project_path)
	if not result["ok"]:
		return
	var data: Dictionary = result["data"]
	var workflow: Dictionary = PF.normalize_workflow(data.get("workflow", {}))
	workflow["built_hash"] = _current_code_hash()
	data["workflow"] = workflow
	PF.save_to(AppState.project_path, data)


# ------------------------------------------------------------------ 下载/烧录
func _on_download_pressed() -> void:
	if _download_controller == null or _download_controller.is_busy() \
			or (_build_controller != null and _build_controller.is_busy()):
		return
	_clear_output()

	var code_hash: String = _current_code_hash()
	var workflow: Dictionary = _load_workflow()
	if code_hash.is_empty() or str(workflow.get("built_hash", "")) != code_hash:
		_append_output("[Error] 当前 AI 代码尚未编译，请先点「编译」")
		return
	_download_controller.start(_project_dst)


func _on_download_busy_changed(is_busy: bool) -> void:
	var button: Node = get_node_or_null(P_DOWNLOAD)
	if button is BaseButton:
		button.disabled = is_busy
		button.text = "烧录中…" if is_busy else "烧录主控板"
	var build_button: Node = get_node_or_null(P_BUILD)
	if build_button is BaseButton:
		build_button.disabled = is_busy
	var hex_export_btn: Node = get_node_or_null(P_HEX_EXPORT)
	if hex_export_btn is BaseButton:
		hex_export_btn.disabled = is_busy
	_set_upgrade_button_busy(is_busy)
	# 烧录阶段允许取消（编译阶段取消按钮保持禁用）。
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("set_cancel_enabled"):
		panel.set_cancel_enabled(is_busy)


func _on_download_succeeded() -> void:
	_update_flashed_hash()
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
	# 引导成功后才进入升级流程（_upgrade_active 在 _do_upgrade 内置位，取消不残留状态）
	KG.ensure_keil(self, _tc, _do_upgrade, _on_keil_guide_cancel)


func _do_upgrade() -> void:
	if not _flush_to_disk():
		return
	var code_edit: Node = get_node_or_null(P_CODE_EDIT)
	var code: String = code_edit.text if code_edit is CodeEdit else ""
	if code.strip_edges().is_empty():
		_append_output("[Error] 没有可升级的代码")
		return
	_upgrade_active = true
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("begin"):
		panel.begin()
	if _wv != null:
		_wv.hide()
	_set_upgrade_progress("正在编译程序", 8.0, "编译成功后会自动烧录到主控板。")
	_set_upgrade_button_busy(true)
	if not _build_controller.start(_project_dst, code):
		_fail_upgrade("无法开始编译", "请查看下方输出中的详细提示。")


func _on_upgrade_progress_changed(stage: String, percent: float, detail: String) -> void:
	if _upgrade_active:
		_set_upgrade_progress(stage, percent, detail)


func _on_upgrade_download_finished(result: Dictionary) -> void:
	# 用户取消 / 硬超时：显示「已取消」状态，而不是「烧录失败」。
	if bool(result.get("canceled", false)):
		if not _upgrade_active:
			return
		_upgrade_active = false
		var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
		if panel != null and panel.has_method("canceled"):
			if str(result.get("stage", "")) == "timeout":
				panel.canceled("烧录超时，已自动取消并释放串口，可以重新升级。")
			else:
				panel.canceled()
		_set_upgrade_button_busy(false)
		return
	if _upgrade_active and not bool(result.get("ok", false)):
		_fail_upgrade("烧录失败", "连接或写入未完成，请查看下方输出。")


func _on_upgrade_cancel_pressed() -> void:
	if _download_controller != null and _download_controller.is_busy():
		_download_controller.cancel()
	# 编译阶段取消按钮是禁用的，无需处理。


func _on_upgrade_build_finished(result: Dictionary) -> void:
	if _upgrade_active and not bool(result.get("ok", false)):
		_fail_upgrade("编译失败",
			UPGRADE_PROGRESS.compile_error_hint(AppState.stage))


func _set_upgrade_progress(stage: String, percent: float, detail: String) -> void:
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("set_progress"):
		panel.set_progress(stage, percent, detail)


func _fail_upgrade(stage: String, detail: String) -> void:
	_upgrade_active = false
	var panel: Node = get_node_or_null(P_UPGRADE_PROGRESS)
	if panel != null and panel.has_method("fail"):
		panel.fail(stage, detail)
	_set_upgrade_button_busy(false)


func _set_upgrade_button_busy(is_busy: bool) -> void:
	var button: Node = get_node_or_null(P_UPGRADE)
	if button is BaseButton:
		button.disabled = is_busy
		button.text = "升级中…" if is_busy else "升级主控板"


func _on_upgrade_panel_closed() -> void:
	if _wv != null:
		_wv.show()


func _update_flashed_hash() -> void:
	if AppState.project_path.is_empty():
		return
	var result: Dictionary = PF.load_from(AppState.project_path)
	if not result["ok"]:
		return
	var data: Dictionary = result["data"]
	var workflow: Dictionary = PF.normalize_workflow(data.get("workflow", {}))
	workflow["flashed_hash"] = _current_code_hash()
	workflow["hardware_tested"] = false
	data["workflow"] = workflow
	PF.save_to(AppState.project_path, data)


# ------------------------------------------------------------------ 返回
func _on_back_pressed() -> void:
	_leave_to_scene(UI_SCENE)


## 离开本场景：落盘 + 停子进程 + 复位全局设置，最后切到目标场景。
## 这套清理顺序有实测依据，见下方各条注释，改动前先看注释。
func _leave_to_scene(scene_path: String) -> void:
	_flush_to_disk()
	# AI 成果不能只留在磁盘 main.c 里，项目文件才是真相源
	if AppState.has_project():
		_save_project(false)
	# webview 是嵌在 OS 窗口里的原生控件，不参与 Godot 渲染顺序。
	# 切场景前必须先隐藏，否则会在新场景上留残影。
	if _wv:
		_wv.set_visible(false)
	if _client:
		_client.stop()
	# auto_accept_quit 是 SceneTree 级别的全局设置。切回别的场景后
	# 那边没有 CLOSE_REQUEST 处理，不恢复默认会导致窗口关不掉。
	get_tree().auto_accept_quit = true
	get_tree().change_scene_to_file(scene_path)


# ------------------------------------------------------------------ 输出
func _append_output(line_text: String) -> void:
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("append_line"):
		out.append_line(line_text)


func _clear_output() -> void:
	var out: Node = get_node_or_null(P_OUTPUT)
	if out and out.has_method("clear_output"):
		out.clear_output()


func _set_status(text: String) -> void:
	var st: Node = get_node_or_null(P_STATUS)
	if st is Label:
		st.text = text

# 注：原先的 Ctrl+Enter 发送快捷键已移除 —— 提示词输入交由内嵌的 Web UI 处理

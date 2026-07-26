extends Control

## AI 代码编辑器场景。
##
## 数据流：磁盘上的 main.c 是唯一真相源。
##   - 进入场景时从磁盘读取填充 CodeEdit
##   - 用户手工编辑后打脏标记，发消息/编译前先落盘
##   - AI 改完文件后比对 mtime，有变化则重新读取刷新 CodeEdit
## 不做内存态双向同步 —— 那样两边会互相覆盖。

# ------------------------------------------------------------------ 节点路径
const P_CODE_EDIT: NodePath = "VBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Code/CodeEdit"
const P_OUTPUT: NodePath = "VBoxContainer/HSplitContainer/CodeZone/VSplitContainer/Output/Output"
const P_STATUS: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Header/Status"
## WebView 必须挂在根节点下、脱离容器管辖，理由见 _sync_webview_rect()
const P_WEBVIEW: NodePath = "WebView"
## 容器里的占位节点，WebView 的目标矩形以它为准
const P_WEB_SLOT: NodePath = "VBoxContainer/HSplitContainer/AIPanel/WebSlot"
const P_RESTART: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Header/Restart"
const P_BUILD: NodePath = "VBoxContainer/TopPanel/Build"
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
const AT = preload("res://scripts/agent_terminal.gd")
const PF = preload("res://scripts/project_file.gd")

## AI 随时会在终端里改盘上的 main.c，靠轮询 mtime 发现
const RELOAD_POLL_SEC: float = 1.5

# ------------------------------------------------------------------ 状态
var _tc = null
var _client = null
var _project_dst: String = ""
var _dirty: bool = false
var _last_mtime: int = 0
var _build_thread: Thread = null
var _build_busy: bool = false
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
	if _build_thread and _build_thread.is_alive():
		_build_thread.wait_to_finish()
	_build_thread = null
	if _client:
		_client.stop()


# ------------------------------------------------------------------ 初始化
func _setup_code_edit() -> void:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.syntax_highlighter = preload("res://scripts/c_highlighter.gd").new()


func _connect_signals() -> void:
	var build: Node = get_node_or_null(P_BUILD)
	if build is BaseButton:
		build.pressed.connect(_on_build_pressed)
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
		ce.text_changed.connect(func() -> void: _dirty = true)
	# AI 会在终端里改盘上的 main.c，定时回读
	var t: Timer = Timer.new()
	t.wait_time = RELOAD_POLL_SEC
	t.autostart = true
	t.timeout.connect(_on_reload_tick)
	add_child(t)


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
	if _dirty or _build_busy:
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
	if _build_busy:
		return
	_clear_output()
	if not _flush_to_disk():
		return
	if not _tc.ensure_deployed():
		_append_output("[Error] 工具链初始化失败，无法编译")
		return
	var uv4_abs: String = _tc.find_uv4()
	if uv4_abs.is_empty():
		_append_output("[Error] 未找到 uVision.com / UV4.exe")
		return
	if not _tc.generate_tools_ini():
		_append_output("[Warn] TOOLS.INI 生成失败，编译可能报错")
	_build_busy = true
	var btn: Node = get_node_or_null(P_BUILD)
	if btn is BaseButton:
		btn.disabled = true
		btn.text = "编译中…"
	_append_output("正在编译…")
	_build_thread = Thread.new()
	var err: int = _build_thread.start(_build_worker.bind(uv4_abs, _project_dst))
	if err != OK:
		_build_busy = false
		if btn is BaseButton:
			btn.disabled = false
			btn.text = "编译"
		_append_output("[Error] 无法启动编译线程（错误码 %d）" % err)


## 子线程禁止访问 UI 节点，结果通过 call_deferred 回主线程
func _build_worker(uv4_abs: String, project_dst: String) -> void:
	var result: Dictionary = _tc.build_sync(uv4_abs, project_dst)
	call_deferred("_on_build_finished", result)


func _on_build_finished(result: Dictionary) -> void:
	_build_busy = false
	if _build_thread and _build_thread.is_alive():
		_build_thread.wait_to_finish()
	_build_thread = null
	var btn: Node = get_node_or_null(P_BUILD)
	if btn is BaseButton:
		btn.disabled = false
		btn.text = "编译"
	var log_text: String = str(result.get("log", ""))
	_clear_output()
	if bool(result.get("ok", false)):
		_append_output("✓ 编译成功")
	else:
		_append_output("✗ 编译失败（UV4 退出码 %d，详见下方日志）"
			% int(result.get("exit", -1)))
	_append_output("")
	if log_text.is_empty():
		_append_output("[Warn] 未读取到编译日志")
	else:
		for line in log_text.split("\n", false):
			_append_output(line)


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

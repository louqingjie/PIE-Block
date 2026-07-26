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
const P_MESSAGES: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Scroll/Messages"
const P_SCROLL: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Scroll"
const P_INPUT: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Input"
const P_SEND: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Actions/Send"
const P_ABORT: NodePath = "VBoxContainer/HSplitContainer/AIPanel/Actions/Abort"
const P_BUILD: NodePath = "VBoxContainer/TopPanel/Build"
const P_BACK: NodePath = "VBoxContainer/TopPanel/Button"
const P_SAVE: NodePath = "VBoxContainer/TopPanel/Save"
const P_TITLE: NodePath = "VBoxContainer/TopPanel/Label"

const UI_SCENE: String = "res://scenes/ui.tscn"

# 用 preload 而非 class_name 引用：headless / 首次导入时
# 全局类名缓存可能尚未建立，class_name 会解析失败
const TC = preload("res://scripts/toolchain.gd")
const OCC = preload("res://scripts/opencode_client.gd")

# 消息气泡配色
const COLOR_USER: Color = Color(0.62, 0.80, 1.0)
const COLOR_AI: Color = Color(0.86, 0.90, 0.96)
const COLOR_TOOL: Color = Color(0.60, 0.75, 0.60)

# ------------------------------------------------------------------ 状态
var _tc = null
var _client = null
var _project_dst: String = ""
var _dirty: bool = false
var _last_mtime: int = 0
var _build_thread: Thread = null
var _build_busy: bool = false


func _ready() -> void:
	_project_dst = AppState.project_dst
	if _project_dst.is_empty():
		# 直接运行本场景（未经 ui.tscn）时兜底到步兵工程
		_project_dst = TC.PROJECT_DST
	_tc = TC.new(_append_output)

	var title: Node = get_node_or_null(P_TITLE)
	if title is Label:
		title.text = "%s · main.c" % AppState.kind_label()

	_setup_code_edit()
	_load_from_disk()
	_connect_signals()
	_start_ai()


func _exit_tree() -> void:
	if _build_thread and _build_thread.is_alive():
		_build_thread.wait_to_finish()
	if _client:
		_client.stop()


# ------------------------------------------------------------------ 初始化
func _setup_code_edit() -> void:
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.syntax_highlighter = preload("res://scripts/c_highlighter.gd").new()


func _connect_signals() -> void:
	var send: Node = get_node_or_null(P_SEND)
	if send is BaseButton:
		send.pressed.connect(_on_send_pressed)
	var abort: Node = get_node_or_null(P_ABORT)
	if abort is BaseButton:
		abort.pressed.connect(_on_abort_pressed)
	var build: Node = get_node_or_null(P_BUILD)
	if build is BaseButton:
		build.pressed.connect(_on_build_pressed)
	var back: Node = get_node_or_null(P_BACK)
	if back is BaseButton:
		back.pressed.connect(_on_back_pressed)
	var save: Node = get_node_or_null(P_SAVE)
	if save is BaseButton:
		save.pressed.connect(_on_save_pressed)
	var ce: Node = get_node_or_null(P_CODE_EDIT)
	if ce is CodeEdit:
		ce.text_changed.connect(func() -> void: _dirty = true)


func _start_ai() -> void:
	_client = OCC.new()
	add_child(_client)
	_client.status_changed.connect(_set_status)
	_client.log_line.connect(_append_output)
	_client.ready_changed.connect(_on_ai_ready_changed)
	_client.reply_received.connect(_on_reply)
	_client.request_failed.connect(_on_request_failed)
	# AI 工作区是整个 stc32g/，这样它能读到 Libraries 下的头文件
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


# ------------------------------------------------------------------ AI 交互
func _on_ai_ready_changed(is_ready: bool) -> void:
	var send: Node = get_node_or_null(P_SEND)
	if send is BaseButton:
		send.disabled = not is_ready


func _on_send_pressed() -> void:
	var input: Node = get_node_or_null(P_INPUT)
	if not input is TextEdit:
		return
	var text: String = input.text.strip_edges()
	if text.is_empty():
		return
	# 发送前先落盘，保证 AI 看到的是用户当前编辑的版本
	if not _flush_to_disk():
		return
	if not _client.send_message(text):
		return
	_add_bubble("你", text, COLOR_USER)
	input.text = ""
	_set_buttons_busy(true)


func _on_abort_pressed() -> void:
	if _client:
		_client.abort()
	_set_buttons_busy(false)


func _on_reply(parts: Array) -> void:
	_set_buttons_busy(false)
	var texts: PackedStringArray = PackedStringArray()
	var tools: PackedStringArray = PackedStringArray()
	for p in parts:
		if not p is Dictionary:
			continue
		var ptype: String = str(p.get("type", ""))
		match ptype:
			"text":
				var t: String = str(p.get("text", "")).strip_edges()
				if not t.is_empty():
					texts.append(t)
			"tool":
				# 第一期只显示工具名与状态，不展开参数和 diff
				var tool_name: String = str(p.get("tool", "?"))
				var state: Variant = p.get("state", {})
				var status: String = ""
				if state is Dictionary:
					status = str((state as Dictionary).get("status", ""))
				tools.append("%s %s" % [tool_name, status] if not status.is_empty() else tool_name)
	if tools.size() > 0:
		_add_bubble("工具", "\n".join(tools), COLOR_TOOL)
	if texts.size() > 0:
		_add_bubble("AI", "\n\n".join(texts), COLOR_AI)
	# AI 可能改了 main.c，回读刷新
	if _reload_if_changed():
		_append_output("AI 已修改 main.c，编辑器已刷新")


func _on_request_failed(message: String) -> void:
	_set_buttons_busy(false)
	_append_output("[Error] %s" % message)


func _set_buttons_busy(busy: bool) -> void:
	var send: Node = get_node_or_null(P_SEND)
	if send is BaseButton:
		send.disabled = busy or not _client.is_ready()
	var abort: Node = get_node_or_null(P_ABORT)
	if abort is BaseButton:
		abort.disabled = not busy


# ------------------------------------------------------------------ 消息气泡
func _add_bubble(who: String, body: String, color: Color) -> void:
	var box: Node = get_node_or_null(P_MESSAGES)
	if not box is VBoxContainer:
		return
	var panel: PanelContainer = PanelContainer.new()
	var vb: VBoxContainer = VBoxContainer.new()
	var head: Label = Label.new()
	head.text = who
	head.add_theme_color_override("font_color", color)
	var content: Label = Label.new()
	content.text = body
	content.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_child(head)
	vb.add_child(content)
	panel.add_child(vb)
	box.add_child(panel)
	# 等布局更新后滚到底部
	await get_tree().process_frame
	var scroll: Node = get_node_or_null(P_SCROLL)
	if scroll is ScrollContainer:
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value)


# ------------------------------------------------------------------ 编译
func _on_save_pressed() -> void:
	if _flush_to_disk():
		_append_output("已保存 main.c")


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
	_flush_to_disk()
	if _client:
		_client.stop()
	get_tree().change_scene_to_file(UI_SCENE)


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


# ------------------------------------------------------------------ 快捷键
func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ENTER and event.ctrl_pressed:
			var input: Node = get_node_or_null(P_INPUT)
			if input is TextEdit and input.has_focus():
				_on_send_pressed()
				get_viewport().set_input_as_handled()

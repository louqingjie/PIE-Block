extends SceneTree
## Headless 端到端验证：Godot 输入事件 -> TerminalControl -> ConPTY -> XTerm.NET。
## 用法：godot --headless --path . --script scripts/test_terminal_headless.gd

var term = null
var state := 0
var elapsed := 0.0
var fail := 0


func _init() -> void:
	term = load("res://scripts/cs/TerminalControl.cs").new()
	root.add_child(term)
	term.Command = "cmd.exe"
	term.Columns = 80
	term.Rows = 20
	term.size = Vector2(800, 400)
	term.Start()
	print("[test] session started, pid=", term.GetProcessId())


func _process(delta: float) -> bool:
	elapsed += delta
	if state == 0 and elapsed > 2.0:
		_next_state()
		_send_text("chcp 65001>nul")
		_send_special(KEY_ENTER)
	elif state == 1 and elapsed > 1.0:
		_next_state()
		_send_text("echo KEY_R")
		_send_char("E", true) # 验证 Echo=true 的按键重复事件不会被丢弃
		_send_text("PEAT 中文😀")
		_send_special(KEY_ENTER)
		_send_text("echo ARROW_X")
		_send_special(KEY_LEFT)
		_send_text("OK")
		_send_special(KEY_ENTER)
	elif state == 2 and elapsed > 2.0:
		_check("普通/重复键输入", _screen_contains("KEY_REPEAT"))
		_check("方向键输入", _screen_contains("ARROW_OKX"))
		_check("中文与补充平面 Unicode", _screen_contains("中文😀"))
		_test_local_selection()
		_next_state()
		_send_text("ping -t 127.0.0.1")
		_send_special(KEY_ENTER)
	elif state == 3 and elapsed > 1.5:
		_next_state()
		_send_ctrl(KEY_C) # Unicode 刻意为 0，验证从 keycode 重建 Ctrl+C -> 0x03
	elif state == 4 and elapsed > 0.8:
		_next_state()
		_send_text("echo INTERRUPT_OK")
		_send_special(KEY_ENTER)
	elif state == 5 and elapsed > 2.0:
		_check("Ctrl+C 中断前台进程", _screen_contains("INTERRUPT_OK"))
		print("[test] diag=", term.GetDiagnostics())
		print("[test] bytes=", term.GetBytesReceived())
		term.Stop()
		print("[test] ", "PASS" if fail == 0 else "FAIL (%d)" % fail)
		quit(0 if fail == 0 else 1)
		return true
	elif elapsed > 15.0:
		_check("测试未超时", false)
		term.Stop()
		quit(1)
		return true
	return false


func _next_state() -> void:
	state += 1
	elapsed = 0.0


func _send_text(text: String) -> void:
	for i in text.length():
		_send_char(text.substr(i, 1), false)


func _send_char(ch: String, is_echo: bool) -> void:
	var ev := InputEventKey.new()
	var code := ch.unicode_at(0)
	ev.keycode = code - 32 if code >= 97 and code <= 122 else code
	ev.unicode = code
	ev.pressed = true
	ev.echo = is_echo
	term._gui_input(ev)


func _send_special(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.pressed = true
	term._gui_input(ev)


func _send_ctrl(keycode: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = keycode
	ev.ctrl_pressed = true
	ev.unicode = 0
	ev.pressed = true
	term._gui_input(ev)


func _test_local_selection() -> void:
	var lines: Array = term.GetVisibleLines()
	var row := -1
	var col := -1
	for i in lines.size():
		var found := str(lines[i]).find("KEY_REPEAT")
		if found >= 0:
			row = i
			col = found
	if row < 0:
		_check("鼠标拖选", false)
		return
	var cw: float = term.GetCellWidth()
	var ch: float = term.GetCellHeight()
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2((col + 0.25) * cw, (row + 0.5) * ch)
	term._gui_input(down)
	var motion := InputEventMouseMotion.new()
	motion.button_mask = MOUSE_BUTTON_MASK_LEFT
	motion.position = Vector2((col + 9.25) * cw, (row + 0.5) * ch)
	term._gui_input(motion)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = motion.position
	term._gui_input(up)
	_check("鼠标拖选", term.GetSelectedText().contains("KEY_REPEAT"))
	term.ClearSelection()
	_check("清除选择", term.GetSelectedText() == "")
	term.SelectAll()
	_check("全选", term.GetSelectedText().contains("KEY_REPEAT"))
	term.ClearSelection()


func _screen_contains(needle: String) -> bool:
	for line in term.GetVisibleLines():
		if str(line).contains(needle):
			return true
	return false


func _check(label: String, ok: bool) -> void:
	print("[%s] %s" % ["PASS" if ok else "FAIL", label])
	if not ok:
		fail += 1

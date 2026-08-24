extends Control
## opencode TUI 验证：在 Godot 终端里跑真实 opencode，验证 TUI 渲染。
## 运行：godot --path . scenes/dev_opencode.tscn

var term: Control
var state := 0
var elapsed := 0.0
var pid := 0
const RUNTIME = preload("res://scripts/opencode_runtime.gd")

func _ready() -> void:
	var ready: Dictionary = RUNTIME.new().ensure_deployed()
	if not bool(ready.get("ok", false)):
		push_error(str(ready.get("reason", "内置 OpenCode 不可用")))
		get_tree().quit(1)
		return
	term = $Term
	term.Command = str(ready.executable)
	term.Arguments = []
	term.WorkingDirectory = "C:/Users/louqi/Desktop/program/pie-block"
	var runtime_home := ProjectSettings.globalize_path("user://opencode")
	term.EnvironmentOverrides = {
		"OPENCODE_DISABLE_AUTOUPDATE": "true",
		"XDG_CONFIG_HOME": runtime_home.path_join("config"),
		"XDG_DATA_HOME": runtime_home.path_join("data"),
		"XDG_CACHE_HOME": runtime_home.path_join("cache"),
		"XDG_STATE_HOME": runtime_home.path_join("state"),
	}
	term.Columns = 120
	term.Rows = 40
	term.Start()
	term.grab_focus()
	pid = term.GetProcessId()
	print("[dev] opencode started pid=", pid)

func _process(delta: float) -> void:
	elapsed += delta
	if state == 0 and elapsed > 12.0:
		state = 1
		var img := get_viewport().get_texture().get_image()
		var path := "user://opencode_shot.png"
		img.save_png(path)
		print("[dev] screenshot saved to ", path, " size=", img.get_size())
		print("[dev] diag=", term.GetDiagnostics())
		print("[dev] stats=", term.GetRenderStats())
		var lines = term.GetVisibleLines()
		for i in range(0, lines.size()):
			if lines[i].strip_edges() != "":
				print("[dev] line", i, ": '", lines[i], "'")
		var nonblank := 0
		var has_box := false
		for l in lines:
			if l.strip_edges() != "":
				nonblank += 1
			if not has_box and has_box_char(l):
				has_box = true
		print("[dev] nonblank_lines=", nonblank, " has_box=", has_box)
		# 像素采样：验证主题背景色真的渲染出来（应不同于默认深色 0.07,0.07,0.09）
		var img2 := get_viewport().get_texture().get_image()
		var default_bg := Color(0.07, 0.07, 0.09)
		var samples := [[5, 5], [800, 450], [630, 340], [100, 100]]
		var bg_ok := false
		for s in samples:
			var px := img2.get_pixel(s[0], s[1])
			var is_bg := absf(px.r - default_bg.r) < 0.02 and absf(px.g - default_bg.g) < 0.02 and absf(px.b - default_bg.b) < 0.02
			if not is_bg:
				bg_ok = true
			print("[dev] pixel", s, "=", px, " is_default_bg=", is_bg)
		print("[dev] theme_bg_rendered=", bg_ok)
		var ok := nonblank > 3 and has_box and pid > 0 and bg_ok
		if not ok:
			term.Stop()
			print("[dev] OPENCODE TUI RENDER CHECK FAILED")
			get_tree().quit(1)
		print("[dev] OPENCODE TUI RENDER CHECK PASSED")
		# 输入测试：模拟按键 'hi'，验证键盘输入转发到 PTY 并回显
		send_key(KEY_H, "h")
		send_key(KEY_I, "i")
		state = 2
		elapsed = 0.0
	elif state == 2 and elapsed > 2.0:
		state = 3
		var lines2 = term.GetVisibleLines()
		var found := false
		for l in lines2:
			if l.contains("hi"):
				found = true
				break
		print("[dev] input_echo_found=", found)
		term.Stop()
		if found:
			print("[dev] OPENCODE INPUT CHECK PASSED")
			get_tree().quit(0)
		else:
			print("[dev] OPENCODE INPUT CHECK FAILED")
			get_tree().quit(1)

func send_key(keycode: int, unicode_char: String) -> void:
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	ev.unicode = unicode_char.unicode_at(0)
	ev.pressed = true
	term._gui_input(ev)

func has_box_char(s: String) -> bool:
	for i in range(s.length()):
		var u := s.unicode_at(i)
		if u >= 0x2500 and u <= 0x259F:
			return true
	return false

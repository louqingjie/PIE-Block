extends SceneTree

## 端到端验证：AgentTerminal -> TerminalControl -> ConPTY -> opencode（原生终端切换）。
## 运行：godot --headless --path . --script scripts/test_ai_native.gd
##
## 直接驱动 AgentTerminal + TerminalControl（不实例化 code_edit 场景）：
## code_edit 里 AppState 是 autoload，--script 模式下没有全局标识符，
## 实例化场景会因 AppState 引用失败；AgentTerminal 侧链路是切换的核心。

const AT = preload("res://scripts/agent_terminal.gd")

var _fail: int = 0
var _done: bool = false
var _elapsed: float = 0.0
var _client: Node = null
var _term: Control = null
var _ready_seen: bool = false
var _bytes_checked: bool = false


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _initialize() -> void:
	print("=== AI 原生终端端到端（AgentTerminal -> TerminalControl -> opencode） ===\n")
	var term_script := load("res://scripts/cs/TerminalControl.cs")
	_check("TerminalControl 脚本可加载", term_script != null)
	if term_script == null:
		quit(1)
		return
	_term = term_script.new()
	root.add_child(_term)
	_client = AT.new()
	root.add_child(_client)
	_client.terminal_control = _term
	_client.status_changed.connect(func(t: String) -> void: print("[status] ", t))
	_client.log_line.connect(func(t: String) -> void: print("[log] ", t))
	_client.ready_changed.connect(_on_ready)

	var ok: bool = _client.start("user://stc32g_test_native", "engineer")
	print("[info] agent_path = ", _client.agent_path())
	_check("start() 返回 true", ok)
	if not ok:
		_client.stop()
		quit(0 if _fail == 0 else 1)
		return


func _on_ready(is_ready: bool) -> void:
	_ready_seen = true
	print("[ready] is_ready=", is_ready)
	if not is_ready:
		return
	_check("AgentTerminal.is_ready()==true", _client.is_ready())
	_check("TerminalControl.IsRunning==true", bool(_term.get("IsRunning")))
	_check("使用内置 OpenCode 路径", _client.agent_path().replace("\\", "/").contains("/opencode/runtime/opencode.exe"))
	var env: Dictionary = _term.get("EnvironmentOverrides")
	_check("OpenCode 自动更新环境变量已关闭",
		str(env.get("OPENCODE_DISABLE_AUTOUPDATE", "")) == "true")
	_check("OpenCode 用户数据与系统安装隔离",
		str(env.get("XDG_CONFIG_HOME", "")).replace("\\", "/").contains("/opencode/config")
		and str(env.get("XDG_DATA_HOME", "")).replace("\\", "/").contains("/opencode/data"))


## 就绪后异步等 opencode 真正吐出 TUI 文本（ConPTY 子进程在后台线程拉起，
## 就绪信号发出时可能还没开始输出；TUI 完整渲染需要几秒）。
func _process(delta: float) -> bool:
	_elapsed += delta
	if _done:
		return false
	if not _ready_seen:
		if _elapsed > 90.0:
			_check("90s 内终端就绪", false)
			_client.stop()
			_finish()
		return false
	if not _bytes_checked:
		var bytes: int = _term.call("GetBytesReceived")
		# 先等输出量足够，再等屏幕出现文本（bg 填充会先于文字绘制）
		var nonblank: int = _count_nonblank()
		if bytes < 1500 or nonblank <= 3:
			if _elapsed > 90.0:
				_check("90s 内 OpenCode TUI 输出充足", false,
					"bytes=%d nonblank=%d" % [bytes, nonblank])
				_dump_screen()
				_client.stop()
				_finish()
			return false
		_bytes_checked = true
		print("[info] bytes=", bytes, " nonblank=", nonblank)
		_check("opencode TUI 输出充足 (bytes>1500)", bytes > 1500)
		var diag: String = _term.call("GetDiagnostics")
		print("[info] diag=", diag)
		_check("终端会话已建立", not diag.begins_with("no session"))
		# TUI 渲染检查：屏幕出现制表符/块元素 = alternate screen 渲染成功
		var stats: String = _term.call("GetRenderStats")
		print("[info] stats=", stats)
		var has_box: bool = stats.contains("box=") and not stats.contains("box=0")
		_check("TUI 制表符已渲染 (box>0)", has_box)
		_check("可见行有内容 (nonblank>3)", nonblank > 3)
		_dump_screen()
		# 工作区按构型准备好
		var ws_abs: String = ProjectSettings.globalize_path("user://stc32g_test_native")
		_check("AGENTS.md 已生成", FileAccess.file_exists(ws_abs.path_join("AGENTS.md")))
		var agents: String = FileAccess.get_file_as_string(ws_abs.path_join("AGENTS.md"))
		_check("AGENTS 标明当前构型（工程）", agents.contains("工程"))
		_check("AGENTS 未残留占位符", not agents.contains("{{"))
		# 停止终端
		_client.stop()
		_check("停止后 IsRunning==false", not bool(_term.get("IsRunning")))
		_finish()
	return false


func _count_nonblank() -> int:
	var n: int = 0
	for l in _term.call("GetVisibleLines"):
		if str(l).strip_edges() != "":
			n += 1
	return n


func _dump_screen() -> void:
	var lines = _term.call("GetVisibleLines")
	for i in range(0, mini(12, lines.size())):
		var s: String = str(lines[i]).rstrip(" ")
		if s != "":
			print("[screen] %02d: '%s'" % [i, s])


func _finish() -> void:
	if _done:
		return
	_done = true
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

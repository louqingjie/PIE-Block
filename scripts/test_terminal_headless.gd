extends SceneTree
## Headless 验证：ConPTY 子进程 -> XTerm.NET 引擎 -> 读取屏幕缓冲。
## 交互式 cmd.exe，通过 Write() 发送命令验证输出与输入。
## 用法：godot --headless --path . --script scripts/test_terminal_headless.gd

var term = null
var state := 0
var elapsed := 0.0

func _init() -> void:
	term = load("res://scripts/cs/TerminalControl.cs").new()
	root.add_child(term)
	term.Command = "cmd.exe"
	term.Columns = 80
	term.Rows = 24
	term.Start()
	print("[test] session started, pid=", term.GetProcessId())

func _process(delta: float) -> bool:
	elapsed += delta
	if state == 0 and elapsed > 3.0:
		state = 1
		term.Write("echo HELLO_FROM_TERMINAL\r")
		print("[test] sent echo command, bytes=", term.GetBytesReceived())
	elif state == 1 and elapsed > 8.0:
		state = 2
		print("[test] diag=", term.GetDiagnostics())
		print("[test] final bytes=", term.GetBytesReceived())
		var lines: Array = term.GetVisibleLines()
		var found := false
		for i in lines.size():
			var l: String = lines[i]
			if l.contains("HELLO_FROM_TERMINAL"):
				found = true
			print("[line ", i, "] ", l)
		print("[test] ", "PASS" if found else "FAIL")
		term.Stop()
		quit(0 if found else 1)
		return true
	return false
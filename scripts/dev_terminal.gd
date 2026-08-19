extends Control
## 窗口模式渲染验证：启动 PowerShell 终端，发送彩色输出，截图保存到 user://。
## 运行：godot --path . scenes/dev_terminal.tscn

var term: Control
var state := 0
var elapsed := 0.0

func _ready() -> void:
	term = $Term
	term.Command = "powershell.exe"
	term.Arguments = ["-NoLogo", "-NoExit"]
	term.Columns = 100
	term.Rows = 30
	term.Start()
	term.grab_focus()
	print("[dev] started pid=", term.GetProcessId())

func _process(delta: float) -> void:
	elapsed += delta
	if state == 0 and elapsed > 2.0:
		state = 1
		term.Write("Write-Host 'HELLO FROM PIE-BLOCK TERMINAL' -ForegroundColor Green\r")
		term.Write("Write-Host 'COLOR TEST' -ForegroundColor Red\r")
		term.Write("Write-Host ('ANSI ' + [char]27 + '[33mYELLOW' + [char]27 + '[0m OK')\r")
		print("[dev] sent commands")
	elif state == 1 and elapsed > 5.0:
		state = 2
		var img := get_viewport().get_texture().get_image()
		var path := "user://terminal_shot.png"
		img.save_png(path)
		print("[dev] screenshot saved to ", path, " size=", img.get_size())
		print("[dev] diag=", term.GetDiagnostics())
		for r in range(0, 8):
			print("[dev] line", r, ": ", term.DumpLine(r))

		# 程序化验证：采样截图像素，确认 ANSI 颜色真正渲染出来了
		var cw: float = term.GetCellWidth()
		var ch: float = term.GetCellHeight()
		print("[dev] cell=", cw, "x", ch)
		var checks := [
			[0, 1, Color(0, 1, 0), "HELLO green"],    # 行1 列0 'H'
			[0, 3, Color(1, 0, 0), "COLOR red"],      # 行3 列0 'C'
			[6, 5, Color(0.8, 0.8, 0), "YELLOW yellow"], # 行5 列6 'Y'
		]
		var failed := 0
		for chk in checks:
			var col: int = chk[0]
			var row: int = chk[1]
			var expect: Color = chk[2]
			var got := sample_cell(img, col, row, cw, ch)
			var ok := absf(got.r - expect.r) < 0.15 and absf(got.g - expect.g) < 0.15 and absf(got.b - expect.b) < 0.15
			if not ok:
				failed += 1
			print("[dev] check ", chk[3], " at (", col, ",", row, ") expect=", expect, " got=", got, " => ", "PASS" if ok else "FAIL")
		term.Stop()
		if failed == 0:
			print("[dev] ALL COLOR CHECKS PASSED")
			get_tree().quit(0)
		else:
			print("[dev] ", failed, " COLOR CHECK(S) FAILED")
			get_tree().quit(1)

func sample_cell(img: Image, col: int, row: int, cw: float, ch: float) -> Color:
	# 在格子内采样 3x3 点，取最亮（离背景最远）的像素
	var best := Color(0, 0, 0)
	for i in range(3):
		for j in range(3):
			var px := img.get_pixel(
				int(col * cw + cw * (0.15 + 0.35 * i)),
				int(row * ch + ch * (0.15 + 0.35 * j)))
			if px.r + px.g + px.b > best.r + best.g + best.b:
				best = px
	return best
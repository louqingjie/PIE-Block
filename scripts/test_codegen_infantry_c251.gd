extends SceneTree

const TC = preload("res://scripts/toolchain.gd")
const CG = preload("res://scripts/codegen/codegen_infantry.gd")


func _initialize() -> void:
	var code: String = CG.new().generate({})
	if code.contains("remote_control_init();") \
			or not code.contains("remoteControlInitWithTimeout();") \
			or not code.contains("retry < 20"):
		printerr("生成代码必须使用有限重试的遥控器初始化")
		quit(1)
		return
	if not code.contains("void iapEnterDownload(void)"):
		printerr("生成代码没有可供 UART ISR 调用的 iapEnterDownload")
		quit(1)
		return
	var code_off: String = CG.new().generate({"lcd_debug": false})
	if not code.contains("LCD_Init();") \
			or not code.contains("LCD_CLS();") \
			or not code.contains("LCD_P6x8Str(0, 0, \"PIE-BLOCK BOOT\");") \
			or not code.contains("burnBeep(1047, 240);"):
		printerr("生成代码缺少 LCD 初始化调试输出（默认应开启）")
		quit(1)
		return
	if code_off.contains("LCD_Init();") or code_off.contains("LCD_CLS();"):
		printerr("lcd_debug=false 时不应生成 LCD 调试代码")
		quit(1)
		return
	var tc = TC.new(func(line: String) -> void: print(line))
	var result: Dictionary = tc.build_project(TC.PROJECT_DST, code)
	if not bool(result.get("ok", false)):
		printerr(str(result.get("log", "步兵 C251 编译失败")))
		quit(1)
		return
	print("=== C251 步兵 IAP 编译: 通过 ===")
	quit(0)
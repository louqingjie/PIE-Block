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
	if not code.contains("burnBeep(1047, 240);"):
		printerr("生成代码缺少初始化完成提示音")
		quit(1)
		return
	# —— 以下为实测修复的回归断言（UART 死锁 / NRF 中断死锁 / LED 诊断）——
	if not code.contains("Uart1TxQuery("):
		printerr("生成代码缺少 UART1 查询发送（UART_BUSY 死锁修复）")
		quit(1)
		return
	if code.contains("UART_PutChar(UART_1, control_frame_pack"):
		printerr("生成代码 ExpansionBoradControl 仍用 UART_PutChar（应改 Uart1TxQuery）")
		quit(1)
		return
	if not code.contains("P2INTE &= ~GPIO_Pin_6"):
		printerr("生成代码缺少关 P2.6 EXTI（NRF 中断死锁修复）")
		quit(1)
		return
	if not code.contains("nrf_handler(); // 轮询 NRF 接收"):
		printerr("生成代码缺少主循环轮询 nrf_handler()（P2.6 中断已关）")
		quit(1)
		return
	if not code.contains("void StepBegin") or not code.contains("void StepDone") \
			or not code.contains("void LedShow"):
		printerr("生成代码缺少初始化 LED 诊断工具")
		quit(1)
		return
	if not code.contains("StepBegin(0);"):
		printerr("生成代码 All_Init 未分步（初始化阻塞定位）")
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
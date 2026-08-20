extends SceneTree

const TC = preload("res://scripts/toolchain.gd")
const CG = preload("res://scripts/codegen/codegen_infantry.gd")
const SC = preload("res://scripts/static_checker.gd")


func _initialize() -> void:
	var infantry_scene: PackedScene = load("res://scenes/infantry.tscn")
	var infantry_ui: Node = infantry_scene.instantiate()
	if not infantry_ui.has_node("KeySetting/Booster/MaxDuty"):
		printerr("步兵界面缺少摩擦轮最大占空比设置")
		infantry_ui.free()
		quit(1)
		return
	infantry_ui.free()
	var friction_issues: Array = SC.check_infantry({"friction_max_duty": "1200"})
	var found_friction_limit: bool = false
	for issue in friction_issues:
		if str(issue.get("msg", "")).contains("摩擦轮最大占空比"):
			found_friction_limit = true
	if not found_friction_limit:
		printerr("静态检查未阻止超过官方上限的摩擦轮占空比")
		quit(1)
		return
	var code: String = CG.new().generate({})
	# IO 初始化区不能因“未被模式控制行引用”而泄漏内部默认值 0Hz。
	# 步兵前四路与摩擦轮共用 50Hz 时基，因此 P60/P62 即使逻辑类型为电机，
	# Init_Order 也必须与官方示例一致保持 50,50,50,50。
	var servo_p62_code: String = CG.new().generate({
		"io_init": {"P62": "舵机"},
	})
	if not servo_p62_code.contains("50, 50,\n                          50, 50,"):
		printerr("步兵前四路必须统一按 50Hz 初始化，不能生成 0Hz 或混合频率")
		quit(1)
		return
	var motor_p62_code: String = CG.new().generate({
		"io_init": {"P62": "电机"},
	})
	if not motor_p62_code.contains("50, 50,\n                          50, 50,"):
		printerr("P62 作为电机时也不得破坏步兵前四路共享的 50Hz 时基")
		quit(1)
		return
	if code.contains("remote_control_init();") \
			or not code.contains("remoteControlInitWithTimeout();") \
			or not code.contains("retry < 20"):
		printerr("生成代码必须使用有限重试的遥控器初始化")
		quit(1)
		return
	if not code.contains("Beep(1047, 240);"):
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
	if not code.contains("uint8_t uart1InterruptEnabled = ES;") \
			or not code.contains("ES = uart1InterruptEnabled;"):
		printerr("UART1 查询发送必须保存并恢复调用前的串口中断状态")
		quit(1)
		return
	var dir_pos: int = code.find("ExpansionBoradControl(Dir_Change_Order,", code.find("void Main_Countrol("))
	var gap_pos: int = code.find("Ms_Delay(EXPANSION_FRAME_GAP_MS);", dir_pos)
	var duty_pos: int = code.find("ExpansionBoradControl(Duty_Change_Order,", gap_pos)
	if dir_pos < 0 or gap_pos < 0 or duty_pos < 0 or not (dir_pos < gap_pos and gap_pos < duty_pos):
		printerr("Main_Countrol 必须按「方向帧 -> 帧间隔 -> 占空比帧」顺序发送")
		quit(1)
		return
	var second_gap_pos: int = code.find("Ms_Delay(EXPANSION_FRAME_GAP_MS);", duty_pos)
	if second_gap_pos < 0:
		printerr("占空比帧后缺少拓展板处理间隔")
		quit(1)
		return
	if code.contains("主循环周期 10ms，每周期变化 1"):
		printerr("摩擦轮渐变注释仍错误地忽略了通信帧间隔")
		quit(1)
		return
	# 摩擦轮必须完全采用官方阻塞式开关控制：500 起步，每 1500ms 增加 100，
	# 稳态只有 0 或用户设定的最大值，不再保留 B/C 档位和非阻塞目标跟踪。
	if not code.contains("#define FRICTION_MAX_DUTY   1100") \
			or not code.contains("while (dutyOfBooster < FRICTION_MAX_DUTY)") \
			or not code.contains("#define FRICTION_STEP_MS    1500") \
			or not code.contains("dutyOfBooster += FRICTION_STEP_DUTY;"):
		printerr("生成代码缺少官方阻塞式摩擦轮增速序列")
		quit(1)
		return
	for forbidden in ["expectDutyOfBooster", "levelDutyOfBooster",
			"lastBoosterUpKeyValue", "lastBoosterDownKeyValue",
			"singleChangeDutyOfBooster"]:
		if code.contains(forbidden):
			printerr("生成代码仍残留可停留中间占空比的逻辑：%s" % forbidden)
			quit(1)
			return
	var limited_code: String = CG.new().generate({"friction_max_duty": "800"})
	if not limited_code.contains("#define FRICTION_MAX_DUTY   800"):
		printerr("用户指定的摩擦轮最大占空比未进入生成代码")
		quit(1)
		return
	var over_limit_code: String = CG.new().generate({"friction_max_duty": "1200"})
	if not over_limit_code.contains("#define FRICTION_MAX_DUTY   1100"):
		printerr("超过官方上限的摩擦轮占空比未安全回退到 1100")
		quit(1)
		return
	if not code.contains("while (dutyOfBooster > FRICTION_START_DUTY)") \
			or not code.contains("dutyOfBooster -= FRICTION_STEP_DUTY;") \
			or not code.contains("dutyOfBooster = 0;"):
		printerr("生成代码缺少摩擦轮阻塞式逐级关闭逻辑")
		quit(1)
		return
	var booster_func_start: int = code.find("void CalculateBoosterControl()\n{")
	var booster_func_end: int = code.find("void CalculateGimbalControls()\n{", booster_func_start)
	var booster_func: String = code.substr(booster_func_start, booster_func_end - booster_func_start)
	var booster_duty_frame: int = booster_func.find("ExpansionBoradControl(Duty_Change_Order")
	var booster_dir_frame: int = booster_func.find("ExpansionBoradControl(Dir_Change_Order")
	if booster_func.contains("Main_Countrol("):
		printerr("摩擦轮阻塞启停仍错误地经过 Main_Countrol")
		quit(1)
		return
	if booster_duty_frame < 0 or booster_dir_frame < 0 or booster_duty_frame > booster_dir_frame:
		printerr("摩擦轮阻塞启停没有严格采用官方 Duty 帧 -> Dir 帧顺序")
		quit(1)
		return
	if not booster_func.contains("Duty_Change_Order, 0, 0, dutyOfBooster, dutyOfBooster, 0, 0, 0, 0") \
			or not booster_func.contains("Dir_Change_Order, 1, 1, 0, 0, 0, 0, 0, 0"):
		printerr("摩擦轮阻塞启停的 P64/P66 直发参数不符合官方示例")
		quit(1)
		return
	if not code.contains("Ms_Delay(1000);"):
		printerr("摩擦轮初始化后缺少必须的 1000ms 硬件反应时间")
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
	print("=== C251 步兵 阻塞开环拨弹 编译: 通过 ===")
	# —— 目视闭环拨弹模式（按住持续拨弹、松开即停，不阻塞）——
	var vcfg: Dictionary = {"feed_mode": "目视闭环"}
	var vcode: String = CG.new().generate(vcfg)
	if not vcode.contains("dutyOfMotor[4] = triggerKeyValue ? boosterDutyOfFeed : 0;"):
		printerr("目视闭环模式缺少「按住持续拨弹」代码")
		quit(1)
		return
	if vcode.contains("boosterFeedDelayMs"):
		printerr("目视闭环模式不应生成拨弹时间常量 boosterFeedDelayMs")
		quit(1)
		return
	if vcode.contains("Ms_Delay(boosterFeedDelayMs)"):
		printerr("目视闭环模式不应有阻塞延时")
		quit(1)
		return
	if not code.contains("Ms_Delay(boosterFeedDelayMs)"):
		printerr("阻塞开环模式（默认）必须保留单发阻塞延时")
		quit(1)
		return
	var vresult: Dictionary = tc.build_project(TC.PROJECT_DST, vcode)
	if not bool(vresult.get("ok", false)):
		printerr(str(vresult.get("log", "目视闭环 C251 编译失败")))
		quit(1)
		return
	print("=== C251 步兵 目视闭环拨弹 编译: 通过 ===")
	quit(0)

extends SceneTree

const TC = preload("res://scripts/toolchain.gd")
const CG = preload("res://scripts/codegen/codegen_infantry.gd")
const SC = preload("res://scripts/static_checker.gd")


func _initialize() -> void:
	var infantry_scene: PackedScene = load("res://scenes/infantry.tscn")
	var infantry_ui: Node = infantry_scene.instantiate()
	if not infantry_ui.has_node("KeySetting/BoosterSpeed/MaxDuty"):
		printerr("步兵界面缺少摩擦轮最大占空比设置")
		infantry_ui.free()
		quit(1)
		return
	if not infantry_ui.has_node("KeySetting/FrictionType/OptionButton"):
		printerr("步兵界面缺少摩擦轮类型设置")
		infantry_ui.free()
		quit(1)
		return
	infantry_ui.free()
	var friction_issues: Array = SC.check_infantry({"friction_max_duty": "900"})
	var found_friction_limit: bool = false
	for issue in friction_issues:
		if str(issue.get("msg", "")).contains("摩擦轮最大占空比"):
			found_friction_limit = true
	if not found_friction_limit:
		printerr("静态检查未阻止超过校内赛安全上限的摩擦轮占空比")
		quit(1)
		return
	var disabled_issues: Array = SC.check_infantry({
		"friction_type": "不使用", "friction_max_duty": "900",
		"l1_io": "P64 P65", "booster_io": "P66 P67",
	})
	for issue in disabled_issues:
		var disabled_msg: String = str(issue.get("msg", ""))
		if disabled_msg.contains("摩擦轮最大占空比") or disabled_msg.contains("摩擦轮固定占用"):
			printerr("禁用摩擦轮后仍参与 duty 或 P64/P66 占用检查：%s" % disabled_msg)
			quit(1)
			return
	var invalid_type_issues: Array = SC.check_infantry({"friction_type": "有刷电机"})
	var found_invalid_type: bool = false
	for issue in invalid_type_issues:
		if str(issue.get("msg", "")).contains("摩擦轮类型"):
			found_invalid_type = true
	if not found_invalid_type:
		printerr("静态检查未报告非法摩擦轮类型")
		quit(1)
		return
	var code: String = CG.new().generate({})
	if code != CG.new().generate({"friction_type": "无刷电调"}):
		printerr("旧项目缺少 friction_type 时未保持原有无刷生成结果")
		quit(1)
		return
	# 步兵不再读取 IO 初始化和高级模式字段；固定角色以外的端口安全按 50Hz 初始化。
	var stale_advanced_code: String = CG.new().generate({
		"io_init": {"P60": "电机", "P62": "电机", "P64": "电机", "P66": "电机"},
		"mode_count": "4", "modes": [{"rows": [{"io": "P62", "key": "A", "mode": "直接", "param": "1000"}]}],
	})
	for forbidden_advanced in ["currentMode", "UpdateMode", "Calculate_Mode", "dutyOfAux"]:
		if stale_advanced_code.contains(forbidden_advanced):
			printerr("步兵代码仍包含高级设置符号：%s" % forbidden_advanced)
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
	# 摩擦轮采用主循环驱动的平滑非阻塞状态机：开关和 B/C 只改目标，
	# 当前 Duty 每轮增加/减少 1，蜂鸣器只在实际变化期间跟随当前 Duty。
	if not code.contains("#define FRICTION_MAX_DUTY   800") \
			or not code.contains("#define FRICTION_STEP_DUTY  1") \
			or not code.contains("targetDutyOfBooster = statusOfBooster ? FRICTION_MAX_DUTY : 0;") \
			or not code.contains("frictionSpeedUpKeyValue && !lastFrictionSpeedUpKeyValue") \
			or not code.contains("frictionSpeedDownKeyValue && !lastFrictionSpeedDownKeyValue") \
			or not code.contains("targetDutyOfBooster += 100;") \
			or not code.contains("dutyOfBooster += FRICTION_STEP_DUTY;"):
		printerr("生成代码缺少校内赛安全的非阻塞摩擦轮增速状态机")
		quit(1)
		return
	for forbidden in ["expectDutyOfBooster", "levelDutyOfBooster",
			"singleChangeDutyOfBooster"]:
		if code.contains(forbidden):
			printerr("生成代码仍残留可停留中间占空比的逻辑：%s" % forbidden)
			quit(1)
			return
	var limited_code: String = CG.new().generate({"friction_max_duty": "700"})
	if not limited_code.contains("#define FRICTION_MAX_DUTY   700"):
		printerr("用户指定的摩擦轮最大占空比未进入生成代码")
		quit(1)
		return
	var over_limit_code: String = CG.new().generate({"friction_max_duty": "900"})
	if not over_limit_code.contains("#define FRICTION_MAX_DUTY   800"):
		printerr("超过校内赛安全上限的摩擦轮占空比未安全回退到 800")
		quit(1)
		return
	if not code.contains("else if (dutyOfBooster > targetDutyOfBooster)") \
			or not code.contains("dutyOfBooster -= FRICTION_STEP_DUTY;"):
		printerr("生成代码缺少摩擦轮非阻塞逐级关闭逻辑")
		quit(1)
		return
	var booster_func_start: int = code.find("void CalculateBoosterControl()\n{")
	var booster_func_end: int = code.find("void CalculateGimbalControls()\n{", booster_func_start)
	var booster_func: String = code.substr(booster_func_start, booster_func_end - booster_func_start)
	if booster_func.contains("Main_Countrol("):
		printerr("摩擦轮状态机不应主动调用 Main_Countrol")
		quit(1)
		return
	if booster_func.contains("ExpansionBoradControl(") or booster_func.contains("Dir_Change_Order"):
		printerr("摩擦轮状态机只能更新当前 duty，不得自行发送扩展板控制帧")
		quit(1)
		return
	if booster_func.contains("Ms_Delay(") or booster_func.contains("while ("):
		printerr("摩擦轮状态机仍残留阻塞等待或追赶循环")
		quit(1)
		return
	if not code.contains("#define BUZZER_CH PWMA_CH4N_P33") \
			or not code.contains("PWM_SET_Frequency(BUZZER_CH, duty, 5000);") \
			or not booster_func.contains("FrictionBuzzerTrace(dutyOfBooster);") \
			or not booster_func.contains("FrictionBuzzerOff();"):
		printerr("摩擦轮平滑斜坡缺少 duty 同频蜂鸣跟踪或完成后的静音逻辑")
		quit(1)
		return
	if booster_func.contains("Beep("):
		printerr("摩擦轮蜂鸣跟踪错误地调用了会额外阻塞时序的 Beep")
		quit(1)
		return
	for forbidden_timer in ["PIT_Timer_Ms(TIM2", "TM2_Isr", "frictionTickMs", "frictionLastStepMs", "FrictionTickNow"]:
		if code.contains(forbidden_timer):
			printerr("摩擦轮主循环状态机仍残留定时器逻辑：%s" % forbidden_timer)
			quit(1)
			return
	if not booster_func.contains("if (frictionRampActive)"):
		printerr("摩擦轮非阻塞状态机没有按主循环逐次推进")
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
	var skip_c251: bool = OS.get_environment("PIE_BLOCK_SKIP_C251") == "1"
	var tc = TC.new(func(line: String) -> void: print(line))
	if skip_c251:
		print("=== C251 外部编译器不可用：跳过步兵 C251 编译，仅执行生成断言 ===")
	else:
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
	if not skip_c251:
		var vresult: Dictionary = tc.build_project(TC.PROJECT_DST, vcode)
		if not bool(vresult.get("ok", false)):
			printerr(str(vresult.get("log", "目视闭环 C251 编译失败")))
			quit(1)
			return
		print("=== C251 步兵 目视闭环拨弹 编译: 通过 ===")
	# —— 不使用摩擦轮：彻底移除控制逻辑并释放 P64/P66 ——
	var dcfg: Dictionary = {
		"friction_type": "不使用",
		"l1_io": "P64 P65",
		"booster_io": "P66 P67",
	}
	var dcode: String = CG.new().generate(dcfg)
	for forbidden_friction in ["FRICTION_MAX_DUTY", "dutyOfBooster", "boosterKeyValue",
			"frictionSpeedUpKeyValue", "frictionSpeedDownKeyValue",
			"CalculateBoosterControl", "FrictionBuzzerTrace", "FrictionBuzzerOff",
			"Ms_Delay(1000);"]:
		if dcode.contains(forbidden_friction):
			printerr("不使用摩擦轮的代码仍残留：%s" % forbidden_friction)
			quit(1)
			return
	if not dcode.contains("void Main_Countrol(int *dutyOfMotor, uint16_t *dutyOfServo)") \
			or not dcode.contains("(uint16_t)abs(dutyOfMotor[0]), dutyOfMotor[4]"):
		printerr("禁用摩擦轮后 P64/P66 未按底盘/拨弹普通端口生成")
		quit(1)
		return
	var yaw_p64_code: String = CG.new().generate({
		"friction_type": "不使用", "yaw_drive": "电机", "yaw_io": "P64",
		"pitch_drive": "舵机", "pitch_io": "P66",
	})
	if not yaw_p64_code.contains("(uint16_t)abs(dutyOfMotor[5]), dutyOfServo[1]"):
		printerr("禁用摩擦轮后 P64/P66 未按云台电机/舵机生成")
		quit(1)
		return
	var invalid_code: String = CG.new().generate({"friction_type": "非法值"})
	if not invalid_code.contains("FRICTION_MAX_DUTY") or not invalid_code.contains("Ms_Delay(1000);"):
		printerr("非法摩擦轮类型未安全回退到无刷电调")
		quit(1)
		return
	if not skip_c251:
		var dresult: Dictionary = tc.build_project(TC.PROJECT_DST, dcode)
		if not bool(dresult.get("ok", false)):
			printerr(str(dresult.get("log", "禁用摩擦轮 C251 编译失败")))
			quit(1)
			return
		print("=== C251 步兵 不使用摩擦轮 编译: 通过 ===")
	quit(0)

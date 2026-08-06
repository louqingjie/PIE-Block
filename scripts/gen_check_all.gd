extends SceneTree
## 验证所有构型生成器都包含实测修复（UART 查询发送 / NRF 中断 / LED 诊断）

const INF = preload("res://scripts/codegen/codegen_infantry.gd")
const ENG = preload("res://scripts/codegen/codegen_engineer.gd")
const IKE = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const DBG = preload("res://scripts/codegen/codegen_debug.gd")


func _check(name: String, code: String, has_nrf: bool) -> bool:
	var fail: bool = false
	var common: Array = [
		["Uart1TxQuery(", "UART1 查询发送"],
		["void StepBegin", "LED 诊断 StepBegin"],
		["void StepDone", "LED 诊断 StepDone"],
		["void LedShow", "LED 诊断 LedShow"],
		["StepBegin(0);", "All_Init 分步"],
	]
	var nrf: Array = [
		["P2INTE &= ~GPIO_Pin_6", "关 P2.6 EXTI"],
		["nrf_handler(); // 轮询 NRF 接收", "主循环轮询 nrf_handler"],
	]
	for item in common:
		if not code.contains(item[0]):
			printerr("[%s] 缺少「%s」→ %s" % [name, item[1], item[0]])
			fail = true
	if has_nrf:
		for item in nrf:
			if not code.contains(item[0]):
				printerr("[%s] 缺少「%s」→ %s" % [name, item[1], item[0]])
				fail = true
	if code.contains("UART_PutChar(UART_1, control_frame_pack"):
		printerr("[%s] ExpansionBoradControl 仍用 UART_PutChar" % name)
		fail = true
	if fail:
		printerr("[%s] 校验失败" % name)
	else:
		print("[%s] 校验通过" % name)
	return not fail


func _make_ik_cfg() -> Dictionary:
	# 2 关节最小真实配置（结构同 test_codegen_ik.gd 的 _make_cfg），
	# 避免用空 {} 调用 engineer_ik.generate 触发数组越界
	var joints: Array = []
	var io_list: Array = ["P74", "P75", "P76", "MP03", "MP74", "P77"]
	var lens: Array = [100.0, 80.0]
	for i in range(2):
		joints.append({
			"io": io_list[i], "dir": "正向",
			"axis": "Yaw" if i == 0 else "Pitch", "len": str(lens[i]), "zero": "45",
			"min": "-90", "max": "90",
		})
	return {
		"joint_count": 2,
		"joints": joints,
		"presets": [],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "5",
		"keymove_speed": "2",
		"orientation_key_speed": "1.5",
		"rocker2_home_enabled": false,
		"keymove": [
			{"plus": "↑", "minus": "↓"},
			{"plus": "←", "minus": "->"},
			{"plus": "B", "minus": "C"},
			{"plus": "不使用", "minus": "不使用"},
			{"plus": "D", "minus": "R"},
			{"plus": "不使用", "minus": "不使用"},
		],
	}


func _initialize() -> void:
	var ok: bool = true
	var inf: String = INF.new().generate({})
	ok = _check("infantry", inf, true) and ok
	var eng: String = ENG.new().generate({})
	ok = _check("engineer", eng, true) and ok
	var ike: String = IKE.new().generate(_make_ik_cfg())
	ok = _check("engineer_ik", ike, true) and ok
	var dbg: String = DBG.new().generate({})
	ok = _check("debug", dbg, false) and ok
	if not ok:
		printerr("=== 有构型未通过校验 ===")
		quit(1)
		return
	print("=== 全部构型校验通过 ===")
	quit(0)

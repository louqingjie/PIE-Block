extends SceneTree

## 工程多模式切换蜂鸣器琶音反馈生成测试。
## 运行：godot --headless --path . --script res://scripts/test_codegen_mode_feedback.gd

const ENGINEER = preload("res://scripts/codegen/codegen_engineer.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s%s" % [label, ("：" + detail) if not detail.is_empty() else ""])
		_fail += 1


func _config(mode_count: int, strategy: String) -> Dictionary:
	var modes: Array = []
	for _i in range(4):
		modes.append({"rows": []})
	return {
		"mode_count": mode_count,
		"switch_strategy": strategy,
		"mode_switch_key": "E",
		"mode_keys": ["A", "B", "C", "D"],
		"modes": modes,
	}


func _update_mode_section(code: String) -> String:
	var start: int = code.find("void UpdateMode()")
	var end: int = code.find("void Calculate_Chassis_Control()\n", start)
	return code.substr(start, end - start) if start >= 0 and end > start else ""


func _initialize() -> void:
	var generator = ENGINEER.new()
	var click_code: String = generator.generate(_config(4, "单击切换"))
	var click_update: String = _update_mode_section(click_code)
	_check("多模式生成 ModeSwitchFeedback", click_code.contains(
		"static void ModeSwitchFeedback(uint8_t mode)"))
	_check("长音为 523Hz/1000ms", click_code.contains("Beep(523, 1000);"))
	_check("长音后等待 300ms", click_code.contains(
		"Beep(523, 1000);\n    Ms_Delay(300);"))
	var short_order: Array[String] = [
		"Beep(659, 300);", "Beep(784, 300);", "Beep(1047, 300);", "Beep(1319, 300)",
	]
	var previous: int = -1
	for note in short_order:
		var position: int = click_code.find(note)
		_check("短音包含 %s" % note, position > previous)
		previous = position
	_check("短音之间使用 300ms 间隔",
		click_code.contains("Beep(659, 300);\n        if (mode > 1)\n            Ms_Delay(300);")
		and click_code.contains("Beep(784, 300);\n        if (mode > 2)\n            Ms_Delay(300);")
		and click_code.contains("Beep(1047, 300);\n        if (mode > 3)\n            Ms_Delay(300);"))
	_check("单击切换更新模式后播放反馈",
		click_update.find("currentMode = (currentMode % 4) + 1;")
			< click_update.find("ModeSwitchFeedback(currentMode);"))
	_check("单击反馈位于按键触发条件块内",
		click_update.contains("if (pressed && !modeKeyHeld)\n    {\n")
		and click_update.contains("ModeSwitchFeedback(currentMode);\n    }\n"))
	_check("单击切换支持模式 4 回到模式 1",
		click_update.contains("currentMode = (currentMode % 4) + 1;"))

	var direct_code: String = generator.generate(_config(4, "一一对应"))
	var direct_update: String = _update_mode_section(direct_code)
	for i in range(4):
		var expected: String = "currentMode = %d;\n        ModeSwitchFeedback(%d);\n    }" % [i + 1, i + 1]
		_check("一一对应模式%d播放对应反馈" % (i + 1), direct_update.contains(expected))
	_check("一一对应反馈位于按下沿逻辑内",
		direct_update.contains("if (valueOfKey[1][0] && !modeKeyLast[0])\n    {")
		and direct_update.contains("ModeSwitchFeedback(1);"))

	var single_code: String = generator.generate(_config(1, "单击切换"))
	_check("单模式不生成模式反馈函数",
		not single_code.contains("ModeSwitchFeedback"))
	_check("单模式不生成模式反馈长音",
		not single_code.contains("Beep(523, 1000);"))

	if _fail > 0:
		print("失败 %d 项" % _fail)
		quit(1)
	else:
		print("全部通过")
		quit(0)

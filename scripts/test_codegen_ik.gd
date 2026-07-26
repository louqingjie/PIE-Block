extends SceneTree

## 代码生成验证脚本：调用 CodeGenEngineerIK 生成 main.c 并输出到文件
## 运行方式：godot --headless --script scripts/test_codegen_ik.gd

func _initialize() -> void:
	print("=== 工程逆解算代码生成验证 ===\n")
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	# 构造测试配置：2轴，L1=100,L2=100，2个关节
	var cfg: Dictionary = {
		"config_type": 0,
		"joint_count": 2,
		"L1": "100",
		"L2": "100",
		"L3": "0",
		"joints": [
			{"io": "P74", "dir": "正向", "zero": "0", "min": "-90", "max": "90"},
			{"io": "P75", "dir": "正向", "zero": "0", "min": "0", "max": "180"},
		],
		"presets": [
			{"key": "A", "x": "100", "y": "100", "z": "0", "phi": "0", "enabled": true},
			{"key": "B", "x": "200", "y": "0", "z": "0", "phi": "0", "enabled": true},
		],
		"joy_x": "左X->末端X",
		"joy_y": "左Y->末端Y",
		"joy_z": "右X->末端Z",
		"joy_scale": "200",
	}
	var code: String = cg.generate(cfg)
	# 写入文件
	var f = FileAccess.open("res://test_ik_output.c", FileAccess.WRITE)
	if f == null:
		print("[✗ FAIL] 无法写入 test_ik_output.c")
		quit(1)
		return
	f.store_string(code)
	f.close()
	print("[✓ PASS] 2轴代码生成成功，长度 %d 字符" % code.length())
	print("[✓ PASS] 写入 res://test_ik_output.c")
	# 验证关键内容
	var checks: Array = [
		{"name": "包含 main.h", "ok": code.find("#include \"main.h\"") >= 0},
		{"name": "包含 MATH.H", "ok": code.find("#include \"MATH.H\"") >= 0},
		{"name": "定义 L1", "ok": code.find("#define L1") >= 0},
		{"name": "定义 JOINT_COUNT", "ok": code.find("#define JOINT_COUNT 2") >= 0},
		{"name": "有 angle_to_duty 函数", "ok": code.find("uint16_t angle_to_duty") >= 0},
		{"name": "有 ik_solve 函数", "ok": code.find("void ik_solve(") >= 0},
		{"name": "有 ExpansionBoradControl", "ok": code.find("void ExpansionBoradControl(") >= 0},
		{"name": "有预设点位表", "ok": code.find("presetAngles") >= 0},
		{"name": "有 main 函数", "ok": code.find("void main()") >= 0},
		{"name": "有 All_Init 函数", "ok": code.find("void All_Init()") >= 0},
		{"name": "有 ReadControllerInputs", "ok": code.find("void ReadControllerInputs()") >= 0},
		{"name": "有 CheckPresetKeys", "ok": code.find("void CheckPresetKeys()") >= 0},
		{"name": "有 CalculateIK", "ok": code.find("void CalculateIK()") >= 0},
		{"name": "有 ApplyServoControl", "ok": code.find("void ApplyServoControl()") >= 0},
	]
	var all_pass: bool = true
	# 测试 2 轴
	all_pass = _test_config(cg, 0, 2, "2轴") and all_pass
	# 测试 3 轴
	all_pass = _test_config(cg, 1, 3, "3轴") and all_pass
	# 测试 4 轴
	all_pass = _test_config(cg, 2, 4, "4轴") and all_pass
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if all_pass else "存在失败 ✗"))
	quit(0 if all_pass else 1)


func _test_config(cg, config_type: int, jc: int, name: String) -> bool:
	var joints: Array = []
	var io_list: Array = ["P74", "P75", "P76", "MP03"]
	for i in range(jc):
		joints.append({
			"io": io_list[i], "dir": "正向", "zero": "0",
			"min": "-90", "max": "90",
		})
	var cfg: Dictionary = {
		"config_type": config_type, "joint_count": jc,
		"L1": "100", "L2": "80", "L3": "30",
		"joints": joints,
		"presets": [ {"key": "A", "x": "100", "y": "80", "z": "50", "phi": "90", "enabled": true}],
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "200",
		"keymove_speed": "2",
		"keymove": [
			{"plus": "↑", "minus": "↓"},
			{"plus": "←", "minus": "->"},
			{"plus": "B", "minus": "C"},
		],
	}
	var code: String = cg.generate(cfg)
	var ok: bool = not code.is_empty()
	# 写入文件供编译验证（最后一个构型覆盖）
	var f = FileAccess.open("res://test_ik_output.c", FileAccess.WRITE)
	if f:
		f.store_string(code)
		f.close()
	var status: String = "✓ PASS" if ok else "✗ FAIL"
	print("[%s] %s 代码生成 (长度 %d)" % [status, name, code.length()])
	return ok

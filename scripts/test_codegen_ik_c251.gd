extends SceneTree

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var cfg: Dictionary = {
		"engineer": {
			"channel": "36", "deadzone": "10", "normal_speed": "4000",
			"l1_io": "P60 P61", "l2_io": "P62 P63",
			"r1_io": "P64 P65", "r2_io": "P66 P67",
			"l1_dir": "正向", "l2_dir": "正向",
			"r1_dir": "正向", "r2_dir": "正向",
			"io_init": {
				"P60": "电机", "P62": "电机", "P64": "电机", "P66": "电机",
				"P74": "舵机", "P75": "舵机", "P76": "电机", "P77": "舵机",
			},
			"key_map": [
				{"input": "A", "dir": "正", "mode": "增量", "param": "2", "target": "P74"},
				{"input": "B", "dir": "反", "mode": "增量", "param": "2", "target": "P74"},
				{"input": "右摇杆X", "dir": "正", "mode": "速度", "param": "3000", "target": "P76"},
				{"input": "C", "dir": "正", "mode": "直接", "param": "30", "target": "MP74"},
			],
		},
		"ik": {
			"config_type": 2, "joint_count": 4, "mode_switch_key": "R",
			"joints": [
				{"io": "P74", "dir": "正向", "axis": "Yaw", "len": "0", "offset": "0", "zero": "0", "min": "-90", "max": "90"},
				{"io": "P75", "dir": "正向", "axis": "Pitch", "len": "120", "offset": "0", "zero": "20", "min": "-90", "max": "90"},
				{"io": "P77", "dir": "正向", "axis": "Pitch", "len": "90", "offset": "0", "zero": "30", "min": "-90", "max": "90"},
				{"io": "MP03", "dir": "正向", "axis": "Pitch", "len": "40", "offset": "0", "zero": "0", "min": "-90", "max": "90"},
			],
			"presets": [],
			"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
			"joy_scale": "5", "keymove_speed": "2",
			"keymove": [
				{"plus": "↑", "minus": "↓"},
				{"plus": "←", "minus": "->"},
				{"plus": "B", "minus": "C"},
				{"plus": "D", "minus": "不使用"},
			],
		},
	}
	var code: String = CG.new().generate(cfg)
	var tc = TC.new()
	var result: Dictionary = tc.build_project(TC.PROJECT_ENGINEER_DST, code)
	print(result.get("log", ""))
	if result.get("ok", false):
		print("=== C251 双模式编译: 通过 ===")
		quit(0)
	else:
		print("=== C251 双模式编译: 失败 ===")
		quit(1)
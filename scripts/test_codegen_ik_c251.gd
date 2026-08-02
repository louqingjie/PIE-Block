extends SceneTree

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _joint(template: Dictionary, io: String, axis: String, length: String,
		zero: String = "0") -> Dictionary:
	var joint: Dictionary = template.duplicate(true)
	joint["io"] = io
	joint["axis"] = axis
	joint["len"] = length
	joint["zero"] = zero
	return joint


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
			"joint_count": 4, "mode_switch_key": "R",
			"joints": [
				{"io": "P74", "dir": "正向", "axis": "Yaw", "len": "0", "offset": "0", "zero": "0", "min": "-90", "max": "90"},
				{"io": "P75", "dir": "正向", "axis": "Pitch", "len": "120", "offset": "0", "zero": "20", "min": "-90", "max": "90"},
				{"io": "P77", "dir": "正向", "axis": "Pitch", "len": "90", "offset": "0", "zero": "30", "min": "-90", "max": "90"},
				{"io": "MP03", "dir": "正向", "axis": "Pitch", "len": "40", "offset": "0", "zero": "0", "min": "-90", "max": "90"},
			],
			"presets": [],
			"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
			"joy_scale": "5", "keymove_speed": "2", "orientation_key_speed": "1",
			"rocker2_home_enabled": true,
			"keymove": [
				{"plus": "↑", "minus": "↓"},
				{"plus": "←", "minus": "->"},
				{"plus": "B", "minus": "C"},
				{"plus": "不使用", "minus": "不使用"},
				{"plus": "D", "minus": "不使用"},
				{"plus": "不使用", "minus": "不使用"},
			],
		},
	}
	var template: Dictionary = cfg["ik"]["joints"][0]
	var cases: Array = [
		{"name": "2-joint", "joints": [
			_joint(template, "P74", "Yaw", "0"),
			_joint(template, "P75", "Pitch", "150", "20"),
		]},
		{"name": "4-joint", "joints": cfg["ik"]["joints"]},
		{"name": "5-joint", "joints": [
			_joint(template, "P74", "Yaw", "0"),
			_joint(template, "P75", "Pitch", "120", "20"),
			_joint(template, "P76", "Roll", "40"),
			_joint(template, "P77", "Pitch", "90", "30"),
			_joint(template, "MP74", "Yaw", "30"),
		]},
		{"name": "6-joint", "joints": [
			_joint(template, "P74", "Yaw", "0"),
			_joint(template, "P75", "Pitch", "120", "20"),
			_joint(template, "P76", "Roll", "40"),
			_joint(template, "P77", "Pitch", "90", "30"),
			_joint(template, "MP03", "Yaw", "30"),
			_joint(template, "MP74", "Roll", "20"),
		]},
	]
	var failed: bool = false
	for c in cases:
		var case_cfg: Dictionary = cfg.duplicate(true)
		# 六关节 + 一夹爪需要让同侧底盘电机共用扩展口，释放 P64/P66。
		case_cfg["engineer"]["l2_io"] = case_cfg["engineer"]["l1_io"]
		case_cfg["engineer"]["r1_io"] = "P62 P63"
		case_cfg["engineer"]["r2_io"] = "P62 P63"
		case_cfg["engineer"]["io_init"]["P64"] = "舵机"
		case_cfg["engineer"]["io_init"]["P66"] = "舵机"
		case_cfg["engineer"]["io_init"]["P76"] = "舵机"
		case_cfg["engineer"]["key_map"] = []
		case_cfg["ik"]["joints"] = c["joints"]
		case_cfg["ik"]["joint_count"] = c["joints"].size()
		case_cfg["ik"]["keymove"][4] = {"plus": "不使用", "minus": "不使用"}
		if c["name"] in ["5-joint", "6-joint"]:
			case_cfg["ik"]["keymove"][3] = {"plus": "A", "minus": "B"}
			case_cfg["ik"]["keymove"][5] = {"plus": "↑", "minus": "↓"}
		case_cfg["ik"]["gripper"] = {
			"enabled": true, "io": "MP03", "dir": "正向", "open_angle": "45",
			"closed_angle": "-45", "initial_open": true, "key": "D"}
		if c["name"] == "4-joint":
			case_cfg["ik"]["joints"] = [
				_joint(template, "P74", "Yaw", "0"),
				_joint(template, "P75", "Pitch", "120", "20"),
				_joint(template, "P76", "Pitch", "90", "30"),
				_joint(template, "P77", "Pitch", "40"),
			]
			case_cfg["ik"]["joint_count"] = 4
		elif c["name"] == "6-joint":
			case_cfg["ik"]["joints"] = [
				_joint(template, "P64", "Yaw", "0"),
				_joint(template, "P66", "Pitch", "120", "20"),
				_joint(template, "P74", "Roll", "40"),
				_joint(template, "P75", "Pitch", "90", "30"),
				_joint(template, "P76", "Yaw", "30"),
				_joint(template, "P77", "Roll", "20"),
			]
			case_cfg["ik"]["joint_count"] = 6
		var code: String = CG.new().generate(case_cfg)
		var result: Dictionary = TC.new().build_project(TC.PROJECT_ENGINEER_DST, code)
		print(result.get("log", ""))
		if result.get("ok", false):
			print("=== C251 %s: PASS ===" % c["name"])
		else:
			print("=== C251 %s: FAIL ===" % c["name"])
			failed = true
	# 仿真固件必须使用相同运动学核心，但完全不包含执行器输出。
	var sim_cfg: Dictionary = cfg["ik"].duplicate(true)
	sim_cfg["joints"] = cases[1]["joints"]
	sim_cfg["joint_count"] = 4
	var sim_code: String = CG.new().generate_simulator(sim_cfg)
	var sim_result: Dictionary = TC.new().build_project(TC.PROJECT_ENGINEER_SIM_DST, sim_code)
	print(sim_result.get("log", ""))
	if not sim_result.get("ok", false):
		print("=== C251 MCU simulator: FAIL ===")
		failed = true
	else:
		print("=== C251 MCU simulator: PASS ===")
	quit(1 if failed else 0)

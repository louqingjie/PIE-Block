extends SceneTree

func _init():
	var cg = preload("res://scripts/codegen/codegen_engineer.gd").new()
	var cfg = {
		"channel": "36",
		"deadzone": "10",
		"normal_speed": "4000",
		"sprint_speed": "8000",
		"sprint_enabled": false,
		"l1_io": "P74 P24",
		"l2_io": "P75 P25",
		"r1_io": "P76 P26",
		"r2_io": "P77 P27",
		"l1_dir": "正向",
		"l2_dir": "正向",
		"r1_dir": "正向",
		"r2_dir": "正向",
		"io_init": {
			"P60": "舵机",
			"P62": "舵机",
			"P64": "电机",
			"P66": "电机",
			"P74": "电机",
			"P75": "电机",
			"P76": "电机",
			"P77": "电机",
		},
		"key_map": [
			{"input": "右摇杆X", "dir": "正", "mode": "速度", "param": "10000", "target": "P64"},
			{"input": "右摇杆Y", "dir": "正", "mode": "速度", "param": "10000", "target": "P66"},
			{"input": "A", "dir": "正", "mode": "增量", "param": "180", "target": "P60"},
			{"input": "B", "dir": "反", "mode": "增量", "param": "180", "target": "P60"},
			{"input": "C", "dir": "正", "mode": "直接", "param": "90", "target": "P62"},
			{"input": "D", "dir": "正", "mode": "直接", "param": "-90", "target": "P62"},
			{"input": "↑", "dir": "正", "mode": "直接", "param": "5000", "target": "P64"},
			{"input": "↓", "dir": "正", "mode": "直接", "param": "5000", "target": "P66"},
			{"input": "←", "dir": "正", "mode": "增量", "param": "90", "target": "MP03"},
			{"input": "->", "dir": "反", "mode": "增量", "param": "90", "target": "MP03"},
			{"input": "R", "dir": "正", "mode": "直接", "param": "0", "target": "MP74"},
		],
	}
	var code = cg.generate(cfg)
	print(code)
	quit()

extends SceneTree

## 临时脚本：生成各构型 main.c 并核验 ±90° 占空比端点（验证完即删）

func _initialize() -> void:
	var cg = preload("res://scripts/codegen/codegen_engineer_ik.gd").new()
	var io_list: Array = ["P74", "P75", "P76", "MP03"]
	var cases: Array = [
		{"n": "ax2", "t": 0, "jc": 2, "pre": true},
		{"n": "ax3", "t": 1, "jc": 3, "pre": true},
		{"n": "ax4", "t": 2, "jc": 4, "pre": true},
		{"n": "nopreset", "t": 1, "jc": 3, "pre": false},
		{"n": "mainonly", "t": 0, "jc": 2, "pre": true, "io": ["MP74", "MP03"]},
	]
	for c in cases:
		var ios: Array = c.get("io", io_list)
		var joints: Array = []
		for i in range(c["jc"]):
			joints.append({
				"io": ios[i],
				"dir": "反向" if i == 1 else "正向",
				"zero": "30", "min": "-90", "max": "90",
			})
		var presets: Array = []
		if c["pre"]:
			presets.append({"key": "A", "x": "100", "y": "80", "z": "50", "phi": "45", "enabled": true})
			presets.append({"key": "B", "x": "60", "y": "60", "z": "20", "phi": "0", "enabled": true})
		var cfg: Dictionary = {
			"config_type": c["t"], "joint_count": c["jc"],
			"L1": "100", "L2": "80", "L3": "30",
			"joints": joints, "presets": presets,
			"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
			"joy_scale": "5", "keymove_speed": "2",
			"keymove": [
				{"plus": "↑", "minus": "↓"},
				{"plus": "←", "minus": "->"},
				{"plus": "B", "minus": "C"},
				{"plus": "D", "minus": "R"},
			],
		}
		var f = FileAccess.open("res://out_%s.c" % c["n"], FileAccess.WRITE)
		f.store_string(cg.generate(cfg))
		f.close()
		print("wrote out_%s.c" % c["n"])
	# 核验角度 -> 占空比端点（复算生成代码里的公式）
	print("\n--- 占空比端点核验（正向关节）---")
	for a in [-90.0, -45.0, 0.0, 45.0, 90.0]:
		var duty: int = int(750 + a * (500.0 / 180.0))
		print("  %+6.1f° -> duty %d" % [a, duty])
	quit(0)

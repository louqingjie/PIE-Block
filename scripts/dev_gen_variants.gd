extends SceneTree

## 生成 5 种构形的 main.c 到 user://，供 Keil 实编译验证。
##
## 覆盖面按「最容易出编译错误」挑选：
##   2 关节        —— 仍使用统一 XYZ 目标
##   4 关节 Yaw+3Pitch —— φ 可控，走完整的姿态解算路径
##   6 关节含 Roll —— 关节数上限，xdata 用量最大
##   4 关节全 Pitch —— φ 不可控，整条 φ 链路都不该生成
##   无预设点位     —— C89 禁止零长数组，presetKey/presetPos 整块跳过
##
## 运行：godot --headless --path . --script scripts/dev_gen_variants.gd

const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")


func _mk(axes: Array, lens: Array, ios: Array) -> Array:
	var out: Array = []
	for i in range(axes.size()):
		out.append({
			"io": ios[i], "dir": "正向", "zero": "10",
			"min": "-90", "max": "90",
			"axis": axes[i], "len": str(lens[i]),
		})
	return out


func _cfg(joints: Array, presets: Array) -> Dictionary:
	var jc: int = joints.size()
	return {
		"joint_count": jc,
		"joints": joints, "presets": presets,
		"joy_x": "右X->末端X", "joy_y": "右Y->末端Y", "joy_z": "右X->末端Z",
		"joy_scale": "5", "keymove_speed": "2",
		"keymove": [
			{"plus": "上", "minus": "下"},
			{"plus": "左", "minus": "右"},
			{"plus": "A", "minus": "B"},
			{"plus": "C", "minus": "D"},
		],
	}


func _initialize() -> void:
	var io6: Array = ["P74", "P75", "P76", "P77", "P60", "P62"]
	var presets: Array = [ {
		"enabled": true, "key": "A",
		"x": "150", "y": "30", "z": "60", "roll": "0", "pitch": "-30", "yaw": "0",
	}]
	var cases: Array = [
		{"name": "v1_2joint",
			"cfg": _cfg(_mk(["Yaw", "Pitch"], [0, 150], ["P74", "P75"]), presets)},
		{"name": "v2_4joint_yaw3pitch",
			"cfg": _cfg(_mk(["Yaw", "Pitch", "Pitch", "Pitch"],
				[0, 120, 90, 40], io6.slice(0, 4)), presets)},
		{"name": "v3_6joint_roll",
			"cfg": _cfg(_mk(["Yaw", "Pitch", "Pitch", "Roll", "Pitch", "Roll"],
				[0, 120, 90, 0, 40, 25], io6), presets)},
		{"name": "v4_4joint_allpitch",
			"cfg": _cfg(_mk(["Pitch", "Pitch", "Pitch", "Pitch"],
				[100, 80, 60, 40], io6.slice(0, 4)), presets)},
		{"name": "v5_no_preset",
			"cfg": _cfg(_mk(["Yaw", "Pitch", "Pitch", "Pitch"],
				[0, 120, 90, 40], io6.slice(0, 4)), [])},
	]
	var dir: String = "user://variants"
	DirAccess.make_dir_recursive_absolute(dir)
	var diag = load("res://scripts/arm_diagnosis.gd").new()
	for c in cases:
		var cfg: Dictionary = c["cfg"]
		var jc: int = cfg["joint_count"]
		var cg = CG.new()
		var code: String = cg.generate(cfg)
		var d: Dictionary = diag.analyze(cfg["joints"], jc)
		var path: String = "%s/%s.c" % [dir, c["name"]]
		var f = FileAccess.open(path, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		var mask: Dictionary = d.get("orientation_mask", {})
		print("%s : jc=%d orientation=%s targetPitch=%s ORIENTATION_WEIGHT=%s -> %s"
			% [c["name"], jc, str(mask),
				str(code.contains("targetPitch")),
				str(code.contains("#define ORIENTATION_WEIGHT")),
				ProjectSettings.globalize_path(path)])
	print("DONE ", ProjectSettings.globalize_path(dir))
	quit(0)

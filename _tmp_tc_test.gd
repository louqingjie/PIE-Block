extends SceneTree

## 临时验证：Toolchain 重构后部署/探测/编译行为是否一致

const TC = preload("res://scripts/toolchain.gd")

func _initialize() -> void:
	var tc = TC.new(func(l): print("  [log] ", l))
	print("=== Toolchain 重构验证 ===")
	print("ensure_deployed: ", tc.ensure_deployed())
	print("find_uv4: ", tc.find_uv4())
	print("generate_tools_ini: ", tc.generate_tools_ini())
	var cg = preload("res://scripts/codegen/codegen_infantry.gd").new()
	var cfg := {
		"channel": "36", "deadzone": "10",
		"normal_speed": "4000", "sprint_speed": "8000", "sprint_enabled": true,
		"l1_io": "P74 P24", "l2_io": "P75 P25",
		"r1_io": "P76 P26", "r2_io": "P77 P27",
		"l1_dir": "正向", "l2_dir": "正向", "r1_dir": "正向", "r2_dir": "正向",
		"booster_io": "P60 P20", "booster_dir": "正向",
		"friction_l_dir": "正向", "friction_r_dir": "正向",
		"yaw_drive": "舵机", "yaw_io": "P62", "yaw_dir": "正向",
		"pitch_drive": "舵机", "pitch_io": "MP74", "pitch_dir": "正向",
		"yaw_mid_offset": "0", "pitch_mid_offset": "0",
		"trigger_key": "A", "trigger_speed": "10000", "trigger_time": "500",
		"booster_key": "D", "zero_enabled": true, "arrow_key": "移动",
	}
	var code: String = cg.generate(cfg)
	var r = tc.build_project(TC.PROJECT_DST, code)
	print("build ok=", r["ok"], " exit=", r["exit"])
	for line in str(r["log"]).split("\n", false):
		if "Error(s)" in line or "warning" in line:
			print("  ", line.strip_edges())
	print("read_main_c 长度: ", tc.read_main_c(TC.PROJECT_DST).length())
	print("mtime > 0: ", tc.main_c_mtime(TC.PROJECT_DST) > 0)
	quit(0 if r["ok"] else 1)

extends SceneTree

## 检查固件上编译进去的机械臂参数（Phase 2/6 验收核对）。
##
## 运行：godot --headless --path . --script scripts/dev_inspect_solver.gd -- --proj=工程项目.pieproj
##
## 打印：工程 ik_config 的逐关节参数（axis/len/zero/min/max/offset/io）、
## 求解器指纹、以及固件代码里实际生成的 jointOffset/jointHome/jointMin/
## jointMax/jointDir/jointAxis/jointLen 数组。用于核对固件参数是否与真实
## 机械臂一致。

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", "工程项目.pieproj"))
	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("无法读取工程文件: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var data: Dictionary = loaded["data"] as Dictionary
	var ik: Dictionary = IK_CONFIG.normalize(data.get("ik_config", {}))
	var cg = CG.new()

	print("=== 工程 ik_config 逐关节参数 ===")
	var jc: int = clampi(int(ik.get("joint_count", 2)), 2, 6)
	print("joint_count: %d" % jc)
	var joints: Array = ik.get("joints", [])
	for i in range(jc):
		var j: Dictionary = joints[i] if i < joints.size() else {}
		print("  J%d: axis=%-6s len=%-8s zero=%-6s min=%-6s max=%-6s offset=%-6s io=%s" % [
			i + 1, str(j.get("axis", "")), str(j.get("len", "")),
			str(j.get("zero", "")), str(j.get("min", "")), str(j.get("max", "")),
			str(j.get("offset", "")), str(j.get("io", ""))])
	var preset_count: int = 0
	for preset in ik.get("presets", []):
		if preset.get("enabled", false):
			preset_count += 1
	var gripper: Dictionary = ik.get("gripper", {})
	print("presets enabled: %d   gripper enabled: %s (io=%s)" % [
		preset_count, str(bool(gripper.get("enabled", false))), str(gripper.get("io", ""))])
	print("solver fingerprint: %s" % cg.solver_fingerprint(ik))

	var code: String = cg.generate_simulator(ik)
	print()
	print("=== 固件代码中的参数数组 ===")
	for name in ["jointOffset", "jointHome", "jointMin", "jointMax", "jointDir", "jointAxis", "jointLen"]:
		_print_const(code, name)
	quit(0)


func _print_const(code: String, name: String) -> void:
	var start: int = code.find("const float %s" % name)
	if start < 0:
		start = code.find("const uint8_t %s" % name)
	if start < 0:
		print("[%s] (not found)" % name)
		return
	var brace: int = code.find("{", start)
	if brace < 0:
		print("[%s] (no brace)" % name)
		return
	var end: int = code.find("};", brace)
	if end < 0:
		print("[%s] (no end)" % name)
		return
	print(code.substr(start, end + 2 - start).strip_edges())


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result

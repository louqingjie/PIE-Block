extends SceneTree

## 实验：把 FK 辅助函数（mat_vec/axis_rot/mat_mul）数组参数显式声明 xdata，
## 验证"xdata 数组作为无存储类参数导致指针空间不匹配"假设。
##
## 运行：godot --headless --path . --script scripts/dev_test_xptr.gd -- --proj=工程项目.pieproj --port=COM3

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", "工程项目.pieproj"))
	var port: String = str(options.get("port", "COM3"))
	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("读取工程失败: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	var code: String = CG.new().generate_simulator(ik)

	var patches := {
		"void mat_vec(float m[3][3], float v[3], float out[3])":
			"void mat_vec(float xdata m[3][3], float xdata v[3], float xdata out[3])",
		"void axis_rot(float a[3], float ang, float m[3][3])":
			"void axis_rot(float xdata a[3], float ang, float xdata m[3][3])",
		"void mat_mul(float x[3][3], float y[3][3], float out[3][3])":
			"void mat_mul(float xdata x[3][3], float xdata y[3][3], float xdata out[3][3])",
	}
	for key in patches:
		if code.contains(key):
			code = code.replace(key, patches[key])
			print("patched: %s" % key)
		else:
			push_error("未找到: %s" % key)
			quit(2)
			return

	var tc = TC.new()
	if not tc.ensure_deployed():
		quit(2)
		return
	if not tc.write_main_c(TC.PROJECT_ENGINEER_SIM_DST, code):
		quit(2)
		return
	var uv4: String = tc.find_uv4()
	if uv4.is_empty():
		push_error("未找到 Keil")
		quit(2)
		return
	var build: Dictionary = tc.build_sync(uv4, TC.PROJECT_ENGINEER_SIM_DST)
	print("BUILD ok=%s" % str(build.get("ok", false)))
	if not bool(build.get("ok", false)):
		print(str(build.get("log", "")))
		quit(2)
		return
	var hex_path: String = tc.get_hex_path(TC.PROJECT_ENGINEER_SIM_DST)
	var flash: Dictionary = tc.download_hex_iap(hex_path, port)
	print("FLASH ok=%s stage=%s" % [str(flash.get("ok", false)), str(flash.get("stage", ""))])
	print(str(flash.get("log", "")))
	quit(0 if bool(flash.get("ok", false)) else 1)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result

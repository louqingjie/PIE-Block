extends SceneTree

## 实验：把仿真固件 const 数组强制改为 `code` 存储类，验证 HCONST 访问假设。
##
## 运行：godot --headless --path . --script scripts/dev_test_hconst.gd -- --proj=工程项目.pieproj --port=COM3
##
## 背景：MemoryModel=3 下 const float 数组进 HCONST(0xFE9xxx, 24 位地址)，
## 怀疑 FK 以截断指针访问导致 jointLen/jointAxis 读 0，FK 末端恒为原点。
## 这里把 jointAxis/jointLen/jointHome/jointMin/jointMax/jointOffset/jointDir
## 改为 `code` 存储类（16 位可寻址 CODE 段），重编译烧录后 dump 验证。

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
		"const float jointAxis[": "float code jointAxis[",
		"const float jointLen[": "float code jointLen[",
		"const float jointHome[": "float code jointHome[",
		"const float jointMin[": "float code jointMin[",
		"const float jointMax[": "float code jointMax[",
		"const float jointOffset[": "float code jointOffset[",
		"const uint8_t jointDir[": "uint8_t code jointDir[",
	}
	for key in patches:
		if code.contains(key):
			code = code.replace(key, patches[key])
			print("patched: %s -> %s" % [key, patches[key]])
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

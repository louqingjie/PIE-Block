extends SceneTree

## 实验：在 ik_fk 末尾硬编码 ikPts 末端 = (123,456,789)，验证：
##   - 若 PING 返回该值：ik_fk 执行 + xdata 写读 OK，问题在 FK 浮点运算
##   - 若 PING 仍返回 (0,0,0)：ik_fk 未执行或 xdata 访问异常
##
## 运行：godot --headless --path . --script scripts/dev_test_inject.gd -- --proj=工程项目.pieproj --port=COM3

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

	var anchor := "        ikPts[k + 1][2] = ikPts[k][2] + ikWv[2];\n    }\n}"
	var inject := "        ikPts[k + 1][2] = ikPts[k][2] + ikWv[2];\n    }\n    ikPts[JOINT_COUNT][0]=123.0f;ikPts[JOINT_COUNT][1]=456.0f;ikPts[JOINT_COUNT][2]=789.0f;\n}"
	if not code.contains(anchor):
		push_error("未找到 ik_fk 注入锚点")
		quit(2)
		return
	code = code.replace(anchor, inject)
	print("injected hardcoded ikPts tip")

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
	tc.generate_tools_ini()
	# 关键：必须用 -r（rebuild）强制重编译。build_sync 的 -b 会跳过 main.c
	# 变更（memory 踩过：-b 下不同变体报一模一样 Program Size）。
	var mdk_abs: String = ProjectSettings.globalize_path(
		"user://stc32g/Projects/ROBOMASTER_ENGINEER_SIM").path_join("MDK").replace("/", "\\")
	var uvproj_abs: String = mdk_abs + "\\Project_Template.uvproj"
	var log_abs: String = mdk_abs + "\\build_rebuild.log"
	var uv4_win: String = uv4.replace("/", "\\")
	var output: Array = []
	var exit_code: int = OS.execute(uv4_win, ["-r", uvproj_abs, "-o", log_abs], output, true)
	var log_text: String = ""
	if FileAccess.file_exists(log_abs):
		log_text = FileAccess.get_file_as_string(log_abs)
	var build: Dictionary = {
		"ok": log_text.find("0 Error(s)") >= 0,
		"log": log_text,
		"exit": exit_code,
	}
	print("BUILD(rebuild) ok=%s exit=%d" % [str(build.get("ok", false)), exit_code])
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

extends SceneTree

## 实验：在 IkSimState 的 payload 层把 position 硬编码为 (123,456,789)（不经
## xdata 的 ikPts 读取），区分：
##   - 若 PING 返回 (123,456,789)：协议链路 + 浮点 PutFloat OK，问题在 xdata
##   - 若 PING 仍返回 (0,0,0)：协议链路或浮点填充本身有问题
##
## 运行：godot --headless --path . --script scripts/dev_test_payload.gd -- --proj=工程项目.pieproj --port=COM3

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", "工程项目.pieproj"))
	var port: String = str(options.get("port", "COM3"))

	# 恢复 uvproj（若被 dev_test_xram 改过）
	var uvproj: String = ProjectSettings.globalize_path(
		"user://stc32g/Projects/ROBOMASTER_ENGINEER_SIM/MDK/Project_Template.uvproj")
	var bak: String = uvproj + ".bak"
	if FileAccess.file_exists(bak):
		var restored: String = FileAccess.get_file_as_string(bak)
		if not restored.is_empty():
			var wf := FileAccess.open(uvproj, FileAccess.WRITE)
			if wf != null:
				wf.store_string(restored)
				wf.close()
				print("uvproj 已从 .bak 恢复")

	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("读取工程失败: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	var code: String = CG.new().generate_simulator(ik)

	# payload 层硬编码 position（不经 xdata ikPts 读取）
	var injected := 0
	var vals: Array = ["123.0f", "456.0f", "789.0f"]
	for suffix in ["0", "1", "2"]:
		var key := "IkSimPutFloat(ikSimPayload,&n,ikPts[JOINT_COUNT][%s]);" % suffix
		var val: String = vals[suffix.to_int()]
		if code.contains(key):
			code = code.replace(key, "IkSimPutFloat(ikSimPayload,&n,%s);" % val)
			injected += 1
	print("payload position 硬编码注入 %d 处" % injected)
	if injected != 3:
		push_error("注入数量不对")
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
	tc.generate_tools_ini()
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
	print("BUILD(rebuild) ok=%s exit=%d" % [str(log_text.find("0 Error(s)") >= 0), exit_code])
	if log_text.find("0 Error(s)") < 0:
		print(log_text)
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

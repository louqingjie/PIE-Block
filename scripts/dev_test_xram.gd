extends SceneTree

## 实验：把 SIM 工程 uvproj 的 XRAM 段从 0x10000-0x11FFF（17 位）改为
## 0x0000-0x1FFF（16 位），验证"C251 large 模型 xdata 16 位寻址与 17 位
## XRAM 段配置错位导致 xdata 写读失败"假设。
##
## 运行：godot --headless --path . --script scripts/dev_test_xram.gd -- --proj=工程项目.pieproj --port=COM3
##
## 步骤：备份 uvproj -> 改 XRAM -> 生成仿真固件(原始) -> 写 main.c
##       -> -r 重编译 -> 烧录。之后用 dev_dump_state.gd 验证 FK。

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", "工程项目.pieproj"))
	var port: String = str(options.get("port", "COM3"))

	var uvproj: String = ProjectSettings.globalize_path(
		"user://stc32g/Projects/ROBOMASTER_ENGINEER_SIM/MDK/Project_Template.uvproj")
	var original: String = FileAccess.get_file_as_string(uvproj)
	if original.is_empty():
		push_error("无法读 uvproj")
		quit(2)
		return
	var bak: String = uvproj + ".bak"
	var bf := FileAccess.open(bak, FileAccess.WRITE)
	if bf != null:
		bf.store_string(original)
		bf.close()
		print("uvproj 已备份到 .bak")
	var patched: String = original.replace("XRAM(0x10000-0x11FFF)", "XRAM(0x0000-0x1FFF)")
	if patched == original:
		push_error("uvproj 未匹配 XRAM(0x10000-0x11FFF)")
		quit(2)
		return
	var wf := FileAccess.open(uvproj, FileAccess.WRITE)
	if wf == null:
		push_error("无法写 uvproj")
		quit(2)
		return
	wf.store_string(patched)
	wf.close()
	print("uvproj XRAM -> 0x0000-0x1FFF")

	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("读取工程失败: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	var code: String = CG.new().generate_simulator(ik)
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

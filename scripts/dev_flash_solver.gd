extends SceneTree

## 编译并烧录 MCU 求解器（仿真固件）到主控板（Phase 2 验收项）。
##
## 运行：godot --headless --path . --script scripts/dev_flash_solver.gd -- --proj=<xxx.pieproj> --port=COM3
##
## 流程（复用产品同一套代码路径，与 GUI「编译并烧录 MCU 求解器」一致）：
##   读工程 ik_config -> 生成仿真固件代码 -> 写 main.c -> Keil 编译 -> IAP 烧录
## 判据：BUILD ok=true 且 FLASH ok=true（stage=done）。

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", ""))
	var port: String = str(options.get("port", ""))
	if proj.is_empty() or port.is_empty():
		push_error("missing --proj=<xxx.pieproj> and --port=COMx")
		quit(2)
		return

	# 1. 读工程配置
	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("无法读取工程文件: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var ik: Dictionary = IK_CONFIG.normalize((loaded["data"] as Dictionary).get("ik_config", {}))
	print("工程: %s  关节数: %d" % [proj, int(ik.get("joint_count", 0))])

	# 2. 生成仿真固件（无执行器 IO）
	var code: String = CG.new().generate_simulator(ik)
	if code.is_empty():
		push_error("生成 MCU 求解器固件失败")
		quit(2)
		return
	print("仿真固件生成: %d 字节" % code.length())

	# 3. 写 main.c 并编译
	var tc = TC.new()
	if not tc.ensure_deployed():
		push_error("工具链部署失败")
		quit(2)
		return
	if not tc.write_main_c(TC.PROJECT_ENGINEER_SIM_DST, code):
		push_error("写 main.c 失败")
		quit(2)
		return
	var uv4: String = tc.find_uv4()
	if uv4.is_empty():
		push_error("未找到 Keil 编译器")
		quit(2)
		return
	if not tc.generate_tools_ini():
		push_error("TOOLS.INI 生成失败，编译可能报错")
	var build: Dictionary = tc.build_sync(uv4, TC.PROJECT_ENGINEER_SIM_DST)
	print("BUILD ok=%s" % str(build.get("ok", false)))
	if not bool(build.get("ok", false)):
		push_error("编译失败")
		print(str(build.get("log", "")))
		quit(2)
		return

	# 4. 烧录（IAP，走 bootloader，230400）
	var hex_path: String = tc.get_hex_path(TC.PROJECT_ENGINEER_SIM_DST)
	if not tc.hex_exists(TC.PROJECT_ENGINEER_SIM_DST):
		push_error("编译产物 hex 不存在: %s" % hex_path)
		quit(2)
		return
	var flash: Dictionary = tc.download_hex_iap(hex_path, port)
	print("FLASH ok=%s stage=%s" % [str(flash.get("ok", false)), str(flash.get("stage", ""))])
	print("--- flash log ---")
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

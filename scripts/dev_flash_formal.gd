extends SceneTree

## 编译并烧录正式工程固件到主控板（Phase 3 验收项，CLI 封装）。
##
## 运行：godot --headless --path . --script scripts/dev_flash_formal.gd -- --proj=<xxx.pieproj> --port=COM3
##
## 从 .pieproj 完整复刻 GUI 的 _collect_engineer_config（io_init + key_map，
## config key 相对 EditZone；FirstRow 的 channel/deadzone/chassis 不在序列化
## 范围，走生成器默认值），再 generate() 正式固件 -> Keil 编译 -> IAP 烧录。
## 烧录成功后自动把 workflow.firmware_mode 置 production 并写 flashed_hash，
## 工程文件「仿真固件」警告随之清除。
## 判据：BUILD ok=true 且 FLASH ok=true 且 WORKFLOW save=true。

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CG = preload("res://scripts/codegen/codegen_engineer_ik.gd")
const TC = preload("res://scripts/toolchain.gd")

# 与 ui.gd 保持一致（config key 相对 EditZone）
const ENGINEER: String = "SecondRow/TabContainer/Engineer"
const ENG_IO_PATHS: Dictionary = {
	"P60": ENGINEER + "/P60P62/OptionButton",
	"P62": ENGINEER + "/P60P62/OptionButton2",
	"P64": ENGINEER + "/P64P66/OptionButton",
	"P66": ENGINEER + "/P64P66/OptionButton2",
	"P74": ENGINEER + "/P74P75/OptionButton",
	"P75": ENGINEER + "/P74P75/OptionButton2",
	"P76": ENGINEER + "/P76P77/OptionButton2",
	"P77": ENGINEER + "/P76P77/OptionButton",
}
const ENG_KEY_ROWS: Array = [
	"RightJoystickX", "RightJoystickY", "A", "B", "C", "D",
	"Up", "Down", "Left", "Right", "R",
]
const ENG_KEY_LABELS: Array = [
	"右摇杆X", "右摇杆Y", "A", "B", "C", "D", "↑", "↓", "←", "->", "R",
]


func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var proj: String = str(options.get("proj", ""))
	var port: String = str(options.get("port", ""))
	if proj.is_empty() or port.is_empty():
		push_error("missing --proj=<xxx.pieproj> and --port=COMx")
		quit(2)
		return

	var loaded: Dictionary = PF.load_from(proj)
	if not bool(loaded.get("ok", false)):
		push_error("无法读取工程文件: %s" % str(loaded.get("err", proj)))
		quit(2)
		return
	var data: Dictionary = loaded["data"] as Dictionary
	var engineer_cfg: Dictionary = _collect_engineer_config(data.get("config", {}))
	var ik: Dictionary = IK_CONFIG.normalize(data.get("ik_config", {}))
	print("工程: %s  关节数: %d  key_map 行: %d  io_init: %s" % [
		proj, int(ik.get("joint_count", 0)), engineer_cfg["key_map"].size(),
		str(engineer_cfg["io_init"])])

	var code: String = CG.new().generate({"engineer": engineer_cfg, "ik": ik})
	if code.is_empty():
		push_error("生成正式固件失败")
		quit(2)
		return
	var code_hash: String = code.sha256_text()
	print("正式固件生成: %d 字节  hash=%s" % [code.length(), code_hash])

	var tc = TC.new()
	if not tc.ensure_deployed():
		push_error("工具链部署失败")
		quit(2)
		return
	if not tc.write_main_c(TC.PROJECT_ENGINEER_DST, code):
		push_error("写 main.c 失败")
		quit(2)
		return
	var uv4: String = tc.find_uv4()
	if uv4.is_empty():
		push_error("未找到 Keil 编译器")
		quit(2)
		return
	var build: Dictionary = tc.build_sync(uv4, TC.PROJECT_ENGINEER_DST)
	print("BUILD ok=%s" % str(build.get("ok", false)))
	if not bool(build.get("ok", false)):
		push_error("编译失败")
		print(str(build.get("log", "")))
		quit(2)
		return

	var hex_path: String = tc.get_hex_path(TC.PROJECT_ENGINEER_DST)
	if not tc.hex_exists(TC.PROJECT_ENGINEER_DST):
		push_error("编译产物 hex 不存在: %s" % hex_path)
		quit(2)
		return
	var flash: Dictionary = tc.download_hex_iap(hex_path, port)
	print("FLASH ok=%s stage=%s" % [str(flash.get("ok", false)), str(flash.get("stage", ""))])
	print("--- flash log ---")
	print(str(flash.get("log", "")))
	if not bool(flash.get("ok", false)):
		quit(1)
		return

	var workflow: Dictionary = data.get("workflow", {})
	workflow["flashed_hash"] = code_hash
	workflow["firmware_mode"] = "production"
	workflow["hardware_tested"] = false
	data["workflow"] = workflow
	var save: Dictionary = PF.save_to(proj, data)
	print("WORKFLOW firmware_mode=production flashed_hash=%s save=%s" % [
		code_hash, str(save.get("ok", false))])
	if not bool(save.get("ok", false)):
		push_error("保存工程文件失败: %s" % str(save.get("err", "")))
		quit(1)
		return
	print("=== Phase 3 完成：正式固件已烧录，仿真固件警告已清除（firmware_mode=production）===")
	quit(0)


## 从工程 config（key 相对 EditZone）复刻 GUI _collect_engineer_config 的
## io_init 与 key_map 部分。FirstRow（channel/deadzone/chassis/speed）不在
## 序列化范围，此处不设，generate 走默认值。
func _collect_engineer_config(config: Dictionary) -> Dictionary:
	var cfg: Dictionary = {}
	var io_init: Dictionary = {}
	for pin in ENG_IO_PATHS:
		var item: Dictionary = config.get(ENG_IO_PATHS[pin], {})
		io_init[pin] = str(item.get("s", "舵机"))
	cfg["io_init"] = io_init
	var key_map: Array = []
	for i in range(ENG_KEY_ROWS.size()):
		var base: String = ENGINEER + "/" + ENG_KEY_ROWS[i]
		var dir_item: Dictionary = config.get(base + "/OptionButton2", {})
		var mode_item: Dictionary = config.get(base + "/OptionButton", {})
		var param_item: Dictionary = config.get(base + "/LineEdit", {})
		var target_item: Dictionary = config.get(base + "/OptionButton3", {})
		var target: String = str(target_item.get("s", "不使用"))
		if target == "不使用":
			target = ""
		key_map.append({
			"input": ENG_KEY_LABELS[i],
			"dir": str(dir_item.get("s", "正")),
			"mode": str(mode_item.get("s", "增量")),
			"param": str(param_item.get("t", "")),
			"target": target,
		})
	cfg["key_map"] = key_map
	return cfg


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result

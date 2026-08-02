extends SceneTree

## 探测主控板上的 bootloader 版本（Phase 1 验收项）。
##
## 运行：godot --headless --path . --script scripts/dev_probe_bootloader.gd -- --port=COM3
## 可指定波特率组合：--app-baud=230400 --boot-baud=115200
##
## 用产品同一套 probe_bootloader 逻辑：
##   - 新版（230400）：PROBE_OK，返回版本号
##   - 旧版（115200）：在 230400 下 connect 失败，返回 ok=false
## 副作用：探测成功后芯片停在 bootloader 下载模式，需随后烧录固件恢复运行。

func _initialize() -> void:
	var options := _parse_options(OS.get_cmdline_user_args())
	var port: String = str(options.get("port", ""))
	if port.is_empty():
		push_error("missing --port=COMx")
		quit(2)
		return
	var tc = load("res://scripts/toolchain.gd").new()
	var app_baud: int = int(options.get("app-baud", 230400))
	var boot_baud: int = int(options.get("boot-baud", 230400))
	var result: Dictionary = tc.probe_bootloader(port, app_baud, boot_baud)
	print("PROBE_RESULT ok=%s version=0x%04X" % [str(result.get("ok", false)), int(result.get("version", 0))])
	print("--- bootloader probe log (app=%d boot=%d) ---" % [app_baud, boot_baud])
	print(str(result.get("log", "")))
	quit(0 if bool(result.get("ok", false)) else 1)


func _parse_options(args: PackedStringArray) -> Dictionary:
	var result: Dictionary = {}
	for arg in args:
		if not arg.begins_with("--") or not arg.contains("="):
			continue
		var pair: PackedStringArray = arg.substr(2).split("=", true, 1)
		result[pair[0]] = pair[1]
	return result

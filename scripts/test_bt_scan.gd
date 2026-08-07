extends SceneTree

## 无头测试：跑一次真实 btctl --scan 并校验 JSON 结构。
##
## 需要先构建：powershell -ExecutionPolicy Bypass -File tools/btctl/build.ps1
## 运行：godot --headless --path . --script scripts/test_bt_scan.gd [-- --full]
## 默认用 --multiplier 2（≈2.5s）加速；加 -- --full 用 8（≈10s，生产参数）。


func _initialize() -> void:
	var bt = load("res://scripts/bt_scan.gd")
	var exe: String = bt.find_exe()
	if exe.is_empty():
		print("FAIL: 未找到 btctl.exe，请先运行 tools/btctl/build.ps1")
		quit(1)
		return

	var multiplier := 2
	var args := OS.get_cmdline_user_args()
	if args.has("--full"):
		multiplier = 8
	print("== btctl --scan (multiplier=%d) ==" % multiplier)
	print("   exe: %s" % exe)

	var r: Dictionary = bt.run_scan(multiplier)
	print(JSON.stringify(r, "\t"))

	if not r.get("ok", false):
		print("FAIL: btctl 退出异常 -> %s" % str(r.get("error", r)))
		quit(1)
		return

	var data: Dictionary = r.get("data", {})
	if not data.get("ok", false):
		print("FAIL: btctl 返回 ok=false -> %s" % str(data))
		quit(1)
		return

	var scan: Dictionary = data.get("scan", {})
	if not scan.has("radio_ready") or not scan.has("radios") \
			or not scan.has("discoverable") or not scan.has("paired"):
		print("FAIL: scan 结构缺字段 -> %s" % str(scan))
		quit(1)
		return

	var radios: Array = scan.get("radios", [])
	print("   适配器: %d 个，radio_ready=%s" % [radios.size(), str(scan.get("radio_ready"))])
	for rd in radios:
		print("     · %s (%s)" % [str(rd.get("Name", "")), str(rd.get("State", ""))])
	var disc: Array = scan.get("discoverable", [])
	var paired: Array = scan.get("paired", [])
	print("   可发现: %d 个，已配对: %d 个" % [disc.size(), paired.size()])
	for d in disc:
		print("     · %s  %s  已配对=%s 已连接=%s" % [
			str(d.get("Name", "")), str(d.get("Address", "")),
			str(d.get("Paired", false)), str(d.get("Connected", false))])

	if not scan.get("radio_ready", false):
		print("WARN: 没有处于开启状态的蓝牙适配器（设备查询仍可能拿到缓存结果）")

	print("PASS")
	quit(0)

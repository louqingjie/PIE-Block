extends SceneTree

## 无头测试：蓝牙配对引导的纯逻辑 + btctl --pair/--scan 管道。
## 不需要真机蓝牙：配对用非法 MAC 走错误分支（不弹窗）；扫描用 multiplier 1 快速跑。
##
## 运行：godot --headless --path . --script scripts/test_bt_pair.gd
## 前置：先跑 tools/btctl/build.ps1

const BT = preload("res://scripts/bt_scan.gd")


func _initialize() -> void:
	var fails: Array = []

	# 1) bt_pair.gd 的 _merge_devices：去重合并 discoverable + paired
	var panel = (load("res://scripts/bt_pair.gd")).new()
	var scan := {
		"discoverable": [
			{"Name": "HC-06", "Address": "AA:BB:CC:DD:EE:01", "Paired": false},
			{"Name": "HC-06", "Address": "AA:BB:CC:DD:EE:01", "Paired": false},
			{"Name": "", "Address": "", "Paired": false},
		],
		"paired": [
			{"Name": "MyPhone", "Address": "AA:BB:CC:DD:EE:02", "Paired": true},
		],
	}
	var merged: Array = panel._merge_devices(scan)
	if merged.size() != 2:
		fails.append("_merge_devices 期望 2 个去重设备，得到 %d" % merged.size())
	var seen_addr: Array = []
	for d in merged:
		var a: String = str(d.get("Address", ""))
		if seen_addr.has(a):
			fails.append("_merge_devices 出现重复地址: %s" % a)
		seen_addr.append(a)

	# 2) ui.gd 的 _is_bt_connection_failure 分类
	var ui = (load("res://scripts/ui.gd")).new()
	var cases := {
		"port": true, "connect": true, "env": true, "": true,
		"erase": false, "program": false, "verify": false, "hex": false,
		"bootloader_upgrade": false, "timeout": false,
	}
	for stage in cases:
		var got: bool = ui._is_bt_connection_failure({"stage": stage})
		if got != cases[stage]:
			fails.append("连接分类 stage='%s' 期望 %s 得到 %s" % [stage, cases[stage], got])

	# 3) btctl --pair 非法 MAC：应返回 ok=false + 「无效 MAC」，不弹窗不崩
	var r: Dictionary = BT.run_pair("ZZ:ZZ:00:00:00:00", "1234", false, true)
	if r.get("ok", false):
		fails.append("非法 MAC 不应配对成功")
	elif not str(r.get("error", "")).contains("无效 MAC"):
		fails.append("非法 MAC 错误文案异常: %s" % str(r.get("error")))

	# 4) btctl --scan 快速跑（multiplier 1）验证管道与 JSON 结构
	var s: Dictionary = BT.run_scan(1)
	if not s.get("ok", false):
		fails.append("run_scan 失败: %s" % str(s.get("error", s)))
	else:
		var data: Dictionary = s.get("data", {})
		if not data.get("ok", false) or not data.get("scan", {}).has("radio_ready"):
			fails.append("run_scan 结构异常: %s" % str(data))

	# 5) bt_pair.tscn 可实例化（add_child 触发 _ready，验证 @onready 节点路径）
	var packed: PackedScene = load("res://scenes/bt_pair.tscn")
	if packed == null:
		fails.append("无法加载 bt_pair.tscn")
	else:
		var inst: Node = packed.instantiate()
		root.add_child(inst)
		if inst.get_node_or_null("Dim/Center/Panel/Content/Status") == null:
			fails.append("bt_pair.tscn 缺 Status 节点（路径与脚本不匹配）")
		if inst.get_node_or_null("Dim/Center/Panel/Content/Buttons/RetryBtn") == null:
			fails.append("bt_pair.tscn 缺 RetryBtn 节点（路径与脚本不匹配）")
		inst.free()

	# 释放测试用裸实例，避免 headless 退出时 RID/资源泄漏告警。
	panel.free()
	ui.free()

	if fails.is_empty():
		print("PASS")
		quit(0)
	else:
		for f in fails:
			print("FAIL: " + f)
		quit(1)

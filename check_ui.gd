extends SceneTree

## 临时脚本：验证 IK 静态检查在 ±90° 约定下的表现（验证完即删）

func _initialize() -> void:
	var scene: PackedScene = load("res://scenes/ui.tscn")
	var r = scene.instantiate()
	get_root().add_child(r)
	var ik: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/EngineerAdvanced"
	r.get_node("VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer").current_tab = 2
	r.get_node(ik + "/LinkLength/L1").text = "100"
	r.get_node(ik + "/LinkLength/L2").text = "80"
	for i in range(4):
		var row: String = ik + "/Joint%d" % (i + 1)
		r.get_node(row + "/Zero").text = "30"
		r.get_node(row + "/Min").text = "-90"
		r.get_node(row + "/Max").text = "90"
	_dump(r, "合法 ±90 限位（应无限位告警）")
	# 超出 ±90 应告警
	r.get_node(ik + "/Joint1/Max").text = "180"
	_dump(r, "关节1 max=180（应告警超出行程）")
	r.get_node(ik + "/Joint1/Max").text = "90"
	# 初始角超出限位应报错
	r.get_node(ik + "/Joint2/Zero").text = "120"
	_dump(r, "关节2 初始角 120（应报超出限位）")
	quit(0)


func _dump(r, label: String) -> void:
	var issues: Array = []
	r._check_ik_params(issues)
	print("\n=== %s ===" % label)
	for it in issues:
		print("  [%s] %s" % [it["type"], it["msg"]])
	if issues.is_empty():
		print("  (无问题)")

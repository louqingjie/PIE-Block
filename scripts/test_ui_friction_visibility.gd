extends SceneTree

## 步兵「摩擦轮类型」切换时，摩擦轮开关行的可见性回归测试。
## 运行方式：godot --headless --path . --script scripts/test_ui_friction_visibility.gd

var _fail: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	var packed: PackedScene = load("res://scenes/ui.tscn") as PackedScene
	_check("ui.tscn 可加载", packed != null)
	if packed == null:
		quit(1)
		return
	var ui: Node = packed.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	var friction_type: Node = ui.get_node_or_null(ui.P_FRICTION_TYPE)
	var switch_row: Node = ui.get_node_or_null(ui.P_FRICTION_SWITCH_ROW)
	_check("摩擦轮类型下拉存在", friction_type is OptionButton)
	_check("摩擦轮开关行存在", switch_row is CanvasItem)
	if friction_type is OptionButton and switch_row is CanvasItem:
		var unused_index: int = -1
		for i in range(friction_type.item_count):
			if friction_type.get_item_text(i) == "不使用":
				unused_index = i
				break
		_check("摩擦轮类型提供不使用选项", unused_index >= 0)
		if unused_index >= 0:
			friction_type.select(unused_index)
			friction_type.item_selected.emit(unused_index)
			await process_frame
			_check("不使用时隐藏摩擦轮开关行", not switch_row.visible)
			var unused_config: Dictionary = ui._snapshot_config()
			friction_type.select(0)
			friction_type.item_selected.emit(0)
			await process_frame
			_check("重新启用时显示摩擦轮开关行", switch_row.visible)
			ui._apply_config(unused_config)
			await process_frame
			_check("回填不使用配置后保持隐藏", not switch_row.visible)
	root.remove_child(ui)
	ui.free()
	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

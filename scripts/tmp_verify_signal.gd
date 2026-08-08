extends SceneTree

## 临时验证：模拟下拉选择模式个数（真实信号路径）

func _initialize() -> void:
	await process_frame
	var ui_scene: PackedScene = load("res://scenes/ui.tscn")
	var ui = ui_scene.instantiate()
	root.add_child(ui)
	await process_frame
	for root in [ui.ENGINEER, ui.ADV_ENGINEER]:
		var btn: OptionButton = ui.get_node(NodePath(root + "/Mode/OptionButton"))
		var mt: CanvasItem = ui.get_node(NodePath(root + "/Mode/TabContainer"))
		var mp: CanvasItem = ui.get_node(NodePath(root + "/TabContainer"))
		for sel in [0, 1]:
			btn.select(sel)
			btn.emit_signal("item_selected", sel)  # 与真实下拉行为一致
			await process_frame
			print("%s 模式%d: ModeTabs.visible=%s in_tree=%s | 模式页TabContainer.visible=%s in_tree=%s current_tab=%d"
				% [root, sel + 1, mt.visible, mt.is_visible_in_tree(), mp.visible, mp.is_visible_in_tree(), mp.current_tab])
	quit(0)

extends SceneTree

var _fails: Array[String] = []


func _check(label: String, condition: bool) -> void:
	if condition:
		print("[ok] %s" % label)
	else:
		print("[FAIL] %s" % label)
		_fails.append(label)


func _initialize() -> void:
	var progress_script = preload("res://scripts/upgrade_progress.gd")
	var stage1_hint: String = progress_script.compile_error_hint(1)
	_check("阶段一编译错误提示联系负责人", stage1_hint.contains("联系项目负责人"))
	_check("阶段一编译错误提示附带项目文件", stage1_hint.contains("附带项目文件"))
	_check("阶段一编译错误提示可考虑 AI", stage1_hint.contains("考虑使用 AI"))
	var stage2_hint: String = progress_script.compile_error_hint(2)
	_check("阶段二编译错误提示使用 AI", stage2_hint.contains("用 AI 修复错误"))
	_check("阶段二编译错误提示返回配置", stage2_hint.contains("重新进入配置阶段"))

	var progress_scene: PackedScene = load("res://scenes/upgrade_progress.tscn")
	var progress: Control = progress_scene.instantiate()
	root.add_child(progress)
	await process_frame
	progress.begin()
	progress.set_progress("正在写入程序", 67.0, "19840/29691 字节 (67%)")
	_check("弹层开始升级后可见", progress.visible)
	_check("阶段文字已更新",
		progress.get_node("Dim/Center/Panel/Content/Stage").text == "正在写入程序")
	_check("进度值已更新",
		is_equal_approx(progress.get_node("Dim/Center/Panel/Content/Progress").value, 67.0))
	_check("升级过程中关闭按钮隐藏",
		not progress.get_node("Dim/Center/Panel/Content/Close").visible)
	_check("升级过程中显示取消按钮",
		progress.get_node("Dim/Center/Panel/Content/Cancel").visible)
	_check("编译阶段取消按钮禁用",
		progress.get_node("Dim/Center/Panel/Content/Cancel").disabled)
	progress.set_cancel_enabled(true)
	_check("烧录阶段取消按钮启用",
		not progress.get_node("Dim/Center/Panel/Content/Cancel").disabled)
	progress.complete()
	_check("完成后显示关闭按钮",
		progress.get_node("Dim/Center/Panel/Content/Close").visible)
	_check("完成后进度为 100",
		is_equal_approx(progress.get_node("Dim/Center/Panel/Content/Progress").value, 100.0))
	_check("完成后取消按钮隐藏",
		not progress.get_node("Dim/Center/Panel/Content/Cancel").visible)
	progress.fail("烧录失败", "连接未完成")
	_check("失败状态保留弹层", progress.visible)
	_check("失败状态显示关闭按钮",
		progress.get_node("Dim/Center/Panel/Content/Close").visible)
	_check("失败状态取消按钮隐藏",
		not progress.get_node("Dim/Center/Panel/Content/Cancel").visible)

	# 取消信号：启用状态下点取消发出 cancel_requested，禁用状态不发出
	var cancel_count: Array[int] = [0]
	progress.cancel_requested.connect(func() -> void: cancel_count[0] += 1)
	progress.begin()
	progress.set_cancel_enabled(true)
	var cancel_btn: Button = progress.get_node("Dim/Center/Panel/Content/Cancel")
	cancel_btn.pressed.emit()
	_check("启用状态下点取消发出 cancel_requested", cancel_count[0] == 1)
	progress.set_cancel_enabled(false)
	cancel_btn.pressed.emit()
	_check("禁用状态下点取消不发出 cancel_requested", cancel_count[0] == 1)
	progress.canceled()
	_check("已取消状态显示关闭按钮",
		progress.get_node("Dim/Center/Panel/Content/Close").visible)
	_check("已取消状态隐藏取消按钮",
		not progress.get_node("Dim/Center/Panel/Content/Cancel").visible)
	_check("已取消状态标题",
		progress.get_node("Dim/Center/Panel/Content/Title").text == "升级已取消")

	var ui_scene: PackedScene = load("res://scenes/ui.tscn")
	var ui: Control = ui_scene.instantiate()
	_check("图形化页隐藏编译按钮", not ui.get_node("VBoxContainer/TopPanel/Build").visible)
	_check("图形化页隐藏烧录按钮", not ui.get_node("VBoxContainer/TopPanel/Download").visible)
	_check("图形化页显示升级按钮", ui.get_node("VBoxContainer/TopPanel/Upgrade").visible)
	ui.free()

	var code_scene: PackedScene = load("res://scenes/code_edit.tscn")
	var code_ui: Control = code_scene.instantiate()
	_check("AI 页隐藏编译按钮", not code_ui.get_node("VBoxContainer/TopPanel/Build").visible)
	_check("AI 页隐藏烧录按钮", not code_ui.get_node("VBoxContainer/TopPanel/Download").visible)
	_check("AI 页显示升级按钮", code_ui.get_node("VBoxContainer/TopPanel/Upgrade").visible)
	code_ui.free()

	root.remove_child(progress)
	progress.free()
	print("=== 升级 UI: %s ===" % ("通过" if _fails.is_empty() else "%d 项失败" % _fails.size()))
	quit(0 if _fails.is_empty() else 1)
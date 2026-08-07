extends SceneTree

const UI_SCENE_PATH: String = "res://scenes/ui.tscn"
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")
const CODEGEN = preload("res://scripts/codegen/codegen_engineer_ik.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


func _valid_ik(jc: int = 4) -> Dictionary:
	var cfg: Dictionary = IK_CONFIG.default_config()
	cfg["enabled"] = true
	var ios: Array = ["P74", "P75", "P76", "P77", "MP03", "MP74"]
	var axes: Array = ["Yaw", "Pitch", "Pitch", "Pitch", "Roll", "Yaw"]
	var lens: Array = [0, 120, 90, 40, 20, 15]
	var joints: Array = []
	for i in range(jc):
		joints.append({"io": ios[i], "dir": "正向", "axis": axes[i],
			"len": str(lens[i]), "offset": "0", "zero": "0", "min": "-90", "max": "90"})
	cfg["joint_count"] = jc
	cfg["joints"] = joints
	return IK_CONFIG.normalize(cfg)


func _initialize() -> void:
	print("=== 结构化 IK UI 端到端验证 ===")
	# In --script mode autoload names are registered after this script's constants.
	# Load the UI at runtime so ui.gd can resolve the AppState singleton.
	await process_frame
	var ui_scene: PackedScene = load(UI_SCENE_PATH)
	var ui = ui_scene.instantiate()
	root.add_child(ui)
	await process_frame

	var ik_root: String = "VBoxContainer/HBoxContainer/HSplitContainer/EditZone/SecondRow/TabContainer/EngineerAdvanced"
	_check("旧关节数控件已移除", ui.get_node_or_null(ik_root + "/ConfigType") == null)
	_check("入口摘要存在", ui.get_node_or_null(ik_root + "/Summary") is Label)
	_check("3D 配置入口存在", ui.get_node_or_null(ik_root + "/OpenSim") is Button)

	ui._ik_config = _valid_ik(4)
	var collected: Dictionary = ui._collect_ik_config()
	_check("主页面从结构化状态收集", collected == _valid_ik(4))
	collected["joints"][0]["len"] = "999"
	_check("收集结果是副本", str(ui._ik_config["joints"][0]["len"]) == "0")

	for pin in ["P74", "P75", "P76", "P77"]:
		var node: Node = ui.get_node_or_null(NodePath(ui.ENG_IO_PATHS[pin]))
		if node is OptionButton:
			ui._select_option_by_text(node, "舵机")
	var dual: Dictionary = ui._collect_engineer_dual_config()
	_check("双模式配置包含结构化 IK", dual["ik"] == ui._ik_config)
	var code_before: String = CODEGEN.new().generate(dual)

	ui._dirty = false
	var changed: Dictionary = _valid_ik(4)
	changed["joints"][1]["len"] = "175"
	changed["gripper"]["enabled"] = true
	changed["gripper"]["io"] = "MP03"
	ui._on_arm_sim_config_changed({"ik": changed, "io_init": {"P76": "舵机"}})
	_check("仿真修改实时更新内存", str(ui._ik_config["joints"][1]["len"]) == "175")
	_check("仿真修改标记未保存", ui._dirty)
	var p76: Node = ui.get_node_or_null(NodePath(ui.ENG_IO_PATHS["P76"]))
	_check("扩展口自动初始化为舵机", p76 is OptionButton and ui._option_text(p76) == "舵机")
	var summary: Label = ui.get_node(ik_root + "/Summary")
	_check("入口摘要显示夹爪 IO", summary.text.contains("夹爪 MP03"))
	var code_after: String = CODEGEN.new().generate(ui._collect_engineer_dual_config())
	_check("仿真配置改变生成代码", code_before != code_after and code_after.contains("175.00f"))

	var tabs: TabContainer = ui.get_node(ui.P_TAB_CONTAINER)
	tabs.current_tab = 1
	ui._run_check()
	var code_edit: CodeEdit = ui.get_node(ui.P_CODE_EDIT)
	var engineer_code: String = code_edit.text
	tabs.current_tab = 2
	ui._run_check()
	_check("两张工程页生成相同代码", code_edit.text == engineer_code)

	ui._ik_config = IK_CONFIG.default_config()
	ui._solver_upgrade_active = false
	ui._upgrade_active = false
	ui._on_solver_build_requested()
	var output: CodeEdit = ui.get_node(ui.P_OUTPUT)
	_check("invalid kinematic configuration cannot start solver build",
		not ui._solver_upgrade_active and not ui._upgrade_active
		and output.text.contains("MCU 求解器构型无效"))
	ui._ik_config = changed

	ui._ik_confirmed = false
	ui._apply_ik_gate(false)
	ui._stage2_preview = false
	_check("未确认时 3D 配置按钮不可用",
		ui.get_node_or_null(ik_root + "/OpenSim") is Button
		and ui.get_node(ik_root + "/OpenSim").disabled)
	_check("未确认时 IK 摘要不可见", not ui.get_node(ik_root + "/Summary").visible)
	# 未启用逆解算：生成纯正解固件，不含逆解内容，也不产生逆解相关检查项
	tabs.current_tab = 1
	ui._run_check()
	var no_ik_code: String = code_edit.text
	_check("未启用时生成纯正解代码", not no_ik_code.contains("JOINT_COUNT")
		and not no_ik_code.contains("ik_solve")
		and not no_ik_code.contains("inverseMode"), no_ik_code.substr(0, 120))
	var no_ik_has_ik_issue: bool = false
	for issue in ui._last_issues:
		if str(issue.get("msg", "")).contains("逆解"):
			no_ik_has_ik_issue = true
			break
	_check("未启用时不产生逆解检查项", not no_ik_has_ik_issue)
	tabs.current_tab = 2
	ui._run_check()
	_check("未启用时两张工程页仍生成相同代码", code_edit.text == no_ik_code)
	ui._on_ik_gate_confirmed()
	ui._on_arm_sim_pressed()
	await process_frame
	_check("入口传入双模式配置", ui._arm_sim != null and ui._arm_sim._jc == 4)
	_check("阶段一仿真可编辑", ui._arm_sim != null and ui._arm_sim._editable)
	ui._on_arm_sim_closed()
	await process_frame
	ui._stage2_preview = true
	ui._ik_confirmed = true
	ui._apply_ik_gate(true)
	ui._on_arm_sim_pressed()
	await process_frame
	_check("阶段二仿真只读", ui._arm_sim != null and not ui._arm_sim._editable)
	ui._on_arm_sim_closed()

	# 升级主控编译失败：阶段一且未开逆解 -> 致命错误页；阶段二或开逆解 -> 普通错误页
	ui._project["stage"] = 1
	ui._ik_confirmed = false
	ui._upgrade_active = true
	ui._on_upgrade_build_finished({"ok": false, "log": "fake fatal log"})
	await process_frame
	var fatal_gate: Node = _find_gate(ui, "遇到致命错误！")
	_check("阶段一未开逆解编译失败弹致命错误页", fatal_gate != null)
	if fatal_gate != null:
		var fatal_log: Node = fatal_gate.get_node_or_null("VBoxContainer/TextEdit")
		_check("致命错误页填入编译日志",
			fatal_log is TextEdit and fatal_log.text.contains("fake fatal log"))
		fatal_gate.queue_free()
		await process_frame

	ui._project["stage"] = 2
	ui._ik_confirmed = false
	ui._upgrade_active = true
	ui._on_upgrade_build_finished({"ok": false, "log": "fake error log"})
	await process_frame
	var error_gate: Node = _find_gate(ui, "遇到错误！")
	_check("阶段二编译失败弹普通错误页", error_gate != null)
	if error_gate != null:
		var error_log: Node = error_gate.get_node_or_null("VBoxContainer/TextEdit")
		_check("普通错误页填入编译日志",
			error_log is TextEdit and error_log.text.contains("fake error log"))
		error_gate.queue_free()
		await process_frame

	ui._project["stage"] = 1
	ui._ik_confirmed = true
	ui._upgrade_active = true
	ui._on_upgrade_build_finished({"ok": false, "log": "fake error log 2"})
	await process_frame
	var error_gate2: Node = _find_gate(ui, "遇到错误！")
	_check("开启逆解后编译失败弹普通错误页", error_gate2 != null)
	if error_gate2 != null:
		error_gate2.queue_free()
		await process_frame

	root.remove_child(ui)
	ui.free()
	print("=== 结果: %s ===" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	quit(0 if _fail == 0 else 1)


func _find_gate(node: Node, title: String) -> Node:
	for child in node.get_children():
		if child is Control and child.has_method("configure"):
			var label: Node = child.get_node_or_null("VBoxContainer/HBoxContainer/Label")
			if label is Label and label.text == title:
				return child
	return null

extends SceneTree

const UI_SCENE = preload("res://scenes/ui.tscn")
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
	var ui = UI_SCENE.instantiate()
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

	ui._stage2_preview = false
	ui._on_arm_sim_pressed()
	await process_frame
	_check("入口传入双模式配置", ui._arm_sim != null and ui._arm_sim._jc == 4)
	_check("阶段一仿真可编辑", ui._arm_sim != null and ui._arm_sim._editable)
	ui._on_arm_sim_closed()
	await process_frame
	ui._stage2_preview = true
	ui._on_arm_sim_pressed()
	await process_frame
	_check("阶段二仿真只读", ui._arm_sim != null and not ui._arm_sim._editable)
	ui._on_arm_sim_closed()

	root.remove_child(ui)
	ui.free()
	print("=== 结果: %s ===" % ("全部通过" if _fail == 0 else "%d 项失败" % _fail))
	quit(0 if _fail == 0 else 1)

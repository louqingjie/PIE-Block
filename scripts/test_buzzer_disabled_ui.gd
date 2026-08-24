extends SceneTree

## 步兵高级设置与工程设置的“禁用蜂鸣器”配置回归测试。
## 运行：godot --headless --path . --script res://scripts/test_buzzer_disabled_ui.gd

const ProjectFile = preload("res://scripts/project_file.gd")
const CliCodegen = preload("res://scripts/cli_codegen.gd")

const INFANTRY_CHECKBOX: NodePath = \
	"VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Infantry/Advanced/Buzzer/CheckBox"
const ENGINEER_CHECKBOX: NodePath = \
	"VBoxContainer/HBoxContainer/HSplitContainer/EditZone/Engineer/PWMGroups/Buzzer/CheckBox"

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

	var infantry_checkbox: Node = ui.get_node_or_null(INFANTRY_CHECKBOX)
	var engineer_checkbox: Node = ui.get_node_or_null(ENGINEER_CHECKBOX)
	_check("步兵高级设置提供禁用蜂鸣器复选框", infantry_checkbox is CheckBox)
	_check("工程设置提供禁用蜂鸣器复选框", engineer_checkbox is CheckBox)
	_check("两个复选框默认均未勾选",
		infantry_checkbox is CheckBox and not infantry_checkbox.button_pressed
		and engineer_checkbox is CheckBox and not engineer_checkbox.button_pressed)
	var edit_zone: Control = ui.get_node(ui.P_EDIT_ZONE) as Control
	_check("步兵复选框位于可见配置区域",
		infantry_checkbox is Control and infantry_checkbox.is_visible_in_tree()
		and infantry_checkbox.size.y > 0.0
		and edit_zone.get_global_rect().intersects(infantry_checkbox.get_global_rect()))

	if infantry_checkbox is CheckBox and engineer_checkbox is CheckBox:
		infantry_checkbox.button_pressed = true
		var snapshot: Dictionary = ui._snapshot_config()
		var infantry_key: String = str(INFANTRY_CHECKBOX).trim_prefix(
			"VBoxContainer/HBoxContainer/HSplitContainer/EditZone/")
		_check("复选框状态进入项目配置快照",
			snapshot.get(infantry_key, {}).get("b", false) == true)
		infantry_checkbox.button_pressed = false
		ui._apply_config(snapshot)
		_check("项目配置回填恢复勾选状态", infantry_checkbox.button_pressed)
		ui._apply_config({infantry_key: {"b": "损坏值"}})
		_check("损坏的复选框值回退为启用", not infantry_checkbox.button_pressed)
		infantry_checkbox.button_pressed = true

		ui._apply_kind_visibility(ProjectFile.KIND_INFANTRY, 0)
		_check("步兵配置收集传递 buzzer_disabled",
			ui._collect_engineer_config().get("buzzer_disabled", false) == true)

		ui._apply_kind_visibility(ProjectFile.KIND_ENGINEER, 0)
		engineer_checkbox.button_pressed = true
		_check("工程配置收集传递 buzzer_disabled",
			ui._collect_engineer_config().get("buzzer_disabled", false) == true)
		var complete_snapshot: Dictionary = ui._snapshot_config()
		var cli = CliCodegen.new()
		_check("CLI 展平步兵项目快照传递 buzzer_disabled",
			cli._flatten_infantry_config(snapshot).get("buzzer_disabled", false) == true)
		_check("CLI 展平工程项目快照传递 buzzer_disabled",
			cli._flatten_engineer_config(complete_snapshot).get("buzzer_disabled", false) == true)
		var corrupt_snapshot: Dictionary = snapshot.duplicate(true)
		corrupt_snapshot[infantry_key] = {"b": "损坏值"}
		_check("CLI 损坏字段回退为启用",
			cli._flatten_infantry_config(corrupt_snapshot).get("buzzer_disabled", true) == false)
		cli.free()

		engineer_checkbox.button_pressed = false
		var engineer_key: String = str(ENGINEER_CHECKBOX).trim_prefix(
			"VBoxContainer/HBoxContainer/HSplitContainer/EditZone/")
		_check("旧项目缺少字段时按默认值保持蜂鸣器启用",
			ui._default_config.has(engineer_key)
			and not bool(ui._default_config[engineer_key].get("b", false)))

	root.remove_child(ui)
	ui.free()
	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

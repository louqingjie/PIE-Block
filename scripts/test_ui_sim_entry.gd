## 顶栏「3D 仿真」入口回归测试。
## 步兵整车仿真保留，工程与调试项目不显示仿真入口。
## 运行：godot --headless --path . --script scripts/test_ui_sim_entry.gd
extends SceneTree

const UI_SCENE_PATH: String = "res://scenes/ui.tscn"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[PASS] %s" % label)
	else:
		print("[FAIL] %s %s" % [label, detail])
		_fail += 1


func _initialize() -> void:
	print("=== 顶栏 3D 仿真入口回归测试 ===")
	# --script 模式下 autoload 在脚本常量之后注册，运行时装场景以便解析 AppState
	await process_frame
	var ui_scene: PackedScene = load(UI_SCENE_PATH)
	var ui: Node = ui_scene.instantiate()
	root.add_child(ui)
	await process_frame

	var btn: Button = ui.get_node(ui.P_SIM_BTN)
	var tabs: TabContainer = ui.get_node(ui.P_TAB_CONTAINER)

	# 无项目自由编辑默认显示步兵页，按钮应可见
	_check("初始按钮可见（默认 Tab %d）" % tabs.current_tab, btn.visible,
		"tab=%d visible=%s" % [tabs.current_tab, str(btn.visible)])

	# 进入工程项目上下文后，顶栏仿真入口应隐藏。
	ui._apply_kind_visibility("engineer", 1)
	await process_frame
	_check("工程 Tab（1）按钮隐藏", not btn.visible)
	_check("工程区域只保留一个配置页", tabs.get_tab_count() == 1)

	# 回到步兵项目上下文后，整车仿真入口仍可用。
	ui._apply_kind_visibility("infantry", 0)
	await process_frame
	_check("步兵 Tab（0）按钮可见", btn.visible)

	# 步兵 Tab 点顶栏按钮 -> 步兵整车仿真
	tabs.current_tab = 0
	await process_frame
	ui._on_sim_pressed()
	await process_frame
	_check("步兵仿真可打开",
		ui._simulation_view != null and ui._simulation_view.scene_file_path.ends_with("infantry_sim.tscn"),
		"simulation=%s" % str(ui._simulation_view))
	if ui._simulation_view != null:
		ui._on_sim_closed()
	await process_frame

	print("失败数: %d" % _fail)
	quit(_fail)

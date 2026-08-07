## 顶栏「3D 仿真」入口回归测试。
## 步兵整车仿真属基础功能，不应被机械臂逆解（IK）高级门控连坐隐藏：
##   0=步兵         -> 顶栏按钮可见，点击打开步兵整车仿真（无需 IK 确认）
##   1=工程         -> 没有仿真，按钮隐藏
##   2=工程逆解算   -> 顶栏按钮可见，点击打开机械臂仿真（经 IK 门控）
##   3=调试         -> 没有仿真，按钮隐藏
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

	var btn: Button = ui.get_node(ui.P_ARM_SIM_BTN)
	var tabs: TabContainer = ui.get_node(ui.P_TAB_CONTAINER)

	# 无项目自由编辑：场景默认停在 Tab 2（工程逆解算），按钮应可见
	_check("初始按钮可见（默认 Tab %d）" % tabs.current_tab, btn.visible,
		"tab=%d visible=%s" % [tabs.current_tab, str(btn.visible)])

	# 逐 Tab 切换（current_tab 赋值会触发 tab_changed 信号刷新可见性）
	tabs.current_tab = 0
	await process_frame
	_check("步兵 Tab（0）按钮可见", btn.visible)
	tabs.current_tab = 1
	await process_frame
	_check("工程 Tab（1）按钮隐藏", not btn.visible)
	tabs.current_tab = 2
	await process_frame
	_check("工程逆解算 Tab（2）按钮可见", btn.visible)
	tabs.current_tab = 3
	await process_frame
	_check("调试 Tab（3）按钮隐藏", not btn.visible)

	# 步兵 Tab 点顶栏按钮 -> 步兵整车仿真（不属 IK 门控，直接打开）
	tabs.current_tab = 0
	await process_frame
	ui._on_arm_sim_pressed()
	await process_frame
	_check("步兵仿真可打开",
		ui._arm_sim != null and ui._arm_sim.scene_file_path.ends_with("infantry_sim.tscn"),
		"arm_sim=%s" % str(ui._arm_sim))
	if ui._arm_sim != null:
		ui._on_arm_sim_closed()
	await process_frame

	print("失败数: %d" % _fail)
	quit(_fail)

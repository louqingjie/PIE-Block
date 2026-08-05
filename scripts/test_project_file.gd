extends SceneTree

## 项目文件（.pieproj）与图形化配置序列化测试。
## 运行方式：godot --headless --path . --script scripts/test_project_file.gd

const PF = preload("res://scripts/project_file.gd")
const IK_CONFIG = preload("res://scripts/engineer_ik_config.gd")

const TMP_DIR: String = "user://_test_pieproj"

var _fail: int = 0


class MissingHexToolchain extends RefCounted:
	func get_hex_path(_project_dst: String) -> String:
		return "user://missing.hex"

	func hex_exists(_project_dst: String) -> bool:
		return false


class SolverReconnectProbe extends Control:
	var reconnect_count: int = 0

	func reconnect_mcu_solver_after_flash() -> void:
		reconnect_count += 1


## AppState 是 autoload，--script 模式下没有全局标识符，只能从 root 拿
func _app() -> Node:
	return root.get_node("/root/AppState")


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _initialize() -> void:
	print("=== 项目文件与配置序列化测试 ===\n")
	_check("项目格式版本已升级到 7", PF.FORMAT_VERSION == 7)
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_test_kind_mapping()
	_test_roundtrip()
	_test_corrupt()
	_test_normalize()
	await _test_config_roundtrip()
	await _test_lifecycle()
	await _test_launcher()
	_test_code_edit_focus_setup()
	_cleanup()
	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _cleanup() -> void:
	var da: DirAccess = DirAccess.open(TMP_DIR)
	if da == null:
		return
	for f in da.get_files():
		da.remove(f)
	DirAccess.open("user://").remove("_test_pieproj")


# ------------------------------------------------------------------ AI 编辑引导与焦点配置
func _test_code_edit_focus_setup() -> void:
	print("--- AI 编辑引导与焦点配置 ---")
	var packed: PackedScene = load("res://scenes/code_edit.tscn") as PackedScene
	_check("code_edit.tscn 可加载", packed != null)
	if packed == null:
		return
	var editor: Node = packed.instantiate()
	var webview: Node = editor.get_node_or_null("WebView")
	var guide: Node = editor.get_node_or_null(editor.P_PROJECT_GUIDE)
	_check("AI 编辑页实例化独立项目引导", guide != null
		and guide.scene_file_path == "res://scenes/project_guide.tscn")
	if guide != null:
		var completed: Array[bool] = [true, true, true, true, false, false, false]
		guide.setup(editor.GUIDE_TITLES, editor.GUIDE_HINTS, completed)
	_check("AI 编辑页引导提供七个步骤", guide != null and guide.get_step_count() == 7)
	_check("AI 编辑页代码框路径有效", editor.get_node_or_null(editor.P_CODE_EDIT) is CodeEdit)
	_check("AI 编辑页终端槽路径有效", editor.get_node_or_null(editor.P_WEB_SLOT) is Control)
	var download: Node = editor.get_node_or_null(editor.P_DOWNLOAD)
	_check("AI 编辑页提供烧录主控板按钮", download is Button
		and download.text == "烧录主控板")
	_check("AI 编辑脚本提供烧录入口", editor.has_method("_on_download_pressed"))
	_check("AI 编辑页使用共享烧录控制器", editor.DC.resource_path
		== "res://scripts/download_controller.gd")
	_check("AI 编辑页使用共享编译控制器", editor.BC.resource_path
		== "res://scripts/build_controller.gd")
	_check("WebView 不在创建时抢焦点", webview != null
		and not bool(webview.get("focused_when_created")))
	_check("脚本提供代码面板聚焦入口", editor.has_method("_focus_code_input"))
	_check("脚本提供终端面板聚焦入口", editor.has_method("_focus_terminal_input"))
	editor.free()
	print("")


# ------------------------------------------------------------------ 类型映射
func _test_kind_mapping() -> void:
	print("--- 项目类型 <-> Tab 映射 ---")
	_check("三种类型", PF.KINDS.size() == 3)
	_check("步兵 -> [0]", PF.kind_tabs(PF.KIND_INFANTRY) == [0])
	_check("工程 -> [1, 2]（含工程逆解算）", PF.kind_tabs(PF.KIND_ENGINEER) == [1, 2])
	_check("调试 -> [3]", PF.kind_tabs(PF.KIND_DEBUG) == [3])
	# 三种类型的 Tab 集合互不重叠，且并集覆盖全部 4 页
	var seen: Array = []
	var overlap: bool = false
	for kind in PF.KINDS:
		for t in PF.kind_tabs(kind):
			if t in seen:
				overlap = true
			seen.append(t)
	seen.sort()
	_check("Tab 集合互不重叠", not overlap)
	_check("并集覆盖全部 4 个 Tab", seen == [0, 1, 2, 3])
	_check("默认 Tab：工程 = 1", PF.kind_default_tab(PF.KIND_ENGINEER) == 1)
	_check("Tab 反查类型：2 -> 工程", PF.tab_to_kind(2) == PF.KIND_ENGINEER)
	_check("Tab 反查类型：3 -> 调试", PF.tab_to_kind(3) == PF.KIND_DEBUG)
	_check("kind_label 覆盖调试", PF.kind_label(PF.KIND_DEBUG) == "调试")
	_check("非法 kind 回退步兵", PF.kind_label("nonsense") == "步兵")
	# kind_tabs 返回副本，改它不能污染常量表
	var tabs: Array = PF.kind_tabs(PF.KIND_ENGINEER)
	tabs.append(99)
	_check("kind_tabs 返回副本", PF.kind_tabs(PF.KIND_ENGINEER) == [1, 2])
	print("")


# ------------------------------------------------------------------ 存读往返
func _test_roundtrip() -> void:
	print("--- 存 / 读往返 ---")
	var cases: Array = [
		[PF.KIND_INFANTRY, 1, 0],
		[PF.KIND_ENGINEER, 1, 2],
		[PF.KIND_ENGINEER, 2, 1],
		[PF.KIND_DEBUG, 2, 3],
	]
	for c in cases:
		var kind: String = c[0]
		var stage: int = c[1]
		var tab: int = c[2]
		var data: Dictionary = PF.new_data(kind)
		data["stage"] = stage
		data["active_tab"] = tab
		# 含中文、引号、反斜杠、换行的配置值与代码
		data["config"] = {
			"FirstRow/RemoteSetting/Channel/LineEdit": {"t": "36"},
			"FirstRow/Chassis/L1/OptionButton": {"i": 3, "s": "P74 P24"},
			"FirstRow/Chassis/Sprint/CheckBox": {"b": true},
			"SecondRow/中文节点/Weird": {"t": "引号\" 反斜杠\\ 换行\n结束"},
		}
		data["ik_config"]["joint_count"] = 6
		data["ik_config"]["joints"] = []
		for i in range(6):
			data["ik_config"]["joints"].append({"io": ["P60", "P62", "P64", "P66", "P74", "P75"][i],
				"dir": "正向", "axis": "Yaw" if i == 0 else "Pitch", "len": str(i * 10),
				"offset": "0", "zero": "0", "min": "-90", "max": "90"})
		data["main_c_stage1"] = "#include \"main.h\"\nint main(){return 0;}\n"
		data["main_c_ai"] = "// AI 改过\nint main(){while(1);}\n" if stage >= 2 else ""
		data["workflow"] = {
			"hardware_confirmed": true,
			"checked_hash": "check-123",
			"built_hash": "build-123",
			"flashed_hash": "flash-123",
			"firmware_mode": "simulator" if kind == PF.KIND_ENGINEER else "production",
			"hardware_tested": stage >= 2,
			"guide_completed": [true, true, true, true, true, true, stage >= 2],
		}
		var path: String = "%s/%s_%d.%s" % [TMP_DIR, kind, stage, PF.EXT]
		var w: Dictionary = PF.save_to(path, data)
		_check("%s/阶段%d 写入成功" % [kind, stage], w["ok"], str(w["err"]))
		var r: Dictionary = PF.load_from(path)
		_check("%s/阶段%d 读取成功" % [kind, stage], r["ok"], str(r["err"]))
		if not r["ok"]:
			continue
		var got: Dictionary = r["data"]
		_check("%s/阶段%d kind 保持" % [kind, stage], got["kind"] == kind)
		_check("%s/阶段%d stage 保持" % [kind, stage], int(got["stage"]) == stage)
		_check("%s/阶段%d active_tab 保持" % [kind, stage], int(got["active_tab"]) == tab)
		_check("%s/阶段%d config 完全一致" % [kind, stage],
			got["config"] == data["config"])
		_check("%s/阶段%d ik_config 完全一致" % [kind, stage],
			got["ik_config"] == data["ik_config"])
		_check("%s/阶段%d main_c_stage1 一致" % [kind, stage],
			got["main_c_stage1"] == data["main_c_stage1"])
		_check("%s/阶段%d main_c_ai 一致" % [kind, stage],
			got["main_c_ai"] == data["main_c_ai"])
		_check("%s/阶段%d workflow 一致" % [kind, stage],
			got["workflow"] == PF.normalize_workflow(data["workflow"]))
	# current_main_c：阶段二优先 AI 版
	var d2: Dictionary = PF.new_data(PF.KIND_ENGINEER)
	d2["stage"] = 2
	d2["main_c_stage1"] = "S1"
	d2["main_c_ai"] = "AI"
	_check("阶段二取 AI 代码", PF.current_main_c(d2) == "AI")
	d2["main_c_ai"] = ""
	_check("阶段二 AI 为空时回落阶段一代码", PF.current_main_c(d2) == "S1")
	d2["stage"] = 1
	d2["main_c_ai"] = "AI"
	_check("阶段一忽略 AI 代码", PF.current_main_c(d2) == "S1")
	print("")


# ------------------------------------------------------------------ 容错
func _test_corrupt() -> void:
	print("--- 损坏文件容错 ---")
	var miss: Dictionary = PF.load_from(TMP_DIR + "/不存在的文件." + PF.EXT)
	_check("文件不存在返回 err", not miss["ok"] and not str(miss["err"]).is_empty())
	_check("空路径返回 err", not PF.load_from("")["ok"])

	var bad_path: String = TMP_DIR + "/bad." + PF.EXT
	var f: FileAccess = FileAccess.open(bad_path, FileAccess.WRITE)
	f.store_string("{ 这不是 JSON ")
	f.close()
	_check("非法 JSON 返回 err 而不崩", not PF.load_from(bad_path)["ok"])

	var arr_path: String = TMP_DIR + "/arr." + PF.EXT
	var f2: FileAccess = FileAccess.open(arr_path, FileAccess.WRITE)
	f2.store_string("[1, 2, 3]")
	f2.close()
	_check("顶层是数组返回 err", not PF.load_from(arr_path)["ok"])

	var future_path: String = TMP_DIR + "/future." + PF.EXT
	var f3: FileAccess = FileAccess.open(future_path, FileAccess.WRITE)
	f3.store_string(JSON.stringify({"format_version": PF.FORMAT_VERSION + 5,
		"kind": "infantry"}))
	f3.close()
	_check("格式版本过高返回 err", not PF.load_from(future_path)["ok"])
	print("")


# ------------------------------------------------------------------ 字段规整
func _test_normalize() -> void:
	print("--- 缺字段 / 非法值规整 ---")
	var empty_path: String = TMP_DIR + "/empty." + PF.EXT
	var f: FileAccess = FileAccess.open(empty_path, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var r: Dictionary = PF.load_from(empty_path)
	_check("空对象可读", r["ok"], str(r["err"]))
	if r["ok"]:
		var d: Dictionary = r["data"]
		_check("缺 kind 回退步兵", d["kind"] == PF.KIND_INFANTRY)
		_check("缺 stage 回退 1", int(d["stage"]) == 1)
		_check("缺 config 回退空字典", (d["config"] as Dictionary).is_empty())
		_check("缺夹爪配置补默认固定舵机", d["ik_config"]["gripper"] == IK_CONFIG.default_gripper())
		_check("缺 main_c 回退空串", d["main_c_stage1"] == "" and d["main_c_ai"] == "")

	var weird: Dictionary = PF.normalize({
		"kind": "spaceship", "stage": 99, "active_tab": 7,
		"config": "不是字典", "main_c_stage1": 12345,
	})
	_check("非法 kind 纠正为步兵", weird["kind"] == PF.KIND_INFANTRY)
	_check("stage 99 钳成 2", int(weird["stage"]) == 2)
	_check("越界 active_tab 回落该类型默认页", int(weird["active_tab"]) == 0)
	_check("config 非字典纠正为空字典", (weird["config"] as Dictionary).is_empty())
	_check("main_c 非字符串转字符串", weird["main_c_stage1"] == "12345")
	_check("旧项目补齐七步引导进度",
		weird["workflow"]["guide_completed"] == [false, false, false, false, false, false, false])
	_check("缺少固件状态时回退 unknown",
		str(weird["workflow"]["firmware_mode"]) == "unknown")
	_check("正式固件状态可规范化保存",
		str(PF.normalize_workflow({"firmware_mode": "production"})["firmware_mode"])
			== "production")
	_check("非法固件状态不会伪装成已烧录",
		str(PF.normalize_workflow({"firmware_mode": "broken"})["firmware_mode"])
			== "unknown")
	var v6: Dictionary = PF.normalize({"format_version": 6, "kind": PF.KIND_ENGINEER,
		"ik_config": {"keymove": [ {}, {}, {}, {}]}})
	_check("版本6工程补齐六维遥控默认字段",
		v6["format_version"] == PF.FORMAT_VERSION
		and v6["ik_config"]["keymove"].size() == 6
		and v6["ik_config"]["orientation_key_speed"] == "1"
		and not v6["ik_config"]["rocker2_home_enabled"])
	var short_progress: Dictionary = PF.normalize({
		"workflow": {"guide_completed": [true, true, false]},
	})
	_check("短引导进度补齐为七步",
		short_progress["workflow"]["guide_completed"]
			== [true, true, false, false, false, false, false])
	var long_progress: Dictionary = PF.normalize({
		"workflow": {"guide_completed": [true, true, true, true, true, true, true, true]},
	})
	_check("超长引导进度截断为七步",
		(long_progress["workflow"]["guide_completed"] as Array).size() == PF.GUIDE_STEP_COUNT)

	# 工程项目的 active_tab 不能落在步兵页上
	var eng: Dictionary = PF.normalize({"kind": PF.KIND_ENGINEER, "active_tab": 0})
	_check("工程的 active_tab=0 纠正为 1", int(eng["active_tab"]) == 1)
	var eng2: Dictionary = PF.normalize({"kind": PF.KIND_ENGINEER, "active_tab": 2})
	_check("工程的 active_tab=2 保留（工程逆解算）", int(eng2["active_tab"]) == 2)
	_check("ensure_ext 补扩展名",
		PF.ensure_ext("C:/a/b/我的项目") == "C:/a/b/我的项目." + PF.EXT)
	_check("ensure_ext 已有扩展名不重复",
		PF.ensure_ext("C:/a/b.pieproj") == "C:/a/b.pieproj")
	print("")


# ------------------------------------------------------------------ 界面配置往返
func _test_config_roundtrip() -> void:
	print("--- 图形化配置快照 / 回填往返 ---")
	var packed: PackedScene = load("res://scenes/ui.tscn") as PackedScene
	_check("ui.tscn 可加载", packed != null)
	if packed == null:
		return
	var ui: Node = packed.instantiate()
	root.add_child(ui)
	# --script 模式下 add_child 不会立刻触发 _ready，必须等一帧
	await process_frame
	await process_frame

	var base: Dictionary = ui._snapshot_config()
	_check("快照非空", base.size() > 50, "实际 %d 项" % base.size())
	_check("快照不再包含工程逆解控件", not "EngineerAdvanced/ConfigType" in " ".join(base.keys()))
	_check("结构化 IK 默认切换键为 R", str(ui._ik_config.get("mode_switch_key", "")) == "R")

	# 改一批控件：LineEdit / OptionButton / CheckBox 三类都覆盖
	var touched: int = 0
	var zone: Node = ui.get_node(ui.P_EDIT_ZONE)
	for key in base.keys():
		var node: Node = zone.get_node_or_null(NodePath(str(key)))
		if node is LineEdit:
			node.text = "777"
			touched += 1
		elif node is OptionButton and node.item_count > 1:
			node.selected = (node.selected + 1) % node.item_count
			touched += 1
		elif node is BaseButton and node.toggle_mode:
			node.button_pressed = not node.button_pressed
			touched += 1
	_check("成功改动控件", touched > 20, "实际 %d 个" % touched)

	var changed: Dictionary = ui._snapshot_config()
	_check("改动后快照与初始不同", changed != base)

	# 回填初始快照，应完全复原
	ui._apply_config(base)
	var restored: Dictionary = ui._snapshot_config()
	_check("回填初始快照后完全复原", restored == base, _diff_hint(base, restored))

	# 再回填改动后的快照，也应完全复现
	ui._apply_config(changed)
	var restored2: Dictionary = ui._snapshot_config()
	_check("回填改动快照后完全复现", restored2 == changed, _diff_hint(changed, restored2))

	# 存盘 -> 读回 -> 回填，走完整 JSON 往返（int 会变 float，这里验证不受影响）
	var data: Dictionary = PF.new_data(PF.KIND_ENGINEER)
	data["config"] = changed
	var path: String = TMP_DIR + "/ui_roundtrip." + PF.EXT
	PF.save_to(path, data)
	var loaded: Dictionary = PF.load_from(path)
	_check("含界面配置的项目可读回", loaded["ok"], str(loaded["err"]))
	if loaded["ok"]:
		ui._apply_config(base)
		ui._apply_config(loaded["data"]["config"] as Dictionary)
		var after_json: Dictionary = ui._snapshot_config()
		_check("经 JSON 往返后配置仍完全复现", after_json == changed,
			_diff_hint(changed, after_json))

	# 缺项由默认值兜底：只回填一半的 key，其余应保持默认
	ui._apply_config(base)
	var partial: Dictionary = {}
	var n: int = 0
	for key in changed.keys():
		if n % 2 == 0:
			partial[key] = changed[key]
		n += 1
	ui._apply_config(partial)
	var mixed: Dictionary = ui._snapshot_config()
	var ok_partial: bool = true
	for key in base.keys():
		var want: Variant = partial[key] if partial.has(key) else base[key]
		if mixed[key] != want:
			ok_partial = false
			break
	_check("部分回填时其余项保持原值", ok_partial)

	# Tab 可见性：三种类型各自只显示自己的页
	var tabs: Node = ui.get_node(ui.P_TAB_CONTAINER)
	for kind in PF.KINDS:
		ui._apply_kind_visibility(kind, PF.kind_default_tab(kind))
		var visible_tabs: Array = []
		for i in range(tabs.get_tab_count()):
			if not tabs.is_tab_hidden(i):
				visible_tabs.append(i)
		_check("%s 只显示 %s" % [PF.kind_label(kind), str(PF.kind_tabs(kind))],
			visible_tabs == PF.kind_tabs(kind), "实际 %s" % str(visible_tabs))
		_check("%s 的 current_tab 落在可见页" % PF.kind_label(kind),
			tabs.current_tab in PF.kind_tabs(kind))

	root.remove_child(ui)
	ui.free()
	print("")


# ------------------------------------------------------------------ 项目生命周期
## 新建 -> 改配置 -> 保存 -> 重开 -> 进阶段二 -> 降回阶段一 全链路
func _test_lifecycle() -> void:
	print("--- 项目生命周期 ---")
	var packed: PackedScene = load("res://scenes/ui.tscn") as PackedScene
	if packed == null:
		return
	var ui: Node = packed.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame

	# 无项目上下文（直跑本场景）：保持老的自由编辑模式，不锁任何东西
	var tabs: Node = ui.get_node(ui.P_TAB_CONTAINER)
	var any_hidden: bool = false
	for i in range(tabs.get_tab_count()):
		if tabs.is_tab_hidden(i):
			any_hidden = true
	_check("无项目时 Tab 全可见（自由编辑）", not any_hidden)
	var channel: Node = ui.get_node(ui.P_CHANNEL)
	_check("无项目时配置区可编辑", channel.editable)
	var save_btn: Node = ui.get_node(ui.P_SAVE_BTN)
	_check("无项目时保存按钮可用", not save_btn.disabled)
	var create_btn: Node = ui.get_node(ui.P_CREATE_BTN)
	_check("无项目时新建按钮可用", not create_btn.disabled)

	# 新建工程项目
	var path: String = TMP_DIR + "/lifecycle." + PF.EXT
	_check("新建工程项目成功", ui._create_project_at(PF.KIND_ENGINEER, path))
	_check("新建后配置区可编辑", channel.editable)
	_check("新建后保存按钮可用", not save_btn.disabled)
	_check("新建后只显示工程相关 Tab", not tabs.is_tab_hidden(1)
		and not tabs.is_tab_hidden(2) and tabs.is_tab_hidden(0) and tabs.is_tab_hidden(3))
	var created: Dictionary = PF.load_from(path)
	_check("新建即落盘", created["ok"])
	_check("新建后是阶段一", int(created["data"]["stage"]) == 1)
	_check("新建后已生成阶段一代码",
		not str(created["data"]["main_c_stage1"]).strip_edges().is_empty())
	_check("新建项目带默认工作流状态",
		created["data"]["workflow"] == PF.normalize_workflow({}))
	_check("新建项目保存七步引导进度",
		(created["data"]["workflow"]["guide_completed"] as Array).size()
			== PF.GUIDE_STEP_COUNT)
	var guide: Node = ui.get_node(ui.P_PROJECT_GUIDE)
	_check("主界面实例化独立项目引导", guide.scene_file_path == "res://scenes/project_guide.tscn")
	_check("主界面显示七步项目引导", guide.get_step_count() == 7)
	_check("烧录按钮明确指向主控板", ui.get_node(ui.P_DOWNLOAD_BTN).text == "烧录主控板")
	_check("主界面使用共享编译控制器", ui.BC.resource_path
		== "res://scripts/build_controller.gd")
	var output: Node = ui.get_node(ui.P_OUTPUT)
	ui._append_output("旧烧录日志")
	var real_toolchain = ui._tc
	ui._download_controller.configure(MissingHexToolchain.new(), ui._clear_output, ui._append_output)
	ui._on_download_pressed()
	_check("新烧录尝试会清空旧日志", not str(output.text).contains("旧烧录日志"))
	_check("清空后保留本次烧录错误", str(output.text).contains("没有找到编译好的程序"))
	ui._download_controller.configure(real_toolchain, ui._clear_output, ui._append_output)
	_check("第一步未确认时显示全屏门禁", ui.get_node(ui.P_HARDWARE_GATE).visible)
	_check("第一步未确认时隐藏主 UI", not ui.get_node(ui.P_MAIN_UI).visible)
	ui._on_hardware_gate_confirmed()
	_check("确认第一步后隐藏门禁", not ui.get_node(ui.P_HARDWARE_GATE).visible)
	_check("确认第一步后显示主 UI", ui.get_node(ui.P_MAIN_UI).visible)
	var confirmed: Dictionary = PF.load_from(path)
	_check("第一步确认状态已写入项目",
		bool(confirmed["data"]["workflow"]["hardware_confirmed"]))
	_check("第一步完成进度已写入项目",
		bool(confirmed["data"]["workflow"]["guide_completed"][0]))

	# 改配置 -> 脏标记 -> 保存
	channel.text = "77"
	channel.text_changed.emit("77")
	_check("改配置后打上脏标记", ui._dirty)
	var title: Node = ui.get_node(ui.P_TITLE_LABEL)
	_check("脏标记体现在标题上", str(title.text).begins_with("*"),
		"实际 %s" % str(title.text))
	ui._save_project(false)
	_check("保存后清除脏标记", not ui._dirty)
	var saved: Dictionary = PF.load_from(path)
	var saved_guide_progress: Array = saved["data"]["workflow"]["guide_completed"].duplicate()
	_check("保存写入了改动的配置",
		str((saved["data"]["config"] as Dictionary)
			.get("FirstRow/RemoteSetting/Channel/LineEdit", {})
			.get("t", "")) == "77")

	# 关掉重开：配置应完全复现
	root.remove_child(ui)
	ui.free()
	_app().reset()
	_app().project_path = path
	_app().project_kind = PF.KIND_ENGINEER
	var ui2: Node = packed.instantiate()
	root.add_child(ui2)
	await process_frame
	await process_frame
	_check("重开后加载了项目", not ui2._project.is_empty())
	_check("重开后配置复现", str(ui2.get_node(ui2.P_CHANNEL).text) == "77",
		"实际 %s" % str(ui2.get_node(ui2.P_CHANNEL).text))
	_check("重开后仍是阶段一", int(ui2._project["stage"]) == 1)
	_check("重开后不是预览态", not ui2._stage2_preview)
	_check("重开已确认项目不再显示门禁", not ui2.get_node(ui2.P_HARDWARE_GATE).visible)
	_check("重开已确认项目直接显示主 UI", ui2.get_node(ui2.P_MAIN_UI).visible)
	var reopened: Dictionary = PF.load_from(path)
	_check("重开项目保留七步引导进度",
		reopened["data"]["workflow"]["guide_completed"] == saved_guide_progress)

	# 仿真求解器烧录会替换主控板上的正式固件，因此必须撤销正式烧录和真机验收状态。
	var production_hash: String = ui2._code_hash()
	var workflow_before_sim: Dictionary = ui2._workflow()
	workflow_before_sim["firmware_mode"] = "production"
	workflow_before_sim["flashed_hash"] = production_hash
	workflow_before_sim["hardware_tested"] = true
	ui2._project["workflow"] = workflow_before_sim
	var reconnect_probe := SolverReconnectProbe.new()
	ui2.add_child(reconnect_probe)
	ui2._arm_sim = reconnect_probe
	ui2._solver_upgrade_active = true
	ui2._upgrade_active = true
	ui2._project_dst_override = ui2.TC.PROJECT_ENGINEER_SIM_DST
	ui2._on_download_succeeded()
	await process_frame
	var after_sim_workflow: Dictionary = ui2._workflow()
	_check("求解器烧录记录主控板为仿真固件",
		str(after_sim_workflow["firmware_mode"]) == "simulator")
	_check("求解器烧录撤销旧正式固件哈希",
		str(after_sim_workflow["flashed_hash"]).is_empty())
	_check("求解器烧录撤销旧真机验收", not bool(after_sim_workflow["hardware_tested"]))
	_check("求解器烧录完成后等待重启并请求串口重连", reconnect_probe.reconnect_count == 1)
	var sim_guide: Array[bool] = ui2._guide_done_states()
	_check("仿真固件不会把正式烧录步骤标为完成", not sim_guide[5])
	_check("仿真固件不会把真机测试步骤标为完成", not sim_guide[6])

	# 用户明确烧录正式工程代码后，仿真警告才清除。
	ui2._arm_sim = null
	reconnect_probe.queue_free()
	ui2._upgrade_active = true
	ui2._on_download_succeeded()
	var after_production_workflow: Dictionary = ui2._workflow()
	_check("正式烧录恢复 production 固件状态",
		str(after_production_workflow["firmware_mode"]) == "production")
	_check("正式烧录记录当前代码哈希",
		str(after_production_workflow["flashed_hash"]) == ui2._code_hash())
	_check("正式烧录要求重新做真机测试",
		not bool(after_production_workflow["hardware_tested"]))

	_check("AI 编辑按钮初始隐藏", not bool(ui2.get_node(ui2.P_AI_EDIT_BTN).visible))
	# 点「启用 AI 功能」应先弹确认框，此时还没解锁 AI 编辑
	ui2._on_ai_enable_toggled(true)
	await process_frame
	var confirm: Node = _find_dialog(ui2, "警告")
	_check("点启用 AI 功能先弹确认框", confirm != null)
	_check("确认框弹出时 AI 编辑仍隐藏", not bool(ui2.get_node(ui2.P_AI_EDIT_BTN).visible))
	if confirm != null:
		# 取消：不该有任何变化
		confirm.canceled.emit()
		confirm.queue_free()
		await process_frame
		_check("取消后 AI 仍未启用", not bool(ui2._ai_enabled))
		_check("取消后 AI 编辑仍隐藏", not bool(ui2.get_node(ui2.P_AI_EDIT_BTN).visible))
		var still1: Dictionary = PF.load_from(path)
		_check("取消后磁盘上仍未启用 AI", not bool((still1["data"]["workflow"] as Dictionary).get("ai_enabled", false)))
	# 倒计时门控页应该先禁用主按钮
	ui2._on_ai_enable_toggled(true)
	await process_frame
	var confirm2: Node = _find_dialog(ui2, "警告")
	if confirm2 != null:
		var primary: Node = confirm2.get_node_or_null("VBoxContainer/HBoxContainer2/Button")
		_check("确认框按钮初始禁用", primary is BaseButton and primary.disabled)
		confirm2.confirmed.emit()
		confirm2.queue_free()
		await process_frame
		_check("确认后 AI 已启用", bool(ui2._ai_enabled))
		_check("确认后 AI 编辑已显示", bool(ui2.get_node(ui2.P_AI_EDIT_BTN).visible))
		var still2: Dictionary = PF.load_from(path)
		_check("确认后磁盘上记录 AI 已启用", bool((still2["data"]["workflow"] as Dictionary).get("ai_enabled", false)))

	# 进入阶段二（不切场景，直接走冻结逻辑）
	var code: String = ui2._current_preview_code()
	ui2._project["config"] = ui2._snapshot_config()
	ui2._project["main_c_stage1"] = code
	ui2._project["stage"] = 2
	ui2._project["main_c_ai"] = code
	ui2._save_project(false)
	var s2: Dictionary = PF.load_from(path)
	_check("阶段二已落盘", int(s2["data"]["stage"]) == 2)
	_check("阶段一代码已冻结", s2["data"]["main_c_stage1"] == code)

	# 模拟 AI 改了代码后保存
	var ai_code: String = code + "\n/* AI 加的注释 */\n"
	var s2d: Dictionary = s2["data"]
	s2d["main_c_ai"] = ai_code
	PF.save_to(path, s2d)

	# 重开：应进入只读预览态
	root.remove_child(ui2)
	ui2.free()
	_app().reset()
	_app().project_path = path
	_app().stage = 2
	var ui3: Node = packed.instantiate()
	root.add_child(ui3)
	await process_frame
	await process_frame
	var preview_dlg: Node = _find_dialog(ui3, "只能预览")
	if preview_dlg != null:
		preview_dlg.queue_free()
		await process_frame
	_check("阶段二重开进入预览态", ui3._stage2_preview)
	# 已在阶段二，再点 AI 编辑不该重复弹确认框（没有新的不可逆动作）
	var dlg_before: int = _count_dialogs(ui3)
	ui3._on_ai_edit_pressed()
	await process_frame
	_check("阶段二点 AI 编辑不再弹确认框",
		_find_dialog(ui3, "警告") == null and _count_dialogs(ui3) == dlg_before)
	# 阶段二在图形化界面保存时，冻结的 config 与 main_c_stage1 都不能被改写
	var frozen_cfg: Dictionary = (s2d["config"] as Dictionary).duplicate(true)
	ui3._save_project(false)
	var after_s2_save: Dictionary = PF.load_from(path)
	_check("阶段二保存不覆盖冻结的 config",
		after_s2_save["data"]["config"] == frozen_cfg)
	_check("阶段二保存不覆盖冻结的阶段一代码",
		after_s2_save["data"]["main_c_stage1"] == code)
	_check("阶段二保存不覆盖 AI 代码", after_s2_save["data"]["main_c_ai"] == ai_code)

	# 阶段二改配置：应先回滚
	var ch3: Node = ui3.get_node(ui3.P_CHANNEL)
	var before: String = str(ch3.text)
	ch3.text = "5"
	ch3.text_changed.emit("5")
	await process_frame
	_check("阶段二改动被回滚", str(ch3.text) == before,
		"期望 %s 实际 %s" % [before, str(ch3.text)])
	_check("阶段二仍未降级", int(ui3._project["stage"]) == 2)
	var ai_kept: Dictionary = PF.load_from(path)
	_check("取消修改时 AI 代码保留", ai_kept["data"]["main_c_ai"] == ai_code)

	# 确认降级：丢弃 AI 代码回到阶段一
	ui3._downgrade_to_stage1()
	_check("降级后回到阶段一", int(ui3._project["stage"]) == 1)
	_check("降级后退出预览态", not ui3._stage2_preview)
	var down: Dictionary = PF.load_from(path)
	_check("降级已落盘为阶段一", int(down["data"]["stage"]) == 1)
	_check("降级后 AI 代码被清空", str(down["data"]["main_c_ai"]).is_empty())
	# 降级后配置可自由编辑，不再回滚
	ch3.text = "5"
	ch3.text_changed.emit("5")
	_check("降级后配置可编辑", str(ch3.text) == "5")

	# 类型不可转换：工程项目里永远看不到步兵 / 调试页
	var tabs3: Node = ui3.get_node(ui3.P_TAB_CONTAINER)
	_check("工程项目看不到步兵页", tabs3.is_tab_hidden(0))
	_check("工程项目看不到调试页", tabs3.is_tab_hidden(3))
	_check("项目类型未被改动", str(ui3._project["kind"]) == PF.KIND_ENGINEER)

	root.remove_child(ui3)
	ui3.free()
	_app().reset()
	print("")


# ------------------------------------------------------------------ 启动页
## 启动页负责项目管理：新建三种类型、打开、最近列表、损坏文件处理
func _test_launcher() -> void:
	print("--- 启动页 ---")
	var packed: PackedScene = load("res://scenes/launcher.tscn") as PackedScene
	_check("launcher.tscn 可加载", packed != null)
	if packed == null:
		return
	# 最近列表是本机偏好，测试前后都要清干净，别污染真实使用
	var recent_backup: Array = PF.recent_list()
	_clear_recent()

	var lau: Node = packed.instantiate()
	root.add_child(lau)
	await process_frame
	await process_frame
	_check("启动页清空了项目上下文", not _app().has_project())
	_check("最近列表为空时显示占位", lau.get_node(lau.P_RECENT_LIST).get_child_count() == 1)

	# 两个文件对话框的 access 都必须是 ACCESS_FILESYSTEM，否则用户只能把项目
	# 存在程序目录里。这类"默认值恰好不对"的问题看代码看不出来
	# （踩过：SaveDialog 漏写 access，默认 ACCESS_RESOURCES=0，
	#  于是能打开任意位置的项目却只能存回程序目录），必须实例化后检查。
	for dlg_name in ["SaveDialog", "OpenDialog"]:
		var dlg: Node = lau.get_node_or_null(dlg_name)
		_check("%s 存在" % dlg_name, dlg != null)
		if dlg == null:
			continue
		_check("%s 可访问整个文件系统" % dlg_name,
			dlg.access == FileDialog.ACCESS_FILESYSTEM,
			"access=%d 期望 %d" % [dlg.access, FileDialog.ACCESS_FILESYSTEM])
	var save_dlg: Node = lau.get_node_or_null("SaveDialog")
	if save_dlg != null:
		_check("SaveDialog 是保存模式",
			save_dlg.file_mode == FileDialog.FILE_MODE_SAVE_FILE,
			"file_mode=%d 期望 %d" % [save_dlg.file_mode, FileDialog.FILE_MODE_SAVE_FILE])
	var open_dlg: Node = lau.get_node_or_null("OpenDialog")
	if open_dlg != null:
		_check("OpenDialog 是打开单文件模式",
			open_dlg.file_mode == FileDialog.FILE_MODE_OPEN_FILE,
			"file_mode=%d 期望 %d" % [open_dlg.file_mode, FileDialog.FILE_MODE_OPEN_FILE])

	# 三种类型各新建一个
	var paths: Dictionary = {}
	for kind in PF.KINDS:
		var path: String = "%s/launcher_%s.%s" % [TMP_DIR, kind, PF.EXT]
		paths[kind] = path
		var res: Dictionary = PF.create_new(path, kind)
		_check("启动页新建%s落盘" % PF.kind_label(kind), res["ok"], str(res["err"]))
		var back: Dictionary = PF.load_from(path)
		_check("新建的%s类型正确" % PF.kind_label(kind),
			back["ok"] and str(back["data"]["kind"]) == kind)
		_check("新建的%s是阶段一" % PF.kind_label(kind),
			back["ok"] and int(back["data"]["stage"]) == 1)
		PF.recent_add(path)

	lau._rebuild_recent_list()
	var rows: int = lau.get_node(lau.P_RECENT_LIST).get_child_count()
	_check("最近列表列出 3 个项目", rows == 3, "实际 %d 行" % rows)
	# 最近打开是「最新在前」
	_check("最近列表最新在前", str(PF.recent_list()[0]) == str(paths[PF.KIND_DEBUG]))
	# 重复添加同一个项目不该产生重复行
	PF.recent_add(str(paths[PF.KIND_INFANTRY]))
	_check("重复添加不产生重复项", PF.recent_list().size() == 3)
	_check("重复添加会提到首位",
		str(PF.recent_list()[0]) == str(paths[PF.KIND_INFANTRY]))
	# 移除
	PF.recent_remove(str(paths[PF.KIND_INFANTRY]))
	_check("移除后只剩 2 个", PF.recent_list().size() == 2)
	# 文件被删掉的条目自动过滤
	DirAccess.open(TMP_DIR).remove(str(paths[PF.KIND_DEBUG]).get_file())
	_check("文件已删的条目被过滤", PF.recent_list().size() == 1)

	# 打开损坏文件：不进主界面，报错并从最近列表摘掉
	var bad: String = TMP_DIR + "/launcher_bad." + PF.EXT
	var bf: FileAccess = FileAccess.open(bad, FileAccess.WRITE)
	bf.store_string("坏文件")
	bf.close()
	PF.recent_add(bad)
	lau._open_project(bad)
	_check("损坏项目不写入上下文", not _app().has_project())
	_check("损坏项目状态栏有提示",
		not str(lau.get_node(lau.P_STATUS).text).is_empty())
	_check("损坏项目被移出最近列表", not bad in PF.recent_list())

	# 正常进入：写好上下文（不真的切场景，只验证上下文）
	var eng_path: String = str(paths[PF.KIND_ENGINEER])
	var info: Dictionary = PF.load_from(eng_path)
	lau._enter_project(eng_path, info["data"], "")
	_check("进入项目后 project_path 正确", _app().project_path == eng_path)
	_check("进入项目后 kind 正确", _app().project_kind == PF.KIND_ENGINEER)
	_check("进入项目后 source_tab 是工程默认页",
		_app().source_tab == PF.kind_default_tab(PF.KIND_ENGINEER))
	_check("进入项目后 project_dst 指向工程模板",
		_app().project_dst == _app().project_dst_for_kind(PF.KIND_ENGINEER))
	_check("进入项目会记进最近列表", eng_path in PF.recent_list())

	if lau.is_inside_tree():
		root.remove_child(lau)
	lau.free()

	# 主界面无项目上下文时保持自由编辑（不被启动页的引入锁死）
	_app().reset()
	var ui_packed: PackedScene = load("res://scenes/ui.tscn") as PackedScene
	var ui: Node = ui_packed.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	var tabs: Node = ui.get_node(ui.P_TAB_CONTAINER)
	var any_hidden: bool = false
	for i in range(tabs.get_tab_count()):
		if tabs.is_tab_hidden(i):
			any_hidden = true
	_check("直跑主界面时 Tab 全可见", not any_hidden)
	_check("直跑主界面时配置区可编辑", ui.get_node(ui.P_CHANNEL).editable)
	_check("直跑主界面时编译按钮可用", not ui.get_node(ui.P_BUILD_BTN).disabled)
	root.remove_child(ui)
	ui.free()

	_clear_recent()
	for p in recent_backup:
		PF.recent_add(str(p))
	_app().reset()
	print("")


func _clear_recent() -> void:
	for p in PF.recent_list():
		PF.recent_remove(str(p))


## 按标题找运行时 add_child 上去的对话框 / 门控页
func _find_dialog(node: Node, title: String) -> Node:
	for child in node.get_children():
		if child is AcceptDialog and child.title == title:
			return child
		if child is Control and child.has_method("configure"):
			var label: Node = child.get_node_or_null("VBoxContainer/HBoxContainer/Label")
			if label is Label and label.text == title:
				return child
	return null


func _count_dialogs(node: Node) -> int:
	var n: int = 0
	for child in node.get_children():
		if child is AcceptDialog:
			n += 1
		elif child is Control and child.has_method("configure"):
			n += 1
	return n


## 找出第一处不一致，方便定位
func _diff_hint(want: Dictionary, got: Dictionary) -> String:
	for key in want.keys():
		if not got.has(key):
			return "缺 key: %s" % key
		if got[key] != want[key]:
			return "%s: 期望 %s 实际 %s" % [key, str(want[key]), str(got[key])]
	for key in got.keys():
		if not want.has(key):
			return "多出 key: %s" % key
	return ""

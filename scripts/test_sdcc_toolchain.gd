extends SceneTree

const TC = preload("res://scripts/toolchain.gd")
const SDCC = preload("res://scripts/sdcc_toolchain.gd")

var _fail := 0


func _check(label: String, condition: bool) -> void:
	if condition:
		print("[PASS] ", label)
	else:
		print("[FAIL] ", label)
		_fail += 1


func _initialize() -> void:
	var tc = TC.new()
	var setting_abs := ProjectSettings.globalize_path(TC.COMPILER_SETTINGS_PATH)
	if FileAccess.file_exists(setting_abs):
		DirAccess.remove_absolute(setting_abs)
	_check("首次默认 SDCC", tc.get_selected_compiler() == TC.COMPILER_SDCC)
	_check("保存 Keil 选择", tc.set_selected_compiler(TC.COMPILER_KEIL))
	_check("读取 Keil 选择", TC.new().get_selected_compiler() == TC.COMPILER_KEIL)
	var broken := FileAccess.open(setting_abs, FileAccess.WRITE)
	broken.store_string("{broken")
	broken.close()
	_check("损坏配置回退 SDCC", tc.get_selected_compiler() == TC.COMPILER_SDCC)
	DirAccess.remove_absolute(setting_abs)

	var sdcc = SDCC.new()
	var manifest := sdcc.load_manifest()
	_check("构建清单可读取", not manifest.is_empty())
	_check("步兵映射", sdcc.project_for_kind("infantry") == "ROBOMASTER_INFANTRY")
	_check("工程映射", sdcc.project_for_kind("engineer") == "ROBOMASTER_ENGINEER")
	_check("调试映射", sdcc.project_for_kind("debug") == "TEST")
	_check("音乐映射", sdcc.project_for_kind("music") == "BUZZER_MUSIC_GENERATED")
	var top_panel: Node = load("res://scenes/top_panel.tscn").instantiate()
	var top_selector: OptionButton = top_panel.get_node("BuildMode")
	_check("主界面顶部编译器下拉可见", top_selector.visible)
	_check("主界面默认显示 SDCC", top_selector.selected == 0
		and top_selector.get_item_text(0) == "SDCC 编译"
		and top_selector.get_item_text(1) == "Keil 编译")
	top_panel.free()
	var code_edit: Node = load("res://scenes/code_edit.tscn").instantiate()
	var edit_selector: OptionButton = code_edit.get_node("VBoxContainer/TopPanel/BuildMode")
	_check("AI 编辑界面与主界面下拉项一致", edit_selector.visible
		and edit_selector.get_item_text(0) == "SDCC 编译"
		and edit_selector.get_item_text(1) == "Keil 编译")
	code_edit.free()
	for kind in ["infantry", "engineer", "debug", "music"]:
		var project := sdcc.project_for_kind(kind)
		var source_info := sdcc._project_sources(manifest, project)
		_check("%s 源码清单有效" % kind, bool(source_info.get("ok", false)))
		if bool(source_info.get("ok", false)):
			for source in source_info.sources:
				_check("源码存在 %s" % source,
					FileAccess.file_exists("res://stc32g_sdcc/" + str(source)))
	print("失败数: ", _fail)
	quit(_fail)

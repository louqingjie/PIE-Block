extends SceneTree

## 设置页“自动查找”按钮及后台扫描集成测试。

const TC = preload("res://scripts/toolchain.gd")

var _fail: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	print("=== 设置页 Keil 自动查找测试 ===")
	var tc = TC.new()
	var settings_abs: String = ProjectSettings.globalize_path(TC.KEIL_SETTINGS_PATH)
	var state_abs: String = ProjectSettings.globalize_path(TC.KEIL_SCAN_STATE_PATH)
	var settings_exists: bool = FileAccess.file_exists(settings_abs)
	var settings_backup: String = FileAccess.get_file_as_string(settings_abs) \
		if settings_exists else ""
	var state_exists: bool = FileAccess.file_exists(state_abs)
	var state_backup: String = FileAccess.get_file_as_string(state_abs) \
		if state_exists else ""
	var env_backup: String = OS.get_environment(TC.KEIL_ENV_VAR)
	var fake_root: String = ProjectSettings.globalize_path("user://test_setting_panel_keil")
	var fake_keil: String = fake_root.path_join("Keil_v5")
	DirAccess.make_dir_recursive_absolute(fake_keil.path_join("UV4"))
	DirAccess.make_dir_recursive_absolute(fake_keil.path_join("C251").path_join("BIN"))
	_write_text(fake_keil.path_join("UV4/uVision.com"), "console app")
	_write_text(fake_keil.path_join("C251/BIN/C251.EXE"), "c251")
	_write_text(fake_keil.path_join("TOOLS.INI"), "[C251]\n")

	OS.set_environment(TC.KEIL_ENV_VAR, "")
	tc.set_configured_keil_path("")
	var packed: PackedScene = load("res://scenes/setting_panel.tscn") as PackedScene
	_check("设置面板场景可加载", packed != null)
	if packed == null:
		_cleanup(settings_abs, settings_exists, settings_backup, state_abs, state_exists,
			state_backup, env_backup, fake_root)
		quit(1)
		return
	var panel: Node = packed.instantiate()
	panel.configure(tc)
	root.add_child(panel)
	await process_frame
	var scan_btn: Button = panel.get_node(panel.P_KEIL_SCAN)
	_check("设置页存在自动查找按钮", scan_btn.text == "自动查找")
	_check("自动查找按钮已接线", scan_btn.pressed.is_connected(panel._on_scan_pressed))

	panel._start_keil_scan(PackedStringArray([fake_root]))
	_check("扫描期间按钮禁用", scan_btn.disabled)
	for _i in range(20):
		await process_frame
		if not panel._scan_active:
			break
	_check("设置页后台扫描已完成", not panel._scan_active)
	_check("设置页自动回填 Keil 路径", tc.get_configured_keil_path() == fake_keil)
	_check("设置页自动保存 Keil 路径", str(panel.get_node(panel.P_KEIL_EDIT).text) == fake_keil)
	_check("扫描完成后按钮恢复可用", not scan_btn.disabled)
	_check("设置页显示扫描结果", str(panel.get_node(panel.P_KEIL_STATUS).text).contains("已找到并保存"))

	panel.queue_free()
	await process_frame
	_cleanup(settings_abs, settings_exists, settings_backup, state_abs, state_exists,
		state_backup, env_backup, fake_root)
	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _cleanup(
	settings_abs: String, settings_exists: bool, settings_backup: String,
	state_abs: String, state_exists: bool, state_backup: String,
	env_backup: String, fake_root: String) -> void:
	_remove_tree(fake_root)
	_restore_file(settings_abs, settings_exists, settings_backup)
	_restore_file(state_abs, state_exists, state_backup)
	OS.set_environment(TC.KEIL_ENV_VAR, env_backup)


func _write_text(path: String, content: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()


func _restore_file(path: String, existed: bool, content: String) -> void:
	if existed:
		_write_text(path, content)
	else:
		DirAccess.remove_absolute(path)


func _remove_tree(abs_path: String) -> void:
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if not entry.begins_with("."):
			var item: String = abs_path.path_join(entry)
			if da.current_is_dir():
				_remove_tree(item)
			else:
				da.remove(entry)
		entry = da.get_next()
	da.list_dir_end()
	var pda: DirAccess = DirAccess.open(abs_path.get_base_dir())
	if pda:
		pda.remove(abs_path.get_file())

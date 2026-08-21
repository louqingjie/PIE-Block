extends SceneTree

## Keil 首次启动后台探测集成测试（只扫描 user:// 下的临时伪造目录）。

const TC = preload("res://scripts/toolchain.gd")

var _fail: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	print("=== Keil 首次启动后台探测测试 ===")
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
	var fake_root: String = ProjectSettings.globalize_path("user://test_keil_autoscan")
	var fake_keil: String = fake_root.path_join("Keil_v5")
	DirAccess.make_dir_recursive_absolute(fake_keil.path_join("UV4"))
	DirAccess.make_dir_recursive_absolute(fake_keil.path_join("C251").path_join("BIN"))
	_write_text(fake_keil.path_join("UV4/uVision.com"), "console app")
	_write_text(fake_keil.path_join("C251/BIN/C251.EXE"), "c251")
	_write_text(fake_keil.path_join("TOOLS.INI"), "[C251]\n")

	# 先让启动页跳过真实自动扫描，再手动启动同一个后台 worker，注入临时根目录。
	OS.set_environment(TC.KEIL_ENV_VAR, "")
	tc.set_configured_keil_path("")
	tc.mark_keil_auto_scan_completed()
	var packed: PackedScene = load("res://scenes/launcher.tscn") as PackedScene
	var launcher: Node = packed.instantiate()
	root.add_child(launcher)
	await process_frame

	DirAccess.remove_absolute(state_abs)
	launcher._keil_scan_active = true
	launcher._keil_scan_thread = Thread.new()
	var start_error: Error = launcher._keil_scan_thread.start(
		launcher._scan_keil_worker.bind(PackedStringArray([fake_root])))
	_check("后台 Keil 探测线程启动成功", start_error == OK)
	for _i in range(20):
		await process_frame
		if not launcher._keil_scan_active:
			break
	_check("后台探测线程已完成", not launcher._keil_scan_active)
	_check("后台探测自动保存 Keil 路径", tc.get_configured_keil_path() == fake_keil)
	_check("后台探测状态栏提示成功", str(launcher.get_node(launcher.P_STATUS).text).contains("已自动找到 Keil"))

	if launcher.is_inside_tree():
		launcher.queue_free()
		await process_frame
	_remove_tree(fake_root)
	_restore_file(settings_abs, settings_exists, settings_backup)
	_restore_file(state_abs, state_exists, state_backup)
	OS.set_environment(TC.KEIL_ENV_VAR, env_backup)
	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


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
	var parent: String = abs_path.get_base_dir()
	var name: String = abs_path.get_file()
	var pda: DirAccess = DirAccess.open(parent)
	if pda:
		pda.remove(name)

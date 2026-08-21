extends SceneTree

## Keil 目录设置/校验单测（headless）。
## 运行：godot --headless --path . --script scripts/test_keil_settings.gd
##
## 覆盖：
##   - 未配置状态（ensure_external_keil_ready 报「未指定」）
##   - validate_keil_dir 正例（标准布局 UV4 + C251 + TOOLS.INI）
##   - validate_keil_dir 负例（缺 C251 / 目录不存在）
##   - set/get/clear 配置读写
##   - 配置有效 -> resolve_keil_root / find_uv4
##   - 配置失效 -> ensure_external_keil_ready 报「失效」，resolve_keil_root 为空（无内置回退）
##   - 环境变量 PIEBLOCK_KEIL 覆盖（有效 / 失效）
##   - build_project 未配置时返回失败并提示配置方式

const TC = preload("res://scripts/toolchain.gd")

var _fail: int = 0


func _check(label: String, ok: bool) -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s" % label)
		_fail += 1


func _initialize() -> void:
	print("=== Keil 目录设置测试 ===")
	var tc = TC.new()
	var scan_state_abs: String = ProjectSettings.globalize_path(TC.KEIL_SCAN_STATE_PATH)
	var scan_state_backup_exists: bool = FileAccess.file_exists(scan_state_abs)
	var scan_state_backup: String = FileAccess.get_file_as_string(scan_state_abs) \
		if scan_state_backup_exists else ""
	if scan_state_backup_exists:
		DirAccess.remove_absolute(scan_state_abs)
	# 从干净状态开始（清掉环境变量与配置）
	OS.set_environment(TC.KEIL_ENV_VAR, "")
	tc.set_configured_keil_path("")

	# 1) 未配置
	_check("未配置时 get_configured_keil_path 为空", tc.get_configured_keil_path().is_empty())
	var ready0: Dictionary = tc.ensure_external_keil_ready()
	_check("未配置时 ensure_external_keil_ready 报未指定",
		not ready0.ok and str(ready0.reason).contains("未指定"))
	_check("未配置时 resolve_keil_root 为空", tc.resolve_keil_root().is_empty())

	# 2) 造一个假 Keil 目录（标准布局）
	var fake_root: String = ProjectSettings.globalize_path("user://test_fake_keil")
	DirAccess.make_dir_recursive_absolute(fake_root.path_join("UV4"))
	DirAccess.make_dir_recursive_absolute(fake_root.path_join("C251").path_join("BIN"))
	_write_text(fake_root.path_join("UV4/uVision.com"), "console app")
	_write_text(fake_root.path_join("C251/BIN/C251.EXE"), "c251")
	_write_text(fake_root.path_join("TOOLS.INI"), "[C251]\nPATH=\"C:\\Keil_v5\\C251\\\"\n")

	# 3) validate 正例
	var v_ok: Dictionary = tc.validate_keil_dir(fake_root)
	_check("标准布局 validate_keil_dir 通过", v_ok.ok)
	_check("validate 返回 uv4 路径", FileAccess.file_exists(str(v_ok.uv4)))
	_check("validate 返回 c251 路径", FileAccess.file_exists(str(v_ok.c251)))

	# 4) validate 负例：缺 C251
	var no_c251: String = fake_root.path_join("no_c251")
	DirAccess.make_dir_recursive_absolute(no_c251.path_join("UV4"))
	_write_text(no_c251.path_join("UV4/uVision.com"), "x")
	var v_bad: Dictionary = tc.validate_keil_dir(no_c251)
	_check("缺少 C251 时校验失败", not v_bad.ok and str(v_bad.reason).contains("C251"))

	# 5) validate 负例：目录不存在
	var v_missing: Dictionary = tc.validate_keil_dir("C:/no/such/keil")
	_check("目录不存在时校验失败", not v_missing.ok)

	# 6) set/get/clear
	_check("set_configured_keil_path 成功", tc.set_configured_keil_path(fake_root))
	_check("get_configured_keil_path 回读一致", tc.get_configured_keil_path() == fake_root)
	var ready1: Dictionary = tc.ensure_external_keil_ready()
	_check("配置有效时 ensure_external_keil_ready 通过", ready1.ok)
	_check("配置有效时 resolve_keil_root 返回外部根", tc.resolve_keil_root() == fake_root)
	_check("配置有效时 find_uv4 找到 uVision.com",
		tc.find_uv4() == fake_root.path_join("UV4/uVision.com"))

	# 7) 配置失效（路径被删 / 指向不存在目录）
	_check("清除配置成功", tc.set_configured_keil_path("C:/no/such/keil"))
	var ready2: Dictionary = tc.ensure_external_keil_ready()
	_check("配置失效时 ensure_external_keil_ready 报失效",
		not ready2.ok and str(ready2.reason).contains("失效"))
	_check("配置失效时 resolve_keil_root 为空（无内置回退）", tc.resolve_keil_root().is_empty())

	# 8) 环境变量覆盖
	tc.set_configured_keil_path("")
	OS.set_environment(TC.KEIL_ENV_VAR, fake_root)
	var ready3: Dictionary = tc.ensure_external_keil_ready()
	_check("环境变量指向有效目录时通过", ready3.ok)
	OS.set_environment(TC.KEIL_ENV_VAR, "C:/no/such/keil")
	var ready4: Dictionary = tc.ensure_external_keil_ready()
	_check("环境变量失效时报失效", not ready4.ok and str(ready4.reason).contains("失效"))
	OS.set_environment(TC.KEIL_ENV_VAR, "")

	# 9) 自动扫描：注入临时根目录，不触碰真实磁盘。
	var custom_root: String = fake_root.path_join("custom_install")
	DirAccess.make_dir_recursive_absolute(custom_root.path_join("UV4"))
	DirAccess.make_dir_recursive_absolute(custom_root.path_join("C251").path_join("BIN"))
	_write_text(custom_root.path_join("UV4/UV4.exe"), "gui app")
	_write_text(custom_root.path_join("C251/BIN/C251.EXE"), "c251")
	var scan_results: Array[String] = tc.scan_keil_installations(
		PackedStringArray([fake_root.get_base_dir()]))
	_check("自动扫描识别有效 Keil 安装", fake_root in scan_results and custom_root in scan_results)
	_check("自动扫描排除无 C251 的目录", no_c251 not in scan_results)
	_check("多个安装优先选择标准 uVision.com 布局",
		tc.choose_best_keil_path(scan_results) == fake_root)
	_check("首次自动扫描状态初始为未完成", not tc.is_keil_auto_scan_completed())
	tc.set_configured_keil_path(fake_root)
	_check("已有用户配置时不触发自动扫描", not tc.should_auto_scan_keil())
	tc.set_configured_keil_path("")
	OS.set_environment(TC.KEIL_ENV_VAR, fake_root)
	_check("已有环境变量时不触发自动扫描", not tc.should_auto_scan_keil())
	OS.set_environment(TC.KEIL_ENV_VAR, "")
	_check("记录首次自动扫描状态成功", tc.mark_keil_auto_scan_completed())
	_check("记录后不再触发自动扫描", not tc.should_auto_scan_keil())

	# 10) build_project 未配置时报错并提示配置方式
	tc.set_configured_keil_path("")
	var bres: Dictionary = tc.build_project("user://stc32g/Projects/ROBOMASTER_INFANTRY")
	_check("build_project 未配置时返回失败", not bres.ok)
	_check("build_project 报错提示配置 Keil 目录", str(bres.log).contains("Keil 目录"))

	# 11) 清理测试目录与配置
	_remove_tree(fake_root)
	_remove_tree(no_c251)
	tc.set_configured_keil_path("")
	if scan_state_backup_exists:
		_write_text(scan_state_abs, scan_state_backup)
	else:
		DirAccess.remove_absolute(scan_state_abs)

	print("=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)


func _write_text(path: String, content: String) -> void:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(content)
		f.close()


func _remove_tree(abs_path: String) -> void:
	var da: DirAccess = DirAccess.open(abs_path)
	if da == null:
		return
	da.list_dir_begin()
	var entry: String = da.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = da.get_next()
			continue
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

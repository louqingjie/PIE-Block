extends SceneTree

## 验证 AI 编辑器与工作区 main.c 的内容同步。
## 运行：godot --headless --path . --script scripts/test_code_edit_sync.gd

const TC = preload("res://scripts/toolchain.gd")
const PF = preload("res://scripts/project_file.gd")

const ROOT_DIR: String = "user://_test_code_edit_sync"
const PROJECT_PATH: String = ROOT_DIR + "/同步测试.pieproj"

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _initialize() -> void:
	await process_frame
	print("=== AI 编辑器 main.c 同步测试 ===\n")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(
		ROOT_DIR + "/USER/src"))
	var created: Dictionary = PF.create_new(PROJECT_PATH, PF.KIND_INFANTRY)
	_check("创建测试工程", bool(created.get("ok", false)))
	if not bool(created.get("ok", false)):
		_finish()
		return
	var app: Node = root.get_node_or_null("AppState")
	_check("AppState 自动加载可用", app != null)
	if app == null:
		_cleanup()
		_finish()
		return
	app.project_path = PROJECT_PATH
	app.stage = 2

	var tc = TC.new()
	var base_code: String = "base code\n"
	_check("写入初始 main.c", tc.write_main_c(ROOT_DIR, base_code))
	var packed: PackedScene = load("res://scenes/code_edit.tscn") as PackedScene
	_check("code_edit 场景可加载", packed != null)
	if packed == null:
		_finish()
		return

	var editor: Node = packed.instantiate()
	editor._project_dst = ROOT_DIR
	editor._tc = tc
	editor._load_from_disk()
	editor._connect_signals()
	var code_edit: CodeEdit = editor.get_node(editor.P_CODE_EDIT) as CodeEdit
	_check("编辑器初始内容来自磁盘", code_edit != null and code_edit.text == base_code)
	_check("初始内容签名已记录", not str(editor._last_disk_signature).is_empty())

	# 快速连续写入不依赖文件 mtime 是否跨秒。
	var ai_code: String = "AI changed in the same second\n"
	var before_signature: String = tc.main_c_signature(ROOT_DIR)
	_check("AI 写入新 main.c", tc.write_main_c(ROOT_DIR, ai_code))
	var after_signature: String = tc.main_c_signature(ROOT_DIR)
	_check("同一秒内容变化产生不同签名", before_signature != after_signature)
	_check("检测到 AI 修改并刷新编辑器", editor._reload_if_changed()
		and code_edit.text == ai_code)

	# 手工修改在自动保存入口中同时更新工作区与工程文件。
	var manual_code: String = ai_code + "manual edit\n"
	code_edit.text = manual_code
	_check("自动保存定时器采用 1 秒延迟", editor._autosave_timer != null
		and editor._autosave_timer.one_shot
		and is_equal_approx(editor._autosave_timer.wait_time, 1.0))
	editor._dirty = true
	editor._on_autosave_timeout()
	_check("自动保存更新 main.c", tc.read_main_c(ROOT_DIR) == manual_code)
	var saved_project: Dictionary = PF.load_from(PROJECT_PATH)
	_check("自动保存更新工程 main_c_ai",
		bool(saved_project.get("ok", false))
		and str(saved_project["data"].get("main_c_ai", "")) == manual_code)
	_check("自动保存后编辑器不再 dirty", not bool(editor._dirty))

	# 外部 AI 修改与未保存手工修改同时存在时，不得静默覆盖。
	var unsaved_code: String = manual_code + "unsaved\n"
	code_edit.text = unsaved_code
	editor._dirty = true
	var conflict_ai_code: String = "AI conflict version\n"
	_check("写入冲突场景的 AI 内容", tc.write_main_c(ROOT_DIR, conflict_ai_code))
	editor._on_reload_tick()
	_check("冲突时弹出处理对话框", is_instance_valid(editor._conflict_dialog))
	_check("冲突时磁盘内容未被静默覆盖",
		tc.read_main_c(ROOT_DIR) == conflict_ai_code)

	# 选择载入 AI 修改。
	editor._resolve_conflict_load()
	_check("载入 AI 修改后编辑器内容正确", code_edit.text == conflict_ai_code)
	_check("载入 AI 修改后清除 dirty", not bool(editor._dirty))

	# 再验证选择保留编辑器修改会显式覆盖磁盘。
	var keep_code: String = "keep editor version\n"
	code_edit.text = keep_code
	editor._dirty = true
	_check("再次写入 AI 冲突内容", tc.write_main_c(ROOT_DIR, "AI overwritten version\n"))
	editor._on_reload_tick()
	_check("第二次冲突对话框可用", is_instance_valid(editor._conflict_dialog))
	editor._resolve_conflict_keep()
	_check("保留编辑器修改后覆盖磁盘", tc.read_main_c(ROOT_DIR) == keep_code)
	_check("保留编辑器修改后清除 dirty", not bool(editor._dirty))

	editor.free()
	app.reset()
	_cleanup()
	_finish()


func _cleanup() -> void:
	var abs_root: String = ProjectSettings.globalize_path(ROOT_DIR)
	if not DirAccess.dir_exists_absolute(abs_root):
		return
	_remove_tree(abs_root)


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	for child_dir in dir.get_directories():
		_remove_tree(path.path_join(child_dir))
	for file_name in dir.get_files():
		dir.remove(file_name)
	dir = null
	DirAccess.remove_absolute(path)


func _finish() -> void:
	print("\n=== 结果：%s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)

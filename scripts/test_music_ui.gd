extends SceneTree

## 音乐页面、项目类型可见性与音乐生成器选择测试。

const PF = preload("res://scripts/project_file.gd")
const MusicCodegen = preload("res://scripts/codegen/codegen_music.gd")

var _fail: int = 0


func _check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		print("[✓ PASS] %s" % label)
	else:
		print("[✗ FAIL] %s%s" % [label, ("  " + detail) if detail != "" else ""])
		_fail += 1


func _initialize() -> void:
	print("=== 音乐 UI 测试 ===\n")
	var music_scene: PackedScene = load("res://scenes/music.tscn") as PackedScene
	_check("音乐页面场景可加载", music_scene != null)
	if music_scene == null:
		quit(1)
		return
	var page: Node = music_scene.instantiate()
	root.add_child(page)
	await process_frame
	_check("音乐页包含 MIDI 打开按钮", page.get_node_or_null("Open") is Button)
	_check("音乐页包含多轨复选列表", page.get_node_or_null("TrackScroll/TrackList") is VBoxContainer)
	_check("音乐页包含伪复音开关", page.get_node_or_null("Polyphonic") is CheckButton)
	_check("音乐页使用原生 MIDI 文件对话框",
		page.get_node_or_null("MidiDialog") is FileDialog
		and page.get_node("MidiDialog").use_native_dialog)
	var selected: Dictionary = {
		"source_name": "旋律.mid",
		"polyphonic": true,
		"track_index": 0,
		"track_indices": [0, 1],
		"track_name": "主旋律",
		"track_names": ["主旋律", "和弦"],
		"track_count": 2,
		"duration_ms": 900,
		"segments": [
			{"notes": [64, 60], "duration_ms": 500},
			{"notes": [], "duration_ms": 100},
			{"notes": [64], "duration_ms": 300},
		],
	}
	page.set_music_data(selected)
	_check("音乐页可回填已保存解析结果", page.get_music_data() == selected)
	_check("音乐页无解析错误", str(page.get_parse_error()).is_empty())
	_check("音乐页显示轨道摘要", str(page.get_node("TrackScroll/TrackList").get_child(0).text).contains("主旋律")
		and str(page.get_node("Status").text).contains("四声部伪复音"))
	var second_track: CheckButton = page.get_node("TrackScroll/TrackList").get_child(1) as CheckButton
	second_track.set_pressed_no_signal(false)
	second_track.toggled.emit(false)
	await process_frame
	_check("轨道切换回调结束后可安全重建列表",
		page.get_node("TrackScroll/TrackList").get_child_count() == 2)
	page.set_music_data(selected)
	page._on_polyphonic_toggled(false)
	_check("关闭伪复音后只保留首条轨道", not bool(page.get_music_data().get("polyphonic", true))
		and page.get_music_data().get("track_indices", []) == [0])
	root.remove_child(page)
	page.free()

	var ui_scene: PackedScene = load("res://scenes/ui.tscn") as PackedScene
	var ui: Node = ui_scene.instantiate()
	root.add_child(ui)
	await process_frame
	await process_frame
	ui._apply_kind_visibility(PF.KIND_MUSIC, 3)
	var edit_zone: Node = ui.get_node(ui.P_EDIT_ZONE)
	_check("音乐项目只显示音乐页", edit_zone.get_node("Music").visible
		and not edit_zone.get_node("Infantry").visible
		and not edit_zone.get_node("Engineer").visible
		and not edit_zone.get_node("Debug").visible)
	_check("音乐项目隐藏无关首行配置", not ui.get_node(ui.P_FIRST_ROW).visible)
	_check("音乐项目逻辑页为 3", ui._current_tab() == 3)
	_check("音乐项目选择音乐代码生成器", ui._get_current_codegen() is MusicCodegen)
	ui._set_music_data(selected)
	ui._run_check()
	_check("音乐数据通过主界面检查", ui._last_issues.is_empty(), JSON.stringify(ui._last_issues))
	root.remove_child(ui)
	ui.free()

	print("\n=== 结果: %s ===" % ("全部通过 ✓" if _fail == 0 else "%d 项失败 ✗" % _fail))
	quit(0 if _fail == 0 else 1)
